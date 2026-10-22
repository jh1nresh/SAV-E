import Foundation

/// Lightweight, self-contained place model for the iMessage extension.
///
/// The main app persists `SaveMemoryRecord` values to a JSON file in the shared
/// App Group container. Reusing `SaveLocalVaultService` / `Place` here would pull
/// in a large dependency closure (AppLanguage, SocialPlaceEvidence, MapKit,
/// share-payload sanitizers, Privy, etc.) that is wasteful inside a memory-tight
/// Messages extension. Instead we decode the same on-disk JSON with a minimal
/// struct that matches the persisted `SaveMemoryRecord` coding keys.
nonisolated struct MessagesPlace: Identifiable, Hashable, Sendable {
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
nonisolated enum MessagesVaultReader {
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
        let ownerSubject: String?
    }

    /// Same App Group key as `SavePlaceLimitHandoff.cachedOwnerKey`.
    static let cachedOwnerKey = "save.cachedActiveOwnerSubject"

    // Mirrors only the minimal deletion receipt, never private record payload.
    private struct PendingDeletion: Decodable {
        enum RemoteOutcome: String, Decodable { case awaitingRemoteResult, succeeded }
        let id: UUID
        let owner: String
        let initialOwnerlessRecordIDs: Set<UUID>
        let remoteOutcome: RemoteOutcome
    }

    static func confirmedPlaces(limit: Int = 250) -> [MessagesPlace] {
        guard let url = vaultURL() else { return [] }
        let currentOwner = UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: cachedOwnerKey)
        return confirmedPlaces(vaultURL: url, currentOwner: currentOwner, limit: limit)
    }

    /// Both files are read while holding the vault's coordination lock, matching
    /// the app's receipt/purge writes. Malformed or inaccessible receipts fail closed.
    static func confirmedPlaces(vaultURL: URL, currentOwner: String?, limit: Int = 250) -> [MessagesPlace] {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: [MessagesPlace] = []
        coordinator.coordinate(readingItemAt: vaultURL, options: [], error: &coordinationError) { url in
            result = (try? readConfirmedPlaces(vaultURL: url, currentOwner: currentOwner, limit: limit)) ?? []
        }
        return coordinationError == nil ? result : []
    }

    private static func readConfirmedPlaces(vaultURL: URL, currentOwner: String?, limit: Int) throws -> [MessagesPlace] {
        let pending: PendingDeletion?
        do {
            pending = try JSONDecoder().decode(
                PendingDeletion.self,
                from: Data(contentsOf: vaultURL.appendingPathExtension("account-deletion.json"))
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            pending = nil
        }
        let records = try JSONDecoder().decode([StoredRecord].self, from: Data(contentsOf: vaultURL))
        return Array(
            records
            .filter { record in
                guard let pending else { return true }
                return record.ownerSubject != pending.owner
                    && !(record.ownerSubject == nil && pending.initialOwnerlessRecordIDs.contains(record.id))
            }
            .filter { $0.state == "confirmed_place" }
            .filter { belongsToActiveAccount($0.ownerSubject, currentUserId: currentOwner) }
            .compactMap { record -> MessagesPlace? in
                guard let latitude = record.latitude,
                      let longitude = record.longitude,
                      latitude != 0 || longitude != 0 else { return nil }

                let name = (record.placeName?.isEmpty == false ? record.placeName! : record.title)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let firstBusinessPhoto = record.businessPhotoUrls?
                    .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let photo = firstNonEmpty(record.sourceImageUrl, firstBusinessPhoto)

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
        )
    }

    /// Must match `SaveVaultOwnerScope.belongsToActiveAccount`.
    static func belongsToActiveAccount(
        _ ownerSubject: String?,
        currentUserId: String?
    ) -> Bool {
        if let currentUserId {
            return ownerSubject == currentUserId
        }
        return ownerSubject == nil
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
