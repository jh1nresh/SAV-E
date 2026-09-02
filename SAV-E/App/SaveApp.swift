import SwiftUI

#if DEBUG
import DebugBridgeCore
import DebugBridgeUI
#endif

private struct DeferredAccountScopedLink: Equatable {
    let id: UUID
    let url: URL
    var ownerGeneration: Int?
}

@main
struct SaveApp: App {
    @StateObject private var authService = PrivyAuthService.shared
    @StateObject private var languageSettings = AppLanguageSettings()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(
        "pendingFriendShareURL",
        store: UserDefaults(suiteName: "group.com.wanderly.app")
    ) private var pendingFriendShareURL = ""
    @State private var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @State private var openedTrip: SharedTripData?
    @State private var openedList: SaveCollaborativeList?
    @State private var openedReferral: SaveReferralProfile?
    @State private var linkErrorMessage: String?
    @State private var verifiedAccountGeneration: Int?
    @State private var deferredAccountScopedLink: DeferredAccountScopedLink?
    @State private var accountScopedURLProcessingID: UUID?
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
#endif

    private let supabaseService = SupabaseService.shared
    private let pendingImportService = PendingPlaceImportService.shared
    private let accountScopedURLMaxBytes = 8 * 1024

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
        }
        // After an intentional backend identity rebuild (new account-ref
        // secret), stored refs can never match and the recovery screen has no
        // forward path. Clearing the ref makes the next sign-in first-time;
        // the local vault is untouched.
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-account-gate") {
            try? KeychainAccountReferenceStore.shared.clear()
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                rootContent
            }
            .environment(\.appLanguageSettings, languageSettings)
            .onAppear(perform: restorePendingFriendShare)
            .onChange(of: incomingPlaceReceipt?.id) { _, receiptID in
                if receiptID == nil {
                    pendingFriendShareURL = ""
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
        if stampFeedFixtureActive {
            SaveStampFeedFixtureView()
        } else if relatedSourcesHarnessActive {
            SaveRelatedSourcesHarnessView()
        } else if smokeHarnessActive {
            SaveSmokeHarnessView()
        } else {
            standardRootContent
        }
#else
        standardRootContent
#endif
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
                    incomingPlaceReceipt: $incomingPlaceReceipt,
                    pendingOnboardingClue: $pendingOnboardingClue,
                    pendingOnboardingClueOwnerID: $pendingOnboardingClueOwnerID,
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
        try? await Task.sleep(nanoseconds: minimumOpeningAnimationDuration)
        minimumOpeningAnimationCompleted = true
    }

    private func handleIncomingURL(_ url: URL) {
#if DEBUG
        if SaveSmokeHarness.isSmokeURL(url) {
            smokeHarnessActive = true
            return
        }
#endif
        if SaveReferralLink.target(from: url) != nil || SaveSharedListPayload.isListLink(url) {
            guard url.absoluteString.utf8.count <= accountScopedURLMaxBytes else { return }
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
            guard url.absoluteString.utf8.count <= ShareRoutePayloadLimits.pendingPlaceURLMaxBytes else {
                pendingFriendShareURL = ""
                incomingPlaceReceipt = .malformed(url)
                return
            }
            pendingFriendShareURL = url.absoluteString
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
        verifiedAccountGeneration = nil
        accountScopedURLProcessingID = nil
        if let ownerGeneration = deferredAccountScopedLink?.ownerGeneration,
           ownerGeneration != generation {
            deferredAccountScopedLink = nil
        }
        openedList = nil
        openedReferral = nil
        linkErrorMessage = nil
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
            openedList = try activeCollaborativeListStore.join(from: link.url)
        } catch {
            openedList = SaveCollaborativeList(
                title: languageSettings.localized(english: "Could not open list", traditionalChinese: "無法打開清單"),
                note: error.localizedDescription,
                viewerRole: .viewer
            )
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
            openedList = joined
        } else {
            openedList = SaveCollaborativeList(
                title: languageSettings.localized(english: "Could not open list", traditionalChinese: "無法打開清單"),
                note: (joinError ?? SaveCollaborativeListError.invalidLink).localizedDescription,
                viewerRole: .viewer
            )
        }
        deferredAccountScopedLink = nil
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

    private func restorePendingFriendShare() {
        guard incomingPlaceReceipt == nil,
              !pendingFriendShareURL.isEmpty,
              let url = URL(string: pendingFriendShareURL),
              isPlaceLink(url)
        else { return }
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
    @Binding var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @Binding var pendingOnboardingClue: String
    @Binding var pendingOnboardingClueOwnerID: String
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
        ContentView(
            incomingPlaceReceipt: $incomingPlaceReceipt,
            pendingOnboardingClue: pendingClueForVerifiedAccount,
            storageScope: authService.isReviewerDemo ? .reviewerDemo : .production
        )
        .onAppear(perform: claimPendingOnboardingClueIfNeeded)
    }

    private var pendingClueForVerifiedAccount: Binding<String> {
        Binding(
            get: {
                guard PendingOnboardingClueAccess.isAvailable(
                    text: pendingOnboardingClue,
                    ownerUserID: pendingOnboardingClueOwnerID,
                    currentUserID: authService.currentUserId
                ) else { return "" }
                return pendingOnboardingClue
            },
            set: { newValue in
                guard let currentUserID = authService.currentUserId else { return }
                guard PendingOnboardingClueAccess.canMutate(
                    ownerUserID: pendingOnboardingClueOwnerID,
                    currentUserID: currentUserID
                ) else { return }
                pendingOnboardingClue = newValue
                pendingOnboardingClueOwnerID = PendingOnboardingClueAccess.ownerAfterMutation(
                    newText: newValue,
                    ownerUserID: pendingOnboardingClueOwnerID,
                    currentUserID: currentUserID
                )
            }
        )
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
            secondaryTitle: languageSettings.localized(english: "Try again", traditionalChinese: "再試一次"),
            secondaryAccessibilityID: "accountGate.retry",
            secondaryAction: verifyAccount,
            tertiaryTitle: reason == .differentAccount
                ? languageSettings.localized(
                    english: "Re-link this phone to the current account…",
                    traditionalChinese: "把這支手機重新連結到現在的帳號…"
                )
                : nil,
            tertiaryAccessibilityID: "accountGate.rebindDevice",
            tertiaryAction: { isRebindConfirmationPresented = true }
        )
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
        accountGate.invalidate()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var activeStep = 0

    private var loadingSteps: [SaveOpeningStep] {
        [
            SaveOpeningStep(icon: "link", label: openingStepClues, tint: SaveAtlasPalette.coral),
            SaveOpeningStep(icon: "checklist", label: languageSettings.text(.review), tint: SaveAtlasPalette.sky),
            SaveOpeningStep(icon: "mappin.and.ellipse", label: openingStepMap, tint: SaveAtlasPalette.mint)
        ]
    }

    var body: some View {
        ZStack {
            AtlasCanvas()
                .ignoresSafeArea()

            VStack(spacing: 20) {
                SaveFirstRunBrandLockup()

                Spacer(minLength: 12)

                SaveOpeningLogoMark(isBreathing: isBreathing, reduceMotion: reduceMotion)

                VStack(spacing: 6) {
                    Text(languageSettings.localized(
                        english: "YOUR PLACE MEMORY",
                        traditionalChinese: "你的地點記憶"
                    ))
                    .font(SaveAtlasType.strong(10))
                    .tracking(1)
                    .foregroundStyle(SaveAtlasPalette.coral)

                    Text(languageSettings.text(.opening))
                        .font(SaveAtlasType.strong(27, relativeTo: .title2))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("opening.loading")
                }

                SaveOpeningStepRail(steps: loadingSteps, activeStep: activeStep)

                SaveOpeningHintPill(text: languageSettings.text(.openingHint))

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 650_000_000)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                    activeStep = (activeStep + 1) % loadingSteps.count
                }
            }
        }
    }

    private var openingStepClues: String {
        switch languageSettings.language {
        case .english: return "Clues"
        case .traditionalChinese: return "線索"
        }
    }

    private var openingStepMap: String {
        switch languageSettings.language {
        case .english: return "Map"
        case .traditionalChinese: return "地圖"
        }
    }
}

