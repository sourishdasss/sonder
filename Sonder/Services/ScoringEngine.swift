import Foundation

/// Deterministic scoring and on-device taste analysis.
///
/// City score = Σ(place score × category weight) / Σ(category weight), on a 0–10 scale.
/// A place's score comes from its sentiment band and where it sits among same-tier places
/// in its category, so head-to-head rankings spread places out inside the band.
enum ScoringEngine {

    struct CityScore: Equatable, Sendable {
        let cumulativeScore: Double
        /// Average place score per category, keyed by `AttractionCategory.rawValue`.
        let breakdown: [String: Double]
        let places: [ScoredPlace]
        let topAttractionName: String?
    }

    struct Narrative: Equatable, Sendable {
        let summary: String
        let highlight: String
        let wouldRecommendIf: String
    }

    // MARK: - Place scores

    /// Score for the place at `positionInBucket` (0 = best) among `bucketCount` same-tier places.
    static func itemScore(sentiment: VisitSentiment, positionInBucket: Int, bucketCount: Int) -> Double {
        let band = sentiment.scoreBand
        let count = max(1, bucketCount)
        let position = min(max(0, positionInBucket), count - 1)
        let fraction = Double(count - position) / Double(count + 1)
        return band.lowerBound + fraction * (band.upperBound - band.lowerBound)
    }

