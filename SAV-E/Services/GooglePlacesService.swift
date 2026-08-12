import Foundation
import CoreLocation
import MapKit

// MARK: - Protocol

protocol GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch]
    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails
    func photoURL(reference: String, maxWidth: Int) -> URL?
}

// MARK: - Models

struct GooglePlaceMatch: Identifiable, Codable {
    let id: String // placeId
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var reviewCount: Int? = nil
    var priceLevel: Int?
    var photoReference: String? = nil
    var types: [String] = []
}

struct GooglePlaceDetails: Codable {
    var placeId: String
    var name: String
    var formattedAddress: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var priceLevel: Int?
    var openingHours: [String]?
    var phoneNumber: String?
    var websiteUrl: String?
    var photoReferences: [String]?
    var types: [String] = []
    /// Structured `opening_hours.periods`, when Google returns them. The flat
    /// `openingHours` strings stay for display; the planner needs these.
    var openingPeriods: [SavePlaceOpeningPeriod]? = nil
}

enum PlaceMatchProvider: String, Codable, Hashable {
    case googlePlaces = "google_places"
    case appleMaps = "apple_maps"
    case amap
    case baidu

    var displayName: String {
        switch self {
        case .googlePlaces: return "Google Places"
        case .appleMaps: return "Apple Maps"
        case .amap: return "Amap"
        case .baidu: return "Baidu Maps"
        }
    }

    var refinementFailureMessage: String {
        switch self {
        case .googlePlaces: return "Google Places refine skipped or failed; confirm exact address/coordinates"
        case .appleMaps: return "Apple Maps refine skipped or failed; confirm exact address/coordinates"
        case .amap: return "Amap refine skipped or failed; confirm exact address/coordinates"
        case .baidu: return "Baidu Maps refine skipped or failed; confirm exact address/coordinates"
        }
    }
}

enum PlaceCoordinateSystem: String, Codable, Hashable {
    case wgs84 = "WGS84"
    case gcj02 = "GCJ-02"
    case bd09 = "BD-09"
}

struct PlaceProviderMatch: Identifiable, Codable, Hashable {
    let provider: PlaceMatchProvider
    let id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var reviewCount: Int?
    var priceLevel: Int?
    var types: [String]
    var coordinateSystem: PlaceCoordinateSystem

    var coordinateEvidenceLabel: String {
        switch coordinateSystem {
        case .wgs84:
            return "\(provider.displayName) coordinates"
        case .gcj02, .bd09:
            return "\(provider.displayName) coordinates (\(coordinateSystem.rawValue))"
        }
    }
}

struct ChinaPlaceResolverConfigurationStatus: Equatable {
    var appleMapsAvailable: Bool
    var backendProxyConfigured: Bool
    var missingRequirements: [String]

    var configuredProviders: [String] {
        var providers: [String] = []
        if appleMapsAvailable { providers.append("apple_maps") }
        if backendProxyConfigured { providers.append("backend_proxy") }
        return providers
    }

    var canResolveChinaPOI: Bool {
        appleMapsAvailable || backendProxyConfigured
    }
}

enum ChinaPlaceResolverConfiguration {
    static func status(
        appleMapsAvailable: Bool = true,
        backendAPIBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
        accessTokenProviderConfigured: Bool = true
    ) -> ChinaPlaceResolverConfigurationStatus {
        let backendProxyConfigured = backendAPIBaseURL != nil && accessTokenProviderConfigured
        let missing = appleMapsAvailable || backendProxyConfigured
            ? []
            : ["Apple Maps availability or SAVE_API_URL with authenticated backend place resolver"]
        return ChinaPlaceResolverConfigurationStatus(
            appleMapsAvailable: appleMapsAvailable,
            backendProxyConfigured: backendProxyConfigured,
            missingRequirements: missing
        )
    }

}

protocol PlaceResolverServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

protocol AppleMapsPlaceSearchServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

protocol BackendPlaceResolverServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

// MARK: - Errors

enum GooglePlacesError: LocalizedError {
    case apiKeyMissing
    case noResults
    case networkError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Google Places key missing. Gemini is configured separately, but Refine + Save requires GOOGLE_PLACES_API_KEY."
        case .noResults: return "No matching places found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let msg): return "Places API: \(msg)"
        }
    }
}

