import Foundation
import CoreLocation
import CryptoKit

/// Lightweight place payload encoded in the App Clip URL.
/// Duplicated across targets — keep in sync with SAVEClip's copy.
struct SharedPlaceData: Codable {
    let id: String
    let name: String
    let address: String
    let lat: Double
    let lng: Double
    let category: String
    let rating: Double?
    let reviewCount: Int?
    let priceRange: String?
    let hours: String?
    let sourceLabel: String
    let sourceURL: String?
    let photoURLs: [String]
    let note: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var hasValidCoordinate: Bool {
        lat.isFinite && lng.isFinite && (-90...90).contains(lat) && (-180...180).contains(lng)
    }

    var safeSourceURL: URL? {
        ShareRoutePayloadSanitizer.publicURL(from: sourceURL)
    }

    var embeddedReceiptID: String {
        let payload = sanitizedForReceipt()
        guard let data = try? JSONEncoder().encode(payload) else {
            return "embedded:invalid"
        }
        let digest = SHA256.hash(data: data)
        return "embedded:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func from(url: URL) -> SharedPlaceData? {
        guard let payload = ShareRouteCodec.decode(
            SharedPlaceData.self,
            from: url,
            route: "p",
            maxTokenCharacters: ShareRoutePayloadLimits.embeddedTokenMaxCharacters
        ),
              payload.hasValidCoordinate else { return nil }
        return payload.sanitizedForReceipt()
    }

    static func shortCode(from url: URL) -> String? {
        ShareRouteCodec.shortCode(from: url, route: "p")
    }

    static func resolveShortCode(from url: URL, apiBaseURL: String? = nil) async -> SharedPlaceData? {
        try? await SharedPlaceReceipt.resolve(from: url, apiBaseURL: apiBaseURL).payload
    }

    func toURL(baseURL: String? = nil) -> URL? {
        let sanitized = sanitizedForReceipt()
        guard ShareRoutePayloadLimits.allowsPlacePayload(sanitized) else { return nil }
        return ShareRouteCodec.url(for: sanitized, baseURL: baseURL ?? SaveShareLinkConfig.placeBaseURL)
    }

    static func from(place: Place) -> SharedPlaceData {
        SharedPlaceData(
            id: "",
            name: place.name,
            address: place.address,
            lat: place.latitude,
            lng: place.longitude,
            category: place.category.displayName,
            rating: place.googleRating ?? place.rating,
            reviewCount: place.externalReviewCount,
            priceRange: place.priceRange,
            hours: place.openingHours,
            sourceLabel: place.sourcePlatform == .other ? "SAV-E" : place.sourcePlatform.displayName,
            sourceURL: place.publicShareSourceURL?.absoluteString,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(place.businessPhotoURLStrings),
            note: nil
        )
    }

    func withShareNote(_ note: String?) -> SharedPlaceData {
        SharedPlaceData(
            id: id,
            name: name,
            address: address,
            lat: lat,
            lng: lng,
            category: category,
            rating: rating,
            reviewCount: reviewCount,
            priceRange: priceRange,
            hours: hours,
            sourceLabel: sourceLabel,
            sourceURL: sourceURL,
            photoURLs: photoURLs,
            note: ShareRoutePayloadSanitizer.publicNote(note)
        )
    }

    func sanitizedForReceipt() -> SharedPlaceData {
        SharedPlaceData(
            id: id,
            name: name,
            address: address,
            lat: lat,
            lng: lng,
            category: category,
            rating: rating,
            reviewCount: reviewCount,
            priceRange: priceRange,
            hours: hours,
            sourceLabel: sourceLabel,
            sourceURL: safeSourceURL?.absoluteString,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(photoURLs),
            note: ShareRoutePayloadSanitizer.publicNote(note)
        )
    }

    static func from(candidate: SaveMapCandidate) -> SharedPlaceData {
        SharedPlaceData(
            id: "",
            name: candidate.title,
            address: candidate.subtitle,
            lat: candidate.latitude,
            lng: candidate.longitude,
            category: candidate.category?.displayName ?? "Place",
            rating: candidate.rating,
            reviewCount: candidate.reviewCount,
            priceRange: nil,
            hours: nil,
            sourceLabel: candidate.sourcePlatform?.displayName ?? "Map result",
            sourceURL: ShareRoutePayloadSanitizer.publicURL(from: candidate.sourceURL)?.absoluteString,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(candidate.businessPhotoURLStrings),
            note: ShareRoutePayloadSanitizer.publicNote(candidate.shareNote)
        )
    }

