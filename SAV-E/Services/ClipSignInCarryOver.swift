import Foundation

/// A legacy Clip Apple identifier is not a Privy session. Always use the
/// full App's normal sign-in; pending share evidence remains unconfirmed.
enum ClipSignInCarryOver {
    static func requiresFullAppSignIn(hasAuthenticatedSession: Bool) -> Bool {
        !hasAuthenticatedSession
    }
}
