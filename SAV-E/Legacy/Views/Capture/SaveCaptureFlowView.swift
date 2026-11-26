import SwiftUI
import UIKit
import PhotosUI
import Vision
import ImageIO

/// Doodle v1 Capture sheet (spec §7.5). Same import / analyze pipeline as
/// before; only the paper, handwriting, and spacing change. Sheet detents are
/// raised-medium (+40pt) / `.large`. Cards stay ungrained.
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
    @State private var detent: PresentationDetent = Self.raisedMediumDetent
    @State private var entitlements = SaveEntitlementStore.shared

    private enum Appearance {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
        static let paper = SaveBrandUI.canvas
        static let contentBackground = Color.clear
        static let ink = SaveBrandUI.ink
        static let muted = SaveBrandUI.muted
        static let action = SaveBrandUI.action
        static let actionInk = SaveBrandUI.actionInk
        static let line = SaveBrandUI.ink.opacity(0.10)
        static let radius: CGFloat = 22
        static func body(_ size: CGFloat) -> Font { size <= 13 ? .caption : .body }
        static func strong(_ size: CGFloat) -> Font { body(size).weight(.semibold) }
#else
        static let paper = SaveAtlasPalette.paper
        static let contentBackground = paper
        static let ink = SaveAtlasPalette.ink
        static let muted = SaveAtlasPalette.muted
        static let action = SaveAtlasPalette.coral
        static let actionInk = Color.white
        static let line = SaveAtlasPalette.ink
        static let radius = SaveAtlasPalette.cardRadius
        static func body(_ size: CGFloat) -> Font { SaveAtlasType.body(size) }
        static func strong(_ size: CGFloat) -> Font { SaveAtlasType.strong(size) }
#endif
    }

    @ScaledMetric(relativeTo: .body) private var scaledControlHeight = SaveLayout.buttonHeight
    private var controlHeight: CGFloat {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
        scaledControlHeight
#else
        SaveLayout.buttonHeight
#endif
    }

    /// Medium + 40pt so the Home peek matches the locked capture mock.
    private static var raisedMediumDetent: PresentationDetent {
        .height((UIScreen.main.bounds.height * 0.5) + 40)
    }

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
        .presentationDetents([Self.raisedMediumDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        #if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
        .presentationBackground(.regularMaterial)
#else
        .presentationBackground(Appearance.paper)
#endif
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

                        if let recentSavedPlace {
                            recentSaveCard(recentSavedPlace)
                                .padding(.top, SaveSpace.md)
                        }

                        if isReadingPhoto {
                            ProgressView(localized("Reading photo…", "讀取照片中…"))
                                .font(Appearance.body(13))
                                .padding(.top, SaveSpace.md)
                                .accessibilityIdentifier("capture.readingPhoto")
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(Appearance.body(13))
                                .foregroundStyle(Appearance.action)
                                .padding(.top, SaveSpace.md)
                                .accessibilityIdentifier("capture.error")
                        }
                    }
                    .padding(.bottom, SaveSpace.lg)
                }
                .scrollDismissesKeyboard(.interactively)

                // Keep Save as a real sibling. A bottom `safeAreaInset`
                // painted over Import file so the in-sheet Postal swap
                // never ran (run 40041793245 hierarchy: both frames
                // at y≈746 on the half-screen detent).
                captureSaveBar
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Appearance.contentBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Appearance.ink)
                            .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
                    }
                    .disabled(isAnalyzing)
                    .accessibilityLabel(localized("Close capture", "關閉新增線索"))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var captureSaveBar: some View {
        VStack(spacing: SaveSpace.sm) {
            if isAIQuotaExhausted {
                Text(localized(
                    "AI assist is unavailable right now. You can still save a link or import a file.",
                    "目前無法使用 AI 協助。仍可從連結或檔案存地點。"
                ))
                .font(Appearance.body(13))
                .foregroundStyle(Appearance.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ai.quotaExhausted")
            }

            Button(action: analyze) {
                HStack(spacing: SaveSpace.xs) {
                    if isAnalyzing { ProgressView().tint(Appearance.actionInk) }
                    Text(isAnalyzing
                         ? localized("Analyzing…", "分析中…")
                         : localized("Save", "儲存"))
                }
                .font(Appearance.strong(17))
                .foregroundStyle(Appearance.actionInk)
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight)
                .background(
                    Appearance.action,
                    in: RoundedRectangle(cornerRadius: Appearance.radius, style: .continuous)
                )
            }
            .disabled(!canSubmitDraft)
            .savvyPressFeedback(prominent: true, plain: false)
            .accessibilityIdentifier("capture.analyze")

            Text(savedCountText)
                .font(Appearance.body(13))
                .foregroundStyle(Appearance.muted)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("capture.savedCount")
        }
        .padding(.top, SaveSpace.xs)
        .padding(.bottom, SaveSpace.sm)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SaveSpace.tight) {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
            Text(localized("Save a place", "存一個地方"))
                .font(.title2.weight(.bold)).foregroundStyle(Appearance.ink)
#else
            SaveDisplayTitle(text: localized("Save a place", "存一個地方"), pointSize: 34, relativeTo: .title)
#endif
            if let tripName {
                Text(localized("For \(tripName)", "準備加入「\(tripName)」"))
                    .font(Appearance.body(13))
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
                    .font(Appearance.body(16))
                    .foregroundStyle(Appearance.muted)
                    .padding(.horizontal, SaveSpace.md)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $sharedText)
                .font(Appearance.body(16))
                .foregroundStyle(Appearance.ink)
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
                            .savvyPressFeedback(plain: false)
                            .accessibilityIdentifier("capture.keyboardDone")
                    }
                }
        }
        .frame(height: controlHeight)
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
        .padding(.vertical, 8)
        .background(SaveBrandUI.surface, in: RoundedRectangle(cornerRadius: Appearance.radius))
        .savvyInputFeedback()
