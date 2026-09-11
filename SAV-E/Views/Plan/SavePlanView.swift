import SwiftUI
import UIKit

@MainActor
final class SavePlanConversation: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let request: String
        let reply: String
    }
    @Published var requestsNewPlan = false
    @Published private(set) var sessionID = UUID()
    @Published var input = ""
    @Published var submittedQuery: String?
    @Published var messages: [Message] = []
    @Published var draft: SaveAIResponse?
    var turns: [ConversationTurn] = []
    var agentRequest: SavePlanRequest?
    var conditions = SavePlanConversationConditions()
    @Published var assignmentPlace: Place?
    @Published var assignmentInProgress = false
    var anchorPlaceID: UUID?
    var excludedPlaceIDs = Set<UUID>()

    func updateDraftDays(_ days: [ItineraryDay], replacing source: SaveAIResponse) {
        guard draft == source else { return }
        draft = SaveAIResponse(
            componentType: source.componentType, title: source.title,
            placeIds: days.flatMap(\.stops).compactMap(\.placeId),
            navigationPlaceId: source.navigationPlaceId, transportMode: source.transportMode,
            itineraryDays: days, tripHealth: source.tripHealth, messageText: source.messageText,
            mapAction: source.mapAction, aiMessage: source.aiMessage,
            followUpChoices: source.followUpChoices, travelLegs: source.travelLegs
        )
    }

    func startNewPlan() {
        guard !assignmentInProgress else { return }
        sessionID = UUID()
        requestsNewPlan = false
        input = ""
        submittedQuery = nil
        messages = []
        draft = nil
        turns = []
        agentRequest = nil
        conditions = SavePlanConversationConditions()
        assignmentPlace = nil
        anchorPlaceID = nil
        excludedPlaceIDs = []
    }

    /// Stage an explicit place action in Plan. No submission, trip mutation,
    /// day count or pace is implied by opening this conversation.
    func stage(place: Place, addingToTrip: Bool, language: AppLanguage) {
        guard !assignmentInProgress else { return }
        if addingToTrip {
            assignmentPlace = place
            messages.append(.init(
                request: language.localized(english: "Add \(place.name) to a trip", traditionalChinese: "把「\(place.name)」加入行程"),
                reply: language.localized(english: "Which saved trip should it join, or would you like a new plan?", traditionalChinese: "要加入哪個已存行程，還是開始一份新草稿？")
            ))
        } else {
            sessionID = UUID()
            assignmentPlace = nil
            anchorPlaceID = place.id
            excludedPlaceIDs = []
            agentRequest = nil
            conditions = SavePlanConversationConditions()
            turns = []
            let area = SavePlanDraftBuilder.areaLabel(for: place)
            let location = area.map { " · \($0)" } ?? ""
            input = language.localized(english: "Plan around \(place.name)\(location)", traditionalChinese: "以「\(place.name)」為中心規劃\(location)")
        }
    }

    func assignPlace(_ place: Place, to trip: Trip, store: TripPackStore, language: AppLanguage) async {
        guard !assignmentInProgress, assignmentPlace?.id == place.id else { return }
        assignmentInProgress = true
        defer { assignmentInProgress = false }
        let added = await store.addConfirmedPlace(place, to: trip.id)
        let alreadyPresent = store.trips.first(where: { $0.id == trip.id })?.places.contains {
            place.savedIDs.contains($0.placeId)
        } ?? false
        let reply = added ? language.localized(english: "Added to your trip.", traditionalChinese: "已加入行程。")
            : alreadyPresent ? language.localized(english: "Already in your trip.", traditionalChinese: "這個地點已在行程中。")
            : (store.errorMessage ?? language.localized(english: "Couldn’t add it. Please try again.", traditionalChinese: "暫時無法加入，請再試一次。"))
        messages.append(.init(
            request: language.localized(english: "Add \(place.name) to \(trip.name)", traditionalChinese: "將「\(place.name)」加入「\(trip.name)」"),
            reply: reply
        ))
        if added || alreadyPresent { assignmentPlace = nil }
    }
}

