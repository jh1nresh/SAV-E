import Foundation

/// A single turn in the conversation (user query + AI JSON response).
struct ConversationTurn: Equatable {
    let userMessage: String
    let assistantResponse: String
}

final class SaveAIService {
    static let shared = SaveAIService()

    static let defaultModelFallbacks = SAVEProductionConfig.defaultGeminiModelFallbacks

    private let geminiTransport: SAVEGeminiTransport

    init(apiKey: String? = nil, modelFallbacks: [String] = SaveAIService.defaultModelFallbacks) {
        let resolved = apiKey
            ?? SAVEProductionConfig.clientGeminiAPIKeyIfAllowed()
        self.geminiTransport = SAVEGeminiTransport(
            modelFallbacks: modelFallbacks,
            accessTokenProvider: { try await PrivyAuthService.shared.accessToken() },
            directAPIKey: resolved
        )
        print("[SaveAI] Gemini transport configured: backend proxy or allowed direct fallback")
    }

    func query(
        _ userMessage: String,
        places: [Place],
        publicCandidates: [SaveMapCandidate] = [],
        conversationHistory: [ConversationTurn] = [],
        outputLanguage: AppLanguage = .english,
        deterministicDraftOverride: SaveAIResponse? = nil,
        requiredPlaceIDs: Set<String> = []
    ) async throws -> SaveAIResponse {
        guard !places.isEmpty else {
            return SaveAIResponse(
                componentType: .message,
                title: nil,
                placeIds: [],
                navigationPlaceId: nil,
                transportMode: .walking,
                itineraryDays: [],
                messageText: outputLanguage.localized(
                    english: "No Map Stamps are loaded yet. Save or import places first, then ask me to plan.",
                    traditionalChinese: "目前還沒有載入地圖章。先保存或匯入地點，再請我幫你規劃。"
                ),
                mapAction: nil,
                aiMessage: nil
            )
        }

        if deterministicDraftOverride == nil,
           let localResponse = localIntentResponse(for: userMessage, places: places, outputLanguage: outputLanguage) {
            return localResponse
        }

        let deterministicDraft = deterministicDraftOverride ?? DeterministicTripPlanner().plan(
            for: userMessage,
            places: places,
            outputLanguage: outputLanguage
        )

        // Build multi-turn contents array
        var contents: [[String: Any]] = []

        // System instruction as first user message
        contents.append([
            "role": "user",
            "parts": [[
                "text": systemPrompt(
                    places: places,
                    publicCandidates: publicCandidates,
                    deterministicDraftJSON: deterministicDraft.map { encodeResponse($0) },
                    outputLanguage: outputLanguage
                )
            ]]
        ])
        contents.append(["role": "model", "parts": [["text": "Understood. I will respond only with valid JSON using the user's Map Stamps and approved public discovery candidates."]]])

        // Previous conversation turns
        for turn in conversationHistory {
            contents.append(["role": "user", "parts": [["text": turn.userMessage]]])
            contents.append(["role": "model", "parts": [["text": turn.assistantResponse]]])
        }

        // Current query
        contents.append(["role": "user", "parts": [["text": userMessage]]])

        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2048
            ]
        ]

        do {
            let json = try await geminiTransport.generateContent(body: body)
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                if let deterministicDraft { return deterministicDraft }
                throw SaveAIError.emptyResponse
            }

            let parsed = try parseResponse(text)
            if let deterministicDraft {
                return validatedItineraryPolish(
                    parsed,
                    fallback: deterministicDraft,
                    places: places,
                    publicCandidates: publicCandidates,
                    requiredPlaceIDs: requiredPlaceIDs
                )
            }
            return parsed
        } catch let error as SAVEGeminiTransportError {
            if let deterministicDraft { return deterministicDraft }
            if case .upstreamStatus(let status) = error { throw SaveAIError.apiError(status) }
            throw SaveAIError.apiKeyMissing
        } catch {
            if let deterministicDraft { return deterministicDraft }
            throw error
        }
    }

    func polishItineraryDraft(
        _ deterministicDraft: SaveAIResponse,
        userMessage: String,
        places: [Place],
        publicCandidates: [SaveMapCandidate] = [],
        outputLanguage: AppLanguage = .english,
        requiredPlaceIDs: Set<String> = []
    ) async -> SaveAIResponse {
        guard deterministicDraft.componentType == .tripItinerary else {
            return deterministicDraft
        }
        guard !places.isEmpty else {
            return deterministicDraft
        }

        do {
            return try await query(
                userMessage,
                places: places,
                publicCandidates: publicCandidates,
                outputLanguage: outputLanguage,
                deterministicDraftOverride: deterministicDraft,
                requiredPlaceIDs: requiredPlaceIDs
            )
        } catch {
            return deterministicDraft
        }
    }

    // MARK: - Private

    private func localIntentResponse(
        for message: String,
        places: [Place],
        outputLanguage: AppLanguage
    ) -> SaveAIResponse? {
        let normalized = message.lowercased()
        guard normalized.contains("show") || normalized.contains("map") || normalized.contains("spots") || normalized.contains("places") else {
            return nil
        }

        let categories: [(PlaceCategory, [String])] = [
            (.food, ["food", "restaurant", "restaurants", "eat", "eats"]),
            (.cafe, ["cafe", "coffee"]),
            (.bar, ["bar", "drink", "drinks"]),
            (.attraction, ["attraction", "attractions", "sight", "sights"]),
            (.stay, ["stay", "hotel", "hotels"]),
            (.shopping, ["shopping", "shop", "shops"])
        ]

        guard let category = categories.first(where: { _, aliases in
            aliases.contains { normalized.contains($0) }
        })?.0 else {
            return nil
        }

        let filtered = places.filter { $0.category == category }
        guard !filtered.isEmpty else {
            return SaveAIResponse(
                componentType: .message,
                title: nil,
                placeIds: [],
                navigationPlaceId: nil,
                transportMode: .walking,
                itineraryDays: [],
                messageText: outputLanguage.localized(
                    english: "No \(category.displayName(language: .english).lowercased()) places saved yet.",
                    traditionalChinese: "還沒有保存\(category.displayName(language: .traditionalChinese))地點。"
                ),
                mapAction: nil,
                aiMessage: nil
            )
        }

        let ids = filtered.map { $0.id.uuidString }
        return SaveAIResponse(
            componentType: .placeList,
            title: outputLanguage.localized(
                english: "\(category.displayName(language: .english)) spots",
                traditionalChinese: "\(category.displayName(language: .traditionalChinese))地點"
            ),
            placeIds: ids,
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: [],
            messageText: nil,
            mapAction: MapActionData(type: .filterPins, placeIds: ids, lat: nil, lng: nil, span: nil),
            aiMessage: outputLanguage.localized(
                english: "Showing your \(category.displayName(language: .english).lowercased()) spots.",
                traditionalChinese: "正在顯示你的\(category.displayName(language: .traditionalChinese))地點。"
            )
        )
    }

    private func systemPrompt(
        places: [Place],
        publicCandidates: [SaveMapCandidate] = [],
        deterministicDraftJSON: String? = nil,
        outputLanguage: AppLanguage
    ) -> String {
        let placesJSON = places.map { p in
            #"{"id":"\#(p.id)","name":"\#(p.name)","address":"\#(p.address)","category":"\#(p.category.rawValue)","status":"\#(p.status.rawValue)","lat":\#(p.latitude),"lng":\#(p.longitude)}"#
        }.joined(separator: ",\n")

        let publicCandidatesJSON = publicCandidates.map { candidate in
            let category = candidate.category?.rawValue ?? "unknown"
            return #"{"name":"\#(candidate.title)","subtitle":"\#(candidate.subtitle)","category":"\#(category)","lat":\#(candidate.latitude),"lng":\#(candidate.longitude)}"#
        }.joined(separator: ",\n")
        let publicCandidatesSection = publicCandidates.isEmpty ? "" : """

        PUBLIC DISCOVERY CANDIDATES:
        [\(publicCandidatesJSON)]
        These are not Map Stamps. In tripItinerary stops, use placeId null for them and keep the exact candidate name.
        """

        let deterministicDraftSection: String
        if let deterministicDraftJSON {
            deterministicDraftSection = """

            DETERMINISTIC PLANNER DRAFT:
            \(deterministicDraftJSON)

            Use this draft as a safe baseline built from Map Stamps and distance/time-slot rules.
            Treat this draft as the approved retrieval candidate set, not the final route. You may reorder stops, assign smarter time slots, regroup stops across days, and drop optional non-anchor stops when the schedule would be unrealistic.
            Keep every non-null place ID valid, preserve required anchor stops, and do not introduce unknown place IDs or claim live travel times.
            If a draft stop has no placeId, it is an unsaved map candidate. You may keep it with a null placeId, but you must clearly label it as unsaved/public and never call it a Map Stamp.
            Preserve the requested day count when the user specified one.
            """
        } else {
            deterministicDraftSection = ""
        }

        return """
        You are SAV-E's AI assistant. The map is a spatial memory canvas, and the drawer is the intent and recommendation layer. You help users explore confirmed Map Stamps and plan trips from them.

        USER'S MAP STAMPS:
        [\(placesJSON)]
        \(publicCandidatesSection)
        \(deterministicDraftSection)

        CRITICAL: Respond ONLY with a valid JSON object. No markdown. No text outside the JSON.
        OUTPUT LANGUAGE: \(outputLanguage.serviceOutputInstruction)

        BEHAVIOR:
        - On the FIRST request, take action immediately. Generate itineraries, lists, recommendations, or navigation using the Map Stamps. For recommendation requests, give one best pick first, explain why, then ask at most one lightweight follow-up such as budget, cuisine, or quick vs sit-down.
        - On FOLLOW-UP messages, refine the previous result. For example: "add more food spots", "swap day 1 and 2", "make it 3 days instead". Build on the previous JSON response.
        - When refining, output the COMPLETE updated JSON (not just the diff).
        - Do NOT assume the user is in San Francisco or any default city. Infer the trip region only from the user's message plus Map Stamp names, addresses, latitudes, and longitudes.
        - Map Stamps may be in any city. Disneyland, Universal Studios, Los Angeles, Anaheim, Tokyo, or any other region are valid planning targets if they appear in USER'S MAP STAMPS.

        RESPONSE SCHEMA:
        {
          "componentType": "placeList" | "navigationCard" | "tripItinerary" | "message",
          "title": "string",
          "placeIds": ["uuid-string", ...],
          "navigationPlaceId": "uuid-string or null",
          "transportMode": "walking" | "transit" | "driving",
          "itineraryDays": [
            {
              "dayNumber": 1,
              "label": "Day 1",
              "stops": [
                {"placeId": "uuid", "placeName": "Name", "time": "9:00 AM", "duration": 90, "note": "optional"}
              ]
            }
          ],
          "messageText": "string or null",
          "mapAction": {
            "type": "filterPins" | "focusRegion" | "showRoute" | "resetPins",
            "placeIds": ["uuid", ...],
            "lat": 0.0, "lng": 0.0, "span": 0.05
          },
          "aiMessage": "one-line explanation shown to user"
        }

        RULES:
        - Every user-visible string in title, itineraryDays.label, itineraryDays.stops.note, messageText, and aiMessage must use the OUTPUT LANGUAGE exactly.
        - For itinerary requests: use Map Stamps to build a realistic schedule with smart times, geographic order, and the user's requested destination/day count/style.
        - If a DETERMINISTIC PLANNER DRAFT is provided, treat it as the approved candidate set. You may reorder, assign time slots, regroup by day, and drop optional non-anchor stops. A reasonable day structure outranks maximizing the number of saved food/drink stops. Every non-null place ID must come from USER'S MAP STAMPS.
        - \(Self.itineraryCandidatePolicyInstruction(outputLanguage: outputLanguage))
        - Stops from the deterministic draft or PUBLIC DISCOVERY CANDIDATES with null or empty placeId are unsaved/public candidates. You may keep those stops only with null placeId, using their exact candidate name, and clearly label them as unsaved/public.
        - The itinerary should read like an assistant-planned draft, not a debug report. Explain the plan in aiMessage before the stop list.
        - If the user asks for trip planning without days or style, still return a usable draft from Map Stamps, then ask exactly one concise follow-up about days or vibe in aiMessage.
        - If the user's saved Map Stamps are mostly food/drink and the trip is missing attractions or activities, use PUBLIC DISCOVERY CANDIDATES when provided to add one attraction/public activity lane. If no public candidates are provided, mention the gap instead of inventing exact places.
        - For destination-specific requests, choose Map Stamps whose name/address matches the destination or whose coordinates are geographically near the matching anchor places.
        - If the Map Stamps are far apart, still plan them honestly with realistic travel notes instead of rejecting them as "not in San Francisco".
        - placeList: set placeIds + mapAction.filterPins with same ids
        - navigationCard: set navigationPlaceId + transportMode + mapAction.focusRegion to that place's lat/lng
        - tripItinerary: set itineraryDays + placeIds (all stop ids) + mapAction.showRoute
        - message: set messageText only, no mapAction. Only use for greetings or when there are truly zero relevant places.
        - Only reference places from USER'S MAP STAMPS above using their exact "id" values, except unsaved/public draft stops that already have null placeId.
        """
    }

    static func itineraryCandidatePolicyInstruction(outputLanguage: AppLanguage) -> String {
        outputLanguage.localized(
            english: "For trip planning, only use the retrieval candidate set: Map Stamps by exact UUID plus public discovery candidates by exact name with placeId null. Prioritize a reasonable itinerary structure over filling every slot. If saved places are mostly or all food/drink, the plan must reserve space for an attraction or public activity candidate when one is available; do not output an all-restaurant itinerary.",
            traditionalChinese: "行程規劃只能使用檢索候選集合：地圖章必須用正確 UUID，公開探索候選必須用精確名稱且 placeId 維持 null。合理行程結構優先於把所有空格塞滿。如果已存地點多半或全是吃喝，且有景點或公開活動候選，行程必須保留景點／活動，不可直接輸出全餐廳行程。"
        )
    }

    private func validatedItineraryPolish(
        _ response: SaveAIResponse,
        fallback: SaveAIResponse,
        places: [Place],
        publicCandidates: [SaveMapCandidate],
        requiredPlaceIDs: Set<String>
    ) -> SaveAIResponse {
        ItineraryPlanValidator(
            savedPlaces: places,
            publicCandidates: publicCandidates,
            fallback: fallback,
            requiredPlaceIDs: requiredPlaceIDs
        ).validated(response) ?? fallback
    }

    private func parseResponse(_ text: String) throws -> SaveAIResponse {
        var jsonString = text
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards),
           start.lowerBound < end.upperBound {
            jsonString = String(text[start.lowerBound..<end.upperBound])
        }
        guard let data = jsonString.data(using: .utf8) else { throw SaveAIError.parseError }
        let dto = try JSONDecoder().decode(SaveAIResponseDTO.self, from: data)
        return dto.toResponse()
    }

    /// Re-encode an AI response back to JSON string for conversation context.
    func encodeResponse(_ response: SaveAIResponse) -> String {
        // Build a minimal JSON representation to send back as context
        var dict: [String: Any] = ["componentType": response.componentType.rawValue]
        if let title = response.title { dict["title"] = title }
        if !response.placeIds.isEmpty { dict["placeIds"] = response.placeIds }
        if let msg = response.aiMessage { dict["aiMessage"] = msg }
        if let text = response.messageText { dict["messageText"] = text }
        if !response.itineraryDays.isEmpty {
            dict["itineraryDays"] = response.itineraryDays.map { day in
                [
                    "dayNumber": day.dayNumber,
                    "label": day.label ?? "Day \(day.dayNumber)",
                    "stops": day.stops.map { stop in
                        ["placeId": stop.placeId ?? "", "placeName": stop.placeName, "time": stop.time ?? "", "duration": stop.duration ?? 60, "note": stop.note ?? ""] as [String: Any]
                    }
                ] as [String: Any]
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

struct ItineraryPlanValidator {
    let savedPlaces: [Place]
    let publicCandidates: [SaveMapCandidate]
    let fallback: SaveAIResponse
    let requiredPlaceIDs: Set<String>

    func validated(_ response: SaveAIResponse) -> SaveAIResponse? {
        guard response.componentType == .tripItinerary,
              !response.itineraryDays.isEmpty else {
            return nil
        }

        let validSavedIDs = Set(savedPlaces.map { $0.id.uuidString })
        let fallbackPublicNames = Set(
            fallback.itineraryDays
                .flatMap(\.stops)
                .filter { Self.nonEmptyPlaceID($0.placeId) == nil }
                .map { Self.normalizedName($0.placeName) }
        )
        let publicCandidateNames = Set(publicCandidates.map { Self.normalizedName($0.title) })

        let stops = response.itineraryDays.flatMap(\.stops)
        guard !stops.isEmpty else { return nil }

        var stopSavedIDs: [String] = []
        for stop in stops {
            if let placeID = Self.nonEmptyPlaceID(stop.placeId) {
                guard validSavedIDs.contains(placeID) else { return nil }
                stopSavedIDs.append(placeID)
            } else {
                let name = Self.normalizedName(stop.placeName)
                guard fallbackPublicNames.contains(name) || publicCandidateNames.contains(name) else {
                    return nil
                }
            }
        }
        guard Set(stopSavedIDs).count == stopSavedIDs.count else {
            return nil
        }

        let responsePlaceIDs = response.placeIds.compactMap { Self.nonEmptyPlaceID($0) }
        let navigationIDs = [response.navigationPlaceId].compactMap { Self.nonEmptyPlaceID($0) }
        let mapActionIDs = (response.mapAction?.placeIds ?? []).compactMap { Self.nonEmptyPlaceID($0) }
        guard (responsePlaceIDs + navigationIDs + mapActionIDs).allSatisfy({ validSavedIDs.contains($0) }) else {
            return nil
        }
        guard requiredPlaceIDs.isSubset(of: Set(stopSavedIDs)) else {
            return nil
        }

        let orderedSavedIDs = stopSavedIDs.removingDuplicates()
        let generatedMapAction = orderedSavedIDs.isEmpty ? nil : MapActionData(
            type: .showRoute,
            placeIds: orderedSavedIDs,
            lat: nil,
            lng: nil,
            span: nil
        )
        let navigationPlaceID = Self.nonEmptyPlaceID(response.navigationPlaceId).flatMap { validSavedIDs.contains($0) ? $0 : nil }
            ?? Self.nonEmptyPlaceID(fallback.navigationPlaceId)

        return SaveAIResponse(
            componentType: .tripItinerary,
            title: response.title ?? fallback.title,
            placeIds: orderedSavedIDs,
            navigationPlaceId: navigationPlaceID,
            transportMode: response.transportMode,
            itineraryDays: response.itineraryDays,
            messageText: response.messageText,
            mapAction: generatedMapAction,
            aiMessage: response.aiMessage ?? fallback.aiMessage
        )
    }

    private static func nonEmptyPlaceID(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Errors

enum SaveAIError: LocalizedError {
    case apiKeyMissing
    case apiError(Int)
    case emptyResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "AI isn't configured yet."
        case .apiError(let code):
            if code == 429 {
                return "AI is busy right now. Try again in a minute."
            }
            if code == 401 || code == 403 {
                return "AI access needs attention."
            }
            return "AI request failed. Try again in a moment."
        case .emptyResponse:
            return "AI didn't return an answer. Try again."
        case .parseError:
            return "AI returned something unexpected. Try again."
        }
    }
}
