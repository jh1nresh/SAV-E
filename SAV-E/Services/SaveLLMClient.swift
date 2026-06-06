import Foundation

struct IntentParseRequest: Equatable {
    let query: String
    let allowedCategories: [PlaceCategory]
}

struct GroundedAnswerRequest: Equatable {
    let query: String
    let intent: SaveSearchIntent
    let allowedPlaceIds: [String]
    let sections: [SaveSearchSection]
    let outputLanguage: AppLanguage
}

struct SaveAgentPromptPolicy {
    static let productSoul = """
    SAV-E is a cute place-memory scout, not a generic travel or map chatbot.
    SAV-E captures messy place signals into Source Clues and Review Candidates, then helps the user decide from confirmed Map Stamps.
    Default answer from the user's private place memory first; public discovery second and clearly labeled.
    """

    static let hardBoundaries = """
    Hard boundaries:
    - Use ONLY allowed result IDs. Do not introduce or invent places outside the allowed results.
    - Keep Saved Map Stamps, Review Candidates, Source-only clues, and Public Discovery separate.
    - Never treat a Review Candidate, Source-only clue, or Public Discovery result as a confirmed Map Stamp.
    - If there are no allowed result IDs, do not name a place. Explain what SAV-E is missing and ask one bounded follow-up.
    - Evidence lines starting with "Search:" are retrieval context, not proof that the place serves the requested item.
    """

    static let specialtyEvidenceRules = """
    Specific item gates:
    - If the query asks for hot pot, shabu, boba, milk tea, or another specific item, only call a place a match when its title, address, dish clues, note, or non-search evidence explicitly mentions that item.
    - Do not treat generic restaurants as hot pot matches.
    - Do not treat generic cafes or coffee shops as boba or milk-tea matches.
    """

    static let outputContract = """
    Output contract:
    - Answer in the requested output language exactly.
    - Sound like a concise assistant, not a debug report.
    - Recommend one best place first when a trustworthy allowed result exists.
    - Explain the reason using state, distance, rating/review count, and evidence.
    - Ask at most one lightweight follow-up question.
    - Do not use headings like "Why:" or "Next:".
    - Keep it under 70 words.
    """

    func groundedAnswerPrompt(for request: GroundedAnswerRequest) -> String {
        """
        \(Self.productSoul)

        Allowed result IDs:
        \(request.allowedPlaceIds.isEmpty ? "none" : request.allowedPlaceIds.joined(separator: ", "))

        User query:
        \(request.query)

        Output language:
        \(request.outputLanguage.serviceOutputInstruction)

        Grounded sections:
        \(sectionSummary(request.sections))

        \(Self.hardBoundaries)

        \(Self.specialtyEvidenceRules)

        \(Self.outputContract)
        """
    }

    func sectionSummary(_ sections: [SaveSearchSection]) -> String {
        sections.map { section in
            let rows = section.results.prefix(5).map { result in
                let evidence = result.evidence.prefix(3).joined(separator: " | ")
                let facts = [
                    "id=\(result.id)",
                    "title=\(result.title)",
                    "state=\(result.objectType.displayName)/\(result.userState.displayName)",
                    result.distanceLabel.map { "distance=\($0)" },
                    result.rating.map { String(format: "rating=%.1f", $0) },
                    result.reviewCount.map { "reviews=\($0)" },
                    evidence.isEmpty ? nil : "evidence=\(evidence)"
                ].compactMap { $0 }
                return "  - " + facts.joined(separator: "; ")
            }
            let empty = section.emptyMessage.map { "empty=\($0)" }
            let searchAction = section.showsNearbySearchAction ? "action=can_search_public_nearby" : nil
            let footer = [empty, searchAction].compactMap { $0 }.map { "  - \($0)" }
            let body = rows.isEmpty && footer.isEmpty ? ["  - none"] : rows + footer
            return "- \(section.title) [\(section.id)]:\n\(body.joined(separator: "\n"))"
        }
        .joined(separator: "\n")
    }
}

