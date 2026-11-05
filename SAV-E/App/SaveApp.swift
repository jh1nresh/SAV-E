import SwiftUI
import UIKit

#if DEBUG
import DebugBridgeCore
import DebugBridgeUI
#endif

private struct DeferredAccountScopedLink: Equatable {
    let id: UUID
    let url: URL
    var ownerGeneration: Int?
}

#if DEBUG
/// UI-test appearance must be applied before first paint. `XCUIDevice.appearance`
/// is ignored on some CI simulators; `-AppleInterfaceStyle` plus this hook
/// force `overrideUserInterfaceStyle` and SwiftUI `preferredColorScheme`.
private struct UITestAppearanceOverride: ViewModifier {
    private let scheme: ColorScheme?
    private let style: UIUserInterfaceStyle

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest-force-dark") || arguments.contains("--uitest-dark") {
            scheme = .dark
            style = .dark
        } else if arguments.contains("--uitest-force-light") {
            scheme = .light
            style = .light
        } else {
            scheme = nil
            style = .unspecified
        }
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(scheme)
            .background(UITestWindowAppearanceSetter(style: style))
    }
}

private struct UITestWindowAppearanceSetter: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        apply(from: uiView)
        DispatchQueue.main.async { apply(from: uiView) }
    }

    private func apply(from view: UIView) {
        guard style != .unspecified else { return }
        view.window?.overrideUserInterfaceStyle = style
        view.window?.rootViewController?.overrideUserInterfaceStyle = style
    }
}
#endif

@main
struct SaveApp: App {
    @StateObject private var authService = PrivyAuthService.shared
    @StateObject private var languageSettings = AppLanguageSettings(userDefaults: SaveInkLaunch.defaults)
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(
        "pendingFriendShareURL",
        store: SaveApp.incomingShareDefaults
    ) private var pendingFriendShareURL = ""
    @State private var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @State private var requiresShareConfirmation = false
    @State private var requiresListConfirmation = false
    @State private var pendingClipListSave: SaveCollaborativeList?
    @State private var incomingShareRequestID = UUID()
    @State private var openedTrip: SharedTripData?
    @State private var openedList: SaveCollaborativeList?
    @State private var openedReferral: SaveReferralProfile?
    @State private var linkErrorMessage: String?
    @State private var verifiedAccountGeneration: Int?
    @State private var deferredAccountScopedLink: DeferredAccountScopedLink?
    @State private var accountScopedURLProcessingID: UUID?
    @State private var lastAccountUserId: String?
    @State private var minimumOpeningAnimationCompleted = false
    /// A real clue typed during onboarding is handed to the explicit capture
    /// screen after sign-in. It is not queued or saved until the user taps
    /// Analyze into Review.
    @AppStorage("pendingOnboardingClue") private var pendingOnboardingClue = ""
    /// Empty until the first verified account receives the clue. Once claimed,
    /// another account must never see or import that unfinished private text.
    @AppStorage("pendingOnboardingClueOwnerID") private var pendingOnboardingClueOwnerID = ""
#if DEBUG
    @State private var smokeHarnessActive = SaveSmokeHarness.isLaunchEnabled
    private let relatedSourcesHarnessActive = SaveSmokeHarness.isRelatedSourcesLaunchEnabled
    @State private var forceOnboardingForUITests = ProcessInfo.processInfo.arguments.contains("--uitest-reset-onboarding")
    private let stampFeedFixtureActive = ProcessInfo.processInfo.arguments.contains("--uitest-stamp-feed-fixture")
    private let photoAttributionEvidenceActive = GooglePlacesPhotoAttributionEvidence.isLaunchEnabled
    private let mapPhotoPinCatalogActive = ProcessInfo.processInfo.arguments.contains("--uitest-map-photo-pin-catalog")
    private let mapPhotoPinMotionActive = ProcessInfo.processInfo.arguments.contains("--uitest-map-photo-pin-motion")
    private let mapPhotoPinCoralCardActive = ProcessInfo.processInfo.arguments.contains("--uitest-map-photo-pin-coral-card")
    private let mapPhotoPinCardActive = ProcessInfo.processInfo.arguments.contains("--uitest-map-photo-pin-card")
#endif

    private let supabaseService = SupabaseService.shared
    private let pendingImportService = PendingPlaceImportService.shared
    private let accountScopedURLMaxBytes = 8 * 1024

    private static var incomingShareDefaults: UserDefaults? {
#if DEBUG
        if SaveIncomingShareFixtureRoot.isEnabled { return SaveIncomingShareFixtureRoot.defaults }
#endif
        return UserDefaults(suiteName: "group.com.wanderly.app")
    }

    private var minimumOpeningAnimationDuration: UInt64 {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-hold-opening") {
            return 8_000_000_000
        }
#endif
        return 1_800_000_000
    }

    init() {
        // Generous shared image/network cache so place photos load once then
        // render instantly on every subsequent open.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
#if DEBUG
        DebugBridgeUIWiring.installAll()
        DebugBridgeManager.shared.start(
            appState: DebugQAState.shared,
            register: DebugQAStateAccessor.register
        )
        ReviewDemoStorage.resetUITestStorageIfRequested()
        // UI tests cannot use "-hasCompletedOnboarding NO": NSArgumentDomain outranks
        // the persistent domain, so the in-app write back to true would never be read.
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "pendingOnboardingClue")
            UserDefaults.standard.removeObject(forKey: "pendingOnboardingClueOwnerID")
            ClipAppleAccountStore.clear()
        }
        // Keep the first-run map coachmark tour out of UI tests / smoke runs so
        // it never traps focus over the map under test.
        if ProcessInfo.processInfo.arguments.contains("--skip-map-tour") {
            UserDefaults.standard.set(true, forKey: "hasSeenMapTour")
        }
        // Screenshot/UI-test rail: jump straight past onboarding so the sign-in
        // screen (and the review-demo flow behind it) is immediately reachable.
        if ProcessInfo.processInfo.arguments.contains("--uitest-complete-onboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "pendingOnboardingClue")
            UserDefaults.standard.removeObject(forKey: "pendingOnboardingClueOwnerID")
            ClipAppleAccountStore.clear()
        }
        // After an intentional backend identity rebuild (new account-ref
        // secret), stored refs can never match and the recovery screen has no
        // forward path. Clearing the ref makes the next sign-in first-time;
        // the local vault is untouched.
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-account-gate") {
            try? KeychainAccountReferenceStore.shared.clear()
            ClipAppleAccountStore.clear()
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                rootContent
            }
            .environment(\.appLanguageSettings, languageSettings)
            .environment(\.locale, languageSettings.locale)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { languageSettings.refreshSystemLanguage() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                languageSettings.refreshSystemLanguage()
            }
