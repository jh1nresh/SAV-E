import Foundation

// MARK: - Protocol

protocol SupabaseServiceProtocol {
    func fetchPlaces(for userId: String) async throws -> [Place]
    func savePlace(_ place: Place, userId: String) async throws
    func saveFriendSharedPlace(_ place: Place, code: String, userId: String) async throws -> FriendSharedPlaceSaveResult
    func updatePlace(_ place: Place) async throws
    func deletePlace(_ placeId: UUID) async throws
    func createMemoryCapture(from candidate: PendingReviewCandidate, userId: String) async throws -> UUID
    func createPlaceCandidate(_ candidate: PendingReviewCandidate, captureId: UUID, userId: String, workflowRunId: UUID?) async throws -> UUID
    func recoverSourceOnlyReviewCandidates(captureId: UUID, workflowRunId: UUID?) async throws -> [PlaceReviewCandidate]
    func fetchReviewCandidates() async throws -> [PlaceReviewCandidate]
    func updatePlaceCandidateStatus(_ candidateId: UUID, status: String, placeId: UUID?) async throws
    func createPlaceRecoveryWorkOrder(sourceURL: String?, sourceType: String?) async throws -> PlaceRecoveryWorkOrder
    func createPlaceRecoveryRun(workOrderId: UUID?, sourceURL: String?, sourceType: String?) async throws -> PlaceRecoveryWorkflowRun
    func recordPlaceRecoveryResult(_ result: PlaceRecoveryResultDraft, for runId: UUID) async throws -> PlaceRecoveryWorkflowRun
    func recordPlaceRecoveryDecision(_ decision: PlaceRecoveryDecisionDraft, for runId: UUID) async throws -> PlaceRecoveryDecisionReceiptResponse
    func fetchTrips(for userId: String) async throws -> [Trip]
    func saveTrip(_ trip: Trip, userId: String) async throws
    func updateTrip(_ trip: Trip) async throws
    func deleteTrip(_ tripId: UUID) async throws
    func fetchProfile(for userId: String) async throws -> UserProfile?
    func updateProfile(_ profile: UserProfile) async throws
    func fetchFollowedFriends() async throws -> [SaveFollowedFriend]
    func followProfile(referralCode: String, lens: SaveSocialLens, source: SaveFollowSource) async throws
    func followProfile(target: SaveReferralTarget, source: SaveFollowSource) async throws
    func fetchReferralProfile(target: SaveReferralTarget) async throws -> SaveReferralProfile
    func fetchSocialSignals(lens: SaveSocialLens) async throws -> [Place]
    func updatePlaceVisibility(_ visibility: PlaceVisibility, for placeId: UUID) async throws
    func createSharedPlaceLink(
        payload: SharedPlaceData,
        sourcePlaceId: UUID?,
        noteConsentVersion: Int?
    ) async throws -> URL
    func recordFriendShareEvent(
        code: String,
        event: FriendShareReceiptEvent,
        failureReason: FriendShareOpenFailureReason?
    ) async throws
    func fetchVerifiedPlaceClaims(for placeId: UUID, includePrivateEvidence: Bool) async throws -> [VerifiedPlaceClaim]
    func createVerifiedPlaceClaim(_ draft: VerifiedPlaceClaimDraft, for placeId: UUID) async throws -> VerifiedPlaceClaim
    func fetchPlaceTrustSummary(for placeId: UUID) async throws -> PlaceTrustSummaryResponse
    func fetchPlaceMaatAnalysis(for placeId: UUID, includePrivateEvidence: Bool, includePublicWeb: Bool) async throws -> MaatPlaceAnalysisResponse
    func recommendPlacesByClaims(_ request: ClaimRecommendationRequest) async throws -> ClaimRecommendationResponse
    func recordRecommendationAnalysisReceipt(_ receipt: RecommendationAnalysisReceiptDraft) async throws -> SaveRecommendationAnalysisReceipt
    func fetchMemoryPreferences() async throws -> [SaveMemoryPreference]
    func createMemoryPreference(_ draft: SaveMemoryPreferenceDraft) async throws -> SaveMemoryPreference
    func updateMemoryPreference(_ preferenceId: UUID, status: SaveMemoryPreference.Status) async throws -> SaveMemoryPreference
    func correctMemoryPreference(_ preferenceId: UUID, draft: SaveMemoryPreferenceDraft) async throws -> SaveMemoryPreference
    func fetchPublicPlaceCard(cardId: UUID) async throws -> PublicPlaceCard
    func createClaimUsageReceipt(_ receipt: ClaimUsageReceiptDraft, requiresAuth: Bool) async throws -> ClaimUsageReceipt
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case recordNotFound
    case networkError(Error)
    case apiError(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "SAV-E API not configured"
        case .notAuthenticated: return "User not authenticated"
        case .recordNotFound: return "Record not found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let msg): return "SAV-E API error \(code): \(msg)"
        case .invalidResponse(let message): return message
        }
    }
}

// MARK: - Implementation

final class SupabaseService: SupabaseServiceProtocol, AccountStatusProviding {
    static let shared = SupabaseService()

    private let apiBaseURL: String?

