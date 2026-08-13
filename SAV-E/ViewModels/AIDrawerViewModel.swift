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
        case error(String)
    }

    @Published var drawerState: DrawerState = .idle
    @Published var query = ""
    @Published var mapAction: MapActionData?
    @Published var chatHistory: [ChatEntry] = []
    @Published var activeCommandTab: CommandDrawerTab = .review

    struct ChatEntry: Identifiable, Equatable {
        let id = UUID()
        let query: String
        let timestamp: Date
    }

    @Published var places: [Place] = []
    @Published var mapCandidates: [SaveMapCandidate] = []
    @Published private(set) var memoryPreferences: [SaveMemoryPreference] = []

    private let aiService: SaveAIService
    private let saveSearchController: SaveSearchController
    private let locationIntentRecommendationService: SaveLocationIntentRecommendationService
    private let locationService: any AIDrawerLocationProviding
    private let mapCandidateSearchService: MapCandidateSearchServiceProtocol
    private let groundedAnswerClient: SaveLLMClient?
    private let persistenceService: SupabaseServiceProtocol
    private let tripRouteService: TripRouteServiceProtocol
    private let tripHoursAnnotator: TripHoursAnnotator
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
        persistenceService: SupabaseServiceProtocol = SupabaseService.shared,
        tripRouteService: TripRouteServiceProtocol = GoogleTripRouteService(),
        tripHoursProvider: TripHoursProviding = GoogleTripHoursService()
    ) {
        self.aiService = aiService
        self.saveSearchController = saveSearchController
        self.locationIntentRecommendationService = locationIntentRecommendationService
        self.locationService = locationService ?? LocationService.shared
        self.mapCandidateSearchService = mapCandidateSearchService
        self.groundedAnswerClient = groundedAnswerClient
        self.persistenceService = persistenceService
        self.tripRouteService = tripRouteService
        self.tripHoursAnnotator = TripHoursAnnotator(hoursProvider: tripHoursProvider)
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
                preferences: memoryPreferences,
                currentLocation: currentLocation,
                outputLanguage: outputLanguage
            )
        } ?? locationIntentRecommendationService.recommendationSearchResponse(
            for: trimmed,
            places: places,
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates,
            preferences: memoryPreferences,
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

    /// Preference memory is an explicit, owner-scoped durable input. Request
    /// context and implicit place-derived taste never promote into this list.
    func loadMemoryPreferences() async {
        do {
            memoryPreferences = try await persistenceService.fetchMemoryPreferences()
        } catch {
            logger.error("Preference refresh failed")
        }
    }

    func showSearchResult(_ result: SaveSearchResult) {
        switch result.objectType {
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

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
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
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
    }

    func returnToCommands() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        lastSaveSearchResponse = nil
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
    }

    func cancelCurrentRequest() {
        activeRequestID = nil
        drawerState = .idle
        query = ""
        lastSaveSearchResponse = nil
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
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

    /// "Plan around this Map Stamp" is the trip planner anchored on one saved
    /// place: same deterministic selection, route optimization, travel legs,
    /// hours annotation, and save-as-trip rail as a typed planning question.
    func showPlanAround(
        anchor place: Place,
        reviewCandidates: [PlaceReviewCandidate] = [],
        outputLanguage: AppLanguage = .english
    ) async {
        guard places.contains(where: { $0.id == place.id }) else {
            showMessage(
                title: outputLanguage.localized(english: "Need saved place", traditionalChinese: "需要已保存地點"),
                message: outputLanguage.localized(
                    english: "Save this as a Map Stamp before planning around it.",
                    traditionalChinese: "請先保存成地圖章，再用它規劃周邊行程。"
                )
            )
            return
        }

        let query = outputLanguage.localized(
            english: "Plan a day around \(place.name)",
            traditionalChinese: "以「\(place.name)」規劃一天行程"
        )
        // The raw message carries the anchor's name, which the deterministic
        // planner scores as the primary anchor and fills the day with saved
        // places nearby. No search terms: nothing else is being requested.
        let intent = TripPlanningIntent(days: 1, searchTerms: [], rawMessage: query)
        await showTripPlanningResponse(
            query: query,
            outputLanguage: outputLanguage,
            intentOverride: intent
        )
    }

    func resolvePlaces(from ids: [String]) -> [Place] {
        let uuids = Set(ids.compactMap { UUID(uuidString: $0) })
        return places.filter { uuids.contains($0.id) }
    }

    func resolvePlace(id: String?) -> Place? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return places.first { $0.id == uuid }
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
        let context = groundedContext(for: query)
        rememberQuery(query)

        // Natural-language queries still get a grounded LLM answer even when
        // the deterministic classifier could not extract an intent, instead of
        // degrading to a raw literal-match list.
        let resolvedIntent = intent
            ?? SaveSearchIntentParser().parse(query)
            ?? (SaveSearchLLMRouter.isNaturalLanguageQuery(query) ? .freeformFallback(rawText: query) : nil)

        let groundedResponse: SaveSearchResponse
        if let groundedAnswerClient, let resolvedIntent {
            groundedResponse = await response.withGroundedAnswer(
                query: query,
                intent: resolvedIntent,
                context: context,
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
        let context = groundedContext(for: query)
        rememberQuery(query)

        let intent = SaveSearchIntentParser().parse(previousResponse.query) ?? SaveSearchIntent.freeformFallback(
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
            context: context,
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

    /// Reads the request through the LLM when one is configured, falling back
    /// to literal parsing on any failure.
    ///
    /// The fallback is not just for offline: planning must never wait on the
    /// network longer than a person will wait for an itinerary, and the
    /// deterministic reading is always good enough to produce a plan. Only
    /// extraction is delegated — selection, routing, and scheduling stay local,
    /// so a hallucinated term can at worst narrow the plan, never populate it.
    func tripPlanningIntent(
        for query: String,
        planner: DeterministicTripPlanner
    ) async -> TripPlanningIntent {
        let fallback = planner.deterministicIntent(from: query)
        guard let groundedAnswerClient else { return fallback }

        let request = TripIntentParseRequest(
            query: query,
            savedAreaHints: Self.savedAreaHints(from: places)
        )
        let extraction = Task { try await groundedAnswerClient.parseTripIntent(request) }
        let timeout = Task {
            try await Task.sleep(nanoseconds: UInt64(Self.tripIntentTimeout * 1_000_000_000))
            extraction.cancel()
        }
        defer { timeout.cancel() }

        do {
            return try await extraction.value
        } catch {
            return fallback
        }
    }

    static let tripIntentTimeout: Double = 4
    static let maxSavedAreaHints = 8

    /// City/area labels only — the same granularity the grounded-answer
    /// context already sends, ordered so the user's densest areas come first.
    static func savedAreaHints(from places: [Place]) -> [String] {
        var counts: [String: Int] = [:]
        for place in places {
            guard let label = SavedPlaceTripRecommender.areaLabel(for: place) else { continue }
            counts[label, default: 0] += 1
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(maxSavedAreaHints)
            .map(\.key)
    }

    private func showTripPlanningResponse(
        query: String,
        outputLanguage: AppLanguage,
        intentOverride: TripPlanningIntent? = nil
    ) async {
        let requestID = UUID()
        activeRequestID = requestID
        drawerState = .loading
        mapAction = nil
        rememberQuery(query)

        do {
            let planner = DeterministicTripPlanner()
            let intent: TripPlanningIntent
            if let intentOverride {
                intent = intentOverride
            } else {
                intent = await tripPlanningIntent(for: query, planner: planner)
            }
            let deterministicDraft = await planner.routeEnhancedPlan(
                intent: intent,
                places: places,
                outputLanguage: outputLanguage,
                routeService: tripRouteService
            )
            guard let deterministicDraft else {
                guard activeRequestID == requestID else { return }
                activeRequestID = nil
                drawerState = .displaying(Self.tripAnchorMessageResponse(
                    query: query,
                    places: places,
                    hasPlaces: !places.isEmpty,
                    outputLanguage: outputLanguage
                ))
                mapAction = nil
                return
            }
            if deterministicDraft.componentType == .message {
                guard activeRequestID == requestID else { return }
                activeRequestID = nil
                drawerState = .displaying(deterministicDraft)
                mapAction = nil
                return
            }

            let deterministicPlaceIDs = Set(
                (deterministicDraft.placeIds + [deterministicDraft.navigationPlaceId].compactMap { $0 })
                    .compactMap(UUID.init(uuidString:))
            )
            let deterministicPlaces = places.filter { deterministicPlaceIDs.contains($0.id) }
            let publicCandidates = await publicDiscoveryCandidates(for: query, scopedPlaces: deterministicPlaces)
            let polished = try await aiService.query(
                query,
                places: deterministicPlaces,
                publicCandidates: publicCandidates,
                conversationHistory: conversationTurns,
                outputLanguage: outputLanguage,
                deterministicDraftOverride: deterministicDraft,
                requiredPlaceIDs: Set(deterministicPlaces.map { $0.id.uuidString })
            )
            // Best-effort hours check: verified-open stops lose their hours
            // risk; stops closed at their slot gain an explicit hours gap.
            let response = await tripHoursAnnotator.annotated(
                polished,
                places: deterministicPlaces,
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
            drawerState = .displaying(Self.tripAnchorMessageResponse(
                query: query,
                places: places,
                hasPlaces: !places.isEmpty,
                outputLanguage: outputLanguage
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

    /// Bounded user context for the grounded LLM answer. Built before
    /// `rememberQuery` so the current query is not echoed back as history.
    private func groundedContext(for query: String) -> GroundedAnswerContext {
        SaveDrawerContextBuilder.makeContext(
            query: query,
            places: places,
            currentLocation: locationService.currentLocation,
            recentQueries: chatHistory.prefix(SaveDrawerContextBuilder.maxRecentQueries).map(\.query),
            lastAssistantAnswer: lastSaveSearchResponse?.resolvedAgentAnswer?.message
                ?? lastSaveSearchResponse?.assistantMessage
        )
    }

    private static func tripAnchorMessageResponse(
        query: String,
        places: [Place],
        hasPlaces: Bool,
        outputLanguage: AppLanguage
    ) -> SaveAIResponse {
        let message = hasPlaces
            ? outputLanguage.localized(
                english: "I could not find matching saved Map Stamps for that trip. Add a city, choose saved places, or ask SAV-E to search public discovery separately.",
                traditionalChinese: "我找不到符合這趟行程的已存地圖章。可以補城市、選幾個已存地點，或另外請 SAV-E 搜尋公開探索。"
            )
            : outputLanguage.localized(
                english: "Save or import a few Map Stamps first, then ask SAV-E to plan from them.",
                traditionalChinese: "先保存或匯入幾個地圖章，再請 SAV-E 從你的地點開始規劃。"
            )
        return SaveAIResponse(
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
            aiMessage: message,
            followUpChoices: tripAnchorChoices(query: query, places: places, outputLanguage: outputLanguage)
        )
    }

    private static func tripAnchorChoices(query: String, places: [Place], outputLanguage: AppLanguage) -> [SaveSearchFollowUpChoice] {
        let dayText = tripDurationText(from: query, outputLanguage: outputLanguage)
        let savedDestinations = destinationChoices(from: places)
        var choices: [SaveSearchFollowUpChoice] = []

        for destination in savedDestinations.prefix(2) {
            choices.append(SaveSearchFollowUpChoice(
                id: "trip-anchor-\(TripDestinationScope.normalizeID(destination))",
                label: "\(destination) \(dayText)",
                prompt: outputLanguage.localized(
                    english: "Plan a \(dayText) \(destination) itinerary from my saved Map Stamps.",
                    traditionalChinese: "規劃\(destination) \(dayText)行程"
                ),
                systemImage: "mappin.and.ellipse"
            ))
        }

        let publicDestination = broadDestinationHint(from: query) ?? TripDestinationScope.destinationHint(from: query) ?? outputLanguage.localized(
            english: "this city",
            traditionalChinese: "這個城市"
        )
        choices.append(SaveSearchFollowUpChoice(
            id: "trip-public-discovery",
            label: outputLanguage.localized(english: "Find public options", traditionalChinese: "找公開景點"),
            prompt: outputLanguage.localized(
                english: "Search public activities and attractions for \(publicDestination).",
                traditionalChinese: "搜尋\(publicDestination)公開景點和活動"
            ),
            systemImage: "location.magnifyingglass"
        ))

        choices.append(SaveSearchFollowUpChoice(
            id: "trip-show-saved",
            label: outputLanguage.localized(english: "Show saved places", traditionalChinese: "看已存地點"),
            prompt: outputLanguage.localized(
                english: "Show my saved places that can anchor a trip.",
                traditionalChinese: "顯示可以當行程錨點的已存地點"
            ),
            systemImage: "bookmark"
        ))

        return Array(choices.prefix(4))
    }

    private static func broadDestinationHint(from query: String) -> String? {
        let normalized = query
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        if normalized.contains("加州") {
            return "加州"
        }
        if normalized.contains("california") {
            return "California"
        }
        return nil
    }

    private static func destinationChoices(from places: [Place]) -> [String] {
        var destinations: [String] = []
        for place in places {
            guard let destination = TripDestinationScope.destinationHint(from: "\(place.name) \(place.address)") else {
                continue
            }
            if !destinations.contains(destination) {
                destinations.append(destination)
            }
        }
        return destinations
    }

    private static func tripDurationText(from query: String, outputLanguage: AppLanguage) -> String {
        let normalized = query.lowercased()
        let patterns = [
            #"(\d+)\s*[- ]?\s*days?"#,
            #"(\d+)\s*[- ]?\s*day"#,
            #"(\d+)\s*[天日]"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: normalized),
               let value = Int(normalized[range]) {
                return outputLanguage == .traditionalChinese ? "\(value) 天" : "\(value) days"
            }
        }
        if normalized.contains("weekend") {
            return outputLanguage == .traditionalChinese ? "週末" : "weekend"
        }
        return outputLanguage == .traditionalChinese ? "1 天" : "1 day"
    }

    private func publicDiscoveryCandidates(for query: String, scopedPlaces: [Place]) async -> [SaveMapCandidate] {
        guard ItineraryPublicDiscoveryPlanner.shouldPreparePublicActivityCandidates(query: query, savedPlaces: scopedPlaces) else {
            return []
        }

        let coordinate = scopedPlaces.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            ?? locationService.currentLocation?.coordinate
        let span = MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        var results: [SaveMapCandidate] = []
        var seen: Set<String> = []

        for searchQuery in ItineraryPublicDiscoveryPlanner.publicActivitySearchQueries(for: query, savedPlaces: scopedPlaces) {
            let candidates = await mapCandidateSearchService.searchCandidates(
                matching: searchQuery,
                near: coordinate,
                span: span,
                excluding: scopedPlaces
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
            "budget", "vibe", "takeout", "sit-down", "save one", "pick one",
            "為什麼", "为什么", "推薦這些", "推荐这些", "這些", "这些", "哪個", "哪个",
            "怎麼選", "怎么选", "原因", "比較", "比较", "不懂", "看不懂",
            "預算", "氛圍", "氣氛", "外帶", "坐一下", "保存", "挑一個", "縮小"
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
        let destination = TripDestinationScope.destinationHint(from: query) ?? TripDestinationScope.destinationHint(from: savedPlaces)
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
        context: GroundedAnswerContext = GroundedAnswerContext(),
        outputLanguage: AppLanguage,
        client: SaveLLMClient
    ) async -> SaveSearchResponse {
        let grounding = groundedAnswerGrounding
        let request = GroundedAnswerRequest(
            query: query,
            intent: intent,
            allowedPlaceIds: grounding.allowedResultIDs,
            sections: groundedAnswerSections,
            outputLanguage: outputLanguage,
            context: context
        )

        guard grounding.hasContext, shouldUseGroundedLLMAnswer else {
            return self
        }

        // Retry once on transient failures; on the second failure keep the
        // deterministic assistant message so the drawer never dead-ends.
        let answer: GroundedLLMAnswer?
        do {
            answer = try await client.renderGroundedAnswer(request)
        } catch {
            answer = try? await client.renderGroundedAnswer(request)
        }
        guard let answer else { return self }
        let message = answer.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return self }
        var copy = self
        copy.replaceAgentAnswer(message, source: .groundedLLM)
        return copy
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
        // Confident lexicon hits skip the LLM round trip; only low-confidence
        // natural-language queries pay for the structured extraction step.
        if SaveSearchLLMRouter.shouldTrustDeterministicIntent(deterministic) {
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

extension SaveAIResponse {
    static func planAroundPublicCandidates(
        _ candidates: [SaveMapCandidate],
        acceptedBy draft: SavePlanAroundDraft
    ) -> [SaveMapCandidate] {
        let acceptedIDs = Set(draft.routeStops.compactMap(\.mapCandidateID))
        return candidates.filter { acceptedIDs.contains($0.id) }
    }

    static func planAroundDraft(_ draft: SavePlanAroundDraft, outputLanguage: AppLanguage) -> SaveAIResponse {
        let savedPlaceIDs = draft.routeStops.compactMap(\.savedPlaceUUIDString)
        let stops = draft.routeStops.enumerated().map { index, stop in
            let evidence = stop.evidence.isEmpty ? nil : "Evidence: \(stop.evidence.joined(separator: "; "))"
            let sourceSummary = stop.itinerarySourceSummary(outputLanguage: outputLanguage)
            let noteParts = [
                sourceSummary,
                stop.distanceLabel.map { "\($0) from anchor" },
                stop.reason,
                evidence,
                index > 0 && draft.routeNotes.indices.contains(index - 1) ? draft.routeNotes[index - 1] : nil
            ].compactMap { $0 }
            return ItineraryStop(
                id: UUID(),
                placeId: stop.savedPlaceUUIDString,
                placeState: stop.itineraryPlaceState,
                placeName: stop.title,
                time: nil,
                duration: suggestedDurationMinutes(for: stop),
                note: noteParts.joined(separator: " · "),
                sourceSummary: sourceSummary,
                risks: stop.itineraryRisks
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
        let transportMode: SaveAIResponse.TransportMode = draft.routeStops.count > 3 ? .driving : .walking
        return SaveAIResponse(
            componentType: .tripItinerary,
            title: title,
            placeIds: savedPlaceIDs,
            navigationPlaceId: draft.anchor.savedPlaceUUIDString,
            transportMode: transportMode,
            itineraryDays: [ItineraryDay(dayNumber: 1, label: title, stops: stops)],
            messageText: nil,
            mapAction: savedPlaceIDs.count >= 2
                ? MapActionData(
                    type: .showRoute,
                    placeIds: savedPlaceIDs,
                    lat: nil,
                    lng: nil,
                    span: nil,
                    transportMode: transportMode
                )
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
    var mapCandidateID: String? {
        guard source == .unsavedMapCandidate, id.hasPrefix("map-candidate-") else { return nil }
        return String(id.dropFirst("map-candidate-".count))
    }

    var savedPlaceUUIDString: String? {
        guard id.hasPrefix("place-") else { return nil }
        let raw = String(id.dropFirst("place-".count))
        guard UUID(uuidString: raw) != nil else { return nil }
        return raw
    }

    var itineraryPlaceState: ItineraryPlaceState {
        switch source {
        case .anchor, .userSaved:
            return .confirmedMapStamp
        case .pendingCandidate:
            return .reviewCandidate
        case .unsavedMapCandidate:
            return .externalSuggestion
        }
    }

    var itineraryRisks: [TripRisk] {
        switch source {
        case .anchor, .userSaved:
            return [.hoursUnknown, .bookingUnknown]
        case .pendingCandidate:
            return [.needsReview, .hoursUnknown, .bookingUnknown]
        case .unsavedMapCandidate:
            return [.externalSuggestion, .hoursUnknown, .bookingUnknown]
        }
    }

    func itinerarySourceSummary(outputLanguage: AppLanguage) -> String {
        switch source {
        case .anchor, .userSaved:
            return outputLanguage.localized(english: "From your SAV-E", traditionalChinese: "來自你的 SAV-E")
        case .pendingCandidate:
            return outputLanguage.localized(english: "Review candidate", traditionalChinese: "待確認候選")
        case .unsavedMapCandidate:
            return outputLanguage.localized(english: "New recommendation", traditionalChinese: "新推薦")
        }
    }
}
