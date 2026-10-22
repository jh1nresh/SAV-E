import Foundation

enum ClipListSaveFailure: Error, Equatable, Sendable {
    case unconfirmed
}

enum ClipSignInKind: Equatable, Sendable {
    case onePlace
    case wholeList(Int)

    var titleKey: String {
        switch self {
        case .onePlace: return "clip.signin.saveOne"
        case .wholeList: return "clip.signin.saveCount"
        }
    }

    var placeCount: Int {
        switch self {
        case .onePlace: return 1
        case .wholeList(let count): return count
        }
    }
}

enum ClipListSwipeHint {
    static let key = "clipListSwipeHintDismissed"
    /// App Group suite. Named here so this Foundation-only file can
    /// compile into SAVETests without the Clip store type.
    static let suiteName = "group.com.wanderly.app"

    static func defaults(_ store: UserDefaults? = nil) -> UserDefaults? {
        store ?? UserDefaults(suiteName: suiteName)
    }

    static func isDismissed(in store: UserDefaults? = nil) -> Bool {
        defaults(store)?.bool(forKey: key) == true
    }

    static func dismiss(in store: UserDefaults? = nil) {
        defaults(store)?.set(true, forKey: key)
    }

    static func reset(in store: UserDefaults? = nil) {
        defaults(store)?.removeObject(forKey: key)
    }

    static func shouldShow(pageIndex: Int, pageCount: Int, dismissed: Bool) -> Bool {
        pageIndex == 0 && pageCount > 1 && !dismissed
    }
}

struct ClipListSaveCounts: Equatable, Sendable {
    var newlySaved: Int
    var alreadySaved: Int
    var overCap: Int
    var remaining: Int
    var limit: Int

    static let freeLimit = 50

    var addedAnything: Bool { newlySaved > 0 }
}

struct ClipListSaveItem: Equatable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var rating: Double?
    var note: String?
    var sourceURL: String?
    var placeId: String?
}

enum ClipListSavePlanner {
    static func uniqueItems(from items: [ClipListSaveItem]) -> [ClipListSaveItem] {
        var seen = Set<String>()
        var unique: [ClipListSaveItem] = []
        for item in items {
            let keys = identities(of: item)
            guard !keys.isEmpty, !keys.contains(where: { seen.contains($0) }) else { continue }
            keys.forEach { seen.insert($0) }
            unique.append(item)
        }
        return unique
    }

    static func identity(of item: ClipListSaveItem) -> String {
        identities(of: item).first ?? ""
    }

    static func identities(of item: ClipListSaveItem) -> [String] {
        var keys: [String] = []
        if let placeId = item.placeId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !placeId.isEmpty {
            keys.append("id:\(placeId)")
        }
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty {
            keys.append("n:\(name)|\(coordinateToken(item.latitude))|\(coordinateToken(item.longitude))")
        }
        return keys
    }

    static func requestBody(items: [ClipListSaveItem]) -> [String: Any] {
        ["places": uniqueItems(from: items).map(placeBody(from:))]
    }

    /// After SIWA, save the shop the user tapped — not `list.items[listPage]`.
    /// Off-screen `PreferenceKey` children can last-write `listPage` back to 0.
    static func onePlaceItem(
        pending: ClipListSaveItem?,
        pageItem: ClipListSaveItem?
    ) -> ClipListSaveItem? {
        pending ?? pageItem
    }

    /// Only a currently visible page may move the tracked index.
    static func visiblePage(current: Int, incoming: Int?) -> Int {
        incoming ?? current
    }

    /// After the user confirms “save all”, POST only that snapshot.
    /// `liveList` is the owner’s current server list and must never replace
    /// a shop the user already confirmed, or add one they never saw.
    static func itemsToSave(
        confirmed: [ClipListSaveItem],
        liveList: [ClipListSaveItem]
    ) -> [ClipListSaveItem] {
        _ = liveList
        return uniqueItems(from: confirmed)
    }

    static func allocate(
        novelCount: Int,
        alreadySaved: Int,
        savedPlaceCount: Int,
        limit: Int = ClipListSaveCounts.freeLimit
    ) -> ClipListSaveCounts {
        let remainingSlots = max(0, limit - savedPlaceCount)
        let newlySaved = min(max(0, novelCount), remainingSlots)
        return ClipListSaveCounts(
            newlySaved: newlySaved,
            alreadySaved: alreadySaved,
            overCap: max(0, novelCount - newlySaved),
            remaining: remainingSlots - newlySaved,
            limit: limit
        )
    }

    static func parseCounts(status: Int, body: [String: Any]) -> ClipListSaveCounts? {
        guard (200...299).contains(status) else { return nil }
        guard let newlySaved = intValue(body, keys: ["newly_saved", "saved", "created"]),
              let alreadySaved = intValue(body, keys: ["already_saved", "duplicates"]),
              let overCap = intValue(body, keys: ["over_cap", "cap_reached", "over_free_limit_count"])
        else { return nil }
        return ClipListSaveCounts(
            newlySaved: newlySaved,
            alreadySaved: alreadySaved,
            overCap: overCap,
            remaining: intValue(body, keys: ["remaining", "remaining_count"]) ?? 0,
            limit: intValue(body, keys: ["limit"]) ?? ClipListSaveCounts.freeLimit
        )
    }

    static func parseCounts(status: Int, data: Data) -> ClipListSaveCounts? {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return parseCounts(status: status, body: body)
    }

    static func parseOutcome(status: Int, data: Data) -> Result<ClipListSaveCounts, ClipListSaveFailure> {
        if let counts = parseCounts(status: status, data: data) {
            return .success(counts)
        }
        return .failure(.unconfirmed)
    }

    static func placeBody(from item: ClipListSaveItem) -> [String: Any] {
        var body: [String: Any] = [
            "id": recipientOwnedPlaceID(),
            "name": item.name,
            "address": item.address,
            "latitude": item.latitude,
            "longitude": item.longitude,
            "category": categoryRaw(item.category),
            "status": "wantToGo",
            "source_platform": "other",
        ]
        if let sourceURL = item.sourceURL { body["source_url"] = sourceURL }
        if let placeId = item.placeId, !placeId.isEmpty { body["provider_place_id"] = placeId }
        return body
    }

    /// Fresh row id. Source UUIDs stay in `provider_place_id` so a copy
    /// never collides with the owner's `places.id`.
    private static func recipientOwnedPlaceID() -> String {
        UUID().uuidString.lowercased()
    }

    private static func coordinateToken(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func intValue(_ body: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = body[key] as? Int { return value }
            if let value = body[key] as? NSNumber { return value.intValue }
        }
        return nil
    }

    private static func categoryRaw(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("cafe") || lower.contains("coffee") || lower.contains("咖啡") { return "cafe" }
        if lower.contains("bar") || lower.contains("酒") { return "bar" }
        if lower.contains("stay") || lower.contains("hotel") || lower.contains("宿") { return "stay" }
        if lower.contains("shop") || lower.contains("購") { return "shopping" }
        if lower.contains("attraction") || lower.contains("museum") || lower.contains("景") { return "attraction" }
        return "food"
    }
}
