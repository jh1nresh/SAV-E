import CoreLocation
import Foundation

@MainActor
protocol AIDrawerLocationProviding {
    var currentLocation: CLLocation? { get }
    func requestCurrentLocation() async -> CLLocation?
}

extension LocationService: AIDrawerLocationProviding {}

@MainActor
final class AIDrawerViewModel: ObservableObject {

    enum DrawerState: Equatable {
        case idle
        case loading
        case displaying(SaveAIResponse)
        case saveSearchResults(SaveSearchResponse)
        case placeDetail(Place)
        case reviewCandidateDetail(PlaceReviewCandidate)
        case mapCandidateDetail(SaveMapCandidate)
        case error(String)
    }

    @Published var drawerState: DrawerState = .idle
    @Published var query = ""
    @Published var mapAction: MapActionData?
    @Published var chatHistory: [ChatEntry] = []

    struct ChatEntry: Identifiable, Equatable {
        let id = UUID()
        let query: String
        let timestamp: Date
    }

    @Published var places: [Place] = []
    @Published var mapCandidates: [SaveMapCandidate] = []

    private let aiService: SaveAIService
    private let saveSearchController: SaveSearchController
    private let locationIntentRecommendationService: SaveLocationIntentRecommendationService
    private let locationService: any AIDrawerLocationProviding
    private let groundedAnswerClient: SaveLLMClient?

    /// Multi-turn conversation context for the current session.
    private var conversationTurns: [ConversationTurn] = []
    private var activeRequestID: UUID?

    init(
        aiService: SaveAIService = .shared,
        saveSearchController: SaveSearchController = SaveSearchController(),
        locationIntentRecommendationService: SaveLocationIntentRecommendationService = SaveLocationIntentRecommendationService(),
        locationService: (any AIDrawerLocationProviding)? = nil,
        groundedAnswerClient: SaveLLMClient? = GeminiSaveLLMClient.liveFromConfig()
    ) {
        self.aiService = aiService
        self.saveSearchController = saveSearchController
        self.locationIntentRecommendationService = locationIntentRecommendationService
        self.locationService = locationService ?? LocationService.shared
        self.groundedAnswerClient = groundedAnswerClient
    }

    func submit(
        reviewCandidates: [PlaceReviewCandidate] = [],
        outputLanguage: AppLanguage = .english
    ) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if DeterministicTripPlanner().isItineraryRequest(trimmed) {
            await showTripPlanningResponse(query: trimmed, outputLanguage: outputLanguage)
            return
        }

        let resolvedIntent = await recommendationIntent(for: trimmed)
        let needsCurrentLocation = resolvedIntent?.mustMatchLocation ??
            locationIntentRecommendationService.requiresCurrentLocation(for: trimmed)
        let currentLocation = needsCurrentLocation
            ? await locationService.requestCurrentLocation()
            : locationService.currentLocation
        let gatedResponse = resolvedIntent.flatMap { intent in
            locationIntentRecommendationService.recommendationSearchResponse(
                for: trimmed,
                intent: intent,
                places: places,
                reviewCandidates: reviewCandidates,
                mapCandidates: mapCandidates,
                currentLocation: currentLocation
            )
        } ?? locationIntentRecommendationService.recommendationSearchResponse(
            for: trimmed,
            places: places,
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates,
            currentLocation: currentLocation
        )
        if let gatedResponse {
            await showGroundedRecommendationResponse(
                gatedResponse,
                query: trimmed,
                intent: resolvedIntent,
                outputLanguage: outputLanguage
            )
            return
        }

        let saveSearchResponse = saveSearchController.search(
            query: trimmed,
            places: places,
            localRecords: [],
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates
        )
        if saveSearchResponse.hasVisibleResults {
            await showGroundedRecommendationResponse(
                saveSearchResponse,
                query: trimmed,
                intent: resolvedIntent,
                outputLanguage: outputLanguage
            )
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil

        // Save to sidebar history (avoid duplicates at top)
        if chatHistory.first?.query != trimmed {
            chatHistory.insert(ChatEntry(query: trimmed, timestamp: Date()), at: 0)
            if chatHistory.count > 20 { chatHistory.removeLast() }
        }

        do {
            let response = try await aiService.query(
                trimmed,
                places: places,
                conversationHistory: conversationTurns,
                outputLanguage: outputLanguage
            )
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            drawerState = .displaying(response)
            mapAction = response.mapAction

            // Save this turn for follow-up context
            let responseJSON = aiService.encodeResponse(response)
            conversationTurns.append(ConversationTurn(userMessage: trimmed, assistantResponse: responseJSON))

            // Keep last 5 turns to avoid token limits
            if conversationTurns.count > 5 {
                conversationTurns.removeFirst()
            }
        } catch {
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            drawerState = .error(error.localizedDescription)
        }
    }