enum BackendPlaceResolverError: LocalizedError {
    case notConfigured
    case noResults
    case apiError(String)
}

// MARK: - Provider Resolver

final class PlaceResolverService: PlaceResolverServiceProtocol {
    static let shared = PlaceResolverService()

    private let googlePlacesService: GooglePlacesServiceProtocol
    private let appleMapsPlaceSearchService: AppleMapsPlaceSearchServiceProtocol
    private let backendPlaceResolverService: BackendPlaceResolverServiceProtocol

    init(
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        appleMapsPlaceSearchService: AppleMapsPlaceSearchServiceProtocol = AppleMapsPlaceSearchService.shared,
        backendPlaceResolverService: BackendPlaceResolverServiceProtocol = BackendPlaceResolverService.shared
    ) {
        self.googlePlacesService = googlePlacesService
        self.appleMapsPlaceSearchService = appleMapsPlaceSearchService
        self.backendPlaceResolverService = backendPlaceResolverService
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        var results: [PlaceProviderMatch] = []
        var seen = Set<String>()
        let shouldTryChinaProviders = Self.shouldTryChinaProviders(for: query)

        if shouldTryChinaProviders,
           let appleMatches = try? await appleMapsPlaceSearchService.searchPlace(query: query, near: near) {
            append(appleMatches, to: &results, seen: &seen)
        }

        if shouldTryChinaProviders,
           let proxyMatches = try? await backendPlaceResolverService.searchPlace(query: query, near: near) {
            append(proxyMatches, to: &results, seen: &seen)
        }

        if let googleMatches = try? await googlePlacesService.searchPlace(query: query, near: near) {
            append(googleMatches.map(\.providerMatch), to: &results, seen: &seen)
        }

        guard !results.isEmpty else { throw GooglePlacesError.noResults }
        return results
    }

    static func chinaProviderConfigurationStatus() -> ChinaPlaceResolverConfigurationStatus {
        ChinaPlaceResolverConfiguration.status()
    }

    private func append(_ matches: [PlaceProviderMatch], to results: inout [PlaceProviderMatch], seen: inout Set<String>) {
        for match in matches {
            let key = "\(match.provider.rawValue):\(match.id)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(match)
        }
    }

    private static func shouldTryChinaProviders(for query: String) -> Bool {
        query.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
                (0x3400...0x4DBF).contains(Int(scalar.value))
        }
    }
}

// MARK: - Apple Maps

