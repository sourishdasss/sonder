import Foundation
import Testing
@testable import Sonder

@Suite("Scoring engine")
struct ScoringEngineTests {
    private func entry(
        _ name: String,
        _ category: AttractionCategory,
        _ sentiment: VisitSentiment,
        rank: Int,
        of count: Int
    ) -> CityVisitAttractionEntry {
        CityVisitAttractionEntry(
            attraction: Attraction(name: name, category: category),
            sentiment: sentiment,
            rankInCategory: rank,
            categoryCount: count
        )
    }

    @Test("A place's score stays inside its sentiment band")
    func itemScoreStaysInBand() {
        for sentiment in VisitSentiment.allCases {
            for count in 1...8 {
                for position in 0..<count {
                    let score = ScoringEngine.itemScore(sentiment: sentiment, positionInBucket: position, bucketCount: count)
                    #expect(sentiment.scoreBand.contains(score))
                }
            }
        }
    }

    @Test("Higher-ranked places in the same tier score higher")
    func itemScoreDecreasesWithRank() {
        let scores = (0..<5).map {
            ScoringEngine.itemScore(sentiment: .wouldReturn, positionInBucket: $0, bucketCount: 5)
        }
        #expect(scores == scores.sorted(by: >))
        #expect(Set(scores).count == 5)
    }

    @Test("Tiers never overlap: any loved place beats any 'fine' place")
    func tiersDoNotOverlap() {
        let worstLoved = ScoringEngine.itemScore(sentiment: .wouldReturn, positionInBucket: 9, bucketCount: 10)
        let bestFine = ScoringEngine.itemScore(sentiment: .decent, positionInBucket: 0, bucketCount: 10)
        let worstFine = ScoringEngine.itemScore(sentiment: .decent, positionInBucket: 9, bucketCount: 10)
        let bestWaste = ScoringEngine.itemScore(sentiment: .waste, positionInBucket: 0, bucketCount: 10)
        #expect(worstLoved > bestFine)
        #expect(worstFine > bestWaste)
    }

    @Test("A single place gets the middle of its band")
    func singlePlaceScore() {
        #expect(ScoringEngine.itemScore(sentiment: .wouldReturn, positionInBucket: 0, bucketCount: 1) == 8.75)
        #expect(ScoringEngine.itemScore(sentiment: .decent, positionInBucket: 0, bucketCount: 1) == 5.75)
        #expect(ScoringEngine.itemScore(sentiment: .waste, positionInBucket: 0, bucketCount: 1) == 2.5)
    }

    @Test("City score is the category-weighted average of place scores")
    func weightedCityScore() {
        // One loved neighbourhood (8.75 × 1.5) and one disliked landmark (2.5 × 0.8).
        let entries = [
            entry("Alfama", .neighbourhood, .wouldReturn, rank: 1, of: 1),
            entry("Belém Tower", .landmark, .waste, rank: 1, of: 1)
        ]
        let score = ScoringEngine.cityScore(for: entries)
        let expected = (8.75 * 1.5 + 2.5 * 0.8) / (1.5 + 0.8)
        #expect(abs(score.cumulativeScore - expected) < 0.0001)
        #expect(score.breakdown[AttractionCategory.neighbourhood.rawValue] == 8.75)
        #expect(score.breakdown[AttractionCategory.landmark.rawValue] == 2.5)
        #expect(score.topAttractionName == "Alfama")
    }

    @Test("General Appeal counts toward the score but is never the top pick")
    func generalAppealWeighting() {
        let places = [entry("Time Out Market", .food, .decent, rank: 1, of: 1)]
        let withVibe = places + [entry(Attraction.generalAppealName, .general, .wouldReturn, rank: 1, of: 1)]

        let base = ScoringEngine.cityScore(for: places)
        let boosted = ScoringEngine.cityScore(for: withVibe)
        #expect(boosted.cumulativeScore > base.cumulativeScore)
        #expect(boosted.topAttractionName == "Time Out Market")
        #expect(boosted.breakdown[AttractionCategory.general.rawValue] == 8.75)
    }

    @Test("An empty visit scores zero without crashing")
    func emptyVisit() {
        let score = ScoringEngine.cityScore(for: [])
        #expect(score.cumulativeScore == 0)
        #expect(score.breakdown.isEmpty)
        #expect(score.topAttractionName == nil)
    }

    @Test("Scores stay within 0–10")
    func scoreBounds() {
        let entries = AttractionCategory.placeCategories.enumerated().map { index, category in
            entry("Place \(index)", category, .wouldReturn, rank: 1, of: 1)
        }
        let score = ScoringEngine.cityScore(for: entries)
        #expect((0...10).contains(score.cumulativeScore))
        #expect(score.places.allSatisfy { (0...10).contains($0.score) })
    }

    @Test("The on-device narrative names the top pick and the city")
    func narrativeMentionsTopPick() {
        let city = CityData(city: "Lisbon", country: "Portugal")
        let score = ScoringEngine.cityScore(for: [
            entry("Alfama", .neighbourhood, .wouldReturn, rank: 1, of: 1),
            entry("Belém Tower", .landmark, .waste, rank: 1, of: 1)
        ])
        let narrative = ScoringEngine.narrative(city: city, score: score, priorCities: [])
        #expect(narrative.summary.contains("Lisbon"))
        #expect(narrative.highlight.contains("Alfama"))
        #expect(!narrative.wouldRecommendIf.isEmpty)
    }

    @Test("The travel profile reflects the strongest category and skips visited cities")
    func travelProfileFromRatings() {
        func foodCity(_ name: String) -> RatedCity {
            var draft = CityRatingDraft()
            draft.insert(Attraction(name: "\(name) Market", category: .food), sentiment: .wouldReturn)
            draft.insert(Attraction(name: "\(name) Tower", category: .landmark), sentiment: .waste)
            return RatedCity.build(city: CityData(city: name, country: "Testland"), draft: draft, priorCities: [])
        }
        let cities = [foodCity("Tokyo"), foodCity("Hanoi"), foodCity("Oaxaca")]
        let profile = ScoringEngine.travelProfile(from: cities)

        #expect(profile.personalityType == "The Flavour Chaser")
        #expect(profile.tasteTraits.count <= 5)
        #expect(!profile.tasteTraits.isEmpty)
        #expect(profile.recommendations.count == 5)
        let recommended = profile.recommendations.map { $0.destination.lowercased() }
        for visited in ["tokyo", "hanoi", "oaxaca"] {
            #expect(!recommended.contains { $0.hasPrefix(visited) })
        }
        #expect(profile.recommendations.allSatisfy { (0...10).contains($0.matchScore) })
        // Best match first.
        let scores = profile.recommendations.map(\.matchScore)
        #expect(scores == scores.sorted(by: >))
    }

    @Test("No ratings means the placeholder profile")
    func emptyProfileIsPlaceholder() {
        #expect(ScoringEngine.travelProfile(from: []).isPlaceholder)
    }

    @Test("Trending groups feed activity by city, most-rated first")
    func trendingRanking() {
        let user = UUID()
        func item(_ city: String, _ score: Double) -> FeedItem {
            FeedItem(userId: user, userName: "A", action: .visitedCity(placeCount: 3), city: city, country: "X", score: score)
        }
        let trending = TrendingCity.rank([item("Tokyo", 9), item("Paris", 8), item("Tokyo", 7)])
        #expect(trending.map(\.city) == ["Tokyo", "Paris"])
        #expect(trending[0].ratingCount == 2)
        #expect(trending[0].averageScore == 8)
    }
}
