import Foundation
import CoreLocation

// MARK: - Categories

enum AttractionCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case culture = "Museums & Culture"
    case nature = "Parks & Nature"
    case food = "Food & Markets"
    case neighbourhood = "Neighbourhoods & Walks"
    case experience = "Experiences & Activities"
    case landmark = "Viewpoints & Landmarks"
    case general = "General Appeal"

    var id: String { rawValue }

    /// Categories a place can be filed under (General Appeal is rated separately).
    static var placeCategories: [AttractionCategory] {
        allCases.filter { $0 != .general }
    }

    /// How strongly this category signals the overall feel of a city.
    var weight: Double {
        switch self {
        case .neighbourhood: return 1.5
        case .food: return 1.2
        case .culture, .nature, .experience: return 1.0
        case .landmark: return 0.8
        case .general: return 1.5
        }
    }

    /// Ordering for category scores: higher score first; ties go to the heavier-weighted
    /// category, then alphabetically so the order is stable.
    static func ranksAbove(
        _ lhs: AttractionCategory, _ lhsScore: Double,
        _ rhs: AttractionCategory, _ rhsScore: Double
    ) -> Bool {
        if abs(lhsScore - rhsScore) > 0.0001 { return lhsScore > rhsScore }
        if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
        return lhs.rawValue < rhs.rawValue
    }

    var icon: String {
        switch self {
        case .culture: return "building.columns"
        case .nature: return "leaf"
        case .food: return "fork.knife"
        case .neighbourhood: return "figure.walk"
        case .experience: return "theatermasks"
        case .landmark: return "binoculars"
        case .general: return "sparkles"
        }
    }

    /// Name shown to people ("General Appeal" is presented as the city's overall vibe).
    var displayName: String {
        self == .general ? "Overall vibe" : rawValue
    }

    /// Short label for chips and compact rows.
    var shortName: String {
        switch self {
        case .culture: return "Culture"
        case .nature: return "Nature"
        case .food: return "Food"
        case .neighbourhood: return "Neighbourhoods"
        case .experience: return "Experiences"
        case .landmark: return "Landmarks"
        case .general: return "Overall vibe"
        }
    }
}

// MARK: - Attractions

struct Attraction: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let category: AttractionCategory
    var weight: Double { category.weight }

    init(id: UUID = UUID(), name: String, category: AttractionCategory) {
        self.id = id
        self.name = name
        self.category = category
    }

    /// Case-insensitive identity used to detect duplicates within a city.
    var dedupeKey: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static let generalAppealName = "General Appeal"
}

// MARK: - Sentiment

/// How a place felt. Combined with head-to-head ranking, this replaces 1–5 stars.
enum VisitSentiment: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case wouldReturn = "would_return"
    case decent = "decent"
    case waste = "waste"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .wouldReturn: return "Loved it"
        case .decent: return "It was fine"
        case .waste: return "Not for me"
        }
    }

    var detailLine: String {
        switch self {
        case .wouldReturn: return "You’d go out of your way to do this again."
        case .decent: return "Glad you went, but not the reason you’d come back."
        case .waste: return "Wouldn’t repeat it."
        }
    }

    var icon: String {
        switch self {
        case .wouldReturn: return "heart.fill"
        case .decent: return "hand.thumbsup.fill"
        case .waste: return "hand.thumbsdown.fill"
        }
    }

    /// 0 is best. Places in a category are always ordered by tier first, then by comparison.
    var sortTier: Int {
        switch self {
        case .wouldReturn: return 0
        case .decent: return 1
        case .waste: return 2
        }
    }

    /// The 0–10 band a place in this tier can score in.
    var scoreBand: ClosedRange<Double> {
        switch self {
        case .wouldReturn: return 7.5...10.0
        case .decent: return 4.5...7.0
        case .waste: return 1.0...4.0
        }
    }
}

// MARK: - City

struct CityData: Identifiable, Hashable, Sendable {
    let id: UUID
    var city: String
    var country: String
    var flag: String
    var photoURL: String
    var latitude: Double?
    var longitude: Double?
    var attractions: [Attraction]

