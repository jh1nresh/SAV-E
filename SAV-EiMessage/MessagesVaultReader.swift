import Foundation

/// Lightweight, self-contained place model for the iMessage extension.
///
/// The main app persists `SaveMemoryRecord` values to a JSON file in the shared
/// App Group container. Reusing `SaveLocalVaultService` / `Place` here would pull
/// in a large dependency closure (AppLanguage, SocialPlaceEvidence, MapKit,
/// share-payload sanitizers, Privy, etc.) that is wasteful inside a memory-tight
/// Messages extension. Instead we decode the same on-disk JSON with a minimal
/// struct that matches the persisted `SaveMemoryRecord` coding keys.
struct MessagesPlace: Identifiable, Hashable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let rating: Double?
    let sourceURL: String?
    let photoURLString: String?
}

/// Reads confirmed places directly from the App Group JSON the main app writes.
enum MessagesVaultReader {
    static let appGroupSuiteName = "group.com.wanderly.app"
    static let fileName = "save-memory-records.json"

    /// Mirrors the persisted shape of `SaveMemoryRecord` (only the fields we need).
    private struct StoredRecord: Decodable {
        let id: UUID
        let state: String
        let title: String
        let placeName: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let category: String?
        let rating: Double?
        let sourceURL: String?
        let sourceImageUrl: String?
        let businessPhotoUrls: [String]?
    }

    static func confirmedPlaces(limit: Int = 250) -> [MessagesPlace] {
        guard let url = vaultURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let records = try? decoder.decode([StoredRecord].self, from: data) else {
            return []
        }

        return records
            .filter { $0.state == "confirmed_place" }
            .compactMap { record -> MessagesPlace? in
                guard let latitude = record.latitude,
                      let longitude = record.longitude,
                      latitude != 0 || longitude != 0 else { return nil }

                let name = (record.placeName?.isEmpty == false ? record.placeName! : record.title)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let photo = firstNonEmpty(record.sourceImageUrl, record.businessPhotoUrls?.first)

                return MessagesPlace(
                    id: record.id,
                    name: name,
                    address: (record.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    latitude: latitude,
                    longitude: longitude,
                    category: record.category,
                    rating: record.rating,
                    sourceURL: record.sourceURL,
                    photoURLString: photo
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func vaultURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent(fileName)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
