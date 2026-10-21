import Foundation

enum ClipListSaveFailure: Equatable, Sendable {
    case unconfirmed
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
            "id": stablePlaceID(item),
            "name": item.name,
            "address": item.address,
            "latitude": item.latitude,
            "longitude": item.longitude,
            "category": categoryRaw(item.category),
            "status": "wantToGo",
            "source_platform": "other",
        ]
        if let rating = item.rating { body["rating"] = rating }
        if let note = item.note { body["note"] = note }
        if let sourceURL = item.sourceURL { body["source_url"] = sourceURL }
        if let placeId = item.placeId, !placeId.isEmpty { body["provider_place_id"] = placeId }
        return body
    }

    private static func stablePlaceID(_ item: ClipListSaveItem) -> String {
        if let placeId = item.placeId, UUID(uuidString: placeId) != nil {
            return placeId.lowercased()
        }
        return UUID().uuidString.lowercased()
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