    static func from(result: SaveSearchResult) -> SharedPlaceData? {
        guard let latitude = result.latitude,
              let longitude = result.longitude,
              latitude != 0 || longitude != 0 else { return nil }

        return SharedPlaceData(
            id: "",
            name: result.title,
            address: result.subtitle,
            lat: latitude,
            lng: longitude,
            category: result.category?.displayName ?? result.objectType.displayName,
            rating: result.rating,
            reviewCount: result.reviewCount,
            priceRange: nil,
            hours: nil,
            sourceLabel: result.sourcePlatform?.displayName ?? result.userState.displayName,
            sourceURL: ShareRoutePayloadSanitizer.publicURL(from: result.sourceURL)?.absoluteString,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(result.businessPhotoURLStrings),
            note: ShareRoutePayloadSanitizer.publicNote(result.shareNote)
        )
    }

    static func from(candidate: PlaceReviewCandidate) -> SharedPlaceData? {
        guard let latitude = candidate.latitude,
              let longitude = candidate.longitude,
              latitude != 0 || longitude != 0 else { return nil }

        return SharedPlaceData(
            id: "",
            name: candidate.name,
            address: candidate.address,
            lat: latitude,
            lng: longitude,
            category: "Review Candidate",
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "SAV-E Review",
            sourceURL: candidate.evidence
                .compactMap(Self.firstURLString(in:))
                .compactMap { ShareRoutePayloadSanitizer.publicURL(from: $0)?.absoluteString }
                .first,
            photoURLs: [],
            note: nil
        )
    }

    private static func firstURLString(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).first?.url?.absoluteString
    }
}

struct SharedPlaceSender: Codable, Hashable {
    let displayName: String?
    let handle: String?

    var publicLabel: String? {
        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        guard let handle = handle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !handle.isEmpty else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handle
    }
}

struct SharedPlaceReceipt: Identifiable {
    let code: String?
    let payload: SharedPlaceData
    let sourcePlaceID: String?
    let expiresAt: String?
    let sender: SharedPlaceSender?

    var id: String { code ?? payload.embeddedReceiptID }
    var verifiedSenderLabel: String? { sender?.publicLabel }

    static func embedded(_ payload: SharedPlaceData) -> SharedPlaceReceipt {
        SharedPlaceReceipt(
            code: nil,
            payload: payload,
            sourcePlaceID: nil,
            expiresAt: nil,
            sender: nil
        )
    }

    static func resolve(from url: URL, apiBaseURL: String? = nil) async throws -> SharedPlaceReceipt {
        guard let code = SharedPlaceData.shortCode(from: url) else {
            throw SharedPlaceReceiptError.malformedLink
        }
        guard let baseURL = apiBaseURL
                ?? SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let requestURL = URL(string: "\(baseURL)/v0/shared-place-links/\(code)")
        else {
            throw SharedPlaceReceiptError.missingAPIConfiguration
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: requestURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SharedPlaceReceiptError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SharedPlaceReceiptError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 || httpResponse.statusCode == 410 {
                throw SharedPlaceReceiptError.missingOrExpired
            }
            throw SharedPlaceReceiptError.serverUnavailable
        }

        return try decode(data: data, code: code)
    }

    static func decode(data: Data, code: String) throws -> SharedPlaceReceipt {
        do {
            guard data.count <= ShareRoutePayloadLimits.receiptResponseMaxBytes else {
                throw SharedPlaceReceiptError.invalidResponse
            }
            let response = try JSONDecoder().decode(SharedPlaceLinkResponse.self, from: data)
            guard response.payload.hasValidCoordinate else {
                throw SharedPlaceReceiptError.invalidResponse
            }
            return SharedPlaceReceipt(
                code: code,
                payload: response.payload.sanitizedForReceipt(),
                sourcePlaceID: response.sourcePlaceID,
                expiresAt: response.expiresAt,
                sender: response.sender
            )
        } catch {
            throw SharedPlaceReceiptError.invalidResponse
        }
    }

    var fullAppURL: URL? {
        if let code {
            return URL(string: "wanderly://p/\(code)")
        }
        return payload.toURL(baseURL: "wanderly://p")
    }

    func privatePlace() -> Place {
        Place(
            id: UUID(),
            name: payload.name,
            address: payload.address,
            latitude: payload.lat,
            longitude: payload.lng,
            googlePlaceId: nil,
            category: payload.placeCategory,
            status: .wantToGo,
            rating: payload.rating,
            note: payload.note,
            sourceUrl: payload.sourceURL,
            sourcePlatform: payload.sourcePlatform,
            sourceImageUrl: payload.photoURLs.first,
            businessPhotoUrls: payload.photoURLs,
            extractedDishes: nil,
            priceRange: payload.priceRange,
            recommender: verifiedSenderLabel,
            googleRating: payload.rating,
            googlePriceLevel: nil,
            openingHours: payload.hours,
            createdAt: Date(),
            visibility: .privateMemory,
            socialSignal: nil
        )
    }
}