#if DEBUG
            .modifier(UITestAppearanceOverride())
#endif
            .onAppear(perform: restorePendingShare)
            .onChange(of: incomingPlaceReceipt?.id) { _, receiptID in
                if receiptID == nil {
                    pendingFriendShareURL = ""
                    // Closing a preview is not confirmation or dismissal of its
                    // durable Clip journal. Relaunch can offer it again.
                }
            }
            .onOpenURL(perform: handleIncomingURL)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleIncomingURL(url)
            }
            .onChange(of: authService.sessionGeneration) { _, generation in
                handleAccountGenerationChange(generation)
            }
            .alert(linkAlertTitle, isPresented: Binding(
                get: { openedTrip != nil || openedList != nil || openedReferral != nil || linkErrorMessage != nil },
                set: {
                    if !$0 {
                        openedTrip = nil
                        openedList = nil
                        openedReferral = nil
                        linkErrorMessage = nil
                    }
                }
            )) {
                Button(languageSettings.text(.ok)) {
                    openedTrip = nil
                    openedList = nil
                    openedReferral = nil
                    linkErrorMessage = nil
                }
            } message: {
                if let linkErrorMessage {
                    Text(linkErrorMessage)
                } else if let openedReferral {
                    Text(referralReadyMessage(openedReferral))
                } else if let openedList {
                    Text(listReadyMessage(openedList))
                } else if let openedTrip {
                    Text(String(
                        format: languageSettings.text(.tripLinkMessage),
                        openedTrip.name,
                        openedTrip.stops.count
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if SaveIncomingShareFixtureRoot.isEnabled {
            SaveIncomingShareFixtureRoot(
                incomingPlaceReceipt: $incomingPlaceReceipt,
                requiresShareConfirmation: $requiresShareConfirmation,
                requiresListConfirmation: $requiresListConfirmation,
                pendingClipListSave: $pendingClipListSave,
                requestID: $incomingShareRequestID,
                showParentAlert: { linkErrorMessage = "Synthetic existing alert" }
            )
        } else if photoAttributionEvidenceActive {
            GooglePlacesPhotoAttributionEvidenceView()
        } else if stampFeedFixtureActive {
            SaveStampFeedFixtureView()
        } else if mapPhotoPinCatalogActive {
            SavvyMapPhotoPinPreviewCatalog(
                colorScheme: ProcessInfo.processInfo.arguments.contains("--uitest-dark") ? .dark : .light,
                language: ProcessInfo.processInfo.arguments.contains("--uitest-map-photo-pin-zh") ? .traditionalChinese : .english
            )
        } else if mapPhotoPinMotionActive {
            SavvyMapPhotoPinMotionFixtureRoot()
        } else if mapPhotoPinCoralCardActive {
            previewPage(
                .coralCardHero,
                scheme: ProcessInfo.processInfo.arguments.contains("--uitest-dark") ? .dark : .light
            )
            .accessibilityIdentifier("map.fixture.coralCard")
        } else if mapPhotoPinCardActive {
            SavvyMapPhotoPinCardFlowFixtureRoot()
        } else if relatedSourcesHarnessActive {
            SaveRelatedSourcesHarnessView()
        } else if smokeHarnessActive {
            SaveSmokeHarnessView()
        } else {
            productRoot
        }
#else
        productRoot
#endif
    }

    @ViewBuilder
    private var productRoot: some View {
        if let screen = SaveInkLaunch.previewScreen {
            SaveInkNotebookRoot(launch: .preview(screen))
        } else {
            standardRootContent
        }
    }

    @ViewBuilder
    private var standardRootContent: some View {
        if shouldShowOnboarding {
            OnboardingView { firstClue in
                if let firstClue {
                    storeUnclaimedOnboardingClue(firstClue)
                }
                hasCompletedOnboarding = true
#if DEBUG
                forceOnboardingForUITests = false
#endif
                minimumOpeningAnimationCompleted = false
            }
        } else if shouldShowOpeningAnimation {
            AuthLoadingView()
                .task {
                    await completeMinimumOpeningAnimation()
                }
        } else {
            switch authService.authState {
            case .unknown:
                AuthLoadingView()
            case .unauthenticated:
                SignInView()
                    .environmentObject(authService)
            case .authenticated:
                AuthenticatedRootView(
                    sessionGeneration: authService.sessionGeneration,
                    sessionOrigin: authService.sessionOrigin,
                    pendingOnboardingClue: $pendingOnboardingClue,
                    pendingOnboardingClueOwnerID: $pendingOnboardingClueOwnerID,
                    incomingPlaceReceipt: $incomingPlaceReceipt,
                    requiresShareConfirmation: $requiresShareConfirmation,
                    requiresListConfirmation: $requiresListConfirmation,
                    pendingClipListSave: $pendingClipListSave,
                    incomingShareRequestID: $incomingShareRequestID,
                    onVerificationChanged: updateVerifiedAccount
                )
                    .environmentObject(authService)
            }
        }
    }

    private var shouldShowOnboarding: Bool {
#if DEBUG
        !hasCompletedOnboarding || forceOnboardingForUITests
#else
        !hasCompletedOnboarding
#endif
    }

    private var shouldShowOpeningAnimation: Bool {
        !minimumOpeningAnimationCompleted || authService.authState == .unknown
    }

    @MainActor
    private func completeMinimumOpeningAnimation() async {
        guard !minimumOpeningAnimationCompleted else { return }
#if DEBUG
        // Screenshot evidence must not race the normal eight-second test hold.
        if ProcessInfo.processInfo.arguments.contains("--uitest-freeze-opening") { return }
#endif
        try? await Task.sleep(nanoseconds: minimumOpeningAnimationDuration)
        minimumOpeningAnimationCompleted = true
    }

    /// A new accepted link replaces only transient presentation. Its predecessor's
    /// durable Clip journal is acknowledged only by a matching confirmed save.
    private func prepareIncomingLink() {
        incomingShareRequestID = UUID()
        incomingPlaceReceipt = nil
        requiresShareConfirmation = false
        requiresListConfirmation = false
        pendingClipListSave = nil
        deferredAccountScopedLink = nil
        accountScopedURLProcessingID = nil
    }

    private func handleIncomingURL(_ url: URL) {
#if DEBUG
        if SaveSmokeHarness.isSmokeURL(url) {
            smokeHarnessActive = true
            return
        }
#endif
        if SaveSharedListPayload.isListLink(url) {
            guard let accepted = ClipListHandoff.acceptedListURL(
                pending: PendingShareStore.load(from: Self.incomingShareDefaults),
                incomingURL: url
            ) else { return }
            prepareIncomingLink()
            deferredAccountScopedLink = DeferredAccountScopedLink(
                id: UUID(),
                url: accepted,
                ownerGeneration: isCurrentAccountVerified ? authService.sessionGeneration : nil
            )
            accountScopedURLProcessingID = nil
            processDeferredAccountURLIfVerified()
            return
        }

        if SaveReferralLink.target(from: url) != nil {
            guard url.absoluteString.utf8.count <= accountScopedURLMaxBytes else { return }
            prepareIncomingLink()
            deferredAccountScopedLink = DeferredAccountScopedLink(
                id: UUID(),
                url: url,
                ownerGeneration: isCurrentAccountVerified ? authService.sessionGeneration : nil
            )
            accountScopedURLProcessingID = nil
            processDeferredAccountURLIfVerified()
            return
        }

        if isPlaceLink(url) {
            prepareIncomingLink()
            guard url.absoluteString.utf8.count <= ShareRoutePayloadLimits.pendingPlaceURLMaxBytes else {
                pendingFriendShareURL = ""
                // A malformed new link does not acknowledge an existing intent.
                incomingPlaceReceipt = .malformed(url)
                return
            }
            pendingFriendShareURL = url.absoluteString
            requiresListConfirmation = false
            requiresShareConfirmation = ClipPlaceHandoff.shouldConfirmPlace(
                pending: PendingShareStore.load(from: Self.incomingShareDefaults),
                incomingURL: url
            )
            if let place = SharedPlaceData.from(url: url) {
                incomingPlaceReceipt = .embedded(place)
            } else if SharedPlaceData.shortCode(from: url) != nil {
                incomingPlaceReceipt = .shortLink(url)
            } else {
                incomingPlaceReceipt = .malformed(url)
            }
            return
        }

        if isTripLink(url), let trip = SharedTripData.from(url: url) {
            prepareIncomingLink()
            openedTrip = trip
            return
        }

    }

    @MainActor
    private func updateVerifiedAccount(sourceGeneration: Int, verifiedGeneration: Int?) {
        guard sourceGeneration == authService.sessionGeneration else { return }
        verifiedAccountGeneration = verifiedGeneration
        if verifiedGeneration != nil {
            processDeferredAccountURLIfVerified()
        }
    }

    private var isCurrentAccountVerified: Bool {
        guard case .authenticated = authService.authState else { return false }
        return verifiedAccountGeneration == authService.sessionGeneration
    }

    @MainActor
    private func handleAccountGenerationChange(_ generation: Int) {
#if DEBUG
        if SaveIncomingShareFixtureRoot.isEnabled { return }
#endif
        incomingShareRequestID = UUID()
        let previousUserId = lastAccountUserId
        let currentUserId = authService.currentUserId
        lastAccountUserId = currentUserId
        verifiedAccountGeneration = nil
        accountScopedURLProcessingID = nil
        if let ownerGeneration = deferredAccountScopedLink?.ownerGeneration,
           ownerGeneration != generation {
            deferredAccountScopedLink = nil
        }
        openedList = nil
        openedReferral = nil
        linkErrorMessage = nil
        guard ClipPlaceHandoff.shouldResetHandoffOnAccountChange(
            previousUserId: previousUserId,
            currentUserId: currentUserId
        ) else { return }
        pendingClipListSave = nil
        requiresListConfirmation = false
        incomingPlaceReceipt = nil
        requiresShareConfirmation = false
        pendingFriendShareURL = ""
        deferredAccountScopedLink = nil
        ClipPlaceHandoff.resetPlaceHandoffOnAccountChange()
    }

    private func storeUnclaimedOnboardingClue(_ clue: String) {
        pendingOnboardingClue = clue
        pendingOnboardingClueOwnerID = ""
    }

    @MainActor
    private func processDeferredAccountURLIfVerified() {
        guard isCurrentAccountVerified,
              accountScopedURLProcessingID == nil,
              var link = deferredAccountScopedLink else { return }

        let generation = authService.sessionGeneration
        guard link.ownerGeneration == nil || link.ownerGeneration == generation else {
            deferredAccountScopedLink = nil
            return
        }
        if link.ownerGeneration == nil {
            link.ownerGeneration = generation
            deferredAccountScopedLink = link
        }

        if let target = SaveReferralLink.target(from: link.url) {
            let processingID = UUID()
            let linkID = link.id
            accountScopedURLProcessingID = processingID
            Task {
                await completeDeferredReferral(
                    target,
                    linkID: linkID,
                    processingID: processingID,
                    generation: generation
                )
            }
            return
        }

        guard SaveSharedListPayload.isListLink(link.url) else {
            deferredAccountScopedLink = nil
            return
        }
        // `?c=` short codes join server-side (role enforced by the backend).
        // Reviewer demo skips the server and falls through to the legacy path,
        // where the code-only link simply reports as invalid.
        if let code = SaveSharedListPayload.shareCode(from: link.url), !authService.isReviewerDemo {
            let processingID = UUID()
            let linkID = link.id
            accountScopedURLProcessingID = processingID
            Task {
                await completeDeferredListJoin(
                    code: code,
                    linkID: linkID,
                    processingID: processingID,
                    generation: generation
                )
            }
            return
        }
        do {
            let joined = try activeCollaborativeListStore.join(from: link.url)
            presentOpenedList(joined, incomingURL: link.url)
        } catch {
            presentListJoinFailure(error, incomingURL: link.url)
        }
        if deferredAccountScopedLink?.id == link.id {
            deferredAccountScopedLink = nil
        }
    }

    @MainActor
    private func completeDeferredListJoin(
        code: String,
        linkID: UUID,
        processingID: UUID,
        generation: Int
    ) async {
        var joined: SaveCollaborativeList?
        var joinError: Error?
        do {
            let row = try await supabaseService.joinCollaborativeList(code: code)
            joined = SaveCollaborativeList(serverRow: row)
            if joined == nil {
                joinError = SaveCollaborativeListError.invalidLink
            }
        } catch {
            joinError = error
        }

        guard accountScopedURLProcessingID == processingID else { return }
        accountScopedURLProcessingID = nil
        guard let link = deferredAccountScopedLink,
              link.id == linkID,
              link.ownerGeneration == generation,
              isCurrentAccountVerified,
              authService.sessionGeneration == generation,
              SaveSharedListPayload.isListLink(link.url) else {
            if deferredAccountScopedLink?.id == linkID {
                deferredAccountScopedLink = nil
            }
            return
        }

        if let joined {
            storeJoinedList(joined)
            presentOpenedList(joined, incomingURL: link.url)
        } else {
            presentListJoinFailure(
                joinError ?? SaveCollaborativeListError.invalidLink,
                incomingURL: link.url
            )
        }
        deferredAccountScopedLink = nil
    }

    /// Clip selected a pending snapshot. A separate full App action confirms
    /// it; live list changes must not add or remove selected places.
    private func presentOpenedList(_ list: SaveCollaborativeList?, incomingURL: URL) {
        if let stamp = ClipListHandoff.stampList(
            pending: PendingShareStore.load(from: Self.incomingShareDefaults),
            incomingURL: incomingURL,
            joined: list
        ) {
            incomingShareRequestID = UUID()
            incomingPlaceReceipt = nil
            requiresShareConfirmation = false
            requiresListConfirmation = true
            pendingClipListSave = stamp
            openedList = nil
        } else if let list {
            openedList = list
        }
    }

    private func presentListJoinFailure(_ error: Error, incomingURL: URL) {
        openedList = SaveCollaborativeList(
            title: languageSettings.localized(english: "Could not open list", traditionalChinese: "無法打開清單"),
            note: error.localizedDescription,
            viewerRole: .viewer
        )
        presentOpenedList(nil, incomingURL: incomingURL)
    }

    /// Persists a server-joined list into the active local store (cache) and
    /// posts didJoin so ContentView's observer reloads MapViewModel.
    @MainActor
    private func storeJoinedList(_ list: SaveCollaborativeList) {
        let store = activeCollaborativeListStore
        var lists = store.load()
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index] = list
        } else {
            lists.insert(list, at: 0)
        }
        store.save(lists)
        NotificationCenter.default.post(name: SaveCollaborativeListNotification.didJoin, object: list)
    }

    @MainActor
    private func completeDeferredReferral(
        _ target: SaveReferralTarget,
        linkID: UUID,
        processingID: UUID,
        generation: Int
    ) async {
        let profile: SaveReferralProfile?
        do {
            profile = try await supabaseService.fetchReferralProfile(target: target)
        } catch {
            profile = nil
        }

        guard accountScopedURLProcessingID == processingID else { return }
        accountScopedURLProcessingID = nil
        guard let link = deferredAccountScopedLink,
              link.id == linkID,
              link.ownerGeneration == generation,
              isCurrentAccountVerified,
              authService.sessionGeneration == generation,
              SaveReferralLink.target(from: link.url) != nil else {
            if deferredAccountScopedLink?.id == linkID {
                deferredAccountScopedLink = nil
            }
            return
        }
        guard let profile else {
            linkErrorMessage = languageSettings.localized(
                english: "This friend profile could not be loaded right now. Check your connection and try again. If it keeps failing, ask your friend to share a new Savvy profile link.",
                traditionalChinese: "目前無法載入這位朋友的資料。請檢查網路後再試一次；若持續失敗，再請朋友重新分享 Savvy 個人連結。"
            )
            deferredAccountScopedLink = nil
            return
        }
        activeReferralHandoffStore.save(profile)
        openedReferral = profile
        deferredAccountScopedLink = nil
    }

    private var activeCollaborativeListStore: SaveCollaborativeListStore {
        authService.isReviewerDemo ? ReviewDemoStorage.collaborativeListStore : .shared
    }

    private var activeReferralHandoffStore: SaveReferralHandoffStore {
        authService.isReviewerDemo ? ReviewDemoStorage.referralHandoffStore : .shared
    }

    private func restorePendingShare() {
#if DEBUG
        if SaveIncomingShareFixtureRoot.isEnabled { return }
#endif
        if lastAccountUserId == nil {
            lastAccountUserId = authService.currentUserId
        }
        guard incomingPlaceReceipt == nil else { return }
        if let payload = PendingShareStore.load(from: Self.incomingShareDefaults), let url = URL(string: payload.url) {
            handleIncomingURL(url)
            return
        }
        guard !pendingFriendShareURL.isEmpty,
              let url = URL(string: pendingFriendShareURL),
              isPlaceLink(url)
        else { return }
        // Preview-only AppStorage URL is not a Clip save intent.
        handleIncomingURL(url)
    }

    private var linkAlertTitle: String {
        if linkErrorMessage != nil {
            return languageSettings.localized(english: "Could not load friend profile", traditionalChinese: "無法載入朋友資料")
        }
        if openedReferral != nil {
            switch languageSettings.language {
            case .english: return "Referral ready"
            case .traditionalChinese: return "推薦連結準備好了"
            }
        }
        if openedList != nil {
            switch languageSettings.language {
            case .english: return "Savvy list ready"
            case .traditionalChinese: return "Savvy 清單準備好了"
            }
        }
        return languageSettings.text(.tripLinkReady)
    }

    private func referralReadyMessage(_ profile: SaveReferralProfile) -> String {
        switch languageSettings.language {
        case .english:
            return "\(profile.displayName)'s starter map pack is ready. Savvy will finish the follow after install/open and unlock your first AI itinerary from their places."
        case .traditionalChinese:
            return "\(profile.displayName) 的入門地圖包準備好了。安裝或打開後，Savvy 會完成追蹤，並用這些地點解鎖你的第一份 AI 行程。"
        }
    }

    private func listReadyMessage(_ list: SaveCollaborativeList) -> String {
        switch languageSettings.language {
        case .english:
            return "\(list.title) joined as \(list.viewerRole.displayName.lowercased()). \(list.items.count) places are ready in Lists."
        case .traditionalChinese:
            return "你已加入「\(list.title)」，目前角色是 \(list.viewerRole.displayName.lowercased())。清單裡有 \(list.items.count) 個地點。"
        }
    }

    private func isPlaceLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/p/")
    }

    private func isTripLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "trip" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/trip/")
            || (url.path == "/trip" && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "d" } == true)
    }
}

