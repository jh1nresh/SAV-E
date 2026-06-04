import Foundation
import CoreLocation

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

    static func from(url: URL) -> SharedPlaceData? {
        ShareRouteCodec.decode(SharedPlaceData.self, from: url, route: "p")
    }

    static func shortCode(from url: URL) -> String? {
        ShareRouteCodec.shortCode(from: url, route: "p")
    }

    static func resolveShortCode(from url: URL, apiBaseURL: String? = nil) async -> SharedPlaceData? {
        guard let code = shortCode(from: url),
              let baseURL = apiBaseURL
                ?? SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let requestURL = URL(string: "\(baseURL)/v0/shared-place-links/\(code)")
        else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SharedPlaceLinkResponse.self, from: data).payload
        } catch {
            return nil
        }
    }

    func toURL(baseURL: String? = nil) -> URL? {
        ShareRouteCodec.url(for: self, baseURL: baseURL ?? SaveShareLinkConfig.placeBaseURL)
    }

    static func from(place: Place) -> SharedPlaceData {
        SharedPlaceData(
            id: place.id.uuidString,
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
            sourceURL: place.primarySourceURL?.absoluteString,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(place.businessPhotoURLStrings),
            note: ShareRoutePayloadSanitizer.publicNote(place.note)
        )
    }

    static func from(candidate: SaveMapCandidate) -> SharedPlaceData {
        SharedPlaceData(
            id: candidate.id,
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
            sourceURL: candidate.sourceURL,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(candidate.businessPhotoURLStrings),
            note: ShareRoutePayloadSanitizer.publicNote(candidate.shareNote)
        )
    }

    static func from(result: SaveSearchResult) -> SharedPlaceData? {
        guard let latitude = result.latitude,
              let longitude = result.longitude,
              latitude != 0 || longitude != 0 else { return nil }

        return SharedPlaceData(
            id: result.id,
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
            sourceURL: result.sourceURL,
            photoURLs: ShareRoutePayloadSanitizer.publicPhotoURLs(result.businessPhotoURLStrings),
            note: ShareRoutePayloadSanitizer.publicNote(result.shareNote)
        )
    }

    static func from(candidate: PlaceReviewCandidate) -> SharedPlaceData? {
        guard let latitude = candidate.latitude,
              let longitude = candidate.longitude,
              latitude != 0 || longitude != 0 else { return nil }

        return SharedPlaceData(
            id: candidate.id.uuidString,
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
            sourceURL: candidate.evidence.compactMap(Self.firstURLString(in:)).first,
            photoURLs: [],
            note: candidate.confidence.map { "Confidence: \(Int($0 * 100))%" }
        )
    }

    private static func firstURLString(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).first?.url?.absoluteString
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
    ]

    static func publicPhotoURLs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return Array(values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(1))
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
        if text.count <= 180 { return text }
        let end = text.index(text.startIndex, offsetBy: 180)
        return String(text[..<end]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) + "…"
    }
}

enum ShareRouteCodec {
    static func url<T: Encodable>(for payload: T, baseURL: String) -> URL? {
        guard let token = token(for: payload) else { return nil }
        return URL(string: "\(baseURL)/\(token)")
    }

    static func decode<T: Decodable>(_ type: T.Type, from url: URL, route: String) -> T? {
        guard let token = token(from: url, route: route),
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
