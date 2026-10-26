import Foundation

/// Apple user id the Clip writes after Sign in with Apple.
/// Shared App Group only; never a JWT, identity token, or Privy session.
enum ClipAppleAccountStore {
    static let suiteName = PendingShareStore.suiteName
    static let key = "clipAppleUserID"

    static func defaults(_ store: UserDefaults? = nil) -> UserDefaults? {
        store ?? UserDefaults(suiteName: suiteName)
    }

    static func read(from store: UserDefaults? = nil) -> String? {
        guard let value = defaults(store)?.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ userID: String, to store: UserDefaults? = nil) {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults(store)?.set(trimmed, forKey: key)
    }

    static func clear(_ store: UserDefaults? = nil) {
        defaults(store)?.removeObject(forKey: key)
    }
}