    init() {
        if let explicit = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]) {
            self.apiBaseURL = explicit
        } else {
            self.apiBaseURL = nil
        }
    }

    private var isConfigured: Bool {
        apiBaseURL != nil
    }

    // MARK: - Places

    func fetchPlaces(for userId: String) async throws -> [Place] {
        guard isConfigured else { return [] }

        let data = try await request(path: "/places")

        let rows = try JSONDecoder.supabase.decode([PlaceRow].self, from: data)
        return rows.map { $0.toPlace() }
    }

    func savePlace(_ place: Place, userId: String) async throws {
        guard isConfigured else { return }

        let row = PlaceRow.from(place: place, userId: userId)
        let body = try JSONEncoder.supabase.encode(row)

        try await request(path: "/places", method: "POST", body: body)
    }

    func saveFriendSharedPlace(
        _ place: Place,
        code: String,
        userId: String
    ) async throws -> FriendSharedPlaceSaveResult {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let row = PlaceRow.from(place: place, userId: userId, friendShareCode: code)
        let body = try JSONEncoder.supabase.encode(row)
        let data = try await request(path: "/places", method: "POST", body: body)
        let response = try JSONDecoder.supabase.decode(FriendSharedPlaceSaveResponse.self, from: data)
        guard let outcome = FriendSharedPlaceSaveResult.Outcome(rawValue: response.outcome) else {
            throw SupabaseError.invalidResponse("SAV-E returned an invalid friend share save outcome")
        }
        return FriendSharedPlaceSaveResult(place: response.place.toPlace(), outcome: outcome)
    }

    func updatePlace(_ place: Place) async throws {
        guard isConfigured else { return }

        let updates: [String: Any?] = [
            "name": place.name,
            "address": place.address,
            "category": place.category.rawValue,
            "status": place.status.rawValue,
            "rating": place.rating,
            "note": place.note,
        ]
        let body = try Self.jsonBody(updates)

        try await request(path: "/places/\(place.id)", method: "PATCH", body: body)
    }

    func deletePlace(_ placeId: UUID) async throws {
        guard isConfigured else { return }
        try await request(path: "/places/\(placeId)", method: "DELETE")
    }

    func updatePlaceVisibility(_ visibility: PlaceVisibility, for placeId: UUID) async throws {
        guard isConfigured else { return }

        let body = try Self.jsonBody([
            "visibility": visibility.rawValue,
            "allow_friend_signal": visibility.allowsFriendSignal,
            "allow_trending_signal": visibility.allowsTrendingSignal,
        ])
        try await request(path: "/places/\(placeId)/visibility", method: "PATCH", body: body)
    }

    func createSharedPlaceLink(
        payload: SharedPlaceData,
        sourcePlaceId: UUID?,
        noteConsentVersion: Int? = nil
    ) async throws -> URL {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try JSONEncoder.supabase.encode(SharedPlaceLinkCreateBody(
            payload: payload,
            source_place_id: sourcePlaceId?.uuidString,
            note_consent_version: noteConsentVersion
        ))
        let data = try await request(path: "/v0/shared-place-links", method: "POST", body: body)
        let row = try JSONDecoder.supabase.decode(SharedPlaceLinkRow.self, from: data)
        guard let url = URL(string: row.url) else { throw SupabaseError.recordNotFound }
        return url
    }

    func recordFriendShareEvent(
        code: String,
        event: FriendShareReceiptEvent,
        failureReason: FriendShareOpenFailureReason? = nil
    ) async throws {
        guard isConfigured else { return }

        var payload: [String: Any] = [
            "code": code,
            "event_type": event.rawValue,
            "surface": FriendShareReceiptSurface.ios.rawValue,
        ]
        if let failureReason {
            payload["reason_code"] = failureReason.rawValue
        }
        let body = try Self.jsonBody(payload)
        try await request(path: "/v0/friend-share-events", method: "POST", body: body)
    }

    // MARK: - KML Export

    func exportTrekKml(placeIds: [UUID]) async throws -> Data {
        let body = try Self.trekKmlExportRequestBody(placeIds: placeIds)
        let (data, response) = try await requestWithResponse(
            path: "/v0/exports/trek-kml",
            method: "POST",
            body: body
        )
        guard Self.isValidTrekKmlResponse(data, mimeType: response.mimeType) else {
            throw SupabaseError.invalidResponse("SAV-E returned an invalid KML file")
        }
        return data
    }

    static func trekKmlExportRequestBody(placeIds: [UUID]) throws -> Data {
        guard (1...100).contains(placeIds.count), Set(placeIds).count == placeIds.count else {
            throw SupabaseError.apiError(422, "KML export requires 1 to 100 unique place IDs")
        }
        return try jsonBody([
            "place_ids": placeIds.map { $0.uuidString.lowercased() }
        ])
    }

    static func isValidTrekKmlResponse(_ data: Data, mimeType: String?) -> Bool {
        guard data.count <= 2_097_152,
              mimeType?.lowercased() == "application/vnd.google-earth.kml+xml" else {
            return false
        }
        let delegate = KmlRootElementParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.rootElementName == "kml"
    }

    static func httpError(statusCode: Int, body: String) -> SupabaseError {
        if statusCode == 401 || statusCode == 403 {
            return .notAuthenticated
        }
        return .apiError(statusCode, body)
    }

    // MARK: - Verified Place Claims

    func fetchVerifiedPlaceClaims(for placeId: UUID, includePrivateEvidence: Bool = false) async throws -> [VerifiedPlaceClaim] {
        guard isConfigured else { return [] }

        let suffix = includePrivateEvidence ? "?includePrivateEvidence=true" : ""
        let data = try await request(path: "/v0/places/\(placeId.uuidString)/verified-claims\(suffix)")
        let row = try JSONDecoder.supabase.decode(VerifiedPlaceClaimsResponse.self, from: data)
        return row.claims
    }

    func createVerifiedPlaceClaim(_ draft: VerifiedPlaceClaimDraft, for placeId: UUID) async throws -> VerifiedPlaceClaim {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody(draft.body)
        let data = try await request(path: "/v0/places/\(placeId.uuidString)/verified-claims", method: "POST", body: body)
        return try JSONDecoder.supabase.decode(VerifiedPlaceClaim.self, from: data)
    }

    func fetchPlaceTrustSummary(for placeId: UUID) async throws -> PlaceTrustSummaryResponse {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let data = try await request(path: "/v0/places/\(placeId.uuidString)/trust-summary")
        return try JSONDecoder.supabase.decode(PlaceTrustSummaryResponse.self, from: data)
    }

    func fetchPlaceMaatAnalysis(for placeId: UUID, includePrivateEvidence: Bool = false, includePublicWeb: Bool = true) async throws -> MaatPlaceAnalysisResponse {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let queryItems = [
            includePrivateEvidence ? "includePrivateEvidence=true" : nil,
            includePublicWeb ? "includePublicWeb=true" : nil,
        ].compactMap { $0 }
        let suffix = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        let data = try await request(path: "/v0/places/\(placeId.uuidString)/maat-analysis\(suffix)")
        return try JSONDecoder.supabase.decode(MaatPlaceAnalysisResponse.self, from: data)
    }

    func recommendPlacesByClaims(_ request: ClaimRecommendationRequest) async throws -> ClaimRecommendationResponse {
        guard isConfigured else { return .empty }

        let body = try Self.jsonBody(request.body)
        let data = try await self.request(path: "/v0/places/recommend-by-claims", method: "POST", body: body)
        return try JSONDecoder.supabase.decode(ClaimRecommendationResponse.self, from: data)
    }

    func recordRecommendationAnalysisReceipt(_ receipt: RecommendationAnalysisReceiptDraft) async throws -> SaveRecommendationAnalysisReceipt {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody(receipt.body)
        let data = try await request(path: "/v0/recommendation-analysis-receipts", method: "POST", body: body)
        return try JSONDecoder.supabase.decode(SaveRecommendationAnalysisReceipt.self, from: data)
    }

    // MARK: - Explicit Memory

    func fetchMemoryPreferences() async throws -> [SaveMemoryPreference] {
        guard isConfigured else { return [] }
        let data = try await request(path: "/v0/memory-preferences")
        return try JSONDecoder.supabase.decode([SaveMemoryPreference].self, from: data)
    }

    func createMemoryPreference(_ draft: SaveMemoryPreferenceDraft) async throws -> SaveMemoryPreference {
        guard isConfigured else { throw SupabaseError.notConfigured }
        let data = try await request(
            path: "/v0/memory-preferences",
            method: "POST",
            body: try JSONEncoder.supabase.encode(draft)
        )
        return try JSONDecoder.supabase.decode(SaveMemoryPreference.self, from: data)
    }

    func updateMemoryPreference(_ preferenceId: UUID, status: SaveMemoryPreference.Status) async throws -> SaveMemoryPreference {
        guard isConfigured else { throw SupabaseError.notConfigured }
        let data = try await request(
            path: "/v0/memory-preferences/\(preferenceId.uuidString)",
            method: "PATCH",
            body: try Self.jsonBody(["status": status.rawValue])
        )
        return try JSONDecoder.supabase.decode(SaveMemoryPreference.self, from: data)
    }

    func correctMemoryPreference(_ preferenceId: UUID, draft: SaveMemoryPreferenceDraft) async throws -> SaveMemoryPreference {
        guard isConfigured else { throw SupabaseError.notConfigured }
        let data = try await request(
            path: "/v0/memory-preferences/\(preferenceId.uuidString)/corrections",
            method: "POST",
            body: try JSONEncoder.supabase.encode(draft)
        )
        return try JSONDecoder.supabase.decode(SaveMemoryPreference.self, from: data)
    }

    func fetchPublicPlaceCard(cardId: UUID) async throws -> PublicPlaceCard {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let data = try await request(path: "/public/v0/cards/\(cardId.uuidString)", requiresAuth: false)
        return try JSONDecoder.supabase.decode(PublicPlaceCard.self, from: data)
    }

    func createClaimUsageReceipt(_ receipt: ClaimUsageReceiptDraft, requiresAuth: Bool = true) async throws -> ClaimUsageReceipt {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let path = requiresAuth ? "/v0/claims/usage-receipts" : "/public/v0/claim-usage-receipts"
        let body = try Self.jsonBody(receipt.body)
        let data = try await request(path: path, method: "POST", body: body, requiresAuth: requiresAuth)
        return try JSONDecoder.supabase.decode(ClaimUsageReceipt.self, from: data)
    }

    // MARK: - Memory Candidates

    func createMemoryCapture(from candidate: PendingReviewCandidate, userId: String) async throws -> UUID {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody([
            "source_type": "url",
            "source_url": candidate.sourceURL,
            "raw_text": candidate.sourceText,
            "title": candidate.candidateName,
            "status": "review",
        ])
        let data = try await request(path: "/memory/captures", method: "POST", body: body)
        let row = try JSONDecoder.supabase.decode(MemoryCaptureRow.self, from: data)
        return row.id
    }

    func createPlaceCandidate(_ candidate: PendingReviewCandidate, captureId: UUID, userId: String, workflowRunId: UUID? = nil) async throws -> UUID {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let evidence = candidate.evidence.map { ["text": $0] }
        let body = try Self.jsonBody([
            "capture_id": captureId.uuidString,
            "workflow_run_id": workflowRunId?.uuidString,
            "name": candidate.candidateName,
            "address": candidate.address,
            "city": "",
            "latitude": candidate.latitude,
            "longitude": candidate.longitude,
            "evidence": evidence,
            "confidence": candidate.confidence,
            "missing_info": candidate.missingInfo,
            "status": "review",
        ])
        let data = try await request(path: "/memory/candidates", method: "POST", body: body)
        let row = try JSONDecoder.supabase.decode(PlaceCandidateRow.self, from: data)
        return row.id
    }

    func recoverSourceOnlyReviewCandidates(captureId: UUID, workflowRunId: UUID? = nil) async throws -> [PlaceReviewCandidate] {
        guard isConfigured else { return [] }

        let body = try Self.jsonBody([
            "workflow_run_id": workflowRunId?.uuidString,
            "include_media_evidence": true,
        ])
        let data = try await request(
            path: "/memory/captures/\(captureId.uuidString)/search-recovery",
            method: "POST",
            body: body
        )
        let row = try JSONDecoder.supabase.decode(SourceSearchRecoveryRow.self, from: data)
        return row.created_candidates.map { $0.toCandidate() }
    }

    func fetchReviewCandidates() async throws -> [PlaceReviewCandidate] {
        guard isConfigured else { return [] }

        let data = try await request(path: "/memory/candidates")
        let rows = try JSONDecoder.supabase.decode([PlaceCandidateRow].self, from: data)
        return rows.map { $0.toCandidate() }
    }

    func updatePlaceCandidateStatus(_ candidateId: UUID, status: String, placeId: UUID? = nil) async throws {
        guard isConfigured else { return }

        var values: [String: Any?] = ["status": status]
        if let placeId {
            values["place_id"] = placeId.uuidString
        }
        let body = try Self.jsonBody(values)
        try await request(path: "/memory/candidates/\(candidateId)", method: "PATCH", body: body)
    }

    // MARK: - Place Recovery Workflow

    func createPlaceRecoveryWorkOrder(sourceURL: String?, sourceType: String? = nil) async throws -> PlaceRecoveryWorkOrder {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody([
            "source_url": sourceURL,
            "source_type": sourceType,
            "credit_reserved": 1,
        ])
        let data = try await request(path: "/v0/workflows/place-recovery/work-orders", method: "POST", body: body)
        return try JSONDecoder.supabase.decode(PlaceRecoveryWorkOrder.self, from: data)
    }

    func createPlaceRecoveryRun(workOrderId: UUID? = nil, sourceURL: String?, sourceType: String? = nil) async throws -> PlaceRecoveryWorkflowRun {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody([
            "work_order_id": workOrderId?.uuidString,
            "source_url": sourceURL,
            "source_type": sourceType,
            "credit_reserved": 1,
        ])
        let data = try await request(path: "/v0/workflows/place-recovery/runs", method: "POST", body: body)
        return try JSONDecoder.supabase.decode(PlaceRecoveryWorkflowRun.self, from: data)
    }

    func recordPlaceRecoveryResult(_ result: PlaceRecoveryResultDraft, for runId: UUID) async throws -> PlaceRecoveryWorkflowRun {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody(result.body)
        let data = try await request(path: "/v0/workflows/place-recovery/runs/\(runId.uuidString)/result", method: "POST", body: body)
        return try Self.decodePlaceRecoveryResultResponse(data)
    }

    static func decodePlaceRecoveryResultResponse(_ data: Data) throws -> PlaceRecoveryWorkflowRun {
        try JSONDecoder.supabase.decode(PlaceRecoveryResultResponse.self, from: data).run
    }

    func recordPlaceRecoveryDecision(_ decision: PlaceRecoveryDecisionDraft, for runId: UUID) async throws -> PlaceRecoveryDecisionReceiptResponse {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try Self.jsonBody(decision.body)
        let data = try await request(path: "/v0/workflows/place-recovery/runs/\(runId.uuidString)/decision", method: "POST", body: body)
        return try JSONDecoder.supabase.decode(PlaceRecoveryDecisionReceiptResponse.self, from: data)
    }

    // MARK: - Trips

    func fetchTrips(for userId: String) async throws -> [Trip] {
        guard isConfigured else { return [] }

        let tripsData = try await request(path: "/trips")

        let rows = try JSONDecoder.supabase.decode([TripRow].self, from: tripsData)
        return rows.map { $0.toTrip() }
    }

    func saveTrip(_ trip: Trip, userId: String) async throws {
        guard isConfigured else { return }

        let row = TripRow.from(trip: trip, userId: userId, includeStops: true)
        let body = try JSONEncoder.supabase.encode(row)
        try await request(path: "/trips", method: "POST", body: body)
    }

    func updateTrip(_ trip: Trip) async throws {
        guard isConfigured else { return }

        let updates: [String: Any?] = [
            "name": trip.name,
            "city": trip.city,
            "is_optimized": trip.isOptimized,
        ]
        let body = try Self.jsonBody(updates)
        try await request(path: "/trips/\(trip.id)", method: "PATCH", body: body)
    }

    func deleteTrip(_ tripId: UUID) async throws {
        guard isConfigured else { return }
        try await request(path: "/trips/\(tripId)", method: "DELETE")
    }

    // MARK: - Profile

    func fetchAccountStatus() async throws -> AccountStatusResponse {
        guard isConfigured else { throw SupabaseError.notConfigured }
        let data = try await request(path: "/v0/account-status")
        return try JSONDecoder.supabase.decode(AccountStatusResponse.self, from: data)
    }

    func confirmAccount(expectedAccountRef: String) async throws -> AccountStatusResponse {
        guard isConfigured else { throw SupabaseError.notConfigured }
        let body = try JSONSerialization.data(withJSONObject: ["account_ref": expectedAccountRef])
        let data = try await request(
            path: "/v0/account-status/confirm",
            method: "POST",
            body: body
        )
        return try JSONDecoder.supabase.decode(AccountStatusResponse.self, from: data)
    }

    func fetchProfile(for userId: String) async throws -> UserProfile? {
        guard isConfigured else { return .mock }

        let data = try await request(path: "/profile")

        let row = try JSONDecoder.supabase.decode(ProfileRow.self, from: data)
        return row.toProfile()
    }

    func updateProfile(_ profile: UserProfile) async throws {
        guard isConfigured else { return }

        let updates: [String: Any?] = [
            "display_name": profile.displayName,
            "avatar_url": profile.avatarUrl,
        ]
        let body = try Self.jsonBody(updates)
        try await request(path: "/profile", method: "PATCH", body: body)
    }

    // MARK: - Social Graph

    func fetchFollowedFriends() async throws -> [SaveFollowedFriend] {
        guard isConfigured else { return [] }

        let data = try await request(path: "/follows")
        return try JSONDecoder.supabase.decode([SaveFollowedFriend].self, from: data)
    }

    func followProfile(referralCode: String, lens: SaveSocialLens, source: SaveFollowSource) async throws {
        try await followProfile(
            target: SaveReferralTarget(referralCode: referralCode, handle: nil, lens: lens),
            source: source
        )
    }

    func followProfile(target: SaveReferralTarget, source: SaveFollowSource) async throws {
        guard isConfigured else { return }
        guard target.isValid else { throw SupabaseError.recordNotFound }

        let body = try Self.jsonBody([
            "referral_code": target.referralCode,
            "handle": target.handle,
            "lens": target.lens.rawValue,
            "source": source.rawValue,
        ])
        try await request(path: "/follows", method: "POST", body: body)
    }

    func fetchReferralProfile(target: SaveReferralTarget) async throws -> SaveReferralProfile {
        guard isConfigured else { throw SupabaseError.notConfigured }
        guard target.isValid else { throw SupabaseError.recordNotFound }

        let path: String
        if let code = target.referralCode?.urlPathEncoded {
            path = "/referrals/\(code)"
        } else if let handle = target.handle?.urlQueryEncoded {
            path = "/referrals?handle=\(handle)"
        } else {
            throw SupabaseError.recordNotFound
        }

        let data = try await request(path: path, requiresAuth: false)
        let row = try JSONDecoder.supabase.decode(ReferralProfileRow.self, from: data)
        return row.toProfile()
    }

    func fetchSocialSignals(lens: SaveSocialLens) async throws -> [Place] {
        guard isConfigured else { return [] }

        let data = try await request(path: "/social/signals?lens=\(lens.rawValue)&limit=60")
        let rows = try JSONDecoder.supabase.decode([PlaceRow].self, from: data)
        return rows.map { $0.toPlace() }
    }

    // MARK: - HTTP

    @discardableResult
    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        requiresAuth: Bool = true
    ) async throws -> Data {
        let (data, _) = try await requestWithResponse(
            path: path,
            method: method,
            body: body,
            requiresAuth: requiresAuth
        )
        return data
    }

    private func requestWithResponse(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        requiresAuth: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        guard let apiBaseURL else { throw SupabaseError.notConfigured }

        guard let url = URL(string: "\(apiBaseURL)\(path)") else {
            throw SupabaseError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresAuth {
            do {
                request.setValue("Bearer \(try await privyAccessToken())", forHTTPHeaderField: "Authorization")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SupabaseError.notAuthenticated
            }
        }

        if let body { request.httpBody = body }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw SupabaseError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse("SAV-E returned a non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Self.httpError(statusCode: http.statusCode, body: body)
        }

        return (data, http)
    }

    @MainActor
    private func privyAccessToken() async throws -> String {
        try await PrivyAuthService.shared.accessToken()
    }

    private static func jsonBody(_ values: [String: Any?]) throws -> Data {
        let object = values.mapValues { $0 ?? NSNull() }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

// MARK: - Row DTOs (snake_case ↔ Swift models)

struct VerifiedPlaceClaim: Codable, Identifiable, Equatable {
    let claimId: UUID
    let placeId: UUID
    let claimType: String
    let claim: String
    let agentUsableSummary: String
    let author: VerifiedPlaceClaimAuthor
    let proofLevel: String
    let confidence: Double
    let visibility: String
    let evidenceSummary: [String]
    let evidenceRefs: [String]?
    let observedAt: String?
    let expiresOrStaleAfter: String?
    let createdAt: String?

    var id: UUID { claimId }

    enum CodingKeys: String, CodingKey {
        case claimId = "claim_id"
        case placeId = "place_id"
        case claimType = "claim_type"
        case claim
        case agentUsableSummary = "agent_usable_summary"
        case author
        case proofLevel = "proof_level"
        case confidence
        case visibility
        case evidenceSummary = "evidence_summary"
        case evidenceRefs = "evidence_refs"
        case observedAt = "observed_at"
        case expiresOrStaleAfter = "expires_or_stale_after"
        case createdAt = "created_at"
    }
}

struct VerifiedPlaceClaimAuthor: Codable, Equatable {
    let authorType: String
    let publicHandle: String?
    let relationship: String

    enum CodingKeys: String, CodingKey {
        case authorType = "author_type"
        case publicHandle = "public_handle"
        case relationship
    }
}

struct VerifiedPlaceClaimDraft: Equatable {
    var claimType: String
    var claim: String
    var agentUsableSummary: String?
    var proofLevel: String
    var evidenceRefs: [String]
    var visibility: String
    var confidence: Double
    var context: [String: Any]
    var ratings: [String: Any]
    var observedAt: String?
    var expiresOrStaleAfter: String?

    var body: [String: Any?] {
        [
            "claim_type": claimType,
            "claim": claim,
            "agent_usable_summary": agentUsableSummary,
            "proof_level": proofLevel,
            "evidence_refs": evidenceRefs,
            "visibility": visibility,
            "confidence": confidence,
            "context": context,
            "ratings": ratings,
            "observed_at": observedAt,
            "expires_or_stale_after": expiresOrStaleAfter,
        ]
    }

    static func == (lhs: VerifiedPlaceClaimDraft, rhs: VerifiedPlaceClaimDraft) -> Bool {
        lhs.claimType == rhs.claimType &&
            lhs.claim == rhs.claim &&
            lhs.agentUsableSummary == rhs.agentUsableSummary &&
            lhs.proofLevel == rhs.proofLevel &&
            lhs.evidenceRefs == rhs.evidenceRefs &&
            lhs.visibility == rhs.visibility &&
            lhs.confidence == rhs.confidence &&
            lhs.observedAt == rhs.observedAt &&
            lhs.expiresOrStaleAfter == rhs.expiresOrStaleAfter
    }
}

private struct VerifiedPlaceClaimsResponse: Codable {
    let place_id: UUID
    let claims: [VerifiedPlaceClaim]
}

struct PlaceTrustSummaryResponse: Codable, Equatable {
    let placeId: UUID
    let trustSummary: PlaceTrustSummary
    let agentAnswer: String

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case trustSummary = "trust_summary"
        case agentAnswer = "agent_answer"
    }
}

struct PlaceTrustSummary: Codable, Equatable {
    let verifiedClaimCount: Int
    let receiptBackedCount: Int
    let friendVerifiedCount: Int
    let lastObservedAt: String?
    let strongestProofLevel: String
    let confidence: Double
    let reputation: ClaimReputationSummary?
    let recommendedUse: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case verifiedClaimCount = "verified_claim_count"
        case receiptBackedCount = "receipt_backed_count"
        case friendVerifiedCount = "friend_verified_count"
        case lastObservedAt = "last_observed_at"
        case strongestProofLevel = "strongest_proof_level"
        case confidence
        case reputation
        case recommendedUse = "recommended_use"
        case warnings
    }
}

