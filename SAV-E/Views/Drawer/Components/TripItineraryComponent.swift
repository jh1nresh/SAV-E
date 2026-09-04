import SwiftUI

struct TripItineraryComponent: View {
    let title: String
    private let sourceDays: [ItineraryDay]
    var tripHealth: TripHealth?
    let aiMessage: String?
    var places: [Place] = []
    var travelLegs: [TripTravelLeg] = []
    /// Persists the distilled plan as a Trip. Nil hides the save action
    /// (previews / surfaces without a trip store).
    var onSaveTripPlan: ((_ name: String, _ city: String, _ stops: [TripPlanPersistableStop]) async -> Trip?)?
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var shareItem: TripItineraryShareItem?
    @State private var exportAlert: TripItineraryExportAlert?
    @State private var exportTask: Task<Void, Never>?
    @State private var canvas: TripCanvasDraft
    @State private var localGapCandidates: [SaveMapCandidate] = []
    @State private var isLoadingLocalGapCandidates = false
    @State private var saveTripPrompt: TripPlanSavePrompt?
    @State private var isSavingTrip = false

    init(
        title: String,
        days: [ItineraryDay],
        tripHealth: TripHealth? = nil,
        aiMessage: String?,
        places: [Place] = [],
        travelLegs: [TripTravelLeg] = [],
        onSaveTripPlan: ((_ name: String, _ city: String, _ stops: [TripPlanPersistableStop]) async -> Trip?)? = nil
    ) {
        self.title = title
        self.sourceDays = days
        self.tripHealth = tripHealth
        self.aiMessage = aiMessage
        self.places = places
        self.travelLegs = travelLegs
        self.onSaveTripPlan = onSaveTripPlan
        _canvas = State(initialValue: TripCanvasDraft(days: days))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(english: "PLAN DRAFT", traditionalChinese: "行程草稿"))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SaveAtlasPalette.kraft.opacity(0.45))
                        .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                        .clipShape(Capsule())

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.saveInk)
                        .lineLimit(2)
                    if let msg = aiMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.saveInk.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(languageSettings.localized(
                        english: "Based on your request and confirmed Map Stamps.",
                        traditionalChinese: "根據你的要求與已確認地圖章安排。"
                    ))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                }
                Spacer()

                Menu {
                    Button(action: shareSaveLink) {
                        Label(
                            languageSettings.localized(
                                english: "Share Savvy Link",
                                traditionalChinese: "分享 Savvy 連結"
                            ),
                            systemImage: "link"
                        )
                    }
                    .disabled(buildShareURL() == nil)

                    Divider()

                    Button {
                        guard exportTask == nil else { return }
                        exportTask = Task { await exportKml() }
                    } label: {
                        Label(
                            languageSettings.localized(
                                english: isExportingKml ? "Preparing KML…" : "Export KML",
                                traditionalChinese: isExportingKml ? "正在準備 KML…" : "匯出 KML"
                            ),
                            systemImage: "doc.badge.arrow.up"
                        )
                    }
                    .disabled(isExportingKml || kmlExportDisabledReason != nil)

                    if let kmlExportDisabledReason {
                        Button(action: {}) {
                            Label(kmlExportDisabledReason, systemImage: "info.circle")
                        }
                        .disabled(true)
                    }

                    if onSaveTripPlan != nil {
                        Divider()

                        Button(action: presentSaveTripPrompt) {
                            Label(
                                languageSettings.localized(
                                    english: isSavingTrip ? "Saving Trip…" : "Save as Trip",
                                    traditionalChinese: isSavingTrip ? "正在儲存旅程…" : "存成旅程"
                                ),
                                systemImage: "suitcase"
                            )
                        }
                        .disabled(isSavingTrip || tripSaveDisabledReason != nil)

                        if let tripSaveDisabledReason {
                            Button(action: {}) {
                                Label(tripSaveDisabledReason, systemImage: "info.circle")
                            }
                            .disabled(true)
                        }
                    }
                } label: {
                    Group {
                        if isExportingKml {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.saveInk)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.saveInk)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(SaveAtlasPalette.paper.opacity(0.74))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SaveAtlasPalette.line, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(
                    english: "Share or export trip",
                    traditionalChinese: "分享或匯出行程"
                ))

                Label(dayCountText, systemImage: "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(SaveAtlasPalette.kraft.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SaveAtlasPalette.line, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let tripHealth {
                TripHealthSummaryCard(
                    health: tripHealth,
                    dayCount: canvas.visibleDays.count,
                    suggestionsByGapID: suggestionsByGapID
                ) { gap, option in
                    canvas.insertGapSuggestion(
                        option,
                        dayNumber: dayNumber(for: gap),
                        note: gap.message
                    )
                }
            }

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(canvas.visibleDays) { day in
                    DaySection(
                        day: day,
                        approvedExternalStopIDs: canvas.approvedExternalStopIDs,
                        travelLegs: travelLegs,
                        onApproveExternalStop: { stopID in canvas.approveExternalStop(stopID) },
                        onSkipStop: { stopID in canvas.skipStop(stopID) },
                        onMoveEarlier: { stopID in canvas.moveStopEarlier(stopID) },
                        onMoveLater: { stopID in canvas.moveStopLater(stopID) }
                    )
                }
            }
        }
        .padding(14)
        .background(SaveAtlasPalette.paper.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: canvasInputID) { _, _ in
            canvas = TripCanvasDraft(days: sourceDays)
        }
        .task(id: canvasInputID) {
            await loadLocalGapCandidates()
        }
        .onAppear(perform: cleanupTemporaryExport)
        .sheet(item: $shareItem, onDismiss: cleanupTemporaryExport) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $saveTripPrompt) { prompt in
            TripPlanSaveSheet(
                defaultName: title,
                selection: prompt.selection,
                onSave: { name, city in
                    saveTripPrompt = nil
                    savePlanAsTrip(name: name, city: city, selection: prompt.selection)
                },
                onCancel: { saveTripPrompt = nil }
            )
        }
        .alert(item: $exportAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(languageSettings.localized(english: "OK", traditionalChinese: "好")))
            )
        }
        .onDisappear(perform: handleDisappear)
    }

    private func buildShareURL() -> URL? {
        let tripData = SharedTripData.from(title: title, city: "", days: canvas.visibleDays, places: places)
        return tripData.toURL()
    }

    private func shareSaveLink() {
        guard let url = buildShareURL() else { return }
        do {
            try removeTemporaryExportIfPresent()
        } catch {
            exportAlert = exportAlert(for: error)
            return
        }
        shareItem = TripItineraryShareItem(url: url)
    }

    private func exportKml() async {
        defer { exportTask = nil }

        do {
            try removeTemporaryExportIfPresent()
            let placeIDs = try canvas.kmlExportPlaceIDs(availablePlaces: places)
            let data = try await SupabaseService.shared.exportTrekKml(placeIds: placeIDs)
            try Task.checkCancellation()

            try data.write(to: kmlExportFileURL, options: [.atomic, .completeFileProtection])
            shareItem = TripItineraryShareItem(url: kmlExportFileURL)
        } catch is CancellationError {
            return
        } catch {
            cleanupTemporaryExport()
            exportAlert = exportAlert(for: error)
        }
    }

    private func handleDisappear() {
        exportTask?.cancel()
        exportTask = nil
        if shareItem == nil {
            cleanupTemporaryExport()
        }
    }

    private func cleanupTemporaryExport() {
        do {
            try removeTemporaryExportIfPresent()
        } catch {
            exportAlert = exportAlert(for: error)
        }
    }

    private var isExportingKml: Bool {
        exportTask != nil
    }

    private var kmlExportFileURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("save-trip-pack.kml", isDirectory: false)
    }

    private func removeTemporaryExportIfPresent() throws {
        guard FileManager.default.fileExists(atPath: kmlExportFileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: kmlExportFileURL)
        } catch {
            throw TripItineraryExportError.temporaryFileCleanupFailed
        }
    }

    private var kmlExportDisabledReason: String? {
        do {
            _ = try canvas.kmlExportPlaceIDs(availablePlaces: places)
            return nil
        } catch let error as TripKmlExportSelectionError {
            return selectionMessage(for: error)
        } catch {
            return languageSettings.localized(
                english: "This trip cannot be exported yet.",
                traditionalChinese: "這份行程目前還不能匯出。"
            )
        }
    }

    private var tripSaveDisabledReason: String? {
        do {
            _ = try canvas.tripSaveSelection(availablePlaces: places)
            return nil
        } catch let error as TripKmlExportSelectionError {
            return selectionMessage(for: error)
        } catch {
            return languageSettings.localized(
                english: "This plan cannot be saved yet.",
                traditionalChinese: "這份行程目前還不能儲存。"
            )
        }
    }

    private func presentSaveTripPrompt() {
        do {
            let selection = try canvas.tripSaveSelection(availablePlaces: places)
            saveTripPrompt = TripPlanSavePrompt(selection: selection)
        } catch {
            exportAlert = TripItineraryExportAlert(
                title: languageSettings.localized(
                    english: "Couldn’t Save Trip",
                    traditionalChinese: "無法儲存旅程"
                ),
                message: (error as? TripKmlExportSelectionError).map(selectionMessage(for:))
                    ?? error.localizedDescription
            )
        }
    }

    private func savePlanAsTrip(name: String, city: String, selection: TripPlanSaveSelection) {
        guard let onSaveTripPlan, !isSavingTrip else { return }
        isSavingTrip = true
        Task {
            let trip = await onSaveTripPlan(name, city, selection.stops)
            isSavingTrip = false
            if let trip {
                exportAlert = TripItineraryExportAlert(
                    title: languageSettings.localized(
                        english: "Saved to Trip Packs",
                        traditionalChinese: "已存入旅程包"
                    ),
                    message: languageSettings.localized(
                        english: "“\(trip.name)” now holds \(trip.places.count) stops from this plan.",
                        traditionalChinese: "「\(trip.name)」已收錄這份行程的 \(trip.places.count) 個地點。"
                    )
                )
            } else {
                exportAlert = TripItineraryExportAlert(
                    title: languageSettings.localized(
                        english: "Couldn’t Save Trip",
                        traditionalChinese: "無法儲存旅程"
                    ),
                    message: languageSettings.localized(
                        english: "Savvy could not save this plan as a trip. Try again.",
                        traditionalChinese: "Savvy 無法把這份行程存成旅程，請再試一次。"
                    )
                )
            }
        }
    }

    private func exportAlert(for error: Error) -> TripItineraryExportAlert {
        let message: String
        if case TripItineraryExportError.temporaryFileCleanupFailed = error {
            message = languageSettings.localized(
                english: "Savvy could not remove its temporary KML file. Close the share sheet and try again.",
                traditionalChinese: "Savvy 無法移除暫存 KML 檔案。請關閉分享畫面後再試一次。"
            )
        } else if let selectionError = error as? TripKmlExportSelectionError {
            message = selectionMessage(for: selectionError)
        } else if let serviceError = error as? SupabaseError {
            switch serviceError {
            case .notConfigured:
                message = languageSettings.localized(
                    english: "Connect Savvy to its backend before exporting KML.",
                    traditionalChinese: "請先連接 Savvy 後端，再匯出 KML。"
                )
            case .notAuthenticated:
                message = languageSettings.localized(
                    english: "Sign in to export your confirmed Map Stamps.",
                    traditionalChinese: "請先登入，再匯出已確認的地圖章。"
                )
            case .networkError:
                message = languageSettings.localized(
                    english: "Check your connection and try exporting again.",
                    traditionalChinese: "請確認網路連線後再試一次。"
                )
            case .recordNotFound, .apiError, .invalidResponse:
                message = languageSettings.localized(
                    english: "Savvy could not prepare a valid KML file. Try again later.",
                    traditionalChinese: "Savvy 無法準備有效的 KML 檔案，請稍後再試。"
                )
            }
        } else {
            message = languageSettings.localized(
                english: "Savvy could not create the KML file. Try again.",
                traditionalChinese: "Savvy 無法建立 KML 檔案，請再試一次。"
            )
        }
        return TripItineraryExportAlert(
            title: languageSettings.localized(
                english: "Couldn’t Export KML",
                traditionalChinese: "無法匯出 KML"
            ),
            message: message
        )
    }

    private func selectionMessage(for error: TripKmlExportSelectionError) -> String {
        switch error {
        case .noConfirmedMapStamps:
            return languageSettings.localized(
                english: "No confirmed Map Stamps are visible in this plan.",
                traditionalChinese: "這份行程目前沒有可見的已確認地圖章。"
            )
        case .tooManyConfirmedMapStamps(let count):
            return languageSettings.localized(
                english: "KML export supports up to 100 Map Stamps; this plan has \(count).",
                traditionalChinese: "KML 最多可匯出 100 個地圖章；這份行程有 \(count) 個。"
            )
        }
    }

    private var canvasInputID: String {
        sourceDays
            .map { day in
                "\(day.dayNumber):" + day.stops.map(\.id.uuidString).joined(separator: ",")
            }
            .joined(separator: "|")
    }

    private var dayCountText: String {
        switch languageSettings.language {
        case .english:
            return canvas.visibleDays.count == 1 ? "1 day" : "\(canvas.visibleDays.count) days"
        case .traditionalChinese:
            return "\(canvas.visibleDays.count) 天"
        }
    }

    private var suggestionsByGapID: [String: GapSuggestion] {
        guard let gaps = tripHealth?.gaps, !gaps.isEmpty else { return [:] }
        let suggestions = TripGapSuggestionEngine().suggestions(
            for: gaps,
            days: canvas.visibleDays,
            savedPlaces: places,
            reviewCandidates: [],
            // Public options near the plan's own stops. They render as
            // `.externalSuggestion`: approve-gated and never auto-saved.
            mapCandidates: localGapCandidates,
            outputLanguage: languageSettings.language
        )
        return Dictionary(uniqueKeysWithValues: suggestions.map { ($0.gapId, $0) })
    }

    /// Loads public options for the open gaps once per plan. Fire-and-forget:
    /// a plan built from saved places must still render if this never returns.
    private func loadLocalGapCandidates() async {
        guard let gaps = tripHealth?.gaps, !gaps.isEmpty else {
            localGapCandidates = []
            return
        }
        guard !isLoadingLocalGapCandidates else { return }
        isLoadingLocalGapCandidates = true
        defer { isLoadingLocalGapCandidates = false }

        localGapCandidates = await TripGapLocalOptionsService().candidates(
            forGaps: gaps,
            days: canvas.visibleDays,
            savedPlaces: places
        )
    }

    private func dayNumber(for gap: TripGap) -> Int {
        gap.dayNumber ?? canvas.visibleDays.first?.dayNumber ?? 1
    }

}

