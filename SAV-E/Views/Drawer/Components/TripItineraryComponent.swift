import SwiftUI

struct TripItineraryComponent: View {
    let title: String
    private let sourceDays: [ItineraryDay]
    var tripHealth: TripHealth?
    let aiMessage: String?
    var places: [Place] = []
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var showShareSheet = false
    @State private var canvas: TripCanvasDraft

    init(
        title: String,
        days: [ItineraryDay],
        tripHealth: TripHealth? = nil,
        aiMessage: String?,
        places: [Place] = []
    ) {
        self.title = title
        self.sourceDays = days
        self.tripHealth = tripHealth
        self.aiMessage = aiMessage
        self.places = places
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
                        .background(Color.saveCream.opacity(0.48))
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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

                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveInk)
                        .frame(width: 34, height: 34)
                        .background(Color.saveNotebookPage.opacity(0.74))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showShareSheet) {
                    if let url = buildShareURL() {
                        ShareSheet(items: [url])
                    }
                }

                Label(dayCountText, systemImage: "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.saveHoney)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let tripHealth {
                TripHealthSummaryCard(health: tripHealth, suggestionsByGapID: suggestionsByGapID) { gap, option in
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
                        onApproveExternalStop: { stopID in canvas.approveExternalStop(stopID) },
                        onSkipStop: { stopID in canvas.skipStop(stopID) },
                        onMoveEarlier: { stopID in canvas.moveStopEarlier(stopID) },
                        onMoveLater: { stopID in canvas.moveStopLater(stopID) }
                    )
                }
            }
        }
        .padding(14)
        .background(Color.saveNotebookPage.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: canvasInputID) { _, _ in
            canvas = TripCanvasDraft(days: sourceDays)
        }
    }

    private func buildShareURL() -> URL? {
        let tripData = SharedTripData.from(title: title, city: "", days: canvas.visibleDays, places: places)
        return tripData.toURL()
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
            mapCandidates: [],
            outputLanguage: languageSettings.language
        )
        return Dictionary(uniqueKeysWithValues: suggestions.map { ($0.gapId, $0) })
    }

    private func dayNumber(for gap: TripGap) -> Int {
        if let explicit = Int(gap.dayId.filter(\.isNumber)) {
            return explicit
        }
        return canvas.visibleDays.first?.dayNumber ?? 1
    }

}

// MARK: - Trip Health

private struct TripHealthSummaryCard: View {
    let health: TripHealth
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
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())
            }

            if let strength = health.strengths.first {
                Text(strength)
                    .font(.caption)
                    .foregroundColor(.saveInk.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !health.warnings.isEmpty || !health.gaps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(health.warnings.prefix(2)) { warning in
                        TripHealthLine(icon: "exclamationmark.triangle.fill", text: warning.message, tint: .saveCoral)
                    }
                    ForEach(health.gaps.prefix(3)) { gap in
                        VStack(alignment: .leading, spacing: 6) {
                            TripHealthLine(icon: "plus.square.dashed", text: gap.message, tint: .saveCream)
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
                                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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
        .background(Color.saveCream.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var scoreColor: Color {
        if health.score >= 80 { return .saveMint }
        if health.score >= 65 { return .saveHoney }
        return .saveCoral
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
            return .saveMint.opacity(0.52)
        case .reviewCandidate:
            return .saveSignal.opacity(0.42)
        case .sourceClue:
            return .saveSignal.opacity(0.42)
        case .externalSuggestion:
            return .saveCoral.opacity(0.24)
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
    let onApproveExternalStop: (UUID) -> Void
    let onSkipStop: (UUID) -> Void
    let onMoveEarlier: (UUID) -> Void
    let onMoveLater: (UUID) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayLabel)
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.saveHoney.opacity(0.66))
                .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                .clipShape(Capsule())
                .padding(.bottom, 12)

            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.saveHoney)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1))
                            .padding(.top, 5)
                        if index < day.stops.count - 1 {
                            Rectangle()
                                .fill(Color.saveNotebookLine.opacity(0.22))
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
                                    .background(Color.saveNotebookPage.opacity(0.74))
                                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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
                                StopBadge(text: riskLabel(risk), tint: .saveCoral)
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
        .background(Color.saveHoney.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
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
            return languageSettings.localized(english: "Confirmed", traditionalChinese: "已確認")
        case .externalSuggestion:
            return languageSettings.localized(english: "External", traditionalChinese: "外部建議")
        }
    }

    private func stateTint(_ state: ItineraryPlaceState) -> Color {
        switch state {
        case .sourceOnly: return .saveSignal
        case .reviewCandidate: return .saveSignal
        case .confirmedMapStamp: return .saveMint
        case .externalSuggestion: return .saveCoral
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
                    .background(Color.saveNotebookPage.opacity(0.74))
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .disabled(!canMoveEarlier)
            .opacity(canMoveEarlier ? 1 : 0.38)

            Button(action: { onMoveLater(stop.id) }) {
                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.bold))
                    .frame(width: 28, height: 26)
                    .background(Color.saveNotebookPage.opacity(0.74))
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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
                        .background((isApprovedExternalStop ? Color.saveMint : Color.saveHoney).opacity(0.58))
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())
                }

                Button(action: { onSkipStop(stop.id) }) {
                    Label(skipText, systemImage: "xmark")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Color.saveCoral.opacity(0.22))
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
            .clipShape(Capsule())
    }
}