private struct SaveOpeningStep: Identifiable {
    let icon: String
    let label: String
    let tint: Color

    var id: String { icon }
}

private struct SaveOpeningLogoMark: View {
    var isBreathing: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            SaveOpeningBackTicket(fill: SaveAtlasPalette.sky, rotation: -7, offset: CGSize(width: -33, height: 19))
            SaveOpeningBackTicket(fill: SaveAtlasPalette.mint, rotation: 6, offset: CGSize(width: 31, height: 25))

            Image("SavesEnvelope")
                .resizable()
                .scaledToFit()
                .frame(width: 246)
                .offset(y: 50)

            MemoMascotMark(size: 126, framed: false)
                .scaleEffect(isBreathing && !reduceMotion ? 1.035 : 0.985)
                .offset(y: isBreathing && !reduceMotion ? -23 : -16)
                .shadow(color: SaveAtlasPalette.ink.opacity(0.12), radius: 6, y: 4)

            SavePostcardPostmark()
                .scaleEffect(0.78)
                .rotationEffect(.degrees(-8))
                .offset(x: -82, y: 60)

            Text("CLUE → STAMP")
                .font(SaveAtlasType.strong(10))
                .tracking(0.8)
                .foregroundStyle(SaveAtlasPalette.forest)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(SaveAtlasPalette.paper.opacity(0.94), in: Capsule())
                .overlay {
                    Capsule().stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
                }
                .offset(x: 64, y: 60)
        }
        .frame(width: 280, height: 220)
        .accessibilityHidden(true)
    }
}

