import Foundation

/// A complete in-process backend. Used for the debug demo mode, SwiftUI previews and unit tests —
/// nothing here touches the network or disk (other than temp files for demo photo pins).
@MainActor
final class InMemoryBackend: Backend {
    struct Account {
        var user: UserSummary
        var email: String
        var password: String
    }

    private(set) var accounts: [UUID: Account] = [:]
    private(set) var sessionUserId: UUID?
    private(set) var citiesByUser: [UUID: [RatedCity]] = [:]
    private(set) var profilesByUser: [UUID: TravelProfile] = [:]
    private(set) var feed: [FeedItem] = []
    private(set) var follows: Set<FollowEdge> = []
    private(set) var pinsByUser: [UUID: [PhotoPin]] = [:]
    private(set) var communityPlaces: [String: [Attraction]] = [:]

    /// When set, the next mutating call throws this error (for testing failure paths).
    var failNextWrite: Error?

    private var authContinuations: [UUID: AsyncStream<SessionUser?>.Continuation] = [:]

    struct FollowEdge: Hashable {
        let follower: UUID
        let following: UUID
    }

    init() {}

    var isConfigured: Bool { true }

    // MARK: - Seeding helpers

    @discardableResult
    func addAccount(name: String, email: String, password: String = "password", id: UUID = UUID()) -> UserSummary {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        let user = UserSummary(
            id: id,
            displayName: name,
            firstName: parts.first ?? "",
            lastName: parts.count > 1 ? parts[1] : ""
        )
        accounts[id] = Account(user: user, email: email.lowercased(), password: password)
        return user
    }

    func setSession(userId: UUID?) {
        sessionUserId = userId
        broadcastSession()
    }

    func seedCities(_ cities: [RatedCity], for userId: UUID) {
        citiesByUser[userId] = cities
    }

    func seedTravelProfile(_ profile: TravelProfile, for userId: UUID) {
        profilesByUser[userId] = profile
    }

    func seedFeed(_ items: [FeedItem]) {
        feed = items
    }

    func seedFollow(follower: UUID, following: UUID) {
        follows.insert(FollowEdge(follower: follower, following: following))
    }

    func seedPins(_ pins: [PhotoPin], for userId: UUID) {
        pinsByUser[userId] = pins
    }

    private func requireUserId() throws -> UUID {
        guard let sessionUserId else { throw BackendError.notSignedIn }
        return sessionUserId
    }

    private func checkWriteFailure() throws {
        if let error = failNextWrite {
            failNextWrite = nil
            throw error
        }
    }

    private func sessionUser() -> SessionUser? {
        guard let id = sessionUserId, let account = accounts[id] else { return nil }
        return SessionUser(id: id, email: account.email)
    }

    private func broadcastSession() {
        let user = sessionUser()
        for continuation in authContinuations.values {
            continuation.yield(user)
        }
    }

    // MARK: - Auth

    func currentUser() async -> SessionUser? { sessionUser() }

    func authStateStream() -> AsyncStream<SessionUser?> {
        let token = UUID()
        return AsyncStream { continuation in
            authContinuations[token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.authContinuations.removeValue(forKey: token) }
            }
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) async throws -> SignUpOutcome {
        try checkWriteFailure()
        let normalized = email.lowercased()
        guard !accounts.values.contains(where: { $0.email == normalized }) else {
            throw BackendError.message("An account with that email already exists. Try signing in instead.")
        }
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let user = addAccount(name: name.isEmpty ? "Traveller" : name, email: normalized, password: password)
        setSession(userId: user.id)
        return .signedIn
    }

    func signIn(email: String, password: String) async throws {
        try checkWriteFailure()
        guard let account = accounts.values.first(where: { $0.email == email.lowercased() }),
              account.password == password else {
            throw BackendError.message("That email and password don’t match. Please try again.")
        }
        setSession(userId: account.user.id)
    }

    func signOut() async throws {
        setSession(userId: nil)
    }

    func sendPasswordReset(email: String) async throws {
        try checkWriteFailure()
    }

    func deleteAccount() async throws {
        try checkWriteFailure()
        let userId = try requireUserId()
        accounts.removeValue(forKey: userId)
        citiesByUser.removeValue(forKey: userId)
        profilesByUser.removeValue(forKey: userId)
        pinsByUser.removeValue(forKey: userId)
        feed.removeAll { $0.userId == userId }
        follows = follows.filter { $0.follower != userId && $0.following != userId }
        setSession(userId: nil)
    }

    // MARK: - Profile

    func fetchMyProfile() async throws -> UserSummary? {
        let userId = try requireUserId()
        return accounts[userId]?.user
    }

    @discardableResult
    func updateMyName(firstName: String, lastName: String) async throws -> UserSummary {
        try checkWriteFailure()
        let userId = try requireUserId()
        guard var account = accounts[userId] else { throw BackendError.notSignedIn }
        let display = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        account.user = UserSummary(
            id: userId,
            displayName: display.isEmpty ? "Traveller" : display,
            firstName: firstName,
            lastName: lastName
        )
        accounts[userId] = account
        return account.user
    }

    // MARK: - Rated cities

    func fetchRatedCities(userId: UUID?) async throws -> [RatedCity] {
        let owner = try userId ?? requireUserId()
        return (citiesByUser[owner] ?? []).sorted { $0.cumulativeScore > $1.cumulativeScore }
    }

