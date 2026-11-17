import Foundation

/// Writes personalised copy with the Claude Messages API.
///
/// Scores are always computed on-device by `ScoringEngine`, so they stay deterministic and match
/// what the app shows per place; Claude turns those numbers into a summary and a taste profile.
/// Every caller falls back to `ScoringEngine`'s on-device copy when this service throws.
struct ClaudeService: Sendable {
    enum ClaudeError: LocalizedError, Equatable {
        case missingAPIKey
        case http(status: Int, message: String)
        case refused
        case truncated
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No Anthropic API key is configured."
            case .http(let status, let message): return "Claude request failed (\(status)): \(message)"
            case .refused: return "Claude declined to answer this request."
            case .truncated: return "Claude’s answer was cut short."
            case .emptyResponse: return "Claude returned an empty answer."
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: String
    let model: String
    let session: URLSession
    let maxRetries: Int

    init(
        apiKey: String = Config.anthropicAPIKey,
        model: String = Config.claudeModel,
        session: URLSession = .shared,
        maxRetries: Int = 2
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.maxRetries = maxRetries
    }

    var isAvailable: Bool { !apiKey.isEmpty }

    // MARK: - City narrative

    private struct NarrativePayload: Decodable {
        let summary: String
        let highlight: String
        let wouldRecommendIf: String

        enum CodingKeys: String, CodingKey {
            case summary
            case highlight
            case wouldRecommendIf = "would_recommend_if"
        }
    }

