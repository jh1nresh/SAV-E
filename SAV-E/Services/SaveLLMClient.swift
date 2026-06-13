import CoreLocation
import Foundation

struct IntentParseRequest: Equatable {
    let query: String
    let allowedCategories: [PlaceCategory]
}

/// Bounded user context that travels with a grounded-answer request.
/// Privacy: only place names, categories, and city/area go to the LLM —
/// never private notes, full addresses, or precise coordinates.
struct GroundedAnswerContext: Equatable {
    var localityHint: String?
    var savedPlaceDigest: [String] = []
    var recentConversation: [String] = []

    var isEmpty: Bool {
        localityHint == nil && savedPlaceDigest.isEmpty && recentConversation.isEmpty
    }

    /// Place names mentioned in the digest. Used to keep the LLM from
    /// recommending digest places that are not allowed grounded results.
    var digestPlaceNames: [String] {
        savedPlaceDigest.compactMap { line in
            let name = line.components(separatedBy: " — ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? name : nil
        }
    }
}

struct GroundedAnswerRequest: Equatable {
    let query: String
    let intent: SaveSearchIntent
    let allowedPlaceIds: [String]
    let sections: [SaveSearchSection]
    let outputLanguage: AppLanguage
    var context: GroundedAnswerContext = GroundedAnswerContext()
}

/// Builds the bounded `GroundedAnswerContext` from drawer state.
/// Pure functions so prompt context stays unit-testable without network.
struct SaveDrawerContextBuilder {
    static let maxDigestEntries = 8
    static let maxDigestLineLength = 80
    static let maxRecentQueries = 3
    static let maxRecentQueryLength = 160
    static let maxAssistantAnswerLength = 200

    static func makeContext(
        query: String,
        places: [Place],
        currentLocation: CLLocation?,
        recentQueries: [String] = [],
        lastAssistantAnswer: String? = nil
    ) -> GroundedAnswerContext {
        GroundedAnswerContext(
            localityHint: localityHint(places: places, currentLocation: currentLocation),
            savedPlaceDigest: savedPlaceDigest(query: query, places: places, currentLocation: currentLocation),
            recentConversation: recentConversation(
                recentQueries: recentQueries,
                lastAssistantAnswer: lastAssistantAnswer
            )
        )
    }

    static func savedPlaceDigest(
        query: String,
        places: [Place],
        currentLocation: CLLocation?
    ) -> [String] {
        let scored = places
            .map { (place: $0, score: relevanceScore(query: query, place: $0, currentLocation: currentLocation)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.place.createdAt > rhs.place.createdAt
            }
        return scored
            .prefix(maxDigestEntries)
            .map { digestLine(for: $0.place) }
    }

    static func digestLine(for place: Place) -> String {
        let pieces = [
            String(place.name.prefix(40)),
            [place.category.displayName, cityOrArea(from: place.address)]
                .compactMap { $0 }
                .joined(separator: ", ")
        ]
        return String(pieces.filter { !$0.isEmpty }.joined(separator: " — ").prefix(maxDigestLineLength))
    }

    static func localityHint(places: [Place], currentLocation: CLLocation?) -> String? {
        let candidates: [Place]
        if let currentLocation {
            candidates = places
                .sorted {
                    distance(from: currentLocation, to: $0) < distance(from: currentLocation, to: $1)
                }
                .prefix(10)
                .map { $0 }
        } else {
            candidates = places
        }
        let cities = candidates.compactMap { cityOrArea(from: $0.address) }
        guard !cities.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for city in cities { counts[city, default: 0] += 1 }
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }

    static func recentConversation(recentQueries: [String], lastAssistantAnswer: String?) -> [String] {
        var lines = recentQueries
            .prefix(maxRecentQueries)
            .map { "User: \(String($0.prefix(maxRecentQueryLength)))" }
        if let answer = lastAssistantAnswer?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
            lines.append("SAV-E: \(String(answer.prefix(maxAssistantAnswerLength)))")
        }
        return lines
    }

    private static func relevanceScore(query: String, place: Place, currentLocation: CLLocation?) -> Int {
        let normalizedQuery = normalize(query)
        let terms = normalizedQuery
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        let haystack = normalize(
            ([place.name, place.category.rawValue, place.category.displayName, place.note ?? ""]
                + place.savedVibeTags
                + (place.extractedDishes ?? []))
                .joined(separator: " ")
        )

        var score = 0
        if !place.name.isEmpty, normalizedQuery.contains(normalize(place.name)) { score += 12 }
        for term in terms where haystack.contains(term) { score += 5 }
        if let currentLocation {
            let meters = distance(from: currentLocation, to: place)
            if meters <= 2_000 { score += 4 } else if meters <= 10_000 { score += 2 }
        }
        return score
    }

