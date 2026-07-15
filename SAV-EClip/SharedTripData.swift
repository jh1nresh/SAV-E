import Foundation
import CoreLocation

/// Lightweight place payload encoded in the App Clip URL.
/// Duplicated in SAVEClip target — keep in sync with main app's copy.
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
        guard let sourceURL else { return nil }
        return Self.sanitizedPublicHTTPURL(sourceURL)
    }

    var appleMapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: "\(lat),\(lng)")
        ]
        return components?.url
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

    func toURL(baseURL: String = "https://sav-e-app.vercel.app/p") -> URL? {
        let sanitized = sanitizedForReceipt()
        guard ShareRoutePayloadLimits.allowsPlacePayload(sanitized) else { return nil }
        return ShareRouteCodec.url(for: sanitized, baseURL: baseURL)
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
            photoURLs: Array(photoURLs.compactMap(Self.sanitizedPublicHTTPURL).map(\.absoluteString).prefix(1)),
            note: Self.publicNote(note)
        )
    }

    private static func sanitizedPublicHTTPURL(_ value: String) -> URL? {
        guard value.count <= ShareRoutePayloadLimits.publicURLMaxCharacters,
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

    private static func publicNote(_ value: String?) -> String? {
        let diagnosticPrefixes = [
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
        let text = value?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return !diagnosticPrefixes.contains {
                    line.range(of: $0, options: [.caseInsensitive, .anchored]) != nil
                }
            }
            .prefix(2)
            .joined(separator: " · ") ?? ""
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

struct SharedPlaceSender: Codable {
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

struct SharedPlaceReceipt {
    let code: String?
    let payload: SharedPlaceData
    let sourcePlaceID: String?
    let expiresAt: String?
    let sender: SharedPlaceSender?

    var verifiedSenderLabel: String? { sender?.publicLabel }

    static func embedded(_ payload: SharedPlaceData) -> SharedPlaceReceipt {
        SharedPlaceReceipt(code: nil, payload: payload, sourcePlaceID: nil, expiresAt: nil, sender: nil)
    }

    static func resolve(from url: URL, apiBaseURL: String? = nil) async throws -> SharedPlaceReceipt {
        guard let code = SharedPlaceData.shortCode(from: url),
              let baseURL = apiBaseURL
                ?? SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let requestURL = URL(string: "\(baseURL)/v0/shared-place-links/\(code)")
        else { throw SharedPlaceReceiptError.malformedOrUnconfigured }

        let data: Data
        let response: URLResponse
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
}

enum SharedPlaceReceiptError: Error {
    case malformedOrUnconfigured
    case networkUnavailable
    case missingOrExpired
    case serverUnavailable
    case invalidResponse

    var eventFailureReason: String {
        switch self {
        case .malformedOrUnconfigured: return "unsupported_route"
        case .networkUnavailable: return "network_error"
        case .missingOrExpired: return "expired"
        case .serverUnavailable: return "server_error"
        case .invalidResponse: return "malformed_payload"
        }
    }
}

extension SharedPlaceReceipt {
    static func recordPublicEvent(
        code: String,
        eventType: String,
        reasonCode: String? = nil,
        apiBaseURL: String? = nil
    ) async {
        guard ["friend_share_receipt_opened", "friend_share_open_failed"].contains(eventType),
              let baseURL = apiBaseURL
                ?? SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let url = URL(string: "\(baseURL)/v0/shared-place-links/\(code)/events")
        else { return }

        var body = [
            "event_type": eventType,
            "surface": "app_clip",
        ]
        if let reasonCode { body["reason_code"] = reasonCode }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
}

/// Lightweight trip payload encoded in the App Clip URL.
/// Duplicated in SAVEClip target — keep in sync with main app's copy.
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

    /// Decode from a SAV-E route token, with legacy `?d=` support.
    static func from(url: URL) -> SharedTripData? {
        ShareRouteCodec.decode(SharedTripData.self, from: url, route: "trip")
    }

    /// Encode to a shareable URL.
    func toURL(baseURL: String = "https://sav-e-app.vercel.app/trip") -> URL? {
        ShareRouteCodec.url(for: self, baseURL: baseURL)
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

struct SharedMySavesData: Codable {
    let places: [SavedPlace]
    let visits: [VerifiedVisit]
    let reviews: [StoredReview]
    let counts: Counts

    struct SavedPlace: Codable, Identifiable {
        let name: String
        let area: String?
        let category: String?
        let sourceUrl: String?
        let createdAt: String?

        var id: String {
            [name, area ?? "", sourceUrl ?? ""].joined(separator: "|")
        }

        var mapURL: URL? {
            let query = [name, area].compactMap { $0 }.joined(separator: " ")
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return URL(string: "https://maps.apple.com/?q=\(query.urlQueryEncoded)")
        }

        var safeSourceURL: URL? {
            guard let sourceUrl,
                  let url = URL(string: sourceUrl),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return nil
            }
            return url
        }
    }

    struct VerifiedVisit: Codable, Identifiable {
        let merchant: String
        let total: String?
        let visitDate: String?
        let createdAt: String?

        var id: String {
            [merchant, total ?? "", visitDate ?? "", createdAt ?? ""].joined(separator: "|")
        }
    }

    struct StoredReview: Codable, Identifiable {
        let merchant: String
        let rating: Int?
        let text: String?
        let createdAt: String?

        var id: String {
            [merchant, rating.map(String.init) ?? "", text ?? "", createdAt ?? ""].joined(separator: "|")
        }
    }

    struct Counts: Codable {
        let places: Int
        let visits: Int
        let reviews: Int
    }

    static func isMySavesLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "my" {
            return token(from: url) != nil
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app", "wanderly-api-production.up.railway.app"].contains(url.host ?? "") else {
            return false
        }
        return token(from: url) != nil
    }

    static func token(from url: URL) -> String? {
        let pathParts = url.path.split(separator: "/").map(String.init)
        if let routeIndex = pathParts.firstIndex(of: "my"),
           pathParts.indices.contains(routeIndex + 1) {
            return pathParts[routeIndex + 1]
        }
        if url.scheme == "wanderly", url.host == "my" {
            return pathParts.first
        }
        return nil
    }

    static func resolve(from url: URL, apiBaseURL: String? = nil) async -> SharedMySavesData? {
        guard let token = token(from: url),
              let requestURL = URL(string: "\(resolvedAPIBaseURL(for: url, override: apiBaseURL))/v0/my/\(token)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SharedMySavesData.self, from: data)
        } catch {
            return nil
        }
    }

    private static func resolvedAPIBaseURL(for url: URL, override: String?) -> String {
        if let override, !override.isEmpty {
            return SAVEProductionConfig.removingTrailingSlashes(from: override)
        }
        if url.host?.hasSuffix("up.railway.app") == true,
           let scheme = url.scheme,
           let host = url.host {
            return "\(scheme)://\(host)"
        }
        return SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"])
            ?? SAVEProductionConfig.defaultAPIBaseURL
    }
}

struct SharedListPayload: Codable {
    var list: SharedListData
    var role: String

    static func from(url: URL) -> SharedListPayload? {
        guard isListLink(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let jsonData = Data(base64Encoded: dataParam),
              var payload = try? JSONDecoder().decode(SharedListPayload.self, from: jsonData) else {
            return nil
        }
        if let role = components.queryItems?.first(where: { $0.name == "r" })?.value {
            payload.role = role
            payload.list.viewerRole = role
        }
        return payload
    }

    static func isListLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "list" {
            return true
        }
        return url.scheme == "https" &&
            ["sav-e-app.vercel.app"].contains(url.host ?? "") &&
            url.path == "/list"
    }
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

struct SharedListData: Codable, Identifiable {
    let id: UUID
    let title: String
    let note: String?
    let ownerDisplayName: String
    var viewerRole: String
    let items: [SharedListItem]
    let createdAt: Date
    let updatedAt: Date

    var roleLabel: String {
        viewerRole.capitalized
    }
}

struct SharedListItem: Codable, Identifiable {
    let id: UUID
    let source: String
    let sourceID: String
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let rating: Double?
    let reviewCount: Int?
    let sourceURL: String?
    let photoURLs: [String]
    let note: String?
    let addedByDisplayName: String
    let addedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var sourceLabel: String {
        source == "savedPlace" ? "Map Stamp" : "Map result"
    }
}

struct SharedReferralProfile: Codable, Hashable {
    var referrerId: String
    var handle: String
    var displayName: String
    var referralCode: String
    var lens: String
    var featuredPlaces: [SharedReferralPlace]

    static func from(url: URL) -> SharedReferralProfile? {
        guard isReferralLink(url) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathParts = url.path.split(separator: "/").map(String.init)
        let ref = components?.queryItems?.first(where: { $0.name == "ref" })?.value
        let lens = components?.queryItems?.first(where: { $0.name == "lens" })?.value ?? "friends"

        if pathParts.first == "r", let code = pathParts.dropFirst().first {
            return preview(handle: "friend", code: code, lens: lens)
        }
        if pathParts.first == "u", let handle = pathParts.dropFirst().first {
            return preview(handle: handle, code: ref ?? handle, lens: lens)
        }
        return nil
    }

    static func isReferralLink(_ url: URL) -> Bool {
        url.scheme == "https" &&
            ["sav-e-app.vercel.app"].contains(url.host ?? "") &&
            (url.path.hasPrefix("/r/") || url.path.hasPrefix("/u/"))
    }

    func fullAppURL() -> URL? {
        URL(string: "wanderly://referral?code=\(referralCode)&handle=\(handle)&lens=\(lens)")
    }

    private static func preview(handle: String, code: String, lens: String) -> SharedReferralProfile {
        let displayName = handle
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return SharedReferralProfile(
            referrerId: "ref_\(code)",
            handle: handle,
            displayName: displayName,
            referralCode: code,
            lens: lens,
            featuredPlaces: [
                SharedReferralPlace(name: "Stereoscope Coffee", address: "4542 Beach Blvd, Buena Park, CA", category: "Cafe", lat: 33.8937, lng: -117.9992, signal: "Featured by \(displayName)"),
                SharedReferralPlace(name: "Gem Dining", address: "10836 Warner Ave, Fountain Valley, CA", category: "Food", lat: 33.7157, lng: -117.9396, signal: "Starter map pack"),
                SharedReferralPlace(name: "The Blind Rabbit", address: "440 S Anaheim Blvd, Anaheim, CA", category: "Bar", lat: 33.8312, lng: -117.9128, signal: "Good for first itinerary"),
            ]
        )
    }
}

struct SharedReferralPlace: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(address)" }
    let name: String
    let address: String
    let category: String
    let lat: Double
    let lng: Double
    let signal: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
