import Foundation

/// A single turn in the conversation (user query + AI JSON response).
struct ConversationTurn: Equatable {
    let userMessage: String
    let assistantResponse: String
}

final class SaveAIService {
    static let shared = SaveAIService()

    static let defaultModelFallbacks = SAVEProductionConfig.defaultGeminiModelFallbacks

    private let apiKey: String?
    private let modelFallbacks: [String]

    init(apiKey: String? = nil, modelFallbacks: [String] = SaveAIService.defaultModelFallbacks) {
        let resolved = apiKey
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? SAVEProductionConfig.configValue(for: ["GEMINI_API_KEY"])
        self.apiKey = resolved
        self.modelFallbacks = modelFallbacks
        print("[SaveAI] API key resolved: \(resolved != nil ? "yes" : "nil")")
    }

    func query(
        _ userMessage: String,
        places: [Place],
        conversationHistory: [ConversationTurn] = [],
        outputLanguage: AppLanguage = .english,
        deterministicDraftOverride: SaveAIResponse? = nil
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

        guard let apiKey, !apiKey.isEmpty else {
            if let deterministicDraft {
                return deterministicDraft
            }
            throw SaveAIError.apiKeyMissing
        }

        // Build multi-turn contents array
        var contents: [[String: Any]] = []

        // System instruction as first user message
        contents.append([
            "role": "user",
            "parts": [[
                "text": systemPrompt(
                    places: places,
                    deterministicDraftJSON: deterministicDraft.map { encodeResponse($0) },
                    outputLanguage: outputLanguage
                )
            ]]
        ])
        contents.append(["role": "model", "parts": [["text": "Understood. I will respond only with valid JSON using the user's Map Stamps."]]])

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

        let requestBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: SaveAIError?
        for model in modelFallbacks {
            let endpoint = SAVEProductionConfig.geminiGenerateContentURL(apiKey: apiKey, model: model)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                print("Gemini request failed on \(model): \(error)")
                if let deterministicDraft {
                    return deterministicDraft
                }
                throw error
            }

            guard let http = response as? HTTPURLResponse else {
                lastError = .apiError(0)
                continue
            }

            if http.statusCode == 200 {
                let json: [String: Any]
                do {
                    json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                } catch {
                    print("Gemini envelope parse failed on \(model): \(error)")
                    if let deterministicDraft {
                        return deterministicDraft
                    }
                    throw SaveAIError.parseError
                }

                guard let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else {
                    if let deterministicDraft {
                        return deterministicDraft
                    }
                    throw SaveAIError.emptyResponse
                }

                do {
                    let parsed = try parseResponse(text)
                    if let deterministicDraft {
                        return validatedItineraryPolish(parsed, fallback: deterministicDraft, places: places)
                    }
                    return parsed
                } catch {
                    print("Gemini response parse failed on \(model): \(error)")
                    if let deterministicDraft {
                        return deterministicDraft
                    }
                    throw SaveAIError.parseError
                }
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            print("Gemini API error \(http.statusCode) on \(model): \(responseBody)")
            lastError = .apiError(http.statusCode)
            if http.statusCode != 404 && http.statusCode != 429 {
                break
            }
        }

        if let deterministicDraft {
            return deterministicDraft
        }
        throw lastError ?? SaveAIError.apiError(0)
    }