    private static func distance(from location: CLLocation, to place: Place) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }

    private static func cityOrArea(from address: String) -> String? {
        let pieces = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard pieces.count >= 2 else {
            // Comma-less addresses (common for CJK) may be full street addresses; only
            // pass through short digit-free values so street-level detail never leaves the device.
            guard let only = pieces.first,
                  only.count <= 20,
                  only.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
            return only
        }
        return pieces[pieces.count - 2]
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}

struct SaveAgentPromptPolicy {
    static let productSoul = """
    SAV-E is a cute place-memory scout, not a generic travel or map chatbot.
    You act as the user's personal place-memory agent: you know which places they saved, why they saved them, and you reason over that memory like a sharp local friend.
    SAV-E captures messy place signals into Source Clues and Review Candidates, then helps the user decide from confirmed Map Stamps.
    Default answer from the user's private place memory first; public discovery second and clearly labeled.
    Mirror the user's language: reply in Traditional Chinese when they write Chinese, English when they write English, exactly as the output language instruction says.
    """

    static let userContextRules = """
    User context rules:
    - The user context block is background memory, not search results.
    - Never recommend or cite a place that appears only in the saved place memory sample; recommend only from Grounded sections.
    - Use locality and recent conversation to resolve vague words like "there", "nearby", "the one you mentioned".
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
    - Respond ONLY with strict JSON. No markdown. No text outside JSON.
    - JSON schema: {"answer":"string shown to the user","citedResultIds":["id-from-allowed-result-ids"]}
    - citedResultIds must contain only IDs from Allowed result IDs; cite no more than two IDs.
    - If no allowed result IDs exist, citedResultIds must be [] and answer must not name a place.
    - Answer in the requested output language exactly.
    - For Traditional Chinese output, write the full answer in natural Taiwanese Traditional Chinese. Do not leave English row labels such as "Saved Map Stamp", "rating", or "Public discovery" unless they are part of a place name or the SAV-E brand.
    - Sound like a concise assistant, not a debug report.
    - Recommend one best place first when a trustworthy allowed result exists.
    - If no nearby Saved Map Stamp exists but Public Discovery has allowed results, say SAV-E has no nearby saved match, then recommend one unsaved public option by title.
    - Never call Public Discovery, unsaved map candidates, Review Candidates, or Source-only clues Map Stamps.
    - If recommending Public Discovery, say it is unsaved/public discovery.
    - If discussing a Review Candidate, say it needs review before becoming a Map Stamp.
    - If discussing a Source-only clue, say it is only a clue/source and needs exact-place recovery.
    - Explain the reason using state, distance, rating/review count, and evidence.
    - Name which saved place your answer is based on, so the user can trust the grounding.
    - End with one concrete next step the user can take in SAV-E: save it, show it on the map, narrow the filter, or answer your follow-up.
    - Ask at most one lightweight follow-up question.
    - Do not use parenthetical lists, dangling brackets, or long row-label explanations.
    - Name no more than two places.
    - Keep it under 90 words and finish the final sentence.
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
        \(contextSummary(request.context))
        Grounded sections:
        \(sectionSummary(request.sections))

        \(Self.hardBoundaries)

        \(Self.specialtyEvidenceRules)

        \(Self.outputContract)
        """
    }

