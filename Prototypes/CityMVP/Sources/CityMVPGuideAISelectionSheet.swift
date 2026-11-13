#if SAVVY_CITY_MVP
import SwiftUI

struct CityMVPGuideAISelectionSheet: View {
    let places: [Place]
    let onSelect: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    @EnvironmentObject private var recommendations: CityMVPRecommendationStore
    @EnvironmentObject private var auth: PrivyAuthService
    @StateObject private var controller: CityMVPGuideAIController
    @State private var question = ""
    @State private var placeIDs = Set<UUID>()
    @State private var sourceIDs = Set<String>()
    @State private var review: CityMVPGuideSelection.Request?
    @State private var showsReview = false
    @State private var notice: String?
    @State private var work: Task<Void, Never>?
    @FocusState private var questionFocused: Bool

    init(places: [Place], onSelect: @escaping (Place) -> Void, client: (any CityMVPGuideChoosing)? = nil) {
        self.places = places; self.onSelect = onSelect
        let auth = PrivyAuthService.shared
        _controller = StateObject(wrappedValue: CityMVPGuideAIController(client: client ?? CityMVPGuideGeminiClient.configured(),
            ownerIdentity: { "\(auth.sessionGeneration):\(auth.currentUserId ?? "signed-out")" }))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(t("Choose what Guide may use", "選擇 Guide 可以使用的資料")).font(.headline)
                    Text(t("AI can suggest up to two of your selected saves. It cannot verify a sender, current hours, menus or visits. No place is saved or changed by a suggestion.", "AI 可從你選取的收藏中建議最多兩個地點；不會驗證寄件者、即時營業時間、菜單或造訪。建議不會新增或修改收藏。"))
                    if controller.client == nil {
                        Text(t("AI is not connected in this local build. You can review the request; local Guide search still works.", "此本地版本尚未連接 AI。你仍可檢視請求內容，並使用 Guide 的本地搜尋。"))
                            .accessibilityIdentifier("cityMVP.guideAI.notConnected")
                    }
                    TextField(t("What would you like to do?", "你想做什麼？"), text: $question, axis: .vertical)
                        .focused($questionFocused).lineLimit(2...5).accessibilityIdentifier("cityMVP.guideAI.question")
                }
                Section(t("Selected places", "選取地點") + " · \(placeIDs.count)/5") {
                    if places.isEmpty { Text(t("Save a confirmed place first.", "先確認並收藏一個地點。")) }
                    ForEach(places) { place in
                        selection(placeIDs.contains(place.id), title: place.name, id: "cityMVP.guideAI.place." + place.id.uuidString) {
                            if placeIDs.contains(place.id) {
                                placeIDs.remove(place.id)
                                sourceIDs.subtract(recommendations.recommendations(for: place).map(\.id))
                            } else { placeIDs.insert(place.id) }
                        }
                        if placeIDs.contains(place.id) {
                            ForEach(recommendations.recommendations(for: place)) { source in
                                selection(sourceIDs.contains(source.id), title: source.senderLabel + "\n" + source.reason,
                                          id: "cityMVP.guideAI.source." + source.id) {
                                    if sourceIDs.contains(source.id) { sourceIDs.remove(source.id) } else { sourceIDs.insert(source.id) }
                                }
                                Text(t("Optional copied text · sender identity not verified", "可選的複製文字 · 寄件者身分未驗證")).font(.caption)
                            }
                        }
                    }
                }
                Section {
                    Text(t("Only your question, selected place names/categories and selected copied sender/reason text are attached. Saved private notes, addresses, coordinates, photos, ratings and visit history are not automatically attached.", "只會附上你的問題、所選地點的名稱／類別，以及你另外勾選的寄件者稱呼／推薦文字。不會自動附上私人筆記、地址、座標、照片、評分或造訪紀錄。"))
                        .font(.footnote)
                    Button(t("Review request", "檢視請求內容")) {
                        do { review = try makeRequest(); notice = nil; showsReview = true }
                        catch { notice = t("Choose 1–5 current places, at most 10 sources and a question up to 1,000 characters. If source details changed, select them again.", "請選擇 1–5 個目前的收藏、最多 10 筆來源，問題限 1,000 字。若來源已變更，請重新選取。") }
                    }.disabled(placeIDs.isEmpty || placeIDs.count > 5 || sourceIDs.count > 10 || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 1_000 || controller.isWorking)
                        .accessibilityIdentifier("cityMVP.guideAI.review")
                    if controller.isWorking {
                        ProgressView(t("Asking Guide…", "正在詢問 Guide…"))
                        Button(t("Cancel request", "取消請求")) { invalidate() }
                            .accessibilityIdentifier("cityMVP.guideAI.cancel")
                    }
                    if let notice { Text(notice).accessibilityIdentifier("cityMVP.guideAI.notice") }
                    if let failure = controller.failure {
                        Text(failure == .inputTooLarge
                             ? t("Choose fewer sources or shorten the question. Nothing was sent.", "請減少來源或縮短問題。尚未送出資料。")
                             : t("Guide AI is unavailable or returned unsupported references. Your selection is kept; nothing was saved. Local search remains available.", "Guide AI 暫時無法使用，或回傳了不支援的引用。選取內容已保留，沒有新增收藏；你仍可使用本地搜尋。"))
                            .accessibilityIdentifier("cityMVP.guideAI.failure")
                    }
                }
                if let response = controller.response, let request = controller.request {
                    Section(t("AI suggestions · check original sources", "AI 建議 · 請核對原始來源")) {
                        if response.choices.isEmpty { Text(t("No choice was supported by the selected data.", "所選資料沒有支持任何建議。")) }
                        ForEach(response.choices, id: \.placeID) { choice in
                            if let venue = request.venues.first(where: { $0.placeID == choice.placeID }),
                               let place = places.first(where: { $0.id == choice.placeID }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(venue.name).font(.headline)
                                    ForEach(venue.sources.filter { choice.sourceIDs.contains($0.sourceID) }, id: \.sourceID) { source in
                                        Text(source.selfDeclaredSender).bold()
                                        Text(t("Copied sender label · identity not verified", "複製的寄件者稱呼 · 身分未驗證")).font(.caption)
                                        Text(source.reason).textSelection(.enabled)
                                    }
                                    Button(t("Open saved place", "開啟收藏地點")) { onSelect(place); dismiss() }
                                        .accessibilityIdentifier("cityMVP.guideAI.open." + choice.placeID.uuidString)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SAV-E Guide AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t("Close", "關閉")) { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("Done", "完成")) { questionFocused = false }.accessibilityIdentifier("cityMVP.guideAI.keyboardDone")
                }
            }
            .sheet(isPresented: $showsReview, onDismiss: { review = nil }) {
                if let review { requestReview(review) }
            }
        }
        .onChange(of: question) { _, _ in invalidate() }
        .onChange(of: placeIDs) { _, _ in invalidate() }
        .onChange(of: sourceIDs) { _, _ in invalidate() }
        .onChange(of: places) { _, _ in reconcile() }
        .onChange(of: recommendations.records) { _, _ in reconcile() }
        .onChange(of: auth.sessionGeneration) { _, _ in
            question = ""; placeIDs = []; sourceIDs = []; invalidate(); dismiss()
        }
        .onDisappear { invalidate() }
    }

    private func requestReview(_ request: CityMVPGuideSelection.Request) -> some View {
        NavigationStack {
            Form {
                Section(t("Question to send", "將送出的問題")) { Text(request.question).accessibilityIdentifier("cityMVP.guideAI.reviewQuestion") }
                ForEach(request.venues, id: \.placeID) { venue in
                    Section(venue.name) {
                        Text(venue.category)
                        if venue.sources.isEmpty { Text(t("No copied source text selected", "未選取複製來源文字")) }
                        ForEach(venue.sources, id: \.sourceID) { source in
                            Text(source.selfDeclaredSender).bold().accessibilityIdentifier("cityMVP.guideAI.reviewSource." + source.sourceID)
                            Text(source.reason)
                            Text(t("Self-declared sender · identity not verified", "寄件者自行填寫的稱呼 · 身分未驗證")).font(.caption)
                        }
                    }
                }
                Section {
                    if let raw = Bundle.main.object(forInfoDictionaryKey: "CITY_MVP_GUIDE_API_URL") as? String,
                       let endpoint = CityMVPGuideGeminiClient.endpoint(raw) {
                        Text(t("Guide backend: ", "Guide 後端：") + endpoint)
                    }
                    Text(t("Sending uses the configured Guide backend and Gemini, and may consume AI allowance. Canceling cannot recall data already sent.", "送出後會使用設定的 Guide 後端與 Gemini，並可能消耗 AI 額度。取消無法收回已送出的資料。"))
                    Button(t("Send selected data to AI", "將所選資料送給 AI")) { send(request) }
                        .disabled(controller.client == nil)
                        .accessibilityIdentifier("cityMVP.guideAI.send")
                    if controller.client == nil { Text(t("A test connection must be configured before sending.", "送出前需先設定測試連線。")) }
                }
            }.navigationTitle(t("Review AI request", "檢視 AI 請求"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { showsReview = false }.accessibilityIdentifier("cityMVP.guideAI.reviewCancel")
                } }
        }.presentationDetents([.large])
    }

    private func selection(_ checked: Bool, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: checked ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(checked ? "Selected" : "Not selected")
            .accessibilityAddTraits(checked ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private func makeRequest() throws -> CityMVPGuideSelection.Request {
        try CityMVPGuideSelection.build(question: question, selectedPlaceIDs: Array(placeIDs),
            selectedSourceIDs: Array(sourceIDs), places: places, records: recommendations.records)
    }
    private func send(_ request: CityMVPGuideSelection.Request) {
        showsReview = false
        work?.cancel()
        work = Task { await controller.run(request, currentRequest: { try makeRequest() }) }
    }
    private func invalidate() {
        work?.cancel(); work = nil; controller.cancel(); notice = nil
        showsReview = false; review = nil
    }
    private func reconcile() {
        placeIDs.formIntersection(places.map(\.id))
        let availableSources = places.filter { placeIDs.contains($0.id) }.flatMap { recommendations.recommendations(for: $0).map(\.id) }
        sourceIDs.formIntersection(availableSources)
        invalidate()
    }
    private func t(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif
