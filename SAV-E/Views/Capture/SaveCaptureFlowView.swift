import SwiftUI
import UIKit
import PhotosUI
import Vision
import ImageIO

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
    let onSearchNearby: () -> Void
    @State private var sharedText = ""
    @State private var isAnalyzing = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isReadingPhoto = false
    @State private var errorMessage: String?
    @State private var isGoogleTakeoutPresented = false
    @FocusState private var isInputFocused: Bool
    @State private var detent: PresentationDetent = .medium
    @State private var entitlements = SaveEntitlementStore.shared

    var body: some View {
        Group {
            if isGoogleTakeoutPresented {
                NavigationStack {
                    GoogleTakeoutImportView(
                        existingPlaces: existingPlaces,
                        onSave: onSaveGoogleTakeoutImport,
                        onClose: { isGoogleTakeoutPresented = false }
                    )
                }
            } else {
                captureStack
            }
        }
        .interactiveDismissDisabled(isAnalyzing)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(SaveAtlasPalette.paper)
        // Keep capture.flow on the cover root. Without `.contain`, the
        // identifier collapses this Group and hides takeout.import.root
        // after the in-sheet swap. Do not remount Postal Import.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.flow")
        .onAppear {
            if sharedText.isEmpty {
                sharedText = initialText
            }
        }
        .task {
            await entitlements.refresh()
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .task(id: selectedPhoto) {
            await readSelectedPhoto()
        }
        .onChange(of: sharedText) { _, draft in
            onDraftChange(draft)
        }
    }

    private var captureStack: some View {
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

                        if isReadingPhoto {
                            ProgressView(localized("Reading photo…", "讀取照片中…"))
                                .font(SaveAtlasType.body(13))
                                .padding(.top, SaveSpace.md)
                                .accessibilityIdentifier("capture.readingPhoto")
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
                    if isAIQuotaExhausted {
                        Text(localized(
                            "AI assist is unavailable right now. You can still save a link or import a file.",
                            "目前無法使用 AI 協助。仍可從連結或檔案存地點。"
                        ))
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ai.quotaExhausted")
                    }

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
                    .disabled(!canSubmitDraft)
                    .opacity(canSubmitDraft ? 1 : 0.48)
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
                .disabled(isBusy)
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
                selectedPhoto = nil
                isPhotoPickerPresented = true
            }
            optionRow(
                systemImage: "magnifyingglass",
                title: localized("Search nearby", "搜尋附近"),
                identifier: "capture.searchNearby"
            ) {
                isInputFocused = false
                onSearchNearby()
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
        .disabled(isBusy)
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
            optionLabel(systemImage: systemImage, title: title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func optionLabel(systemImage: String, title: String) -> some View {
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

    private var savedCountText: String {
        let count = existingPlaces.count
        return localized("\(count) places saved", "已收藏 \(count) 個地點")
    }

    private var isBusy: Bool { isAnalyzing || isReadingPhoto }

#if DEBUG
    private var forcesQuotaExhausted: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-ai-quota-exhausted")
    }
#else
    private var forcesQuotaExhausted: Bool { false }
#endif

    /// Exhausted AI assist is a neutral hint on this surface. It never
    /// opens `paywall.root` — Pro is sold for unlimited saved places only.
    private var isAIQuotaExhausted: Bool {
        if forcesQuotaExhausted { return true }
        return entitlements.decideAIAssist().isRefusal
    }

    /// Links stay capturable after AI quota exhaustion. Metered analysis
    /// is the only path that turns Save off.
    private var draftLooksLikeLink: Bool {
        PendingPlaceImportService.looksLikeURL(trimmedText)
    }

    private var canSubmitDraft: Bool {
        guard !trimmedText.isEmpty, !isBusy else { return false }
        if isAIQuotaExhausted { return draftLooksLikeLink }
        return true
    }

    private func readSelectedPhoto() async {
        guard let photo = selectedPhoto else { return }
        isReadingPhoto = true
        isInputFocused = false
        errorMessage = nil
        defer { isReadingPhoto = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw SaveCapturePhotoText.Failure.invalidImage
            }
            try Task.checkCancellation()
            let text = try await Task.detached(priority: .userInitiated) {
                try SaveCapturePhotoText.recognize(data)
            }.value
            try Task.checkCancellation()
            sharedText = trimmedText.isEmpty ? text : sharedText + "\n" + text
            detent = .large
            isInputFocused = true
        } catch is CancellationError {
            // Dismissing Capture must not write a late OCR result into the draft.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = localized(
                "Could not read place text in this photo. Choose a clear sign or screenshot, or type the place name.",
                "無法辨識照片中的地點文字。請選擇清晰的招牌或截圖，或輸入地點名稱。"
            )
        }
    }

    private var trimmedText: String {
        sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func analyze() {
        guard canSubmitDraft else { return }
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

/// Reads only the user-selected image on device. The caller presents editable
/// text; only the explicit Save action invokes the existing candidate pipeline.
enum SaveCapturePhotoText {
    enum Failure: Error { case invalidImage, noText }

    nonisolated static func recognize(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else {
            throw Failure.invalidImage
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.noText }
        return text
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
        onCancel: {},
        onSearchNearby: {}
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
        onCancel: {},
        onSearchNearby: {}
    )
    .preferredColorScheme(.dark)
}