private struct SaveOpeningBackTicket: View {
    var fill: Color
    var rotation: Double
    var offset: CGSize

    var body: some View {
        SavePostcardScallopedRectangle(depth: 3, pitch: 10)
            .fill(fill.opacity(0.82))
            .frame(width: 184, height: 108)
            .overlay {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .stroke(
                        SaveAtlasPalette.line.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
            .rotationEffect(.degrees(rotation))
            .offset(offset)
    }
}

private struct SaveOpeningStepRail: View {
    var steps: [SaveOpeningStep]
    var activeStep: Int

    var body: some View {
        VStack(spacing: -4) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                SaveOpeningStepChip(step: step, isActive: index == activeStep)
                    .zIndex(Double(steps.count - index))
            }
        }
        .frame(maxWidth: 320)
    }
}

private struct SaveOpeningStepChip: View {
    var step: SaveOpeningStep
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: step.icon)
                .font(.system(size: 12, weight: .bold))
            Text(step.label)
                .font(SaveAtlasType.strong(13))

            Spacer(minLength: 8)

            Image(systemName: isActive ? "arrow.right" : "circle.fill")
                .font(.system(size: isActive ? 11 : 5, weight: .bold))
                .opacity(isActive ? 1 : 0.28)
        }
        .foregroundStyle(SaveAtlasPalette.ink)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 45)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(4)
        .background {
            SavePostcardScallopedRectangle(depth: 2.5, pitch: 10)
                .fill(isActive ? step.tint.opacity(0.82) : SaveAtlasPalette.kraft.opacity(0.34))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 2.5, pitch: 10)
                .stroke(
                    isActive
                        ? SaveAtlasPalette.forest.opacity(0.46)
                        : SaveAtlasPalette.line.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                )
        }
        .scaleEffect(isActive ? 1 : 0.97)
        .shadow(color: SaveAtlasPalette.ink.opacity(isActive ? 0.055 : 0.02), radius: 4, y: 2)
    }
}