// MARK: - Verified Account Root

@MainActor
private struct AuthenticatedRootView: View {
    @EnvironmentObject private var authService: PrivyAuthService
    @Environment(\.appLanguageSettings) private var languageSettings
    @StateObject private var accountGate = AccountSessionGate()

    let sessionGeneration: Int
    let sessionOrigin: AccountSessionOrigin
    @Binding var pendingOnboardingClue: String
    @Binding var pendingOnboardingClueOwnerID: String
    @Binding var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @Binding var requiresShareConfirmation: Bool
    @Binding var requiresListConfirmation: Bool
    @Binding var pendingClipListSave: SaveCollaborativeList?
    @Binding var incomingShareRequestID: UUID
    let onVerificationChanged: (_ sourceGeneration: Int, _ verifiedGeneration: Int?) -> Void

    @State private var isRebindConfirmationPresented = false

    private var taskID: AccountGateTaskID {
        AccountGateTaskID(generation: sessionGeneration, origin: sessionOrigin)
    }

    var body: some View {
        Group {
            switch accountGate.state {
            case .verified(let verifiedGeneration) where verifiedGeneration == sessionGeneration:
                verifiedAccountContent
            case .idle, .verifying, .verified:
                AuthLoadingView()
            case .accountNeedsConfirmation(let kind):
                accountConfirmationView(kind)
            case .recoveryNeeded(let reason):
                recoveryView(reason)
            case .reauthenticationRequired:
                reauthenticationView
            case .unavailable:
                unavailableView
            }
        }
        .task(id: taskID) {
            await verifyAccount()
#if DEBUG
            if DebugVaultExporter.isServiceDiagnosisRequested {
                await DebugVaultExporter.runServiceDiagnosis()
            }
            if DebugVaultExporter.isRequested {
                await DebugVaultExporter.run()
            }
#endif
        }
        .onChange(of: accountGate.state) { _, state in
            if case .verified(let generation) = state, generation == sessionGeneration {
                onVerificationChanged(sessionGeneration, generation)
            } else {
                onVerificationChanged(sessionGeneration, nil)
            }
        }
        .onDisappear {
            onVerificationChanged(sessionGeneration, nil)
        }
    }

