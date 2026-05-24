import Foundation

/// A single turn in the conversation (user query + AI JSON response).
struct ConversationTurn: Equatable {
    let userMessage: String
    let assistantResponse: String
}

final class WanderlyAIService {
    static let shared = WanderlyAIService()

    private static let modelFallbacks = [
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash",
        "gemini-flash-lite-latest"
    ]

    private let apiKey: String?

    init(apiKey: String? = nil) {
        let resolved = apiKey
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? Self.keyFromPlist("GEMINI_API_KEY")
        self.apiKey = resolved
        print("[WanderlyAI] API key resolved: \(resolved != nil ? "yes" : "nil")")
    }

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict[key],
              value != "YOUR_KEY_HERE" else { return nil }
        return value
    }

    func query(_ userMessage: String, places: [Place], conversationHistory: [ConversationTurn] = []) async throws -> WanderlyAIResponse {
        guard !places.isEmpty else {
            return WanderlyAIResponse(
                componentType: .message,
                title: nil,
                placeIds: [],
                navigationPlaceId: nil,
                transportMode: .walking,
                itineraryDays: [],
                messageText: "No saved places are loaded yet. Save or import places first, then ask me to plan.",
                mapAction: nil,
                aiMessage: nil
            )
        }

        if let localResponse = localIntentResponse(for: userMessage, places: places) {
            return localResponse
        }

        let deterministicDraft = DeterministicTripPlanner().plan(for: userMessage, places: places)

        guard let apiKey, !apiKey.isEmpty else {
            if let deterministicDraft {
                return deterministicDraft
            }
            throw WanderlyAIError.apiKeyMissing
        }

        // Build multi-turn contents array
        var contents: [[String: Any]] = []

        // System instruction as first user message
        contents.append([
            "role": "user",
            "parts": [[
                "text": systemPrompt(
                    places: places,
                    deterministicDraftJSON: deterministicDraft.map { encodeResponse($0) }
                )
            ]]
        ])
        contents.append(["role": "model", "parts": [["text": "Understood. I will respond only with valid JSON using the saved places."]]])

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

        var lastError: WanderlyAIError?
        for model in Self.modelFallbacks {
            let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = .apiError(0)
                continue
            }

            if http.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let candidates = json?["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else {
                    throw WanderlyAIError.emptyResponse
                }

                let parsed = try parseResponse(text)
                if let deterministicDraft {
                    return validatedItineraryPolish(parsed, fallback: deterministicDraft, places: places)
                }
                return parsed
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
        throw lastError ?? WanderlyAIError.apiError(0)
    }

    // MARK: - Private

    private func localIntentResponse(for message: String, places: [Place]) -> WanderlyAIResponse? {
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
            return WanderlyAIResponse(
                componentType: .message,
                title: nil,
                placeIds: [],
                navigationPlaceId: nil,
                transportMode: .walking,
                itineraryDays: [],
                messageText: "No \(category.displayName.lowercased()) places saved yet.",
                mapAction: nil,
                aiMessage: nil
            )
        }

        let ids = filtered.map { $0.id.uuidString }
        return WanderlyAIResponse(
            componentType: .placeList,
            title: "\(category.displayName) spots",
            placeIds: ids,
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: [],
            messageText: nil,
            mapAction: MapActionData(type: .filterPins, placeIds: ids, lat: nil, lng: nil, span: nil),
            aiMessage: "Showing your \(category.displayName.lowercased()) spots."
        )
    }

    private func systemPrompt(places: [Place], deterministicDraftJSON: String? = nil) -> String {
        let placesJSON = places.map { p in
            #"{"id":"\#(p.id)","name":"\#(p.name)","address":"\#(p.address)","category":"\#(p.category.rawValue)","status":"\#(p.status.rawValue)","lat":\#(p.latitude),"lng":\#(p.longitude)}"#
        }.joined(separator: ",\n")

        let deterministicDraftSection: String
        if let deterministicDraftJSON {
            deterministicDraftSection = """

            DETERMINISTIC PLANNER DRAFT:
            \(deterministicDraftJSON)

            Use this draft as the source of truth for itinerary place IDs, day grouping, stop order, first-pass times, and map route IDs.
            You may polish the title, aiMessage, and stop notes. Do not introduce unknown place IDs or claim live travel times.
            """
        } else {
            deterministicDraftSection = ""
        }

        return """
        You are SAV-E's AI assistant. You help users explore their saved places and plan trips.

        USER'S SAVED PLACES:
        [\(placesJSON)]
        \(deterministicDraftSection)

        CRITICAL: Respond ONLY with a valid JSON object. No markdown. No text outside the JSON.

        BEHAVIOR:
        - On the FIRST request, take action immediately. Generate itineraries, lists, or navigation using the saved places. Do NOT ask clarifying questions on the first message.
        - On FOLLOW-UP messages, refine the previous result. For example: "add more food spots", "swap day 1 and 2", "make it 3 days instead". Build on the previous JSON response.
        - When refining, output the COMPLETE updated JSON (not just the diff).
        - Do NOT assume the user is in San Francisco or any default city. Infer the trip region only from the user's message plus saved place names, addresses, latitudes, and longitudes.
        - Saved places may be in any city. Disneyland, Universal Studios, Los Angeles, Anaheim, Tokyo, or any other region are valid planning targets if they appear in SAVED PLACES.

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
        - For itinerary requests: use saved places to build a realistic schedule with smart times and geographic order.
        - If a DETERMINISTIC PLANNER DRAFT is provided, preserve its place IDs, day grouping, stop order, first-pass times, and mapAction. Polish explanation and notes only.
        - For destination-specific requests, choose saved places whose name/address matches the destination or whose coordinates are geographically near the matching anchor places.
        - If the saved places are far apart, still plan them honestly with realistic travel notes instead of rejecting them as "not in San Francisco".
        - placeList: set placeIds + mapAction.filterPins with same ids
        - navigationCard: set navigationPlaceId + transportMode + mapAction.focusRegion to that place's lat/lng
        - tripItinerary: set itineraryDays + placeIds (all stop ids) + mapAction.showRoute
        - message: set messageText only, no mapAction. Only use for greetings or when there are truly zero relevant places.
        - Only reference places from the SAVED PLACES list above using their exact "id" values
        """
    }

    private func validatedItineraryPolish(_ response: WanderlyAIResponse, fallback: WanderlyAIResponse, places: [Place]) -> WanderlyAIResponse {
        guard response.componentType == .tripItinerary,
              !response.itineraryDays.isEmpty else {
            return fallback
        }

        let validIDs = Set(places.map { $0.id.uuidString })
        let stopIDs = response.itineraryDays.flatMap(\.stops).compactMap(\.placeId)
        guard !stopIDs.isEmpty,
              stopIDs.allSatisfy({ validIDs.contains($0) }) else {
            return fallback
        }

        return response
    }

    private func parseResponse(_ text: String) throws -> WanderlyAIResponse {
        var jsonString = text
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards),
           start.lowerBound < end.upperBound {
            jsonString = String(text[start.lowerBound..<end.upperBound])
        }
        guard let data = jsonString.data(using: .utf8) else { throw WanderlyAIError.parseError }
        let dto = try JSONDecoder().decode(WanderlyAIResponseDTO.self, from: data)
        return dto.toResponse()
    }

    /// Re-encode an AI response back to JSON string for conversation context.
    func encodeResponse(_ response: WanderlyAIResponse) -> String {
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

// MARK: - Errors

enum WanderlyAIError: LocalizedError {
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