private struct SaveOpeningHintPill: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SaveAtlasPalette.coral)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 0.8))

            Text(text)
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(SaveAtlasPalette.paper.opacity(0.82))
        .overlay {
            Capsule().stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @EnvironmentObject var authService: PrivyAuthService
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var email = ""
    @State private var showEmailCode = false
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorTitle = "Can't Sign In"
    @State private var errorMessage: String?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSendEmailCode: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".") && !isLoading
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight = proxy.size.height < 760

            ZStack {
                SaveDottedBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: isCompactHeight ? 18 : 36)

                    SignInHero(isCompactHeight: isCompactHeight)
                        .padding(.horizontal, 24)

                    Spacer(minLength: isCompactHeight ? 22 : 42)

                    VStack(spacing: isCompactHeight ? 10 : 12) {
                        appleSignInButton
                        googleSignInButton
                        emailSignInSection
                    }
                    .disabled(isLoading)
                    .padding(isCompactHeight ? 14 : 18)
                    .background(SaveAtlasPalette.paper.opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(SaveAtlasPalette.line.opacity(0.34), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: SaveAtlasPalette.ink.opacity(0.06), radius: 12, y: 5)
                    .padding(.horizontal, 22)
                    .padding(.bottom, isCompactHeight ? 18 : 34)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottom) {
            if isLoading {
                ProgressView()
                    .tint(.saveInk)
                    .padding(.bottom, 10)
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
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(.headline)
                Text(languageSettings.text(.continueWithGoogle))
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
        }
        .buttonStyle(.plain)
    }

    private var emailSignInSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.saveNotebookLine.opacity(0.22))
                    .frame(height: 1)
                Text(languageSettings.text(.orUseEmail))
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.68))
                Rectangle()
                    .fill(Color.saveNotebookLine.opacity(0.22))
                    .frame(height: 1)
            }

            if !showEmailCode {
                SignInInputRow(
                    placeholder: languageSettings.text(.emailAddress),
                    text: $email,
                    buttonTitle: languageSettings.text(.sendCode),
                    keyboardType: .emailAddress,
                    isDisabled: !canSendEmailCode,
                    fieldAccessibilityID: "signin.emailField",
                    buttonAccessibilityID: "signin.sendCode"
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
                SignInInputRow(
                    placeholder: languageSettings.text(.verificationCode),
                    text: $verificationCode,
                    buttonTitle: languageSettings.text(.verify),
                    keyboardType: .numberPad,
                    isDisabled: verificationCode.isEmpty || isLoading,
                    fieldAccessibilityID: "signin.codeField",
                    buttonAccessibilityID: "signin.verify"
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

private struct SignInHero: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let isCompactHeight: Bool

    var body: some View {
        VStack(spacing: isCompactHeight ? 10 : 14) {
            MemoMascotMark(size: isCompactHeight ? 76 : 92, framed: false)
                .accessibilityHidden(true)

            VStack(spacing: isCompactHeight ? 5 : 7) {
                Text(languageSettings.text(.appName))
                    .font(SaveAtlasType.strong(isCompactHeight ? 26 : 28, relativeTo: .title))
                    .foregroundStyle(SaveAtlasPalette.forest)

                Text(languageSettings.text(.signInTagline))
                    .font(SaveAtlasType.strong(isCompactHeight ? 16 : 18, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .multilineTextAlignment(.center)

                Text(languageSettings.text(.signInDescription))
                    .font(SaveAtlasType.body(isCompactHeight ? 12 : 14))
                    .lineSpacing(2)
                    .foregroundStyle(SaveAtlasPalette.ink.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(keyboardType == .emailAddress ? .emailAddress : .oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .foregroundColor(.saveInk)
                .accessibilityIdentifier(fieldAccessibilityID)
                .focused($isFocused)
                // The sign-in layout ignores the keyboard safe area, so the
                // keyboard covers the Send/Verify button while typing. The
                // number pad has no return key, so without this Done button a
                // reviewer typing the demo code could never reach "Verify".
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(languageSettings.localized(english: "Done", traditionalChinese: "完成")) {
                            isFocused = false
                        }
                        .accessibilityIdentifier("signin.keyboardDone")
                    }
                }

            Button(buttonTitle, action: action)
                .accessibilityIdentifier(buttonAccessibilityID)
                .font(SaveAtlasType.strong(13))
                .foregroundStyle(isDisabled ? SaveAtlasPalette.muted.opacity(0.42) : SaveAtlasPalette.paper)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(isDisabled ? Color.clear : SaveAtlasPalette.coral)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isDisabled)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
