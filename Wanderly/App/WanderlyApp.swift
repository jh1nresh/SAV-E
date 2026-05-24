import SwiftUI

@main
struct WanderlyApp: App {
    @StateObject private var authService = PrivyAuthService.shared
    @StateObject private var languageSettings = AppLanguageSettings()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var openedTrip: SharedTripData?

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
            .preferredColorScheme(.light)
            .onOpenURL(perform: handleIncomingURL)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleIncomingURL(url)
            }
            .alert(languageSettings.text(.tripLinkReady), isPresented: Binding(
                get: { openedTrip != nil },
                set: { if !$0 { openedTrip = nil } }
            )) {
                Button(languageSettings.text(.ok)) { openedTrip = nil }
            } message: {
                if let openedTrip {
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
        guard isTripLink(url),
              let trip = SharedTripData.from(url: url) else {
            return
        }
        openedTrip = trip
    }

    private func isTripLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "trip" {
            return true
        }
        return url.scheme == "https" &&
            url.host == "wanderly.app" &&
            url.path == "/trip"
    }
}

// MARK: - Auth Loading View

struct AuthLoadingView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.saveInk)
                Text(languageSettings.text(.opening))
                    .font(.headline)
                    .foregroundColor(.saveInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
