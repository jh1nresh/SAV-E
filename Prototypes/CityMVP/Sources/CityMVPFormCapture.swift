#if SAVVY_CITY_MVP
import SwiftUI

/// Presentation only. Capture owns drafts, quotas, OCR and candidate creation.
struct CityMVPFormCapture: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let tripName: String?
    let isBusy: Bool
    let isAnalyzing: Bool
    let isReadingPhoto: Bool
    let errorMessage: String?
    let isQuotaExhausted: Bool
    let canSubmit: Bool
    let savedCountText: String
    let recentSavedPlace: Place?
    let onPhoto: () -> Void
    let onSearch: () -> Void
    let onImportFile: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("What's the place?", "想去哪個地方？")).font(.largeTitle.bold())
                            Text(t("A link, a screenshot, a name. Start anywhere.", "一個連結、一張截圖、一個名字，都可以。"))
                                .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                            if let tripName { Text(t("For \(tripName)", "準備加入「\(tripName)」")).font(.caption) }
                        }.accessibilityIdentifier("capture.header")
                        CityMVPFormSteps(titles: [t("Clue", "線索"), t("Review", "確認"), t("Save", "收藏")], selected: 0)
                        if !text.isEmpty {
                            HStack {
                                Spacer()
                                Button(t("Clear draft", "清空草稿")) {
                                    text = ""; focus.wrappedValue = false
                                }.frame(minHeight: 44).disabled(isBusy)
                                    .accessibilityIdentifier("capture.clearDraft")
                            }
                        }
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(t("Paste a link or type a place name", "貼上連結或輸入地點名稱"))
                                    .foregroundStyle(CityMVPFormStyle.muted).padding(17).allowsHitTesting(false)
                            }
                            TextEditor(text: $text)
                                .font(.body).scrollContentBackground(.hidden).padding(10)
                                .focused(focus).disabled(isBusy)
                                .accessibilityLabel(t("Link or note", "連結或筆記"))
                                .accessibilityIdentifier("capture.input")
                                .toolbar { ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button(t("Done", "完成")) { focus.wrappedValue = false }
                                        .accessibilityIdentifier("capture.keyboardDone")
                                } }
                        }
                        .frame(height: 112)
                        .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("🔗").font(.title).accessibilityHidden(true)
                                HStack {
                                    Text(t("Link", "連結")).font(.headline)
                                    Spacer(minLength: 0)
                                    PasteButton(payloadType: String.self) { values in
                                        if let value = values.first { text = value }
                                    }
                                    .labelStyle(.iconOnly).tint(CityMVPFormStyle.ink)
                                    .accessibilityLabel(t("Paste link", "貼上連結"))
                                    .accessibilityIdentifier("capture.paste")
                                    .frame(minWidth: 44, minHeight: 44)
                                }
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                                .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                            option("📷", t("Photo", "照片"), "capture.fromPhoto", onPhoto)
                            option("🔎", t("Nearby", "附近"), "capture.searchNearby", onSearch)
                            option("📂", t("Import file", "匯入檔案"), "capture.importGoogleTakeout", onImportFile)
                                .accessibilityLabel(t("Import Google Takeout", "匯入 Google Takeout"))
                        }.disabled(isBusy)
                        if let place = recentSavedPlace {
                            HStack(spacing: 14) {
                                Image(systemName: "bookmark.fill").frame(width: 40, height: 40)
                                    .background(CityMVPFormStyle.canvas, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name).font(.headline)
                                    Text(t("Map Stamp · Saved", "Map Stamp · 已收藏"))
                                        .font(.caption).foregroundStyle(CityMVPFormStyle.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("capture.recentSave")
                        }
                        if isReadingPhoto {
                            ProgressView(t("Reading photo…", "讀取照片中…")).accessibilityIdentifier("capture.readingPhoto")
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("capture.error")
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 12)
                }.scrollDismissesKeyboard(.interactively)
                VStack(spacing: 10) {
                    if isQuotaExhausted {
                        Text(t("AI assist is unavailable right now. You can still add a link or import a file.", "目前無法使用 AI 協助。仍可新增連結或匯入檔案。"))
                            .font(.footnote).foregroundStyle(CityMVPFormStyle.muted)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ai.quotaExhausted")
                    }
                    Button(action: onSubmit) {
                        HStack {
                            if isAnalyzing { ProgressView().tint(CityMVPFormStyle.canvas) }
                            Text(isAnalyzing ? t("Finding…", "尋找中…") : t("Find the place", "尋找地點"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.font(.headline).foregroundStyle(CityMVPFormStyle.canvas).padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(CityMVPFormStyle.ink.opacity(canSubmit ? 1 : 0.4), in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).disabled(!canSubmit).accessibilityIdentifier("capture.analyze")
                    Text(savedCountText).font(.footnote).foregroundStyle(CityMVPFormStyle.muted)
                        .accessibilityIdentifier("capture.savedCount")
                }.padding(.horizontal, 24).padding(.bottom, 12)
                    .background(CityMVPFormStyle.canvas)
            }.foregroundStyle(CityMVPFormStyle.ink).background(CityMVPFormStyle.canvas.ignoresSafeArea())
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                            .background(CityMVPFormStyle.card, in: Circle()).contentShape(Circle())
                    }.disabled(isAnalyzing).accessibilityLabel(t("Close capture", "關閉新增線索"))
                        .accessibilityIdentifier("capture.close")
                } }
                .toolbarBackground(.hidden, for: .navigationBar)
        }.tint(CityMVPFormStyle.ink)
    }

    private func option(_ emoji: String, _ title: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Text(emoji).font(.title).accessibilityHidden(true)
                Text(title).font(.headline)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func t(_ en: String, _ zh: String) -> String { language.localized(english: en, traditionalChinese: zh) }
}

/// Non-map surfaces follow the Ramin reference; map and dock retain their own palette.
enum CityMVPFormStyle {
    static let canvas = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
    static let ink = Color.primary
    static let muted = Color.secondary
}

struct CityMVPFormSteps: View {
    let titles: [String]
    let selected: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text("\(index + 1)  \(title)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(index == selected ? CityMVPFormStyle.canvas : CityMVPFormStyle.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(index == selected ? CityMVPFormStyle.ink : CityMVPFormStyle.card, in: Capsule())
            }
        }.accessibilityElement(children: .combine)
    }
}
#endif