struct ClaimReputationSummary: Codable, Equatable {
    let usageCount: Int
    let acceptedCount: Int
    let score: Double

    enum CodingKeys: String, CodingKey {
        case usageCount = "usage_count"
        case acceptedCount = "accepted_count"
        case score
    }
}

struct MaatPlaceAnalysisResponse: Codable, Equatable {
    let placeId: UUID
    let capability: String
    let status: String
    let title: String
    let summary: String
    let verdict: String
    let confidence: Double
    let strongestProofLevel: String
    let citedClaimIds: [UUID]
    let citedEvidence: [String]
    let warnings: [String]
    let nextActions: [String]
    let restaurantDetails: MaatRestaurantDetails?
    let analysisReceipt: MaatPlaceAnalysisReceipt

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case capability
        case status
        case title
        case summary
        case verdict
        case confidence
        case strongestProofLevel = "strongest_proof_level"
        case citedClaimIds = "cited_claim_ids"
        case citedEvidence = "cited_evidence"
        case warnings
        case nextActions = "next_actions"
        case restaurantDetails = "restaurant_details"
        case analysisReceipt = "analysis_receipt"
    }
}

struct MaatRestaurantDetails: Codable, Equatable {
    let platformScores: [MaatPlatformScore]
    let mustTry: [MaatDishRecommendation]
    let warnings: [String]
    let criticalReviews: [MaatCriticalReview]
    let priceRange: String?
    let avgCost: String?
    let bestFor: [String]
    let cuisine: String?
    let ambiance: String?
    let serviceRating: String?
    let reservationTips: String?
    let parking: String?
    let evidenceGaps: [String]