    private var verifiedAccountContent: some View {
        SaveInkNotebookRoot()
            .modifier(SaveIncomingShareHost(
                incomingPlaceReceipt: $incomingPlaceReceipt,
                requiresShareConfirmation: $requiresShareConfirmation,
                requiresListConfirmation: $requiresListConfirmation,
                pendingClipListSave: $pendingClipListSave,
                requestID: $incomingShareRequestID,
                session: SaveIncomingShareSession(owner: authService.currentUserId ?? "", generation: sessionGeneration),
                currentSession: {
                    guard case .authenticated = authService.authState,
                          case .verified(let generation) = accountGate.state,
                          generation == sessionGeneration,
                          authService.sessionGeneration == generation,
                          let owner = authService.currentUserId else { return nil }
                    return SaveIncomingShareSession(owner: owner, generation: generation)
                }
            ))
            .onAppear(perform: claimPendingOnboardingClueIfNeeded)
    }

    private func claimPendingOnboardingClueIfNeeded() {
        guard !pendingOnboardingClue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pendingOnboardingClueOwnerID.isEmpty,
              let userID = authService.currentUserId
        else { return }
        pendingOnboardingClueOwnerID = userID
    }

    private func accountConfirmationView(_ kind: AccountConfirmationKind) -> some View {
        AccountAccessView(
            icon: "person.crop.circle.badge.plus",
            title: confirmationTitle(kind),
            message: confirmationMessage(kind),
            primaryTitle: confirmationPrimaryTitle(kind),
            primaryAccessibilityID: "accountGate.startNew",
            primaryAction: {
                await accountGate.confirmPendingAccount(sessionGeneration: sessionGeneration)
            },
            secondaryTitle: languageSettings.localized(
                english: "Use a different sign-in",
                traditionalChinese: "改用其他登入帳號"
            ),
            secondaryAccessibilityID: "accountGate.switchGoogle",
            secondaryAction: signOutForGoogleChoice
        )
    }

