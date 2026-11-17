import Foundation

extension RatedCity {
    /// Scores a rating draft and produces the city record (with on-device copy).
    ///
    /// - Parameters:
    ///   - id: Pass the existing id when re-rating a city so the saved row is updated in place.
    ///   - narrative: Optional AI-written copy; defaults to the on-device narrative.
    static func build(
        id: UUID = UUID(),
        city: CityData,
        draft: CityRatingDraft,
        priorCities: [RatedCity],
        narrative: ScoringEngine.Narrative? = nil,
        createdAt: Date? = nil
    ) -> RatedCity {
        let entries = draft.entries
        let score = ScoringEngine.cityScore(for: entries)
        let copy = narrative ?? ScoringEngine.narrative(city: city, score: score, priorCities: priorCities)

        var cityData = city
        cityData.attractions = draft.allAttractions

        return RatedCity(
            id: id,
            cityData: cityData,
            cumulativeScore: score.cumulativeScore,
            summary: copy.summary,
            highlight: copy.highlight,
            wouldRecommendIf: copy.wouldRecommendIf,
            scoreBreakdown: score.breakdown,
            ratings: entries.map {
                AttractionRating(
                    attractionId: $0.attraction.id,
                    sentiment: $0.sentiment,
                    rankAmongSimilar: $0.rankInCategory
                )
            },
            topAttractionName: score.topAttractionName,
            createdAt: createdAt
        )
    }

    /// Returns a copy with different written copy (used when Claude's narrative arrives).
    func with(narrative: ScoringEngine.Narrative) -> RatedCity {
        var copy = self
        copy.summary = narrative.summary
        copy.highlight = narrative.highlight
        copy.wouldRecommendIf = narrative.wouldRecommendIf
        return copy
    }
}
