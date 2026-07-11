import SwiftUI

@main
struct SaveApp: App {
    @StateObject private var authService = PrivyAuthService.shared
    @StateObject private var languageSettings = AppLanguageSettings()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var openedPlace: SharedPlaceData?
    @State private var openedTrip: SharedTripData?
    @State private var openedList: SaveCollaborativeList?
    @State private var openedReferral: SaveReferralProfile?
    @State private var minimumOpeningAnimationCompleted = false
#if DEBUG
    @State private var smokeHarnessActive = SaveSmokeHarness.isLaunchEnabled
    @State private var forceOnboardingForUITests = ProcessInfo.processInfo.arguments.contains("--uitest-reset-onboarding")
#endif

    private let supabaseService = SupabaseService.shared
    private let pendingImportService = PendingPlaceImportService.shared
    private let minimumOpeningAnimationDuration: UInt64 = 1_800_000_000

    init() {
        // Generous shared image/network cache so place photos load once then
        // render instantly on every subsequent open.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
#if DEBUG
        // UI tests cannot use "-hasCompletedOnboarding NO": NSArgumentDomain outranks
        // the persistent domain, so the in-app write back to true would never be read.
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
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
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                rootContent
            }
            .environment(\.appLanguageSettings, languageSettings)
            .onOpenURL(perform: handleIncomingURL)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleIncomingURL(url)
            }
            .alert(linkAlertTitle, isPresented: Binding(
                get: { openedPlace != nil || openedTrip != nil || openedList != nil || openedReferral != nil },
                set: {
                    if !$0 {
                        openedPlace = nil
                        openedTrip = nil
                        openedList = nil
                        openedReferral = nil
                    }
                }
            )) {
                Button(languageSettings.text(.ok)) {
                    openedPlace = nil
                    openedTrip = nil
                    openedList = nil
                    openedReferral = nil
                }
            } message: {
                if let openedReferral {
                    Text(referralReadyMessage(openedReferral))
                } else if let openedPlace {
                    Text(placeReadyMessage(openedPlace))
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
        if smokeHarnessActive {
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
                captureOnboardingFirstClue(firstClue)
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
                SignInView(onFirstClueCaptured: captureOnboardingFirstClue)
                    .environmentObject(authService)
            case .authenticated:
                ContentView()
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

    private func captureOnboardingFirstClue(_ firstClue: String?) {
        guard let firstClue else { return }
        pendingImportService.queueOnboardingFirstClue(firstClue)
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
        if let target = SaveReferralLink.target(from: url) {
            Task { await handleReferralTarget(target) }
            return
        }

        if isPlaceLink(url), let place = SharedPlaceData.from(url: url) {
            openedPlace = place
            return
        }

        if isPlaceLink(url), SharedPlaceData.shortCode(from: url) != nil {
            Task {
                guard let place = await SharedPlaceData.resolveShortCode(from: url) else { return }
                await MainActor.run {
                    openedPlace = place
                }
            }
            return
        }

        if isTripLink(url), let trip = SharedTripData.from(url: url) {
            openedTrip = trip
            return
        }

        guard SaveSharedListPayload.isListLink(url) else {
            return
        }

        do {
            openedList = try SaveCollaborativeListStore.shared.join(from: url)
        } catch {
            openedList = SaveCollaborativeList(
                title: languageSettings.localized(english: "Could not open list", traditionalChinese: "無法打開清單"),
                note: error.localizedDescription,
                viewerRole: .viewer
            )
        }
    }

    @MainActor
    private func handleReferralTarget(_ target: SaveReferralTarget) async {
        let profile: SaveReferralProfile
        do {
            profile = try await supabaseService.fetchReferralProfile(target: target)
        } catch {
            profile = target.previewProfile
        }
        SaveReferralHandoffStore.shared.save(profile)
        openedReferral = profile
    }

    private var linkAlertTitle: String {
        if openedReferral != nil {
            switch languageSettings.language {
            case .english: return "Referral ready"
            case .traditionalChinese: return "推薦連結準備好了"
            }
        }
        if openedPlace != nil {
            switch languageSettings.language {
            case .english: return "SAV-E place ready"
            case .traditionalChinese: return "SAV-E 地點準備好了"
            }
        }
        if openedList != nil {
            switch languageSettings.language {
            case .english: return "SAV-E list ready"
            case .traditionalChinese: return "SAV-E 清單準備好了"
            }
        }
        return languageSettings.text(.tripLinkReady)
    }

    private func referralReadyMessage(_ profile: SaveReferralProfile) -> String {
        switch languageSettings.language {
        case .english:
            return "\(profile.displayName)'s starter map pack is ready. SAV-E will finish the follow after install/open and unlock your first AI itinerary from their places."
        case .traditionalChinese:
            return "\(profile.displayName) 的入門地圖包準備好了。安裝或打開後，SAV-E 會完成追蹤，並用這些地點解鎖你的第一份 AI 行程。"
        }
    }

    private func placeReadyMessage(_ place: SharedPlaceData) -> String {
        switch languageSettings.language {
        case .english:
            return "\(place.name) is ready. Save it to your SAV-E or open Maps from the place card."
        case .traditionalChinese:
            return "\(place.name) 已準備好。你可以存進 SAV-E，或從地點卡打開地圖。"
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
        if url.scheme == "wanderly", url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/p/")
    }

    private func isTripLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "trip" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/trip/")
            || (url.path == "/trip" && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "d" } == true)
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
            SaveOpeningStep(icon: "link", label: openingStepClues, tint: .saveSignal),
            SaveOpeningStep(icon: "checklist", label: languageSettings.text(.review), tint: .saveHoney),
            SaveOpeningStep(icon: "mappin.and.ellipse", label: openingStepMap, tint: .saveMint)
        ]
    }

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                SaveOpeningLogoMark(isBreathing: isBreathing, reduceMotion: reduceMotion)

                VStack(spacing: 12) {
                    Text(languageSettings.text(.opening))
                        .font(.title3.weight(.bold))
                        .foregroundColor(.saveInk)

                    SaveOpeningStepRail(steps: loadingSteps, activeStep: activeStep)
                }

                SaveOpeningHintPill(text: languageSettings.text(.openingHint))
            }
            .padding(.horizontal, 32)
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
            SaveOpeningScrapbookCard(fill: .saveCream, rotation: -10, offset: CGSize(width: -42, height: 28))
            SaveOpeningScrapbookCard(fill: .saveHoney, rotation: 9, offset: CGSize(width: 38, height: 18))
            SaveOpeningScrapbookCard(fill: .saveNotebookPage, rotation: 3, offset: CGSize(width: 8, height: 42))

            Circle()
                .stroke(Color.saveHoney.opacity(0.42), lineWidth: 9)
                .frame(width: 156, height: 156)
                .scaleEffect(isBreathing && !reduceMotion ? 1.08 : 0.96)
                .opacity(isBreathing && !reduceMotion ? 0.18 : 0.42)

            MemoMascotMark(size: 126, framed: false)
                .scaleEffect(isBreathing && !reduceMotion ? 1.035 : 0.985)
                .offset(y: isBreathing && !reduceMotion ? -5 : 2)
                .shadow(color: Color.saveInk.opacity(0.16), radius: 0, x: 0, y: 7)

            SaveOpeningSpark(systemImage: "sparkles", fill: .saveHoney, offset: CGSize(width: 72, height: -54))
            SaveOpeningSpark(systemImage: "link", fill: .saveCream, offset: CGSize(width: -76, height: -34))
            SaveOpeningSpark(systemImage: "heart.fill", fill: .saveCream, offset: CGSize(width: 76, height: 50))
        }
        .frame(width: 210, height: 190)
        .accessibilityHidden(true)
    }
}

