import AuthenticationServices
import Foundation

enum ClipAppleCredentialState: Equatable, Sendable {
    case authorized
    case unavailable
}

enum ClipSignInCarryOverOutcome: Equatable, Sendable {
    /// Skip `SignInView` and restore the Privy session.
    case skipSignIn
    /// Show the normal sign-in screen.
    case showSignIn
}

enum ClipSignInCarryOver {
    static func decide(
        storedAppleUserID: String?,
        credentialState: ClipAppleCredentialState?
    ) -> ClipSignInCarryOverOutcome {
        guard let storedAppleUserID,
              !storedAppleUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .showSignIn }
        return credentialState == .authorized ? .skipSignIn : .showSignIn
    }

    static func map(_ state: ASAuthorizationAppleIDProvider.CredentialState) -> ClipAppleCredentialState {
        state == .authorized ? .authorized : .unavailable
    }
}

/// Backend has no Apple-id → session route (`resolveUserId` accepts Privy JWTs only).
enum ClipAppleSessionExchange {
    static func exchange(appleUserID: String) async -> String? {
        let trimmed = appleUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nil
    }
}

enum ClipAppleCredentialClient {
    static func state(forUserID userID: String) async -> ClipAppleCredentialState {
        do {
            let state = try await ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID)
            return ClipSignInCarryOver.map(state)
        } catch {
            return .unavailable
        }
    }
}

/// Follow-up Sign in with Apple after `getCredentialState == .authorized`.
/// Requests no name or email, so Apple normally shows no name/email sheet.
enum ClipAppleSilentAuth {
    static func makeRequest() -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        return request
    }
}

struct ClipSignInCarryOverController {
    var loadAppleUserID: () -> String?
    var credentialState: (String) async -> ClipAppleCredentialState
    var restoreSession: () async throws -> Void

    func run() async -> ClipSignInCarryOverOutcome {
        let userID = loadAppleUserID()
        let state: ClipAppleCredentialState?
        if let userID {
            state = await credentialState(userID)
        } else {
            state = nil
        }
        guard ClipSignInCarryOver.decide(storedAppleUserID: userID, credentialState: state) == .skipSignIn else {
            return .showSignIn
        }
        do {
            try await restoreSession()
            return .skipSignIn
        } catch {
            return .showSignIn
        }
    }
}
