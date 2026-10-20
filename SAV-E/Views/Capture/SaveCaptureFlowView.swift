import SwiftUI
import UIKit

/// Doodle v1 Capture sheet (spec §7.5). Same import / analyze pipeline as
/// before; only the paper, handwriting, and spacing change. Sheet detents are
/// `.medium` / `.large`. Cards stay ungrained.
struct SaveCaptureFlowView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let tripName: String?
    let initialText: String
    let existingPlaces: [Place]
    let onDraftChange: (String) -> Void
    let onImport: (String) async throws -> [UUID]
    let onSaveGoogleTakeoutImport: ([ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary
    let onComplete: ([UUID]) -> Void
    let onCancel: () -> Void
    @State private var sharedText = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var isGoogleTakeoutPresented = false
    @FocusState private var isInputFocused: Bool
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, SaveSpace.xs)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        inputField
                            .padding(.top, SaveSpace.md)

                        optionRows
                            .padding(.top, SaveSpace.md)

                        if let suggestion {
                            suggestionCard(suggestion)
                                .padding(.top, SaveSpace.md)
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(SaveAtlasType.body(13))
                                .foregroundStyle(SaveAtlasPalette.coral)
                                .padding(.top, SaveSpace.md)
                                .accessibilityIdentifier("capture.error")
                        }
                    }
                    .padding(.bottom, SaveSpace.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SaveAtlasPalette.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: SaveSpace.sm) {
                    Button(action: analyze) {
                        HStack(spacing: SaveSpace.xs) {
                            if isAnalyzing { ProgressView().tint(.white) }
                            Text(isAnalyzing
                                 ? localized("Analyzing…", "分析中…")
                                 : localized("Save", "儲存"))
                        }
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: SaveLayout.buttonHeight)
                        .background(
                            SaveAtlasPalette.coral,
                            in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                        )
                    }
                    .disabled(trimmedText.isEmpty || isAnalyzing)
                    .opacity(trimmedText.isEmpty || isAnalyzing ? 0.48 : 1)
                    .accessibilityIdentifier("capture.analyze")

                    Text(savedCountText)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("capture.savedCount")
                }
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, SaveSpace.xs)
                .padding(.bottom, SaveSpace.sm)
                .background(SaveAtlasPalette.paper)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
                    }
                    .disabled(isAnalyzing)
                    .accessibilityLabel(localized("Close capture", "關閉新增線索"))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isGoogleTakeoutPresented) {
                GoogleTakeoutImportView(
                    existingPlaces: existingPlaces,
                    onSave: onSaveGoogleTakeoutImport
                )
            }
        }
        .interactiveDismissDisabled(isAnalyzing)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(SaveAtlasPalette.paper)
        .accessibilityIdentifier("capture.flow")
        .onAppear {
            if sharedText.isEmpty {
                sharedText = initialText
            }
        }
        .onChange(of: sharedText) { _, draft in
            onDraftChange(draft)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SaveSpace.tight) {
            SaveDisplayTitle(
                text: localized("Save a place", "存一個地方"),
                pointSize: 28,
                relativeTo: .title2
            )
            if let tripName {
                Text(localized("For \(tripName)", "準備加入「\(tripName)」"))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.forest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("capture.header")
    }

    private var inputField: some View {
        ZStack(alignment: .leading) {
            if sharedText.isEmpty {
                Text(localized("Paste a link or type a name", "貼上連結或輸入名稱"))
                    .font(SaveAtlasType.body(16))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .padding(.horizontal, SaveSpace.md)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $sharedText)
                .font(SaveAtlasType.body(16))
                .foregroundStyle(SaveAtlasPalette.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, SaveSpace.sm)
                .padding(.vertical, SaveSpace.tight)
                .focused($isInputFocused)
                .accessibilityLabel(localized("Link or note", "連結或筆記"))
                .accessibilityIdentifier("capture.input")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(localized("Done", "完成")) { isInputFocused = false }
                            .accessibilityIdentifier("capture.keyboardDone")
                    }
                }
        }
        .frame(height: SaveLayout.buttonHeight)
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
        }
    }

    private var optionRows: some View {
        VStack(spacing: 0) {
            pasteRow
            optionRow(
                systemImage: "photo",
                title: localized("From photo", "從照片"),
                identifier: "capture.fromPhoto"
            ) {
                isInputFocused = false
            }
            optionRow(
                systemImage: "magnifyingglass",
                title: localized("Search nearby", "搜尋附近"),
                identifier: "capture.searchNearby"
            ) {
                isInputFocused = true
            }
            optionRow(
                systemImage: "square.and.arrow.down",
                title: localized("Import file", "匯入檔案"),
                identifier: "capture.importGoogleTakeout"
            ) {
                isInputFocused = false
                detent = .large
                isGoogleTakeoutPresented = true
            }
            .disabled(isAnalyzing)
            .accessibilityLabel(localized("Import Google Takeout", "匯入 Google Takeout"))
        }
    }

    private var pasteRow: some View {
        ZStack {
            optionRow(
                systemImage: "clipboard",
                title: localized("Paste link", "貼上連結"),
                identifier: "capture.paste"
            ) {
                if let value = UIPasteboard.general.string {
                    sharedText = value
                }
            }
            PasteButton(payloadType: String.self) { values in
                if let value = values.first { sharedText = value }
            }
            .labelStyle(.iconOnly)
            .opacity(0.015)
            .frame(maxWidth: .infinity, maxHeight: SaveLayout.buttonHeight)
            .accessibilityHidden(true)
        }
        .frame(height: SaveLayout.buttonHeight)
    }

    private func optionRow(
        systemImage: String,
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SaveLayout.stickerToText) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(SaveAtlasType.body(17))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SaveLayout.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func suggestionCard(_ place: Place) -> some View {
        HStack(spacing: SaveLayout.stickerToText) {
            SaveDoodleSticker(category: place.category, visited: false)
                .frame(width: SaveLayout.stickerBox, height: SaveLayout.stickerBox)
            VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                Text(place.name)
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(1)
                Text(suggestionMeta(place))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SaveSpace.md)
        .frame(minHeight: SaveLayout.rowMinHeight)
        .background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
        }
        .accessibilityIdentifier("capture.suggestion")
    }

    private var suggestion: Place? {
        existingPlaces.first
    }

    private func suggestionMeta(_ place: Place) -> String {
        let lens = SaveDoodleHomeCatalog.lens(for: place.category)
            .title(language: languageSettings.language)
        if let area = SaveDoodleHomeCatalog.cityDisplayName(
            for: place,
            language: languageSettings.language
        ) {
            return "\(lens) · \(area)"
        }
        return lens
    }

    private var savedCountText: String {
        let count = min(existingPlaces.count, 50)
        return localized("Saved \(count) / 50", "已存 \(count) / 50")
    }

    private var trimmedText: String {
        sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func analyze() {
        guard !trimmedText.isEmpty, !isAnalyzing else { return }
        isAnalyzing = true
        errorMessage = nil
        Task {
            defer { isAnalyzing = false }
            do {
                let candidateIDs = try await onImport(trimmedText)
                guard !candidateIDs.isEmpty else {
                    errorMessage = localized(
                        "No place clue was found. Add the post caption, city, or a map link and try again.",
                        "沒有找到地點線索。請補上貼文文字、城市或地圖連結後再試。"
                    )
                    return
                }
                onComplete(candidateIDs)
            } catch ReviewCandidateError.sourceAlreadyReviewed {
                errorMessage = localized(
                    "This source was already saved or reviewed. No new review was added.",
                    "這個來源已收藏或處理過，沒有新增待確認項目。"
                )
            } catch {
                errorMessage = localized("Analysis could not finish. Please try again later.", "分析暫時無法完成，請稍後再試。")
            }
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

#Preview("Capture light") {
    SaveCaptureFlowView(
        tripName: nil,
        initialText: "",
        existingPlaces: [],
        onDraftChange: { _ in },
        onImport: { _ in [] },
        onSaveGoogleTakeoutImport: { _ in
            GoogleTakeoutSaveSummary(saved: 0, skippedDuplicates: 0, reviewDrafts: 0)
        },
        onComplete: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Capture dark") {
    SaveCaptureFlowView(
        tripName: nil,
        initialText: "",
        existingPlaces: [],
        onDraftChange: { _ in },
        onImport: { _ in [] },
        onSaveGoogleTakeoutImport: { _ in
            GoogleTakeoutSaveSummary(saved: 0, skippedDuplicates: 0, reviewDrafts: 0)
        },
        onComplete: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
