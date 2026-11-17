import Foundation
import Testing
@testable import Sonder

@MainActor
@Suite("App store with an in-memory backend")
struct AppStoreTests {
    private struct Fixture {
        let backend: InMemoryBackend
        let store: AppStore
        let me: UserSummary
        let friend: UserSummary
    }

    private func makeFixture() async -> Fixture {
        let backend = InMemoryBackend()
        let me = backend.addAccount(name: "Test Traveller", email: "me@example.com")
        let friend = backend.addAccount(name: "Maya Chen", email: "maya@example.com")
        backend.setSession(userId: me.id)
        let store = AppStore(backend: backend, claude: nil, cache: nil, toaster: Toaster())
        await store.start(userId: me.id)
        return Fixture(backend: backend, store: store, me: me, friend: friend)
    }

    private func draft(loved: [String] = [], fine: [String] = [], disliked: [String] = []) -> CityRatingDraft {
        var draft = CityRatingDraft()
        for name in loved { draft.insert(Attraction(name: name, category: .food), sentiment: .wouldReturn) }
        for name in fine { draft.insert(Attraction(name: name, category: .culture), sentiment: .decent) }
        for name in disliked { draft.insert(Attraction(name: name, category: .landmark), sentiment: .waste) }
        return draft
    }

    /// Lets the store's fire-and-forget follow-up tasks (feed post, profile refresh) finish.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    @Test("Saving a city stores it, ranks it and shares it to the feed")
    func saveCity() async throws {
        let fixture = await makeFixture()
        let store = fixture.store

        try await store.saveCity(city: CityData(city: "Lisbon", country: "Portugal"), draft: draft(fine: ["Museum"]))
        try await store.saveCity(city: CityData(city: "Tokyo", country: "Japan"), draft: draft(loved: ["Market"]))
        await settle()

        #expect(store.ratedCities.map(\.cityData.city) == ["Tokyo", "Lisbon"])
        #expect(store.totalPlacesRated == 2)
        #expect(store.countriesVisited == 2)
        #expect(store.rank(of: store.ratedCities[1]) == 2)

        let saved = try await fixture.backend.fetchRatedCities(userId: nil)
        #expect(saved.count == 2)
        #expect(fixture.backend.feed.count == 2)
        #expect(fixture.backend.feed.allSatisfy { $0.userId == fixture.me.id })
    }

    @Test("Re-rating a city updates it in place instead of duplicating it")
    func reRatingUpdatesInPlace() async throws {
        let fixture = await makeFixture()
        let store = fixture.store
        let lisbon = CityData(city: "Lisbon", country: "Portugal")

        let first = try await store.saveCity(city: lisbon, draft: draft(disliked: ["Tower"]))
        // Same place arriving as a brand-new CityData (as it does from search).
        let second = try await store.saveCity(
            city: CityData(city: "lisbon ", country: "PORTUGAL"),
            draft: draft(loved: ["Market"])
        )
        await settle()

        #expect(store.ratedCities.count == 1)
        #expect(second.id == first.id)
        #expect(second.cumulativeScore > first.cumulativeScore)
        #expect(try await fixture.backend.fetchRatedCities(userId: nil).count == 1)
        // Only the first visit is announced in the feed.
        #expect(fixture.backend.feed.count == 1)
    }

