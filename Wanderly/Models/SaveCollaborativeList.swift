import CoreLocation
import Foundation

enum SaveListRole: String, Codable, CaseIterable, Hashable {
    case owner
    case editor
    case viewer

    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }

    var canEdit: Bool {
        self == .owner || self == .editor
    }
}

enum SaveListItemSource: String, Codable, Hashable {
    case savedPlace
    case mapCandidate

    var label: String {
        switch self {
        case .savedPlace: return "Map Stamp"
        case .mapCandidate: return "Map result"
        }
    }
}

struct SaveListItem: Identifiable, Codable, Hashable {
    var id: UUID
    var source: SaveListItemSource
    var sourceID: String
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var category: PlaceCategory?
    var rating: Double?
    var reviewCount: Int?
    var sourceURL: String?
    var photoURLs: [String]
    var note: String?
    var addedByDisplayName: String
    var addedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isMappable: Bool {
        latitude != 0 || longitude != 0
    }

    static func from(place: Place, addedByDisplayName: String = "You", addedAt: Date = Date()) -> SaveListItem {
        SaveListItem(
            id: UUID(),
            source: .savedPlace,
            sourceID: place.id.uuidString,
            title: place.name,
            subtitle: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            category: place.category,
            rating: place.googleRating ?? place.rating,
            reviewCount: nil,
            sourceURL: place.sourceUrl,
            photoURLs: place.businessPhotoURLStrings,
            note: place.note,
            addedByDisplayName: addedByDisplayName,
            addedAt: addedAt
        )
    }

    static func from(candidate: SaveMapCandidate, addedByDisplayName: String = "You", addedAt: Date = Date()) -> SaveListItem {
        SaveListItem(
            id: UUID(),
            source: .mapCandidate,
            sourceID: candidate.id,
            title: candidate.title,
            subtitle: candidate.subtitle,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            category: candidate.category,
            rating: candidate.rating,
            reviewCount: candidate.reviewCount,
            sourceURL: candidate.sourceURL,
            photoURLs: candidate.businessPhotoURLStrings,
            note: candidate.shareNote,
            addedByDisplayName: addedByDisplayName,
            addedAt: addedAt
        )
    }

    func matches(_ other: SaveListItem) -> Bool {
        if source == other.source, sourceID == other.sourceID { return true }
        let sameTitle = title.localizedCaseInsensitiveCompare(other.title) == .orderedSame
        let nearby = abs(latitude - other.latitude) < 0.0008 && abs(longitude - other.longitude) < 0.0008
        return sameTitle && nearby
    }

    func alreadySaved(in places: [Place]) -> Bool {
        places.contains { place in
            place.matchesMapFeature(title: title, coordinate: coordinate) ||
                place.name.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
    }

    func asPlace(createdAt: Date = Date()) -> Place {
        Place(
            id: UUID(),
            name: title,
            address: subtitle,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category ?? .food,
            status: .wantToGo,
            rating: nil,
            note: note,
            sourceUrl: sourceURL,
            sourcePlatform: .other,
            sourceImageUrl: photoURLs.first,
            businessPhotoUrls: photoURLs,
            extractedDishes: nil,
            priceRange: nil,
            recommender: addedByDisplayName,
            googleRating: rating,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: createdAt
        )
    }
}

struct SaveCollaborativeList: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var note: String?
    var ownerDisplayName: String
    var viewerRole: SaveListRole
    var items: [SaveListItem]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        ownerDisplayName: String = "You",
        viewerRole: SaveListRole = .owner,
        items: [SaveListItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.ownerDisplayName = ownerDisplayName
        self.viewerRole = viewerRole
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var shareSubject: String {
        "SAV-E List: \(title)"
    }

    var placeCountLabel: String {
        items.count == 1 ? "1 place" : "\(items.count) places"
    }

    var canEdit: Bool {
        viewerRole.canEdit
    }

    mutating func add(_ item: SaveListItem, now: Date = Date()) {
        guard canEdit else { return }
        guard !items.contains(where: { $0.matches(item) }) else { return }
        items.append(item)
        updatedAt = now
    }

    func shareURL(role: SaveListRole = .viewer) -> URL? {
        SaveSharedListPayload(list: self, role: role).toURL()
    }

    func joined(as role: SaveListRole) -> SaveCollaborativeList {
        var copy = self
        copy.viewerRole = role
        return copy
    }

    func itineraryResponse() -> SaveAIResponse {
        let stops = items.enumerated().map { index, item in
            ItineraryStop(
                id: item.id,
                placeId: item.source == .savedPlace ? item.sourceID : nil,
                placeName: item.title,
                time: suggestedTime(for: index),
                duration: 60,
                note: item.source == .mapCandidate ? "Map result from shared list. Save it before treating it as your memory." : item.note
            )
        }

        return SaveAIResponse(
            componentType: .tripItinerary,
            title: "\(title) plan",
            placeIds: items.filter { $0.source == .savedPlace }.map(\.sourceID),
            navigationPlaceId: nil,
            transportMode: items.count > 3 ? .driving : .walking,
            itineraryDays: [ItineraryDay(dayNumber: 1, label: "List plan", stops: stops)],
            messageText: nil,
            mapAction: nil,
            aiMessage: "Built from this shared SAV-E list. Unsaved map results stay separate until you save them."
        )
    }

    private func suggestedTime(for index: Int) -> String {
        let hour = min(21, 10 + index * 2)
        return String(format: "%02d:00", hour)
    }
}

struct SaveSharedListPayload: Codable, Hashable {
    var list: SaveCollaborativeList
    var role: SaveListRole

