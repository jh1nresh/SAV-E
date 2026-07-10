import Foundation

enum SavePlaceCorrectionEventType: String, Codable {
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
        case .confirmCandidate, .mergeExisting:
            return "confirm"
        case .wrongPlace, .rejectCandidate:
            return "reject"
        case .investigateMore:
            return "needs_more_evidence"
        case .wrongCity, .wrongBranch:
            return "needs_more_evidence"
        case .saveSourceOnly:
            return "save_source_only"
        case .editPlaceIdentity, .editAddress, .addReason, .changeCollection:
            return "edit"
        }
    }
}

struct SavePlaceCorrectionSnapshot: Codable, Equatable {
    var name: String
    var address: String
    var city: String?
    var status: String
    var latitude: Double?
    var longitude: Double?

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

struct SavePlaceCorrectionEvent: Identifiable, Codable, Equatable {
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

final class SavePlaceCorrectionEventStore {
    static let shared = SavePlaceCorrectionEventStore()

    private let fileManager: FileManager
    private let overrideURL: URL?
    private let fileName = "save-place-correction-events.json"
    private let queue = DispatchQueue(label: "com.save.place-correction-event-store")

    init(fileManager: FileManager = .default, overrideURL: URL? = nil) {
        self.fileManager = fileManager
        self.overrideURL = overrideURL
    }

    func append(_ event: SavePlaceCorrectionEvent) throws {
        try queue.sync {
            var events = try recentEventsUnlocked(limit: 999)
            events.insert(event, at: 0)
            guard let url = storageURL else { throw SaveLocalVaultError.storageUnavailable }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    private func recentEventsUnlocked(limit: Int) throws -> [SavePlaceCorrectionEvent] {
        guard let url = storageURL else { throw SaveLocalVaultError.storageUnavailable }
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Array(try decoder.decode([SavePlaceCorrectionEvent].self, from: Data(contentsOf: url)).prefix(limit))
    }

    private var storageURL: URL? {
        if let overrideURL { return overrideURL }
        if let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName) {
            return appGroupURL.appendingPathComponent(fileName)
        }
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
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
