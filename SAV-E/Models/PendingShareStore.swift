import Foundation

/// Compact list snapshot written at Clip “save all” tap. Stamp only these
/// after SIWA / handoff — never the live joined list.
struct PendingConfirmedPlace: Codable, Equatable {
    var placeId: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var sourceURL: String?
    var extraPlaceIds: [String]? = nil

    func asListItem() -> SaveListItem {
        SaveListItem(
            id: UUID(),
            source: .savedPlace,
            sourceID: placeId,
            title: name,
            subtitle: address,
            latitude: latitude,
            longitude: longitude,
            category: PlaceCategory.fromClipSnapshot(category),
            rating: nil,
            reviewCount: nil,
            sourceURL: sourceURL,
            photoURLs: [],
            note: nil,
            addedByDisplayName: "",
            addedAt: Date(timeIntervalSince1970: 0),
            extraPlaceIds: extraPlaceIds
        )
    }
}

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

    /// Clip “save all” journal for this list URL. A leftover list journal
    /// must not stamp an unrelated list the user only opened.
    func matchesIncomingList(url: URL) -> Bool {
        guard kind == .list else { return false }
        if Self.normalizedLink(self.url) == Self.normalizedLink(url.absoluteString) {
            return true
        }
        let incomingCode = SaveSharedListPayload.shareCode(from: url)
            ?? Self.pathToken(url.absoluteString)
        if let shareCode, !shareCode.isEmpty,
           incomingCode.caseInsensitiveCompare(shareCode) == .orderedSame {
            return true
        }
        if let listId, !listId.isEmpty,
           url.absoluteString.range(of: listId, options: .caseInsensitive) != nil {
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

    @discardableResult
    static func write(_ payload: PendingSharePayload, to store: UserDefaults? = nil) -> Bool {
        guard let defaults = defaults(store),
              let data = try? JSONEncoder().encode(payload),
              data.count <= journalByteLimit
        else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// Matches `listMaxItems * listItemPayloadMaxBytes` so a supported list can journal.
    static let journalByteLimit = 200 * 8 * 1024

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

/// Always recompute from the incoming URL. A leftover true flag must not
/// save an unrelated `/p` that arrived before sign-in finished.
enum ClipPlaceHandoff {
    static func shouldAutoSavePlace(pending: PendingSharePayload?, incomingURL: URL) -> Bool {
        pending?.matchesIncomingPlace(url: incomingURL) == true
    }

    /// Sign-out / account switch must not stamp the previous user's pending place.
    static func shouldKeepPlaceHandoff(ownerGeneration: Int?, currentGeneration: Int) -> Bool {
        ownerGeneration == currentGeneration
    }

    /// `nil` → first user is session restoration, not an account switch.
    /// Keep the unowned Clip journal so universal-link launch can still stamp.
    static func shouldResetHandoffOnAccountChange(previousUserId: String?, currentUserId: String?) -> Bool {
        guard let previousUserId else { return false }
        return previousUserId != currentUserId
    }

    static func resetPlaceHandoffOnAccountChange() {
        PendingShareStore.clear()
    }
}

struct ClipListHandoffCounts: Equatable {
    var newlySaved: Int
    var alreadySaved: Int
    var overCap: Int
    var remaining: Int
    var limit: Int

    var addedAnything: Bool { newlySaved > 0 }
}

enum ClipListHandoffError: Error, Equatable {
    case unconfirmed
    case capReached
}

/// A matching Clip “save all” journal is user confirmation to stamp the
/// confirmed snapshot. A list link without that journal is join-only.
enum ClipListHandoff {
    static let freeLimit = 50

    static func shouldSaveItems(pending: PendingSharePayload?, incomingURL: URL) -> Bool {
        pending?.matchesIncomingList(url: incomingURL) == true
    }

    static let listURLMaxBytes = 8 * 1024

    static func compactHandoffURL(incoming: URL?, shareCode: String?, listId: String?) -> URL {
        _ = listId
        let code = (shareCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty, let url = URL(string: "https://sav-e-app.vercel.app/list?c=\(code)") {
            return url
        }
        if let incoming, incoming.absoluteString.utf8.count <= listURLMaxBytes {
            return incoming
        }
        return URL(string: "https://sav-e-app.vercel.app/list")!
    }

    /// Oversized embedded list URLs are still accepted when a matching
    /// confirmed journal exists, then rewritten to a compact handoff.
    static func acceptedListURL(pending: PendingSharePayload?, incomingURL: URL) -> URL? {
        if incomingURL.absoluteString.utf8.count <= listURLMaxBytes {
            return incomingURL
        }
        guard pending?.matchesIncomingList(url: incomingURL) == true else { return nil }
        return compactHandoffURL(
            incoming: incomingURL,
            shareCode: pending?.shareCode,
            listId: pending?.listId
        )
    }

    /// Stamp the confirmed snapshot only. `liveItems` is the joined server
    /// list after sign-in and must not add or drop shops.
    static func itemsToStamp(
        pending: PendingSharePayload?,
        incomingURL: URL,
        liveItems: [SaveListItem]
    ) -> [SaveListItem] {
        _ = liveItems
        guard shouldSaveItems(pending: pending, incomingURL: incomingURL),
              let places = pending?.confirmedPlaces, !places.isEmpty
        else { return [] }
        return places.map { $0.asListItem() }
    }

    static func stampList(
        pending: PendingSharePayload?,
        incomingURL: URL,
        joined: SaveCollaborativeList?
    ) -> SaveCollaborativeList? {
        let items = itemsToStamp(
            pending: pending,
            incomingURL: incomingURL,
            liveItems: joined?.items ?? []
        )
        guard !items.isEmpty else { return nil }
        var list = joined ?? SaveCollaborativeList(
            id: pending?.listId.flatMap(UUID.init(uuidString:)) ?? UUID(),
            title: pending?.sender?.isEmpty == false
                ? "\(pending?.sender ?? "")'s list"
                : "Shared list",
            ownerDisplayName: pending?.sender ?? "",
            viewerRole: .viewer,
            items: items
        )
        list.items = items
        return list
    }

    static func needsPlaceRefresh(
        confirmed: [SaveListItem],
        places: [Place],
        newlySaved: Int,
        alreadySaved: Int
    ) -> Bool {
        let claimed = newlySaved + alreadySaved
        guard claimed > 0 else { return false }
        return confirmed.filter { $0.alreadySaved(in: places) }.count < claimed
    }

    /// Quota-aware bulk plan. Only `toStamp` may become local Map Stamps.
    static func planStamps(
        confirmed: [SaveListItem],
        alreadySaved: (SaveListItem) -> Bool,
        savedPlaceCount: Int,
        limit: Int = freeLimit
    ) -> (toStamp: [SaveListItem], counts: ClipListHandoffCounts) {
        let countable = confirmed.filter { !identities(of: $0).isEmpty }
        let unique = uniqueItems(countable)
        var already = max(0, countable.count - unique.count)
        var novel: [SaveListItem] = []
        for item in unique {
            if alreadySaved(item) {
                already += 1
                continue
            }
            novel.append(item)
        }
        let remainingSlots = max(0, limit - max(0, savedPlaceCount))
        let toStamp = Array(novel.prefix(remainingSlots))
        let counts = ClipListHandoffCounts(
            newlySaved: toStamp.count,
            alreadySaved: already,
            overCap: max(0, novel.count - toStamp.count),
            remaining: remainingSlots - toStamp.count,
            limit: limit
        )
        return (toStamp, counts)
    }

    /// One-place installed-app handoff uses the same three counts as Clip SIWA.
    static func onePlaceImport(counts: ClipListHandoffCounts) -> OnePlaceImport {
        if counts.newlySaved > 0 { return .saved }
        if counts.alreadySaved > 0 { return .alreadySaved }
        if counts.overCap > 0 { return .capReached }
        return .unconfirmed
    }

    /// Recipient cache row only. A reconstructed share snapshot is not a Map Stamp.
    static func cachedAlreadySavedPlace(
        places: [Place],
        already: [SavedRow],
        fallback: Place
    ) -> Place? {
        for row in already {
            if let match = places.first(where: { $0.id == row.id }) {
                return match
            }
        }
        return places.first { $0.matches(fallback) }
    }

    enum OnePlaceImport: Equatable {
        case saved
        case alreadySaved
        case capReached
        case unconfirmed
    }

    struct SavedRow: Equatable {
        var id: UUID
        var providerPlaceId: String
        var name: String
        var latitude: Double
        var longitude: Double
    }

    /// Stamp inserted rows plus account duplicates. A count-only prefix of
    /// locally novel items can pick a different set when the cache is stale.
    static func parseRemote(
        status: Int,
        data: Data
    ) -> (counts: ClipListHandoffCounts, saved: [SavedRow], already: [SavedRow])? {
        guard let counts = parseCounts(status: status, data: data) else { return nil }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let saved = parseSavedRows(body["saved"])
        let already: [SavedRow]
        if body["already"] == nil {
            already = []
        } else {
            guard let parsedAlready = parseSavedRows(body["already"]) else { return nil }
            already = parsedAlready
        }
        if counts.newlySaved == 0 {
            return (counts, saved ?? [], already)
        }
        guard let saved, saved.count == counts.newlySaved else { return nil }
        return (counts, saved, already)
    }

    static func placesFromRemoteRows(
        confirmed: [SaveListItem],
        rows: [SavedRow]
    ) -> [Place]? {
        var remaining = confirmed
        var places: [Place] = []
        for row in rows {
            guard let index = remaining.firstIndex(where: { matches($0, row) }) else { return nil }
            let item = remaining.remove(at: index)
            var place = item.asPlace(id: row.id, includeSenderMemory: false)
            if place.providerPlaceId == nil {
                let provider = row.providerPlaceId.isEmpty ? item.sourceID : row.providerPlaceId
                place.providerPlaceId = provider.isEmpty ? nil : provider
            }
            places.append(place)
        }
        return places
    }

    static func parseCounts(status: Int, data: Data) -> ClipListHandoffCounts? {
        guard (200...299).contains(status) else { return nil }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let newlySaved = intValue(body, keys: ["newly_saved", "saved", "created"]),
              let alreadySaved = intValue(body, keys: ["already_saved", "duplicates"]),
              let overCap = intValue(body, keys: ["over_cap", "cap_reached", "over_free_limit_count"])
        else { return nil }
        return ClipListHandoffCounts(
            newlySaved: newlySaved,
            alreadySaved: alreadySaved,
            overCap: overCap,
            remaining: intValue(body, keys: ["remaining", "remaining_count"]) ?? 0,
            limit: intValue(body, keys: ["limit"]) ?? freeLimit
        )
    }

    static func placeBody(from item: SaveListItem) -> [String: Any] {
        var body: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "name": item.title,
            "address": item.subtitle,
            "latitude": item.latitude,
            "longitude": item.longitude,
            "category": (item.category ?? .food).rawValue,
            "status": "wantToGo",
            "source_platform": "other",
        ]
        if let sourceURL = item.sourceURL { body["source_url"] = sourceURL }
        if !item.sourceID.isEmpty { body["provider_place_id"] = item.sourceID }
        let extras = (item.extraPlaceIds ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let google = ([item.sourceID] + extras).first(where: isGooglePlaceID) {
            body["google_place_id"] = google
        }
        if !extras.isEmpty { body["extra_place_ids"] = extras }
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

    static func toastEnglish(counts: ClipListHandoffCounts, confirmedCount: Int) -> String {
        if counts.newlySaved == 0, counts.alreadySaved > 0, counts.overCap == 0 {
            return "Already saved."
        }
        if counts.overCap > 0 {
            return "Saved \(counts.newlySaved) of \(confirmedCount). \(counts.overCap) over the free \(counts.limit)."
        }
        if counts.newlySaved == 1 {
            return "Saved 1 place from the list."
        }
        return "Saved \(counts.newlySaved) places from the list."
    }

    private static func parseSavedRows(_ rawValue: Any?) -> [SavedRow]? {
        guard let raw = rawValue as? [[String: Any]] else { return nil }
        var rows: [SavedRow] = []
        for item in raw {
            guard let id = uuidValue(item["id"]) else { return nil }
            rows.append(
                SavedRow(
                    id: id,
                    providerPlaceId: stringValue(item["provider_place_id"]),
                    name: stringValue(item["name"]),
                    latitude: doubleValue(item["latitude"]) ?? 0,
                    longitude: doubleValue(item["longitude"]) ?? 0
                )
            )
        }
        return rows
    }

    private static func matches(_ item: SaveListItem, _ row: SavedRow) -> Bool {
        let sourceID = item.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceID.isEmpty, !row.providerPlaceId.isEmpty,
           sourceID.caseInsensitiveCompare(row.providerPlaceId) == .orderedSame {
            return true
        }
        let name = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rowName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.caseInsensitiveCompare(rowName) == .orderedSame else { return false }
        return String(format: "%.4f", item.latitude) == String(format: "%.4f", row.latitude)
            && String(format: "%.4f", item.longitude) == String(format: "%.4f", row.longitude)
    }

    static func uniqueItems(_ items: [SaveListItem]) -> [SaveListItem] {
        var indexByKey: [String: Int] = [:]
        var unique: [SaveListItem] = []
        for item in items {
            let keys = identities(of: item)
            guard !keys.isEmpty else { continue }
            let matched = Array(Set(keys.compactMap { indexByKey[$0] })).sorted()
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

    private static func mergingIdentities(_ kept: SaveListItem, _ incoming: SaveListItem) -> SaveListItem {
        var result = kept
        var extras = Set(
            (kept.extraPlaceIds ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
        let incomingId = incoming.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !incomingId.isEmpty,
           result.sourceID.caseInsensitiveCompare(incomingId) != .orderedSame {
            extras.insert(incomingId)
        }
        for extra in incoming.extraPlaceIds ?? [] {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               result.sourceID.caseInsensitiveCompare(trimmed) != .orderedSame {
                extras.insert(trimmed)
            }
        }
        result.extraPlaceIds = extras.isEmpty ? nil : extras.sorted()
        return result
    }

    private static func identities(of item: SaveListItem) -> [String] {
        var keys: [String] = []
        var placeIds: [String] = []
        let sourceID = item.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !sourceID.isEmpty { placeIds.append(sourceID) }
        for extra in item.extraPlaceIds ?? [] {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty { placeIds.append(trimmed) }
        }
        for placeId in placeIds {
            keys.append("id:\(placeId)")
            keys.append("p:\(placeId)")
            keys.append("g:\(placeId)")
        }
        let name = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty {
            keys.append("n:\(name)|\(String(format: "%.4f", item.latitude))|\(String(format: "%.4f", item.longitude))")
        }
        return keys
    }

    private static func intValue(_ body: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = body[key] as? Int { return value }
            if let value = body[key] as? NSNumber { return value.intValue }
        }
        return nil
    }

    private static func uuidValue(_ raw: Any?) -> UUID? {
        if let value = raw as? String { return UUID(uuidString: value) }
        return nil
    }

    private static func stringValue(_ raw: Any?) -> String {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}
