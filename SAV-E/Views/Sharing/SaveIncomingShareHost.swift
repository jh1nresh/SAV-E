import SwiftUI

struct SaveIncomingShareSession: Equatable {
    let owner: String
    let generation: Int

    func accepts(_ current: Self?) -> Bool {
        !owner.isEmpty && current == self
    }
}

private enum SaveIncomingSharePresentation: Identifiable {
    case place(SharedPlaceReceiptDestination, PendingSharePayload?, UUID, SaveIncomingShareSession)
    case list(SaveCollaborativeList, PendingSharePayload?, UUID, SaveIncomingShareSession)

    var id: UUID {
        switch self {
        case .place(_, _, let id, _), .list(_, _, let id, _): return id
        }
    }
}

extension Notification.Name {
    static let saveInkIncomingShareSaved = Notification.Name("saveInkIncomingShareSaved")
}

/// The verified root owns presentation; persistence retains its existing
/// server, account, deduplication and saved-place-limit checks.
@MainActor
struct SaveIncomingShareHost: ViewModifier {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Binding var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @Binding var requiresShareConfirmation: Bool
    @Binding var requiresListConfirmation: Bool
    @Binding var pendingClipListSave: SaveCollaborativeList?
    @Binding var requestID: UUID
    let session: SaveIncomingShareSession
    let currentSession: () -> SaveIncomingShareSession?
    var journalStore: UserDefaults?
    var resolveReceipt: ((URL) async throws -> SharedPlaceReceipt)?
    var recordReceiptEvent: ((String, FriendShareReceiptEvent, FriendShareOpenFailureReason?) async -> Void)?
    var saveReceipt: ((SharedPlaceReceipt, PendingSharePayload?) async throws -> SharedPlaceSaveOutcome)?
    var saveList: ((SaveCollaborativeList) async throws -> ClipListHandoffCounts)?
    // Receipt previews and injected fixtures do not initialize persistence.
    @State private var persistence: MapViewModel?
    @State private var presentation: SaveIncomingSharePresentation?
    @State private var isActive = false
    @State private var completionMessage: String?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if presentation == nil {
                    if requiresListConfirmation, pendingClipListSave != nil {
                        SaveInkOutlineButton(
                            title: localized("Review pending shared places", "查看待確認的分享地點"),
                            identifier: "app.handoff.reviewList", compact: true
                        ) { presentPendingShare() }
                        .padding(12)
                        .background(SaveInkPalette.paper)
                    }
                    if let completionMessage {
                        HStack {
                            Text(completionMessage)
                                .font(SaveInkType.aux)
                                .accessibilityIdentifier("app.handoff.confirmationMessage")
                            SaveInkCircleButton(
                                label: "×", identifier: "app.handoff.dismissMessage",
                                spoken: localized("Dismiss confirmation", "關閉確認訊息")
                            ) { self.completionMessage = nil }
                        }
                        .foregroundStyle(SaveInkPalette.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(SaveInkPalette.paper)
                    }
                    }
                }
            }
            .sheet(item: presentationBinding) { item in
                switch item {
                case .place(let destination, let journal, let token, let owner):
                    FriendShareReceiptView(destination: destination, resolveReceipt: resolveReceipt, recordEvent: recordReceiptEvent) { receipt in
                        try await confirmPlace(receipt, destination: destination, journal: journal, token: token, owner: owner)
                    }
                    .id(item.id)
                case .list(let list, let journal, let token, let owner):
                    SaveIncomingListConfirmation(
                        list: list,
                        save: { try await confirmList(list, journal: journal, token: token, owner: owner) },
                        completed: { counts in finishList(list, journal: journal, token: token, owner: owner, counts: counts) }
                    )
                    .id(item.id)
                }
            }
            .onAppear {
                isActive = true
                presentPendingShare()
            }
            .onDisappear {
                isActive = false
                presentation = nil
            }
            .onChange(of: requestID) { _, _ in
                completionMessage = nil
                presentPendingShare()
            }
            .onChange(of: incomingPlaceReceipt?.id) { _, _ in presentPendingShare() }
            .onChange(of: pendingClipListSave) { _, _ in presentPendingShare() }
            .onChange(of: session) { _, _ in
                completionMessage = nil
                presentPendingShare()
            }
    }

    private var presentationBinding: Binding<SaveIncomingSharePresentation?> {
        Binding(
            get: { presentation },
            set: { next in
                if next == nil, let previous = presentation,
                   case .place(let destination, _, let token, _) = previous,
                   token == requestID, incomingPlaceReceipt?.id == destination.id {
                    incomingPlaceReceipt = nil
                }
                presentation = next
            }
        )
    }

    private func presentPendingShare() {
        guard isActive, session.accepts(currentSession()) else {
            presentation = nil
            return
        }
        let journal = PendingShareStore.load(from: journalStore)
        if let destination = incomingPlaceReceipt {
            presentation = .place(destination, journal, requestID, session)
        } else if requiresListConfirmation, let list = pendingClipListSave {
            presentation = .list(list, journal, requestID, session)
        } else {
            presentation = nil
        }
    }

    private func requireCurrent(_ token: UUID, owner: SaveIncomingShareSession) throws {
        try Task.checkCancellation()
        guard isActive, token == requestID, owner.accepts(currentSession()) else {
            throw CancellationError()
        }
    }

    private func confirmPlace(
        _ receipt: SharedPlaceReceipt, destination: SharedPlaceReceiptDestination,
        journal: PendingSharePayload?, token: UUID, owner: SaveIncomingShareSession
    ) async throws -> SharedPlaceSaveOutcome {
        try requireCurrent(token, owner: owner)
        guard incomingPlaceReceipt?.id == destination.id else { throw CancellationError() }
        let confirmsClip = requiresShareConfirmation
        let selectedJournal = ClipPlaceHandoff.journalForConfirmation(pending: journal, destination: destination)
        if confirmsClip {
            guard selectedJournal != nil, PendingShareStore.load(from: journalStore) == selectedJournal else { throw CancellationError() }
        }
        let outcome: SharedPlaceSaveOutcome
        if let saveReceipt {
            outcome = try await saveReceipt(receipt, selectedJournal)
        } else {
            outcome = try await saver().saveSharedPlaceReceipt(
                receipt, requiringAuthenticatedSession: true, confirmedJournal: selectedJournal
            )
        }
        NotificationCenter.default.post(name: .saveInkIncomingShareSaved, object: nil)
        try requireCurrent(token, owner: owner)
        guard incomingPlaceReceipt?.id == destination.id else { throw CancellationError() }
        if confirmsClip, PendingShareStore.clear(ifUnchanged: selectedJournal, from: journalStore) {
            requiresShareConfirmation = false
        }
        return outcome
    }

    private func confirmList(
        _ list: SaveCollaborativeList, journal: PendingSharePayload?,
        token: UUID, owner: SaveIncomingShareSession
    ) async throws -> ClipListHandoffCounts {
        try requireCurrent(token, owner: owner)
        guard requiresListConfirmation, pendingClipListSave == list,
              PendingShareStore.load(from: journalStore) == journal,
              ClipListHandoff.matchesPendingSelection(list, pending: journal) else { throw CancellationError() }
        let counts: ClipListHandoffCounts
        if let saveList {
            counts = try await saveList(list)
        } else {
            counts = try await saver().saveClipListHandoff(list, requiringAuthenticatedSession: true).counts
        }
        NotificationCenter.default.post(name: .saveInkIncomingShareSaved, object: nil)
        try requireCurrent(token, owner: owner)
        guard pendingClipListSave == list, PendingShareStore.load(from: journalStore) == journal else { throw CancellationError() }
        return counts
    }

    private func finishList(
        _ list: SaveCollaborativeList, journal: PendingSharePayload?, token: UUID,
        owner: SaveIncomingShareSession, counts: ClipListHandoffCounts
    ) {
        do { try requireCurrent(token, owner: owner) } catch { return }
        guard pendingClipListSave == list, PendingShareStore.load(from: journalStore) == journal else { return }
        completionMessage = localized(
            ClipListHandoff.toastEnglish(counts: counts, confirmedCount: list.items.count),
            ClipListHandoff.toastTraditionalChinese(counts: counts, confirmedCount: list.items.count)
        )
        if counts.overCap == 0, PendingShareStore.clear(ifUnchanged: journal, from: journalStore) {
            requiresListConfirmation = false
            pendingClipListSave = nil
            presentation = nil
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }

    private func saver() -> MapViewModel {
        if let persistence { return persistence }
        let model = MapViewModel()
        persistence = model
        return model
    }
}

