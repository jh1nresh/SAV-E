import SwiftUI

@main
struct WanderlyApp: App {
    @StateObject private var authService = PrivyAuthService.shared
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
            .preferredColorScheme(.light)
            .onOpenURL(perform: handleIncomingURL)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleIncomingURL(url)
            }
            .alert("Trip Link Ready", isPresented: Binding(
                get: { openedTrip != nil },
                set: { if !$0 { openedTrip = nil } }
            )) {
                Button("OK") { openedTrip = nil }
            } message: {
                if let openedTrip {
                    Text("\(openedTrip.name) has \(openedTrip.stops.count) stops. Full trip import is coming next.")
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
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.wanderlyTerracotta)
            Text("Opening SAV-E")
                .font(.headline)
                .foregroundColor(.wanderlyCharcoal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wanderlyCream)
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @EnvironmentObject var authService: PrivyAuthService
    @State private var email = ""
    @State private var showEmailCode = false
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorTitle = "Can't Sign In"
    @State private var errorMessage: String?

    var body: some View {
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
        .overlay(alignment: .bottom) {
            if isLoading {
                ProgressView()
                    .tint(.wanderlyTerracotta)
                    .padding(.bottom, 10)
            }
        }
        .background(Color.wanderlyCream)
        .alert(errorTitle, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func presentAuthError(_ error: Error) {
        let rawMessage = error.localizedDescription
        print("SAV-E sign-in failed: \(rawMessage)")

        if rawMessage.contains("disallowed_login_method") || rawMessage.contains("not allowed") {
            errorTitle = "Google Isn't Enabled"
            errorMessage = "Turn on Google in Privy, or use email sign-in for now."
        } else if rawMessage.contains("invalid_native_app_id") {
            errorTitle = "App Not Allowed"
            errorMessage = "Add com.wanderly.app to the allowed app identifiers in Privy."
        } else if rawMessage.contains("Invalid app client ID") {
            errorTitle = "Auth Setup Needed"
            errorMessage = "Check the iOS client ID in Privy and try again."
        } else if rawMessage.contains("Missing Privy config") {
            errorTitle = "Auth Setup Needed"
            errorMessage = rawMessage
        } else {
            errorTitle = "Can't Sign In"
            errorMessage = "Something went wrong. Try again in a moment."
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
                Text("Continue with Google")
            }
            .font(.headline)
            .foregroundColor(.wanderlyCharcoal)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var emailSignInSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.wanderlyTerracotta.opacity(0.14))
                    .frame(height: 1)
                Text("or use email")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.wanderlyTerracotta.opacity(0.14))
                    .frame(height: 1)
            }

            if !showEmailCode {
                SignInInputRow(
                    placeholder: "Email address",
                    text: $email,
                    buttonTitle: "Send Code",
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
                    placeholder: "Verification code",
                    text: $verificationCode,
                    buttonTitle: "Verify",
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
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.wanderlyTerracotta.opacity(0.10))
                    .frame(width: 96, height: 96)

                Image(systemName: "map.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundColor(.wanderlyTerracotta)
            }

            VStack(spacing: 8) {
                Text("SAV-E")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.wanderlyCharcoal)

                Text("Your personal place agent.")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.wanderlyCharcoal)

                Text("Send links, posts, screenshots, notes, or maps. SAV-E investigates first, then asks before saving.")
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SignInWorkflowStrip: View {
    private let steps: [(String, String, Color)] = [
        ("Capture", "link or media", .wanderlyTerracotta),
        ("Review", "with evidence", Color(hex: "5B8FA8")),
        ("Remember", "confirmed places", Color(hex: "8B5E83")),
    ]

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
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.wanderlyCharcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
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
                .foregroundColor(.wanderlyCharcoal)

            Button(buttonTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isDisabled ? .secondary : .wanderlyTerracotta)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.white.opacity(0.86))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