private struct TripItineraryShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct TripItineraryExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum TripItineraryExportError: Error {
    case temporaryFileCleanupFailed
}

private struct TripPlanSavePrompt: Identifiable {
    let id = UUID()
    let selection: TripPlanSaveSelection
}

/// Confirmation sheet for "Save as Trip": name/city entry plus an explicit
/// count of stops that cannot be persisted (anything that is not a confirmed
/// Map Stamp), so exclusion is never silent.
private struct TripPlanSaveSheet: View {
    let defaultName: String
    let selection: TripPlanSaveSelection
    let onSave: (_ name: String, _ city: String) -> Void
    let onCancel: () -> Void

    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var name: String = ""
    @State private var city: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        languageSettings.localized(english: "Trip name", traditionalChinese: "旅程名稱"),
                        text: $name
                    )
                    .accessibilityIdentifier("tripPlanSave.name")
                    TextField(
                        languageSettings.localized(english: "City (optional)", traditionalChinese: "城市（選填）"),
                        text: $city
                    )
                    .accessibilityIdentifier("tripPlanSave.city")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageSettings.localized(
                            english: "\(selection.stops.count) confirmed Map Stamps will be saved.",
                            traditionalChinese: "將儲存 \(selection.stops.count) 個已確認地圖章。"
                        ))
                        if selection.excludedStopCount > 0 {
                            Text(languageSettings.localized(
                                english: "\(selection.excludedStopCount) stops are not confirmed Map Stamps yet and will be left out.",
                                traditionalChinese: "另有 \(selection.excludedStopCount) 個停靠點尚未確認為地圖章，不會存入。"
                            ))
                        }
                    }
                }
            }
            .navigationTitle(languageSettings.localized(english: "Save as Trip", traditionalChinese: "存成旅程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        languageSettings.localized(english: "Cancel", traditionalChinese: "取消"),
                        action: onCancel
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageSettings.localized(english: "Save", traditionalChinese: "儲存")) {
                        onSave(name, city)
                    }
                    .accessibilityIdentifier("tripPlanSave.confirm")
                }
            }
            .onAppear {
                if name.isEmpty { name = defaultName }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Trip Health

private struct TripHealthSummaryCard: View {
    let health: TripHealth
    var dayCount: Int = 1
    var suggestionsByGapID: [String: GapSuggestion] = [:]
    var onAddSuggestion: ((TripGap, GapSuggestionOption) -> Void)?
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    languageSettings.localized(english: "Trip Health", traditionalChinese: "行程健康度"),
                    systemImage: "checklist.checked"
                )
                .font(.caption.weight(.bold))
                .foregroundColor(.saveInk)

                Spacer()

                Text("\(health.score)/100")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(scoreColor.opacity(0.74))
                    .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                    .clipShape(Capsule())
            }

            if let strength = health.strengths.first {
                Text(strength)
                    .font(.caption)
                    .foregroundColor(.saveInk.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !warningDigests.isEmpty || !health.gaps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warningDigests.prefix(2)) { digest in
                        TripHealthLine(
                            icon: "exclamationmark.triangle.fill",
                            text: warningText(for: digest),
                            tint: SaveAtlasPalette.coral
                        )
                    }
                    ForEach(health.gaps.prefix(3)) { gap in
                        VStack(alignment: .leading, spacing: 6) {
                            TripHealthLine(icon: "plus.square.dashed", text: gapText(for: gap), tint: SaveAtlasPalette.kraft)
                            if let suggestion = suggestionsByGapID[gap.id], let onAddSuggestion {
                                ForEach(suggestion.options.prefix(3)) { option in
                                    Button(action: { onAddSuggestion(gap, option) }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label(optionButtonTitle(for: option), systemImage: iconName(for: option.source))
                                                .font(.caption2.weight(.bold))
                                            Text(option.reason)
                                                .font(.caption2.weight(.semibold))
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .foregroundColor(.saveInk)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(optionBackground(for: option.source))
                                        .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(SaveAtlasPalette.canvas.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var warningDigests: [TripWarningDigest] {
        health.warningDigests()
    }

    /// A caveat that holds on every day reads as one plan-wide line; one that only hits some
    /// days keeps the day scope so the repeat is not silently dropped.
    private func warningText(for digest: TripWarningDigest) -> String {
        guard !digest.coversWholeTrip(dayCount: dayCount) else { return digest.message }
        return languageSettings.localized(
            english: "\(digest.message) (\(englishDayScope(digest.dayNumbers)))",
            traditionalChinese: "\(digest.message)（第 \(digest.dayNumbers.map(String.init).joined(separator: "、")) 天）"
        )
    }

    /// Gaps are not collapsed: each one owns its own suggestions and fills a specific day,
    /// so a repeated gap message gets the day that makes the repeat meaningful.
    private func gapText(for gap: TripGap) -> String {
        guard dayCount > 1, let dayNumber = gap.dayNumber else { return gap.message }
        return languageSettings.localized(
            english: "\(gap.message) (Day \(dayNumber))",
            traditionalChinese: "\(gap.message)（第 \(dayNumber) 天）"
        )
    }

    private func englishDayScope(_ dayNumbers: [Int]) -> String {
        let list = dayNumbers.map(String.init).joined(separator: ", ")
        return dayNumbers.count == 1 ? "Day \(list)" : "Days \(list)"
    }

    // Traffic-light semantics stay; only the palette moves to Atlas.
    private var scoreColor: Color {
        if health.score >= 80 { return SaveAtlasPalette.mint }
        if health.score >= 65 { return SaveAtlasPalette.honey }
        return SaveAtlasPalette.coral
    }

    private func optionButtonTitle(for option: GapSuggestionOption) -> String {
        switch option.source {
        case .confirmedSaved:
            return languageSettings.localized(english: "Add saved: \(option.title)", traditionalChinese: "加入已存：\(option.title)")
        case .reviewCandidate:
            return languageSettings.localized(english: "Review candidate: \(option.title)", traditionalChinese: "確認候選：\(option.title)")
        case .sourceClue:
            return languageSettings.localized(english: "Resolve clue: \(option.title)", traditionalChinese: "查證線索：\(option.title)")
        case .externalSuggestion:
            return languageSettings.localized(english: "Approve external: \(option.title)", traditionalChinese: "批准公開候選：\(option.title)")
        }
    }

    private func iconName(for source: GapSuggestionSource) -> String {
        switch source {
        case .confirmedSaved:
            return "mappin.and.ellipse"
        case .reviewCandidate:
            return "checkmark.seal"
        case .sourceClue:
            return "link"
        case .externalSuggestion:
            return "globe"
        }
    }

    private func optionBackground(for source: GapSuggestionSource) -> Color {
        switch source {
        case .confirmedSaved:
            return SaveAtlasPalette.mint.opacity(0.52)
        case .reviewCandidate:
            return SaveAtlasPalette.kraft.opacity(0.5)
        case .sourceClue:
            return SaveAtlasPalette.kraft.opacity(0.5)
        case .externalSuggestion:
            return SaveAtlasPalette.coral.opacity(0.22)
        }
    }
}

private struct TripHealthLine: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundColor(.saveInk)
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveInk.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Day Section

private struct DaySection: View {
    let day: ItineraryDay
    let approvedExternalStopIDs: Set<UUID>
    var travelLegs: [TripTravelLeg] = []
    let onApproveExternalStop: (UUID) -> Void
    let onSkipStop: (UUID) -> Void
    let onMoveEarlier: (UUID) -> Void
    let onMoveLater: (UUID) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    /// A leg renders only when its two stops are still adjacent in the
    /// current canvas order, so user reordering can never surface a stale
    /// estimate.
    private func travelLeg(before index: Int) -> TripTravelLeg? {
        guard index > 0 else { return nil }
        let previous = day.stops[index - 1]
        let current = day.stops[index]
        guard let fromID = previous.placeId, let toID = current.placeId else { return nil }
        return travelLegs.first { $0.fromPlaceId == fromID && $0.toPlaceId == toID }
    }

    private func travelLegLabel(_ leg: TripTravelLeg) -> String {
        switch leg.mode {
        case .walking:
            return languageSettings.localized(
                english: "≈ \(leg.durationMinutes) min walk",
                traditionalChinese: "步行約 \(leg.durationMinutes) 分鐘"
            )
        case .driving:
            return languageSettings.localized(
                english: "≈ \(leg.durationMinutes) min drive",
                traditionalChinese: "開車約 \(leg.durationMinutes) 分鐘"
            )
        case .transit:
            return languageSettings.localized(
                english: "≈ \(leg.durationMinutes) min transit",
                traditionalChinese: "大眾運輸約 \(leg.durationMinutes) 分鐘"
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayLabel)
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(SaveAtlasPalette.kraft.opacity(0.58))
                .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                .clipShape(Capsule())
                .padding(.bottom, 12)

            if let windowNote = day.windowNote, !windowNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageSettings.localized(english: "Travel window", traditionalChinese: "行程時窗"))
                        .font(SaveAtlasType.strong(10))
                        .tracking(0.7)
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(windowNote)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.ink)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaveAtlasPalette.kraft.opacity(0.38), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                }
                .accessibilityIdentifier("plan.window.\(day.dayNumber)")
                .padding(.bottom, 10)
            }

            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                if let leg = travelLeg(before: index) {
                    Label(travelLegLabel(leg), systemImage: leg.mode == .driving ? "car" : "figure.walk")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .padding(.leading, 20)
                        .padding(.vertical, 2)
                }
                HStack(alignment: .top, spacing: 12) {
                    // Timeline
                    VStack(spacing: 0) {
                        Circle()
                            .fill(SaveAtlasPalette.kraft)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(SaveAtlasPalette.line, lineWidth: 1))
                            .padding(.top, 5)
                        if index < day.stops.count - 1 {
                            Rectangle()
                                .fill(SaveAtlasPalette.line.opacity(0.22))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)

                    // Content
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stop.placeName)
                                .font(.subheadline)
                                .fontWeight(.black)
                                .foregroundColor(.saveInk)
                                .lineLimit(2)
                            Spacer()
                            if let time = stop.time {
                                Text(time)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.saveInk)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(SaveAtlasPalette.paper.opacity(0.74))
                                    .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                        }
                        if let duration = stop.duration {
                            Text(durationText(duration))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.saveInk.opacity(0.76))
                        }
                        HStack(spacing: 6) {
                            if let placeState = stop.placeState {
                                StopBadge(text: stateLabel(placeState), tint: stateTint(placeState))
                            }
                            ForEach(stop.risks.prefix(2), id: \.self) { risk in
                                StopBadge(text: riskLabel(risk), tint: SaveAtlasPalette.coral)
                            }
                        }
                        if let note = stop.note {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.saveInk.opacity(0.78))
                                .padding(.top, 1)
                        }
                        if let sourceSummary = stop.sourceSummary {
                            Text(sourceSummary)
                                .font(.caption2)
                                .foregroundColor(.saveMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        StopCanvasControls(
                            stop: stop,
                            canMoveEarlier: index > 0,
                            canMoveLater: index < day.stops.count - 1,
                            isApprovedExternalStop: approvedExternalStopIDs.contains(stop.id),
                            onApproveExternalStop: onApproveExternalStop,
                            onSkipStop: onSkipStop,
                            onMoveEarlier: onMoveEarlier,
                            onMoveLater: onMoveLater
                        )
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .padding(14)
        .background(SaveAtlasPalette.kraft.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var displayLabel: String {
        if let label = day.label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localizedKnownDayLabel(label)
        }
        return fallbackDayLabel
    }

    private var fallbackDayLabel: String {
        languageSettings.localized(
            english: "Day \(day.dayNumber)",
            traditionalChinese: "第 \(day.dayNumber) 天"
        )
    }

    private func localizedKnownDayLabel(_ label: String) -> String {
        let englishDay = "Day \(day.dayNumber)"
        if label == englishDay || label == "List plan" {
            return fallbackDayLabel
        }
        return label
    }

    private func durationText(_ minutes: Int) -> String {
        switch languageSettings.language {
        case .english:
            return "\(minutes) min"
        case .traditionalChinese:
            return "\(minutes) 分鐘"
        }
    }

    private func stateLabel(_ state: ItineraryPlaceState) -> String {
        switch state {
        case .sourceOnly:
            return languageSettings.localized(english: "Source clue", traditionalChinese: "來源線索")
        case .reviewCandidate:
            return languageSettings.localized(english: "Needs review", traditionalChinese: "待確認")
        case .confirmedMapStamp:
            return languageSettings.localized(english: "Map Stamp", traditionalChinese: "地圖章")
        case .externalSuggestion:
            return languageSettings.localized(english: "Unsaved Candidate", traditionalChinese: "尚未儲存")
        }
    }

    private func stateTint(_ state: ItineraryPlaceState) -> Color {
        switch state {
        case .sourceOnly: return SaveAtlasPalette.coral
        case .reviewCandidate: return SaveAtlasPalette.sky
        case .confirmedMapStamp: return SaveAtlasPalette.mint
        case .externalSuggestion: return SaveAtlasPalette.sky
        }
    }

    private func riskLabel(_ risk: TripRisk) -> String {
        switch risk {
        case .hoursUnknown:
            return languageSettings.localized(english: "Hours?", traditionalChinese: "營業待查")
        case .bookingUnknown:
            return languageSettings.localized(english: "Booking?", traditionalChinese: "預約待查")
        case .needsReview:
            return languageSettings.localized(english: "Review", traditionalChinese: "需確認")
        case .externalSuggestion:
            return languageSettings.localized(english: "Approve first", traditionalChinese: "先批准")
        case .tooFarFromPrevious:
            return languageSettings.localized(english: "Far", traditionalChinese: "距離遠")
        case .sourceWeak:
            return languageSettings.localized(english: "Weak source", traditionalChinese: "來源弱")
        }
    }
}

private struct StopCanvasControls: View {
    let stop: ItineraryStop
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let isApprovedExternalStop: Bool
    let onApproveExternalStop: (UUID) -> Void
    let onSkipStop: (UUID) -> Void
    let onMoveEarlier: (UUID) -> Void
    let onMoveLater: (UUID) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        if canMoveEarlier || canMoveLater || stop.placeState == .externalSuggestion {
            VStack(alignment: .leading, spacing: 7) {
                controls

                if stop.placeState == .externalSuggestion, isApprovedExternalStop {
                    Text(languageSettings.localized(
                        english: "Approved for this draft. It is still not saved to memory.",
                        traditionalChinese: "已加入這份草稿，但還不會存進記憶。"
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                }
            }
            .padding(.top, 5)
        }
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Button(action: { onMoveEarlier(stop.id) }) {
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.bold))
                    .frame(width: 28, height: 26)
                    .background(SaveAtlasPalette.paper.opacity(0.74))
                    .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .disabled(!canMoveEarlier)
            .opacity(canMoveEarlier ? 1 : 0.38)

            Button(action: { onMoveLater(stop.id) }) {
                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.bold))
                    .frame(width: 28, height: 26)
                    .background(SaveAtlasPalette.paper.opacity(0.74))
                    .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .disabled(!canMoveLater)
            .opacity(canMoveLater ? 1 : 0.38)

            if stop.placeState == .externalSuggestion {
                Button(action: { onApproveExternalStop(stop.id) }) {
                    Label(approveText, systemImage: isApprovedExternalStop ? "checkmark.circle.fill" : "checkmark")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background((isApprovedExternalStop ? SaveAtlasPalette.mint : SaveAtlasPalette.kraft).opacity(0.58))
                        .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                        .clipShape(Capsule())
                }

                Button(action: { onSkipStop(stop.id) }) {
                    Label(skipText, systemImage: "xmark")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(SaveAtlasPalette.coral.opacity(0.2))
                        .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.saveInk)
    }

    private var approveText: String {
        isApprovedExternalStop
            ? languageSettings.localized(english: "Added", traditionalChinese: "已加入")
            : languageSettings.localized(english: "Approve", traditionalChinese: "批准")
    }

    private var skipText: String {
        languageSettings.localized(english: "Skip", traditionalChinese: "略過")
    }
}

private struct StopBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.52))
            .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
            .clipShape(Capsule())
    }
}