protocol SaveLLMClient {
    func parseIntent(_ request: IntentParseRequest) async throws -> SaveSearchIntent
    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> String
}

struct DeterministicSaveIntentParser: SaveLLMClient {
    private let parser: SaveSearchIntentParser

    init(parser: SaveSearchIntentParser = SaveSearchIntentParser()) {
        self.parser = parser
    }

    func parseIntent(_ request: IntentParseRequest) async throws -> SaveSearchIntent {
        guard let intent = parser.parse(request.query) else {
            throw SaveSearchIntentValidationError.malformedJSON
        }
        return intent
    }

    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> String {
        if request.sections.allSatisfy(\.results.isEmpty) {
            return "No matching Map Stamps passed the category and location gates."
        }
        return request.sections
            .filter { !$0.results.isEmpty }
            .map { "\($0.title): \($0.results.count)" }
            .joined(separator: "\n")
    }
}

final class GeminiSaveLLMClient: SaveLLMClient {
    private let apiKey: String
    private let modelFallbacks: [String]
    private let validator: SaveSearchIntentJSONValidator
    private let promptPolicy: SaveAgentPromptPolicy
    private let session: URLSession

    init(
        apiKey: String,
        modelFallbacks: [String] = SAVEProductionConfig.defaultGeminiModelFallbacks,
        validator: SaveSearchIntentJSONValidator = SaveSearchIntentJSONValidator(),
        promptPolicy: SaveAgentPromptPolicy = SaveAgentPromptPolicy(),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.modelFallbacks = modelFallbacks
        self.validator = validator
        self.promptPolicy = promptPolicy
        self.session = session
    }

    static func liveFromConfig() -> GeminiSaveLLMClient? {
        let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? SAVEProductionConfig.configValue(for: ["GEMINI_API_KEY"])
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return GeminiSaveLLMClient(apiKey: apiKey)
    }

    func parseIntent(_ request: IntentParseRequest) async throws -> SaveSearchIntent {
        let allowed = request.allowedCategories.map(\.rawValue)
        let payload: [String: Any] = [
            "task": "parse_user_place_query",
            "allowedCategories": allowed,
            "query": request.query
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
        let prompt = """
        Respond ONLY with strict JSON. No markdown.
        Input:
        \(payloadJSON)

        Output schema:
        {
          "kind": "explicitPlaceSearch|categoryRecommendation|craving|tripPlanning|publicDiscovery|unknown",
          "requiredCategories": ["food|cafe|bar|attraction|stay|shopping"],
          "optionalCategories": [],
          "locationMode": {"type": "currentLocation|mapRegion|namedArea|savedAnywhere|unspecified", "radiusMeters": 2000, "area": null},
          "sourceScope": "savedOnly|savedFirstAllowPublicFallback|publicOnly",
          "mustMatchCategory": true,
          "mustMatchLocation": true,
          "confidence": 0.0
        }
        """
        let text = try await generateText(prompt: prompt, temperature: 0, maxOutputTokens: 512)
        return try validator.parseIntentJSON(extractJSONObject(from: text), rawText: request.query)
    }

    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> String {
        let prompt = promptPolicy.groundedAnswerPrompt(for: request)
        return try await generateText(prompt: prompt, temperature: 0.2, maxOutputTokens: 384)
    }

    private func generateText(prompt: String, temperature: Double, maxOutputTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": temperature, "maxOutputTokens": maxOutputTokens]
        ]
        let requestBody = try JSONSerialization.data(withJSONObject: body)

        for model in modelFallbacks {
            let endpoint = SAVEProductionConfig.geminiGenerateContentURL(apiKey: apiKey, model: model)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { continue }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 || http.statusCode == 429 { continue }
                throw SaveAIError.apiError(http.statusCode)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                throw SaveAIError.emptyResponse
            }
            return text
        }
        throw SaveAIError.apiError(0)
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound else {
            return text
        }
        return String(text[start.lowerBound..<end.upperBound])
    }
}