enum SharedPlaceReceiptDestination: Identifiable {
    case embedded(SharedPlaceData)
    case shortLink(URL)
    case malformed(URL)

    var id: String {
        switch self {
        case .embedded(let payload): return payload.embeddedReceiptID
        case .shortLink(let url): return "short:\(url.absoluteString)"
        case .malformed(let url): return "malformed:\(url.absoluteString)"
        }
    }
}

enum SharedPlaceReceiptError: Error, LocalizedError, Equatable {
    case malformedLink
    case missingAPIConfiguration
    case networkUnavailable
    case missingOrExpired
    case serverUnavailable
    case invalidResponse

    var reasonCode: String {
        switch self {
        case .malformedLink: return "malformed_link"
        case .missingAPIConfiguration: return "missing_api_configuration"
        case .networkUnavailable: return "network_unavailable"
        case .missingOrExpired: return "missing_or_expired"
        case .serverUnavailable: return "server_unavailable"
        case .invalidResponse: return "invalid_response"
        }
    }

    var errorDescription: String? {
        switch self {
        case .malformedLink:
            return "This share link is malformed."
        case .missingAPIConfiguration:
            return "SAV-E is not configured to open this link."
        case .networkUnavailable:
            return "Check your connection and try again."
        case .missingOrExpired:
            return "This share link is missing or has expired."
        case .serverUnavailable:
            return "The share receipt is temporarily unavailable."
        case .invalidResponse:
            return "SAV-E could not verify this share receipt."
        }
    }
}

enum FriendShareReceiptEvent: String {
    case receiptOpened = "friend_share_receipt_opened"
    case saveTapped = "friend_share_save_tapped"
    case openFailed = "friend_share_open_failed"
}

enum FriendShareReceiptSurface: String {
    case web
    case ios
    case appClip = "app_clip"
}

enum FriendShareOpenFailureReason: String {
    case expired
    case malformedPayload = "malformed_payload"
    case networkError = "network_error"
    case serverError = "server_error"
    case unsupportedRoute = "unsupported_route"
    case unknown
}

extension SharedPlaceReceiptError {
    var eventFailureReason: FriendShareOpenFailureReason {
        switch self {
        case .malformedLink: return .unsupportedRoute
        case .networkUnavailable: return .networkError
        case .missingOrExpired: return .expired
        case .invalidResponse: return .malformedPayload
        case .missingAPIConfiguration, .serverUnavailable: return .serverError
        }
    }
}

extension SharedPlaceData {
    var appleMapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: "\(lat),\(lng)")
        ]
        return components?.url
    }

    var placeCategory: PlaceCategory {
        PlaceCategory.allCases.first {
            $0.rawValue.localizedCaseInsensitiveCompare(category) == .orderedSame ||
                $0.displayName.localizedCaseInsensitiveCompare(category) == .orderedSame
        } ?? .food
    }

    var sourcePlatform: SourcePlatform {
        SourcePlatform.allCases.first {
            $0.rawValue.localizedCaseInsensitiveCompare(sourceLabel) == .orderedSame ||
                $0.displayName.localizedCaseInsensitiveCompare(sourceLabel) == .orderedSame
        } ?? .other
    }
}

/// Lightweight trip payload encoded in the App Clip URL.
/// Duplicated across targets — keep in sync with SAVEClip's copy.
struct SharedTripData: Codable {
    let name: String
    let city: String
    let stops: [SharedStop]

    struct SharedStop: Codable, Identifiable {
        let id: String
        let name: String
        let address: String
        let lat: Double
        let lng: Double
        let time: String?
        let note: String?

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    // MARK: - URL Encoding

    static func from(url: URL) -> SharedTripData? {
        ShareRouteCodec.decode(SharedTripData.self, from: url, route: "trip")
    }

    func toURL(baseURL: String? = nil) -> URL? {
        ShareRouteCodec.url(for: self, baseURL: baseURL ?? SaveShareLinkConfig.tripBaseURL)
    }

    // MARK: - Convenience Builders

    /// Build from an AI-generated itinerary response + resolved places.
    static func from(title: String, city: String, days: [ItineraryDay], places: [Place]) -> SharedTripData {
        let placeMap = Dictionary(uniqueKeysWithValues: places.map { ($0.id.uuidString, $0) })
        let stops: [SharedStop] = days.flatMap { day in
            day.stops.map { stop in
                let place = stop.placeId.flatMap { placeMap[$0] }
                return SharedStop(
                    id: UUID().uuidString,
                    name: stop.placeName,
                    address: place?.address ?? "",
                    lat: place?.latitude ?? 0,
                    lng: place?.longitude ?? 0,
                    time: stop.time,
                    note: stop.note
                )
            }
        }
        return SharedTripData(name: title, city: city, stops: stops)
    }

