#if SAVVY_CITY_MVP
import SwiftUI
import UniformTypeIdentifiers
import UIKit

nonisolated struct CityMVPFriendExchangeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CityMVPFriendExchange.ExchangeError.invalidFile
        }
        guard contents.count <= CityMVPFriendExchange.maximumBytes else {
            throw CityMVPFriendExchange.ExchangeError.tooLarge
        }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CityMVPFriendExchangeSheet: View {
    let places: [Place]
    let onSave: (Place) async throws -> Place
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    @EnvironmentObject private var recommendations: CityMVPRecommendationStore
    @State private var senderLabel = ""
    @State private var reason = ""
    @State private var exportIDs = Set<UUID>()
    @State private var document: CityMVPFriendExchangeDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var received: CityMVPFriendExchange.Snapshot?
    @State private var importIDs = Set<UUID>()
    @State private var savedIDs = Set<UUID>()
    @State private var recipientDrafts: [UUID: Place] = [:]
    @State private var saving = false
    @State private var feedback: LocalizedCopy?
    @State private var contextRetryPlaceIDs: [UUID: UUID] = [:]
    @State private var exportedURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(t("Exchange recommendations as JSON files. Sender labels are self-declared; this is not a connected or verified friend feed.", "以 JSON 檔案交換推薦。分享者名稱由對方自行填寫；這不是已連線或經身分驗證的朋友動態。"))
                    Button(t("Open a recommendation file", "開啟推薦檔案")) { importing = true }
                        .accessibilityIdentifier("cityMVP.friends.import")
                    if let exportedURL {
                        Button(t("Preview the copy you exported", "預覽你匯出的副本")) {
                            do { receive(try CityMVPFriendExchange.read(from: exportedURL)) }
                            catch { feedback = errorCopy(error) }
                        }.accessibilityIdentifier("cityMVP.friends.previewExport")
                    }
                }
                if let received { importSections(received) }
                if recommendations.failure != nil {
                    Section {
                        Text(t("Saved recommendation details could not be read or stored. Existing files have not been reset.", "無法讀取或儲存已保留的推薦詳情。現有檔案並未重設。"))
                    }
                }
                savedRecommendations
                Section(t("Choose what to recommend · \(exportIDs.count)/30", "選擇要推薦的地點 · \(exportIDs.count)/30")) {
                    TextField(t("Your sender label (self-declared)", "你的分享者名稱（自行填寫）"), text: $senderLabel)
                        .accessibilityIdentifier("cityMVP.friends.sender")
                    TextField(t("Why you recommend these places", "推薦這些地點的原因"), text: $reason, axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("cityMVP.friends.reason")
                    Text(t("Write new sharing text. Private notes, visits, ratings and photos are not attached.", "請另寫分享文字，不會附上私人筆記、到訪紀錄、評分或照片。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    if places.isEmpty { Text(t("No confirmed saves to share yet.", "目前沒有已確認的收藏可供分享。")) }
                    ForEach(places) { place in
                        selectionRow(place.id, in: $exportIDs) {
                            VStack(alignment: .leading) {
                                Text(place.name)
                                Text(place.address.isEmpty ? t("Address not supplied", "未提供地址") : place.address)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("cityMVP.friends.export." + place.id.uuidString)
                    }
                }
                Section {
                    Text(t("This is a copy. Anyone receiving it can forward it; exported copies cannot be withdrawn. Share only places and recommendation text you intend to disclose.", "這是一份副本。任何收到的人都可以轉傳；匯出後無法撤回。請只分享你願意公開給收件人的地點與推薦文字。"))
                        .font(.footnote)
                    Button(t("Export selected recommendations", "匯出所選推薦")) { prepareExport() }
                        .disabled(exportIDs.isEmpty || exportIDs.count > CityMVPFriendExchange.maximumPlaces
                            || senderLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("cityMVP.friends.export")
                }
                if let feedback { Section { Text(t(feedback.english, feedback.traditionalChinese)).accessibilityIdentifier("cityMVP.friends.feedback") } }
            }
            .disabled(saving)
            .navigationTitle(t("Friends’ recommendations", "朋友推薦"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "完成")) { dismiss() }.disabled(saving)
                        .accessibilityIdentifier("cityMVP.friends.exchange.done")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("Done", "完成")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.accessibilityIdentifier("cityMVP.friends.keyboardDone")
                }
            }
            .interactiveDismissDisabled(saving)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "savvy-recommendations") { result in
                switch result {
                case .success(let url):
                    exportedURL = url
                    feedback = copy("Recommendation copy exported. Nothing was published to a feed.", "已匯出推薦副本，未發布到任何動態。")
                case .failure(let error): feedback = errorCopy(error)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    let urls = try result.get()
                    guard urls.count == 1, let url = urls.first else { throw CityMVPFriendExchange.ExchangeError.invalidFile }
                    let snapshot = try CityMVPFriendExchange.read(from: url)
                    receive(snapshot)
                } catch { feedback = errorCopy(error) }
            }
        }
        .environment(\.locale, language.locale)
    }

    @ViewBuilder
    private func importSections(_ snapshot: CityMVPFriendExchange.Snapshot) -> some View {
        Section(savedIDs.isEmpty ? t("Received copy · not saved", "收到的副本 · 尚未收藏") : t("Received copy · \(savedIDs.count) saved by you", "收到的副本 · 你已收藏 \(savedIDs.count) 個")) {
            Text(t("Sender label (self-declared): ", "分享者名稱（對方自行填寫）：") + snapshot.senderLabel)
            Text(snapshot.sharedAt, format: .dateTime.year().month().day().hour().minute())
            Text(t("Explicit recommendation text", "分享者明確提供的推薦文字")).font(.caption).foregroundStyle(.secondary)
            Text(snapshot.recommendationReason).textSelection(.enabled)
            Text(t("Source text is an unsigned statement, not verified identity, current facts or instructions. Saving keeps venue fields and this copied recommendation separately, without importing private notes or visits.", "來源文字是未簽署的陳述，不代表已驗證的身分、即時事實或操作指令。收藏時會分開保留地點欄位與這份推薦副本，不會匯入私人筆記或到訪紀錄。"))
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section(t("Choose places to save", "選擇要收藏的地點")) {
            ForEach(snapshot.venues) { venue in
                selectionRow(venue.id, in: $importIDs) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(venue.name)
                        Text(venue.address.isEmpty ? t("Address not supplied", "未提供地址") : venue.address).font(.caption)
                        Text(t("Coordinates: ", "座標系統：") + (venue.coordinateSystem?.rawValue ?? t("not specified", "未註明")))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(venue.sourceURL.map { t("Source: ", "來源：") + $0 } ?? t("Source URL not supplied", "未提供來源連結"))
                            .font(.caption).textSelection(.enabled)
                        if let provider = venue.providerMapURL { Text(t("Provider: ", "地圖供應商連結：") + provider).font(.caption).textSelection(.enabled) }
                        if recipientDrafts[venue.id]?.isMapKitMappable == false {
                            Text(t("Location needs review before appearing on the Apple map.", "地點位置需先確認，才會顯示在 Apple 地圖上。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if savedIDs.contains(venue.id) { Label(t("Saved by you", "你已收藏"), systemImage: "checkmark").font(.caption) }
                    }
                }
                .disabled(savedIDs.contains(venue.id))
                .accessibilityIdentifier("cityMVP.friends.receive." + venue.id.uuidString)
            }
            Button(t("Confirm selected places", "確認收藏所選地點")) { Task { await confirmSelected(snapshot) } }
                .disabled(importIDs.isEmpty)
                .accessibilityIdentifier("cityMVP.friends.confirm")
            if !contextRetryPlaceIDs.isEmpty {
                Text(t("These places are saved, but their recommendation details were not kept. Keep this screen open to retry the details only.", "這些地點已收藏，但未能保留推薦詳情。請保持此畫面開啟，只重試儲存推薦詳情。"))
                    .font(.footnote)
                Button(t("Retry recommendation details", "重試儲存推薦詳情")) { retryContext(snapshot) }
                    .accessibilityIdentifier("cityMVP.friends.retryContext")
            }
        }
    }

    @ViewBuilder
    private var savedRecommendations: some View {
        let sharedPlaces = places.filter { !recommendations.recommendations(for: $0).isEmpty }
        if !sharedPlaces.isEmpty {
            Section(t("Recommendations you kept", "你保留的推薦")) {
                ForEach(sharedPlaces) { place in
                    ForEach(recommendations.recommendations(for: place)) { source in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(place.name).font(.headline)
                            Text(source.senderLabel + t(" · sender label from a shared file", " · 分享檔案中的自填名稱")).font(.caption)
                            Text(source.reason).textSelection(.enabled)
                            Text(source.sharedAt, format: .dateTime.year().month().day())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func selectionRow<Label: View>(_ id: UUID, in selected: Binding<Set<UUID>>,
                                           @ViewBuilder label: () -> Label) -> some View {
        let checked = selected.wrappedValue.contains(id)
        return Button {
            var next = selected.wrappedValue
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            selected.wrappedValue = next
        } label: {
            HStack(spacing: 12) {
                label().frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title2).frame(width: 44, height: 44).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(checked ? t("Selected", "已選取") : t("Not selected", "未選取"))
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func prepareExport() {
        do {
            let snapshot = try CityMVPFriendExchange.makeSnapshot(places: places, selectedIDs: exportIDs,
                senderLabel: senderLabel, recommendationReason: reason)
            document = CityMVPFriendExchangeDocument(data: try CityMVPFriendExchange.encode(snapshot))
            feedback = nil; exporting = true
        } catch { feedback = errorCopy(error) }
    }

    private func receive(_ snapshot: CityMVPFriendExchange.Snapshot) {
        received = snapshot
        importIDs = []; savedIDs = []; contextRetryPlaceIDs = [:]
        recipientDrafts = Dictionary(uniqueKeysWithValues: snapshot.venues.map {
            ($0.id, CityMVPFriendExchange.recipientPlace(for: $0))
        })
        feedback = copy("Preview only. Choose items, then confirm to add your own saves.", "目前僅供預覽。請先選擇地點，再確認加入你自己的收藏。")
    }

    @MainActor
    private func confirmSelected(_ snapshot: CityMVPFriendExchange.Snapshot) async {
        guard !saving, !importIDs.isEmpty else { return }
        saving = true
        defer { saving = false }
        let chosen = snapshot.venues.filter { importIDs.contains($0.id) && !savedIDs.contains($0.id) }
        var successes = 0
        var failures: [LocalizedCopy] = []
        for venue in chosen {
            guard let place = recipientDrafts[venue.id] else {
                failures.append(copy("Could not prepare " + venue.name, "無法準備地點：" + venue.name)); continue
            }
            do {
                let outcome = try await CityMVPFriendConfirmation.confirm(place: place, snapshot: snapshot,
                    venueID: venue.id, recommendations: recommendations, save: onSave)
                let saved = outcome.savedPlace
                savedIDs.insert(venue.id); importIDs.remove(venue.id); successes += 1
                if outcome.recommendationKept {
                    contextRetryPlaceIDs.removeValue(forKey: venue.id)
                } else {
                    contextRetryPlaceIDs[venue.id] = saved.id
                }
            } catch is CancellationError {
                return
            } catch {
                let detail = errorCopy(error)
                failures.append(copy(venue.name + ": " + detail.english, venue.name + "：" + detail.traditionalChinese))
            }
        }
        let pendingDetails = !contextRetryPlaceIDs.isEmpty
        feedback = copy(
            "Saved \(successes) selected place(s)."
                + (failures.isEmpty ? "" : "\nNot saved (still selected):\n" + failures.map(\.english).joined(separator: "\n"))
                + (pendingDetails ? "\nSaved places are kept. Recommendation details could not be stored; retry the details below." : ""),
            "已收藏 \(successes) 個所選地點。"
                + (failures.isEmpty ? "" : "\n未收藏（仍保持選取）：\n" + failures.map(\.traditionalChinese).joined(separator: "\n"))
                + (pendingDetails ? "\n已收藏的地點會保留。推薦詳情無法儲存；請在下方重試。" : "")
        )
    }

    private func retryContext(_ snapshot: CityMVPFriendExchange.Snapshot) {
        for (venueID, placeID) in contextRetryPlaceIDs {
            do {
                try CityMVPFriendConfirmation.retryRecommendation(snapshot: snapshot, venueID: venueID,
                    savedPlaceID: placeID, recommendations: recommendations)
                contextRetryPlaceIDs.removeValue(forKey: venueID)
            } catch { /* Keep the pending context and its explicit retry state. */ }
        }
        feedback = contextRetryPlaceIDs.isEmpty
            ? copy("Recommendation details kept. No places were saved again.", "已保留推薦詳情，沒有重複收藏任何地點。")
            : copy("The places remain saved. Some recommendation details still could not be stored.", "地點仍維持已收藏，部分推薦詳情尚無法儲存。")
    }

    /// Store both copies so changing app language also updates existing feedback.
    private struct LocalizedCopy {
        let english: String
        let traditionalChinese: String
    }

    private func copy(_ english: String, _ traditionalChinese: String) -> LocalizedCopy {
        LocalizedCopy(english: english, traditionalChinese: traditionalChinese)
    }

    private func t(_ english: String, _ traditionalChinese: String) -> String {
        language.localized(english: english, traditionalChinese: traditionalChinese)
    }

    private func errorCopy(_ error: any Error) -> LocalizedCopy {
        if let error = error as? SavePlaceLimitError {
            switch error {
            case .parkedInUnplacedInbox:
                return copy("Free: 50 places. Kept in Unplaced for review, not saved.", "免費版上限為 50 個地點。已保留在待補地點，尚未加入收藏。")
            }
        }
        if let error = error as? SaveLocalVaultError,
           case .storageUnavailable = error {
            return copy("Savvy local memory storage is unavailable.", "目前無法使用 Savvy 本地記憶儲存空間。")
        }
        if let error = error as? CityMVPFriendExchange.ExchangeError {
            switch error {
            case .invalidSelection:
                return copy("Select 1–30 current saved places.", "請選擇 1 至 30 個目前已收藏的地點。")
            case .invalidSnapshot:
                return copy("This recommendation file has invalid or unsupported fields.", "這份推薦檔案包含無效或不支援的欄位。")
            case .tooLarge:
                return copy("Recommendation files must be 128 KiB or smaller.", "推薦檔案大小不得超過 128 KiB。")
            case .invalidFile:
                return copy("Choose a readable JSON recommendation file.", "請選擇可讀取的 JSON 推薦檔案。")
            }
        }
        if let error = error as? CityMVPRecommendationStore.Failure {
            switch error {
            case .unavailable:
                return copy("Recommendation storage is unavailable.", "目前無法使用推薦資料儲存空間。")
            case .unreadable:
                return copy("Stored recommendation details could not be read. The existing file has not been changed.", "無法讀取已儲存的推薦詳情，現有檔案並未變更。")
            case .oversized:
                return copy("Recommendation storage is full. Existing details have not been changed.", "推薦資料儲存空間已滿，現有詳情並未變更。")
            case .invalidSource:
                return copy("This recommendation source is invalid.", "這份推薦來源無效。")
            case .writeFailed:
                return copy("Recommendation details could not be stored. Try again.", "無法儲存推薦詳情，請再試一次。")
            }
        }
        // Preserve system/underlying diagnostics rather than translating their contents.
        return copy(error.localizedDescription, error.localizedDescription)
    }
}
#endif