    enum CodingKeys: String, CodingKey {
        case platformScores = "platform_scores"
        case mustTry = "must_try"
        case warnings
        case criticalReviews = "critical_reviews"
        case priceRange = "price_range"
        case avgCost = "avg_cost"
        case bestFor = "best_for"
        case cuisine
        case ambiance
        case serviceRating = "service_rating"
        case reservationTips = "reservation_tips"
        case parking
        case evidenceGaps = "evidence_gaps"
    }
}

struct MaatPlatformScore: Codable, Equatable {
    let platform: String
    let score: Double
    let source: String?
}

struct MaatDishRecommendation: Codable, Equatable {
    let name: String
    let description: String?
    let price: String?
    let evidence: String?
}

struct MaatCriticalReview: Codable, Equatable {
    let issue: String
    let source: String?
    let frequency: String?
}

struct MaatPlaceAnalysisReceipt: Codable, Equatable {
    let inputScope: String
    let placeId: UUID
    let claimCount: Int
    let citedClaimCount: Int
    let includesPrivateClaimSummaries: Bool
    let rawPrivateEvidenceIncluded: Bool
    let wholeMapUsed: Bool
    let publicWebUsed: Bool
    let modelUsed: Bool

    enum CodingKeys: String, CodingKey {
        case inputScope = "input_scope"
        case placeId = "place_id"
        case claimCount = "claim_count"
        case citedClaimCount = "cited_claim_count"
        case includesPrivateClaimSummaries = "includes_private_claim_summaries"
        case rawPrivateEvidenceIncluded = "raw_private_evidence_included"
        case wholeMapUsed = "whole_map_used"
        case publicWebUsed = "public_web_used"
        case modelUsed = "model_used"
    }
}

