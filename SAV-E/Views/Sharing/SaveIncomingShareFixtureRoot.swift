#if DEBUG
import SwiftUI

@MainActor
final class SaveIncomingShareFixtureSession: ObservableObject {
    static let shared = SaveIncomingShareFixtureSession()
    @Published var verified = false
    @Published var owner = "fixture-account"
    @Published var generation = 1
    @Published private(set) var joins = 0

    var session: SaveIncomingShareSession { .init(owner: owner, generation: generation) }

    func join(code: String) throws -> SaveCollaborativeList {
        guard code == "fixture-list" else { throw SaveCollaborativeListError.invalidLink }
        joins += 1
        let scenario = ProcessInfo.processInfo.environment["SAVE_INCOMING_SHARE_SCENARIO"] ?? ""
        if ["list-join-failure", "list-clip-join-failure"].contains(scenario)
            || (scenario == "list-join-recovery" && joins == 1) {
            throw SaveCollaborativeListError.invalidLink
        }
        // The live joined list deliberately differs from the Clip selection.
        return SaveCollaborativeList(title: "Synthetic joined list", items: [])
    }
}

/// Explicit UI-suite launch only: isolated preferences, synthetic receipts and
/// in-memory save responses. No App Group journal or backend writes.
struct SaveIncomingShareFixtureRoot: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-incoming-share")
            && ReviewDemo.isOfflineUITestMode
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
    let verificationChanged: () -> Void
    @StateObject private var language = AppLanguageSettings(userDefaults: Self.defaults, preferredLanguages: { ["en"] })
    @StateObject private var notebook = Self.makeNotebook()
    @ObservedObject private var account = SaveIncomingShareFixtureSession.shared
    @State private var prepared = false
    @State private var saves = 0
    @State private var resolutions = 0
    @State private var returnedSaves = 0
    @State private var waiting: (CheckedContinuation<SharedPlaceSaveOutcome, Error>, SharedPlaceSaveOutcome)?

    var body: some View {
        Group {
            if account.verified {
                // Exercise the resizable navigation surface, not the 393×852 screenshot canvas.
                SaveInkNavigator(store: notebook)
                    .environment(\.saveInkScreenshot, true)
                    .modifier(SaveIncomingShareHost(
                        incomingPlaceReceipt: $incomingPlaceReceipt,
                        requiresShareConfirmation: $requiresShareConfirmation,
                        requiresListConfirmation: $requiresListConfirmation,
                        pendingClipListSave: $pendingClipListSave,
                        requestID: $requestID,
                        session: account.session,
                        currentSession: { account.verified ? account.session : nil },
                        journalStore: Self.defaults,
                        resolveReceipt: { url in
                            resolutions += 1
                            if Self.scenario == "retry", resolutions == 1 {
                                throw SharedPlaceReceiptError.networkUnavailable
                            }
                            var payload = Self.payload(second: url.lastPathComponent.hasSuffix("-b"))
                            if Self.scenario == "unknown-reference" { payload.coordinateSystem = "unsupported-reference" }
                            return .embedded(payload)
                        },
                        recordReceiptEvent: { _, _, _ in },
                        saveReceipt: { receipt, _ in
                            saves += 1
                            if Self.scenario == "failure" { throw SharedPlaceReceiptError.networkUnavailable }
                            if Self.scenario == "cap" { throw SavePlaceLimitError.parkedInUnplacedInbox }
                            let place = receipt.recipientOwnedPlace(ownerSubject: account.owner)
                            if Self.scenario == "account-switch" {
                                account.verified = false
                                account.owner = "fixture-account-b"
                                account.generation += 1
                                incomingPlaceReceipt = nil
                                requestID = UUID()
                                let outcome: SharedPlaceSaveOutcome = try await withCheckedThrowingContinuation { continuation in
                                    waiting = (continuation, .saved(place))
                                    Task {
                                        try? await Task.sleep(for: .seconds(60))
                                        finishWaiting(cancel: true)
                                    }
                                }
                                returnedSaves += 1
                                return outcome
                            }
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
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if Self.scenario != "list-layout" {
                            VStack {
                                Text("Synthetic share fixture").font(SaveInkType.aux)
                                Text("Saves: \(saves)").accessibilityIdentifier("incoming.fixture.saves")
                                Text("Returned saves: \(returnedSaves)").accessibilityIdentifier("incoming.fixture.returnedSaves")
                                joinCounter
                                Text(PendingShareStore.load(from: Self.defaults) == nil ? "Journal: none" : "Journal: pending")
                                    .accessibilityIdentifier("incoming.fixture.journal")
                                if Self.scenario == "account-switch", waiting != nil {
                                    Button("Complete previous save") { finishWaiting(cancel: false) }
                                        .frame(minHeight: 44)
                                        .accessibilityIdentifier("incoming.fixture.completePreviousSave")
                                }
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
                    }
            } else {
                VStack(spacing: 20) {
                    Text("Account verification fixture").font(SaveInkType.sheetTitle)
                    joinCounter
                    SaveInkOutlineButton(title: "Verify fixture account", identifier: "incoming.fixture.verify") {
                        account.verified = true
                        verificationChanged()
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
            if ["clip", "replacement", "failure", "cap", "list", "list-cap", "list-layout", "list-clip-join-failure", "clip-unknown-reference", "list-unknown-reference", "account-switch"].contains(Self.scenario) { writeJournal() }
            account.verified = !ProcessInfo.processInfo.arguments.contains("--uitest-incoming-share-unverified")
            verificationChanged()
        }
        .onChange(of: requestID) { _, _ in
            if Self.scenario != "account-switch" { finishWaiting(cancel: false) }
        }
        .onDisappear { finishWaiting(cancel: true) }
    }

    private var joinCounter: some View {
        Text("Joins: \(account.joins)").accessibilityIdentifier("incoming.fixture.joins")
    }

    private static func makeNotebook() -> SaveInkNotebookStore {
        let store = SaveInkPreviewFactory.store(for: .main)
        if scenario == "existing-modal" { store.path = [.passport] }
        return store
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
            kind: list ? .list : .place, shareCode: list ? "fixture-list" : "share-fixture",
            placeId: nil, listId: nil, sender: nil,
            url: list ? "savvy://list?c=fixture-list" : "savvy://p/share-fixture",
            confirmedPlaces: [Self.snapshot]
        ), to: Self.defaults)
    }

    private static var snapshot: PendingConfirmedPlace {
        PendingConfirmedPlace(
            placeId: "fixture-place-a", name: "Fixture place A", address: "Synthetic address",
            latitude: 25.033, longitude: 121.5654, category: "cafe", sourceURL: nil,
            coordinateSystem: scenario.hasSuffix("unknown-reference") ? "unsupported-reference" : nil
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
