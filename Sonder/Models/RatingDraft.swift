import Foundation

/// A place in an in-progress ranking, with how it felt.
struct RankedPlace: Identifiable, Hashable, Sendable {
    let attraction: Attraction
    var sentiment: VisitSentiment
    var id: UUID { attraction.id }
}

/// The editable state behind the "rate a city" flow.
///
/// Each category holds a best-first list. The list is always grouped by sentiment tier
/// (loved → fine → not for me); within a tier the order comes from head-to-head comparisons.
struct CityRatingDraft: Equatable, Sendable {
    private(set) var rankings: [AttractionCategory: [RankedPlace]] = [:]

    /// The city's overall feel (walkability, atmosphere, ease of getting around). Optional.
    var generalAppeal: VisitSentiment?

    /// Backing attraction for the General Appeal rating, kept stable across edits.
    private(set) var generalAttraction = Attraction(name: Attraction.generalAppealName, category: .general)

    init() {}

    /// Rebuilds a draft from a saved city so it can be edited.
    init(ratedCity: RatedCity) {
        let entries = ratedCity.visitEntries.sorted { lhs, rhs in
            if lhs.sentiment.sortTier != rhs.sentiment.sortTier {
                return lhs.sentiment.sortTier < rhs.sentiment.sortTier
            }
            return lhs.rankInCategory < rhs.rankInCategory
        }
        for entry in entries {
            if entry.attraction.category == .general {
                generalAppeal = entry.sentiment
                generalAttraction = entry.attraction
            } else {
                rankings[entry.attraction.category, default: []]
                    .append(RankedPlace(attraction: entry.attraction, sentiment: entry.sentiment))
            }
        }
    }

    // MARK: Reading

    var activeCategories: [AttractionCategory] {
        AttractionCategory.placeCategories.filter { rankings[$0]?.isEmpty == false }
    }

    var placeCount: Int { rankings.values.reduce(0) { $0 + $1.count } }

    var hasPlaces: Bool { placeCount > 0 }

    func places(in category: AttractionCategory) -> [RankedPlace] {
        rankings[category] ?? []
    }

    /// True when a place with the same name is already in the draft (any category).
    func contains(name: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rankings.values.contains { list in list.contains { $0.attraction.dedupeKey == key } }
    }

    /// Positions at which a place with `sentiment` may be inserted into `category`
    /// (`lowerBound...upperBound`, i.e. anywhere inside or at the edges of its tier).
    func insertionRange(for sentiment: VisitSentiment, in category: AttractionCategory) -> Range<Int> {
        let list = places(in: category)
        let lower = list.firstIndex { $0.sentiment.sortTier >= sentiment.sortTier } ?? list.count
        let upper = list.firstIndex { $0.sentiment.sortTier > sentiment.sortTier } ?? list.count
        return lower..<upper
    }

    // MARK: Editing

    /// Inserts a place at `index`, clamped so the tier grouping always holds.
    mutating func insert(_ attraction: Attraction, sentiment: VisitSentiment, at index: Int? = nil) {
        guard attraction.category != .general else {
            generalAppeal = sentiment
            return
        }
        let range = insertionRange(for: sentiment, in: attraction.category)
        let target = min(max(index ?? range.upperBound, range.lowerBound), range.upperBound)
        rankings[attraction.category, default: []]
            .insert(RankedPlace(attraction: attraction, sentiment: sentiment), at: target)
    }

    mutating func remove(id: UUID) {
        for category in Array(rankings.keys) {
            rankings[category]?.removeAll { $0.id == id }
            if rankings[category]?.isEmpty == true {
                rankings.removeValue(forKey: category)
            }
        }
    }

    // MARK: Output

    /// All attractions referenced by the draft (places + General Appeal when rated).
    var allAttractions: [Attraction] {
        var result = AttractionCategory.placeCategories.flatMap { places(in: $0).map(\.attraction) }
        if generalAppeal != nil { result.append(generalAttraction) }
        return result
    }

    /// Scoreable entries with 1-based ranks per category.
    var entries: [CityVisitAttractionEntry] {
        var result: [CityVisitAttractionEntry] = []
        for category in AttractionCategory.placeCategories {
            let list = places(in: category)
            for (index, place) in list.enumerated() {
                result.append(CityVisitAttractionEntry(
                    attraction: place.attraction,
                    sentiment: place.sentiment,
                    rankInCategory: index + 1,
                    categoryCount: list.count
                ))
            }
        }
        if let generalAppeal {
            result.append(CityVisitAttractionEntry(
                attraction: generalAttraction,
                sentiment: generalAppeal,
                rankInCategory: 1,
                categoryCount: 1
            ))
        }
        return result
    }
}

/// Binary search over insertion positions, driven by "which did you prefer?" answers.
struct InsertionSearch: Equatable, Sendable {
    private(set) var low: Int
    private(set) var high: Int

    /// - Parameter range: Allowed insertion positions (`lowerBound...upperBound`).
    init(range: Range<Int>) {
        low = range.lowerBound
        high = range.upperBound
    }

    var isResolved: Bool { low >= high }

    /// Where the new place goes once `isResolved` is true.
    var insertionIndex: Int { low }

    /// Index of the existing place to compare against next.
    var opponentIndex: Int { (low + high) / 2 }

    /// Upper bound on the questions still to ask.
    var remainingComparisons: Int {
        guard !isResolved else { return 0 }
        return Int(ceil(log2(Double(high - low + 1))))
    }

    /// The new place beat the opponent: it belongs at or above the opponent's position.
    mutating func preferNew() {
        guard !isResolved else { return }
        high = opponentIndex
    }

    /// The existing place won: the new one belongs below it.
    mutating func preferExisting() {
        guard !isResolved else { return }
        low = opponentIndex + 1
    }
}