struct SavePlanView: View {
    let savedPlaces: [Place]
    let mapCandidates: [SaveMapCandidate]
    @ObservedObject var tripStore: TripPackStore
    @ObservedObject var conversation: SavePlanConversation
    let onOpenTrip: (UUID) -> Void
    let onOpenPassport: () -> Void
    let onConfirmCandidate: (SaveMapCandidate) async throws -> Place

    @Environment(\.appLanguageSettings) private var languageSettings
    @FocusState private var isChatFocused: Bool
    @State private var keyboardOverlap: CGFloat = 0
    @State private var showsSavedTrips = false
    @State private var showsDraftDetails = false
    @State private var confirmsNewPlan = false
    private var draft: SaveAIResponse? {
        get { conversation.draft }
        nonmutating set { conversation.draft = newValue }
    }
    @State private var isPlanning = false
    @State private var planError: String?
    @State private var planningTask: Task<Void, Never>?

    private var assignmentTrips: [Trip] {
        var seen = Set<UUID>()
        return (tripStore.currentTrips + tripStore.upcomingTrips + tripStore.planningTrips)
            .filter { seen.insert($0.id).inserted }
    }

    private var areas: [String] {
        SavePlanDraftBuilder.areas(from: savedPlaces)
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                EmptyView()
            }
            .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)

            planActions
                .placed(x: 16, y: 105, width: AtlasMetrics.width - 32, height: 44)

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    if showsSavedTrips {
                        savedTripsContent
                    } else {
                        conversationContent
                            .id("conversationEnd")
                        if let draft {
                            draftCanvas(draft)
                                .disabled(isPlanning)
                                .id("latestDraft")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { if !showsSavedTrips { chatInput } }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("conversationEnd", anchor: .bottom) }
            }
            .onAppear {
                if conversation.assignmentPlace != nil { proxy.scrollTo("conversationEnd", anchor: .bottom) }
            }
            .onChange(of: conversation.draft) { _, _ in
                withAnimation { proxy.scrollTo("latestDraft", anchor: .top) }
            }
            .onChange(of: showsDraftDetails) { _, _ in
                withAnimation { proxy.scrollTo("latestDraft", anchor: .top) }
            }
            .placed(x: 0, y: 159, width: AtlasMetrics.width, height: max(160, min(620, AtlasMetrics.height - keyboardOverlap - 171)))
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let keyboard = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let frame = geometry.frame(in: .global)
            let intersection = frame.intersection(keyboard)
            keyboardOverlap = intersection.isNull ? 0 : intersection.height * geometry.size.height / max(1, frame.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOverlap = 0
        }
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .alert(localized("Start a new trip?", "開始新行程？"), isPresented: $confirmsNewPlan) {
            Button(localized("Cancel", "取消"), role: .cancel) {}
            Button(localized("Start new trip", "開始新行程"), role: .destructive) { startNewPlan() }
        } message: {
            Text(localized("This unsaved draft will be cleared. Your saved trips are kept.", "目前未儲存的草稿會清除，已存行程會保留。"))
        }
        .onChange(of: conversation.requestsNewPlan) { _, requested in
            if requested { requestNewPlan() }
        }
        .onChange(of: conversation.sessionID) { _, _ in
            planningTask?.cancel()
            isPlanning = false
            showsSavedTrips = false
            showsDraftDetails = false
        }
        .environment(\.atlasPresentation, atlasPresentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.root")
        .onAppear {
            if conversation.requestsNewPlan { requestNewPlan() }
            consumeSubmittedQuery()
        }
        .onChange(of: conversation.submittedQuery) { _, _ in consumeSubmittedQuery() }
        .onDisappear {
            planningTask?.cancel()
            isPlanning = false
        }
        .alert(
            localized("Couldn’t draft that plan", "無法排出這版行程"),
            isPresented: Binding(
                get: { planError != nil },
                set: { if !$0 { planError = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { planError = nil }
        } message: {
            Text(planError ?? "")
        }
    }

    private var planActions: some View {
        HStack(spacing: 16) {
            Button(action: requestNewPlan) {
                Label(localized("New trip", "新建行程"), systemImage: "plus")
                    .frame(minHeight: 44)
            }
            .disabled(conversation.assignmentInProgress)
            .accessibilityIdentifier("plan.newTrip")
            Spacer()
            Button {
                isChatFocused = false
                showsSavedTrips.toggle()
            } label: {
                Label(showsSavedTrips ? localized("Back to plan", "返回規劃") : localized("Saved trips", "已存行程"),
                      systemImage: showsSavedTrips ? "arrow.left" : "list.bullet")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("plan.allTrips")
        }
        .font(SaveAtlasType.body(14))
        .foregroundStyle(SaveAtlasPalette.forest)
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private var savedTripsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tripStore.trips.isEmpty {
                Text(localized("No saved trips yet. Start a new trip to plan from your saved places.", "還沒有已存行程。點「新建行程」，從已存地點開始規劃。"))
                    .font(SaveAtlasType.body(16))
            }
            ForEach(tripStore.trips) { trip in
                Button { onOpenTrip(trip.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.name).font(SaveAtlasType.strong(17))
                            Text(trip.city).font(SaveAtlasType.body(14))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .saveAtlasPaper(radius: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trip.name)
                .accessibilityHint(trip.city)
                .accessibilityIdentifier("plan.savedTrip.\(trip.id.uuidString)")
            }
        }
        .foregroundStyle(SaveAtlasPalette.forest)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.savedTrips")
    }

    private func requestNewPlan() {
        conversation.requestsNewPlan = false
        guard !conversation.assignmentInProgress else { return }
        if draft != nil {
            confirmsNewPlan = true
        } else {
            startNewPlan()
        }
    }

    private func startNewPlan() {
        planningTask?.cancel()
        isPlanning = false
        planError = nil
        conversation.startNewPlan()
        showsSavedTrips = false
        showsDraftDetails = false
        isChatFocused = true
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showsSavedTrips ? localized("Saved trips", "已存行程") : localized("Plan with Savvy", "和 Savvy 一起規劃"))
                .font(SaveAtlasType.strong(25, relativeTo: .title2))
                .foregroundStyle(SaveAtlasPalette.forest)
            Text(showsSavedTrips ? localized("Open a trip to see its places and route.", "選擇行程，查看地點與路線。") : localized("A trip from the places you’ve saved.", "從你已存的地點，聊出一趟行程。"))
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
        }
        .accessibilityIdentifier("plan.heading")
    }

    private var conversationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if conversation.messages.isEmpty {
                Text(localized("Where would you like to go, and how much time do you have?", "想去哪裡？這次有多少時間？"))
                    .font(SaveAtlasType.body(19))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.vertical, 16)
                if areas.isEmpty {
                    Text(localized("Save a few places first so I can arrange them.", "先存幾個地點，我就能幫你安排。"))
                        .font(SaveAtlasType.body(15))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }

            }
            ForEach(conversation.messages) { message in
                VStack(alignment: .leading, spacing: 14) {
                    Text(message.request)
                        .font(SaveAtlasType.body(16))
                        .padding(12)
                        .background(SaveAtlasPalette.mint.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(message.reply)
                        .font(SaveAtlasType.body(16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(SaveAtlasPalette.ink)
            }
            if let place = conversation.assignmentPlace {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assignmentTrips) { trip in
                        Button(localized("Add to \(trip.name)", "加入「\(trip.name)」")) {
                            Task {
                                await conversation.assignPlace(place, to: trip, store: tripStore, language: languageSettings.language)
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("plan.assignTrip.\(trip.id.uuidString)")
                    }
                    Button(localized("Start a new plan", "開始新草稿")) {
                        conversation.stage(place: place, addingToTrip: false, language: languageSettings.language)
                        isChatFocused = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("plan.assignTrip.new")
                    Button(localized("Cancel", "取消")) { conversation.assignmentPlace = nil }
                        .frame(minHeight: 44)
                }
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.forest)
                .disabled(conversation.assignmentInProgress || isPlanning)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.tripChoices")
            }
            if isPlanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(localized("Putting your plan together…", "正在安排你的行程…"))
                        .font(SaveAtlasType.body(14))
                    Spacer()
                    Button(localized("Cancel", "取消")) {
                        planningTask?.cancel()
                        isPlanning = false
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.conversation")
    }

    private var chatInput: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(localized("Tell me about your trip…", "說說你想怎麼玩…"), text: $conversation.input, axis: .vertical)
                .font(SaveAtlasType.body(16))
                .lineLimit(1...4)
                .focused($isChatFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)
                .accessibilityIdentifier("plan.chat.input")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(localized("Done", "完成")) { isChatFocused = false }
                            .accessibilityIdentifier("plan.keyboardDone")
                    }
                }
            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isPlanning || conversation.assignmentPlace != nil || conversation.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(localized("Send", "送出"))
            .accessibilityIdentifier("plan.chat.send")
        }
        .padding(12)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(SaveAtlasPalette.line.opacity(0.4)) }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func consumeSubmittedQuery() {
        guard let query = conversation.submittedQuery, !isPlanning,
              conversation.assignmentPlace == nil else { return }
        conversation.submittedQuery = nil
        conversation.input = query
        sendMessage()
    }

    private func sendMessage() {
        let query = conversation.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isPlanning, conversation.assignmentPlace == nil else { return }
        let sessionID = conversation.sessionID
        let language = languageSettings.language
        let places = savedPlaces
        let currentDraft = conversation.draft
        let request = conversation.agentRequest
        // Only conversational text goes back to the model, never serialized place notes/addresses.
        let history = conversation.messages.suffix(8).map {
            ConversationTurn(userMessage: $0.request, assistantResponse: $0.reply)
        }
        let anchorID = conversation.anchorPlaceID
        let candidates = mapCandidates
        isPlanning = true
        isChatFocused = false
        planError = nil
        planningTask = Task {
            defer { if !Task.isCancelled, conversation.sessionID == sessionID { isPlanning = false } }
            do {
                let result: SavePlanAgentResult
                var offline = false
                var fixture: SavePlanAgentResult?
#if DEBUG
                offline = ReviewDemo.isOfflineUITestMode
                if offline {
                    fixture = try SavePlanAgent.reviewFixture(query: query, history: history, request: request,
                        draft: currentDraft, savedPlaces: places, anchorID: anchorID, language: language)
                }
#endif
                if let fixture {
                    result = fixture
                } else {
                    result = try await SavePlanAgent(generate: { try await SaveAIService.shared.planDecision($0) }).respond(
                        query: query, history: history, request: request, draft: currentDraft,
                        savedPlaces: places, candidates: candidates, anchorID: anchorID, language: language)
                }
                try Task.checkCancellation()
                guard conversation.sessionID == sessionID else { return }
                guard conversation.draft == currentDraft else {
                    throw SavePlanAgentValidationError("The draft changed while planning; keep the newer draft.")
                }
                if let response = result.draft {
                    draft = response
                    conversation.agentRequest = result.request
                    if let request = result.request { conversation.conditions.acceptAgentRequest(request) }
                    if let anchorID, !response.placeIds.contains(anchorID.uuidString) { conversation.anchorPlaceID = nil }
                    showsDraftDetails = false
                }
                conversation.messages.append(.init(request: query, reply: result.message))
                conversation.turns.append(ConversationTurn(userMessage: query, assistantResponse: result.message))
                if conversation.turns.count > 12 { conversation.turns.removeFirst() }
                if conversation.input.trimmingCharacters(in: .whitespacesAndNewlines) == query { conversation.input = "" }
            } catch {
                guard !Task.isCancelled, conversation.sessionID == sessionID else { return }
                // A failed semantic edit must not be presented as a successful generic redraft.
                planError = localized(
                    "Savvy couldn’t finish this change. Your draft and message are kept; please try again.",
                    "Savvy 這次沒能完成調整，原本草稿和訊息都留著，請再試一次。"
                )
            }
        }
    }

    private func draftCanvas(_ draft: SaveAIResponse) -> some View {
        Group {
            if showsDraftDetails {
                VStack(alignment: .leading, spacing: 12) {
                    draftReviewButton
                    itineraryDetails(draft)
                }
            } else {
                draftSummary(draft)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.draft")
    }

    private func draftSummary(_ draft: SaveAIResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(localized("DRAFT · NOT SAVED", "草稿 · 尚未儲存"), systemImage: "map")
                    .font(SaveAtlasType.strong(11))
                Spacer()
                Text(localized(draft.itineraryDays.count == 1 ? "1 day" : "\(draft.itineraryDays.count) days", "\(draft.itineraryDays.count) 天"))
                    .font(SaveAtlasType.body(12))
            }
            .foregroundStyle(SaveAtlasPalette.muted)
            Text(draft.title ?? localized("Your trip", "你的行程"))
                .font(SaveAtlasType.strong(20, relativeTo: .title3))
                .foregroundStyle(SaveAtlasPalette.forest)
            ForEach(Array(draft.itineraryDays.prefix(3))) { day in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", day.dayNumber))
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .frame(width: 32, height: 32)
                        .background(SaveAtlasPalette.kraft.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.label ?? localized("Day \(day.dayNumber)", "第 \(day.dayNumber) 天"))
                            .font(SaveAtlasType.strong(14))
                        Text(day.stops.isEmpty
                             ? localized("Open details to fill this day", "打開詳情，補上這天的安排")
                             : day.stops.prefix(2).map(previewLabel).joined(separator: " → "))
                            .font(SaveAtlasType.body(13))
                            .foregroundStyle(SaveAtlasPalette.muted)
                            .lineLimit(2)
                        if day.health?.gaps.contains(where: { $0.type == .missingAfternoonActivity }) == true {
                            Text(localized("Activities still needed · review suggestions", "還缺景點活動 · 查看建議補齊"))
                                .font(SaveAtlasType.body(12))
                                .foregroundStyle(SaveAtlasPalette.forest)
                        }
                    }
                }
            }
            if draft.itineraryDays.count > 3 {
                Text(localized("+ \(draft.itineraryDays.count - 3) more days in details", "詳情還有 \(draft.itineraryDays.count - 3) 天"))
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            draftReviewButton
        }
        .padding(16)
        .foregroundStyle(SaveAtlasPalette.ink)
        .saveAtlasPaper(radius: 18)
    }

    private var draftReviewButton: some View {
        Button { showsDraftDetails.toggle() } label: {
            HStack {
                Text(showsDraftDetails ? localized("Hide details", "收起詳情") : localized("Review & save", "確認並儲存"))
                Spacer()
                Image(systemName: showsDraftDetails ? "chevron.up" : "chevron.down")
            }
            .font(SaveAtlasType.strong(15))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(SaveAtlasPalette.ink)
            .background(SaveAtlasPalette.kraft.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.draft.review")
    }

    private func previewLabel(_ stop: ItineraryStop) -> String {
        let isSaved = savedPlaces.contains { $0.id.uuidString.caseInsensitiveCompare(stop.placeId ?? "") == .orderedSame }
        let state = isSaved
            ? localized("saved", "已存")
            : localized("to review", "待確認")
        return "\(stop.placeName) · \(state)"
    }

    private func itineraryDetails(_ draft: SaveAIResponse) -> some View {
        TripItineraryComponent(
            title: draft.title ?? localized("Plan draft", "行程草稿"),
            days: draft.itineraryDays,
            tripHealth: draft.tripHealth,
            aiMessage: draft.aiMessage,
            places: savedPlaces,
            travelLegs: draft.travelLegs,
            onSaveTripPlan: { name, city, stops in
                await tripStore.createTrip(fromPlanNamed: name, city: city, stops: stops)
            },
            onOpenTrip: { tripID in
                conversation.startNewPlan()
                onOpenTrip(tripID)
            },
            onConfirmCandidate: onConfirmCandidate,
            onDaysChange: { conversation.updateDraftDays($0, replacing: draft) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.draft.details")
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}
