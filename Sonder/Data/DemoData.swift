#if DEBUG
import Foundation

/// Sample content for the debug demo mode (`-SonderDemoMode YES`) and SwiftUI previews.
/// Nothing here ships in release builds.
@MainActor
enum DemoData {
    static let meId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let mayaId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let jordanId = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let priyaId = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let lucaId = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
    static let sofiaId = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!

    typealias Pick = (name: String, sentiment: VisitSentiment)

    /// Rates a curated city. Picks are listed best-first within each category and tier.
    static func ratedCity(
        _ seed: CityData,
        picks: [Pick],
        vibe: VisitSentiment?,
        prior: [RatedCity] = [],
        daysAgo: Double = 0
    ) -> RatedCity {
        var draft = CityRatingDraft()
        for pick in picks {
            guard let attraction = seed.attractions.first(where: { $0.name == pick.name }) else { continue }
            draft.insert(attraction, sentiment: pick.sentiment)
        }
        draft.generalAppeal = vibe
        return RatedCity.build(
            city: seed,
            draft: draft,
            priorCities: prior,
            createdAt: Date().addingTimeInterval(-daysAgo * 86_400)
        )
    }

    static var myCities: [RatedCity] {
        let tokyo = ratedCity(Attractions.tokyo, picks: [
            ("Tsukiji Outer Market", .wouldReturn),
            ("Depachika Food Halls", .wouldReturn),
            ("Yanaka Neighbourhood", .wouldReturn),
            ("Harajuku & Takeshita Street", .decent),
            ("Senso-ji Temple", .wouldReturn),
            ("teamLab Planets", .wouldReturn),
            ("Shinjuku Gyoen", .wouldReturn),
            ("Tokyo Skytree", .decent)
        ], vibe: .wouldReturn, daysAgo: 40)

        let lisbon = ratedCity(Attractions.lisbon, picks: [
            ("Alfama", .wouldReturn),
            ("Bairro Alto", .decent),
            ("Pastéis de Belém", .wouldReturn),
            ("Time Out Market", .decent),
            ("Miradouro da Senhora do Monte", .wouldReturn),
            ("Belém Tower", .waste),
            ("Tram 28", .decent)
        ], vibe: .wouldReturn, prior: [tokyo], daysAgo: 21)

        let kyoto = ratedCity(Attractions.kyoto, picks: [
            ("Fushimi Inari Taisha", .wouldReturn),
            ("Gion", .wouldReturn),
            ("Higashiyama", .wouldReturn),
            ("Nishiki Market", .decent),
            ("Arashiyama Bamboo Grove", .decent),
            ("Kinkaku-ji", .decent)
        ], vibe: .wouldReturn, prior: [tokyo, lisbon], daysAgo: 9)

        return [tokyo, lisbon, kyoto]
    }

    static func feed() -> [FeedItem] {
        func item(
            _ userId: UUID, _ name: String, _ seed: CityData,
            places: Int, score: Double, review: String, hoursAgo: Double
        ) -> FeedItem {
            FeedItem(
                userId: userId,
                userName: name,
                action: .visitedCity(placeCount: places),
                city: seed.city,
                country: seed.country,
                cityPhotoURL: seed.photoURL,
                score: score,
                review: review,
                timestamp: Date().addingTimeInterval(-hoursAgo * 3_600)
            )
        }
        return [
            item(mayaId, "Maya Chen", Attractions.paris, places: 7, score: 8.6,
                 review: "Le Marais was the top pick — best wandered without a plan.", hoursAgo: 2),
            item(jordanId, "Jordan Okafor", Attractions.tokyo, places: 9, score: 9.2,
                 review: "Depachika food halls ruined every other lunch.", hoursAgo: 7),
            item(priyaId, "Priya Nair", Attractions.marrakech, places: 6, score: 7.9,
                 review: "Medina souks at dusk were the highlight.", hoursAgo: 20),
            item(lucaId, "Luca Rossi", Attractions.newOrleans, places: 5, score: 8.8,
                 review: "Live jazz on Frenchmen Street beat everything on the list.", hoursAgo: 31),
            item(sofiaId, "Sofia Alvarez", Attractions.tokyo, places: 6, score: 8.9,
                 review: "Yanaka felt like a different city entirely.", hoursAgo: 52),
            item(mayaId, "Maya Chen", Attractions.bali, places: 8, score: 8.1,
                 review: "Tegallalang at sunrise, before the crowds.", hoursAgo: 96),
            item(priyaId, "Priya Nair", Attractions.newYork, places: 9, score: 8.4,
                 review: "West Village on foot is the whole trip.", hoursAgo: 140)
        ]
    }

