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

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                } else {
                    switch authService.authState {
                    case .unknown:
                        AuthLoadingView()
                    case .unauthenticated:
                        SignInView()
                            .environmentObject(authService)
                    case .authenticated:
                        ContentView()
                            .environmentObject(authService)
                    }
                }
            }
            .environmentObject(languageSettings)
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
                    Text("\(openedReferral.displayName)'s starter map pack is ready. SAV-E will finish the follow after install/open and unlock your first AI itinerary from their places.")
                } else if let openedPlace {
                    Text("\(openedPlace.name) is ready. Save it to your SAV-E or open Maps from the place card.")
                } else if let openedList {
                    Text("\(openedList.title) joined as \(openedList.viewerRole.displayName.lowercased()). \(openedList.items.count) places are ready in Lists.")
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

    private func handleIncomingURL(_ url: URL) {
        if let profile = SaveReferralLink.profile(from: url) {
            SaveReferralHandoffStore.shared.save(profile)
            openedReferral = profile
            return
        }

        if isPlaceLink(url), let place = SharedPlaceData.from(url: url) {
            openedPlace = place
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
            openedList = SaveCollaborativeList(title: "Could not open list", note: error.localizedDescription, viewerRole: .viewer)
        }
    }

    private var linkAlertTitle: String {
        if openedReferral != nil { return "Referral ready" }
        if openedPlace != nil { return "SAV-E place ready" }
        return openedList == nil ? languageSettings.text(.tripLinkReady) : "SAV-E list ready"
    }

    private func isPlaceLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app", "sav-e.app", "wanderly.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/p/")
    }

    private func isTripLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "trip" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app", "sav-e.app", "wanderly.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/trip/")
            || (url.path == "/trip" && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "d" } == true)
    }
}

// MARK: - Auth Loading View

struct AuthLoadingView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var activeStep = 0

    private let loadingSteps: [SaveOpeningStep] = [
        SaveOpeningStep(icon: "link", label: "Clues", tint: .saveSky),
        SaveOpeningStep(icon: "checklist", label: "Review", tint: .saveHoney),
        SaveOpeningStep(icon: "mappin.and.ellipse", label: "Map", tint: .saveMint)
    ]

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                SaveOpeningLogoMark(isBreathing: isBreathing, reduceMotion: reduceMotion)

                VStack(spacing: 12) {
                    Text(languageSettings.text(.opening))
                        .font(.title3.weight(.black))
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
}

private struct SaveOpeningStep: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let tint: Color
}

private struct SaveOpeningLogoMark: View {
    var isBreathing: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            SaveOpeningScrapbookCard(fill: .saveSky, rotation: -10, offset: CGSize(width: -42, height: 28))
            SaveOpeningScrapbookCard(fill: .saveHoney, rotation: 9, offset: CGSize(width: 38, height: 18))
            SaveOpeningScrapbookCard(fill: .savePink, rotation: 3, offset: CGSize(width: 8, height: 42))

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
            SaveOpeningSpark(systemImage: "link", fill: .saveSky, offset: CGSize(width: -76, height: -34))
            SaveOpeningSpark(systemImage: "heart.fill", fill: .savePink, offset: CGSize(width: 76, height: 50))
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
            .font(.caption.weight(.black))
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
                .font(.caption.weight(.black))
            Text(step.label)
                .font(.caption.weight(.black))
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
                .fill(Color.saveCoral)
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
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @State private var email = ""
    @State private var showEmailCode = false
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorTitle = "Can't Sign In"
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                SignInHero()
                    .padding(.horizontal, 24)

                Spacer(minLength: 22)

                SignInWorkflowStrip()
                    .padding(.horizontal, 22)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    appleSignInButton
                    googleSignInButton
                    emailSignInSection
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
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
        print("SAV-E sign-in failed: \(rawMessage)")

        if rawMessage.contains("disallowed_login_method") || rawMessage.contains("not allowed") {
            errorTitle = languageSettings.text(.googleNotEnabled)
            errorMessage = languageSettings.text(.googleNotEnabledMessage)
        } else if rawMessage.contains("invalid_native_app_id") {
            errorTitle = languageSettings.text(.appNotAllowed)
            errorMessage = languageSettings.text(.appNotAllowedMessage)
        } else if rawMessage.contains("Invalid app client ID") {
            errorTitle = languageSettings.text(.authSetupNeeded)
            errorMessage = "Check the iOS client ID in Privy and try again."
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
                    isDisabled: email.isEmpty || isLoading
                ) {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do {
                            try await authService.signInWithEmail(email)
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
                    isDisabled: verificationCode.isEmpty || isLoading
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
    @EnvironmentObject private var languageSettings: AppLanguageSettings

    var body: some View {
        VStack(spacing: 18) {
            MemoMascotMark(size: 132)

            VStack(spacing: 8) {
                Text(languageSettings.text(.appName))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.saveInk)

                Text(languageSettings.text(.signInTagline))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.saveInk)

                Text(languageSettings.text(.signInDescription))
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundColor(.saveInk.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SignInWorkflowStrip: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings

    private var steps: [(String, String, Color)] {
        [
            (languageSettings.text(.capture), languageSettings.text(.captureSubtitle), .saveHoney),
            (languageSettings.text(.review), languageSettings.text(.reviewSubtitle), .saveSky),
            (languageSettings.text(.save), languageSettings.text(.saveSubtitle), .saveMint),
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { index in
                WorkflowStepCard(
                    title: steps[index].0,
                    subtitle: steps[index].1,
                    tint: steps[index].2
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture links or media, review with evidence, remember confirmed places.")
    }
}

private struct WorkflowStepCard: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
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
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SignInInputRow: View {
    let placeholder: String
    @Binding var text: String
    let buttonTitle: String
    let keyboardType: UIKeyboardType
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(keyboardType == .emailAddress ? .emailAddress : .oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.saveInk)

            Button(buttonTitle, action: action)
                .font(.subheadline.weight(.black))
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