struct ClaimRecommendationRequest: Equatable {
    var intent: String
    var constraints: [String]
    var proofLevelMin: String
    var limit: Int

    var body: [String: Any?] {
        [
            "intent": intent,
            "constraints": constraints,
            "proof_level_min": proofLevelMin,
            "limit": limit,
        ]
    }
}

struct ClaimRecommendationResponse: Codable, Equatable {
    let results: [ClaimRecommendationResult]
    let retrievalReceipt: ClaimRetrievalReceipt
    let agentShackReceiptEnvelope: AgentShackReceiptEnvelope?

    static let empty = ClaimRecommendationResponse(
        results: [],
        retrievalReceipt: ClaimRetrievalReceipt(used: [], skipped: [], publicWebUsed: false),
        agentShackReceiptEnvelope: nil
    )

    enum CodingKeys: String, CodingKey {
        case results
        case retrievalReceipt = "retrieval_receipt"
        case agentShackReceiptEnvelope = "agent_shack_receipt_envelope"
    }
}

struct ClaimRecommendationResult: Codable, Identifiable, Equatable {
    let placeId: UUID
    let name: String
    let why: String
    let proofLevel: String
    let confidence: Double
    let supportingClaims: [UUID]
    let warnings: [String]
    let nextActions: [String]

    var id: UUID { placeId }

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case why
        case proofLevel = "proof_level"
        case confidence
        case supportingClaims = "supporting_claims"
        case warnings
        case nextActions = "next_actions"
    }
}