    /// Scores every entry, returning places best-first.
    static func scoredPlaces(for entries: [CityVisitAttractionEntry]) -> [ScoredPlace] {
        var result: [ScoredPlace] = []
        let byCategory = Dictionary(grouping: entries, by: { $0.attraction.category })
        for (_, group) in byCategory {
            let ordered = group.sorted { lhs, rhs in
                if lhs.rankInCategory != rhs.rankInCategory { return lhs.rankInCategory < rhs.rankInCategory }
                return lhs.attraction.name < rhs.attraction.name
            }
            let tierCounts = Dictionary(grouping: ordered, by: \.sentiment).mapValues(\.count)
            var seenInTier: [VisitSentiment: Int] = [:]
            for entry in ordered {
                let position = seenInTier[entry.sentiment, default: 0]
                seenInTier[entry.sentiment] = position + 1
                let score = itemScore(
                    sentiment: entry.sentiment,
                    positionInBucket: position,
                    bucketCount: tierCounts[entry.sentiment] ?? 1
                )
                result.append(ScoredPlace(
                    attraction: entry.attraction,
                    sentiment: entry.sentiment,
                    rank: entry.rankInCategory,
                    score: score
                ))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.attraction.category.weight != rhs.attraction.category.weight {
                return lhs.attraction.category.weight > rhs.attraction.category.weight
            }
            return lhs.attraction.name < rhs.attraction.name
        }
    }

    // MARK: - City score

    static func cityScore(for entries: [CityVisitAttractionEntry]) -> CityScore {
        let places = scoredPlaces(for: entries)
        var weightedSum = 0.0
        var weightTotal = 0.0
        var perCategory: [AttractionCategory: [Double]] = [:]

        for place in places {
            let weight = place.attraction.category.weight
            weightedSum += place.score * weight
            weightTotal += weight
            perCategory[place.attraction.category, default: []].append(place.score)
        }

        let cumulative = weightTotal > 0 ? clamp(weightedSum / weightTotal) : 0
        var breakdown: [String: Double] = [:]
        for (category, scores) in perCategory {
            breakdown[category.rawValue] = clamp(scores.reduce(0, +) / Double(scores.count))
        }

        let top = places.first { $0.attraction.category != .general }
        return CityScore(
            cumulativeScore: cumulative,
            breakdown: breakdown,
            places: places,
            topAttractionName: top?.attraction.name
        )
    }

    // MARK: - On-device narrative (used when Claude is unavailable)

    static func narrative(
        city: CityData,
        score: CityScore,
        priorCities: [RatedCity]
    ) -> Narrative {
        let placeScores = score.places.filter { $0.attraction.category != .general }
        let categories = score.breakdown
            .compactMap { key, value -> (AttractionCategory, Double)? in
                guard let category = AttractionCategory(rawValue: key), category != .general else { return nil }
                return (category, value)
            }
            .sorted { AttractionCategory.ranksAbove($0.0, $0.1, $1.0, $1.1) }

        let best = categories.first
        let weakest = categories.count > 1 ? categories.last : nil
        let top = placeScores.first
        let scoreText = ScoreFormat.string(score.cumulativeScore)
        let placeWord = placeScores.count == 1 ? "place" : "places"

        var sentences: [String] = []
        sentences.append("You rated \(placeScores.count) \(placeWord) in \(city.city) for an overall \(scoreText).")
        if let best {
            var line = "\(best.0.rawValue) stood out at \(ScoreFormat.string(best.1))"
            if let top, top.attraction.category == best.0 {
                line += ", led by \(top.attraction.name)"
            }
            if let weakest, weakest.1 < best.1 - 0.5 {
                line += ", while \(weakest.0.rawValue.lowercased()) landed softer at \(ScoreFormat.string(weakest.1))"
            }
            sentences.append(line + ".")
        }
        let others = priorCities.filter { $0.cityData.placeKey != city.placeKey }
        if !others.isEmpty {
            let average = others.map(\.cumulativeScore).reduce(0, +) / Double(others.count)
            let delta = score.cumulativeScore - average
            if abs(delta) >= 0.3 {
                let direction = delta > 0 ? "above" : "below"
                sentences.append("That puts it \(direction) your usual \(ScoreFormat.string(average)).")
            } else {
                sentences.append("That’s right in line with your usual \(ScoreFormat.string(average)).")
            }
        }

        let highlight: String
        if let top {
            highlight = "\(top.attraction.name) was your top pick in \(city.city)."
        } else {
            highlight = "\(city.city)’s overall feel is what stayed with you."
        }

        let strong = categories.filter { $0.1 >= 7 }.prefix(2).map { travellerPhrase(for: $0.0) }
        let wouldRecommendIf: String
        if strong.isEmpty {
            wouldRecommendIf = "Worth a visit if \(city.city) is already on your route, rather than a trip in itself."
        } else {
            wouldRecommendIf = "Best for travellers who \(strong.joined(separator: " and "))."
        }

        return Narrative(
            summary: sentences.joined(separator: " "),
            highlight: highlight,
            wouldRecommendIf: wouldRecommendIf
        )
    }

    private static func travellerPhrase(for category: AttractionCategory) -> String {
        switch category {
        case .culture: return "love museums and local culture"
        case .nature: return "seek out parks and green space"
        case .food: return "plan trips around food and markets"
        case .neighbourhood: return "like exploring neighbourhoods on foot"
        case .experience: return "collect hands-on experiences"
        case .landmark: return "chase big views and landmarks"
        case .general: return "care about a city’s overall feel"
        }
    }

    // MARK: - Taste analysis

    /// Average place score per category across every rated city.
    static func categoryAverages(for cities: [RatedCity]) -> [AttractionCategory: Double] {
        var totals: [AttractionCategory: (sum: Double, count: Int)] = [:]
        for city in cities {
            for place in city.scoredPlaces {
                let current = totals[place.attraction.category] ?? (0, 0)
                totals[place.attraction.category] = (current.sum + place.score, current.count + 1)
            }
        }
        return totals.mapValues { $0.sum / Double($0.count) }
    }

    /// Place categories ordered by how much the user favours them.
    ///
    /// Averages are pulled slightly toward the user's overall mean, so a category with a single
    /// lucky rating doesn't outrank one they have loved again and again.
    static func rankedCategories(for cities: [RatedCity]) -> [(category: AttractionCategory, average: Double, count: Int)] {
        var totals: [AttractionCategory: (sum: Double, count: Int)] = [:]
        for city in cities {
            for place in city.scoredPlaces where place.attraction.category != .general {
                let current = totals[place.attraction.category] ?? (0, 0)
                totals[place.attraction.category] = (current.sum + place.score, current.count + 1)
            }
        }
        let allCount = totals.values.reduce(0) { $0 + $1.count }
        guard allCount > 0 else { return [] }
        let overallMean = totals.values.reduce(0) { $0 + $1.sum } / Double(allCount)

        func adjusted(_ value: (sum: Double, count: Int)) -> Double {
            (value.sum + overallMean) / Double(value.count + 1)
        }
        return totals
            .sorted { lhs, rhs in
                AttractionCategory.ranksAbove(lhs.key, adjusted(lhs.value), rhs.key, adjusted(rhs.value))
            }
            .map { (category: $0.key, average: $0.value.sum / Double($0.value.count), count: $0.value.count) }
    }

    /// The category the user favours most.
    static func favouriteCategory(for cities: [RatedCity]) -> AttractionCategory? {
        rankedCategories(for: cities).first?.category
    }

    /// Builds a travel personality and recommendations without calling an AI service.
    static func travelProfile(from cities: [RatedCity]) -> TravelProfile {
        let averages = categoryAverages(for: cities).filter { $0.key != .general }
        let ranked = rankedCategories(for: cities).map { (key: $0.category, value: $0.average) }
        guard !ranked.isEmpty else { return .placeholder }

        let primary = ranked[0].key
        let secondary = ranked.count > 1 ? ranked[1].key : nil

        let personality = personalityName(for: primary)
        var description = "You’re happiest when a trip is built around \(focusPhrase(for: primary))"
        if let secondary {
            description += ", with \(focusPhrase(for: secondary)) close behind"
        }
        description += ". "
        if let weakest = ranked.last, ranked.count > 2, weakest.value < ranked[0].value - 1 {
            description += "\(weakest.key.shortName) matter less to you than to most travellers."
        } else {
            description += "You rate cities on how they feel day to day, not just their headline sights."
        }

        var traits: [String] = []
        for (category, _) in ranked.prefix(3) {
            traits.append(contentsOf: traitNames(for: category))
        }
        if let landmarks = averages[.landmark], let best = ranked.first?.value, landmarks < best - 1.5 {
            traits.append("Hidden Gems")
        }
        var uniqueTraits: [String] = []
        for trait in traits where !uniqueTraits.contains(trait) {
            uniqueTraits.append(trait)
        }

        return TravelProfile(
            personalityType: personality,
            personalityDescription: description,
            tasteTraits: Array(uniqueTraits.prefix(5)),
            recommendations: recommendations(for: averages, visited: cities)
        )
    }

    /// Ranks catalogue destinations by how well they fit the user's category preferences.
    static func recommendations(
        for averages: [AttractionCategory: Double],
        visited: [RatedCity],
        limit: Int = 5
    ) -> [DestinationRecommendation] {
        let visitedCities = Set(visited.map { $0.cityData.city.lowercased() })
        let values = Array(averages.values)
        guard let low = values.min(), let high = values.max() else { return [] }
        let spread = max(0.5, high - low)

        // Preference weight per category: 0.25 (least favourite) … 1.25 (favourite). Unrated → neutral.
        func preference(_ category: AttractionCategory) -> Double {
            guard let value = averages[category] else { return 0.6 }
            return 0.25 + (value - low) / spread
        }

        let scored: [(Destination, Double)] = Destination.catalogue
            .filter { !visitedCities.contains($0.city.lowercased()) }
            .map { destination in
                var sum = 0.0
                var total = 0.0
                for category in AttractionCategory.placeCategories {
                    let weight = preference(category)
                    sum += weight * (destination.affinity[category] ?? 0.5)
                    total += weight
                }
                return (destination, total > 0 ? sum / total : 0)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.city < rhs.0.city : lhs.1 > rhs.1
            }

        let favourites = averages
            .sorted { AttractionCategory.ranksAbove($0.key, $0.value, $1.key, $1.value) }
            .map(\.key)

        return scored.prefix(limit).map { destination, fit in
            let matching = favourites.first { (destination.affinity[$0] ?? 0) >= 0.8 } ?? favourites.first ?? .neighbourhood
            let reason = "You rate \(matching.rawValue.lowercased()) highly, and \(destination.city) is known for \(destination.knownFor)."
            return DestinationRecommendation(
                destination: "\(destination.city), \(destination.country)",
                matchReason: reason,
                vibeTags: destination.vibeTags,
                matchScore: clamp(5.5 + fit * 4.5)
            )
        }
    }

    private static func personalityName(for category: AttractionCategory) -> String {
        switch category {
        case .neighbourhood: return "The Slow Wanderer"
        case .food: return "The Flavour Chaser"
        case .culture: return "The Culture Vulture"
        case .nature: return "The Green Seeker"
        case .landmark: return "The Skyline Collector"
        case .experience: return "The Experience Hunter"
        case .general: return "The Balanced Voyager"
        }
    }

    private static func focusPhrase(for category: AttractionCategory) -> String {
        switch category {
        case .neighbourhood: return "walkable neighbourhoods"
        case .food: return "markets and memorable meals"
        case .culture: return "museums and local culture"
        case .nature: return "parks and time outdoors"
        case .landmark: return "big views and landmark sights"
        case .experience: return "hands-on experiences"
        case .general: return "a city’s overall feel"
        }
    }

    private static func traitNames(for category: AttractionCategory) -> [String] {
        switch category {
        case .neighbourhood: return ["Walkable Streets", "Local Rhythm"]
        case .food: return ["Street Food", "Market Mornings"]
        case .culture: return ["Museums", "Architecture"]
        case .nature: return ["Green Escapes", "Slow Afternoons"]
        case .landmark: return ["Big Views", "Iconic Sights"]
        case .experience: return ["Hands-On Experiences", "After Dark"]
        case .general: return ["Good Atmosphere"]
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(10, max(0, value))
    }
}