private struct SaveOpeningScrapbookCard: View {
    var fill: Color
    var rotation: Double
    var offset: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fill.opacity(0.92))
            .frame(width: 76, height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.6)
            )
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .shadow(color: Color.saveInk.opacity(0.10), radius: 0, x: 3, y: 4)
    }
}

private struct SaveOpeningSpark: View {
    var systemImage: String
    var fill: Color
    var offset: CGSize

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundColor(.saveInk)
            .frame(width: 34, height: 34)
            .background(fill)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.3))
            .offset(offset)
    }
}

private struct SaveOpeningStepRail: View {
    var steps: [SaveOpeningStep]
    var activeStep: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                SaveOpeningStepChip(step: step, isActive: index == activeStep)
            }
        }
        .padding(8)
        .background(Color.saveNotebookPage.opacity(0.88))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.4))
    }
}

private struct SaveOpeningStepChip: View {
    var step: SaveOpeningStep
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: step.icon)
                .font(.caption.weight(.bold))
            Text(step.label)
                .font(.caption.weight(.bold))
        }
        .foregroundColor(.saveInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isActive ? step.tint : Color.saveCream.opacity(0.55))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(isActive ? 1 : 0.35), lineWidth: 1))
        .scaleEffect(isActive ? 1.03 : 0.96)
    }
}