    private func recoveryView(_ reason: AccountRecoveryReason) -> some View {
        // For `.differentAccount` (stale Keychain ref after backend rebuild),
        // re-link is the real escape hatch — promote it to primary. "Use a
        // different sign-in" used to be primary and often looped because the
        // dead ref survived sign-out.
        Group {
            if reason == .differentAccount {
                AccountAccessView(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: recoveryTitle(reason),
                    message: recoveryMessage(reason),
                    primaryTitle: languageSettings.localized(
                        english: "Re-link this phone to the current account…",
                        traditionalChinese: "把這支手機重新連結到現在的帳號…"
                    ),
                    primaryAccessibilityID: "accountGate.rebindDevice",
                    primaryAction: {
                        isRebindConfirmationPresented = true
                    },
                    secondaryTitle: languageSettings.localized(
                        english: "Use a different sign-in",
                        traditionalChinese: "改用其他登入帳號"
                    ),
                    secondaryAccessibilityID: "accountGate.switchGoogle",
                    secondaryAction: signOutForGoogleChoice,
                    tertiaryTitle: languageSettings.localized(
                        english: "Try again",
                        traditionalChinese: "再試一次"
                    ),
                    tertiaryAccessibilityID: "accountGate.retry",
                    tertiaryAction: { Task { await verifyAccount() } }
                )
            } else {
                AccountAccessView(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: recoveryTitle(reason),
                    message: recoveryMessage(reason),
                    primaryTitle: languageSettings.localized(
                        english: "Use a different sign-in",
                        traditionalChinese: "改用其他登入帳號"
                    ),
                    primaryAccessibilityID: "accountGate.switchGoogle",
                    primaryAction: signOutForGoogleChoice,
                    secondaryTitle: languageSettings.localized(
                        english: "Try again",
                        traditionalChinese: "再試一次"
                    ),
                    secondaryAccessibilityID: "accountGate.retry",
                    secondaryAction: verifyAccount
                )
            }
        }
        .confirmationDialog(
            languageSettings.localized(
                english: "Forget the old account link on this phone?",
                traditionalChinese: "要清除這支手機上的舊帳號連結嗎？"
            ),
            isPresented: $isRebindConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                languageSettings.localized(
                    english: "Forget old link and continue",
                    traditionalChinese: "清除舊連結並繼續"
                ),
                role: .destructive
            ) {
                Task { await resetDeviceBinding() }
            }
            Button(
                languageSettings.localized(english: "Cancel", traditionalChinese: "取消"),
                role: .cancel
            ) {}
        } message: {
            Text(languageSettings.localized(
                english: "Only this phone's record of the old account link is removed — no saved places or map data are deleted. Next you'll see the current account's contents and confirm it yourself before anything is linked.",
                traditionalChinese: "只會清除這支手機上舊的帳號連結紀錄，不會刪除任何已存地點或地圖資料。下一步會先顯示現在帳號裡的內容，由你親自確認後才會連結。"
            ))
        }
    }

    private func resetDeviceBinding() async {
        await accountGate.resetDeviceBinding(
            sessionGeneration: sessionGeneration,
            sessionOrigin: sessionOrigin,
            reviewerDemo: authService.isReviewerDemo
        )
    }

    private var reauthenticationView: some View {
        AccountAccessView(
            icon: "key.horizontal.fill",
            title: languageSettings.localized(
                english: "Verify your Savvy account",
                traditionalChinese: "重新驗證 Savvy 帳號"
            ),
            message: languageSettings.localized(
                english: "Your saved data is unchanged. Sign in again with the exact method and account you used for Savvy.",
                traditionalChinese: "你的已存資料沒有被刪除。請用原本的登入方式與同一個帳號重新登入 Savvy。"
            ),
            primaryTitle: languageSettings.localized(
                english: "Continue to sign-in",
                traditionalChinese: "前往重新登入"
            ),
            primaryAccessibilityID: "accountGate.reauthenticate",
            primaryAction: signOutForGoogleChoice,
            secondaryTitle: languageSettings.localized(english: "Try again", traditionalChinese: "再試一次"),
            secondaryAccessibilityID: "accountGate.retry",
            secondaryAction: verifyAccount
        )
    }

    private var unavailableView: some View {
        AccountAccessView(
            icon: "wifi.exclamationmark",
            title: languageSettings.localized(
                english: "Couldn’t verify your account",
                traditionalChinese: "目前無法確認你的帳號"
            ),
            message: languageSettings.localized(
                english: "Savvy kept the map locked so data from two accounts cannot mix. Check your connection and try again.",
                traditionalChinese: "Savvy 已先鎖住地圖，避免兩個帳號的資料混在一起。請檢查網路後再試一次。"
            ),
            primaryTitle: languageSettings.localized(english: "Try again", traditionalChinese: "再試一次"),
            primaryAccessibilityID: "accountGate.retry",
            primaryAction: verifyAccount,
            secondaryTitle: languageSettings.localized(
                english: "Use a different sign-in",
                traditionalChinese: "改用其他登入帳號"
            ),
            secondaryAccessibilityID: "accountGate.switchGoogle",
            secondaryAction: signOutForGoogleChoice
        )
    }

    private func verifyAccount() async {
        await accountGate.verify(
            sessionGeneration: sessionGeneration,
            sessionOrigin: sessionOrigin,
            reviewerDemo: authService.isReviewerDemo
        )
    }

    private func signOutForGoogleChoice() async {
        // Clear a stale different-account Keychain ref before Privy sign-out
        // so the next interactive login can reach confirmation instead of
        // bouncing straight back into recovery.
        accountGate.prepareAccountSwitch()
        await authService.signOut()
    }

    private func recoveryTitle(_ reason: AccountRecoveryReason) -> String {
        switch reason {
        case .emptyRestoredAccount, .differentAccount:
            return languageSettings.localized(
                english: "This isn’t your saved Savvy account",
                traditionalChinese: "這不是你原本有資料的 Savvy 帳號"
            )
        case .unconfirmedRestoredAccount:
            return languageSettings.localized(
                english: "Confirm your original account",
                traditionalChinese: "確認你的原本帳號"
            )
        case .splitProfileBinding, .conflictingProfileBinding, .missingConfirmedProfile:
            return languageSettings.localized(
                english: "Your account needs recovery",
                traditionalChinese: "你的帳號需要恢復確認"
            )
        }
    }

    private func recoveryMessage(_ reason: AccountRecoveryReason) -> String {
        switch reason {
        case .emptyRestoredAccount:
            return languageSettings.localized(
                english: "This login has no Map Stamps or Review items. Your original data has not been deleted. Sign out and use the exact method and account you used before.",
                traditionalChinese: "這個登入沒有地圖章或 Review 紀錄。你的原始資料沒有被刪除；請登出並用之前的登入方式與同一個帳號重新登入。"
            )
        case .differentAccount:
            return languageSettings.localized(
                english: "Savvy stopped before opening a different account, so saved and local data cannot mix. Use your original sign-in and account.",
                traditionalChinese: "Savvy 已在打開不同帳號前停止，避免已存與本機資料混在一起。請使用原本的登入方式與帳號。"
            )
        case .unconfirmedRestoredAccount:
            return languageSettings.localized(
                english: "Before this update can attach the map stored on this phone, sign out and use the exact method and account you used before. You’ll confirm it once after sign-in.",
                traditionalChinese: "這次更新在連結手機上的舊地圖前，會先請你登出並用之前的登入方式與同一個帳號重新登入；登入後只需確認一次。"
            )
        case .splitProfileBinding, .conflictingProfileBinding:
            return languageSettings.localized(
                english: "Savvy found conflicting account records and did not choose one. Your data is unchanged; verify the original sign-in and account before continuing.",
                traditionalChinese: "Savvy 發現互相衝突的帳號紀錄，因此沒有擅自選擇。你的資料未被更動；請先驗證原本的登入方式與帳號。"
            )
        case .missingConfirmedProfile:
            return languageSettings.localized(
                english: "The previously confirmed account record is unavailable. Savvy stopped before loading or syncing any data.",
                traditionalChinese: "先前已確認的帳號紀錄目前不存在。Savvy 已在載入或同步任何資料前停止。"
            )
        }
    }

    private func confirmationTitle(_ kind: AccountConfirmationKind) -> String {
        switch kind {
        case .newAccount:
            return languageSettings.localized(
                english: "Start a new Savvy account?",
                traditionalChinese: "要建立新的 Savvy 帳號嗎？"
            )
        case .existingAccount:
            return languageSettings.localized(
                english: "Is this your original Savvy account?",
                traditionalChinese: "這是你原本的 Savvy 帳號嗎？"
            )
        case .emptyAccount:
            return languageSettings.localized(
                english: "Use this empty Savvy account?",
                traditionalChinese: "要使用這個空白 Savvy 帳號嗎？"
            )
        }
    }

    private func confirmationMessage(_ kind: AccountConfirmationKind) -> String {
        switch kind {
        case .newAccount:
            return languageSettings.localized(
                english: "This sign-in has no Savvy profile yet. Continue only if this is the account you want to bind to this phone’s map.",
                traditionalChinese: "這個登入帳號尚未有 Savvy 資料。只有在你確定要把這支手機的地圖連結到此帳號時才繼續。"
            )
        case .existingAccount(let stamps, let reviewItems):
            return languageSettings.localized(
                english: "Savvy found \(stamps) Map Stamps and \(reviewItems) Review items. Confirm once before this phone’s local map is attached.",
                traditionalChinese: "Savvy 找到 \(stamps) 個地圖章與 \(reviewItems) 筆 Review。請先確認一次，才會連結這支手機上的本機地圖。"
            )
        case .emptyAccount:
            return languageSettings.localized(
                english: "This existing profile has 0 Map Stamps and 0 Review items. Continue only if you intentionally want this account on this phone.",
                traditionalChinese: "這個既有帳號目前有 0 個地圖章與 0 筆 Review。只有在你確定要在這支手機使用此帳號時才繼續。"
            )
        }
    }

    private func confirmationPrimaryTitle(_ kind: AccountConfirmationKind) -> String {
        switch kind {
        case .newAccount:
            return languageSettings.localized(english: "Start with this account", traditionalChinese: "用這個帳號開始")
        case .existingAccount:
            return languageSettings.localized(english: "Confirm original account", traditionalChinese: "確認原本帳號")
        case .emptyAccount:
            return languageSettings.localized(english: "Use this empty account", traditionalChinese: "使用這個空白帳號")
        }
    }
}