    static func from(url: URL) -> SaveSharedListPayload? {
        guard isListLink(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let jsonData = Data(base64Encoded: dataParam),
              var payload = try? JSONDecoder().decode(SaveSharedListPayload.self, from: jsonData) else {
            return nil
        }

        if let roleValue = components.queryItems?.first(where: { $0.name == "r" })?.value,
           let role = SaveListRole(rawValue: roleValue) {
            payload.role = role
        }
        payload.list.viewerRole = payload.role
        return payload
    }

    func toURL(baseURL: String? = nil) -> URL? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let base64 = jsonData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let base = baseURL ?? SaveCollaborativeListLinkConfig.listBaseURL
        return URL(string: "\(base)?d=\(base64)&r=\(role.rawValue)")
    }

    static func isListLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "list" {
            return true
        }
        return url.scheme == "https" &&
            (url.host == "sav-e-app.vercel.app" || url.host == "wanderly.app") &&
            url.path == "/list"
    }
}

enum SaveCollaborativeListNotification {
    static let didJoin = Notification.Name("SaveCollaborativeListDidJoin")
}

final class SaveCollaborativeListStore {
    static let shared = SaveCollaborativeListStore()

    private let storageKey = "save.collaborativeLists.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SaveCollaborativeList] {
        guard let data = defaults.data(forKey: storageKey),
              let lists = try? JSONDecoder().decode([SaveCollaborativeList].self, from: data) else {
            return []
        }
        return lists.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ lists: [SaveCollaborativeList]) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        defaults.set(data, forKey: storageKey)
    }

    @discardableResult
    func join(from url: URL) throws -> SaveCollaborativeList {
        guard let payload = SaveSharedListPayload.from(url: url) else {
            throw SaveCollaborativeListError.invalidLink
        }
        let joined = payload.list.joined(as: payload.role)
        var lists = load()
        if let index = lists.firstIndex(where: { $0.id == joined.id }) {
            lists[index] = joined
        } else {
            lists.insert(joined, at: 0)
        }
        save(lists)
        NotificationCenter.default.post(name: SaveCollaborativeListNotification.didJoin, object: joined)
        return joined
    }
}

enum SaveCollaborativeListError: LocalizedError {
    case invalidLink
    case listNotFound
    case viewerCannotEdit

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "This SAV-E list link is invalid or expired."
        case .listNotFound:
            return "Choose a list first."
        case .viewerCannotEdit:
            return "This list is viewer-only. Join with an editor link to add places."
        }
    }
}

private enum SaveCollaborativeListLinkConfig {
    static let listBaseURL: String = {
        configValue(for: ["SAVE_LIST_SHARE_BASE_URL", "SAVE_SHARE_LIST_BASE_URL"])
            ?? "https://sav-e-app.vercel.app/list"
    }()

    private static func configValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = normalizedConfigValue(ProcessInfo.processInfo.environment[key]) {
                return removingTrailingSlashes(from: value)
            }
            if let value = normalizedConfigValue(keyFromPlist(key)) {
                return removingTrailingSlashes(from: value)
            }
        }
        return nil
    }

    private static func normalizedConfigValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "YOUR_KEY_HERE"
        else { return nil }
        return value
    }

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return nil }
        return dict[key]
    }

    private static func removingTrailingSlashes(from value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
