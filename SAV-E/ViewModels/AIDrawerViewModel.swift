import CoreLocation
import Foundation
import MapKit
import OSLog

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
    private let mapCandidateSearchService: MapCandidateSearchServiceProtocol
    private let groundedAnswerClient: SaveLLMClient?
    private let persistenceService: SupabaseServiceProtocol
    private let logger = Logger(subsystem: "SAV-E", category: "RecommendationAnalysisReceipt")

    /// Multi-turn conversation context for the current session.
    private var conversationTurns: [ConversationTurn] = []
    private var activeRequestID: UUID?
    private var lastSaveSearchResponse: SaveSearchResponse?

    init(
        aiService: SaveAIService = .shared,
        saveSearchController: SaveSearchController = SaveSearchController(),
        locationIntentRecommendationService: SaveLocationIntentRecommendationService = SaveLocationIntentRecommendationService(),
        locationService: (any AIDrawerLocationProviding)? = nil,
        mapCandidateSearchService: MapCandidateSearchServiceProtocol = MapCandidateSearchService(),
        groundedAnswerClient: SaveLLMClient? = GeminiSaveLLMClient.liveFromConfig(),
        persistenceService: SupabaseServiceProtocol = SupabaseService.shared
    ) {
        self.aiService = aiService
        self.saveSearchController = saveSearchController
        self.locationIntentRecommendationService = locationIntentRecommendationService
        self.locationService = locationService ?? LocationService.shared
        self.mapCandidateSearchService = mapCandidateSearchService
        self.groundedAnswerClient = groundedAnswerClient
        self.persistenceService = persistenceService
    }

    func submit(
        reviewCandidates: [PlaceReviewCandidate] = [],
        outputLanguage: AppLanguage = .english
    ) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if isFollowUpToLastSearch(trimmed),
           let lastSaveSearchResponse,
           let groundedAnswerClient {
            await showSearchFollowUpResponse(
                lastSaveSearchResponse,
                query: trimmed,
                outputLanguage: outputLanguage,
                client: groundedAnswerClient
            )
            return
        }

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
                currentLocation: currentLocation,
                outputLanguage: outputLanguage
            )
        } ?? locationIntentRecommendationService.recommendationSearchResponse(
            for: trimmed,
            places: places,
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates,
            currentLocation: currentLocation,
            outputLanguage: outputLanguage
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
        lastSaveSearchResponse = nil
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
    }

    func startNewConversation() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        conversationTurns = []
        lastSaveSearchResponse = nil
    }

    func returnToCommands() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        lastSaveSearchResponse = nil
    }

    func cancelCurrentRequest() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        lastSaveSearchResponse = nil
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

    func shouldPrepareMapCandidates(for query: String) -> Bool {
        saveSearchController.shouldPrepareMapCandidates(for: query)
    }

    func shouldSearchExactMapCandidates(for query: String) -> Bool {
        saveSearchController.exactMapCandidateQuery(for: query) != nil
    }

    func showCollaborativeListPlan(_ list: SaveCollaborativeList) {
        drawerState = .displaying(list.itineraryResponse())
    }

    func showFoodPlaceAnalysis(for place: Place, outputLanguage: AppLanguage = .english) {
        let response = FoodPlaceAnalysisService().whatShouldIOrder(at: place, outputLanguage: outputLanguage)
        drawerState = .displaying(response)
        mapAction = response.mapAction
    }

    func showPlanAround(
        anchor place: Place,
        reviewCandidates: [PlaceReviewCandidate] = [],
        outputLanguage: AppLanguage = .english,
        duration: SavePlanDuration = .halfDay,
        intent: SavePlanIntent = .balanced
    ) async {
        let response = saveSearchController.search(
            query: "",
            places: places,
            localRecords: [],
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates
        )
        let allSavedResults = response.fromYourSave.results + response.additionalSections.flatMap(\.results)
        let anchorID = "place-\(place.id.uuidString)"
        guard let anchor = allSavedResults.first(where: { $0.id == anchorID }) else {
            showMessage(
                title: outputLanguage.localized(english: "Need saved place", traditionalChinese: "需要已保存地點"),
                message: outputLanguage.localized(
                    english: "Save this as a Map Stamp before planning around it.",
                    traditionalChinese: "請先保存成地圖章，再用它規劃周邊行程。"
                )
            )
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil

        let request = SavePlanAroundRequest(anchorResultID: anchor.id, duration: duration, intent: intent)
        let result = SavePlanAroundController().planAround(
            anchor: anchor,
            savedResults: allSavedResults,
            mapCandidates: mapCandidates,
            request: request
        )
        switch result {
        case .draft(let draft):
            let prompt = planAroundPrompt(for: draft, outputLanguage: outputLanguage)
            let deterministicResponse = SaveAIResponse.planAroundDraft(draft, outputLanguage: outputLanguage)
            let savedRoutePlaceIDs = Set(draft.routeStops.compactMap(\.savedPlaceUUIDString).compactMap(UUID.init(uuidString:)))
            let routePlaces = places.filter { savedRoutePlaceIDs.contains($0.id) }
            let polishedResponse = await aiService.polishItineraryDraft(
                deterministicResponse,
                userMessage: prompt,
                places: routePlaces,
                publicCandidates: mapCandidates,
                outputLanguage: outputLanguage,
                requiredPlaceIDs: [place.id.uuidString]
            )
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            drawerState = .displaying(polishedResponse)
            mapAction = polishedResponse.mapAction

            let responseJSON = aiService.encodeResponse(polishedResponse)
            conversationTurns.append(ConversationTurn(userMessage: prompt, assistantResponse: responseJSON))
            if conversationTurns.count > 5 {
                conversationTurns.removeFirst()
            }
        case .blocked(let state):
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            showMessage(title: state.title, message: state.message)
        }
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
        lastSaveSearchResponse = groundedResponse
        mapAction = mapAction(for: groundedResponse)
        Task { await recordRecommendationAnalysisReceiptIfNeeded(for: groundedResponse) }
    }

    private func showSearchFollowUpResponse(
        _ previousResponse: SaveSearchResponse,
        query: String,
        outputLanguage: AppLanguage,
        client: SaveLLMClient
    ) async {
        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil
        rememberQuery(query)

        let intent = SaveSearchIntentParser().parse(previousResponse.query) ?? SaveSearchIntent.followUpIntent(
            rawText: previousResponse.query
        )
        let followUpQuery = """
        Follow-up question: \(query)
        Previous SAV-E query: \(previousResponse.query)
        Explain or narrow only the previous visible results.
        """
        let groundedResponse = await previousResponse.withGroundedAnswer(
            query: followUpQuery,
            intent: intent,
            outputLanguage: outputLanguage,
            client: client
        )

        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        drawerState = .saveSearchResults(groundedResponse)
        lastSaveSearchResponse = groundedResponse
        mapAction = mapAction(for: groundedResponse)
        Task { await recordRecommendationAnalysisReceiptIfNeeded(for: groundedResponse) }
    }

    private func showTripPlanningResponse(query: String, outputLanguage: AppLanguage) async {
        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil
        rememberQuery(query)

        do {
            let publicCandidates = await publicDiscoveryCandidates(for: query)
            let response = try await aiService.query(
                query,
                places: places,
                publicCandidates: publicCandidates,
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

    private func planAroundPrompt(for draft: SavePlanAroundDraft, outputLanguage: AppLanguage) -> String {
        let stops = draft.routeStops.enumerated().map { index, stop in
            let marker = stop.sourceLabel
            let distance = stop.distanceLabel.map { ", \($0) from anchor" } ?? ""
            let filler = stop.fillerSlot.map { ", fills \($0.displayName)" } ?? ""
            let placeID = stop.savedPlaceUUIDString ?? "null"
            return "\(index + 1). \(stop.title) (placeId: \(placeID), source: \(marker)\(distance)\(filler))"
        }.joined(separator: "\n")
        let gaps = draft.unfilledGaps.isEmpty
            ? "none"
            : draft.unfilledGaps.map(\.displayName).joined(separator: ", ")

        return outputLanguage.localized(
            english: """
            Plan a \(draft.request.duration.displayName.lowercased()) \(draft.request.intent.displayName.lowercased()) route around \(draft.anchor.title).
            Turn these approved candidates into a useful itinerary. You may reorder stops, assign smarter time slots, regroup by day, and drop optional non-anchor stops if the route would be unrealistic. Keep the anchor and every non-null placeId valid. Public recommendations must keep placeId null, source "New recommendation", and their exact candidate name.
            Unfilled gaps: \(gaps).
            Retrieval receipt: \(draft.retrievalReceipt.querySelector)
            \(stops)
            """,
            traditionalChinese: """
            請用「\(draft.anchor.title)」周邊規劃一個\(draft.request.duration.displayName.lowercased())、\(draft.request.intent.displayName.lowercased())行程。
            請把這些已核准候選整理成實用行程。你可以調整順序、安排更合理的時間、重新分天，也可以刪掉非錨點的 optional stop，避免路線不合理。必須保留錨點，所有非 null placeId 都必須有效。公開推薦必須維持 placeId null、來源維持「New recommendation」，並使用精確候選名稱。
            尚未補上的空缺：\(gaps)。
            檢索 receipt：\(draft.retrievalReceipt.querySelector)
            \(stops)
            """
        )
    }

    private func publicDiscoveryCandidates(for query: String) async -> [SaveMapCandidate] {
        guard ItineraryPublicDiscoveryPlanner.shouldPreparePublicActivityCandidates(query: query, savedPlaces: places) else {
            return []
        }

        let coordinate = locationService.currentLocation?.coordinate
            ?? places.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let span = MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        var results: [SaveMapCandidate] = []
        var seen: Set<String> = []

        for searchQuery in ItineraryPublicDiscoveryPlanner.publicActivitySearchQueries(for: query, savedPlaces: places) {
            let candidates = await mapCandidateSearchService.searchCandidates(
                matching: searchQuery,
                near: coordinate,
                span: span,
                excluding: places
            )
            for candidate in candidates where ItineraryPublicDiscoveryPlanner.isPublicActivityCandidate(candidate) {
                let key = "\(candidate.title.lowercased())|\(candidate.subtitle.lowercased())"
                guard seen.insert(key).inserted else { continue }
                results.append(candidate)
            }
        }

        return Array(results.prefix(8))
    }

    private func recordRecommendationAnalysisReceiptIfNeeded(for response: SaveSearchResponse) async {
        guard let receipt = response.recommendationAnalysisReceiptDraft() else { return }
        do {
            _ = try await persistenceService.recordRecommendationAnalysisReceipt(receipt)
        } catch {
            logger.debug("Recommendation analysis receipt recording skipped")
        }
    }

    private func isFollowUpToLastSearch(_ query: String) -> Bool {
        guard lastSaveSearchResponse?.groundedAnswerGrounding.hasContext == true else { return false }
        let normalized = SaveSearchIntentParser.normalize(query)
        let followUpNeedles = [
            "why", "explain", "reason", "these", "those", "which", "compare", "narrow",
            "為什麼", "为什么", "推薦這些", "推荐这些", "這些", "这些", "哪個", "哪个",
            "怎麼選", "怎么选", "原因", "比較", "比较", "不懂", "看不懂"
        ]
        return followUpNeedles.contains { normalized.contains($0) }
    }
}

struct ItineraryPublicDiscoveryPlanner {
    private static let foodDrinkCategories: Set<PlaceCategory> = [.food, .cafe, .bar]
    private static let activityCategories: Set<PlaceCategory> = [.attraction, .shopping]

    static func shouldPreparePublicActivityCandidates(query: String, savedPlaces: [Place]) -> Bool {
        guard DeterministicTripPlanner().isItineraryRequest(query) else { return false }
        guard !savedPlaces.isEmpty else { return false }

        let savedCategories = Set(savedPlaces.map(\.category))
        let hasActivity = !savedCategories.isDisjoint(with: activityCategories)
        let allFoodDrink = savedCategories.isSubset(of: foodDrinkCategories)
        return allFoodDrink || !hasActivity
    }

    static func publicActivitySearchQueries(for query: String, savedPlaces: [Place]) -> [String] {
        let destination = destinationHint(from: query) ?? destinationHint(from: savedPlaces)
        let prefix = destination.map { "\($0) " } ?? ""
        return [
            "\(prefix)景點",
            "\(prefix)things to do",
            "\(prefix)museum park"
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func isPublicActivityCandidate(_ candidate: SaveMapCandidate) -> Bool {
        guard let category = candidate.category else { return true }
        return activityCategories.contains(category)
    }

    private static func destinationHint(from query: String) -> String? {
        let normalized = query
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let knownDestinations: [(needle: String, destination: String)] = [
            ("台北", "台北"),
            ("臺北", "台北"),
            ("taipei", "Taipei"),
            ("台南", "台南"),
            ("臺南", "台南"),
            ("tainan", "Tainan"),
            ("高雄", "高雄"),
            ("kaohsiung", "Kaohsiung"),
            ("東京", "東京"),
            ("tokyo", "Tokyo"),
            ("首爾", "首爾"),
            ("seoul", "Seoul"),
            ("los angeles", "Los Angeles"),
            (" la ", "Los Angeles"),
            ("anaheim", "Anaheim"),
            ("irvine", "Irvine")
        ]

        let padded = " \(normalized) "
        return knownDestinations.first { padded.contains($0.needle) || normalized.contains($0.needle) }?.destination
    }

    private static func destinationHint(from places: [Place]) -> String? {
        let joinedAddresses = places.map(\.address).joined(separator: " ")
        return destinationHint(from: joinedAddresses)
    }
}

private extension SaveSearchIntent {
    static func followUpIntent(rawText: String) -> SaveSearchIntent {
        let normalized = SaveSearchIntentParser.normalize(rawText)
        return SaveSearchIntent(
            rawText: rawText,
            normalizedText: normalized,
            kind: .unknown,
            requiredCategories: [],
            optionalCategories: [],
            locationMode: .unspecified,
            sourceScope: .savedFirstAllowPublicFallback,
            mustMatchCategory: false,
            mustMatchLocation: false,
            confidence: 0.5,
            unsupportedCategoryLabel: nil,
            categoryNeedles: []
        )
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

        guard grounding.hasContext, shouldUseGroundedLLMAnswer else {
            return self
        }

        do {
            let answer = try await client.renderGroundedAnswer(request)
            let message = answer.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return self }
            var copy = self
            copy.replaceAgentAnswer(message, source: .groundedLLM)
            return copy
        } catch {
            return self
        }
    }

    private var shouldUseGroundedLLMAnswer: Bool {
        let savedOrReviewContext = saveUsedEvidenceSections.contains { section in
            section.results.contains { result in
                switch result.objectType {
                case .savedPlace, .triedMemory, .pendingCandidate, .sourceOnlyClue:
                    return true
                default:
                    return false
                }
            }
        }
        if savedOrReviewContext { return true }

        // Public-only nearby discovery needs deterministic copy: first tell the user
        // SAV-E has no matching memory, then show unsaved public candidates as a list.
        // Letting Gemini rewrite this case repeatedly caused awkward one-place answers
        // and made public results feel like SAV-E memories.
        let publicOnlyResultCount = newRecommendations.results.filter { result in
            result.objectType == .mapVisibleUnsavedPlace || result.objectType == .newRecommendation
        }.count
        return publicOnlyResultCount < 2
    }
}

private extension AIDrawerViewModel {
    func recommendationIntent(for query: String) async -> SaveSearchIntent? {
        let deterministic = SaveSearchIntentParser().parse(query)
        if let deterministic,
           deterministic.unsupportedCategoryLabel != nil ||
           (!deterministic.requiredCategories.isEmpty && deterministic.categoryNeedles.isEmpty) {
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

private extension SaveAIResponse {
    static func planAroundDraft(_ draft: SavePlanAroundDraft, outputLanguage: AppLanguage) -> SaveAIResponse {
        let savedPlaceIDs = draft.routeStops.compactMap(\.savedPlaceUUIDString)
        let stops = draft.routeStops.enumerated().map { index, stop in
            let evidence = stop.evidence.isEmpty ? nil : "Evidence: \(stop.evidence.joined(separator: "; "))"
            let noteParts = [
                stop.sourceLabel,
                stop.distanceLabel.map { "\($0) from anchor" },
                stop.reason,
                evidence,
                index > 0 && draft.routeNotes.indices.contains(index - 1) ? draft.routeNotes[index - 1] : nil
            ].compactMap { $0 }
            return ItineraryStop(
                id: UUID(),
                placeId: stop.savedPlaceUUIDString,
                placeName: stop.title,
                time: nil,
                duration: suggestedDurationMinutes(for: stop),
                note: noteParts.joined(separator: " · ")
            )
        }
        let title = outputLanguage.localized(
            english: "Plan around \(draft.anchor.title)",
            traditionalChinese: "用「\(draft.anchor.title)」規劃"
        )
        let publicNote = draft.newSuggestions.isEmpty ? "" : outputLanguage.localized(
            english: " New recommendations are clearly marked and are not saved to SAV-E unless you confirm them.",
            traditionalChinese: " New recommendation 會清楚標示；只有你確認後才會保存到 SAV-E。"
        )
        let gapNote = draft.unfilledGaps.isEmpty ? "" : outputLanguage.localized(
            english: " Public discovery could not fill: \(draft.unfilledGaps.map(\.displayName).joined(separator: ", ")).",
            traditionalChinese: " 公開探索尚未補上：\(draft.unfilledGaps.map(\.displayName).joined(separator: ", "))。"
        )
        return SaveAIResponse(
            componentType: .tripItinerary,
            title: title,
            placeIds: savedPlaceIDs,
            navigationPlaceId: draft.anchor.savedPlaceUUIDString,
            transportMode: draft.routeStops.count > 3 ? .driving : .walking,
            itineraryDays: [ItineraryDay(dayNumber: 1, label: title, stops: stops)],
            messageText: nil,
            mapAction: savedPlaceIDs.count >= 2
                ? MapActionData(type: .showRoute, placeIds: savedPlaceIDs, lat: nil, lng: nil, span: nil)
                : MapActionData(type: .focusRegion, placeIds: nil, lat: draft.anchor.latitude, lng: draft.anchor.longitude, span: 0.03),
            aiMessage: draft.explanation + publicNote + gapNote
        )
    }

    static func suggestedDurationMinutes(for stop: SavePlanStop) -> Int {
        switch stop.category {
        case .cafe: return 45
        case .food: return 90
        case .bar: return 75
        case .attraction: return 90
        case .shopping: return 60
        case .stay: return 30
        case nil: return 45
        }
    }
}

private extension SavePlanStop {
    var savedPlaceUUIDString: String? {
        guard id.hasPrefix("place-") else { return nil }
        let raw = String(id.dropFirst("place-".count))
        guard UUID(uuidString: raw) != nil else { return nil }
        return raw
    }
}