    @Test("A failed save leaves local state untouched and surfaces the error")
    func failedSaveDoesNotMutateState() async {
        let fixture = await makeFixture()
        fixture.backend.failNextWrite = BackendError.message("Server unavailable")

        await #expect(throws: BackendError.message("Server unavailable")) {
            try await fixture.store.saveCity(
                city: CityData(city: "Paris", country: "France"),
                draft: draft(loved: ["Café"])
            )
        }
        #expect(fixture.store.ratedCities.isEmpty)
    }

    @Test("A visit with no places is rejected")
    func emptyVisitRejected() async {
        let fixture = await makeFixture()
        await #expect(throws: BackendError.self) {
            try await fixture.store.saveCity(city: CityData(city: "Paris", country: "France"), draft: CityRatingDraft())
        }
    }

    @Test("The travel personality unlocks at three cities and is saved")
    func profileUnlocksAtThreshold() async throws {
        let fixture = await makeFixture()
        let store = fixture.store

        try await store.saveCity(city: CityData(city: "A", country: "X"), draft: draft(loved: ["a"]))
        try await store.saveCity(city: CityData(city: "B", country: "X"), draft: draft(loved: ["b"]))
        await settle()
        #expect(store.travelProfile.isPlaceholder)
        #expect(store.citiesUntilProfile == 1)

        try await store.saveCity(city: CityData(city: "C", country: "X"), draft: draft(loved: ["c"], disliked: ["d"]))
        await settle()
        #expect(!store.travelProfile.isPlaceholder)
        #expect(store.travelProfile.personalityType == "The Flavour Chaser")
        #expect(try await fixture.backend.fetchTravelProfile(userId: nil) != nil)
    }

    @Test("Deleting a city removes it; a failed delete restores it")
    func deleteCity() async throws {
        let fixture = await makeFixture()
        let store = fixture.store
        let city = try await store.saveCity(city: CityData(city: "Kyoto", country: "Japan"), draft: draft(loved: ["Tea"]))
        await settle()

        fixture.backend.failNextWrite = BackendError.message("offline")
        await store.deleteCity(city)
        #expect(store.ratedCities.count == 1)

        await store.deleteCity(city)
        #expect(store.ratedCities.isEmpty)
        #expect(try await fixture.backend.fetchRatedCities(userId: nil).isEmpty)
    }

    @Test("The feed can be scoped to people you follow")
    func feedScopes() async throws {
        let fixture = await makeFixture()
        let stranger = fixture.backend.addAccount(name: "Stranger", email: "s@example.com")
        fixture.backend.seedFeed([
            FeedItem(userId: fixture.friend.id, userName: "Maya Chen", action: .visitedCity(placeCount: 4), city: "Paris", country: "France", score: 8.6),
            FeedItem(userId: stranger.id, userName: "Stranger", action: .visitedCity(placeCount: 2), city: "Rome", country: "Italy", score: 7.1)
        ])
        fixture.backend.seedFollow(follower: fixture.me.id, following: fixture.friend.id)

        await fixture.store.refreshFeed()
        #expect(fixture.store.feedItems.count == 2)

        await fixture.store.setFeedScope(.following)
        #expect(fixture.store.feedItems.map(\.city) == ["Paris"])

        await fixture.store.setFeedScope(.trending)
        #expect(Set(fixture.store.trendingCities.map(\.city)) == ["Paris", "Rome"])
    }

    @Test("Following is optimistic and rolls back when the server refuses")
    func followRollsBack() async {
        let fixture = await makeFixture()
        let social = SocialStore(backend: fixture.backend, toaster: Toaster())
        await social.start(userId: fixture.me.id)

        await social.toggleFollow(fixture.friend)
        #expect(social.isFollowing(fixture.friend.id))
        #expect(social.myCounts.following == 1)

        fixture.backend.failNextWrite = BackendError.message("nope")
        await social.toggleFollow(fixture.friend)
        // Unfollow failed, so we are still following.
        #expect(social.isFollowing(fixture.friend.id))
        #expect(social.myCounts.following == 1)

        await social.toggleFollow(fixture.friend)
        #expect(!social.isFollowing(fixture.friend.id))
        #expect(social.myCounts.following == 0)
    }

    @Test("Signing out and deleting the account clear the session")
    func authLifecycle() async {
        let backend = InMemoryBackend()
        let auth = AuthStore(backend: backend)
        await auth.bootstrap()
        #expect(auth.phase == .signedOut)

        await auth.signUp(firstName: "Ada", lastName: "Lovelace", email: "not-an-email", password: "longenough")
        #expect(auth.errorMessage != nil)
        #expect(auth.phase == .signedOut)

        await auth.signUp(firstName: "Ada", lastName: "Lovelace", email: "ada@example.com", password: "short")
        #expect(auth.errorMessage != nil)

        await auth.signUp(firstName: "Ada", lastName: "Lovelace", email: "ada@example.com", password: "longenough")
        #expect(auth.phase == .signedIn)
        #expect(auth.errorMessage == nil)

        await auth.signOut()
        #expect(auth.phase == .signedOut)

        await auth.signIn(email: "ada@example.com", password: "wrong-password")
        #expect(auth.phase == .signedOut)
        #expect(auth.errorMessage != nil)

        await auth.signIn(email: "ADA@example.com", password: "longenough")
        #expect(auth.phase == .signedIn)

        #expect(await auth.deleteAccount())
        #expect(auth.phase == .signedOut)
        #expect(backend.accounts.isEmpty)
    }

    @Test("Email validation accepts real addresses and rejects obvious mistakes")
    func emailValidation() {
        #expect(AuthStore.isValidEmail("ada@example.com"))
        #expect(AuthStore.isValidEmail("  first.last+tag@sub.example.co.uk "))
        for bad in ["", "ada", "ada@", "@example.com", "ada@example", "ada @example.com", "ada@.com", "a@b@c.com"] {
            #expect(!AuthStore.isValidEmail(bad))
        }
    }

    @Test("Database rows round-trip a rated city without losing ratings")
    func rowRoundTrip() throws {
        var draft = CityRatingDraft()
        draft.insert(Attraction(name: "Alfama", category: .neighbourhood), sentiment: .wouldReturn)
        draft.insert(Attraction(name: "Belém Tower", category: .landmark), sentiment: .waste)
        draft.generalAppeal = .decent
        let city = RatedCity.build(
            city: CityData(city: "Lisbon", country: "Portugal", flag: "🇵🇹", photoURL: "https://example.com/p.jpg", latitude: 38.7, longitude: -9.1),
            draft: draft,
            priorCities: []
        )

        let row = RatedCityRow.from(city, userId: UUID())
        let data = try JSONEncoder().encode(row)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Column names match the Postgres schema, and server-managed columns are left out.
        #expect(object["city_name"] as? String == "Lisbon")
        #expect(object["would_recommend_if"] != nil)
        #expect(object["created_at"] == nil)

        let restored = try JSONDecoder().decode(RatedCityRow.self, from: data).toRatedCity()
        #expect(restored.id == city.id)
        #expect(restored.cityData.coordinate?.latitude == 38.7)
        #expect(restored.ratings.count == 3)
        #expect(restored.placeCount == 2)
        #expect(Set(restored.scoredPlaces.map(\.attraction.name)) == ["Alfama", "Belém Tower", Attraction.generalAppealName])
        #expect(abs(ScoringEngine.cityScore(for: restored.visitEntries).cumulativeScore - city.cumulativeScore) < 0.0001)
    }

    @Test("Cities saved by the first app version still load")
    func legacyRowsStillLoad() {
        func stars(_ score: Int) -> AttractionRatingDTO {
            AttractionRatingDTO(attractionId: UUID().uuidString, name: nil, category: nil, sentiment: nil, rank: nil, score: score)
        }
        let row = RatedCityRow(
            id: UUID(), userId: UUID(), cityName: "Porto", country: "Portugal", flag: "",
            photoUrl: "https://source.unsplash.com/featured/?porto,travel", latitude: nil, longitude: nil,
            cumulativeScore: 8.2, summary: "Lovely.", highlight: "The river.", wouldRecommendIf: "You like hills.",
            scoreBreakdown: ["Food & Markets": 9.0, "something old": 4.0], topAttractionName: nil,
            ratings: [stars(5), stars(3), stars(1)], createdAt: nil
        )
        let city = row.toRatedCity()

        // The dead photo link is dropped and the flag is recovered from the country name.
        #expect(city.cityData.photoURL.isEmpty)
        #expect(city.cityData.flag == "🇵🇹")
        // Star ratings map onto sentiments; the saved score and write-up are kept.
        #expect(city.ratings.map(\.sentiment) == [.wouldReturn, .decent, .waste])
        #expect(city.cumulativeScore == 8.2)
        #expect(city.placeCount == 3)
        #expect(!city.hasPlaceDetails)
        #expect(city.scoredPlaces.isEmpty)
        // Unknown breakdown keys are ignored rather than crashing the chart.
        #expect(city.sortedBreakdown.map(\.category) == [.food])
        // Editing starts from an empty ranking.
        #expect(!CityRatingDraft(ratedCity: city).hasPlaces)
    }

    @Test("Flags can be recovered from country names")
    func flagsFromCountryNames() {
        #expect(Attractions.flagEmoji(countryName: "Portugal") == "🇵🇹")
        #expect(Attractions.flagEmoji(countryName: " united states ") == "🇺🇸")
        #expect(Attractions.flagEmoji(countryName: "USA") == "🇺🇸")
        #expect(Attractions.flagEmoji(countryName: "Japan") == "🇯🇵")
        #expect(Attractions.flagEmoji(countryName: "Unknown") == "")
        #expect(Attractions.flagEmoji(countryName: "") == "")
    }

    @Test("Flags come from ISO country codes")
    func flags() {
        #expect(Attractions.flagEmoji(isoCountryCode: "pt") == "🇵🇹")
        #expect(Attractions.flagEmoji(isoCountryCode: "JP") == "🇯🇵")
        #expect(Attractions.flagEmoji(isoCountryCode: "") == "")
        #expect(Attractions.flagEmoji(isoCountryCode: "USA") == "")
        #expect(Attractions.makeCity(city: " tokyo ", country: "Japan", isoCountryCode: "JP").photoURL == Attractions.tokyo.photoURL)
        #expect(Attractions.makeCity(city: "Porto", country: "Portugal", isoCountryCode: "PT").flag == "🇵🇹")
    }
}
