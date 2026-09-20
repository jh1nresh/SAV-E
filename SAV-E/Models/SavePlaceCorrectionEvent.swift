import Foundation
import CryptoKit

nonisolated enum SavePlaceCorrectionEventType: String, Codable, Sendable {
    case confirmCandidate = "confirm_candidate"
    case editPlaceIdentity = "edit_place_identity"
    case editAddress = "edit_address"
    case wrongPlace = "wrong_place"
    case wrongCity = "wrong_city"
    case wrongBranch = "wrong_branch"
    case saveSourceOnly = "save_source_only"
    case mergeExisting = "merge_existing"
    case addReason = "add_reason"
    case changeCollection = "change_collection"
    case rejectCandidate = "reject_candidate"
    case investigateMore = "investigate_more"

    var workflowAction: String {
        switch self {
        case .confirmCandidate:
            return "confirm"
        case .mergeExisting:
            return "merge_existing"
        case .wrongPlace, .rejectCandidate:
            return "reject"
        case .investigateMore:
            return "investigate_more"
        case .wrongCity, .wrongBranch:
            return "needs_more_evidence"
        case .saveSourceOnly:
            return "source_only"
        case .editPlaceIdentity, .editAddress, .addReason, .changeCollection:
            return "edit"
        }
    }
}

nonisolated struct SavePlaceCorrectionSnapshot: Codable, Equatable, Sendable {
    var name: String
    var address: String
    var city: String?
    var status: String
    var latitude: Double?
    var longitude: Double?

    @MainActor
    init(candidate: PlaceReviewCandidate) {
        name = candidate.name
        address = candidate.address
        city = candidate.city
        status = candidate.status
        latitude = candidate.latitude
        longitude = candidate.longitude
    }

    var workflowPayload: [String: Any] {
        var payload: [String: Any] = [
            "name": name,
            "address": address,
            "status": status,
        ]
        if let city { payload["city"] = city }
        if let latitude { payload["latitude"] = latitude }
        if let longitude { payload["longitude"] = longitude }
        return payload
    }
}

nonisolated struct SavePlaceCorrectionEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var userId: String?
    var captureId: UUID?
    var candidateId: UUID
    var workflowRunId: UUID?
    var eventType: SavePlaceCorrectionEventType
    var beforeSnapshot: SavePlaceCorrectionSnapshot
    var afterSnapshot: SavePlaceCorrectionSnapshot?
    var sourceEvidenceTierBefore: String
    var confidenceBefore: Double?
    var userFinalPlaceId: UUID?
    var userFinalCollectionIds: [UUID]
    var userReasonText: String?
    var createdAt: Date
    var correctionScopeKey: String?
    var learningCommitted: Bool?
    var learningRevoked: Bool?

    @MainActor
    init(
        id: UUID = UUID(),
        userId: String?,
        candidate: PlaceReviewCandidate,
        eventType: SavePlaceCorrectionEventType,
        afterSnapshot: SavePlaceCorrectionSnapshot? = nil,
        userFinalPlaceId: UUID? = nil,
        userFinalCollectionIds: [UUID] = [],
        userReasonText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        captureId = candidate.captureId
        candidateId = candidate.id
        workflowRunId = candidate.workflowRunId
        self.eventType = eventType
        beforeSnapshot = SavePlaceCorrectionSnapshot(candidate: candidate)
        self.afterSnapshot = afterSnapshot
        sourceEvidenceTierBefore = candidate.correctionEvidenceTier
        confidenceBefore = candidate.confidence
        self.userFinalPlaceId = userFinalPlaceId
        self.userFinalCollectionIds = userFinalCollectionIds
        self.userReasonText = userReasonText
        self.createdAt = createdAt
        correctionScopeKey = candidate.correctionScopeKey
        learningCommitted = false
        learningRevoked = false
    }

    var workflowPayload: [String: Any] {
        var payload: [String: Any] = [
            "correction_event_id": id.uuidString,
            "event_type": eventType.rawValue,
            "candidate_id": candidateId.uuidString,
            "before_snapshot": beforeSnapshot.workflowPayload,
            "source_evidence_tier_before": sourceEvidenceTierBefore,
            "user_final_collection_ids": userFinalCollectionIds.map(\.uuidString),
        ]
        if let captureId { payload["capture_id"] = captureId.uuidString }
        if let afterSnapshot { payload["after_snapshot"] = afterSnapshot.workflowPayload }
        if let confidenceBefore { payload["confidence_before"] = confidenceBefore }
        if let userFinalPlaceId { payload["user_final_place_id"] = userFinalPlaceId.uuidString }
        if let userReasonText { payload["user_reason_text"] = userReasonText }
        return payload
    }
}