    func showPlace(_ place: Place) {
        drawerState = .placeDetail(place)
        mapAction = MapActionData(type: .focusRegion, placeIds: nil,
                                  lat: place.latitude, lng: place.longitude, span: 0.01)
    }

    func showSearchResult(_ result: SaveSearchResult) {
        switch result.objectType {
        case .savedPlace, .triedMemory:
            guard let place = place(for: result) else { return }
            showPlace(place)
        case .mapVisibleUnsavedPlace:
            guard let candidate = mapCandidate(for: result) else { return }
            showMapCandidate(candidate)
        case .pendingCandidate, .sourceOnlyClue:
            showSearchResultFallback(result)
        default:
            return
        }
    }

    private func showSearchResultFallback(_ result: SaveSearchResult) {
        let missingLine = result.missingInfo.isEmpty
            ? nil
            : "Missing: \(result.missingInfo.prefix(3).joined(separator: ", "))"
        let evidenceLine = result.evidence.first.map { "Evidence: \($0)" }
        let message = [
            result.subtitle,
            evidenceLine,
            missingLine,
            result.sourceURL.map { "Source: \($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        drawerState = .displaying(SaveAIResponse(
            componentType: .message,
            title: result.statusLabel,
            placeIds: [],
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: [],
            messageText: message.isEmpty ? result.title : message,
            mapAction: nil,
            aiMessage: nil
        ))
    }

    func showReviewCandidate(_ candidate: PlaceReviewCandidate) {
        drawerState = .reviewCandidateDetail(candidate)
        if let latitude = candidate.latitude, let longitude = candidate.longitude {
            mapAction = MapActionData(type: .focusRegion, placeIds: nil,
                                      lat: latitude, lng: longitude, span: 0.01)
        }
    }

