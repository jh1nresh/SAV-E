import Foundation

// MARK: - Protocol

protocol SupabaseServiceProtocol {
    func fetchPlaces(for userId: String) async throws -> [Place]
    func savePlace(_ place: Place, userId: String) async throws
    func updatePlace(_ place: Place) async throws
    func deletePlace(_ placeId: UUID) async throws
    func createMemoryCapture(from candidate: PendingReviewCandidate, userId: String) async throws -> UUID
    func createPlaceCandidate(_ candidate: PendingReviewCandidate, captureId: UUID, userId: String) async throws
    func recoverSourceOnlyReviewCandidates(captureId: UUID) async throws -> [PlaceReviewCandidate]
    func fetchReviewCandidates() async throws -> [PlaceReviewCandidate]
    func updatePlaceCandidateStatus(_ candidateId: UUID, status: String, placeId: UUID?) async throws
    func fetchTrips(for userId: String) async throws -> [Trip]
    func saveTrip(_ trip: Trip, userId: String) async throws
    func updateTrip(_ trip: Trip) async throws
    func deleteTrip(_ tripId: UUID) async throws
    func fetchProfile(for userId: String) async throws -> UserProfile?
    func updateProfile(_ profile: UserProfile) async throws
    func followProfile(referralCode: String, lens: SaveSocialLens, source: SaveFollowSource) async throws
    func followProfile(target: SaveReferralTarget, source: SaveFollowSource) async throws
    func fetchReferralProfile(target: SaveReferralTarget) async throws -> SaveReferralProfile
    func fetchSocialSignals(lens: SaveSocialLens) async throws -> [Place]
    func updatePlaceVisibility(_ visibility: PlaceVisibility, for placeId: UUID) async throws
    func createSharedPlaceLink(payload: SharedPlaceData, sourcePlaceId: UUID?) async throws -> URL
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case recordNotFound
    case networkError(Error)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "SAV-E API not configured"
        case .notAuthenticated: return "User not authenticated"
        case .recordNotFound: return "Record not found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let msg): return "SAV-E API error \(code): \(msg)"
        }
    }
}

// MARK: - Implementation

final class SupabaseService: SupabaseServiceProtocol {
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

    func createSharedPlaceLink(payload: SharedPlaceData, sourcePlaceId: UUID?) async throws -> URL {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let body = try JSONEncoder.supabase.encode(SharedPlaceLinkCreateBody(
            payload: payload,
            source_place_id: sourcePlaceId?.uuidString
        ))
        let data = try await request(path: "/v0/shared-place-links", method: "POST", body: body)
        let row = try JSONDecoder.supabase.decode(SharedPlaceLinkRow.self, from: data)
        guard let url = URL(string: row.url) else { throw SupabaseError.recordNotFound }
        return url
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

    func createPlaceCandidate(_ candidate: PendingReviewCandidate, captureId: UUID, userId: String) async throws {
        guard isConfigured else { throw SupabaseError.notConfigured }

        let evidence = candidate.evidence.map { ["text": $0] }
        let body = try Self.jsonBody([
            "capture_id": captureId.uuidString,
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
        try await request(path: "/memory/candidates", method: "POST", body: body)
    }

    func recoverSourceOnlyReviewCandidates(captureId: UUID) async throws -> [PlaceReviewCandidate] {
        guard isConfigured else { return [] }

        let body = try Self.jsonBody([:])
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
        guard let apiBaseURL else { throw SupabaseError.notConfigured }

        guard let url = URL(string: "\(apiBaseURL)\(path)") else {
            throw SupabaseError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresAuth {
            request.setValue("Bearer \(try await privyAccessToken())", forHTTPHeaderField: "Authorization")
        }

        if let body { request.httpBody = body }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.apiError(http.statusCode, body)
        }

        return data
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

    static func from(place: Place, userId: String) -> PlaceRow {
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
            social_signal: nil
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