nonisolated final class SavePlaceCorrectionEventStore: Sendable {
    static let shared = SavePlaceCorrectionEventStore()

    private let overrideURL: URL?
    private let fileName = "save-place-correction-events.json"
    private let queue = DispatchQueue(label: "com.save.place-correction-event-store")

    init(overrideURL: URL? = nil) {
        self.overrideURL = overrideURL
    }

    func append(_ event: SavePlaceCorrectionEvent) throws {
        try queue.sync {
            var events = try recentEventsUnlocked(limit: 999)
            events.removeAll { $0.id == event.id }
            events.insert(event, at: 0)
            guard let url = storageURL else { throw SaveLocalVaultError.storageUnavailable }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(events).write(to: url, options: [.atomic])
        }
    }

    func recentEvents(limit: Int = 100) throws -> [SavePlaceCorrectionEvent] {
        try queue.sync {
            try recentEventsUnlocked(limit: limit)
        }
    }

    /// Filter before limiting; a shared device file is never an account boundary.
    func recentEvents(userId: String, limit: Int = 1000) throws -> [SavePlaceCorrectionEvent] {
        guard !userId.isEmpty else { return [] }
        return try queue.sync {
            Array(try recentEventsUnlocked(limit: 1000).filter { $0.userId == userId }.prefix(max(0, limit)))
        }
    }

    private func recentEventsUnlocked(limit: Int) throws -> [SavePlaceCorrectionEvent] {
        guard let url = storageURL else { throw SaveLocalVaultError.storageUnavailable }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Array(try decoder.decode([SavePlaceCorrectionEvent].self, from: Data(contentsOf: url)).prefix(limit))
    }

    private var storageURL: URL? {
        if let overrideURL { return overrideURL }
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName) {
            return appGroupURL.appendingPathComponent(fileName)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }
}

private extension PlaceReviewCandidate {
    var correctionEvidenceTier: String {
        if status == "source_only" || evidence.contains(where: { $0.localizedCaseInsensitiveContains("source-only") }) {
            return "source_only"
        }
        if status == "confirmed" { return "confirmed" }
        return hasReliableCoordinates ? "likely" : "weak_candidate"
    }
}

/// Reversible account-local projection. It proposes a review identity, never a saved place.
@MainActor
enum SaveCorrectionLearning {
    static let provenance = "Suggested from your previous correction of this source. Confirm the place."

    static func scopeKey(for pending: PendingReviewCandidate) -> String? {
        guard let source = SaveSourceIdentity.url(pending.sourceURL),
              let raw = pending.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw != pending.sourceURL, SaveSourceIdentity.url(raw) == nil else { return nil }
        // A post can contain multiple venues. Content and original venue slot are
        // both required; no name-only, URL-only or cross-source generalization.
        let fields = ["correction-v1", source, raw,
                      SaveSourceIdentity.text(pending.candidateName), SaveSourceIdentity.text(pending.address)]
        guard let bytes = try? JSONEncoder().encode(fields) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func validScope(_ key: String?) -> Bool {
        guard let key, key.utf8.count == 64 else { return false }
        return key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func suggestion(for candidate: PlaceReviewCandidate, userId: String?,
                           events: [SavePlaceCorrectionEvent], ownedPlaces: [Place],
                           now: Date = Date()) -> PlaceReviewCandidate {
        guard let userId, !userId.isEmpty, validScope(candidate.correctionScopeKey),
              ["review", "needs_more_evidence"].contains(candidate.status), candidate.hasReliableCoordinates else { return candidate }
        let relevant = events.filter { $0.userId == userId && $0.correctionScopeKey == candidate.correctionScopeKey }
        // A failed/pending/revoked newer decision must not resurrect an older one.
        guard let latestDate = relevant.map(\.createdAt).max(), latestDate <= now else { return candidate }
        let latest = Array(Set(relevant.filter { $0.createdAt == latestDate }.map { $0.id }))
        guard latest.count == 1, let event = relevant.first(where: { $0.createdAt == latestDate }),
              events.filter({ $0.userId == userId && $0.id == event.id }).allSatisfy({ $0 == event }),
              event.learningCommitted == true, event.learningRevoked != true,
              [.confirmCandidate, .editPlaceIdentity, .mergeExisting].contains(event.eventType),
              let snapshot = event.afterSnapshot, snapshot.status == "saved",
              let placeID = event.userFinalPlaceId,
              let place = ownedPlaces.first(where: { $0.id == placeID }),
              matches(snapshot, place: place) else { return candidate }
        var proposed = candidate
        proposed.name = place.name
        proposed.address = place.address
        proposed.city = nil
        proposed.latitude = place.latitude
        proposed.longitude = place.longitude
        proposed.googlePlaceId = place.googlePlaceId
        proposed.category = place.category
        proposed.status = "review"
        proposed.confidence = nil // No invented model confidence for a user decision.
        proposed.missingInfo = ["Confirm the place"]
        proposed.correctionLearningPlaceID = place.id
        proposed.correctionLearningUserID = userId
        // Old provider identity fields cannot travel with the corrected identity.
        proposed.evidence = candidate.evidence.filter {
            !$0.localizedCaseInsensitiveContains("Amap POI id:") &&
            !$0.localizedCaseInsensitiveContains("Amap reference coordinates") &&
            !$0.localizedCaseInsensitiveContains("Provider map URL:") && $0 != provenance
        } + [provenance]
        return proposed
    }

    static func matches(_ snapshot: SavePlaceCorrectionSnapshot, place: Place) -> Bool {
        place.isMapKitMappable && snapshot.name == place.name && snapshot.address == place.address &&
        snapshot.latitude == place.latitude && snapshot.longitude == place.longitude
    }
}
