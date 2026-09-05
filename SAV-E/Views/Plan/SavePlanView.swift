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
    @Published var messages: [Message] = []
    @Published var draft: SaveAIResponse?
    var turns: [ConversationTurn] = []
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
    @State private var selectedArea: String = ""
    @State private var days: Int = 2
    @State private var pace: ItineraryPace = .balanced
    @State private var usesArrival = false
    @State private var usesDeparture = false
    @State private var arrivalDate = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var departureDate = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
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
                    HStack(alignment: .top) {
                        heading
                        Spacer()
                        Button(action: onOpenTrips) {
                            Image(systemName: "calendar").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(localized("Saved trips", "已存行程"))
                        .accessibilityIdentifier("plan.allTrips")
                    }
                    conversationContent
                    if let draft {
                        draftCanvas(draft)
                            .disabled(isPlanning)
                            .id("latestDraft")
                    }
                    DisclosureGroup(localized("Plan options", "調整行程條件")) {
                        composer
                    }
                    .font(SaveAtlasType.body(14))
                    .tint(SaveAtlasPalette.forest)
                    .accessibilityIdentifier("plan.options")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { chatInput }
            .scrollDismissesKeyboard(.interactively)
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
        .onAppear(perform: selectDefaultArea)
        .onDisappear {
            planningTask?.cancel()
            isPlanning = false
        }
        .onChange(of: areas) { _, _ in selectDefaultArea() }
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
                ForEach(Array(areas.prefix(2)), id: \.self) { area in
                    Button {
                        conversation.input = localized("Plan a relaxed day in \(area)", "用已存地點安排\(area)輕鬆的一天")
                        sendMessage()
                    } label: {
                        Label(localized("A relaxed day in \(area)", "在\(area)輕鬆逛一天"), systemImage: "arrow.up.left")
                            .font(SaveAtlasType.body(15))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .disabled(isPlanning)
                    .foregroundStyle(SaveAtlasPalette.forest)
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
            .disabled(isPlanning || conversation.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(localized("Send", "送出"))
            .accessibilityIdentifier("plan.chat.send")
        }
        .padding(12)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(SaveAtlasPalette.line.opacity(0.4)) }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func sendMessage() {
        let query = conversation.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isPlanning else { return }
        isChatFocused = false
        isPlanning = true
        planError = nil
        let places = savedPlaces
        let language = languageSettings.language
        let history = conversation.turns
        planningTask = Task {
            defer { if !Task.isCancelled { isPlanning = false } }
            do {
                let response: SaveAIResponse
#if DEBUG
                if ReviewDemo.isOfflineUITestMode,
                   let local = DeterministicTripPlanner().plan(for: query, places: places, outputLanguage: language) {
                    response = local
                } else {
                    response = try await SaveAIService.shared.query(query, places: places, conversationHistory: history, outputLanguage: language)
                }
#else
                response = try await SaveAIService.shared.query(query, places: places, conversationHistory: history, outputLanguage: language)
#endif
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
                    "Couldn’t reach planning right now. Your message is kept; please try again. You can also choose a city in Plan options to draft from saved places.",
                    "暫時無法連上規劃服務，訊息已保留，請再試一次。也可以在「調整行程條件」選城市，用已存地點建立草稿。"
                )
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Composer", "行程條件"))
                .font(SaveAtlasType.strong(13))
                .tracking(0.65)
                .foregroundStyle(SaveAtlasPalette.forest)

            if areas.isEmpty {
                Text(localized(
                    "Save a few Map Stamps first, then Plan can arrange them.",
                    "先存幾個地圖章，Plan 才能幫你排。"
                ))
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
                .accessibilityIdentifier("plan.emptyStamps")
            } else {
                areaChips
                    .disabled(isPlanning)
                dayAndPace
                    .disabled(isPlanning)
                travelWindows
                    .disabled(isPlanning)
                if isPlanning {
                    HStack {
                        ProgressView()
                        Text(localized("Checking local options and travel…", "正在檢查附近選項與交通…"))
                            .font(SaveAtlasType.body(12))
                        Spacer()
                        Button(localized("Cancel", "取消")) {
                            planningTask?.cancel()
                            isPlanning = false
                        }
                        .frame(minHeight: 44)
                    }
                }
                Button(action: planFromStamps) {
                    Text(localized("Plan from Map Stamps", "用地圖章規劃"))
                        .font(SaveAtlasType.strong(16))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(SaveAtlasPalette.coral)
                .disabled(isPlanning || selectedArea.isEmpty)
                .accessibilityIdentifier("plan.compose")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaveAtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.composer")
    }

    private var areaChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("CITY", "城市"))
                .font(SaveAtlasType.strong(11))
                .tracking(0.8)
                .foregroundStyle(SaveAtlasPalette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(areas, id: \.self) { area in
                        Button {
                            selectedArea = area
                        } label: {
                            Text(area)
                                .font(SaveAtlasType.display(13))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .background(
                                    SaveAtlasPalette.kraft.opacity(selectedArea == area ? 0.72 : 0.28),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(SaveAtlasPalette.line.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan.area.\(area)")
                    }
                }
            }
        }
    }

    private var dayAndPace: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("Days", "天數"))
                    .font(SaveAtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Spacer()
                Stepper(value: $days, in: 1...7) {
                    Text("\(days)")
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .accessibilityIdentifier("plan.days")
            }

            HStack(spacing: 8) {
                paceChip(.relaxed, title: localized("Relaxed", "輕鬆"))
                paceChip(.balanced, title: localized("Balanced", "適中"))
                paceChip(.packed, title: localized("Packed", "緊湊"))
            }
        }
    }

    private func paceChip(_ value: ItineraryPace, title: String) -> some View {
        Button {
            pace = value
        } label: {
            Text(title)
                .font(SaveAtlasType.display(13))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(SaveAtlasPalette.ink)
                .background(
                    SaveAtlasPalette.kraft.opacity(pace == value ? 0.72 : 0.28),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.pace.\(value.rawValue)")
    }

    private var travelWindows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(localized("Arrival flight time", "抵達班機時間"), isOn: $usesArrival)
                .font(SaveAtlasType.body(14))
                .tint(SaveAtlasPalette.forest)
                .accessibilityIdentifier("plan.arrival.toggle")
            if usesArrival {
                DatePicker(
                    localized("Arrive", "抵達"),
                    selection: $arrivalDate,
                    displayedComponents: .hourAndMinute
                )
                .font(SaveAtlasType.body(14))
                .accessibilityIdentifier("plan.arrival.time")
            }
            Toggle(localized("Departure flight time", "離開班機時間"), isOn: $usesDeparture)
                .font(SaveAtlasType.body(14))
                .tint(SaveAtlasPalette.forest)
                .accessibilityIdentifier("plan.departure.toggle")
            if usesDeparture {
                DatePicker(
                    localized("Depart", "出發"),
                    selection: $departureDate,
                    displayedComponents: .hourAndMinute
                )
                .font(SaveAtlasType.body(14))
                .accessibilityIdentifier("plan.departure.time")
            }
            Text(localized(
                "These clocks only shrink the walking day. Savvy does not buy tickets or rooms.",
                "這些時間只用來縮短可走路程；Savvy 不會代買機票或訂房。"
            ))
            .font(SaveAtlasType.body(12))
            .foregroundStyle(SaveAtlasPalette.muted)
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

    private func selectDefaultArea() {
        if selectedArea.isEmpty || !areas.contains(selectedArea) {
            selectedArea = areas.first ?? ""
        }
    }

    private func planFromStamps() {
        isPlanning = true
        planError = nil
        let request = SavePlanRequest(
            area: selectedArea,
            days: days,
            pace: pace,
            arrivalMinutes: usesArrival ? minutes(from: arrivalDate) : nil,
            departureMinutes: usesDeparture ? minutes(from: departureDate) : nil,
            language: languageSettings.language
        )
        planningTask?.cancel()
        let places = savedPlaces
        let candidates = mapCandidates
        planningTask = Task {
            defer { if !Task.isCancelled { isPlanning = false } }
            let first = SavePlanDraftBuilder.draft(
                request: request,
                savedPlaces: places,
                unsavedCandidates: candidates
            )
            guard var response = first else {
                planError = localized(
                    "Need confirmed Map Stamps in this city before Savvy can draft a plan.",
                    "這個城市還沒有已確認地圖章，沒辦法排出行程。"
                )
                return
            }
#if DEBUG
            if ReviewDemo.isOfflineUITestMode {
                if ProcessInfo.processInfo.arguments.contains("--uitest-plan-candidate"), let firstDay = response.itineraryDays.first {
                    let candidate = SaveMapCandidate(title: "Plan Test Garden", subtitle: "Taipei", latitude: 25.04, longitude: 121.54,
                        category: .attraction, sourceURL: "https://example.com/plan-garden")
                    let stop = ItineraryStop(id: UUID(), placeId: nil, placeState: .externalSuggestion,
                        placeName: candidate.title, time: nil, duration: 60, note: nil,
                        sourceSummary: "Public map candidate", risks: [.externalSuggestion], mapCandidate: candidate)
                    response = response.replacingItineraryDays(
                        [firstDay.replacingStops([stop] + firstDay.stops)] + response.itineraryDays.dropFirst(),
                        tripHealth: nil
                    )
                }
                draft = response
                return
            }
#endif
            draft = response
            let gaps = response.itineraryDays.flatMap { $0.health?.gaps ?? [] }
            if !gaps.isEmpty {
                let extras = await TripGapLocalOptionsService().candidates(
                    forGaps: gaps,
                    days: response.itineraryDays,
                    savedPlaces: places
                )
                guard !Task.isCancelled else { return }
                if !extras.isEmpty,
                   let enriched = SavePlanDraftBuilder.draft(
                    request: request,
                    savedPlaces: places,
                    unsavedCandidates: extras + candidates
                   ) {
                    response = enriched
                }
            }
            response = await SavePlanDraftBuilder.checkingTravel(response, savedPlaces: places, language: request.language)
            guard !Task.isCancelled else { return }
            draft = response
        }
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}