    func cityNarrative(
        city: CityData,
        score: ScoringEngine.CityScore,
        priorCities: [RatedCity]
    ) async throws -> ScoringEngine.Narrative {
        let payload: NarrativePayload = try await send(
            system: Self.analystSystemPrompt,
            user: Self.cityPrompt(city: city, score: score, priorCities: priorCities),
            schema: Self.narrativeSchema
        )
        let summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw ClaudeError.emptyResponse }
        return ScoringEngine.Narrative(
            summary: summary,
            highlight: payload.highlight.trimmingCharacters(in: .whitespacesAndNewlines),
            wouldRecommendIf: payload.wouldRecommendIf.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Travel profile

    private struct ProfilePayload: Decodable {
        struct Recommendation: Decodable {
            let destination: String
            let matchReason: String
            let vibeTags: [String]
            let matchScore: Double

            enum CodingKeys: String, CodingKey {
                case destination
                case matchReason = "match_reason"
                case vibeTags = "vibe_tags"
                case matchScore = "match_score"
            }
        }

        let personalityType: String
        let personalityDescription: String
        let tasteTraits: [String]
        let recommendations: [Recommendation]

        enum CodingKeys: String, CodingKey {
            case personalityType = "personality_type"
            case personalityDescription = "personality_description"
            case tasteTraits = "taste_traits"
            case recommendations
        }
    }

    func travelProfile(for cities: [RatedCity]) async throws -> TravelProfile {
        let payload: ProfilePayload = try await send(
            system: Self.tasteSystemPrompt,
            user: Self.profilePrompt(cities: cities),
            schema: Self.profileSchema
        )
        let visited = Set(cities.map { $0.cityData.city.lowercased() })
        let recommendations = payload.recommendations
            .filter { recommendation in
                let cityName = recommendation.destination
                    .split(separator: ",").first
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
                return !cityName.isEmpty && !visited.contains(cityName)
            }
            .sorted { $0.matchScore > $1.matchScore }
            .prefix(5)
            .map {
                DestinationRecommendation(
                    destination: $0.destination,
                    matchReason: $0.matchReason,
                    vibeTags: Array($0.vibeTags.prefix(3)),
                    matchScore: min(10, max(0, $0.matchScore))
                )
            }
        let type = payload.personalityType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, !recommendations.isEmpty else { throw ClaudeError.emptyResponse }
        return TravelProfile(
            personalityType: type,
            personalityDescription: payload.personalityDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            tasteTraits: Array(payload.tasteTraits.prefix(5)),
            recommendations: Array(recommendations)
        )
    }

    // MARK: - Prompts

    static let analystSystemPrompt = """
    You are the travel analyst inside Sonder, an app where people rate individual places within a city \
    instead of the city as a whole. Users do not give stars: they mark each place as "loved it", \
    "it was fine" or "not for me", then rank similar places head-to-head. Sonder turns that into scores \
    out of 10, which are given to you and are final.

    Write for the person who made these ratings, in the second person. Be warm, specific and concise. \
    Refer to their places by name and reflect what the numbers actually say, including the weaker spots. \
    Only mention places that appear in the ratings. Plain prose, no emoji, no markdown.
    """

    static let tasteSystemPrompt = """
    You are the travel taste expert inside Sonder, an app where people rate individual places within \
    cities. From a user's ratings you infer their travel personality and recommend where to go next. \
    Scores are out of 10 and already computed.

    Ground everything in the rating patterns you are given: what they score highly, what leaves them \
    cold, and which specific places they loved. Recommend real cities they have not visited yet. \
    Plain prose, no emoji, no markdown.
    """

    static func cityPrompt(
        city: CityData,
        score: ScoringEngine.CityScore,
        priorCities: [RatedCity]
    ) -> String {
        var lines: [String] = []
        lines.append("City: \(city.displayName)")
        lines.append("Overall score: \(ScoreFormat.string(score.cumulativeScore)) / 10")

        let categories = score.breakdown
            .filter { $0.key != AttractionCategory.general.rawValue }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) \(ScoreFormat.string($0.value))" }
        if !categories.isEmpty {
            lines.append("Category scores: \(categories.joined(separator: "; "))")
        }

        lines.append("")
        lines.append("Places, best first within each category:")
        let places = score.places
            .filter { $0.attraction.category != .general }
            .sorted { lhs, rhs in
                if lhs.attraction.category != rhs.attraction.category {
                    return lhs.attraction.category.rawValue < rhs.attraction.category.rawValue
                }
                return lhs.rank < rhs.rank
            }
        for place in places {
            lines.append(
                "- [\(place.attraction.category.rawValue)] #\(place.rank) \(place.attraction.name): "
                + "\(place.sentiment.shortLabel.lowercased()) (\(ScoreFormat.string(place.score)))"
            )
        }
        if let vibe = score.places.first(where: { $0.attraction.category == .general }) {
            lines.append("")
            lines.append("Overall feel of the city (walkability, atmosphere, getting around): \(vibe.sentiment.shortLabel.lowercased())")
        }

        let others = priorCities.filter { $0.cityData.placeKey != city.placeKey }
        if !others.isEmpty {
            let average = others.map(\.cumulativeScore).reduce(0, +) / Double(others.count)
            lines.append("")
            lines.append("For context, their average across \(others.count) other rated \(others.count == 1 ? "city" : "cities") is \(ScoreFormat.string(average)).")
        }

        lines.append("")
        lines.append("""
        Write three things:
        - summary: 2-3 sentences on their experience of this city, referencing their specific ratings.
        - highlight: one sentence on the single best thing about the city for them.
        - would_recommend_if: one sentence describing the kind of traveller who would love this city, based on what they rated highly.
        """)
        return lines.joined(separator: "\n")
    }