struct ClaimRetrievalReceipt: Codable, Equatable {
    let used: [String]
    let skipped: [String]
    let publicWebUsed: Bool

    enum CodingKeys: String, CodingKey {
        case used
        case skipped
        case publicWebUsed = "public_web_used"
    }
}

struct AgentShackReceiptEnvelope: Codable, Equatable {
    let product: String
    let receiptType: String
    let userId: String
    let agentId: String
    let capability: String
    let inputHash: String
    let outputHash: String
    let privatePayloadRef: String
    let publicSummary: RecommendationAnalysisPublicSummary
    let preferenceSignals: [String]
    let evaluatorVerdict: String
    let settlementState: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case product
        case receiptType = "receipt_type"
        case userId = "user_id"
        case agentId = "agent_id"
        case capability
        case inputHash = "input_hash"
        case outputHash = "output_hash"
        case privatePayloadRef = "private_payload_ref"
        case publicSummary = "public_summary"
        case preferenceSignals = "preference_signals"
        case evaluatorVerdict = "evaluator_verdict"
        case settlementState = "settlement_state"
        case createdAt = "created_at"
    }
}

struct RecommendationAnalysisPublicSummary: Codable, Equatable {
    let summary: String
    let capability: String
    let resultCount: Int
    let savedResultCount: Int
    let publicResultCount: Int
    let proofLevelMin: String?
    let publicWebUsed: Bool

    enum CodingKeys: String, CodingKey {
        case summary
        case capability
        case resultCount = "result_count"
        case savedResultCount = "saved_result_count"
        case publicResultCount = "public_result_count"
        case proofLevelMin = "proof_level_min"
        case publicWebUsed = "public_web_used"
    }
}

struct SaveMemoryPreference: Codable, Identifiable, Equatable, Sendable {
    enum Polarity: String, Codable, CaseIterable, Sendable { case like, dislike, constraint }
    enum Source: String, Codable, Sendable { case explicit, inferred }
    enum Status: String, Codable, Sendable { case proposed, active, corrected, removed }

    let id: UUID
    let preferenceType: String
    let normalizedValue: String
    let context: String
    let polarity: Polarity
    let source: Source
    let evidenceRefs: [String]
    let evidenceCount: Int
    let confidence: Double
    let status: Status
    let correctedFromId: UUID?
    let createdAt: Date
    let updatedAt: Date

    var isActiveForRanking: Bool { status == .active }

    enum CodingKeys: String, CodingKey {
        case id
        case preferenceType = "preference_type"
        case normalizedValue = "normalized_value"
        case context, polarity, source
        case evidenceRefs = "evidence_refs"
        case evidenceCount = "evidence_count"
        case confidence, status
        case correctedFromId = "corrected_from_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SaveMemoryPreferenceDraft: Codable, Equatable, Sendable {
    var preferenceType: String
    var normalizedValue: String
    var context: String = "general"
    var polarity: SaveMemoryPreference.Polarity
    var source: SaveMemoryPreference.Source = .explicit
    var evidenceRefs: [String] = []
    var evidenceCount: Int = 0
    var confidence: Double = 1
    var status: SaveMemoryPreference.Status = .active

    enum CodingKeys: String, CodingKey {
        case preferenceType = "preference_type"
        case normalizedValue = "normalized_value"
        case context, polarity, source
        case evidenceRefs = "evidence_refs"
        case evidenceCount = "evidence_count"
        case confidence, status
    }
}

extension Notification.Name {
    static let saveMemoryPreferencesDidChange = Notification.Name("saveMemoryPreferencesDidChange")
}

struct SaveRecommendationAnalysisReceipt: Codable, Identifiable, Equatable {
    let id: UUID
    let envelope: AgentShackReceiptEnvelope
    let fullPayloadJSON: String

    var agentShackProjection: AgentShackReceiptEnvelope { envelope }

    enum CodingKeys: String, CodingKey {
        case id
        case envelope
        case fullPayloadJSON = "full_payload_json"
    }
}

struct PublicPlaceCard: Codable, Identifiable, Equatable {
    let cardId: UUID
    let title: String
    let place: PublicPlaceCardPlace
    let summary: String
    let publicClaims: [VerifiedPlaceClaim]
    let trustSummary: PlaceTrustSummary
    let agentActions: [String]

    var id: UUID { cardId }

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case title
        case place
        case summary
        case publicClaims = "public_claims"
        case trustSummary = "trust_summary"
        case agentActions = "agent_actions"
    }
}

struct PublicPlaceCardPlace: Codable, Equatable {
    let id: UUID
    let name: String
    let city: String
    let address: String
    let category: String?
}

struct ClaimUsageReceiptDraft: Equatable {
    var claimId: UUID
    var consumerAgentId: String
    var action: String
    var outcome: String

    var body: [String: Any?] {
        [
            "claim_id": claimId.uuidString,
            "consumer_agent_id": consumerAgentId,
            "action": action,
            "outcome": outcome,
        ]
    }
}

struct ClaimUsageReceipt: Codable, Identifiable, Equatable {
    let id: UUID
    let claimId: UUID
    let placeId: UUID
    let consumerAgentId: String
    let consumerUserId: String?
    let action: String
    let outcome: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case claimId = "claim_id"
        case placeId = "place_id"
        case consumerAgentId = "consumer_agent_id"
        case consumerUserId = "consumer_user_id"
        case action
        case outcome
        case createdAt = "created_at"
    }
}

struct PlaceRecoveryWorkOrder: Codable, Identifiable, Equatable {
    let id: UUID
    let workflowId: String
    let listingId: String
    let intent: String
    let inputType: String
    let inputRef: String?
    let sourceURL: String?
    let evaluatorPolicyId: String
    let settlementMode: String
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workflowId = "workflow_id"
        case listingId = "listing_id"
        case intent
        case inputType = "input_type"
        case inputRef = "input_ref"
        case sourceURL = "source_url"
        case evaluatorPolicyId = "evaluator_policy_id"
        case settlementMode = "settlement_mode"
        case status
        case createdAt = "created_at"
    }
}