private struct AccountGateTaskID: Hashable {
    let generation: Int
    let origin: AccountSessionOrigin
}

private struct AccountAccessView: View {
    let icon: String
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAccessibilityID: String
    let primaryAction: () async -> Void
    let secondaryTitle: String?
    let secondaryAccessibilityID: String?
    let secondaryAction: (() async -> Void)?
    var tertiaryTitle: String? = nil
    var tertiaryAccessibilityID: String? = nil
    var tertiaryAction: (() -> Void)? = nil

    @State private var isWorking = false

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.saveInk)
                    .frame(width: 82, height: 82)
                    .background(Color.saveHoney.opacity(0.58))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.4))

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.saveInk)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.saveMutedText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                VStack(spacing: 12) {
                    Button(primaryTitle) {
                        run(primaryAction)
                    }
                    .font(.headline)
                    .foregroundColor(.saveNotebookPage)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.saveInk)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier(primaryAccessibilityID)

                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle) {
                            run(secondaryAction)
                        }
                        .font(.headline)
                        .foregroundColor(.saveInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.saveNotebookPage)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier(secondaryAccessibilityID ?? "")
                    }

                    if let tertiaryTitle, let tertiaryAction {
                        Button(tertiaryTitle) {
                            tertiaryAction()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .accessibilityIdentifier(tertiaryAccessibilityID ?? "")
                    }
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView()
                        .tint(.saveInk)
                }
            }
            .padding(24)
            .frame(maxWidth: 430)
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}

