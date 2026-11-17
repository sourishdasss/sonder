import Foundation
import SwiftUI

/// Central state for the signed-in experience: rated cities, taste profile, feed and photo pins.
@MainActor
final class AppStore: ObservableObject {
    enum Tab: String, CaseIterable, Hashable {
        case feed, map, lists, profile
    }

    /// Cities needed before a travel personality can be inferred.
    static let profileThreshold = 3

    // MARK: Published state

    @Published var selectedTab: Tab = .feed
    @Published private(set) var ratedCities: [RatedCity] = []
    @Published private(set) var travelProfile: TravelProfile = .placeholder
    @Published private(set) var feedItems: [FeedItem] = []
    @Published private(set) var feedScope: FeedScope = .everyone
    @Published private(set) var photoPins: [PhotoPin] = []

    /// True once cities have been loaded (from cache or network) at least once.
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoadingFeed = false
    @Published private(set) var isRefreshingProfile = false
    /// Set when the first load fails and there is nothing cached to show.
    @Published private(set) var loadError: String?

    // MARK: Presentation

    /// Presents the city search sheet.
    @Published var isAddingCity = false
    /// Presents the rating flow for an existing city.
    @Published var editingCity: RatedCity?

    // MARK: Dependencies

    private let backend: Backend
    private let claude: ClaudeService?
    private let cache: LocalCache?
    private let toaster: Toaster
    /// Finds a photo for a city that has none (nil in tests, so they never touch the network).
    private let photoResolver: ((CityData) async -> String?)?
    private var userId: UUID?
    private var profileTask: Task<Void, Never>?

    init(
        backend: Backend,
        claude: ClaudeService? = nil,
        cache: LocalCache? = nil,
        toaster: Toaster? = nil,
        photoResolver: ((CityData) async -> String?)? = nil
    ) {
        self.backend = backend
        self.claude = claude
        self.cache = cache
        self.toaster = toaster ?? .shared
        self.photoResolver = photoResolver
    }

    /// Whether summaries and profiles are written by Claude (vs. on-device).
    var isAIEnabled: Bool { claude?.isAvailable == true }

    // MARK: - Derived values

    var totalPlacesRated: Int {
        ratedCities.reduce(0) { $0 + $1.placeCount }
    }

    var countriesVisited: Int {
        Set(ratedCities.map { $0.cityData.country.lowercased() }.filter { !$0.isEmpty }).count
    }

    var favouriteCategory: AttractionCategory? {
        ScoringEngine.favouriteCategory(for: ratedCities)
    }

    var averageCityScore: Double? {
        guard !ratedCities.isEmpty else { return nil }
        return ratedCities.map(\.cumulativeScore).reduce(0, +) / Double(ratedCities.count)
    }

    /// Average place score per category, best first (excludes General Appeal).
    var tasteBreakdown: [(category: AttractionCategory, score: Double)] {
        ScoringEngine.categoryAverages(for: ratedCities)
            .filter { $0.key != .general }
            .map { (category: $0.key, score: $0.value) }
            .sorted { AttractionCategory.ranksAbove($0.category, $0.score, $1.category, $1.score) }
    }

    var citiesUntilProfile: Int {
        max(0, Self.profileThreshold - ratedCities.count)
    }

    var trendingCities: [TrendingCity] {
        TrendingCity.rank(feedItems)
    }

    func city(id: UUID) -> RatedCity? {
        ratedCities.first { $0.id == id }
    }

    /// The saved rating for the same place, if the user has already logged it.
    func existingCity(matching city: CityData) -> RatedCity? {
        ratedCities.first { $0.cityData.placeKey == city.placeKey }
    }

    /// 1-based position of a city in the user's rankings.
    func rank(of city: RatedCity) -> Int? {
        ratedCities.firstIndex { $0.id == city.id }.map { $0 + 1 }
    }

    // MARK: - Lifecycle

    /// Loads everything for a newly signed-in user: cached data first, then the network.
    func start(userId: UUID) async {
        guard self.userId != userId else { return }
        reset()
        self.userId = userId

        if let cached = cache?.load(userId: userId) {
            ratedCities = Self.sorted(cached.cities)
            travelProfile = cached.travelProfile ?? .placeholder
            hasLoaded = true
        }
        await refreshAll()
    }