    func polishItineraryDraft(
        _ deterministicDraft: SaveAIResponse,
        userMessage: String,
        places: [Place],
        outputLanguage: AppLanguage = .english
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
                outputLanguage: outputLanguage,
                deterministicDraftOverride: deterministicDraft
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
        deterministicDraftJSON: String? = nil,
        outputLanguage: AppLanguage
    ) -> String {
        let placesJSON = places.map { p in
            #"{"id":"\#(p.id)","name":"\#(p.name)","address":"\#(p.address)","category":"\#(p.category.rawValue)","status":"\#(p.status.rawValue)","lat":\#(p.latitude),"lng":\#(p.longitude)}"#
        }.joined(separator: ",\n")

        let deterministicDraftSection: String
        if let deterministicDraftJSON {
            deterministicDraftSection = """

            DETERMINISTIC PLANNER DRAFT:
            \(deterministicDraftJSON)

            Use this draft as a safe baseline built from Map Stamps and distance/time-slot rules.
            Treat this draft as route metadata, not a loose suggestion. Do not change stop order, place IDs, mapAction, day count, or route membership. You may only improve title, aiMessage, and stop notes.
            Keep every place ID valid and do not introduce unknown place IDs or claim live travel times.
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
        - If a DETERMINISTIC PLANNER DRAFT is provided, treat its route metadata as the source of truth. Do not change stop order, place IDs, day count, mapAction, or route membership. You may only improve title, aiMessage, and stop notes, and every non-null place ID must come from USER'S MAP STAMPS.
        - Stops from the deterministic draft with null or empty placeId are unsaved/public candidates. You may keep those stops only if they are already in the draft, still with null placeId, and clearly labeled as unsaved/public.
        - The itinerary should read like an assistant-planned draft, not a debug report. Explain the plan in aiMessage before the stop list.
        - If the user asks for trip planning without days or style, still return a usable draft from Map Stamps, then ask exactly one concise follow-up about days or vibe in aiMessage.
        - If the user's saved Map Stamps are mostly food/drink and the trip is missing attractions or activities, do not invent exact public places. Mention the gap and ask whether to search public discovery near the saved anchors.
        - For destination-specific requests, choose Map Stamps whose name/address matches the destination or whose coordinates are geographically near the matching anchor places.
        - If the Map Stamps are far apart, still plan them honestly with realistic travel notes instead of rejecting them as "not in San Francisco".
        - placeList: set placeIds + mapAction.filterPins with same ids
        - navigationCard: set navigationPlaceId + transportMode + mapAction.focusRegion to that place's lat/lng
        - tripItinerary: set itineraryDays + placeIds (all stop ids) + mapAction.showRoute
        - message: set messageText only, no mapAction. Only use for greetings or when there are truly zero relevant places.
        - Only reference places from USER'S MAP STAMPS above using their exact "id" values, except unsaved/public draft stops that already have null placeId.
        """
    }

    private func validatedItineraryPolish(_ response: SaveAIResponse, fallback: SaveAIResponse, places: [Place]) -> SaveAIResponse {
        guard response.componentType == .tripItinerary,
              !response.itineraryDays.isEmpty else {
            return fallback
        }

        let validIDs = Set(places.map { $0.id.uuidString })
        let stopIDs = response.itineraryDays.flatMap(\.stops).compactMap(\.placeId)
        let topLevelIDs = response.placeIds
        let navigationIDs = [response.navigationPlaceId].compactMap { $0 }
        let mapActionIDs = response.mapAction?.placeIds ?? []
        let referencedIDs = stopIDs + topLevelIDs + navigationIDs + mapActionIDs
        guard !stopIDs.isEmpty,
              referencedIDs.allSatisfy({ validIDs.contains($0) }) else {
            return fallback
        }

        return fallback.copyingItineraryCopy(from: response)
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

private extension SaveAIResponse {
    func copyingItineraryCopy(from response: SaveAIResponse) -> SaveAIResponse {
        let responseStops = response.itineraryDays.flatMap(\.stops)
        var responseNotesByPlaceID: [String: [String]] = [:]
        responseStops.forEach { stop in
            guard let placeId = stop.placeId, let note = stop.note, !note.isEmpty else { return }
            responseNotesByPlaceID[placeId, default: []].append(note)
        }

        var fallbackIndex = 0
        let copiedDays = itineraryDays.map { day in
            ItineraryDay(
                dayNumber: day.dayNumber,
                label: day.label,
                stops: day.stops.map { stop in
                    defer { fallbackIndex += 1 }
                    let responseNote = stop.placeId.flatMap { placeId -> String? in
                        guard var notes = responseNotesByPlaceID[placeId], !notes.isEmpty else { return nil }
                        let note = notes.removeFirst()
                        responseNotesByPlaceID[placeId] = notes
                        return note
                    } ?? {
                        guard responseStops.indices.contains(fallbackIndex) else { return nil }
                        return responseStops[fallbackIndex].note
                    }()
                    return ItineraryStop(
                        id: stop.id,
                        placeId: stop.placeId,
                        placeName: stop.placeName,
                        time: stop.time,
                        duration: stop.duration,
                        note: responseNote ?? stop.note
                    )
                }
            )
        }

        return SaveAIResponse(
            componentType: componentType,
            title: response.title ?? title,
            placeIds: placeIds,
            navigationPlaceId: navigationPlaceId,
            transportMode: transportMode,
            itineraryDays: copiedDays,
            messageText: messageText,
            mapAction: mapAction,
            aiMessage: response.aiMessage ?? aiMessage
        )
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
