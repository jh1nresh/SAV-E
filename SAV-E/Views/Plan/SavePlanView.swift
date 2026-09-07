import SwiftUI
import UIKit

@MainActor
final class SavePlanConversation: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let request: String
        let reply: String
    }
    @Published var input = ""
    @Published var submittedQuery: String?
    @Published var messages: [Message] = []
    @Published var draft: SaveAIResponse?
    var turns: [ConversationTurn] = []
    var conditions = SavePlanConversationConditions()
    @Published var assignmentPlace: Place?
    @Published var assignmentInProgress = false
    var anchorPlaceID: UUID?

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
            assignmentPlace = nil
            anchorPlaceID = place.id
            conditions = SavePlanConversationConditions()
            turns = []
            let area = SavedPlaceTripRecommender.areaLabel(for: place)
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
    let onOpenTrips: () -> Void
    let onConfirmCandidate: (SaveMapCandidate) async throws -> Place

    @Environment(\.appLanguageSettings) private var languageSettings
    @FocusState private var isChatFocused: Bool
    @State private var keyboardOverlap: CGFloat = 0
    @State private var reviewDraft: PlanReviewDraft?
    @State private var pendingTripID: UUID?

    private struct PlanReviewDraft: Identifiable {
        let id = UUID()
        let response: SaveAIResponse
    }
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

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    conversationContent
                        .id("conversationEnd")
                    if let draft {
                        draftCanvas(draft)
                            .disabled(isPlanning)
                            .id("latestDraft")
                    }
                    Button(action: onOpenTrips) {
                        Label(localized("Saved trips", "已存行程"), systemImage: "list.bullet")
                            .font(SaveAtlasType.body(14))
                            .frame(minHeight: 44)
                    }
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .accessibilityIdentifier("plan.allTrips")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { chatInput }
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
            .placed(x: 0, y: 105, width: AtlasMetrics.width, height: max(160, min(674, AtlasMetrics.height - keyboardOverlap - 117)))
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
        .sheet(item: $reviewDraft, onDismiss: {
            if let tripID = pendingTripID {
                pendingTripID = nil
                onOpenTrip(tripID)
            }
        }) { review in
            NavigationStack {
                ScrollView {
                    itineraryDetails(review.response)
                        .padding(16)
                }
                .background(SaveAtlasPalette.canvas)
                .navigationTitle(localized("Review your plan", "確認行程"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(localized("Done", "完成")) { reviewDraft = nil }
                            .accessibilityIdentifier("plan.review.close")
                    }
                }
            }
            .presentationDetents([.large])
        }
        .environment(\.atlasPresentation, atlasPresentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.root")
        .onAppear(perform: consumeSubmittedQuery)
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("Plan with Savvy", "和 Savvy 一起規劃"))
                .font(SaveAtlasType.strong(25, relativeTo: .title2))
                .foregroundStyle(SaveAtlasPalette.forest)
            Text(localized("A trip from the places you’ve saved.", "從你已存的地點，聊出一趟行程。"))
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
        conversation.conditions.receive(query, areas: areas)
        if let question = conversation.conditions.clarification(language: languageSettings.language) {
            conversation.messages.append(.init(request: query, reply: question))
            conversation.turns.append(ConversationTurn(userMessage: query, assistantResponse: question))
            if conversation.turns.count > 12 { conversation.turns.removeFirst() }
            conversation.input = ""
            isChatFocused = true
            return
        }
        guard var request = conversation.conditions.request(language: languageSettings.language) else { return }
        if let anchorID = conversation.anchorPlaceID,
           let anchor = savedPlaces.first(where: { $0.id == anchorID }),
           !SavePlanDraftBuilder.matches(area: request.area, place: anchor) {
            conversation.anchorPlaceID = nil
        }
        request.anchorPlaceID = conversation.anchorPlaceID
        isChatFocused = false
        isPlanning = true
        planError = nil
        let places = savedPlaces.filter { SavePlanDraftBuilder.matches(area: request.area, place: $0) }
        let candidates = mapCandidates.filter { SavePlanDraftBuilder.matches(area: request.area, candidate: $0) }
        let planningMessage = conversation.conditions.planningMessage(language: languageSettings.language)
        let language = languageSettings.language
        let history = conversation.turns
        planningTask = Task {
            defer { if !Task.isCancelled { isPlanning = false } }
            do {
                guard var local = SavePlanDraftBuilder.draft(request: request, savedPlaces: places, unsavedCandidates: candidates) else {
                    conversation.messages.append(.init(request: query, reply: localized(
                        "I can’t fit your confirmed places into these conditions yet. Your previous draft is kept. Add places in this area or adjust the time or destination.",
                        "目前無法把這些已確認地點排進所說的條件，上一版草稿仍保留著。可以補存這個區域的地點，或調整時間、目的地。"
                    )))
                    conversation.input = ""
                    return
                }
                var isOffline = false
#if DEBUG
                isOffline = ReviewDemo.isOfflineUITestMode
                if isOffline, ProcessInfo.processInfo.arguments.contains("--uitest-plan-candidate"),
                   let firstDay = local.itineraryDays.first {
                    let candidate = SaveMapCandidate(title: "Plan Test Garden", subtitle: "Taipei", latitude: 25.04, longitude: 121.54,
                        category: .attraction, sourceURL: "https://example.com/plan-garden")
                    let stop = ItineraryStop(id: UUID(), placeId: nil, placeState: .externalSuggestion,
                        placeName: candidate.title, time: nil, duration: 60, note: nil,
                        sourceSummary: "Public map candidate", risks: [.externalSuggestion], mapCandidate: candidate)
                    local = local.replacingItineraryDays(
                        [firstDay.replacingStops([stop] + firstDay.stops)] + local.itineraryDays.dropFirst(), tripHealth: nil
                    )
                }
#endif
                var response = local
                if !isOffline {
                    let gaps = local.itineraryDays.flatMap { $0.health?.gaps ?? [] }
                    if !gaps.isEmpty {
                        let extras = await TripGapLocalOptionsService().candidates(forGaps: gaps, days: local.itineraryDays, savedPlaces: places)
                        guard !Task.isCancelled else { return }
                        if !extras.isEmpty, let enriched = SavePlanDraftBuilder.draft(
                            request: request, savedPlaces: places, unsavedCandidates: extras + candidates
                        ) { local = enriched }
                    }
                    let polished = try await SaveAIService.shared.query(
                        planningMessage, places: places, conversationHistory: history,
                        outputLanguage: language, deterministicDraftOverride: local,
                        maxStopsPerDay: request.pace.maxStopsPerDay
                    )
                    guard !Task.isCancelled else { return }
                    response = SavePlanDraftBuilder.preservingSchedule(polished, draft: local)
                    response = await SavePlanDraftBuilder.checkingTravel(response, savedPlaces: places, language: language)
                }
                guard !Task.isCancelled else { return }
                conversation.turns.append(ConversationTurn(userMessage: query, assistantResponse: SaveAIService.shared.encodeResponse(response)))
                if conversation.turns.count > 12 { conversation.turns.removeFirst() }
                let reply = response.componentType == .tripItinerary
                    ? localized("Here’s a draft. Tell me what you’d like to change, or review it before saving.", "先排好這版草稿。可以繼續聊想調整的地方，或確認內容後儲存。")
                    : response.aiMessage ?? response.messageText ?? response.title ?? localized("Tell me more about your trip.", "再多說一點你想怎麼玩。")
                conversation.messages.append(.init(request: query, reply: reply))
                if response.componentType == .tripItinerary { draft = response }
                if conversation.input.trimmingCharacters(in: .whitespacesAndNewlines) == query { conversation.input = "" }
            } catch {
                guard !Task.isCancelled else { return }
                planError = localized(
                    "Couldn’t finish this draft. Your message is kept; please try again.",
                    "這次沒能完成草稿，訊息已保留，請再試一次。"
                )
            }
        }
    }

    private func draftCanvas(_ draft: SaveAIResponse) -> some View {
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
            Button { reviewDraft = PlanReviewDraft(response: draft) } label: {
                HStack {
                    Text(localized("Review & save", "確認並儲存"))
                    Spacer()
                    Image(systemName: "arrow.right")
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
        .padding(16)
        .foregroundStyle(SaveAtlasPalette.ink)
        .saveAtlasPaper(radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.draft")
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
                pendingTripID = tripID
                reviewDraft = nil
            },
            onConfirmCandidate: onConfirmCandidate
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