private struct SaveOpeningHintPill: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.saveHoney)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 0.8))

            Text(text)
                .font(.caption.weight(.bold))
                .foregroundColor(.saveMutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.saveNotebookPage.opacity(0.72))
        .clipShape(Capsule())
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @EnvironmentObject var authService: PrivyAuthService
    @Environment(\.appLanguageSettings) private var languageSettings
    var onFirstClueCaptured: (String) -> Void = { _ in }
    @State private var email = ""
    @State private var showEmailCode = false
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var showsSampleProof = false
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
                    Spacer(minLength: isCompactHeight ? 10 : 22)

                    SignInHero(isCompactHeight: isCompactHeight)
                        .padding(.horizontal, 24)

                    Spacer(minLength: isCompactHeight ? 12 : 20)

                    SignInWorkflowStrip(isCompactHeight: isCompactHeight)
                        .padding(.horizontal, 22)

                    sampleProofButton
                        .padding(.horizontal, 22)
                        .padding(.top, isCompactHeight ? 10 : 14)

                    Spacer(minLength: isCompactHeight ? 12 : 18)

                    VStack(spacing: isCompactHeight ? 10 : 12) {
                        appleSignInButton
                        googleSignInButton
                        emailSignInSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, isCompactHeight ? 16 : 28)
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
        .sheet(isPresented: $showsSampleProof) {
            OnboardingView(startWithSampleProof: true) { firstClue in
                if let firstClue {
                    onFirstClueCaptured(firstClue)
                }
                showsSampleProof = false
            }
        }
    }

    private func presentAuthError(_ error: Error) {
        let rawMessage = error.localizedDescription
        print("SAV-E sign-in failed: \(rawMessage)")

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
            Task {
                isLoading = true
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
            Task {
                isLoading = true
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
                    .stroke(Color.saveNotebookLine, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sampleProofButton: some View {
        Button {
            showsSampleProof = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(
                        english: "See how it works — no sign-in",
                        traditionalChinese: "先試試看 — 不用登入"
                    ))
                    .font(.subheadline.weight(.bold))
                    Text(languageSettings.localized(
                        english: "Drop a sample clue and watch it land on a map.",
                        traditionalChinese: "丟一個範例線索，看它變成地圖上的地點。"
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(.saveInk)
            .padding(14)
            .background(Color.saveHoney.opacity(0.50))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    Task {
                        isLoading = true
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
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do { try await authService.verifyEmailCode(verificationCode) }
                        catch { presentAuthError(error) }
                    }
                }
            }
        }
    }
}

private struct SignInHero: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let isCompactHeight: Bool

    var body: some View {
        VStack(spacing: isCompactHeight ? 12 : 16) {
            SignInProofMark(
                label: languageSettings.localized(english: "Proof kept", traditionalChinese: "保留證據"),
                isCompactHeight: isCompactHeight
            )

            VStack(spacing: isCompactHeight ? 5 : 8) {
                Text(languageSettings.text(.appName))
                    .font(.system(size: isCompactHeight ? 34 : 38, weight: .black, design: .rounded))
                    .foregroundColor(.saveInk)

                Text(languageSettings.text(.signInTagline))
                    .font(isCompactHeight ? .headline.weight(.bold) : .title3.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)

                Text(languageSettings.text(.signInDescription))
                    .font(isCompactHeight ? .caption.weight(.semibold) : .subheadline)
                    .lineSpacing(2)
                    .foregroundColor(.saveInk.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineLimit(isCompactHeight ? 3 : nil)
                    .minimumScaleFactor(0.84)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SignInProofMark: View {
    let label: String
    let isCompactHeight: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.saveNotebookPage.opacity(0.82))
                .frame(width: isCompactHeight ? 140 : 166, height: isCompactHeight ? 106 : 126)
                .rotationEffect(.degrees(-4))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.saveHoney.opacity(0.22))
                .frame(width: isCompactHeight ? 114 : 138, height: isCompactHeight ? 84 : 100)
                .offset(x: 22, y: 12)

            MemoMascotMark(size: isCompactHeight ? 98 : 118, framed: false)
                .offset(y: isCompactHeight ? -3 : -5)

            Label(label, systemImage: "link")
                .font((isCompactHeight ? Font.caption2 : Font.caption).weight(.bold))
                .foregroundColor(.saveInk)
                .padding(.horizontal, isCompactHeight ? 9 : 11)
                .padding(.vertical, isCompactHeight ? 6 : 7)
                .background(Color.saveHoney.opacity(0.92))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.52), lineWidth: 1))
                .offset(x: isCompactHeight ? 54 : 66, y: isCompactHeight ? 44 : 52)
        }
        .frame(height: isCompactHeight ? 126 : 152)
        .accessibilityHidden(true)
    }
}

private struct SignInWorkflowStrip: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let isCompactHeight: Bool

    private var steps: [(String, String, Color)] {
        [
            (languageSettings.text(.capture), languageSettings.text(.captureSubtitle), .saveHoney),
            (languageSettings.text(.review), languageSettings.text(.reviewSubtitle), .saveSignal),
            (languageSettings.text(.save), languageSettings.text(.saveSubtitle), .saveMint),
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { index in
                WorkflowStepCard(
                    title: steps[index].0,
                    subtitle: steps[index].1,
                    tint: steps[index].2,
                    isCompactHeight: isCompactHeight
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(languageSettings.localized(
            english: "Capture links or media, review with evidence, remember confirmed places.",
            traditionalChinese: "收進連結或媒體，看證據確認，再記住已確認地點。"
        ))
    }
}

private struct WorkflowStepCard: View {
    let title: String
    let subtitle: String
    let tint: Color
    let isCompactHeight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 4 : 5) {
            Circle()
                .fill(tint)
                .frame(width: isCompactHeight ? 8 : 10, height: isCompactHeight ? 8 : 10)
                .overlay(
                    Circle()
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.saveCocoa.opacity(0.68))
                .lineLimit(isCompactHeight ? 1 : 2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompactHeight ? 10 : 12)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .font(.subheadline.weight(.bold))
                .foregroundColor(isDisabled ? Color.saveCocoa.opacity(0.42) : .saveInk)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(isDisabled ? Color.clear : Color.saveHoney)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isDisabled)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