// MARK: - Auth Loading View

struct AuthLoadingView: View {
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SaveInkEntryBrand()
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(SaveInkPalette.ink)
                            .accessibilityHidden(true)
                        Text(languageSettings.text(.opening))
                            .font(SaveInkType.secondaryButton)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(languageSettings.text(.opening))
                    .accessibilityIdentifier("opening.loading")
                    Text(languageSettings.localized(
                        english: "Just a moment.",
                        traditionalChinese: "稍等一下，就好。"
                    ))
                    .font(SaveInkType.body)
                    .foregroundStyle(SaveInkPalette.inkSub)
                }
                .frame(maxWidth: 390, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .clipped()
        }
        .foregroundStyle(SaveInkPalette.ink)
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

private struct SaveInkEntryBrand: View {
    var body: some View {
        Image("SavvyWordmark")
            .resizable()
            .scaledToFit()
            .frame(width: 164)
            .accessibilityLabel("Savvy")
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @EnvironmentObject var authService: PrivyAuthService
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var email = ""
    @State private var showEmailCode = false
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var focusedActionID: String?
    @State private var errorTitle = "Can't Sign In"
    @State private var errorMessage: String?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSendEmailCode: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".") && !isLoading
    }

    private var signingInLabel: String {
        languageSettings.localized(english: "Signing in…", traditionalChinese: "正在登入…")
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if focusedActionID == nil {
                        SaveInkEntryBrand()
                            .padding(.bottom, 28)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(showEmailCode
                            ? languageSettings.localized(english: "Enter your code", traditionalChinese: "輸入驗證碼")
                            : languageSettings.localized(english: "Sign in to Savvy", traditionalChinese: "登入 Savvy"))
                            .font(SaveInkType.subpageTitle)
                            .foregroundStyle(SaveInkPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("signin.title")
                        if !showEmailCode && focusedActionID == nil {
                            Text(languageSettings.localized(
                                english: "Keep the places you want to visit.",
                                traditionalChinese: "把想去的地方，留在自己的手帳裡。"
                            ))
                            .font(SaveInkType.body)
                            .foregroundStyle(SaveInkPalette.inkSub)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 14) {
                        if !showEmailCode && focusedActionID == nil {
                            appleSignInButton
                            googleSignInButton
                        }
                        emailSignInSection
                    }
                    .disabled(isLoading)

                    if showEmailCode {
                        Button {
                            focusedActionID = nil
                            verificationCode = ""
                            showEmailCode = false
                        } label: {
                            Text(languageSettings.localized(english: "Back to sign-in options", traditionalChinese: "返回登入選項"))
                                .font(SaveInkType.body)
                                .foregroundStyle(SaveInkPalette.inkSub)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        .padding(.top, 12)
                        .accessibilityIdentifier("signin.backToOptions")
                    }

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(SaveInkPalette.ink)
                            Text(signingInLabel)
                            .font(SaveInkType.aux)
                        }
                        .foregroundStyle(SaveInkPalette.inkSub)
                        .padding(.top, 16)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("signin.loading")
                    }
                }
                .frame(maxWidth: 390, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .clipped()
            .onChange(of: focusedActionID) { _, actionID in
                guard let actionID else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(actionID, anchor: .bottom)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                guard let focusedActionID else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(focusedActionID, anchor: .bottom)
                }
            }
        }
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onChange(of: isLoading) { _, loading in
            if loading {
                UIAccessibility.post(notification: .announcement, argument: signingInLabel)
            }
        }
        .alert(errorTitle, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(languageSettings.text(.ok)) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func presentAuthError(_ error: Error) {
        let rawMessage = error.localizedDescription
        print("Savvy sign-in failed: \(rawMessage)")

        if rawMessage.contains("disallowed_login_method") || rawMessage.contains("not allowed") {
            errorTitle = languageSettings.text(.googleNotEnabled)
            errorMessage = languageSettings.text(.googleNotEnabledMessage)
        } else if rawMessage.contains("invalid_native_app_id") {
            errorTitle = languageSettings.text(.appNotAllowed)
            errorMessage = languageSettings.text(.appNotAllowedMessage)
        } else if rawMessage.contains("Invalid app client ID") {
            errorTitle = languageSettings.text(.authSetupNeeded)
            errorMessage = languageSettings.localized(
                english: "Check the iOS client ID in Privy and try again.",
                traditionalChinese: "請檢查 Privy 裡的 iOS client ID，然後再試一次。"
            )
        } else if rawMessage.contains("Missing Privy config") {
            errorTitle = languageSettings.text(.authSetupNeeded)
            errorMessage = rawMessage
        } else {
            errorTitle = languageSettings.text(.cantSignIn)
            errorMessage = languageSettings.text(.genericSignInError)
        }
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton {
            guard !isLoading else { return }
            isLoading = true
            Task {
                defer { isLoading = false }
                do { try await authService.signInWithApple() }
                catch { presentAuthError(error) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("signin.apple")
    }

    private var googleSignInButton: some View {
        Button(action: {
            guard !isLoading else { return }
            isLoading = true
            Task {
                defer { isLoading = false }
                do { try await authService.signInWithGoogle() }
                catch { presentAuthError(error) }
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SaveInkPalette.ink)
                Text(languageSettings.text(.continueWithGoogle))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(SaveInkType.secondaryButton)
            .foregroundStyle(SaveInkPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                SaveInkRoughRoundedRect(cornerRadius: 20, seed: 511)
                    .fill(SaveInkPalette.card)
            )
            .overlay(
                SaveInkRoughRoundedRect(cornerRadius: 20, seed: 511)
                    .stroke(SaveInkPalette.ink, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signin.google")
    }

    private var emailSignInSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !showEmailCode && focusedActionID == nil {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(SaveInkPalette.emptyLine)
                        .frame(height: 1)
                    Text(languageSettings.text(.orUseEmail))
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Rectangle()
                        .fill(SaveInkPalette.emptyLine)
                        .frame(height: 1)
                }
            }

            if !showEmailCode {
                SignInInputRow(
                    placeholder: languageSettings.text(.emailAddress),
                    text: $email,
                    buttonTitle: languageSettings.text(.sendCode),
                    keyboardType: .emailAddress,
                    isDisabled: !canSendEmailCode,
                    fieldAccessibilityID: "signin.emailField",
                    buttonAccessibilityID: "signin.sendCode",
                    onFocusChange: { focusedActionID = $0 }
                ) {
                    guard !isLoading else { return }
                    isLoading = true
                    Task {
                        defer { isLoading = false }
                        do {
                            email = trimmedEmail
                            try await authService.signInWithEmail(trimmedEmail)
                            showEmailCode = true
                        } catch {
                            presentAuthError(error)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if focusedActionID == nil {
                        Text(languageSettings.localized(
                            english: "Enter the code sent to",
                            traditionalChinese: "輸入寄到以下信箱的驗證碼"
                        ))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(email)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("signin.codeHint")

                SignInInputRow(
                    placeholder: languageSettings.text(.verificationCode),
                    text: $verificationCode,
                    buttonTitle: languageSettings.text(.verify),
                    keyboardType: .numberPad,
                    isDisabled: verificationCode.isEmpty || isLoading,
                    fieldAccessibilityID: "signin.codeField",
                    buttonAccessibilityID: "signin.verify",
                    onFocusChange: { focusedActionID = $0 }
                ) {
                    guard !isLoading else { return }
                    isLoading = true
                    Task {
                        defer { isLoading = false }
                        do { try await authService.verifyEmailCode(verificationCode) }
                        catch { presentAuthError(error) }
                    }
                }
            }
        }
    }
}

enum PendingOnboardingClueAccess {
    static func isAvailable(text: String, ownerUserID: String, currentUserID: String?) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let currentUserID else { return false }
        return ownerUserID.isEmpty || ownerUserID == currentUserID
    }

    static func canMutate(ownerUserID: String, currentUserID: String?) -> Bool {
        guard let currentUserID else { return false }
        return ownerUserID.isEmpty || ownerUserID == currentUserID
    }

    static func ownerAfterMutation(newText: String, ownerUserID: String, currentUserID: String) -> String {
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return ownerUserID.isEmpty ? currentUserID : ownerUserID
    }
}

private struct SignInInputRow: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let placeholder: String
    @Binding var text: String
    let buttonTitle: String
    let keyboardType: UIKeyboardType
    let isDisabled: Bool
    // Stable hooks for UI tests / the App Store screenshot rail — the demo
    // sign-in flow types into these fields (see Tests/SAVEUITests).
    var fieldAccessibilityID: String = ""
    var buttonAccessibilityID: String = ""
    var onFocusChange: (String?) -> Void = { _ in }
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(SaveInkPalette.inkSub))
                .font(SaveInkType.secondaryButton)
                .keyboardType(keyboardType)
                .textContentType(keyboardType == .emailAddress ? .emailAddress : .oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .foregroundStyle(SaveInkPalette.ink)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier(fieldAccessibilityID)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    onFocusChange(focused ? buttonAccessibilityID : nil)
                }
                .onSubmit { isFocused = false }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .background {
                    SaveInkRoughRoundedRect(cornerRadius: 18, seed: 512)
                        .fill(SaveInkPalette.card)
                }
                .overlay {
                    SaveInkRoughRoundedRect(cornerRadius: 18, seed: 512)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(languageSettings.localized(english: "Done", traditionalChinese: "完成")) {
                            isFocused = false
                        }
                        .accessibilityIdentifier("signin.keyboardDone")
                    }
                }

            Button {
                isFocused = false
                action()
            } label: {
                Text(buttonTitle)
                    .font(SaveInkType.secondaryButton)
                    .foregroundStyle(isDisabled ? SaveInkPalette.inkSub : SaveInkPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background {
                        SaveInkRoughRoundedRect(cornerRadius: 24, seed: 513)
                            .fill(isDisabled ? SaveInkPalette.unverifiedFill : SaveInkPalette.card)
                    }
                    .overlay {
                        SaveInkRoughRoundedRect(cornerRadius: 24, seed: 513)
                            .stroke(isDisabled ? SaveInkPalette.emptyLine : SaveInkPalette.ink, lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(buttonAccessibilityID)
            .id(buttonAccessibilityID)
            .disabled(isDisabled)
        }
    }
}