private struct SaveIncomingListConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    let list: SaveCollaborativeList
    let save: () async throws -> ClipListHandoffCounts
    let completed: (ClipListHandoffCounts) -> Void
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(localized("These places are pending. Confirm to save them to this account. Places over your limit stay pending.", "這些地點尚未收藏。確認後才會存入目前帳號；超過收藏上限的地點仍保留待辦。"))
                    ForEach(list.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(SaveInkType.shop)
                            Text(item.subtitle).foregroundStyle(SaveInkPalette.inkSub)
                        }
                    }
                    if let message {
                        Text(message).accessibilityIdentifier("app.handoff.confirmationMessage")
                    }
                    SaveInkOutlineButton(
                        title: localized(isSaving ? "Saving…" : "Confirm save", isSaving ? "儲存中…" : "確認收藏"),
                        identifier: "app.handoff.confirmList", compact: true
                    ) { Task { await confirm() } }
                    .disabled(isSaving)
                }
                .padding(24)
            }
            .font(SaveInkType.body)
            .foregroundStyle(SaveInkPalette.ink)
            .background(SaveInkPalette.paper.ignoresSafeArea())
            .navigationTitle(localized("Pending places", "待收藏地點"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(localized("Pending places", "待收藏地點")).font(SaveInkType.subpageTitle)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Later", "稍後")) { dismiss() }
                        .font(SaveInkType.secondaryButton)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isSaving)
                }
            }
        }
        .tint(SaveInkPalette.ink)
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func confirm() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let counts = try await save()
            message = localized(
                ClipListHandoff.toastEnglish(counts: counts, confirmedCount: list.items.count),
                ClipListHandoff.toastTraditionalChinese(counts: counts, confirmedCount: list.items.count)
            )
            completed(counts)
        } catch is CancellationError {
            return
        } catch {
            message = error is SavePlaceLimitError
                ? localized("Your saved-place limit has been reached. These places stay pending.", "已達收藏地點上限，這些地點仍保留待辦。")
                : localized("Couldn't save these places. Try again.", "地點沒有存好，請再試一次。")
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}
