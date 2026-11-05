#if DEBUG
import SwiftUI

/// Explicit UI-suite launch only: isolated preferences, synthetic receipts and
/// in-memory save responses. No App Group journal or backend writes.
struct SaveIncomingShareFixtureRoot: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-incoming-share")
    }
    static let defaults: UserDefaults = {
        let name = "savvy.incoming-share.fixture"
        let store = UserDefaults(suiteName: name)!
        if ProcessInfo.processInfo.arguments.contains("--uitest-incoming-share-reset") {
            store.removePersistentDomain(forName: name)
        }
        return store
    }()
    private static var scenario: String {
        ProcessInfo.processInfo.environment["SAVE_INCOMING_SHARE_SCENARIO"] ?? "success"
    }
    @Binding var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @Binding var requiresShareConfirmation: Bool
    @Binding var requiresListConfirmation: Bool
    @Binding var pendingClipListSave: SaveCollaborativeList?
    @Binding var requestID: UUID
    let showParentAlert: () -> Void
    @StateObject private var language = AppLanguageSettings(userDefaults: Self.defaults, preferredLanguages: { ["en"] })
    @State private var verified = false
    @State private var prepared = false
    @State private var saves = 0
    @State private var resolutions = 0
    @State private var waiting: (CheckedContinuation<SharedPlaceSaveOutcome, Error>, SharedPlaceSaveOutcome)?
    private let session = SaveIncomingShareSession(owner: "fixture-account", generation: 1)

    var body: some View {
        Group {
            if verified {
                SaveInkNotebookRoot(launch: .preview(Self.scenario == "existing-modal" ? .passport : .main))
                    .modifier(SaveIncomingShareHost(
                        incomingPlaceReceipt: $incomingPlaceReceipt,
                        requiresShareConfirmation: $requiresShareConfirmation,
                        requiresListConfirmation: $requiresListConfirmation,
                        pendingClipListSave: $pendingClipListSave,
                        requestID: $requestID,
                        session: session,
                        currentSession: { verified ? session : nil },
                        journalStore: Self.defaults,
                        resolveReceipt: { url in
                            resolutions += 1
                            if Self.scenario == "retry", resolutions == 1 {
                                throw SharedPlaceReceiptError.networkUnavailable
                            }
                            return .embedded(Self.payload(second: url.lastPathComponent.hasSuffix("-b")))
                        },
                        recordReceiptEvent: { _, _, _ in },
                        saveReceipt: { receipt, _ in
                            saves += 1
                            if Self.scenario == "failure" { throw SharedPlaceReceiptError.networkUnavailable }
                            if Self.scenario == "cap" { throw SavePlaceLimitError.parkedInUnplacedInbox }
                            let place = receipt.recipientOwnedPlace(ownerSubject: session.owner)
                            if Self.scenario == "replacement", saves == 1 {
                                // J2 arrives while J1 is still saving, before its URL is opened.
                                writeJournal()
                                return try await withCheckedThrowingContinuation { continuation in
                                    waiting = (continuation, .saved(place))
                                    Task {
                                        try? await Task.sleep(for: .seconds(60))
                                        finishWaiting(cancel: true)
                                    }
                                }
                            }
                            return Self.scenario == "duplicate" ? .alreadySaved(place) : .saved(place)
                        },
                        saveList: { _ in
                            saves += 1
                            if Self.scenario == "list-cap" { throw SavePlaceLimitError.parkedInUnplacedInbox }
                            return ClipListHandoffCounts(newlySaved: 1, alreadySaved: 0, overCap: 0, remaining: 49, limit: 50)
                        }
                    ))
                    .safeAreaInset(edge: .top) {
                        VStack {
                            Text("Synthetic share fixture").font(SaveInkType.aux)
                            Text("Saves: \(saves)").accessibilityIdentifier("incoming.fixture.saves")
                            Text(PendingShareStore.load(from: Self.defaults) == nil ? "Journal: none" : "Journal: pending")
                                .accessibilityIdentifier("incoming.fixture.journal")
                            if Self.scenario == "existing-alert" {
                                Button("Show synthetic alert", action: showParentAlert)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("incoming.fixture.alert")
                            }
                        }
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.ink)
                        .background(SaveInkPalette.paper)
                    }
            } else {
                VStack(spacing: 20) {
                    Text("Account verification fixture").font(SaveInkType.sheetTitle)
                    SaveInkOutlineButton(title: "Verify fixture account", identifier: "incoming.fixture.verify") {
                        verified = true
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SaveInkPalette.paper)
            }
        }
        .environment(\.appLanguageSettings, language)
        .environment(\.locale, language.locale)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            language.language = ProcessInfo.processInfo.arguments.contains("--uitest-incoming-share-zh") ? .traditionalChinese : .english
            if ["clip", "replacement", "failure", "cap", "list", "list-cap"].contains(Self.scenario) { writeJournal() }
            if Self.scenario.hasPrefix("list") {
                let snapshot = Self.snapshot
                pendingClipListSave = SaveCollaborativeList(title: "Synthetic list", items: [snapshot.asListItem()])
                requiresListConfirmation = true
                requestID = UUID()
            }
            verified = !ProcessInfo.processInfo.arguments.contains("--uitest-incoming-share-unverified")
        }
        .onChange(of: requestID) { _, _ in finishWaiting(cancel: false) }
        .onDisappear { finishWaiting(cancel: true) }
    }

    private func finishWaiting(cancel: Bool) {
        guard let pending = waiting else { return }
        waiting = nil
        if cancel { pending.0.resume(throwing: CancellationError()) }
        else { pending.0.resume(returning: pending.1) }
    }

    private func writeJournal() {
        let list = Self.scenario.hasPrefix("list")
        _ = PendingShareStore.write(PendingSharePayload(
            kind: list ? .list : .place, shareCode: list ? nil : "share-fixture",
            placeId: nil, listId: nil, sender: nil,
            url: list ? "savvy://list/fixture" : "savvy://p/share-fixture",
            confirmedPlaces: [Self.snapshot]
        ), to: Self.defaults)
    }

    private static var snapshot: PendingConfirmedPlace {
        PendingConfirmedPlace(
            placeId: "fixture-place-a", name: "Fixture place A", address: "Synthetic address",
            latitude: 25.033, longitude: 121.5654, category: "cafe", sourceURL: nil
        )
    }

    private static func payload(second: Bool) -> SharedPlaceData {
        SharedPlaceData(
            id: second ? "fixture-b" : "fixture-a", name: second ? "Fixture place B" : "Fixture place A",
            address: "Synthetic address", lat: 25.033, lng: 121.5654, category: "cafe",
            rating: nil, reviewCount: nil, priceRange: nil, hours: nil,
            sourceLabel: "Synthetic source", sourceURL: nil, photoURLs: [], note: "Consented fixture share note"
        )
    }
}
#endif