    func contextSummary(_ context: GroundedAnswerContext) -> String {
        guard !context.isEmpty else { return "" }
        var lines = ["", "User context (background memory, not results):"]
        if let localityHint = context.localityHint {
            lines.append("- Locality: \(localityHint)")
        }
        if !context.recentConversation.isEmpty {
            lines.append("- Recent conversation:")
            lines.append(contentsOf: context.recentConversation.prefix(4).map { "  \($0)" })
        }
        if !context.savedPlaceDigest.isEmpty {
            lines.append("- Saved place memory sample (names only, may be irrelevant):")
            lines.append(contentsOf: context.savedPlaceDigest.prefix(SaveDrawerContextBuilder.maxDigestEntries).map { "  - \($0)" })
        }
        lines.append(contentsOf: ["", Self.userContextRules, ""])
        return lines.joined(separator: "\n")
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

struct GroundedLLMAnswer: Equatable {
    var message: String
    var citedResultIds: [String]
}

private struct GroundedLLMAnswerDTO: Decodable {
    let answer: String
    let citedResultIds: [String]
}

enum GroundedAnswerValidationError: LocalizedError, Equatable {
    case malformedJSON
    case unknownTopLevelKeys([String])
    case emptyAnswer
    case incompleteAnswer
    case tooLong
    case tooManyCitations
    case citedUnknownResultID(String)
    case citedResultNotGrounded(String)
    case mentionsUncitedResult(String)
    case mentionsDisallowedResult(String)
    case missingPublicDiscoveryLabel(String)
    case mislabeledUnsavedAsMapStamp(String)
    case mislabeledReviewCandidateAsMapStamp(String)
    case mislabeledSourceOnlyAsMapStamp(String)
    case specificItemNotInEvidence(String)
}

struct GroundedAnswerJSONValidator {
    func parseAndValidate(_ rawText: String, request: GroundedAnswerRequest) throws -> GroundedLLMAnswer {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
              let data = trimmed.data(using: .utf8)
        else { throw GroundedAnswerValidationError.malformedJSON }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GroundedAnswerValidationError.malformedJSON
        }
        let allowedKeys: Set<String> = ["answer", "citedResultIds"]
        let unknownKeys = object.keys.filter { !allowedKeys.contains($0) }.sorted()
        guard unknownKeys.isEmpty else { throw GroundedAnswerValidationError.unknownTopLevelKeys(unknownKeys) }

        let dto: GroundedLLMAnswerDTO
        do {
            dto = try JSONDecoder().decode(GroundedLLMAnswerDTO.self, from: data)
        } catch {
            throw GroundedAnswerValidationError.malformedJSON
        }

        let answer = dto.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw GroundedAnswerValidationError.emptyAnswer }
        guard !GeminiSaveLLMClient.looksIncompleteGroundedAnswer(answer) else {
            throw GroundedAnswerValidationError.incompleteAnswer
        }
        guard answer.count <= 700 && answer.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count <= 120 else {
            throw GroundedAnswerValidationError.tooLong
        }
        guard dto.citedResultIds.count <= 2 else { throw GroundedAnswerValidationError.tooManyCitations }

        let allowedIDs = Set(request.allowedPlaceIds)
        let allResults = request.sections.flatMap(\.results)
        let resultsByID = Dictionary(uniqueKeysWithValues: allResults.map { ($0.id, $0) })

        for id in dto.citedResultIds {
            guard allowedIDs.contains(id) else { throw GroundedAnswerValidationError.citedUnknownResultID(id) }
            guard resultsByID[id] != nil else { throw GroundedAnswerValidationError.citedResultNotGrounded(id) }
        }

        let normalizedAnswer = normalize(answer)
        for result in allResults {
            let normalizedTitle = normalize(result.title)
            guard !normalizedTitle.isEmpty, normalizedAnswer.contains(normalizedTitle) else { continue }
            if !allowedIDs.contains(result.id) {
                throw GroundedAnswerValidationError.mentionsDisallowedResult(result.id)
            }
            if !dto.citedResultIds.contains(result.id) {
                throw GroundedAnswerValidationError.mentionsUncitedResult(result.id)
            }
        }

        // Context digest names are background memory only. If the answer names a
        // digest place that is not a grounded result, reject it.
        let groundedTitles = Set(allResults.map { normalize($0.title) })
        for digestName in request.context.digestPlaceNames {
            let normalizedName = normalize(digestName)
            guard !normalizedName.isEmpty,
                  !groundedTitles.contains(where: { $0.contains(normalizedName) || normalizedName.contains($0) }),
                  normalizedAnswer.contains(normalizedName)
            else { continue }
            throw GroundedAnswerValidationError.mentionsDisallowedResult(digestName)
        }

        for id in dto.citedResultIds {
            guard let result = resultsByID[id] else { continue }
            try validateBoundary(result: result, answer: normalizedAnswer)
            if request.intent.requiresSpecificEvidenceMatch {
                try validateSpecificEvidence(result: result, intent: request.intent)
            }
        }

        return GroundedLLMAnswer(message: answer, citedResultIds: dto.citedResultIds)
    }