    func showMapCandidate(_ candidate: SaveMapCandidate) {
        drawerState = .mapCandidateDetail(candidate)
        mapAction = MapActionData(type: .focusRegion, placeIds: nil,
                                  lat: candidate.latitude, lng: candidate.longitude, span: 0.01)
    }

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
        if case .placeDetail(let selected) = drawerState, selected.id == place.id {
            drawerState = .idle
        }
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
    }

    func reset() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        mapCandidates = []
        conversationTurns = []
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
    }

    func startNewConversation() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        conversationTurns = []
    }

    func returnToCommands() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
    }

    func cancelCurrentRequest() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
    }

    func showMessage(title: String, message: String) {
        drawerState = .displaying(SaveAIResponse(
            componentType: .message,
            title: title,
            placeIds: [],
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: [],
            messageText: message,
            mapAction: nil,
            aiMessage: message
        ))
    }

    func shouldSearchNearbyUnsavedCandidates(for query: String) -> Bool {
        saveSearchController.shouldSearchNearbyUnsavedCandidatesImmediately(for: query)
    }

    func shouldSearchExactMapCandidates(for query: String) -> Bool {
        saveSearchController.exactMapCandidateQuery(for: query) != nil
    }

    func shouldPrepareNearbyCandidatesAfterAnswer(for query: String) -> Bool {
        mapCandidates.isEmpty && saveSearchController.shouldPrepareMapCandidates(for: query)
    }

    func shouldAutoSearchNearbyUnsavedCandidates() -> Bool {
        guard case .saveSearchResults(let response) = drawerState else { return false }
        return response.shouldAutoSearchNearbyUnsavedCandidates
    }

    func showCollaborativeListPlan(_ list: SaveCollaborativeList) {
        drawerState = .displaying(list.itineraryResponse())
    }

    func resolvePlaces(from ids: [String]) -> [Place] {
        let uuids = Set(ids.compactMap { UUID(uuidString: $0) })
        return places.filter { uuids.contains($0.id) }
    }

    func resolvePlace(id: String?) -> Place? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return places.first { $0.id == uuid }
    }

    private func place(for result: SaveSearchResult) -> Place? {
        guard result.id.hasPrefix("place-") else { return nil }
        let rawID = String(result.id.dropFirst("place-".count))
        guard let uuid = UUID(uuidString: rawID) else { return nil }
        return places.first { $0.id == uuid }
    }

    private func mapCandidate(for result: SaveSearchResult) -> SaveMapCandidate? {
        guard result.id.hasPrefix("map-candidate-") else { return nil }
        let rawID = String(result.id.dropFirst("map-candidate-".count))
        return mapCandidates.first { $0.id == rawID }
    }

    private func mapAction(for response: SaveSearchResponse) -> MapActionData? {
        let placeIDs = response.fromYourSave.results.compactMap { result -> String? in
            guard result.objectType == .savedPlace || result.objectType == .triedMemory,
                  result.id.hasPrefix("place-")
            else { return nil }
            return String(result.id.dropFirst("place-".count))
        }
        guard !placeIDs.isEmpty else { return nil }
        return MapActionData(type: .filterPins, placeIds: placeIDs, lat: nil, lng: nil, span: nil)
    }

    private func showGroundedRecommendationResponse(
        _ response: SaveSearchResponse,
        query: String,
        intent: SaveSearchIntent? = nil,
        outputLanguage: AppLanguage
    ) async {
        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil
        rememberQuery(query)

        let groundedResponse: SaveSearchResponse
        if let groundedAnswerClient,
           let intent = intent ?? SaveSearchIntentParser().parse(query) {
            groundedResponse = await response.withGroundedAnswer(
                query: query,
                intent: intent,
                outputLanguage: outputLanguage,
                client: groundedAnswerClient
            )
        } else {
            groundedResponse = response
        }

        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        drawerState = .saveSearchResults(groundedResponse)
        mapAction = mapAction(for: groundedResponse)
    }

    private func showTripPlanningResponse(query: String, outputLanguage: AppLanguage) async {
        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil
        rememberQuery(query)

        do {
            let response = try await aiService.query(
                query,
                places: places,
                conversationHistory: conversationTurns,
                outputLanguage: outputLanguage
            )
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            drawerState = .displaying(response)
            mapAction = response.mapAction

            let responseJSON = aiService.encodeResponse(response)
            conversationTurns.append(ConversationTurn(userMessage: query, assistantResponse: responseJSON))
            if conversationTurns.count > 5 {
                conversationTurns.removeFirst()
            }
        } catch SaveAIError.apiKeyMissing {
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            let message = places.isEmpty
                ? outputLanguage.localized(
                    english: "Save or import a few Map Stamps first, then ask SAV-E to plan from them.",
                    traditionalChinese: "先保存或匯入幾個地圖章，再請 SAV-E 從你的地點開始規劃。"
                )
                : outputLanguage.localized(
                    english: "I could not find matching saved Map Stamps for that trip. Add a city, choose saved places, or ask SAV-E to search public discovery separately.",
                    traditionalChinese: "我找不到符合這趟行程的已存地圖章。可以補城市、選幾個已存地點，或另外請 SAV-E 搜尋公開探索。"
                )
            drawerState = .displaying(SaveAIResponse(
                componentType: .message,
                title: outputLanguage.localized(
                    english: "Need trip anchors",
                    traditionalChinese: "需要行程錨點"
                ),
                placeIds: [],
                navigationPlaceId: nil,
                transportMode: .walking,
                itineraryDays: [],
                messageText: message,
                mapAction: nil,
                aiMessage: message
            ))
        } catch {
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            drawerState = .error(error.localizedDescription)
        }
    }

    private func rememberQuery(_ query: String) {
        if chatHistory.first?.query != query {
            chatHistory.insert(ChatEntry(query: query, timestamp: Date()), at: 0)
            if chatHistory.count > 20 { chatHistory.removeLast() }
        }
    }
}

private extension SaveSearchResponse {
    var hasVisibleResults: Bool {
        !fromYourSave.results.isEmpty ||
            !additionalSections.flatMap(\.results).isEmpty ||
            !newRecommendations.results.isEmpty
    }

    func withGroundedAnswer(
        query: String,
        intent: SaveSearchIntent,
        outputLanguage: AppLanguage,
        client: SaveLLMClient
    ) async -> SaveSearchResponse {
        let grounding = groundedAnswerGrounding
        let request = GroundedAnswerRequest(
            query: query,
            intent: intent,
            allowedPlaceIds: grounding.allowedResultIDs,
            sections: groundedAnswerSections,
            outputLanguage: outputLanguage
        )

        guard grounding.hasContext else {
            return self
        }

        do {
            let answer = try await client.renderGroundedAnswer(request)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return self }
            var copy = self
            copy.replaceAgentAnswer(answer, source: .groundedLLM)
            return copy
        } catch {
            return self
        }
    }
}

private extension AIDrawerViewModel {
    func recommendationIntent(for query: String) async -> SaveSearchIntent? {
        let deterministic = SaveSearchIntentParser().parse(query)
        if let deterministic,
           !deterministic.requiredCategories.isEmpty || deterministic.unsupportedCategoryLabel != nil {
            return deterministic
        }
        guard let groundedAnswerClient else {
            return deterministic
        }
        let request = IntentParseRequest(
            query: query,
            allowedCategories: PlaceCategory.allCases
        )
        guard let llmIntent = try? await groundedAnswerClient.parseIntent(request) else {
            return deterministic
        }
        return llmIntent
    }
}