final class AppleMapsPlaceSearchService: AppleMapsPlaceSearchServiceProtocol {
    static let shared = AppleMapsPlaceSearchService()

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let near {
            request.region = MKCoordinateRegion(
                center: near,
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        let matches = response.mapItems.prefix(20).compactMap { item -> PlaceProviderMatch? in
            let name = (item.name ?? item.placemark.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let coordinate = item.placemark.coordinate
            guard !name.isEmpty,
                  coordinate.latitude.isFinite,
                  coordinate.longitude.isFinite,
                  (-90...90).contains(coordinate.latitude),
                  (-180...180).contains(coordinate.longitude),
                  !(coordinate.latitude == 0 && coordinate.longitude == 0) else {
                return nil
            }

            let address = Self.address(from: item.placemark)
            let id = "apple-\(name.lowercased())-\(coordinate.latitude)-\(coordinate.longitude)"
            return PlaceProviderMatch(
                provider: .appleMaps,
                id: id,
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                rating: nil,
                reviewCount: nil,
                priceLevel: nil,
                types: [item.pointOfInterestCategory?.rawValue].compactMap { $0 },
                coordinateSystem: .wgs84
            )
        }

        guard !matches.isEmpty else { throw GooglePlacesError.noResults }
        return Array(matches)
    }

    private static func address(from placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [
            street,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
            .joined(separator: ", ")
    }
}

private extension GooglePlaceMatch {
    var providerMatch: PlaceProviderMatch {
        PlaceProviderMatch(
            provider: .googlePlaces,
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            reviewCount: reviewCount,
            priceLevel: priceLevel,
            types: types,
            coordinateSystem: .wgs84
        )
    }
}

// MARK: - Implementation

final class GooglePlacesService: GooglePlacesServiceProtocol {
    static let shared = GooglePlacesService()

    private let apiKey: String?
    private let session: URLSession
    private let bundleIdentifier: String?

    init(
        apiKey: String? = nil,
        session: URLSession? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.apiKey = Self.normalizedAPIKey(
            apiKey
                ?? ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"]
                ?? SAVEProductionConfig.keyFromPlist("GOOGLE_PLACES_API_KEY")
        )
        self.bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let placeholders: Set<String> = [
            "YOUR_KEY_HERE",
            "REPLACE_ME",
            "GOOGLE_PLACES_API_KEY"
        ]
        return placeholders.contains(trimmed.uppercased()) ? nil : trimmed
    }

    // MARK: - Text Search

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        guard let apiKey, !apiKey.isEmpty else {
            throw GooglePlacesError.apiKeyMissing
        }

        var urlString = "https://maps.googleapis.com/maps/api/place/textsearch/json?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&key=\(apiKey)"

        if let location = near {
            urlString += "&location=\(location.latitude),\(location.longitude)&radius=5000"
        }

        guard let url = URL(string: urlString) else {
            throw GooglePlacesError.noResults
        }

        let (data, _) = try await session.data(for: authorizedRequest(for: url))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let results = json?["results"] as? [[String: Any]], !results.isEmpty else {
            if let status = json?["status"] as? String, status != "OK" {
                throw GooglePlacesError.apiError(status)
            }
            throw GooglePlacesError.noResults
        }

        return results.prefix(20).compactMap { result in
            guard let placeId = result["place_id"] as? String,
                  let name = result["name"] as? String,
                  let geometry = result["geometry"] as? [String: Any],
                  let location = geometry["location"] as? [String: Any],
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double else { return nil }

            return GooglePlaceMatch(
                id: placeId,
                name: name,
                address: result["formatted_address"] as? String ?? "",
                latitude: lat,
                longitude: lng,
                rating: result["rating"] as? Double,
                reviewCount: result["user_ratings_total"] as? Int,
                priceLevel: result["price_level"] as? Int,
                photoReference: (result["photos"] as? [[String: Any]])?.first?["photo_reference"] as? String,
                types: result["types"] as? [String] ?? []
            )
        }
    }

    // MARK: - Place Details

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        guard let apiKey, !apiKey.isEmpty else {
            throw GooglePlacesError.apiKeyMissing
        }

        let fields = "place_id,name,formatted_address,geometry,rating,price_level,opening_hours,formatted_phone_number,website,photos,types"
        let urlString = "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&fields=\(fields)&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw GooglePlacesError.noResults
        }

        let (data, _) = try await session.data(for: authorizedRequest(for: url))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let result = json?["result"] as? [String: Any] else {
            if let status = json?["status"] as? String, status != "OK" {
                throw GooglePlacesError.apiError(status)
            }
            throw GooglePlacesError.noResults
        }

        let geometry = result["geometry"] as? [String: Any]
        let location = geometry?["location"] as? [String: Any]
        let openingHours = result["opening_hours"] as? [String: Any]
        let photos = result["photos"] as? [[String: Any]]

        return GooglePlaceDetails(
            placeId: placeId,
            name: result["name"] as? String ?? "",
            formattedAddress: result["formatted_address"] as? String ?? "",
            latitude: location?["lat"] as? Double ?? 0,
            longitude: location?["lng"] as? Double ?? 0,
            rating: result["rating"] as? Double,
            priceLevel: result["price_level"] as? Int,
            openingHours: openingHours?["weekday_text"] as? [String],
            phoneNumber: result["formatted_phone_number"] as? String,
            websiteUrl: result["website"] as? String,
            photoReferences: photos?.compactMap { $0["photo_reference"] as? String },
            types: result["types"] as? [String] ?? [],
            openingPeriods: SavePlaceOpeningPeriod.periods(
                fromGooglePeriods: openingHours?["periods"] as? [[String: Any]]
            )
        )
    }

    // MARK: - Photo URL

    func photoURL(reference: String, maxWidth: Int = 400) -> URL? {
        guard apiKey != nil else { return nil }
        return GooglePlacesPhotoURL.persistableURL(reference: reference, maxWidth: maxWidth)
    }

    func authorizedPhotoURL(for persistedURL: URL) -> URL? {
        guard GooglePlacesPhotoURL.isGooglePlacesPhotoURL(persistedURL) else { return persistedURL }
        guard let apiKey else { return nil }
        return GooglePlacesPhotoURL.authorizedURL(persistedURL, apiKey: apiKey)
    }