    private func validateBoundary(result: SaveSearchResult, answer: String) throws {
        let mapStampMarkers = ["map stamp", "saved memory", "your save", "your saved", "地圖章", "地图章", "已保存"]
        let safeNegatedMapStampContext = answer.contains("no nearby saved map stamp") ||
            answer.contains("no saved map stamp") ||
            answer.contains("沒有已保存") ||
            answer.contains("没有已保存") ||
            answer.contains("沒有附近") ||
            answer.contains("没有附近")
        let saysMapStamp = !safeNegatedMapStampContext && mapStampMarkers.contains { answer.contains($0) }
        switch result.objectType {
        case .mapVisibleUnsavedPlace, .newRecommendation:
            if saysMapStamp { throw GroundedAnswerValidationError.mislabeledUnsavedAsMapStamp(result.id) }
            let labels = ["unsaved", "public", "not saved", "public discovery", "not in your saved", "未保存", "尚未保存", "公開探索", "公开探索", "不是地圖章", "不是地图章"]
            guard labels.contains(where: { answer.contains($0) }) else {
                throw GroundedAnswerValidationError.missingPublicDiscoveryLabel(result.id)
            }
        case .pendingCandidate:
            if saysMapStamp { throw GroundedAnswerValidationError.mislabeledReviewCandidateAsMapStamp(result.id) }
            let labels = ["review candidate", "needs review", "待確認", "待确认", "需要確認", "需要确认"]
            guard labels.contains(where: { answer.contains($0) }) else {
                throw GroundedAnswerValidationError.mislabeledReviewCandidateAsMapStamp(result.id)
            }
        case .sourceOnlyClue:
            if saysMapStamp { throw GroundedAnswerValidationError.mislabeledSourceOnlyAsMapStamp(result.id) }
            let labels = ["clue", "source", "source-only", "needs exact place", "線索", "线索", "來源", "来源"]
            guard labels.contains(where: { answer.contains($0) }) else {
                throw GroundedAnswerValidationError.mislabeledSourceOnlyAsMapStamp(result.id)
            }
        default:
            break
        }
    }

    private func validateSpecificEvidence(result: SaveSearchResult, intent: SaveSearchIntent) throws {
        let needles = specificNeedles(for: intent)
        guard !needles.isEmpty else { return }
        let evidenceText = [
            result.title,
            result.subtitle,
            result.statusLabel,
            result.cityOrArea,
            result.missingInfo.joined(separator: " "),
            result.evidence
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("search:") }
                .joined(separator: " "),
            result.recoveryQueries.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let normalized = normalize(evidenceText)
        guard needles.contains(where: { normalized.contains($0) }) else {
            throw GroundedAnswerValidationError.specificItemNotInEvidence(result.id)
        }
    }