    var routeSummary: String {
        let countLabel = stops.count == 1 ? "1 stop" : "\(stops.count) stops"
        guard !city.isEmpty else { return countLabel }
        return "\(countLabel) in \(city)"
    }
}

enum ShareRoutePayloadLimits {
    static let placePayloadMaxBytes = 12 * 1024
    static let embeddedTokenMaxCharacters = 16 * 1024
    static let pendingPlaceURLMaxBytes = 20 * 1024
    static let receiptResponseMaxBytes = 32 * 1024
    static let publicURLMaxCharacters = 2 * 1024

    static func allowsPlacePayload<T: Encodable>(_ payload: T) -> Bool {
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        return data.count <= placePayloadMaxBytes
    }
}

enum ShareRoutePayloadSanitizer {
    private static let diagnosticPrefixes = [
        "Source URL:",
        "Venue name:",
        "Address clue:",
        "Category clue:",
        "Location clue:",
        "Analysis pipeline:",
        "Evidence tier:",
        "Google Places refined match:",
        "Google Places address:",
        "Google Places coordinates:",
        "Confidence:",
        "Analysis failed:",
        "Debug:",
        "Diagnostic:",
        "Error:",
        "Source recovery failed:",
        "Stack trace:",
    ]

    static func publicPhotoURLs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return Array(values
            .compactMap { publicURL(from: $0)?.absoluteString }
            .filter { seen.insert($0).inserted }
            .prefix(1))
    }

    static func publicURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= ShareRoutePayloadLimits.publicURLMaxCharacters,
              var components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func publicNote(_ value: String?) -> String? {
        let lines: [String] = value?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return !diagnosticPrefixes.contains {
                    line.range(of: $0, options: [.caseInsensitive, .anchored]) != nil
                }
            } ?? []
        let text = lines.prefix(2).joined(separator: " · ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.utf16.count <= 180 { return text }

        var truncated = ""
        var usedUTF16Units = 0
        for character in text {
            let characterUnits = String(character).utf16.count
            guard usedUTF16Units + characterUnits <= 179 else { break }
            truncated.append(character)
            usedUTF16Units += characterUnits
        }
        return truncated.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

enum ShareRouteCodec {
    static func url<T: Encodable>(for payload: T, baseURL: String) -> URL? {
        guard let token = token(for: payload) else { return nil }
        return URL(string: "\(baseURL)/\(token)")
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        route: String,
        maxTokenCharacters: Int? = nil
    ) -> T? {
        guard let token = token(from: url, route: route),
              maxTokenCharacters.map({ token.count <= $0 }) ?? true,
              let data = data(from: token) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func shortCode(from url: URL, route: String) -> String? {
        guard let token = token(from: url, route: route),
              token.range(of: #"^[A-Za-z0-9_-]{6,32}$"#, options: .regularExpression) != nil
        else { return nil }
        return token
    }

    private static func token<T: Encodable>(for payload: T) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(from token: String) -> Data? {
        var base64 = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }
        return Data(base64Encoded: base64)
    }

    private static func token(from url: URL, route: String) -> String? {
        let pathParts = url.path.split(separator: "/").map(String.init)
        if let routeIndex = pathParts.firstIndex(of: route),
           pathParts.indices.contains(routeIndex + 1) {
            return pathParts[routeIndex + 1]
        }
        if url.scheme == "wanderly", url.host == route {
            return pathParts.first ?? legacyQueryToken(from: url)
        }
        return legacyQueryToken(from: url)
    }

    private static func legacyQueryToken(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first(where: { $0.name == "d" })?
            .value
    }
}

private struct SharedPlaceLinkResponse: Codable {
    let payload: SharedPlaceData
    let sourcePlaceID: String?
    let expiresAt: String?
    let sender: SharedPlaceSender?

    private enum CodingKeys: String, CodingKey {
        case payload
        case sourcePlaceID = "source_place_id"
        case expiresAt = "expires_at"
        case sender
    }
}

enum SaveShareLinkConfig {
    static let placeBaseURL: String = {
        SAVEProductionConfig.URLConfigValue(for: ["SAVE_PLACE_SHARE_BASE_URL", "SAVE_SHARE_PLACE_BASE_URL"])
            ?? SAVEProductionConfig.defaultPlaceShareBaseURL
    }()

    static let tripBaseURL: String = {
        SAVEProductionConfig.URLConfigValue(for: ["SAVE_TRIP_SHARE_BASE_URL", "SAVE_SHARE_BASE_URL", "WANDERLY_SHARE_BASE_URL"])
            ?? SAVEProductionConfig.defaultTripShareBaseURL
    }()
}

private extension Place {
    var externalReviewCount: Int? {
        for line in sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let count = Int(value.filter(\.isNumber)) {
                return count
            }
        }
        return nil
    }
}
