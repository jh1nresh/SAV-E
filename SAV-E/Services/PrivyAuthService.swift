import SwiftUI
import AuthenticationServices
import PrivySDK

// MARK: - Auth State

enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case authenticated(userId: String)
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case signInFailed(String)
    case invalidCode
    case missingPrivyConfig(String)
    /// Thrown by `accessToken()` while in the App Review demo session, which has
    /// no real Privy user. Callers must treat this as "no token available" and
    /// degrade to local/cached behavior — never crash or block.
    case reviewerDemoNoToken

    var errorDescription: String? {
        switch self {
        case .signInFailed(let reason): return "Sign in failed: \(reason)"
        case .invalidCode: return "No pending email — call signInWithEmail first"
        case .missingPrivyConfig(let key): return "Missing Privy config: \(key)"
        case .reviewerDemoNoToken: return "Reviewer demo session has no auth token"
        }
    }
}

// MARK: - Privy Auth Service

@MainActor
final class PrivyAuthService: ObservableObject {
    static let shared = PrivyAuthService()

    private let privy: Privy?
    @Published var authState: AuthState = .unknown
    private var pendingEmail: String?
    private let appId: String
    private let clientId: String
    private var authStateTask: Task<Void, Never>?

    // MARK: App Review Demo

    /// True while the App Review demo session is active. See `ReviewDemo`.
    private(set) var isReviewerDemo = false

    /// Anonymous backend guest token for the demo session, used so drawer search
    /// works via the LLM proxy without a real Privy JWT. Nil if the guest-session
    /// request failed (demo still proceeds local-only).
    private(set) var demoGuestToken: String?

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    var currentUserId: String? {
        if case .authenticated(let userId) = authState { return userId }
        return nil
    }