    static func pins() -> [PhotoPin] {
        func pin(_ seed: CityData, caption: String, daysAgo: Double, dLat: Double, dLon: Double) -> PhotoPin {
            PhotoPin(
                id: UUID(),
                userId: meId,
                photoURL: seed.photoURL,
                storagePath: nil,
                latitude: (seed.latitude ?? 0) + dLat,
                longitude: (seed.longitude ?? 0) + dLon,
                locationName: seed.displayName,
                caption: caption,
                takenAt: Date().addingTimeInterval(-daysAgo * 86_400),
                uploadedAt: Date().addingTimeInterval(-daysAgo * 86_400)
            )
        }
        return [
            pin(Attractions.tokyo, caption: "Blue hour from the hotel roof.", daysAgo: 41, dLat: 1.2, dLon: 0.9),
            pin(Attractions.lisbon, caption: "The view was worth every stair.", daysAgo: 22, dLat: 0.9, dLon: -1.1)
        ]
    }

    /// A fully populated in-memory backend, signed in as the demo traveller.
    static func makeBackend(signedIn: Bool = true) -> InMemoryBackend {
        let backend = InMemoryBackend()
        backend.addAccount(name: "Alex Morgan", email: "alex@example.com", id: meId)
        backend.addAccount(name: "Maya Chen", email: "maya@example.com", id: mayaId)
        backend.addAccount(name: "Jordan Okafor", email: "jordan@example.com", id: jordanId)
        backend.addAccount(name: "Priya Nair", email: "priya@example.com", id: priyaId)
        backend.addAccount(name: "Luca Rossi", email: "luca@example.com", id: lucaId)
        backend.addAccount(name: "Sofia Alvarez", email: "sofia@example.com", id: sofiaId)

        let mine = myCities
        backend.seedCities(mine, for: meId)
        backend.seedTravelProfile(ScoringEngine.travelProfile(from: mine), for: meId)

        let mayaCities = [
            ratedCity(Attractions.paris, picks: [
                ("Le Marais", .wouldReturn), ("Montmartre", .wouldReturn),
                ("Louvre Museum", .wouldReturn), ("Marché des Enfants Rouges", .wouldReturn),
                ("Parisian Cafés", .decent), ("Eiffel Tower", .decent), ("Seine River Cruise", .decent)
            ], vibe: .wouldReturn, daysAgo: 1),
            ratedCity(Attractions.bali, picks: [
                ("Tegallalang Rice Terraces", .wouldReturn), ("Balinese Cooking Class", .wouldReturn),
                ("Canggu", .decent), ("Ubud Market", .decent), ("Tanah Lot", .waste)
            ], vibe: .decent, daysAgo: 4)
        ]
        backend.seedCities(mayaCities, for: mayaId)
        backend.seedTravelProfile(ScoringEngine.travelProfile(from: mayaCities), for: mayaId)

        backend.seedCities([
            ratedCity(Attractions.marrakech, picks: [
                ("Medina Souks", .wouldReturn), ("Jemaa el-Fnaa Food Stalls", .wouldReturn),
                ("Majorelle Garden", .decent), ("Bahia Palace", .wouldReturn), ("Hammam Experience", .decent)
            ], vibe: .decent, daysAgo: 1)
        ], for: priyaId)

        backend.seedFeed(feed())
        backend.seedFollow(follower: meId, following: mayaId)
        backend.seedFollow(follower: meId, following: priyaId)
        backend.seedFollow(follower: mayaId, following: meId)
        backend.seedFollow(follower: lucaId, following: meId)
        backend.seedFollow(follower: sofiaId, following: meId)
        backend.seedPins(pins(), for: meId)

        if signedIn {
            backend.setSession(userId: meId)
        }
        return backend
    }
}

extension InMemoryBackend {
    /// Backend used when the app is launched in demo mode.
    static func demo() -> InMemoryBackend {
        // `-SonderDemoSignedOut YES` starts on the welcome screen instead.
        DemoData.makeBackend(signedIn: !UserDefaults.standard.bool(forKey: "SonderDemoSignedOut"))
    }
}
#endif