    private func specificNeedles(for intent: SaveSearchIntent) -> [String] {
        var values = intent.categoryNeedles.map(normalize)
        let query = normalize(intent.rawText)
        let groups: [(String, [String])] = [
            ("hot pot", ["hot pot", "shabu", "火鍋", "火锅"]),
            ("boba", ["boba", "milk tea", "奶茶", "珍珠"]),
            ("ramen", ["ramen", "拉麵", "拉面"]),
            ("sushi", ["sushi", "壽司", "寿司"])
        ]
        for (_, group) in groups where group.contains(where: { query.contains(normalize($0)) }) {
            values.append(contentsOf: group.map(normalize))
        }
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol SaveLLMClient {
    func parseIntent(_ request: IntentParseRequest) async throws -> SaveSearchIntent
    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> GroundedLLMAnswer
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

    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> GroundedLLMAnswer {
        if request.sections.allSatisfy(\.results.isEmpty) {
            return GroundedLLMAnswer(
                message: "No matching Map Stamps passed the category and location gates.",
                citedResultIds: []
            )
        }
        let message = request.sections
            .filter { !$0.results.isEmpty }
            .map { "\($0.title): \($0.results.count)" }
            .joined(separator: "\n")
        return GroundedLLMAnswer(message: message, citedResultIds: Array(request.allowedPlaceIds.prefix(2)))
    }
}

final class GeminiSaveLLMClient: SaveLLMClient {
    private let validator: SaveSearchIntentJSONValidator
    private let groundedAnswerValidator: GroundedAnswerJSONValidator
    private let promptPolicy: SaveAgentPromptPolicy
    private let geminiTransport: SAVEGeminiTransport

    init(
        apiKey: String? = nil,
        modelFallbacks: [String] = SAVEProductionConfig.defaultGeminiModelFallbacks,
        validator: SaveSearchIntentJSONValidator = SaveSearchIntentJSONValidator(),
        groundedAnswerValidator: GroundedAnswerJSONValidator = GroundedAnswerJSONValidator(),
        promptPolicy: SaveAgentPromptPolicy = SaveAgentPromptPolicy(),
        session: URLSession = .shared
    ) {
        self.validator = validator
        self.groundedAnswerValidator = groundedAnswerValidator
        self.promptPolicy = promptPolicy
        self.geminiTransport = SAVEGeminiTransport(
            modelFallbacks: modelFallbacks,
            session: session,
            accessTokenProvider: { try await PrivyAuthService.shared.accessToken() },
            directAPIKey: apiKey ?? SAVEProductionConfig.clientGeminiAPIKeyIfAllowed()
        )
    }

    static func liveFromConfig() -> GeminiSaveLLMClient? {
        let hasBackend = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]) != nil
        let apiKey = SAVEProductionConfig.clientGeminiAPIKeyIfAllowed()
        guard hasBackend || apiKey != nil else {
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
        You extract a structured place-search intent for SAV-E, a personal place-memory app over the user's saved places.
        Respond ONLY with strict JSON. No markdown.

        Guidance:
        - Queries can be English or Chinese. Map cravings and vibes to the closest category: "想喝點甜的" -> cafe, "date night drinks" -> bar, "somewhere to walk around" -> attraction.
        - "nearby", "near me", "walking distance", "附近", "走路" -> locationMode currentLocation. A named city or neighborhood -> namedArea with that name in "area".
        - "new", "unsaved", "public", "新的", "沒存" -> sourceScope publicOnly. Otherwise default savedFirstAllowPublicFallback.
        - Asking for a specific saved place by name -> kind explicitPlaceSearch. Multi-day or itinerary wording -> tripPlanning.
        - Be honest with confidence: 0.9+ only when category and location are explicit; below 0.6 when you are guessing.

        Examples:
        Query: "find me a quiet cafe near me to work" -> {"kind":"categoryRecommendation","requiredCategories":["cafe"],"optionalCategories":[],"locationMode":{"type":"currentLocation","radiusMeters":2000,"area":null},"sourceScope":"savedFirstAllowPublicFallback","mustMatchCategory":true,"mustMatchLocation":true,"confidence":0.93}
        Query: "今晚想吃辣的" -> {"kind":"craving","requiredCategories":["food"],"optionalCategories":[],"locationMode":{"type":"currentLocation","radiusMeters":2000,"area":null},"sourceScope":"savedFirstAllowPublicFallback","mustMatchCategory":true,"mustMatchLocation":false,"confidence":0.7}

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

    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> GroundedLLMAnswer {
        let prompt = promptPolicy.groundedAnswerPrompt(for: request)
        let answer = try await generateText(prompt: prompt, temperature: 0.2, maxOutputTokens: 1_024)
        do {
            return try groundedAnswerValidator.parseAndValidate(answer, request: request)
        } catch {
            let repairPrompt = """
            \(prompt)

            The previous response failed validation.

            Previous response:
            \(answer)

            Return ONLY valid JSON matching:
            {"answer":"complete user-facing answer","citedResultIds":["allowed-result-id"]}

            Requirements:
            - Use only Allowed result IDs.
            - Do not invent place names.
            - Do not call unsaved/public/review/source-only results Map Stamps.
            - Finish the final sentence.
            """
            let repaired = try await generateText(prompt: repairPrompt, temperature: 0.1, maxOutputTokens: 512)
            return try groundedAnswerValidator.parseAndValidate(repaired, request: request)
        }
    }

    static func looksIncompleteGroundedAnswer(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let danglingSuffixes = ["（", "(", "「", "『", "“", "，", ",", "、", "：", ":", "；", ";", "/", "|", "｜", "-"]
        if danglingSuffixes.contains(where: { trimmed.hasSuffix($0) }) {
            return true
        }
        let pairs: [(Character, Character)] = [
            ("（", "）"),
            ("(", ")"),
            ("「", "」"),
            ("『", "』"),
            ("“", "”")
        ]
        return pairs.contains { open, close in
            trimmed.filter { $0 == open }.count > trimmed.filter { $0 == close }.count
        }
    }

    private func generateText(prompt: String, temperature: Double, maxOutputTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": temperature, "maxOutputTokens": maxOutputTokens]
        ]
        let json = try await geminiTransport.generateContent(body: body)
        guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
            throw SaveAIError.emptyResponse
        }
        return text
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
