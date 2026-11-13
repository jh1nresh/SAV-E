#if SAVVY_CITY_MVP
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Translation

struct CityMVPGuideBriefSheet: View {
    let place: Place
    let onOpen: (Place) -> Void
    var opensSavedDetail = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    @EnvironmentObject private var recommendations: CityMVPRecommendationStore
    @State private var showsDriver = false
    @State private var showsExport = false
    @State private var document: CityGuideDocument?
    @State private var notice: String?
    private var brief: CityMVPGuideBrief { .init(place: place) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(brief.name).font(.title.bold()).textSelection(.enabled)
                Text(brief.visited ? t("Visited · not verified arrival", "已標記去過 · 並非驗證抵達") : t("Want to go", "想去"))
                    .font(.subheadline.weight(.semibold))
                recommendationSources
                Text(t("Saved", "收藏時間") + " · " + brief.savedAt.formatted(date: .abbreviated, time: .shortened))
                Text(t("This is the saved date, not a verification date. Visit status is not proof of arrival.", "這是收藏時間，不是驗證時間；去過狀態不代表抵達證明。"))
                    .font(.caption).foregroundStyle(.secondary)
                section(t("Original address", "原始地址"), text: brief.hasAddress ? brief.address : t("No address saved.", "尚未儲存地址。"))
                if brief.hasAddress {
                    Button(t("Copy address", "複製地址")) { UIPasteboard.general.string = brief.address; notice = t("Address copied.", "已複製地址。") }
                        .accessibilityIdentifier("cityMVP.guide.copyAddress")
                    Button(t("Show address card", "顯示地址卡")) { showsDriver = true }
                        .disabled(!brief.hasStreetNumber)
                        .accessibilityIdentifier("cityMVP.guide.driverCard")
                    if !brief.hasStreetNumber {
                        Text(t("Add a full street address with a house number before making a driver card.", "請先補上完整街道門牌，再產生司機卡。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let source = brief.sourceURL {
                    Link(t("Open saved source", "開啟已存來源"), destination: source)
                } else {
                    Text(t("No safe HTTPS source link saved.", "尚未儲存可安全開啟的 HTTPS 來源。"))
                        .foregroundStyle(.secondary)
                }
                section(t("Source statements · not independently verified", "來源敘述 · 未獨立驗證"),
                        text: brief.sourceStatements.isEmpty ? t("No source statements saved.", "尚未儲存來源敘述。") : brief.sourceStatements.joined(separator: "\n\n"))
                section(t("Your private note", "你的私人筆記"), text: brief.privateNote ?? t("No private note saved.", "尚未儲存私人筆記。"))
                if #available(iOS 18.0, *) {
                    CityGuideTranslation()
                } else {
                    Text(t("Apple translation requires iOS 18 or later. Original text remains available.", "Apple 翻譯需要 iOS 18 以上；原文仍可查看。"))
                }
                Button(opensSavedDetail ? t("Open place", "開啟地點") : t("Show on map", "顯示於地圖")) {
                    guard opensSavedDetail || brief.canShowOnMap else { return }
                    onOpen(place)
                }
                    .disabled(!opensSavedDetail && !brief.canShowOnMap)
                    .accessibilityIdentifier(opensSavedDetail ? "cityMVP.guide.openPlace" : "cityMVP.guide.showMap")
                if !brief.canShowOnMap { Text(t("This place has no Apple Maps-compatible location.", "此地點沒有可用於 Apple 地圖的位置。")) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("Export this venue only", "只匯出這個地點")).font(.headline)
                    Text(t("The file contains this place’s ID, name, address, category, saved date and safe source URL. Private notes, source statements, photos, ratings and visit history are excluded. You choose where to save or share it.", "檔案只含此地點的 ID、名稱、地址、類別、收藏時間與安全來源網址，不含私人筆記、來源敘述、照片、評分或造訪紀錄。儲存或分享位置由你選擇。"))
                        .font(.footnote)
                    Button(t("Export venue JSON", "匯出地點 JSON")) {
                        guard let data = CityMVPGuideExport.encode(brief) else { notice = t("This venue could not be exported within the file limit.", "此地點無法在檔案大小限制內匯出。"); return }
                        document = CityGuideDocument(data: data); showsExport = true
                    }.accessibilityIdentifier("cityMVP.guide.export")
                }
                if let notice { Text(notice).font(.footnote).accessibilityIdentifier("cityMVP.guide.notice") }
            }.padding(24).buttonStyle(.bordered)
        }
        .background(CityMVPFormStyle.canvas).navigationTitle("SAV-E Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button(t("Close", "關閉")) { dismiss() }.accessibilityIdentifier("cityMVP.guide.close")
        } }
        .accessibilityIdentifier("cityMVP.guide.brief")
        .sheet(isPresented: $showsDriver) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text("师傅，请带我去：").font(.headline)
                    Text(brief.address).font(.largeTitle.bold()).textSelection(.enabled)
                    Text(brief.name).font(.title2).textSelection(.enabled)
                    Text(brief.hasStreetNumber
                         ? t("Confirm this address and destination with the driver.", "請與司機確認地址與目的地。")
                         : t("No street number detected. Confirm the full address before taking a taxi.", "未找到街道門牌；搭車前請確認完整地址。"))
                        .foregroundStyle(.secondary)
                    Button(t("Copy address card", "複製地址卡")) { UIPasteboard.general.string = brief.driverCardText }
                        .accessibilityIdentifier("cityMVP.guide.copyDriverCard")
                    Spacer()
                }.padding(24)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Done", "完成")) { showsDriver = false } } }
            }
        }
        .fileExporter(isPresented: $showsExport, document: document, contentType: .json,
                      defaultFilename: "savvy-guide-\(brief.id.uuidString)") { result in
            switch result {
            case .success: notice = t("One venue exported.", "已匯出一個地點。")
            case .failure: notice = t("Export canceled or could not finish. Check the chosen destination before retrying.", "匯出已取消或無法完成，重試前請先檢查選擇的儲存位置。")
            }
        }
    }
    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).textSelection(.enabled) }
    }

    @ViewBuilder
    private var recommendationSources: some View {
        let sources = recommendations.recommendations(for: place)
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(t("Why it was recommended", "為什麼推薦這裡")).font(.headline)
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.senderLabel).font(.subheadline.bold())
                            .accessibilityIdentifier("cityMVP.guide.recommendation." + source.id)
                        Text(t("Sender label from a shared file · identity not verified", "分享檔中的寄件者稱呼 · 身分未驗證"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(source.reason).textSelection(.enabled)
                        Text(t("Shared", "分享時間") + " · " + source.sharedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                        if let url = CityMVPGuideBrief.safeSourceURL(source.sourceURL) {
                            Link(t("Open recommendation source", "開啟推薦來源"), destination: url)
                        }
                        Button {
                            do { try recommendations.forget(recordID: source.id) }
                            catch { notice = t("The recommendation could not be removed. Your saved place is unchanged.", "無法移除推薦說明；收藏地點未變更。") }
                        } label: {
                            Text(t("Forget this recommendation", "移除這筆推薦說明"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("cityMVP.guide.forgetRecommendation." + source.id)
                    }
                }
                Text(t("Copied recommendations stay separate from your private note and are excluded from venue-only AI exports.", "複製的推薦說明與你的私人筆記分開保存，不會包含在只匯出地點的 AI 檔案裡。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func t(_ en: String, _ zh: String) -> String { language.localized(english: en, traditionalChinese: zh) }
}

private nonisolated struct CityGuideDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= CityMVPGuideExport.maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@available(iOS 18.0, *)
private struct CityGuideTranslation: View {
    @Environment(\.appLanguageSettings) private var language
    @State private var original = ""
    @State private var translated: String?
    @State private var presentsTranslation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Translate Chinese source text", "翻譯中文來源文字")).font(.headline)
            Text(t("Paste source text, then choose English in Apple’s translation sheet. Apple may request a language download or report that translation is unavailable. Your original text stays here.", "貼上來源原文，再到 Apple 翻譯畫面選擇英文。Apple 可能要求下載語言，或顯示無法翻譯；原文會保留在這裡。"))
                .font(.footnote).foregroundStyle(.secondary)
            TextEditor(text: $original).frame(minHeight: 100)
                .accessibilityLabel(t("Original Chinese source text", "原始中文來源文字"))
                .accessibilityIdentifier("cityMVP.guide.translationInput")
            Button(t("Translate with Apple", "使用 Apple 翻譯")) {
                presentsTranslation = true
            }.disabled(original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || original.count > 4000)
                .accessibilityIdentifier("cityMVP.guide.translationStart")
            if original.count > 4000 { Text(t("Use up to 4,000 characters at a time.", "每次請使用最多 4,000 字。")) }
            if let translated { Text(t("Apple translation", "Apple 翻譯")).font(.headline); Text(translated).textSelection(.enabled) }
        }
        .translationPresentation(isPresented: $presentsTranslation, text: original,
                                 replacementAction: { translated = $0 })
        .onChange(of: original) { _, _ in translated = nil }
    }
    private func t(_ en: String, _ zh: String) -> String { language.localized(english: en, traditionalChinese: zh) }
}

#endif