struct PlaceRecoveryWorkflowRun: Codable, Identifiable, Equatable {
    let id: UUID
    let workOrderId: UUID?
    let workflowId: String
    let listingId: String
    let sourceURL: String?
    let sourceType: String
    let status: String
    let resultType: String?
    let confidence: Double?
    let evidenceTier: String
    let resultEvidenceRefs: [String]
    let resultCandidateRefs: [String]
    let creditReserved: Int
    let creditSettlement: String
    let receiptId: UUID?
    let createdAt: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workOrderId = "work_order_id"
        case workflowId = "workflow_id"
        case listingId = "listing_id"
        case sourceURL = "source_url"
        case sourceType = "source_type"
        case status
        case resultType = "result_type"
        case confidence
        case evidenceTier = "evidence_tier"
        case resultEvidenceRefs = "result_evidence_refs"
        case resultCandidateRefs = "result_candidate_refs"
        case creditReserved = "credit_reserved"
        case creditSettlement = "credit_settlement"
        case receiptId = "receipt_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

struct PlaceRecoveryResultDraft: Equatable {
    var resultType: String
    var evidenceTier: String
    var confidence: Double
    var evidenceRefs: [String]
    var candidateRefs: [String]
    var technicalFailure: Bool
    var failureCode: String? = nil
    var failedStep: String? = nil
    var retryable: Bool? = nil

    var body: [String: Any?] {
        [
            "result_type": resultType,
            "evidence_tier": evidenceTier,
            "confidence": confidence,
            "evidence_refs": evidenceRefs,
            "candidate_refs": candidateRefs,
            "technical_failure": technicalFailure,
            "failure_code": failureCode,
            "failed_step": failedStep,
            "retryable": retryable,
        ]
    }
}

struct PlaceRecoveryDecisionDraft: Equatable {
    var action: String
    var candidateId: UUID? = nil
    var finalPlaceId: UUID? = nil
    var finalPlace: Place? = nil
    var reasonCode: String? = nil
    var editedPayload: [String: Any]
    var reason: String?

    var body: [String: Any?] {
        [
            "action": action,
            "candidate_id": candidateId?.uuidString,
            "final_place_id": finalPlaceId?.uuidString,
            "final_place": finalPlacePayload,
            "reason_code": reasonCode,
            "edited_payload": editedPayload,
            "reason": reason,
        ]
    }

    static func == (lhs: PlaceRecoveryDecisionDraft, rhs: PlaceRecoveryDecisionDraft) -> Bool {
        lhs.action == rhs.action
            && lhs.candidateId == rhs.candidateId
            && lhs.finalPlaceId == rhs.finalPlaceId
            && lhs.finalPlace == rhs.finalPlace
            && lhs.reasonCode == rhs.reasonCode
            && lhs.reason == rhs.reason
    }

    private var finalPlacePayload: [String: Any]? {
        guard let finalPlace else { return nil }
        var payload: [String: Any] = [
            "id": finalPlace.id.uuidString,
            "name": finalPlace.name,
            "address": finalPlace.address,
            "latitude": finalPlace.latitude,
            "longitude": finalPlace.longitude,
            "category": finalPlace.category.rawValue,
            "status": finalPlace.status.rawValue,
            "source_platform": finalPlace.sourcePlatform.rawValue,
            "created_at": ISO8601DateFormatter().string(from: finalPlace.createdAt),
        ]
        if let value = finalPlace.googlePlaceId { payload["google_place_id"] = value }
        if let value = finalPlace.rating { payload["rating"] = value }
        if let value = finalPlace.note { payload["note"] = value }
        if let value = finalPlace.sourceUrl { payload["source_url"] = value }
        if let value = finalPlace.sourceImageUrl { payload["source_image_url"] = value }
        if let value = finalPlace.businessPhotoUrls { payload["business_photo_urls"] = value }
        if let value = finalPlace.extractedDishes { payload["extracted_dishes"] = value }
        if let value = finalPlace.priceRange { payload["price_range"] = value }
        if let value = finalPlace.recommender { payload["recommender"] = value }
        if let value = finalPlace.googleRating { payload["google_rating"] = value }
        if let value = finalPlace.googlePriceLevel { payload["google_price_level"] = value }
        if let value = finalPlace.openingHours { payload["opening_hours"] = value }
        return payload
    }
}

struct PlaceRecoveryDecisionReceiptResponse: Codable, Equatable {
    let run: PlaceRecoveryWorkflowRun
    let receipt: WorkflowReceipt
}

struct PlaceRecoveryResultResponse: Codable, Equatable {
    let run: PlaceRecoveryWorkflowRun
    let receipt: WorkflowReceipt
}

struct WorkflowReceipt: Codable, Identifiable, Equatable {
    let id: UUID
    let runId: UUID
    let workflowId: String
    let verdict: String
    let settlement: String
    let evaluatorSummary: String
    let evidenceRefs: [String]
    let candidateRefs: [String]
    let receiptHash: String
    let anchorStatus: String
    let privateURL: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case runId = "run_id"
        case workflowId = "workflow_id"
        case verdict
        case settlement
        case evaluatorSummary = "evaluator_summary"
        case evidenceRefs = "evidence_refs"
        case candidateRefs = "candidate_refs"
        case receiptHash = "receipt_hash"
        case anchorStatus = "anchor_status"
        case privateURL = "private_url"
        case createdAt = "created_at"
    }
}

struct FriendSharedPlaceSaveResult {
    enum Outcome: String {
        case saved
        case alreadySaved = "already_saved"
    }

    let place: Place
    let outcome: Outcome

    var isDuplicate: Bool { outcome == .alreadySaved }
}

private struct FriendSharedPlaceSaveResponse: Decodable {
    let place: PlaceRow
    let outcome: String
}

private struct PlaceRow: Codable {
    let id: UUID
    let user_id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let google_place_id: String?
    let category: String
    let status: String
    let rating: Double?
    let note: String?
    let source_url: String?
    let source_platform: String
    let source_image_url: String?
    let business_photo_urls: [String]?
    let extracted_dishes: [String]?
    let price_range: String?
    let recommender: String?
    let google_rating: Double?
    let google_price_level: Int?
    let opening_hours: String?
    let created_at: String
    let visibility: String?
    let social_signal: PlaceSocialSignalRow?
    let friend_share_code: String?

    func toPlace() -> Place {
        Place(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: google_place_id,
            category: PlaceCategory(rawValue: category) ?? .food,
            status: PlaceStatus(rawValue: status) ?? .wantToGo,
            rating: rating,
            note: note,
            sourceUrl: source_url,
            sourcePlatform: SourcePlatform(rawValue: source_platform) ?? .other,
            sourceImageUrl: source_image_url,
            businessPhotoUrls: business_photo_urls,
            extractedDishes: extracted_dishes,
            priceRange: price_range,
            recommender: recommender,
            googleRating: google_rating,
            googlePriceLevel: google_price_level,
            openingHours: opening_hours,
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date(),
            visibility: visibility.flatMap(PlaceVisibility.init(rawValue:)),
            socialSignal: social_signal?.toSignal()
        )
    }

