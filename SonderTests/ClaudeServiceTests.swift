import Foundation
import Testing
@testable import Sonder

/// Intercepts requests so the Claude service can be tested without the network.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    nonisolated(unsafe) static var queue: [Stub] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    private static let lock = NSLock()

    static func reset(_ stubs: [Stub]) {
        lock.lock()
        defer { lock.unlock() }
        queue = stubs
        requests = []
        bodies = []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(of: request))
        let stub = Self.queue.isEmpty ? Stub(status: 500, body: Data()) : Self.queue.removeFirst()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream, so read it back out.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// Serialized: the stub protocol shares static state between tests.
@Suite("Claude service", .serialized)
struct ClaudeServiceTests {
    private func messageBody(text: String, stopReason: String = "end_turn", leadingThinking: Bool = false) -> Data {
        var content: [[String: Any]] = []
        if leadingThinking {
            content.append(["type": "thinking", "thinking": "", "signature": "sig"])
        }
        content.append(["type": "text", "text": text])
        let payload: [String: Any] = [
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-5-5",
            "content": content,
            "stop_reason": stopReason
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private var sampleScore: ScoringEngine.CityScore {
        ScoringEngine.cityScore(for: [
            CityVisitAttractionEntry(
                attraction: Attraction(name: "Alfama", category: .neighbourhood),
                sentiment: .wouldReturn, rankInCategory: 1, categoryCount: 1
            )
        ])
    }

    private let lisbon = CityData(city: "Lisbon", country: "Portugal")

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func service(model: String = "claude-sonnet-5-5", key: String = "test-key", retries: Int = 0) -> ClaudeService {
        ClaudeService(apiKey: key, model: model, session: StubURLProtocol.makeSession(), maxRetries: retries)
    }

    @Test("Requests use the Messages API with structured output and no sampling parameters")
    func requestShape() throws {
        let request = try service().makeRequest(system: "sys", user: "hello", schema: ClaudeService.narrativeSchema)

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try jsonObject(request.httpBody)
        #expect(body["model"] as? String == "claude-sonnet-5-5")
        #expect(body["system"] as? String == "sys")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["temperature"] == nil)
        #expect(body["top_p"] == nil)
        #expect(body["thinking"] == nil)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "hello")

        let outputConfig = try #require(body["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test("Models without server-side fallback don't send the fallback parameter")
    func fallbackOnlyWhereSupported() throws {
        let request = try service(model: "claude-haiku-5-5")
            .makeRequest(system: "s", user: "u", schema: ClaudeService.narrativeSchema)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let body = try jsonObject(request.httpBody)
        #expect(body["fallbacks"] == nil)
    }

    @Test("A missing key fails fast without a network call")
    func missingKey() async {
        StubURLProtocol.reset([])
        await #expect(throws: ClaudeService.ClaudeError.missingAPIKey) {
            _ = try await service(key: "").cityNarrative(city: lisbon, score: sampleScore, priorCities: [])
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("A city narrative is parsed from the text block, even after a thinking block")
    func parsesNarrative() async throws {
        let json = #"{"summary":" You loved Alfama. ","highlight":"Alfama stole the show.","would_recommend_if":"You like to wander."}"#
        StubURLProtocol.reset([.init(status: 200, body: messageBody(text: json, leadingThinking: true))])

        let narrative = try await service().cityNarrative(city: lisbon, score: sampleScore, priorCities: [])
        #expect(narrative.summary == "You loved Alfama.")
        #expect(narrative.highlight == "Alfama stole the show.")
        #expect(narrative.wouldRecommendIf == "You like to wander.")

        // The prompt carries the user's actual ratings.
        let sent = try jsonObject(StubURLProtocol.bodies.first)
        let prompt = try #require((sent["messages"] as? [[String: Any]])?.first?["content"] as? String)
        #expect(prompt.contains("Lisbon, Portugal"))
        #expect(prompt.contains("Alfama"))
        #expect(prompt.contains("loved it"))
    }

    @Test("A refusal is surfaced as an error, not parsed as content")
    func refusal() async {
        StubURLProtocol.reset([.init(status: 200, body: messageBody(text: "", stopReason: "refusal"))])
        await #expect(throws: ClaudeService.ClaudeError.refused) {
            _ = try await service().cityNarrative(city: lisbon, score: sampleScore, priorCities: [])
        }
    }

    @Test("A truncated answer is surfaced as an error")
    func truncation() async {
        StubURLProtocol.reset([.init(status: 200, body: messageBody(text: "{\"summary\":", stopReason: "max_tokens"))])
        await #expect(throws: ClaudeService.ClaudeError.truncated) {
            _ = try await service().cityNarrative(city: lisbon, score: sampleScore, priorCities: [])
        }
    }

    @Test("Client errors are not retried and report the API message")
    func clientErrorNotRetried() async {
        let error = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        StubURLProtocol.reset([.init(status: 401, body: Data(error.utf8))])
        await #expect(throws: ClaudeService.ClaudeError.http(status: 401, message: "invalid x-api-key")) {
            _ = try await service(retries: 2).cityNarrative(city: lisbon, score: sampleScore, priorCities: [])
        }
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("Overload responses are retried and then succeed")
    func retriesOverload() async throws {
        let json = #"{"summary":"Good.","highlight":"H","would_recommend_if":"W"}"#
        StubURLProtocol.reset([
            .init(status: 529, body: Data(), headers: ["retry-after": "0"]),
            .init(status: 200, body: messageBody(text: json))
        ])
        let narrative = try await service(retries: 2).cityNarrative(city: lisbon, score: sampleScore, priorCities: [])
        #expect(narrative.summary == "Good.")
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("Profiles drop already-visited cities, cap at five and sort by match")
    func parsesTravelProfile() async throws {
        func recommendation(_ destination: String, _ score: Double) -> [String: Any] {
            ["destination": destination, "match_reason": "Because.", "vibe_tags": ["a", "b", "c", "d"], "match_score": score]
        }
        let payload: [String: Any] = [
            "personality_type": "The Slow Wanderer",
            "personality_description": "You wander.",
            "taste_traits": ["1", "2", "3", "4", "5", "6"],
            "recommendations": [
                recommendation("Lisbon, Portugal", 9.9),   // already visited: must be dropped
                recommendation("Porto, Portugal", 8.0),
                recommendation("Hanoi, Vietnam", 9.5),
                recommendation("Oaxaca, Mexico", 12.0),    // out of range: must be clamped
                recommendation("Seoul, South Korea", 7.0),
                recommendation("Rome, Italy", 6.0),
                recommendation("Vienna, Austria", 5.0)
            ]
        ]
        let text = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        StubURLProtocol.reset([.init(status: 200, body: messageBody(text: text))])

        var draft = CityRatingDraft()
        draft.insert(Attraction(name: "Alfama", category: .neighbourhood), sentiment: .wouldReturn)
        let visited = RatedCity.build(city: lisbon, draft: draft, priorCities: [])

        let profile = try await service().travelProfile(for: [visited])
        #expect(profile.personalityType == "The Slow Wanderer")
        #expect(profile.tasteTraits.count == 5)
        #expect(profile.recommendations.count == 5)
        #expect(!profile.recommendations.contains { $0.destination.hasPrefix("Lisbon") })
        #expect(profile.recommendations.first?.destination == "Oaxaca, Mexico")
        #expect(profile.recommendations.first?.matchScore == 10)
        #expect(profile.recommendations.allSatisfy { $0.vibeTags.count <= 3 })
    }
}
