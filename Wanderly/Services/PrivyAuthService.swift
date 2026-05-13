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

    var errorDescription: String? {
        switch self {
        case .signInFailed(let reason): return "Sign in failed: \(reason)"
        case .invalidCode: return "No pending email — call signInWithEmail first"
        case .missingPrivyConfig(let key): return "Missing Privy config: \(key)"
        }
    }
}

// MARK: - Privy Auth Service

@MainActor
final class PrivyAuthService: ObservableObject {
    static let shared = PrivyAuthService()

    let privy: Privy
    @Published var authState: AuthState = .unknown
    private var pendingEmail: String?
    private let appId: String
    private let clientId: String
    private var authStateTask: Task<Void, Never>?

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    var currentUserId: String? {
        if case .authenticated(let userId) = authState { return userId }
        return nil
    }

    private init() {
        let appId = Self.keyFromPlist("PRIVY_APP_ID") ?? ""
        let clientId = Self.keyFromPlist("PRIVY_APP_CLIENT_ID") ?? ""
        self.appId = appId
        self.clientId = clientId
        let config   = PrivyConfig(appId: appId, appClientId: clientId)
        self.privy   = PrivySdk.initialize(config: config)

        observeAuthState()
        Task { await restoreSession() }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Session Restore

    func restoreSession() async {
        let state = await privy.getAuthState()
        applyPrivyState(state)
    }

    private func observeAuthState() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.privy.authStateStream {
                self.applyPrivyState(state)
            }
        }
    }

    // MARK: - Apple

    func signInWithApple() async throws {
        try validateConfig()
        let user = try await privy.oAuth.login(with: .apple)
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Google

    func signInWithGoogle() async throws {
        try validateConfig()
        let user = try await privy.oAuth.login(with: .google)
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Email OTP

    func signInWithEmail(_ email: String) async throws {
        try validateConfig()
        pendingEmail = email
        try await privy.email.sendCode(to: email)
    }

    func verifyEmailCode(_ code: String) async throws {
        guard let email = pendingEmail else { throw AuthError.invalidCode }
        let user = try await privy.email.loginWithCode(code, sentTo: email)
        pendingEmail = nil
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Sign Out

    func signOut() async {
        let user = await privy.getUser()
        await user?.logout()
        authState = .unauthenticated
    }

    func accessToken() async throws -> String {
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

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict[key],
              value != "YOUR_KEY_HERE",
              !value.isEmpty else { return nil }
        return value
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