    private init() {
        let appId = SAVEProductionConfig.configValue(for: ["PRIVY_APP_ID"]) ?? ""
        let clientId = SAVEProductionConfig.configValue(for: ["PRIVY_APP_CLIENT_ID"]) ?? ""
        self.appId = appId
        self.clientId = clientId

        guard !appId.isEmpty, !clientId.isEmpty else {
            self.privy = nil
            self.authState = .unauthenticated
            return
        }

        let config = PrivyConfig(appId: appId, appClientId: clientId)
        self.privy = PrivySdk.initialize(config: config)

        observeAuthState()
        Task { await restoreSession() }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Session Restore

    func restoreSession() async {
        guard let privy else {
            authState = .unauthenticated
            return
        }
        let state = await privy.getAuthState()
        applyPrivyState(state)
    }

    private func observeAuthState() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            guard let privy = self.privy else { return }
            for await state in privy.authStateStream {
                self.applyPrivyState(state)
            }
        }
    }

    // MARK: - Apple

    func signInWithApple() async throws {
        let privy = try validatedPrivy()
        let user = try await privy.oAuth.login(with: .apple)
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Google

    func signInWithGoogle() async throws {
        let privy = try validatedPrivy()
        let user = try await privy.oAuth.login(with: .google)
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Email OTP

    func signInWithEmail(_ email: String) async throws {
        // App Review demo bypass: never send a real OTP for the demo email — it
        // would fail/spam and the reviewer can't receive it anyway. Just record
        // the pending email so the UI advances to the code field.
        if ReviewDemo.isDemoEmail(email) {
            pendingEmail = email
            return
        }
        let privy = try validatedPrivy()
        pendingEmail = email
        try await privy.email.sendCode(to: email)
    }

    func verifyEmailCode(_ code: String) async throws {
        // App Review demo bypass: the EXACT (demo email, demo code) pair enters
        // the isolated demo session instead of calling Privy. Any other email or
        // code falls through to the normal Privy flow below, unchanged.
        if let email = pendingEmail, ReviewDemo.isDemoCredentialPair(email: email, code: code) {
            pendingEmail = nil
            await enterReviewerDemo()
            return
        }
        let privy = try validatedPrivy()
        guard let email = pendingEmail else { throw AuthError.invalidCode }
        let user = try await privy.email.loginWithCode(code, sentTo: email)
        pendingEmail = nil
        authState = .authenticated(userId: user.id)
    }

    // MARK: - App Review Demo Session

    /// Enters the isolated App Review demo session: best-effort backend guest
    /// token + locally-seeded places, then flips `authState` to authenticated.
    /// Never throws — if the network call fails we still enter local-only demo so
    /// the reviewer is never blocked at the door.
    func enterReviewerDemo() async {
        isReviewerDemo = true
        demoGuestToken = await fetchGuestToken()
        ReviewDemoGuestTokenHolder.shared.set(demoGuestToken)
        seedReviewerDemoVaultIfNeeded()
        authState = .authenticated(userId: ReviewDemo.userId)
    }

    /// POST {API}/v0/guest-sessions -> { guest_token }. Returns nil on any error.
    private func fetchGuestToken() async -> String? {
        guard let apiBaseURL = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let url = URL(string: "\(apiBaseURL)/v0/guest-sessions") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["guest_token"] as? String,
                  !token.isEmpty else {
                return nil
            }
            return token
        } catch {
            return nil
        }
    }

    /// Seeds an empty production demo vault once. A DEBUG-only UI-test flag may
    /// repair missing simulator seeds without changing or clearing existing data.
    /// Best-effort: a seed failure must not block demo entry.
    private func seedReviewerDemoVaultIfNeeded() {
        let defaults = UserDefaults.standard
#if DEBUG
        let shouldRepairForUITests = ProcessInfo.processInfo.arguments.contains("--uitest-repair-review-demo-seed")
#else
        let shouldRepairForUITests = false
#endif
        let vault = SaveLocalVaultService()
        let existingPlaces = (try? vault.confirmedPlaces(limit: 500)) ?? []
        let wasSeeded = defaults.bool(forKey: ReviewDemo.seededDefaultsKey)
        guard ReviewDemoSeed.shouldSeedVault(
            existingPlaces: existingPlaces,
            wasSeeded: wasSeeded,
            repairForUITests: shouldRepairForUITests
        ) else {
            defaults.set(true, forKey: ReviewDemo.seededDefaultsKey)
            return
        }
        for place in ReviewDemoSeed.missingPlaces(from: existingPlaces) {
            _ = try? vault.saveConfirmedPlace(place)
        }
        defaults.set(true, forKey: ReviewDemo.seededDefaultsKey)
    }

    // MARK: - Sign Out

    func signOut() async {
        if isReviewerDemo {
            isReviewerDemo = false
            demoGuestToken = nil
            ReviewDemoGuestTokenHolder.shared.set(nil)
            authState = .unauthenticated
            return
        }
        guard let privy else {
            authState = .unauthenticated
            return
        }
        let user = await privy.getUser()
        await user?.logout()
        authState = .unauthenticated
    }

    func accessToken() async throws -> String {
        // The App Review demo session has no Privy user. Throw a clear, already-
        // handled error so callers degrade to local/cached behavior. The demo
        // path that needs the backend (drawer search) uses `demoGuestToken`.
        if isReviewerDemo { throw AuthError.reviewerDemoNoToken }
        let privy = try validatedPrivy()
        guard let user = await privy.getUser() else { throw AuthError.signInFailed("No authenticated user") }
        return try await user.getAccessToken()
    }

    // MARK: - Helpers

    private func applyPrivyState(_ state: PrivySDK.AuthState) {
        switch state {
        case .authenticated(let user):
            authState = .authenticated(userId: user.id)
        case .unauthenticated:
            authState = .unauthenticated
        case .notReady, .authenticatedUnverified:
            authState = .unknown
        @unknown default:
            authState = .unknown
        }
    }

    private func validateConfig() throws {
        if appId.isEmpty { throw AuthError.missingPrivyConfig("PRIVY_APP_ID") }
        if clientId.isEmpty { throw AuthError.missingPrivyConfig("PRIVY_APP_CLIENT_ID") }
    }

    private func validatedPrivy() throws -> Privy {
        try validateConfig()
        guard let privy else {
            throw AuthError.missingPrivyConfig("PRIVY_APP_ID / PRIVY_APP_CLIENT_ID")
        }
        return privy
    }
}

// MARK: - SignInWithApple Button (Privy-compatible)

struct SignInWithAppleButton: UIViewRepresentable {
    typealias UIViewType = ASAuthorizationAppleIDButton
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