    init(
        id: UUID = UUID(),
        city: String,
        country: String,
        flag: String = "",
        photoURL: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        attractions: [Attraction] = []
    ) {
        self.id = id
        self.city = city
        self.country = country
        self.flag = flag
        self.photoURL = photoURL
        self.latitude = latitude
        self.longitude = longitude
        self.attractions = attractions
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Stable key for "is this the same place" checks (case-insensitive).
    var placeKey: String { CityData.placeKey(city: city, country: country) }

    static func placeKey(city: String, country: String) -> String {
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let k = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(c)|\(k)"
    }

    /// "Lisbon, Portugal" (or just the city when the country is unknown).
    var displayName: String {
        country.isEmpty ? city : "\(city), \(country)"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CityData, rhs: CityData) -> Bool { lhs.id == rhs.id }
}

// MARK: - Ratings

struct AttractionRating: Identifiable, Hashable, Sendable {
    let id: UUID
    let attractionId: UUID
    let sentiment: VisitSentiment
    /// 1 = best within the same category for that city.
    let rankAmongSimilar: Int

    init(id: UUID = UUID(), attractionId: UUID, sentiment: VisitSentiment, rankAmongSimilar: Int) {
        self.id = id
        self.attractionId = attractionId
        self.sentiment = sentiment
        self.rankAmongSimilar = max(1, rankAmongSimilar)
    }
}

/// One place the user is logging for a city visit, ready to be scored.
struct CityVisitAttractionEntry: Hashable, Sendable {
    let attraction: Attraction
    let sentiment: VisitSentiment
    /// 1 = best in this category for this visit.
    let rankInCategory: Int
    let categoryCount: Int
}

/// A place together with its rating and computed score, for display.
struct ScoredPlace: Identifiable, Hashable, Sendable {
    let attraction: Attraction
    let sentiment: VisitSentiment
    let rank: Int
    let score: Double
    var id: UUID { attraction.id }
}

struct RatedCity: Identifiable, Sendable {
    let id: UUID
    var cityData: CityData
    var cumulativeScore: Double
    var summary: String
    var highlight: String
    var wouldRecommendIf: String
    var scoreBreakdown: [String: Double]?
    var ratings: [AttractionRating]
    var topAttractionName: String?
    var createdAt: Date?

    init(
        id: UUID = UUID(),
        cityData: CityData,
        cumulativeScore: Double,
        summary: String,
        highlight: String,
        wouldRecommendIf: String,
        scoreBreakdown: [String: Double]? = nil,
        ratings: [AttractionRating] = [],
        topAttractionName: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.cityData = cityData
        self.cumulativeScore = cumulativeScore
        self.summary = summary
        self.highlight = highlight
        self.wouldRecommendIf = wouldRecommendIf
        self.scoreBreakdown = scoreBreakdown
        self.ratings = ratings
        self.topAttractionName = topAttractionName
        self.createdAt = createdAt
    }

    /// Ratings joined with their attractions, as scoreable entries.
    var visitEntries: [CityVisitAttractionEntry] {
        let byId = Dictionary(cityData.attractions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let joined: [(Attraction, AttractionRating)] = ratings.compactMap { rating in
            guard let attraction = byId[rating.attractionId] else { return nil }
            return (attraction, rating)
        }
        let counts = Dictionary(grouping: joined, by: { $0.0.category }).mapValues(\.count)
        return joined.map { attraction, rating in
            CityVisitAttractionEntry(
                attraction: attraction,
                sentiment: rating.sentiment,
                rankInCategory: rating.rankAmongSimilar,
                categoryCount: counts[attraction.category] ?? 1
            )
        }
    }

    /// Every rated place with its individual 0–10 score, best first.
    var scoredPlaces: [ScoredPlace] {
        ScoringEngine.scoredPlaces(for: visitEntries)
    }

    /// Number of places rated (General Appeal is a rating of the city, not a place).
    var placeCount: Int {
        let named = visitEntries.filter { $0.attraction.category != .general }.count
        // Visits logged by the first version of the app saved ratings without place names.
        return named > 0 ? named : ratings.count
    }

    /// False for visits saved by the first version of the app, which kept scores but not which
    /// places they belonged to.
    var hasPlaceDetails: Bool {
        ratings.isEmpty || !visitEntries.isEmpty
    }

    /// Category scores sorted best-first, for breakdown charts.
    var sortedBreakdown: [(category: AttractionCategory, score: Double)] {
        (scoreBreakdown ?? [:])
            .compactMap { key, value -> (category: AttractionCategory, score: Double)? in
                guard let category = AttractionCategory(rawValue: key) else { return nil }
                return (category, value)
            }
            .sorted { lhs, rhs in
                AttractionCategory.ranksAbove(lhs.category, lhs.score, rhs.category, rhs.score)
            }
    }
}
