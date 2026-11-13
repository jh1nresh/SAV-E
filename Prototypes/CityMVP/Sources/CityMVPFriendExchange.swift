#if SAVVY_CITY_MVP
import Foundation

/// An unsigned, forwardable local copy. Sender text is data, never instructions
/// or authenticated identity; it is not copied into the recipient's memory.
nonisolated enum CityMVPFriendExchange {
    static let maximumBytes = 128 * 1_024
    static let maximumPlaces = 30

    struct Snapshot: Codable, Equatable, Sendable {
        let version: Int
        let senderLabel: String
        let recommendationReason: String
        let sharedAt: Date
        let venues: [Venue]
    }

    struct Venue: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let name: String
        let address: String
        let category: PlaceCategory
        let latitude: Double
        let longitude: Double
        let coordinateSystem: PlaceCoordinateSystem?
        let locationProvider: PlaceMatchProvider?
        let providerPlaceID: String?
        let googlePlaceID: String?
        let providerMapURL: String?
        let sourceURL: String?
    }

    enum ExchangeError: LocalizedError {
        case invalidSelection, invalidSnapshot, tooLarge, invalidFile
        var errorDescription: String? {
            switch self {
            case .invalidSelection: "Select 1–30 current saved places."
            case .invalidSnapshot: "This recommendation file has invalid or unsupported fields."
            case .tooLarge: "Recommendation files must be 128 KiB or smaller."
            case .invalidFile: "Choose a readable JSON recommendation file."
            }
        }
    }

    @MainActor
    static func makeSnapshot(places: [Place], selectedIDs: Set<UUID>, senderLabel: String,
                             recommendationReason: String, now: Date = Date()) throws -> Snapshot {
        let selected = places.filter { selectedIDs.contains($0.id) }
        guard !selectedIDs.isEmpty, selectedIDs.count <= maximumPlaces,
              selected.count == selectedIDs.count else { throw ExchangeError.invalidSelection }
        let snapshot = Snapshot(version: 1, senderLabel: senderLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            recommendationReason: recommendationReason.trimmingCharacters(in: .whitespacesAndNewlines),
            sharedAt: Date(timeIntervalSince1970: floor(now.timeIntervalSince1970)),
            venues: selected.map { place in
                Venue(id: UUID(), name: place.name, address: place.address, category: place.category,
                    latitude: place.latitude, longitude: place.longitude, coordinateSystem: place.resolvedCoordinateSystem,
                    locationProvider: place.locationProvider, providerPlaceID: place.providerPlaceId,
                    googlePlaceID: place.googlePlaceId, providerMapURL: place.providerMapUrl,
                    sourceURL: place.sourceUrl)
            })
        _ = try encode(snapshot)
        return snapshot
    }

    static func encode(_ snapshot: Snapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(snapshot)
        guard data.count <= maximumBytes else { throw ExchangeError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Snapshot {
        guard data.count <= maximumBytes else { throw ExchangeError.tooLarge }
        // Reject unknown fields as well as malformed values: a future format
        // must not silently become a different import under this schema.
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["version", "senderLabel", "recommendationReason", "sharedAt", "venues"]),
              let rows = object["venues"] as? [[String: Any]],
              !rows.isEmpty, rows.count <= maximumPlaces else { throw ExchangeError.invalidSnapshot }
        let required: Set<String> = ["id", "name", "address", "category", "latitude", "longitude", "coordinateSystem"]
        let allowed = required.union(["coordinateSystem", "locationProvider", "providerPlaceID", "googlePlaceID", "providerMapURL", "sourceURL"])
        guard rows.allSatisfy({ required.isSubset(of: Set($0.keys)) && Set($0.keys).isSubset(of: allowed) }) else {
            throw ExchangeError.invalidSnapshot
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { throw ExchangeError.invalidSnapshot }
        try validate(snapshot)
        return snapshot
    }

    /// Reads at most the byte limit plus one; no unbounded Data(contentsOf:).
    static func read(from url: URL) throws -> Snapshot {
        guard url.isFileURL else { throw ExchangeError.invalidFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ExchangeError.invalidFile }
        if let size = values.fileSize, size > maximumBytes { throw ExchangeError.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try file.read(upToCount: maximumBytes + 1 - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return try decode(data)
    }

    @MainActor
    static func recipientPlace(for venue: Venue, now: Date = Date()) -> Place {
        // Preserve provider coordinates verbatim. GCJ-02/BD-09 are not WGS84
        // and the existing Place.isMapKitMappable boundary remains authoritative.
        Place(id: UUID(), name: venue.name, address: venue.address,
            latitude: venue.latitude, longitude: venue.longitude, googlePlaceId: venue.googlePlaceID,
            category: venue.category, status: .wantToGo, rating: nil, note: nil,
            sourceUrl: venue.sourceURL, sourcePlatform: .other, coordinateSystem: venue.coordinateSystem,
            locationProvider: venue.locationProvider, providerPlaceId: venue.providerPlaceID,
            providerMapUrl: venue.providerMapURL, sourceImageUrl: nil, businessPhotoUrls: nil,
            extractedDishes: nil, priceRange: nil, recommender: nil, googleRating: nil,
            googlePriceLevel: nil, openingHours: nil, createdAt: now)
    }

    private static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.version == 1,
              validText(snapshot.senderLabel, limit: 80, required: true),
              validText(snapshot.recommendationReason, limit: 1_000, required: true, allowsLineBreaks: true),
              snapshot.sharedAt.timeIntervalSince1970.isFinite,
              !snapshot.venues.isEmpty, snapshot.venues.count <= maximumPlaces,
              Set(snapshot.venues.map(\.id)).count == snapshot.venues.count,
              snapshot.venues.allSatisfy({ venue in
                  validText(venue.name, limit: 180, required: true)
                      && validText(venue.address, limit: 500, required: false)
                      && venue.latitude.isFinite && venue.longitude.isFinite
                      && (-90...90).contains(venue.latitude) && (-180...180).contains(venue.longitude)
                      && (venue.latitude != 0 || venue.longitude != 0)
                      && venue.coordinateSystem != nil
                      && !(venue.locationProvider == .amap && venue.coordinateSystem != .gcj02)
                      && optionalText(venue.providerPlaceID, limit: 256)
                      && optionalText(venue.googlePlaceID, limit: 256)
                      && validURL(venue.providerMapURL) && validURL(venue.sourceURL)
              }) else { throw ExchangeError.invalidSnapshot }
    }

    private static func validText(_ value: String, limit: Int, required: Bool, allowsLineBreaks: Bool = false) -> Bool {
        value.count <= limit && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) && !(allowsLineBreaks && ($0 == "\n" || $0 == "\t"))
            }
    }

    private static func optionalText(_ value: String?, limit: Int) -> Bool {
        value.map { validText($0, limit: limit, required: true) } ?? true
    }

    private static func validURL(_ value: String?) -> Bool {
        guard let value else { return true }
        guard validText(value, limit: 2_048, required: true),
              let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.url != nil else { return false }
        let credentials: Set<String> = ["token", "access_token", "refresh_token", "api_key", "apikey", "password", "authorization"]
        let fragmentQuery = parts.fragment.flatMap { URLComponents(string: "?" + $0)?.queryItems } ?? []
        return !((parts.queryItems ?? []) + fragmentQuery).contains { credentials.contains($0.name.lowercased()) }
    }
}
#endif
