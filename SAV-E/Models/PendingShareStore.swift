import Foundation

/// App Group payload written by the Clip at “Save to my Savvy” tap time.
/// The full app reads `pendingShare` on first launch, auto-saves, then clears.
struct PendingSharePayload: Codable, Equatable {
    enum Kind: String, Codable {
        case place
        case list
    }

    var kind: Kind
    var shareCode: String?
    var placeId: String?
    var listId: String?
    var sender: String?
    var url: String

    /// Auto-save only the place the Clip journal actually confirmed.
    /// A leftover failed/cancelled journal, or a list payload, must not
    /// save an unrelated `/p` launch.
    func matchesIncomingPlace(url: URL) -> Bool {
        guard kind == .place else { return false }
        if Self.normalizedLink(self.url) == Self.normalizedLink(url.absoluteString) {
            return true
        }
        let incomingToken = Self.pathToken(url.absoluteString)
        if let shareCode, !shareCode.isEmpty,
           incomingToken.caseInsensitiveCompare(shareCode) == .orderedSame {
            return true
        }
        if let placeId, !placeId.isEmpty,
           incomingToken.caseInsensitiveCompare(placeId) == .orderedSame {
            return true
        }
        return false
    }

    private static func normalizedLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return trimmed.lowercased() }
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return (components.string ?? trimmed).lowercased()
    }

    private static func pathToken(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return "" }
        return url.path.split(separator: "/").last.map(String.init) ?? ""
    }
}

enum PendingShareStore {
    static let suiteName = "group.com.wanderly.app"
    static let key = "pendingShare"
    static let legacyURLKey = "pendingFriendShareURL"

    static func defaults(_ store: UserDefaults? = nil) -> UserDefaults? {
        store ?? UserDefaults(suiteName: suiteName)
    }

    static func write(_ payload: PendingSharePayload, to store: UserDefaults? = nil) {
        guard let defaults = defaults(store),
              let data = try? JSONEncoder().encode(payload),
              data.count <= 8 * 1024
        else { return }
        defaults.set(data, forKey: key)
    }

    static func load(from store: UserDefaults? = nil) -> PendingSharePayload? {
        guard let defaults = defaults(store) else { return nil }
        if let data = defaults.data(forKey: key),
           let payload = try? JSONDecoder().decode(PendingSharePayload.self, from: data),
           !payload.url.isEmpty {
            return payload
        }
        if let raw = defaults.string(forKey: key),
           let data = raw.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PendingSharePayload.self, from: data),
           !payload.url.isEmpty {
            return payload
        }
        return nil
    }

    /// Missing `pendingShare` falls back to the pre-v2 URL key.
    static func loadURL(from store: UserDefaults? = nil) -> URL? {
        if let payload = load(from: store), let url = URL(string: payload.url) {
            return url
        }
        guard let defaults = defaults(store),
              let raw = defaults.string(forKey: legacyURLKey),
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    static func clear(_ store: UserDefaults? = nil) {
        guard let defaults = defaults(store) else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyURLKey)
    }
}