    func reset() {
        profileTask?.cancel()
        profileTask = nil
        userId = nil
        ratedCities = []
        travelProfile = .placeholder
        feedItems = []
        feedScope = .everyone
        photoPins = []
        hasLoaded = false
        loadError = nil
        isLoadingFeed = false
        isRefreshingProfile = false
        isAddingCity = false
        editingCity = nil
        selectedTab = .feed
    }

    /// Removes the cached copy of a user's data (on account deletion).
    func clearCache(userId: UUID) {
        cache?.clear(userId: userId)
    }

    /// Reloads cities, profile, feed and pins from the server.
    func refreshAll() async {
        guard userId != nil else { return }
        async let citiesResult = Self.capture { try await self.backend.fetchRatedCities(userId: nil) }
        async let profileResult = Self.capture { try await self.backend.fetchTravelProfile(userId: nil) }
        async let pinsResult = Self.capture { try await self.backend.fetchPhotoPins(userId: nil) }

        switch await citiesResult {
        case .success(let cities):
            ratedCities = Self.sorted(cities)
            hasLoaded = true
            loadError = nil
        case .failure(let error):
            if hasLoaded {
                toaster.error(error)
            } else {
                loadError = ErrorCopy.message(for: error)
            }
        }
        if case .success(let profile) = await profileResult, let profile {
            travelProfile = profile
        }
        // Photo pins are optional; an unconfigured bucket or table shouldn't block the app.
        if case .success(let pins) = await pinsResult {
            photoPins = pins
        }

        persistCache()
        await refreshFeed()

        if ratedCities.count >= Self.profileThreshold, travelProfile.isPlaceholder {
            await refreshTravelProfile()
        }
        await fillMissingPhotos()
    }

    /// Looks up a photo for any city saved without one (for example by the first version of the
    /// app). The result is kept in memory and in the local cache; the saved row is only updated
    /// the next time the user edits that city.
    private func fillMissingPhotos() async {
        guard let photoResolver else { return }
        for city in ratedCities where city.cityData.photoURL.isEmpty {
            guard let url = await photoResolver(city.cityData), !url.isEmpty else { continue }
            if let index = ratedCities.firstIndex(where: { $0.id == city.id }),
               ratedCities[index].cityData.photoURL.isEmpty {
                ratedCities[index].cityData.photoURL = url
            }
        }
        persistCache()
    }

