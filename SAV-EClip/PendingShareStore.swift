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
    var confirmedPlaceIds: [String]? = nil
    var confirmedPlaces: [PendingConfirmedPlace]? = nil
}

/// Compact list snapshot written at “save all” tap. The full app stamps
/// these rows after SIWA / handoff and must not re-fetch the live list.
struct PendingConfirmedPlace: Codable, Equatable {
    var placeId: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var sourceURL: String?
    var extraPlaceIds: [String]? = nil
}

enum PendingShareStore {
    static let suiteName = "group.com.wanderly.app"
    static let key = "pendingShare"
    static let legacyURLKey = "pendingFriendShareURL"

    static func defaults(_ store: UserDefaults? = nil) -> UserDefaults? {
        store ?? UserDefaults(suiteName: suiteName)
    }

    @discardableResult
    static func write(_ payload: PendingSharePayload, to store: UserDefaults? = nil) -> Bool {
        guard let defaults = defaults(store),
              let data = try? JSONEncoder().encode(payload),
              data.count <= journalByteLimit
        else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    static let journalByteLimit = 256 * 1024

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