    static func profilePrompt(cities: [RatedCity]) -> String {
        var lines: [String] = ["The user has rated places across these cities:", ""]
        for city in cities.sorted(by: { $0.cumulativeScore > $1.cumulativeScore }).prefix(25) {
            let breakdown = city.sortedBreakdown.filter { $0.category != .general }
            let strongest = breakdown.prefix(2)
                .map { "\($0.category.rawValue) (\(ScoreFormat.string($0.score)))" }
                .joined(separator: ", ")
            var line = "\(city.cityData.displayName): \(ScoreFormat.string(city.cumulativeScore))/10."
            if !strongest.isEmpty { line += " Strongest: \(strongest)." }
            if breakdown.count > 2, let weakest = breakdown.last {
                line += " Weakest: \(weakest.category.rawValue) (\(ScoreFormat.string(weakest.score)))."
            }
            if let top = city.topAttractionName, !top.isEmpty { line += " Top pick: \(top)." }
            lines.append(line)
        }

        let averages = ScoringEngine.categoryAverages(for: cities)
            .filter { $0.key != .general }
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .map { "\($0.key.rawValue) \(ScoreFormat.string($0.value))" }
        if !averages.isEmpty {
            lines.append("")
            lines.append("Average place score by category across all cities: \(averages.joined(separator: "; "))")
        }

        lines.append("")
        lines.append("Already visited (never recommend these): \(cities.map(\.cityData.city).joined(separator: ", "))")
        lines.append("")
        lines.append("""
        Return:
        - personality_type: a short title in the style of "The Slow Wanderer".
        - personality_description: 2 sentences on their travel style and what they seek.
        - taste_traits: exactly 5 short tags of 1-3 words each (for example "Walkable Streets").
        - recommendations: exactly 5 cities they have not visited, sorted by match_score descending. \
        For each: destination as "City, Country"; match_reason as one sentence referencing their rating \
        patterns; vibe_tags as exactly 3 short tags; match_score from 0 to 10.
        """)
        return lines.joined(separator: "\n")
    }

    // MARK: - Schemas (structured outputs)

    static var narrativeSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "summary": ["type": "string"],
                "highlight": ["type": "string"],
                "would_recommend_if": ["type": "string"]
            ],
            "required": ["summary", "highlight", "would_recommend_if"],
            "additionalProperties": false
        ]
    }

    static var profileSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "personality_type": ["type": "string"],
                "personality_description": ["type": "string"],
                "taste_traits": ["type": "array", "items": ["type": "string"]],
                "recommendations": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "destination": ["type": "string"],
                            "match_reason": ["type": "string"],
                            "vibe_tags": ["type": "array", "items": ["type": "string"]],
                            "match_score": ["type": "number"]
                        ],
                        "required": ["destination", "match_reason", "vibe_tags", "match_score"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "required": ["personality_type", "personality_description", "taste_traits", "recommendations"],
            "additionalProperties": false
        ]
    }

    // MARK: - Transport

    /// Models that accept the server-side refusal fallback parameter.
    private var supportsServerFallback: Bool {
        ["claude-sonnet-5-5", "claude-opus-5", "claude-fable-5"].contains { model.hasPrefix($0) }
    }

    func makeRequest(system: String, user: String, schema: [String: Any]) throws -> URLRequest {
        guard isAvailable else { throw ClaudeError.missingAPIKey }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema]
            ] as [String: Any]
        ]
        if supportsServerFallback {
            body["fallbacks"] = "default"
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if supportsServerFallback {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct MessageEnvelope: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }

    private func send<T: Decodable>(system: String, user: String, schema: [String: Any]) async throws -> T {
        let request = try makeRequest(system: system, user: user, schema: schema)
        var attempt = 0

        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClaudeError.emptyResponse }

            if (200..<300).contains(http.statusCode) {
                return try Self.decode(T.self, from: data)
            }

            // 429 (rate limit), 5xx and 529 (overloaded) are transient; everything else is not.
            let retryable = http.statusCode == 429 || http.statusCode >= 500
            if retryable, attempt < maxRetries {
                attempt += 1
                let header = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                let delay = min(header ?? pow(2, Double(attempt)) * 0.5, 6)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }

            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
            throw ClaudeError.http(status: http.statusCode, message: message ?? "Unexpected response")
        }
    }

    /// Reads the text blocks of a Messages response and decodes them as JSON.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
        // Always check the stop reason first: a refusal or truncation may not match the schema.
        switch envelope.stopReason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        // A response can begin with thinking blocks, so pick out text blocks by type.
        let text = envelope.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.emptyResponse }
        return try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }
}
