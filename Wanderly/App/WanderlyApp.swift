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
            .preferredColorScheme(nil) // Respect system setting
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
            Text("Opening Wanderly")
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
        VStack(spacing: 32) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.wanderlyTerracotta)

                Text("Wanderly")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.wanderlyCharcoal)

                Text("Your places, your map, your adventures")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Auth buttons
            VStack(spacing: 12) {
                SignInWithAppleButton {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do { try await authService.signInWithApple() }
                        catch { presentAuthError(error) }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .cornerRadius(16)

                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do { try await authService.signInWithGoogle() }
                        catch { presentAuthError(error) }
                    }
                }) {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Continue with Google")
                    }
                    .font(.headline)
                    .foregroundColor(.wanderlyCharcoal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                }

                // Divider
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("or").font(.caption).foregroundColor(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }

                // Email
                if !showEmailCode {
                    HStack {
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        Button("Send Code") {
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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.wanderlyTerracotta)
                        .disabled(email.isEmpty || isLoading)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 2)
                } else {
                    HStack {
                        TextField("Verification code", text: $verificationCode)
                            .keyboardType(.numberPad)

                        Button("Verify") {
                            Task {
                                isLoading = true
                                defer { isLoading = false }
                                do { try await authService.verifyEmailCode(verificationCode) }
                                catch { presentAuthError(error) }
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.wanderlyTerracotta)
                        .disabled(verificationCode.isEmpty)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            if isLoading {
                ProgressView()
                    .tint(.wanderlyTerracotta)
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
        print("Wanderly sign-in failed: \(rawMessage)")

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
}
