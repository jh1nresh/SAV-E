import CoreLocation
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
    var extraPlaceIds: [String] = []
    var coordinateSystem: String? = nil
    var locationProvider: String? = nil
    var providerMapURL: String? = nil
    var googlePlaceId: String? = nil
}

/// Presentation decisions shared with the real Clip view and its unit tests.
enum ClipPreviewPolicy {
    static func senderLabel(_ value: String?) -> String? {
        let label = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !label.isEmpty, label.caseInsensitiveCompare("Shared list") != .orderedSame else { return nil }
        return label
    }
}

struct ClipOverlayPresentationState {
    enum Action: Equatable { case none, present, dismiss }
    private(set) var didPresent = false

    mutating func update(requested: Bool, hasScene: Bool) -> Action {
        if !requested {
            guard didPresent else { return .none }
            didPresent = false
            return .dismiss
        }
        guard !didPresent, hasScene else { return .none }
        didPresent = true
        return .present
    }
}

enum ClipListSavePlanner {
    static func uniqueItems(from items: [ClipListSaveItem]) -> [ClipListSaveItem] {
        var indexByKey: [String: Int] = [:]
        var unique: [ClipListSaveItem] = []
        for item in items {
            let keys = identities(of: item)
            guard !keys.isEmpty else { continue }
            var matchedIndexes = Set(keys.compactMap { indexByKey[$0] })
            for (index, existing) in unique.enumerated() where isNearbyDuplicate(item, existing) {
                matchedIndexes.insert(index)
            }
            let matched = matchedIndexes.sorted()
            if matched.isEmpty {
                let index = unique.count
                unique.append(item)
                for key in keys { indexByKey[key] = index }
                continue
            }
            let keep = matched[0]
            var merged = mergingIdentities(unique[keep], item)
            for other in matched.dropFirst() {
                merged = mergingIdentities(merged, unique[other])
            }
            unique[keep] = merged
            if matched.count == 1 {
                for key in identities(of: merged) { indexByKey[key] = keep }
                continue
            }
            let remove = Set(matched.dropFirst())
            unique = unique.enumerated().compactMap { remove.contains($0.offset) ? nil : $0.element }
            indexByKey = [:]
            for (index, remaining) in unique.enumerated() {
                for key in identities(of: remaining) { indexByKey[key] = index }
            }
        }
        return unique
    }

    static func mergingIdentities(_ kept: ClipListSaveItem, _ incoming: ClipListSaveItem) -> ClipListSaveItem {
        var result = kept
        var extras = Set(
            kept.extraPlaceIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        if let incomingId = incoming.placeId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !incomingId.isEmpty {
            if let keptId = result.placeId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !keptId.isEmpty {
                if keptId.caseInsensitiveCompare(incomingId) != .orderedSame {
                    extras.insert(incomingId)
                }
            } else {
                result.placeId = incomingId
            }
        }
        for extra in incoming.extraPlaceIds {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               result.placeId?.caseInsensitiveCompare(trimmed) != .orderedSame {
                extras.insert(trimmed)
            }
        }
        for google in [kept.googlePlaceId, incoming.googlePlaceId].compactMap({ $0 }) {
            if google != result.placeId { extras.insert(google) }
        }
        result.googlePlaceId = kept.googlePlaceId ?? incoming.googlePlaceId
        result.extraPlaceIds = extras.sorted()
        if result.coordinateSystem == nil { result.coordinateSystem = incoming.coordinateSystem }
        if result.locationProvider == nil { result.locationProvider = incoming.locationProvider }
        if result.providerMapURL == nil { result.providerMapURL = incoming.providerMapURL }
        return result
    }

    static func identity(of item: ClipListSaveItem) -> String {
        identities(of: item).first ?? ""
    }

    static func identities(of item: ClipListSaveItem) -> [String] {
        var keys: [String] = []
        var placeIds: [String] = []
        if let placeId = item.placeId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !placeId.isEmpty {
            placeIds.append(placeId)
        }
        for extra in item.extraPlaceIds + [item.googlePlaceId].compactMap({ $0 }) {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty { placeIds.append(trimmed) }
        }
        for placeId in placeIds {
            keys.append("id:\(placeId)")
            keys.append("p:\(placeId)")
            keys.append("g:\(placeId)")
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

    /// Friend-share receipts stay on the scalar `/places` path. Every other
    /// one-place Clip save must use the quota/dedupe planner (`{ places: [] }`).
    static func onePlacePayload(item: ClipListSaveItem, friendShareCode: String?) -> [String: Any] {
        let code = friendShareCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty {
            var body = placeBody(from: item)
            body["friend_share_code"] = code
            return body
        }
        return requestBody(items: [item])
    }

    enum OnePlaceResult: Equatable, Sendable {
        case saved
        case duplicate
        case capReached
        case failed
    }

    /// A 2xx list body is not Saved unless `newly_saved > 0`.
    static func onePlaceResult(status: Int, data: Data) -> OnePlaceResult? {
        guard let counts = parseCounts(status: status, data: data) else { return nil }
        if counts.newlySaved > 0 { return .saved }
        if counts.overCap > 0 { return .capReached }
        if counts.alreadySaved > 0 { return .duplicate }
        return .failed
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

    /// Journal write is the App Group fallback. Do not report handoff if it failed.
    static func handoffAfterPersist(written: Bool, opened: Bool) -> Bool {
        written && opened
    }

    /// Full-app list links are rejected above 8 KiB. Prefer a short-code
    /// handoff so the journal can still be consumed.
    static let fullAppListURLMaxBytes = 8 * 1024

    static func compactHandoffURL(
        incoming: URL?,
        shareCode: String?,
        listId: String?
    ) -> URL {
        _ = listId
        let code = (shareCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty, let url = URL(string: "https://sav-e-app.vercel.app/list?c=\(code)") {
            return url
        }
        if let incoming, incoming.absoluteString.utf8.count <= fullAppListURLMaxBytes {
            return incoming
        }
        return URL(string: "https://sav-e-app.vercel.app/list")!
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
        let extras = item.extraPlaceIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let google = item.googlePlaceId ?? ([item.placeId ?? ""] + extras).first(where: isGooglePlaceID) {
            body["google_place_id"] = google
        }
        if !extras.isEmpty { body["extra_place_ids"] = extras }
        if let system = item.coordinateSystem, !system.isEmpty { body["coordinate_system"] = system }
        if let provider = item.locationProvider, !provider.isEmpty { body["location_provider"] = provider }
        if let mapURL = item.providerMapURL, !mapURL.isEmpty { body["provider_map_url"] = mapURL }
        return body
    }

    static func isGooglePlaceID(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, UUID(uuidString: value) == nil else { return false }
        let lowered = value.lowercased()
        return lowered.hasPrefix("chij")
            || lowered.hasPrefix("ghij")
            || lowered.hasPrefix("eic")
            || lowered.hasPrefix("iho")
    }

    /// Fresh row id. Source UUIDs stay in `provider_place_id` so a copy
    /// never collides with the owner's `places.id`.
    private static func recipientOwnedPlaceID() -> String {
        UUID().uuidString.lowercased()
    }

    static func isNearbyDuplicate(_ left: ClipListSaveItem, _ right: ClipListSaveItem) -> Bool {
        let leftName = left.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rightName = right.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !leftName.isEmpty, leftName == rightName else { return false }
        return CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude)) < 120
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