    static func from(place: Place, userId: String, friendShareCode: String? = nil) -> PlaceRow {
        PlaceRow(
            id: place.id,
            user_id: userId,
            name: place.name,
            address: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            google_place_id: place.googlePlaceId,
            category: place.category.rawValue,
            status: place.status.rawValue,
            rating: place.rating,
            note: place.note,
            source_url: place.sourceUrl,
            source_platform: place.sourcePlatform.rawValue,
            source_image_url: place.sourceImageUrl,
            business_photo_urls: place.businessPhotoUrls,
            extracted_dishes: place.extractedDishes,
            price_range: place.priceRange,
            recommender: place.recommender,
            google_rating: place.googleRating,
            google_price_level: place.googlePriceLevel,
            opening_hours: place.openingHours,
            created_at: ISO8601DateFormatter().string(from: place.createdAt),
            visibility: place.visibility?.rawValue,
            social_signal: nil,
            friend_share_code: friendShareCode
        )
    }
}

private struct PlaceSocialSignalRow: Codable {
    let kind: String
    let lens: String
    let friendNames: [String]?
    let friendCount: Int?
    let saveCount: Int?
    let trendingRank: Int?
    let categoryRank: Int?
    let sourceLabel: String?
    let referrerId: String?
    let referralCode: String?

    func toSignal() -> PlaceSocialSignal {
        PlaceSocialSignal(
            kind: PlaceSocialSignalKind(rawValue: kind) ?? .friendSaved,
            lens: SaveSocialLens(rawValue: lens) ?? .friends,
            friendNames: friendNames ?? [],
            friendCount: friendCount ?? 0,
            saveCount: saveCount ?? 0,
            trendingRank: trendingRank,
            categoryRank: categoryRank,
            sourceLabel: sourceLabel ?? "SAV-E",
            referrerId: referrerId,
            referralCode: referralCode
        )
    }
}

private struct ReferralProfileRow: Codable {
    let referrerId: String
    let handle: String
    let displayName: String
    let referralCode: String
    let lens: String
    let featuredPlaces: [PlaceRow]

    func toProfile() -> SaveReferralProfile {
        SaveReferralProfile(
            referrerId: referrerId,
            handle: handle,
            displayName: displayName,
            referralCode: referralCode,
            lens: SaveSocialLens(rawValue: lens) ?? .friends,
            featuredPlaces: featuredPlaces.map { $0.toPlace() }
        )
    }
}

private struct MemoryCaptureRow: Codable {
    let id: UUID
}

private struct SourceSearchRecoveryRow: Codable {
    let created_candidates: [PlaceCandidateRow]
}

private struct PlaceCandidateRow: Codable {
    let id: UUID
    let capture_id: UUID?
    let workflow_run_id: UUID?
    let name: String
    let address: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let evidence: [PlaceCandidateEvidenceRow]?
    let confidence: Double?
    let missing_info: [String]?
    let status: String
    let created_at: String

    func toCandidate() -> PlaceReviewCandidate {
        PlaceReviewCandidate(
            id: id,
            captureId: capture_id,
            workflowRunId: workflow_run_id,
            name: name,
            address: address ?? "",
            city: city,
            latitude: latitude,
            longitude: longitude,
            evidence: (evidence ?? []).compactMap(\.text),
            confidence: confidence,
            missingInfo: missing_info ?? [],
            status: status,
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }
}

private struct PlaceCandidateEvidenceRow: Codable {
    let text: String?
}

private struct TripRow: Codable {
    let id: UUID
    let user_id: String
    let name: String
    let city: String
    let start_date: String?
    let end_date: String?
    let is_optimized: Bool
    let created_at: String
    let trip_stops: [TripStopRow]?

    func toTrip() -> Trip {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return Trip(
            id: id,
            name: name,
            city: city,
            startDate: start_date.flatMap { df.date(from: $0) },
            endDate: end_date.flatMap { df.date(from: $0) },
            places: (trip_stops ?? []).map { $0.toStop() },
            isOptimized: is_optimized,
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }

    static func from(trip: Trip, userId: String, includeStops: Bool = false) -> TripRow {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return TripRow(
            id: trip.id,
            user_id: userId,
            name: trip.name,
            city: trip.city,
            start_date: trip.startDate.map { df.string(from: $0) },
            end_date: trip.endDate.map { df.string(from: $0) },
            is_optimized: trip.isOptimized,
            created_at: ISO8601DateFormatter().string(from: trip.createdAt),
            trip_stops: includeStops ? trip.places.map { TripStopRow.from(stop: $0, tripId: trip.id) } : nil
        )
    }
}

private struct TripStopRow: Codable {
    let id: UUID
    let trip_id: UUID
    let place_id: UUID?
    let place_name: String
    let day: Int
    let order_index: Int
    let start_time: String?
    let duration: Int?
    let note: String?

    func toStop() -> TripStop {
        TripStop(
            id: id,
            placeId: place_id ?? UUID(),
            placeName: place_name,
            day: day,
            orderIndex: order_index,
            startTime: start_time,
            duration: duration,
            note: note
        )
    }

    static func from(stop: TripStop, tripId: UUID) -> TripStopRow {
        TripStopRow(
            id: stop.id,
            trip_id: tripId,
            place_id: stop.placeId,
            place_name: stop.placeName,
            day: stop.day,
            order_index: stop.orderIndex,
            start_time: stop.startTime,
            duration: stop.duration,
            note: stop.note
        )
    }
}

private struct ProfileRow: Codable {
    let id: String
    let display_name: String
    let email: String?
    let avatar_url: String?
    let is_premium: Bool
    let created_at: String
    let saved_count: Int?
    let visited_count: Int?
    let cities_count: Int?

    func toProfile() -> UserProfile {
        UserProfile(
            id: id,
            displayName: display_name,
            email: email,
            avatarUrl: avatar_url,
            savedCount: saved_count ?? 0,
            visitedCount: visited_count ?? 0,
            citiesCount: cities_count ?? 0,
            isPremium: is_premium,
            collections: [],
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }
}

private struct SharedPlaceLinkCreateBody: Encodable {
    let payload: SharedPlaceData
    let source_place_id: String?
    let note_consent_version: Int?
}

private final class KmlRootElementParserDelegate: NSObject, XMLParserDelegate {
    private(set) var rootElementName: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if rootElementName == nil {
            rootElementName = elementName.lowercased()
        }
    }
}

private struct SharedPlaceLinkRow: Codable {
    let code: String
    let url: String
    let payload: SharedPlaceData
}

// MARK: - JSON Coding

extension JSONDecoder {
    static let supabase: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
}

extension JSONEncoder {
    static let supabase: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
}

private extension String {
    var urlPathEncoded: String? {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    var urlQueryEncoded: String? {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }
}