    func authorizedPhotoRequest(for persistedURL: URL) -> URLRequest? {
        guard let requestURL = authorizedPhotoURL(for: persistedURL) else { return nil }
        return GooglePlacesPhotoURL.isGooglePlacesPhotoURL(persistedURL)
            ? authorizedRequest(for: requestURL)
            : URLRequest(url: requestURL)
    }

    private func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        return request
    }
}

enum GooglePlacesPhotoURL {
    nonisolated private static let host = "maps.googleapis.com"
    nonisolated private static let path = "/maps/api/place/photo"

    nonisolated static func persistableURL(reference: String, maxWidth: Int) -> URL? {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "maxwidth", value: String(max(1, maxWidth))),
            URLQueryItem(name: "photo_reference", value: normalizedReference),
        ]
        return urlWithLiteralPlusesEncoded(from: components)
    }

    nonisolated static func persistableURL(_ url: URL) -> URL {
        guard isGooglePlacesPhotoURL(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = components.queryItems?.filter { $0.name.lowercased() != "key" }
        return urlWithLiteralPlusesEncoded(from: components) ?? url
    }

    nonisolated static func persistableString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let url = URL(string: normalized) else { return normalized }
        return persistableURL(url).absoluteString
    }

    nonisolated static func persistableStrings(_ values: [String]?) -> [String]? {
        guard let values else { return nil }
        let sanitized = values.compactMap(persistableString)
        return sanitized.isEmpty ? nil : sanitized
    }

    nonisolated static func isGooglePlacesPhotoURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == host &&
            url.path == path
    }

    nonisolated static func authorizedURL(_ persistedURL: URL, apiKey: String) -> URL? {
        guard isGooglePlacesPhotoURL(persistedURL),
              var components = URLComponents(url: persistableURL(persistedURL), resolvingAgainstBaseURL: false)
        else { return persistedURL }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
        components.queryItems = queryItems
        return urlWithLiteralPlusesEncoded(from: components)
    }

    nonisolated private static func urlWithLiteralPlusesEncoded(from components: URLComponents) -> URL? {
        var encodedComponents = components
        encodedComponents.percentEncodedQuery = encodedComponents.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return encodedComponents.url
    }
}

// MARK: - Backend place resolver proxy

final class BackendPlaceResolverService: BackendPlaceResolverServiceProtocol {
    static let shared = BackendPlaceResolverService()

    private let apiBaseURL: String?
    private let accessTokenProvider: (() async throws -> String)?

    init(
        apiBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
        accessTokenProvider: (() async throws -> String)? = {
            try await PrivyAuthService.shared.accessToken()
        }
    ) {
        self.apiBaseURL = apiBaseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessTokenProvider = accessTokenProvider
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        guard let apiBaseURL, !apiBaseURL.isEmpty,
              let endpoint = URL(string: "\(apiBaseURL)/place-resolve") else {
            throw BackendPlaceResolverError.notConfigured
        }
        guard let accessTokenProvider else { throw BackendPlaceResolverError.notConfigured }

        var body: [String: Any] = ["query": query, "provider": "china"]
        if let near {
            body["near"] = ["latitude": near.latitude, "longitude": near.longitude]
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessTokenProvider())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BackendPlaceResolverError.apiError(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(BackendPlaceResolveResponse.self, from: data)
        guard !decoded.matches.isEmpty else { throw BackendPlaceResolverError.noResults }
        return decoded.matches
    }
}

private struct BackendPlaceResolveResponse: Codable {
    var matches: [PlaceProviderMatch]
}

// MARK: - China map deep-link parser

struct ChinaMapDeepLinkParser {
    static func match(from urlString: String) -> PlaceProviderMatch? {
        guard let match = SharedChinaMapLinkParser.match(from: urlString) else { return nil }
        return PlaceProviderMatch(
            provider: match.provider == .amap ? .amap : .baidu,
            id: match.id,
            name: match.name,
            address: match.address,
            latitude: match.latitude,
            longitude: match.longitude,
            rating: nil,
            reviewCount: nil,
            priceLevel: nil,
            types: [],
            coordinateSystem: {
                switch match.coordinateSystem {
                case .wgs84: return .wgs84
                case .gcj02: return .gcj02
                case .bd09: return .bd09
                }
            }()
        )
    }
}