    func saveRatedCity(_ city: RatedCity) async throws {
        try checkWriteFailure()
        let userId = try requireUserId()
        var cities = citiesByUser[userId] ?? []
        cities.removeAll { $0.id == city.id || $0.cityData.placeKey == city.cityData.placeKey }
        var stored = city
        if stored.createdAt == nil { stored.createdAt = Date() }
        cities.append(stored)
        citiesByUser[userId] = cities
    }

    func deleteRatedCity(id: UUID) async throws {
        try checkWriteFailure()
        let userId = try requireUserId()
        citiesByUser[userId]?.removeAll { $0.id == id }
    }

    // MARK: - Travel profile

    func fetchTravelProfile(userId: UUID?) async throws -> TravelProfile? {
        let owner = try userId ?? requireUserId()
        return profilesByUser[owner]
    }

    func saveTravelProfile(_ profile: TravelProfile) async throws {
        try checkWriteFailure()
        let userId = try requireUserId()
        profilesByUser[userId] = profile
    }

    // MARK: - Community places

    func fetchCityAttractions(city: String, country: String) async throws -> [Attraction] {
        communityPlaces[CityData.placeKey(city: city, country: country)] ?? []
    }

    func addCityAttraction(city: String, country: String, name: String, category: AttractionCategory) async throws -> Attraction {
        try checkWriteFailure()
        let attraction = Attraction(name: name.trimmingCharacters(in: .whitespacesAndNewlines), category: category)
        let key = CityData.placeKey(city: city, country: country)
        if let existing = communityPlaces[key]?.first(where: { $0.dedupeKey == attraction.dedupeKey }) {
            return existing
        }
        communityPlaces[key, default: []].append(attraction)
        return attraction
    }

    // MARK: - Feed

    func fetchFeed(scope: FeedScope, limit: Int) async throws -> [FeedItem] {
        let sorted = feed.sorted { $0.timestamp > $1.timestamp }
        let filtered: [FeedItem]
        switch scope {
        case .everyone:
            filtered = sorted
        case .following:
            let ids = try await followingIds()
            filtered = sorted.filter { ids.contains($0.userId) }
        case .trending:
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            filtered = sorted.filter { $0.timestamp >= weekAgo }
        }
        return Array(filtered.prefix(limit))
    }

    func postFeedActivity(_ draft: FeedActivityDraft) async throws {
        try checkWriteFailure()
        let userId = try requireUserId()
        feed.append(FeedItem(
            userId: userId,
            userName: accounts[userId]?.user.name ?? "Traveller",
            action: .visitedCity(placeCount: draft.placeCount),
            city: draft.city,
            country: draft.country,
            cityPhotoURL: draft.cityPhotoURL,
            score: draft.score,
            review: draft.review
        ))
    }

    // MARK: - Social graph

    func searchUsers(query: String) async throws -> [UserSummary] {
        let me = try requireUserId()
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return [] }
        return accounts.values
            .map(\.user)
            .filter { $0.id != me && $0.name.lowercased().contains(needle) }
            .sorted { $0.name < $1.name }
    }

    func suggestedUsers(limit: Int) async throws -> [UserSummary] {
        let me = try requireUserId()
        return Array(
            accounts.values.map(\.user).filter { $0.id != me }.sorted { $0.name < $1.name }.prefix(limit)
        )
    }

    func followingIds() async throws -> Set<UUID> {
        let me = try requireUserId()
        return Set(follows.filter { $0.follower == me }.map(\.following))
    }

    func followCounts(userId: UUID) async throws -> FollowCounts {
        FollowCounts(
            followers: follows.filter { $0.following == userId }.count,
            following: follows.filter { $0.follower == userId }.count
        )
    }

    func followers(of userId: UUID) async throws -> [UserSummary] {
        follows.filter { $0.following == userId }
            .compactMap { accounts[$0.follower]?.user }
            .sorted { $0.name < $1.name }
    }

    func following(of userId: UUID) async throws -> [UserSummary] {
        follows.filter { $0.follower == userId }
            .compactMap { accounts[$0.following]?.user }
            .sorted { $0.name < $1.name }
    }

    func follow(userId: UUID) async throws {
        try checkWriteFailure()
        let me = try requireUserId()
        guard me != userId else { return }
        follows.insert(FollowEdge(follower: me, following: userId))
    }

    func unfollow(userId: UUID) async throws {
        try checkWriteFailure()
        let me = try requireUserId()
        follows.remove(FollowEdge(follower: me, following: userId))
    }

    // MARK: - Photo pins

    func fetchPhotoPins(userId: UUID?) async throws -> [PhotoPin] {
        let owner = try userId ?? requireUserId()
        return (pinsByUser[owner] ?? []).sorted { $0.uploadedAt > $1.uploadedAt }
    }

    func addPhotoPin(_ draft: PhotoPinDraft) async throws -> PhotoPin {
        try checkWriteFailure()
        let userId = try requireUserId()
        let id = UUID()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("sonder-pin-\(id.uuidString).jpg")
        try draft.imageData.write(to: fileURL, options: .atomic)
        let pin = PhotoPin(
            id: id,
            userId: userId,
            photoURL: fileURL.absoluteString,
            storagePath: nil,
            latitude: draft.latitude,
            longitude: draft.longitude,
            locationName: draft.locationName,
            caption: draft.caption,
            takenAt: draft.takenAt,
            uploadedAt: Date()
        )
        pinsByUser[userId, default: []].append(pin)
        return pin
    }

    func deletePhotoPin(_ pin: PhotoPin) async throws {
        try checkWriteFailure()
        let userId = try requireUserId()
        pinsByUser[userId]?.removeAll { $0.id == pin.id }
    }
}
