import Foundation

struct TravelProfile: Equatable, Sendable {
    var personalityType: String
    var personalityDescription: String
    var tasteTraits: [String]
    var recommendations: [DestinationRecommendation]

    static let placeholder = TravelProfile(
        personalityType: "The Explorer",
        personalityDescription: "You’re still building your travel DNA. Rate places in a few cities to unlock your personality.",
        tasteTraits: [],
        recommendations: []
    )

    /// True until a real profile has been generated.
    var isPlaceholder: Bool { tasteTraits.isEmpty && recommendations.isEmpty }
}

struct DestinationRecommendation: Identifiable, Equatable, Sendable {
    let id: UUID
    let destination: String
    let matchReason: String
    let vibeTags: [String]
    /// 0–10 fit score.
    var matchScore: Double

    init(id: UUID = UUID(), destination: String, matchReason: String, vibeTags: [String], matchScore: Double = 0) {
        self.id = id
        self.destination = destination
        self.matchReason = matchReason
        self.vibeTags = vibeTags
        self.matchScore = matchScore
    }

    /// "92% match" style label, or nil when no score is available.
    var matchLabel: String? {
        guard matchScore > 0 else { return nil }
        return "\(Int((min(10, matchScore) * 10).rounded()))% match"
    }
}