    private static func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }

    private static func sorted(_ cities: [RatedCity]) -> [RatedCity] {
        cities.sorted { lhs, rhs in
            if lhs.cumulativeScore != rhs.cumulativeScore { return lhs.cumulativeScore > rhs.cumulativeScore }
            return lhs.cityData.city < rhs.cityData.city
        }
    }

    private func persistCache() {
        guard let userId, hasLoaded else { return }
        cache?.save(cities: ratedCities, travelProfile: travelProfile, userId: userId)
    }

    // MARK: - Feed

    func setFeedScope(_ scope: FeedScope) async {
        guard scope != feedScope else { return }
        feedScope = scope
        feedItems = []
        await refreshFeed()
    }

    func refreshFeed() async {
        guard userId != nil else { return }
        let scope = feedScope
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            let items = try await backend.fetchFeed(scope: scope, limit: scope == .trending ? 200 : 60)
            // Ignore a response for a scope the user has already navigated away from.
            if scope == feedScope { feedItems = items }
        } catch {
            toaster.error(error)
        }
    }

    // MARK: - Cities

    /// Scores and saves a city visit. Throws when the visit can't be saved, leaving state untouched.
    @discardableResult
    func saveCity(city: CityData, draft: CityRatingDraft, existing: RatedCity? = nil) async throws -> RatedCity {
        guard draft.hasPlaces else {
            throw BackendError.message("Add at least one place you visited.")
        }
        let match = existing ?? existingCity(matching: city)
        let prior = ratedCities.filter { $0.id != match?.id }

        // When re-rating, keep the saved city's identity (exact name, photo, coordinates) so the
        // stored row is updated in place rather than duplicated under a differently-cased name.
        var city = city
        if let saved = match?.cityData {
            city.city = saved.city
            city.country = saved.country
            if city.flag.isEmpty { city.flag = saved.flag }
            if city.photoURL.isEmpty { city.photoURL = saved.photoURL }
            if city.coordinate == nil {
                city.latitude = saved.latitude
                city.longitude = saved.longitude
            }
        }

        var rated = RatedCity.build(
            id: match?.id ?? UUID(),
            city: city,
            draft: draft,
            priorCities: prior,
            createdAt: match?.createdAt ?? Date()
        )

        if let claude, claude.isAvailable {
            let score = ScoringEngine.cityScore(for: draft.entries)
            let cityData = rated.cityData
            // Claude is a nice-to-have: never let it block or fail a save.
            let narrative = await Self.withTimeout(seconds: 25) {
                try await claude.cityNarrative(city: cityData, score: score, priorCities: prior)
            }
            if let narrative {
                rated = rated.with(narrative: narrative)
            }
        }

        try await backend.saveRatedCity(rated)

        ratedCities.removeAll { $0.id == rated.id || $0.cityData.placeKey == rated.cityData.placeKey }
        ratedCities.append(rated)
        ratedCities = Self.sorted(ratedCities)
        hasLoaded = true
        persistCache()

        if match == nil {
            let draftActivity = FeedActivityDraft(
                ratedCityId: rated.id,
                city: rated.cityData.city,
                country: rated.cityData.country,
                cityPhotoURL: rated.cityData.photoURL.isEmpty ? nil : rated.cityData.photoURL,
                score: rated.cumulativeScore,
                review: rated.highlight,
                placeCount: rated.placeCount
            )
            Task {
                // Sharing to the feed is best-effort; the city itself is already saved.
                try? await self.backend.postFeedActivity(draftActivity)
                await self.refreshFeed()
            }
        }
        scheduleProfileRefresh()
        return rated
    }

    func deleteCity(_ city: RatedCity) async {
        let snapshot = ratedCities
        ratedCities.removeAll { $0.id == city.id }
        do {
            try await backend.deleteRatedCity(id: city.id)
            persistCache()
            toaster.show("\(city.cityData.city) removed", style: .success)
            scheduleProfileRefresh()
            await refreshFeed()
        } catch {
            ratedCities = snapshot
            toaster.error(error)
        }
    }

    // MARK: - Travel profile

    private func scheduleProfileRefresh() {
        profileTask?.cancel()
        profileTask = Task { [weak self] in
            await self?.refreshTravelProfile()
        }
    }

    /// Rebuilds the travel personality from the current ratings.
    func refreshTravelProfile() async {
        guard ratedCities.count >= Self.profileThreshold else {
            if !travelProfile.isPlaceholder {
                travelProfile = .placeholder
                persistCache()
            }
            return
        }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        let cities = ratedCities
        var profile = ScoringEngine.travelProfile(from: cities)
        if let claude, claude.isAvailable {
            let generated = await Self.withTimeout(seconds: 40) {
                try await claude.travelProfile(for: cities)
            }
            if let generated { profile = generated }
        }
        guard !Task.isCancelled else { return }

        travelProfile = profile
        persistCache()
        do {
            try await backend.saveTravelProfile(profile)
        } catch {
            // The profile is derived data and will be regenerated; no need to interrupt the user.
        }
    }

    // MARK: - Community places

    /// Places other travellers have added for this city (never throws; suggestions are optional).
    func communityPlaces(for city: CityData) async -> [Attraction] {
        (try? await backend.fetchCityAttractions(city: city.city, country: city.country)) ?? []
    }

    /// Shares a custom place so other travellers see it as a suggestion. Best-effort.
    func shareCustomPlace(_ attraction: Attraction, in city: CityData) async {
        _ = try? await backend.addCityAttraction(
            city: city.city,
            country: city.country,
            name: attraction.name,
            category: attraction.category
        )
    }

    // MARK: - Photo pins

    @discardableResult
    func addPhotoPin(_ draft: PhotoPinDraft) async throws -> PhotoPin {
        let pin = try await backend.addPhotoPin(draft)
        photoPins.insert(pin, at: 0)
        return pin
    }

    func deletePhotoPin(_ pin: PhotoPin) async {
        let snapshot = photoPins
        photoPins.removeAll { $0.id == pin.id }
        do {
            try await backend.deletePhotoPin(pin)
        } catch {
            photoPins = snapshot
            toaster.error(error)
        }
    }

    // MARK: - Helpers

    /// Runs `work`, returning nil if it throws or takes longer than `seconds`.
    static func withTimeout<T: Sendable>(
        seconds: Double,
        _ work: @escaping @Sendable () async throws -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
