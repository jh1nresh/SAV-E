import SwiftUI

struct FriendShareReceiptView: View {
    private enum LoadState {
        case loading
        case loaded(SharedPlaceReceipt)
        case failed(SharedPlaceReceiptError)
    }

    private enum SaveState {
        case idle
        case saving
        case saved
        case alreadySaved
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.appLanguageSettings) private var languageSettings
    let destination: SharedPlaceReceiptDestination
    let resolveReceipt: (URL) async throws -> SharedPlaceReceipt
    let recordEvent: (String, FriendShareReceiptEvent, FriendShareOpenFailureReason?) async -> Void
    let onSave: (SharedPlaceReceipt) async throws -> SharedPlaceSaveOutcome
    @State private var loadState: LoadState = .loading
    @State private var saveState: SaveState = .idle
    @State private var saveErrorMessage: String?
    @State private var retryCount = 0
    @State private var activeLoadID: UUID?
    @State private var activeSaveID: UUID?

    init(
        destination: SharedPlaceReceiptDestination,
        resolveReceipt: ((URL) async throws -> SharedPlaceReceipt)? = nil,
        recordEvent: ((String, FriendShareReceiptEvent, FriendShareOpenFailureReason?) async -> Void)? = nil,
        onSave: @escaping (SharedPlaceReceipt) async throws -> SharedPlaceSaveOutcome
    ) {
        self.destination = destination
        self.resolveReceipt = resolveReceipt ?? { try await SharedPlaceReceipt.resolve(from: $0) }
        self.recordEvent = recordEvent ?? { code, event, reason in
            try? await SupabaseService.shared.recordFriendShareEvent(code: code, event: event, failureReason: reason)
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    loadingView
                case .loaded(let receipt):
                    receiptView(receipt)
                case .failed(let error):
                    errorView(error)
                }
            }
            .navigationTitle(localized("Shared place", "好友分享"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("Done", "完成")) { dismiss() }
                        .font(SaveInkType.secondaryButton)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(saveState == .saving)
                }
                ToolbarItem(placement: .principal) {
                    Text(localized("Shared place", "好友分享")).font(SaveInkType.subpageTitle)
                }
            }
        }
        .font(SaveInkType.body)
        .foregroundStyle(SaveInkPalette.ink)
        .tint(SaveInkPalette.ink)
        .task(id: "\(destination.id):\(retryCount)") {
            await loadReceipt()
        }
        .onDisappear {
            activeLoadID = nil
            activeSaveID = nil
        }
        .interactiveDismissDisabled(saveState == .saving)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(localized("Checking this Savvy link", "正在檢查這個 Savvy 連結"))
                .font(SaveInkType.sheetTitle)
            Text(localized(
                "Verifying the sender and place before showing a save action.",
                "正在確認分享者與地點，再顯示儲存動作。"
            ))
            .foregroundStyle(SaveInkPalette.inkSub)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friendShareReceipt.loading")
    }

    private func errorView(_ error: SharedPlaceReceiptError) -> some View {
        VStack(spacing: 20) {
            Text(localized("Could not open this place", "無法打開這個地點"))
                .font(SaveInkType.sheetTitle)
            Text(localized(error.errorDescription ?? "The link is unavailable.", errorMessage(error)))
                .foregroundStyle(SaveInkPalette.inkSub)
            if case .shortLink = destination {
                SaveInkOutlineButton(title: localized("Try Again", "再試一次"), identifier: "friendShareReceipt.retry", compact: true) {
                    retryCount += 1
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friendShareReceipt.unavailable")
    }

    private func receiptView(_ receipt: SharedPlaceReceipt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if let sender = receipt.verifiedSenderLabel {
                        Label(localized("Shared by \(sender)", "由 \(sender) 分享"), systemImage: "person.crop.circle")
                            .font(SaveInkType.body)
                            .foregroundStyle(SaveInkPalette.ink)
                            .accessibilityIdentifier("friendShareReceipt.sender")
                    } else {
                        Label(localized("Shared place", "分享的地點"), systemImage: "square.and.arrow.down")
                            .font(SaveInkType.body)
                            .foregroundStyle(SaveInkPalette.inkSub)
                    }

                    Text(receipt.payload.name)
                        .font(SaveInkType.pageTitle)
                        .foregroundStyle(SaveInkPalette.ink)

                    if !receipt.payload.address.isEmpty {
                        Text(receipt.payload.address)
                            .font(SaveInkType.body)
                            .foregroundStyle(SaveInkPalette.inkSub)
                    }

                    Text(receipt.payload.category)
                        .font(SaveInkType.aux)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SaveInkPalette.unverifiedFill, in: Capsule())
                }

                if let note = receipt.payload.note, !note.isEmpty {
                    receiptSection(
                        title: friendShareNoteTitle(receipt),
                        value: note,
                        icon: "quote.bubble"
                    )
                    .accessibilityIdentifier("friendShareReceipt.note")
                }

                receiptSection(
                    title: localized("Original source", "原始來源"),
                    value: receipt.payload.sourceLabel,
                    icon: "link"
                )

                if let sourceURL = receipt.payload.safeSourceURL {
                    Link(destination: sourceURL) {
                        Label(localized("Open original source", "打開原始來源"), systemImage: "arrow.up.right.square")
                    }
                    .font(SaveInkType.body)
                }

                if receipt.verifiedSenderLabel != nil {
                    Label(
                        localized("Share record verified by Savvy. Saving stays private.", "分享紀錄已由 Savvy 驗證；儲存後仍是私人記憶。"),
                        systemImage: "checkmark.shield"
                    )
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                }

                VStack(spacing: 12) {
                    SaveInkOutlineButton(title: saveButtonTitle, identifier: "friendShareReceipt.save", compact: true) {
                        Task { await save(receipt) }
                    }
                    .disabled(saveState != .idle)

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(SaveInkType.aux)
                            .foregroundStyle(SaveInkPalette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("friendShareReceipt.saveError")
                    }

                    if let mapsURL = receipt.payload.appleMapsURL {
                        SaveInkOutlineButton(title: localized("Open in Maps", "在地圖中打開"), identifier: "friendShareReceipt.openMaps", compact: true) {
                            openURL(mapsURL)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(SaveInkPalette.paper.ignoresSafeArea())
    }

    private func receiptSection(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
            Text(value)
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SaveInkPalette.card, in: SaveInkRoughRoundedRect(cornerRadius: 16, seed: 151))
    }

    private var saveButtonTitle: String {
        switch saveState {
        case .idle: return localized("Save to my Savvy", "存到我的 Savvy")
        case .saving: return localized("Saving…", "儲存中…")
        case .saved: return localized("Saved privately", "已私人儲存")
        case .alreadySaved: return localized("Already saved", "已經存過")
        }
    }

    @MainActor
    private func loadReceipt() async {
        let loadID = UUID()
        let expectedDestination = destination
        activeLoadID = loadID
        activeSaveID = nil
        saveState = .idle
        saveErrorMessage = nil
        switch expectedDestination {
        case .embedded(let payload):
            guard activeLoadID == loadID else { return }
            loadState = .loaded(.embedded(payload))
        case .malformed:
            guard activeLoadID == loadID else { return }
            loadState = .failed(.malformedLink)
        case .shortLink(let url):
            loadState = .loading
            do {
                let receipt = try await resolveReceipt(url)
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .loaded(receipt)
                if let code = receipt.code {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    await recordEvent(code, .receiptOpened, nil)
                }
            } catch is CancellationError {
                return
            } catch let error as SharedPlaceReceiptError {
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .failed(error)
                if let code = SharedPlaceData.shortCode(from: url) {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    await recordEvent(code, .openFailed, error.eventFailureReason)
                }
            } catch {
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .failed(.invalidResponse)
                if let code = SharedPlaceData.shortCode(from: url) {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    await recordEvent(code, .openFailed, .unknown)
                }
            }
        }
    }

    @MainActor
    private func save(_ receipt: SharedPlaceReceipt) async {
        guard saveState == .idle,
              case .loaded(let currentReceipt) = loadState,
              currentReceipt.id == receipt.id
        else { return }
        let saveID = UUID()
        activeSaveID = saveID
        saveState = .saving
        saveErrorMessage = nil
        do {
            let outcome = try await onSave(receipt)
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = outcome.isDuplicate ? .alreadySaved : .saved
        } catch is SavePlaceLimitError {
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = .idle
            saveErrorMessage = localized(
                "Your saved-place limit has been reached. This place stays pending.",
                "已達收藏地點上限，這個地點仍保留待辦。"
            )
        } catch {
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = .idle
            saveErrorMessage = localized(
                "Couldn't save this verified share. It may have expired; refresh the receipt and try again.",
                "無法儲存這張已驗證的分享。連結可能已過期；請重新載入收據後再試。"
            )
        }
    }

    private func friendShareNoteTitle(_ receipt: SharedPlaceReceipt) -> String {
        let copy = FriendShareNoteCopy.title(sender: receipt.verifiedSenderLabel)
        return localized(copy.english, copy.traditionalChinese)
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }

    private func errorMessage(_ error: SharedPlaceReceiptError) -> String {
        switch error {
        case .malformedLink: return "這個分享連結格式不正確。"
        case .missingAPIConfiguration: return "Savvy 尚未設定好這個分享服務。"
        case .networkUnavailable: return "請檢查網路後再試一次。"
        case .missingOrExpired: return "這個分享連結不存在或已過期。"
        case .serverUnavailable: return "分享收據暫時無法使用。"
        case .invalidResponse: return "Savvy 無法驗證這張分享收據。"
        }
    }
}
