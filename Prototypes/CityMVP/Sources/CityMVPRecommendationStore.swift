#if SAVVY_CITY_MVP
import Foundation
import Combine
import CryptoKit

/// Copied, unsigned source context. This sidecar never changes a Place or its private note.
@MainActor
final class CityMVPRecommendationStore: ObservableObject {
    nonisolated struct Record: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let savedPlaceID: UUID
        let senderLabel: String
        let reason: String
        let sharedAt: Date
        let receivedAt: Date
        let sourceURL: String?
        var authenticatedSender: Bool { false }
    }

    nonisolated enum Failure: Error, Equatable, LocalizedError {
        case unavailable, unreadable, oversized, invalidSource, writeFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: "Recommendation storage is unavailable."
            case .unreadable: "Stored recommendation details could not be read. The existing file has not been changed."
            case .oversized: "Recommendation storage is full. Existing details have not been changed."
            case .invalidSource: "This recommendation source is invalid."
            case .writeFailed: "Recommendation details could not be stored. Try again."
            }
        }
    }

    private nonisolated struct Payload: Codable {
        let version: Int
        let records: [Record]
    }
    static let maximumBytes = 256 * 1_024
    static let maximumRecords = 200
    @Published private(set) var records: [Record] = []
    @Published private(set) var failure: Failure?
    let fileURL: URL?
    private var loadFailure: Failure?
    private let isCurrentSession: () -> Bool

    init(documentsDirectory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
         storageID: String? = nil, isCurrentSession: @escaping () -> Bool = { true }) {
        self.isCurrentSession = isCurrentSession
        guard let documentsDirectory, documentsDirectory.isFileURL else {
            fileURL = nil; failure = .unavailable; loadFailure = .unavailable; return
        }
        var directory = documentsDirectory.appendingPathComponent("SavvyCityMVP/Recommendations", isDirectory: true)
        if let storageID {
            guard !storageID.isEmpty, storageID.utf8.count <= 100,
                  storageID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                      || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
                fileURL = nil; failure = .unavailable; loadFailure = .unavailable; return
            }
            directory.appendPathComponent("test-" + storageID, isDirectory: true)
        }
        fileURL = directory.appendingPathComponent("source-context-v1.json")
        load()
    }

    func recommendations(for place: Place) -> [Record] {
        records.filter { place.savedIDs.contains($0.savedPlaceID) }
    }

    /// Caller must first complete explicit venue confirmation and pass its actual returned ID.
    func remember(snapshot: CityMVPFriendExchange.Snapshot, venueID: UUID, savedPlaceID: UUID,
                  receivedAt: Date = Date()) throws {
        do {
            if let loadFailure { throw loadFailure }
            let canonical: Data
            do { canonical = try CityMVPFriendExchange.encode(snapshot) }
            catch { throw Failure.invalidSource }
            guard receivedAt.timeIntervalSince1970.isFinite,
                  let venue = snapshot.venues.first(where: { $0.id == venueID }) else { throw Failure.invalidSource }
            var identity = canonical
            identity.append(Data(("\n" + venueID.uuidString + "\n" + savedPlaceID.uuidString).utf8))
            let id = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
            guard !records.contains(where: { $0.id == id }) else { failure = nil; return }
            let record = Record(id: id, savedPlaceID: savedPlaceID, senderLabel: snapshot.senderLabel,
                reason: snapshot.recommendationReason, sharedAt: snapshot.sharedAt,
                receivedAt: receivedAt, sourceURL: venue.sourceURL)
            try commit(records + [record])
        } catch { throw report(error) }
    }

    func forget(recordID: String) throws {
        do {
            if let loadFailure { throw loadFailure }
            guard records.contains(where: { $0.id == recordID }) else { return }
            try commit(records.filter { $0.id != recordID })
        } catch { throw report(error) }
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unreadable }
            guard let size = values.fileSize, size <= Self.maximumBytes else { throw Failure.oversized }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= Self.maximumBytes {
                let chunk = try handle.read(upToCount: Self.maximumBytes + 1 - data.count) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
            }
            guard data.count <= Self.maximumBytes else { throw Failure.oversized }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(root.keys) == ["version", "records"], let rows = root["records"] as? [[String: Any]],
                  rows.allSatisfy({ row in
                      let required: Set<String> = ["id", "savedPlaceID", "senderLabel", "reason", "sharedAt", "receivedAt"]
                      return required.isSubset(of: Set(row.keys)) && Set(row.keys).isSubset(of: required.union(["sourceURL"]))
                  }) else { throw Failure.unreadable }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.version == 1 else { throw Failure.unreadable }
            try validate(payload.records)
            records = payload.records
        } catch {
            let issue = (error as? Failure) ?? .unreadable
            loadFailure = issue; failure = issue
        }
    }

    private func validate(_ values: [Record]) throws {
        guard values.count <= Self.maximumRecords else { throw Failure.oversized }
        guard Set(values.map(\.id)).count == values.count else { throw Failure.unreadable }
        for record in values {
            guard record.id.utf8.count == 64,
                  record.id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  record.receivedAt.timeIntervalSince1970.isFinite else { throw Failure.unreadable }
            // Reuse the exchange's text/date/link validation, without persisting venue coordinates.
            let venue = CityMVPFriendExchange.Venue(id: record.savedPlaceID, name: "Validation",
                address: "", category: .cafe, latitude: 1, longitude: 1, coordinateSystem: .wgs84,
                locationProvider: nil, providerPlaceID: nil, googlePlaceID: nil, providerMapURL: nil,
                sourceURL: record.sourceURL)
            let snapshot = CityMVPFriendExchange.Snapshot(version: 1, senderLabel: record.senderLabel,
                recommendationReason: record.reason, sharedAt: record.sharedAt, venues: [venue])
            do { _ = try CityMVPFriendExchange.encode(snapshot) }
            catch { throw Failure.unreadable }
        }
    }

    private func commit(_ next: [Record]) throws {
        guard isCurrentSession() else { throw Failure.unavailable }
        guard let fileURL else { throw Failure.unavailable }
        try validate(next)
        let data = try JSONEncoder().encode(Payload(version: 1, records: next))
        guard data.count <= Self.maximumBytes else { throw Failure.oversized }
        var directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var metadata = URLResourceValues(); metadata.isExcludedFromBackup = true
        try directory.setResourceValues(metadata)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        records = next
        failure = nil
    }

    private func report(_ error: Error) -> Failure {
        let issue = (error as? Failure) ?? .writeFailed
        failure = issue
        return issue
    }
}
#endif
