import Foundation

enum SaveLocalVaultError: LocalizedError {
    case storageUnavailable
    case accountDeletionScopeChanged
    case invalidLocalReviewDecision

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Savvy local memory storage is unavailable."
        case .accountDeletionScopeChanged:
            return "The pending account cleanup changed. Retry to reload its saved scope."
        case .invalidLocalReviewDecision:
            return "The local review candidate changed. Reload it before making this decision."
        }
    }
}

/// Minimal durable intent; no names, notes, tokens or other private payload.
nonisolated struct SaveAccountDeletionIntent: Codable, Sendable, Equatable {
    enum RemoteOutcome: String, Codable, Sendable {
        case awaitingRemoteResult
        case succeeded
    }
    let id: UUID
    let owner: String
    let initialOwnerlessRecordIDs: Set<UUID>
    var remoteOutcome: RemoteOutcome
    /// Pre-deletion ownerless Share-queue fingerprints. Later ownerless rows
    /// and other owners are not in this set and must stay.
    let initialOwnerlessQueueItemKeys: Set<String>
    /// Queue files that existed but could not be read at prepare. Purge drops
    /// every ownerless row in them once they are readable; still-unreadable
    /// files keep the receipt.
    let unreadableQueueFileNames: Set<String>

    enum CodingKeys: String, CodingKey {
        case id
        case owner
        case initialOwnerlessRecordIDs
        case remoteOutcome
        case initialOwnerlessQueueItemKeys
        case unreadableQueueFileNames
    }

    init(
        id: UUID,
        owner: String,
        initialOwnerlessRecordIDs: Set<UUID>,
        remoteOutcome: RemoteOutcome,
        initialOwnerlessQueueItemKeys: Set<String> = [],
        unreadableQueueFileNames: Set<String> = []
    ) {
        self.id = id
        self.owner = owner
        self.initialOwnerlessRecordIDs = initialOwnerlessRecordIDs
        self.remoteOutcome = remoteOutcome
        self.initialOwnerlessQueueItemKeys = initialOwnerlessQueueItemKeys
        self.unreadableQueueFileNames = unreadableQueueFileNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        owner = try container.decode(String.self, forKey: .owner)
        initialOwnerlessRecordIDs = try container.decode(Set<UUID>.self, forKey: .initialOwnerlessRecordIDs)
        remoteOutcome = try container.decode(RemoteOutcome.self, forKey: .remoteOutcome)
        initialOwnerlessQueueItemKeys = try container.decodeIfPresent(
            Set<String>.self, forKey: .initialOwnerlessQueueItemKeys
        ) ?? []
        unreadableQueueFileNames = try container.decodeIfPresent(
            Set<String>.self, forKey: .unreadableQueueFileNames
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(owner, forKey: .owner)
        try container.encode(initialOwnerlessRecordIDs, forKey: .initialOwnerlessRecordIDs)
        try container.encode(remoteOutcome, forKey: .remoteOutcome)
        try container.encode(initialOwnerlessQueueItemKeys, forKey: .initialOwnerlessQueueItemKeys)
        try container.encode(unreadableQueueFileNames, forKey: .unreadableQueueFileNames)
    }

    func includes(recordID: UUID, ownerSubject: String?) -> Bool {
        ownerSubject == owner || (ownerSubject == nil && initialOwnerlessRecordIDs.contains(recordID))
    }
}

final class SaveLocalVaultService: Sendable {
    static let shared = SaveLocalVaultService()

    private let fileName = "save-memory-records.json"
    private let overrideVaultURL: URL?
    private let lock = NSLock()
#if DEBUG
    nonisolated(unsafe) var removeReviewCandidateError: Error?
    nonisolated(unsafe) var saveReviewCandidateError: Error?
#endif

    init(overrideVaultURL: URL? = nil) {
        self.overrideVaultURL = overrideVaultURL
    }

    func append(_ record: SaveMemoryRecord) throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                records.insert(record, at: 0)
                try save(records, to: url)
            }
        }
    }

    func recentRecords(limit: Int = 25) throws -> [SaveMemoryRecord] {
        try recentRecords(limit: limit, belongingTo: nil, scopedToActiveAccount: false)
    }

    func recentRecords(
        limit: Int = 25,
        belongingTo currentUserId: String?
    ) throws -> [SaveMemoryRecord] {
        try recentRecords(limit: limit, belongingTo: currentUserId, scopedToActiveAccount: true)
    }

    private func recentRecords(
        limit: Int,
        belongingTo currentUserId: String?,
        scopedToActiveAccount: Bool
    ) throws -> [SaveMemoryRecord] {
        try withLock {
            try withCoordinatedVaultRead { url in
                let records = try visibleRecords(from: url)
                let scoped = scopedToActiveAccount
                    ? records.filter {
                        MapViewModel.localVaultRecordBelongsToActiveAccount(
                            $0.ownerSubject,
                            currentUserId: currentUserId
                        )
                    }
                    : records
                return Array(scoped.prefix(limit))
            }
        }
    }

    func confirmedPlaces(limit: Int = 250) throws -> [Place] {
        try confirmedPlaces(limit: limit, belongingTo: nil, scopedToActiveAccount: false)
    }

    func confirmedPlaces(
        limit: Int = 250,
        belongingTo currentUserId: String?
    ) throws -> [Place] {
        try confirmedPlaces(limit: limit, belongingTo: currentUserId, scopedToActiveAccount: true)
    }

    private func confirmedPlaces(
        limit: Int,
        belongingTo currentUserId: String?,
        scopedToActiveAccount: Bool
    ) throws -> [Place] {
        try withLock {
            try withCoordinatedVaultRead { url in
                Array(
                    Place.consolidated(
                        try visibleRecords(from: url).compactMap { record -> Place? in
                            guard record.state == .confirmedPlace else { return nil }
                            if scopedToActiveAccount,
                               !MapViewModel.localVaultRecordBelongsToActiveAccount(
                                record.ownerSubject,
                                currentUserId: currentUserId
                               ) {
                                return nil
                            }
                            return record.confirmedPlace
                        }
                    ).prefix(limit)
                )
            }
        }
    }

    func confirmedPlaceRecords(limit: Int = 250) throws -> [SaveMemoryRecord] {
        try withLock {
            try withCoordinatedVaultRead { url in
                Array(try visibleRecords(from: url).filter { $0.state == .confirmedPlace }.prefix(limit))
            }
        }
    }

    func reviewCandidates(limit: Int = 250) throws -> [PlaceReviewCandidate] {
        try reviewCandidates(limit: limit, belongingTo: nil, scopedToActiveAccount: false)
    }

    func reviewCandidates(
        limit: Int = 250,
        belongingTo currentUserId: String?
    ) throws -> [PlaceReviewCandidate] {
        try reviewCandidates(limit: limit, belongingTo: currentUserId, scopedToActiveAccount: true)
    }

    private func reviewCandidates(
        limit: Int,
        belongingTo currentUserId: String?,
        scopedToActiveAccount: Bool
    ) throws -> [PlaceReviewCandidate] {
        try withLock {
            try withCoordinatedVaultRead { url in
                let candidates = try visibleRecords(from: url)
                    .compactMap(\.reviewCandidate)
                    .filter { candidate in
                        !scopedToActiveAccount
                            || MapViewModel.localVaultRecordBelongsToActiveAccount(
                                candidate.ownerSubject,
                                currentUserId: currentUserId
                            )
                    }
                    .sorted(by: PlaceReviewCandidate.newestFirst)
                return Array(candidates.prefix(limit))
            }
        }
    }

    func deleteAllRecords() throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                try save([], to: url)
            }
        }
    }

    /// Removes only rows stamped with `ownerSubject`. Ownerless rows and every
    /// other account stay in the shared device vault.
    func deleteRecords(belongingTo ownerSubject: String) throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                records.removeAll { $0.ownerSubject == ownerSubject }
                try save(records, to: url)
            }
        }
    }

    /// Capture legacy private data before the remote deletion suspends. This does
    /// not infer ownership, and must read the entire vault rather than a UI page.
    func ownerlessRecordIDsForAccountDeletion() throws -> Set<UUID> {
        try withLock {
            try withCoordinatedVaultRead { url in
                Set(try loadRecords(from: url).filter { $0.ownerSubject == nil }.map(\.id))
            }
        }
    }

    /// Delete the account's rows and its initial legacy cleanup scope atomically.
    /// A later owner stamp or newly created ownerless row is never swept up.
    func deleteAccountRecords(
        belongingTo ownerSubject: String,
        initialOwnerlessRecordIDs: Set<UUID>
    ) throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                records.removeAll {
                    $0.ownerSubject == ownerSubject
                        || ($0.ownerSubject == nil && initialOwnerlessRecordIDs.contains($0.id))
                }
                try save(records, to: url)
            }
        }
    }

    func pendingAccountDeletionIntent() throws -> SaveAccountDeletionIntent? {
        try withLock {
            try withCoordinatedVaultRead { try loadAccountDeletionIntent(vaultURL: $0) }
        }
    }

    /// The receipt and snapshot are committed under the same cross-process lock
    /// used by vault writers/readers, before any remote DELETE may be sent.
    func prepareAccountDeletion(
        belongingTo owner: String,
        initialOwnerlessQueueItemKeys: Set<String> = [],
        unreadableQueueFileNames: Set<String> = []
    ) throws -> SaveAccountDeletionIntent {
        try withLock {
            try withCoordinatedVaultWrite { url in
                guard try loadAccountDeletionIntent(vaultURL: url) == nil else {
                    throw SaveLocalVaultError.accountDeletionScopeChanged
                }
                let records = try loadRecords(from: url)
                let intent = SaveAccountDeletionIntent(
                    id: UUID(), owner: owner,
                    initialOwnerlessRecordIDs: Set(records.filter { $0.ownerSubject == nil }.map(\.id)),
                    remoteOutcome: .awaitingRemoteResult,
                    initialOwnerlessQueueItemKeys: initialOwnerlessQueueItemKeys,
                    unreadableQueueFileNames: unreadableQueueFileNames
                )
                try JSONEncoder().encode(intent).write(to: accountDeletionIntentURL(for: url), options: .atomic)
                return intent
            }
        }
    }

    func recordRemoteAccountDeletionSuccess(intentID: UUID) throws -> SaveAccountDeletionIntent {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var intent = try matchingAccountDeletionIntent(intentID, vaultURL: url)
                intent.remoteOutcome = .succeeded
                try JSONEncoder().encode(intent).write(to: accountDeletionIntentURL(for: url), options: .atomic)
                return intent
            }
        }
    }

    func purgeAccountDeletionRecords(intentID: UUID) throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                let intent = try matchingAccountDeletionIntent(intentID, vaultURL: url)
                var records = try loadRecords(from: url)
                records.removeAll { intent.includes(recordID: $0.id, ownerSubject: $0.ownerSubject) }
                try save(records, to: url)
            }
        }
    }

    /// Caller must finish both vault and avatar cleanup first. Matching the ID
    /// prevents an old process/response from clearing a newer deletion intent.
    func completeAccountDeletionCleanup(intentID: UUID) throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                let intent = try matchingAccountDeletionIntent(intentID, vaultURL: url)
                // Recheck after avatar cleanup: an extension may have appended an
                // A-owned row since the first purge. Later ownerless/B rows stay.
                var records = try loadRecords(from: url)
                records.removeAll { intent.includes(recordID: $0.id, ownerSubject: $0.ownerSubject) }
                try save(records, to: url)
                try FileManager.default.removeItem(at: accountDeletionIntentURL(for: url))
            }
        }
    }

    private func accountDeletionIntentURL(for vaultURL: URL) -> URL {
        vaultURL.appendingPathExtension("account-deletion.json")
    }

    private func loadAccountDeletionIntent(vaultURL: URL) throws -> SaveAccountDeletionIntent? {
        let url = accountDeletionIntentURL(for: vaultURL)
        do {
            return try JSONDecoder().decode(SaveAccountDeletionIntent.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func matchingAccountDeletionIntent(_ id: UUID, vaultURL: URL) throws -> SaveAccountDeletionIntent {
        guard let intent = try loadAccountDeletionIntent(vaultURL: vaultURL), intent.id == id else {
            throw SaveLocalVaultError.accountDeletionScopeChanged
        }
        return intent
    }

    private func visibleRecords(from url: URL) throws -> [SaveMemoryRecord] {
        let intent = try loadAccountDeletionIntent(vaultURL: url)
        let records = try loadRecords(from: url)
        guard let intent else { return records }
        return records.filter { !intent.includes(recordID: $0.id, ownerSubject: $0.ownerSubject) }
    }

    func saveSourceOnly(url: URL, note: String? = nil, ownerSubject: String? = nil) throws -> SaveMemoryRecord {
        let diagnostic = sourceOnlyDiagnostic(url: url, note: note)
        let record = SaveMemoryRecord(
            state: .sourceOnly,
            sourceURL: url.absoluteString,
            sourceText: note,
            title: sourceOnlyDisplayName(for: url),
            evidence: diagnostic.candidateEvidence(extras: diagnosticSearchEvidence(diagnostic)),
            evidenceDiagnostic: diagnostic,
            ownerSubject: ownerSubject
        )
        return try upsertReviewRecord(record, matchSourceIdentity: true)
    }

    func saveReviewCandidate(
        _ candidate: PendingReviewCandidate,
        recordID: UUID? = nil,
        preservingExisting: Bool = false
    ) throws -> SaveMemoryRecord {
        let record = SaveMemoryRecord(
            id: recordID ?? UUID(),
            state: candidate.isSourceOnly ? .sourceOnly : .reviewCandidate,
            sourceURL: candidate.sourceURL,
            sourceText: candidate.sourceText,
            title: candidate.candidateName,
            placeName: candidate.isSourceOnly ? nil : candidate.candidateName,
            address: candidate.address.isEmpty ? nil : candidate.address,
            evidence: candidate.evidence,
            evidenceDiagnostic: preservingMissingInfo(candidate.missingInfo, diagnostic: candidate.evidenceDiagnostic),
            placeHighlights: candidate.placeHighlights,
            recommendedItems: candidate.recommendedItems,
            vibeTags: candidate.vibeTags,
            accessNotes: candidate.accessNotes,
            sourceHandle: candidate.sourceHandle,
            latitude: candidate.isSourceOnly ? nil : candidate.latitude,
            longitude: candidate.isSourceOnly ? nil : candidate.longitude,
            category: candidate.isSourceOnly
                ? nil
                : PlaceCategory(rawValue: candidate.category)
                    ?? PlaceCategory.inferred(from: "\(candidate.candidateName) \(candidate.address)"),
            createdAt: candidate.savedAt,
            googlePlaceId: candidate.isSourceOnly ? nil : candidate.googlePlaceId,
            semanticSource: candidate.semanticSource,
            ownerSubject: candidate.ownerSubject
        )
        guard let recordID else {
            return try upsertReviewRecord(record, matchSourceIdentity: true)
        }
        return try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                if let index = records.firstIndex(where: { $0.id == recordID && $0.ownerSubject == record.ownerSubject }) {
                    // A retry must retain already-refined evidence or a user-confirmed place.
                    let existing = records[index]
                    if preservingExisting || existing.state == .confirmedPlace { return existing }
                    let losesReviewState = existing.state == .reviewCandidate && record.state == .sourceOnly
                    let losesLocation = existing.reviewCandidate?.hasSavableLocation == true
                        && record.reviewCandidate?.hasSavableLocation != true
                    // Keep the whole stronger candidate; never combine an old branch's coordinates
                    // with the name/address/evidence of an unresolved retry.
                    if losesReviewState || losesLocation { return existing }
                    records[index] = mergingReviewEvidence(record, with: existing)
                } else {
                    records.insert(record, at: 0)
                }
                try save(records, to: url)
                return records.first { $0.id == recordID && $0.ownerSubject == record.ownerSubject } ?? record
            }
        }
    }

    func saveReviewCandidate(_ candidate: PlaceReviewCandidate, preservingParkedContext: Bool = false) throws -> SaveMemoryRecord {
#if DEBUG
        if let saveReviewCandidateError { throw saveReviewCandidateError }
#endif
        var record = SaveMemoryRecord(
            id: candidate.id,
            state: candidate.status == "source_only" ? .sourceOnly : .reviewCandidate,
            title: candidate.name,
            placeName: candidate.name,
            address: candidate.address.isEmpty ? nil : candidate.address,
            evidence: candidate.evidence,
            evidenceDiagnostic: preservingMissingInfo(candidate.missingInfo, diagnostic: nil),
            placeHighlights: candidate.placeHighlights,
            recommendedItems: candidate.recommendedItems,
            vibeTags: candidate.vibeTags,
            accessNotes: candidate.accessNotes,
            sourceHandle: candidate.sourceHandle,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            category: candidate.category ?? PlaceCategory.inferred(from: "\(candidate.name) \(candidate.address)"),
            createdAt: candidate.createdAt,
            googlePlaceId: candidate.googlePlaceId,
            semanticSource: candidate.semanticSource,
            ownerSubject: candidate.ownerSubject
        )
        if preservingParkedContext && candidate.isUnplacedInbox {
            record.parkedReviewCandidate = candidate
        }
        return try upsertReviewRecord(record, matchSourceIdentity: false)
    }

    /// Explicit user decisions may downgrade a review to a source clue. Normal
    /// evidence merges must still keep their existing protection against regressions.
    func saveLocalReviewDecision(_ candidate: PlaceReviewCandidate) throws {
        guard candidate.captureId == nil, candidate.workflowRunId == nil,
              ["source_only", "needs_more_evidence"].contains(candidate.status) else {
            throw SaveLocalVaultError.invalidLocalReviewDecision
        }
#if DEBUG
        if let saveReviewCandidateError { throw saveReviewCandidateError }
#endif
        try withLock {
            try withCoordinatedVaultWrite { url in
                if let deletion = try loadAccountDeletionIntent(vaultURL: url),
                   deletion.includes(recordID: candidate.id, ownerSubject: candidate.ownerSubject) {
                    throw SaveLocalVaultError.accountDeletionScopeChanged
                }
                var records = try loadRecords(from: url)
                guard let index = records.firstIndex(where: {
                    $0.id == candidate.id && $0.ownerSubject == candidate.ownerSubject
                        && ($0.state == .reviewCandidate || $0.state == .sourceOnly)
                }) else { throw SaveLocalVaultError.invalidLocalReviewDecision }
                // Keep the record's source payload, date, venue and merged context;
                // replace the old parked snapshot so it cannot undo this decision.
                records[index].state = candidate.status == "source_only" ? .sourceOnly : .reviewCandidate
                records[index].parkedReviewCandidate = candidate
                for evidence in candidate.evidence where !records[index].evidence.contains(evidence) {
                    records[index].evidence.append(evidence)
                }
                records[index].evidenceDiagnostic = preservingMissingInfo(
                    candidate.missingInfo, diagnostic: records[index].evidenceDiagnostic
                )
                try save(records, to: url)
            }
        }
    }

    private func preservingMissingInfo(_ fields: [String], diagnostic: SocialPlaceEvidenceDiagnostic?) -> SocialPlaceEvidenceDiagnostic? {
        guard !fields.isEmpty else { return diagnostic }
        var result = diagnostic ?? SocialPlaceEvidenceDiagnostic(found: [], attempts: [], missingFields: [], nextBestClue: "")
        for field in fields where !result.missingFields.contains(field) { result.missingFields.append(field) }
        return result
    }

    private func upsertReviewRecord(_ incoming: SaveMemoryRecord, matchSourceIdentity: Bool) throws -> SaveMemoryRecord {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                let index = records.firstIndex { existing in
                    guard existing.ownerSubject == incoming.ownerSubject else { return false }
                    if existing.id == incoming.id { return true }
                    guard matchSourceIdentity,
                          existing.ownerSubject == incoming.ownerSubject,
                          let source = SaveSourceIdentity.url(incoming.sourceURL),
                          source == SaveSourceIdentity.url(existing.sourceURL),
                          existing.state == incoming.state else { return false }
                    if incoming.state == .sourceOnly { return true }
                    guard let candidate = existing.reviewCandidate else { return false }
                    return candidate.matchesImport(PendingReviewCandidate(
                        candidateName: incoming.displayTitle, address: incoming.address ?? "", category: "other",
                        latitude: incoming.latitude, longitude: incoming.longitude,
                        sourceURL: incoming.sourceURL, sourceText: incoming.sourceText, evidence: incoming.evidence,
                        confidence: 0, missingInfo: [], savedAt: incoming.createdAt, googlePlaceId: incoming.googlePlaceId, semanticSource: incoming.semanticSource
                    ))
                }
                let record: SaveMemoryRecord
                if let index {
                    let existing = records[index]
                    if existing.state == .confirmedPlace { return existing }
                    record = mergingReviewEvidence(incoming, with: existing)
                    records[index] = record
                } else {
                    record = incoming
                    records.insert(record, at: 0)
                }
                try save(records, to: url)
                return record
            }
        }
    }

    private func mergingReviewEvidence(_ incoming: SaveMemoryRecord, with existing: SaveMemoryRecord) -> SaveMemoryRecord {
        let losesLocation = existing.reviewCandidate?.hasSavableLocation == true
            && incoming.reviewCandidate?.hasSavableLocation != true
        var merged = losesLocation || (existing.state == .reviewCandidate && incoming.state == .sourceOnly)
            ? existing : incoming
        merged.id = existing.id
        merged.createdAt = min(existing.createdAt, incoming.createdAt)
        merged.sourceURL = existing.sourceURL ?? incoming.sourceURL
        var seen = Set<String>()
        // Re-parking a stable recipient ID carries the current live venue. Old
        // provider coordinates must not remain the first active location after
        // an author corrects that venue (or switches it back to WGS84).
        let replacesVenue = incoming.id == existing.id
            && incoming.reviewCandidate?.isUnplacedInbox == true
            && incoming.reviewCandidate?.hasSavableLocation == true
        let activeProviderPrefixes = ["Amap POI id:", "Amap reference coordinates (GCJ-02):", "Provider map URL:"]
        let previousEvidence = replacesVenue ? existing.evidence.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !activeProviderPrefixes.contains { trimmed.lowercased().hasPrefix($0.lowercased()) }
        } : existing.evidence
        let evidence = replacesVenue ? incoming.evidence + previousEvidence : previousEvidence + incoming.evidence
        merged.evidence = evidence.filter { seen.insert($0).inserted }
        let texts = [existing.sourceText, incoming.sourceText].compactMap { $0 }.filter { !$0.isEmpty }
        seen.removeAll()
        merged.sourceText = texts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        merged.sourceHandle = SaveSourceHandle.displayable(incoming.sourceHandle)
            ?? SaveSourceHandle.displayable(existing.sourceHandle)
            ?? SaveSourceHandle.stored(incoming.sourceHandle)
            ?? SaveSourceHandle.stored(existing.sourceHandle)
        merged.ownerSubject = existing.ownerSubject ?? incoming.ownerSubject
        merged.parkedReviewCandidate = incoming.parkedReviewCandidate ?? existing.parkedReviewCandidate
        return merged
    }

    func saveConfirmedPlace(_ incoming: Place, ownerSubject: String? = nil) throws -> SaveMemoryRecord {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                let matches = records.compactMap { record -> Place? in
                    guard record.state == .confirmedPlace,
                          record.ownerSubject == ownerSubject else { return nil }
                    return record.confirmedPlace
                }.filter { $0.matches(incoming) }
                // Keep current edits, and retain all prior source evidence and trip IDs.
                let place = matches.reduce(incoming) { $0.mergingSources(from: $1) }
                let record = SaveMemoryRecord(
                    id: place.id,
                    state: .confirmedPlace,
                    sourceURL: place.sourceUrl,
                    sourceText: place.note,
                    title: place.name,
                    placeName: place.name,
                    address: place.address,
                    evidence: confirmedPlaceEvidence(place),
                    placeHighlights: place.savedPlaceHighlights,
                    recommendedItems: place.savedRecommendedItems,
                    vibeTags: place.savedVibeTags,
                    accessNotes: place.savedAccessNotes,
                    sourceHandle: place.savedSourceHandle,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    category: place.category,
                    status: place.status,
                    rating: place.rating ?? place.googleRating,
                    createdAt: place.createdAt,
                    googlePlaceId: place.googlePlaceId,
                    coordinateSystem: place.coordinateSystem,
                    locationProvider: place.locationProvider,
                    providerPlaceId: place.providerPlaceId,
                    providerMapUrl: place.providerMapUrl,
                    sourceImageUrl: GooglePlacesPhotoURL.persistableString(place.sourceImageUrl),
                    businessPhotoUrls: GooglePlacesPhotoURL.persistableStrings(place.businessPhotoUrls),
                    mergedPlaceIDs: place.mergedPlaceIDs,
                    ownerSubject: ownerSubject
                )
                records.removeAll { record in
                    record.state == .confirmedPlace && place.savedIDs.contains(record.id)
                }
                records.insert(record, at: 0)
                try save(records, to: url)
                return record
            }
        }
    }

    func removeConfirmedPlace(_ place: Place) throws {
        try removeConfirmedPlace(place, belongingTo: nil, scopedToActiveAccount: false)
    }

    func removeConfirmedPlace(_ place: Place, belongingTo currentUserId: String?) throws {
        try removeConfirmedPlace(place, belongingTo: currentUserId, scopedToActiveAccount: true)
    }

    private func removeConfirmedPlace(
        _ place: Place,
        belongingTo currentUserId: String?,
        scopedToActiveAccount: Bool
    ) throws {
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                records.removeAll { record in
                    guard let confirmed = record.confirmedPlace else { return false }
                    if scopedToActiveAccount,
                       !MapViewModel.localVaultRecordBelongsToActiveAccount(
                            record.ownerSubject,
                            currentUserId: currentUserId
                       ) {
                        return false
                    }
                    return place.savedIDs.contains(confirmed.id) || confirmed.matches(place)
                }
                try save(records, to: url)
            }
        }
    }

    func removeReviewCandidate(_ candidateID: UUID, ownerSubject: String? = nil) throws {
#if DEBUG
        if let removeReviewCandidateError { throw removeReviewCandidateError }
#endif
        try withLock {
            try withCoordinatedVaultWrite { url in
                var records = try loadRecords(from: url)
                records.removeAll { ($0.state == .reviewCandidate || $0.state == .sourceOnly) && $0.id == candidateID && $0.ownerSubject == ownerSubject }
                try save(records, to: url)
            }
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func confirmedPlaceEvidence(_ place: Place) -> [String] {
        var evidence: [String] = []
        if let sourceUrl = place.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceUrl.isEmpty {
            evidence.append("Source URL: \(sourceUrl)")
        }
        if let sourceHandle = place.savedSourceHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceHandle.isEmpty {
            evidence.append("Source handle: @\(sourceHandle)")
        }
        evidence.append(contentsOf: place.savedAdditionalSourceEvidence)
        evidence.append(contentsOf: place.savedPlaceHighlights.map { "Highlight: \($0)" })
        evidence.append(contentsOf: place.savedRecommendedItems.map { "Highlight: Recommended item: \($0.displayText)" })
        evidence.append(contentsOf: place.savedVibeTags.map { "Vibe: \($0)" })
        evidence.append(contentsOf: place.savedAccessNotes.map { "Access: \($0)" })
        if let note = place.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            evidence.append(note)
        }
        var seen = Set<String>()
        return evidence.filter { seen.insert($0).inserted }
    }

    private func loadRecords(from url: URL) throws -> [SaveMemoryRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.saveVault.decode([SaveMemoryRecord].self, from: data)
    }

    private func save(_ records: [SaveMemoryRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.saveVault.encode(records)
        try data.write(to: url, options: [.atomic])
    }

    private func withCoordinatedVaultRead<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let url = vaultURL() else { throw SaveLocalVaultError.storageUnavailable }
        return try coordinate(url: url, writing: false, operation)
    }

    private func withCoordinatedVaultWrite<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let url = vaultURL() else { throw SaveLocalVaultError.storageUnavailable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try coordinate(url: url, writing: true, operation)
    }

    private func coordinate<T>(
        url: URL,
        writing: Bool,
        _ operation: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?

        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                result = Result { try operation(coordinatedURL) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                result = Result { try operation(coordinatedURL) }
            }
        }

        if let coordinationError { throw coordinationError }
        guard let result else { throw SaveLocalVaultError.storageUnavailable }
        return try result.get()
    }

    private func vaultURL() -> URL? {
        if let overrideVaultURL { return overrideVaultURL }
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName) {
            return appGroupURL.appendingPathComponent(fileName)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    private func sourceOnlyDisplayName(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("/reel/") || path.contains("/reels/") { return "Instagram reel" }
        if url.host()?.lowercased().contains("instagram") == true { return "Instagram link" }
        if url.host()?.lowercased().matchesDomain("xiaohongshu.com") == true || url.host()?.lowercased().matchesDomain("xhslink.com") == true { return "Xiaohongshu link" }
        if url.host()?.lowercased().matchesDomain("douyin.com") == true || url.host()?.lowercased().matchesDomain("iesdouyin.com") == true { return "Douyin link" }
        if url.host()?.lowercased().matchesDomain("dianping.com") == true || url.host()?.lowercased().matchesDomain("dpurl.cn") == true { return "Dianping link" }
        if url.host()?.lowercased().matchesDomain("meituan.com") == true { return "Meituan link" }
        if url.host()?.lowercased().matchesDomain("ele.me") == true { return "Taobao Instant Commerce link" }
        if SocialShareTextNormalizer.isGenericTaobaoProductURL(url.absoluteString) { return "Taobao product link" }
        return url.host() ?? url.absoluteString
    }

    private func sourceOnlyDiagnostic(url: URL, note: String?) -> SocialPlaceEvidenceDiagnostic {
        var found = ["Source URL: \(url.absoluteString)"]
        if note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            found.append("Shared text/caption was present but did not contain a verified place candidate")
        }
        let searchQueries = sourceRecoverySearchQueries(url: url, note: note)
        return SocialPlaceEvidenceDiagnostic(
            found: found,
            attempts: [
                "Saved the original source before place evidence was verified",
                "Kept this as a source-only clue instead of inventing a place",
                "Prepared public web search fallback queries for source-only recovery"
            ],
            missingFields: [
                "Verified place name",
                "Verified address",
                "Verified coordinates"
            ],
            nextBestClue: "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.",
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries,
            recoveryPlan: SocialPlaceEvidenceRecoveryPlan(
                sourceURL: url.absoluteString,
                evidenceAtoms: sourceOnlyEvidenceAtoms(url: url, note: note),
                queriesToTry: searchQueries,
                blockedResultHints: [
                    "creator profile without venue name/address",
                    "generic social shell or login wall",
                    "aggregator/list page without address or map coordinates",
                    "map home/directions page without canonical place identity"
                ],
                requiredEvidence: [
                    "Verified place name",
                    "Verified address",
                    "Verified coordinates"
                ],
                decision: .sourceOnly,
                allowsDirectSave: false
            ),
            rejectedEvidence: [
                SocialPlaceRejectedEvidence(value: "source-only link", reason: "kept as receipt until place evidence is verified")
            ]
        )
    }

    private func diagnosticSearchEvidence(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> [String] {
        (diagnostic.suggestedSearchQueries ?? []).map { "Suggested public search: \($0)" }
    }

    private func sourceOnlyEvidenceAtoms(url: URL, note: String?) -> [String] {
        var atoms = [
            "source_url: \(url.absoluteString)",
            "source_host: \(url.host() ?? "unknown")"
        ]
        if note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            atoms.append("shared_note: present")
        } else {
            atoms.append("shared_note: none")
        }
        return atoms
    }

    private func sourceRecoverySearchQueries(url: URL, note: String?) -> [String] {
        var queries: [String] = []
        let host = url.host()?.lowercased() ?? ""
        if let reelID = instagramReelID(in: url) {
            queries.append("instagram reel \(reelID) place")
            queries.append("\(reelID) restaurant venue")
        } else if !host.isEmpty {
            queries.append("\(host) \(url.lastPathComponent) place")
        }

        let cleanedNote = (note ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedNote.isEmpty {
            queries.append("\"\(String(cleanedNote.prefix(80)))\" place")
        }

        if let canonicalURL = canonicalSearchURL(from: url) {
            queries.append("\"\(canonicalURL)\"")
        }

        return Array(appendUnique([], queries).prefix(4))
    }

    private func instagramReelID(in url: URL) -> String? {
        guard url.host()?.lowercased().contains("instagram") == true else { return nil }
        let components = url.pathComponents
        guard let markerIndex = components.firstIndex(where: { $0.lowercased() == "reel" || $0.lowercased() == "reels" }),
              components.indices.contains(markerIndex + 1) else { return nil }
        let id = components[markerIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return id.isEmpty ? nil : id
    }

    private func canonicalSearchURL(from url: URL) -> String? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let value = components?.url?.absoluteString ?? url.absoluteString
        return value.isEmpty ? nil : value
    }

    private func appendUnique(_ values: [String], _ newValues: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values + newValues {
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private extension SaveMemoryRecord {
    var reviewCandidate: PlaceReviewCandidate? {
        guard state == .reviewCandidate || state == .sourceOnly else { return nil }
        let name = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var candidate = PlaceReviewCandidate(
            id: id,
            captureId: nil,
            name: name,
            address: (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            city: nil,
            latitude: latitude,
            longitude: longitude,
            evidence: (evidence + [sourceText ?? ""] + (sourceURL.map { ["Source URL: \($0)"] } ?? []))
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.reduce(into: [String]()) {
                    if !$0.contains($1) { $0.append($1) }
                },
            confidence: nil,
            missingInfo: evidenceDiagnostic?.missingFields ?? [],
            status: state == .sourceOnly ? "source_only" : "review",
            createdAt: createdAt,
            placeHighlights: placeHighlights,
            recommendedItems: recommendedItems,
            vibeTags: vibeTags,
            accessNotes: accessNotes,
            sourceHandle: sourceHandle,
            googlePlaceId: googlePlaceId,
            category: category,
            semanticSource: semanticSource,
            ownerSubject: ownerSubject
        )
        if let parked = parkedReviewCandidate,
           parked.id == id, parked.ownerSubject == ownerSubject,
           parked.isUnplacedInbox || (parked.captureId == nil && parked.workflowRunId == nil
                && ["source_only", "needs_more_evidence"].contains(parked.status)) {
            // The record owns merged venue/evidence fields; the validated snapshot
            // supplies context the generic vault projection cannot represent.
            candidate.captureId = parked.captureId
            candidate.workflowRunId = parked.workflowRunId
            candidate.city = parked.city
            candidate.confidence = parked.confidence
            candidate.correctionScopeKey = parked.correctionScopeKey
            candidate.supersededByCandidateID = parked.supersededByCandidateID
            candidate.supersededByCandidateIDs = parked.supersededByCandidateIDs
            candidate.status = state == .sourceOnly ? "source_only" : parked.status
            for field in parked.missingInfo where !candidate.missingInfo.contains(field) {
                candidate.missingInfo.append(field)
            }
        }
        return candidate
    }

    var confirmedPlace: Place? {
        guard state == .confirmedPlace else { return nil }
        guard let latitude, let longitude, latitude != 0 || longitude != 0 else { return nil }

        let name = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let address = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Place(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: googlePlaceId,
            category: category ?? PlaceCategory.inferred(from: "\(name) \(address)"),
            status: status ?? .wantToGo,
            rating: rating,
            note: sourceText,
            sourceUrl: sourceURL,
            sourcePlatform: SourcePlatform.from(urlString: sourceURL),
            coordinateSystem: coordinateSystem,
            locationProvider: locationProvider,
            providerPlaceId: providerPlaceId,
            providerMapUrl: providerMapUrl,
            sourceImageUrl: GooglePlacesPhotoURL.persistableString(sourceImageUrl),
            businessPhotoUrls: GooglePlacesPhotoURL.persistableStrings(businessPhotoUrls),
            extractedDishes: recommendedItems.map(\.name).nilIfEmpty,
            priceRange: nil,
            recommender: sourceHandle,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: createdAt,
            visibility: .privateMemory,
            socialSignal: nil,
            placeHighlights: placeHighlights.nilIfEmpty,
            recommendedItems: recommendedItems.nilIfEmpty,
            vibeTags: vibeTags.nilIfEmpty,
            accessNotes: accessNotes.nilIfEmpty,
            sourceHandle: sourceHandle,
            mergedPlaceIDs: mergedPlaceIDs,
            additionalSourceEvidence: evidence.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                if Place.isGeneratedEvidenceLine(trimmed) || Place.isStructuredEvidenceLine(trimmed) { return false }
                if trimmed == sourceText { return false }
                if let sourceURL, trimmed == "Source URL: \(sourceURL)" { return false }
                return true
            }.nilIfEmpty
        )
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

private extension JSONEncoder {
    static var saveVault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var saveVault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    func matchesDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }
}