#endif
        .overlay {
            RoundedRectangle(cornerRadius: Appearance.radius, style: .continuous)
                .stroke(Appearance.line, lineWidth: SaveAtlasPalette.strokeWidth)
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
        .frame(height: controlHeight)
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
        .savvyPressFeedback()
        .accessibilityIdentifier(identifier)
    }

    private func optionLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: SaveLayout.stickerToText) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Appearance.ink)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(Appearance.body(17))
                .foregroundStyle(Appearance.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: controlHeight)
        .contentShape(Rectangle())
    }

    private var savedCountText: String {
        let count = existingPlaces.count
        return localized("\(count) places saved", "已收藏 \(count) 個地點")
    }

    /// Newest confirmed save for the mock's "recent saves" sticker card.
    /// Not a suggestion and not analyzed until the user taps Save.
    private var recentSavedPlace: Place? {
        existingPlaces.max(by: { $0.createdAt < $1.createdAt })
    }

    private func recentSaveCard(_ place: Place) -> some View {
        let eatGo = eatGoLabel(for: place.category)
        let city = SaveDoodleHomeCatalog.localityLabel(in: place.address) ?? ""
        let meta = city.isEmpty ? eatGo : "\(eatGo) · \(city)"
        return HStack(alignment: .center, spacing: SaveLayout.stickerToText) {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
            Image(systemName: "bookmark.fill")
                .font(.title3).foregroundStyle(SaveBrandUI.brand)
                .frame(width: 44, height: 44)
                .background(SaveBrandUI.soft, in: RoundedRectangle(cornerRadius: 14))
#else
            SaveDoodleSticker(
                category: place.category,
                placeName: place.name,
                visited: place.status == .visited
            )
            .frame(width: SaveLayout.stickerBox, height: SaveLayout.stickerBox)
#endif

            VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                Text(place.name)
                    .font(Appearance.strong(17))
                    .foregroundStyle(Appearance.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(meta)
                    .font(Appearance.body(13))
                    .foregroundStyle(Appearance.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SaveSpace.md)
        .padding(.vertical, SaveSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Appearance.paper,
            in: RoundedRectangle(cornerRadius: Appearance.radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Appearance.radius, style: .continuous)
                .stroke(Appearance.line, lineWidth: SaveAtlasPalette.strokeWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.recentSave")
        .accessibilityLabel("\(place.name), \(meta)")
    }

    private func eatGoLabel(for category: PlaceCategory) -> String {
        switch category {
        case .food, .cafe, .bar:
            return localized("Eat", "吃")
        case .attraction, .stay, .shopping:
            return localized("Go", "去")
        }
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
        SaveSourceHandle.looksLikeURL(trimmedText)
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
