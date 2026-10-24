import AuthenticationServices
import Foundation
import UIKit

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
        // HoP 2026-10-24: an empty Apple Privy duplicate is tolerated
        // pre-launch. Clip journals must land on the phone/email Privy
        // session, so never skip SignInView with an Apple identity token.
        _ = storedAppleUserID
        _ = credentialState
        return .showSignIn
    }

    static func map(_ state: ASAuthorizationAppleIDProvider.CredentialState) -> ClipAppleCredentialState {
        state == .authorized ? .authorized : .unavailable
    }
}

struct ClipAppleLinkedSession: Equatable, Sendable {
    let privyUserId: String
    let identityToken: String
}

enum ClipAppleSessionError: Error {
    case failed
}

/// Exchanges a follow-up Apple identity token for the linked Privy DID.
enum ClipAppleSessionExchange {
    struct Dependencies: Sendable {
        var requestIdentityToken: @Sendable () async throws -> String
        var resolvePrivyUserId: @Sendable (String) async throws -> String

        static let live = Dependencies(
            requestIdentityToken: { try await ClipAppleSilentAuth.requestIdentityToken() },
            resolvePrivyUserId: { try await ClipAppleSessionClient.resolvePrivyUserId(identityToken: $0) }
        )
    }

    static func exchange(
        appleUserID: String,
        dependencies: Dependencies = .live
    ) async -> ClipAppleLinkedSession? {
        let trimmed = appleUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let token = try await dependencies.requestIdentityToken()
            let privyUserId = try await dependencies.resolvePrivyUserId(token)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, privyUserId.hasPrefix("did:privy:") else { return nil }
            return ClipAppleLinkedSession(privyUserId: privyUserId, identityToken: token)
        } catch {
            return nil
        }
    }
}

enum ClipAppleSessionClient {
    static func resolvePrivyUserId(identityToken: String) async throws -> String {
        let base = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"])
            ?? SAVEProductionConfig.defaultAPIBaseURL
        guard let url = URL(string: "\(base)/v0/clip-apple-session") else {
            throw ClipAppleSessionError.failed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClipAppleSessionError.failed
        }
        let payload = try JSONDecoder().decode(ClipAppleSessionPayload.self, from: data)
        let privyUserId = payload.privyUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard privyUserId.hasPrefix("did:privy:") else { throw ClipAppleSessionError.failed }
        return privyUserId
    }
}

private struct ClipAppleSessionPayload: Decodable {
    let privyUserId: String

    enum CodingKeys: String, CodingKey {
        case privyUserId = "privy_user_id"
    }
}

enum ClipAppleIdentityToken {
    static func isExpired(_ token: String, now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiration = expiration(of: token) else { return true }
        return now.addingTimeInterval(leeway) >= expiration
    }

    static func expiration(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let exp = json["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = json["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        if let exp = json["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: exp.doubleValue)
        }
        return nil
    }
}

enum ClipAppleCredentialClient {
    static func state(forUserID userID: String) async -> ClipAppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if error != nil {
                    continuation.resume(returning: .unavailable)
                    return
                }
                continuation.resume(returning: ClipSignInCarryOver.map(state))
            }
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

    static func requestIdentityToken() async throws -> String {
        try await ClipAppleSilentAuthController().perform()
    }
}

final class ClipAppleSilentAuthController: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?
    private static var retained: ClipAppleSilentAuthController?

    func perform() async throws -> String {
        Self.retained = self
        defer { Self.retained = nil }
        let request = ClipAppleSilentAuth.makeRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty
        else {
            continuation?.resume(throwing: ClipAppleSessionError.failed)
            continuation = nil
            return
        }
        continuation?.resume(returning: token)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
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
