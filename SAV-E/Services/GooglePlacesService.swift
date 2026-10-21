import Foundation
import CoreGraphics
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
    /// Session-only photo records with `html_attributions`. Never persist.
    var photos: [GooglePlacePhoto]? = nil
    /// Place Details `url` (legacy) / `googleMapsUri` (new). Session-only.
    var googleMapsUri: String? = nil
}

struct GooglePlacePhoto: Codable, Hashable {
    var photoReference: String
    var htmlAttributions: [String] = []
}

struct GooglePlacePhotoAuthor: Hashable {
    var displayName: String
    var uri: URL?
}

/// Session-only Google photo metadata keyed by the key-stripped photo URL.
struct GooglePlacePhotoRecord: Hashable {
    var url: URL
    var authors: [GooglePlacePhotoAuthor]
    var googleMapsURI: URL?
}

enum GoogleMapsPlatformAvailability {
    /// Mainland China is a Google Maps Platform prohibited territory.
    /// Users there must not trigger Places calls; show coral / own photos.
    static func isAllowed(regionCode: String? = Locale.current.region?.identifier) -> Bool {
        regionCode?.uppercased() != "CN"
    }
}

enum GoogleMapsAttributionMetrics {
    /// Official Places logo height range is 16–19dp.
    static let logoHeight: CGFloat = 18
    static let logoMinHeight: CGFloat = 16
    static let logoMaxHeight: CGFloat = 19
    static let clearSpaceLeading: CGFloat = 10
    static let clearSpaceTrailing: CGFloat = 10
    static let clearSpaceTop: CGFloat = 10
    static let clearSpaceBottom: CGFloat = 5
}

enum GooglePlacesHTMLAttribution {
    static func authors(from htmlAttributions: [String]) -> [GooglePlacePhotoAuthor] {
        htmlAttributions.compactMap { raw in
            let html = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !html.isEmpty else { return nil }
            if let link = firstLink(in: html) {
                return GooglePlacePhotoAuthor(displayName: link.name, uri: link.uri)
            }
            let name = unescape(stripTags(html))
            guard !name.isEmpty else { return nil }
            return GooglePlacePhotoAuthor(displayName: name, uri: nil)
        }
    }

    static func mapsURL(placeId: String?, explicit: String? = nil) -> URL? {
        if let explicit, let url = URL(string: explicit.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        let trimmed = placeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "place_id:\(trimmed)"),
            URLQueryItem(name: "query_place_id", value: trimmed),
        ]
        return components?.url
    }

    private static func firstLink(in html: String) -> (name: String, uri: URL?)? {
        let pattern = #"<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let hrefRange = Range(match.range(at: 1), in: html),
              let nameRange = Range(match.range(at: 2), in: html)
        else { return nil }
        let name = unescape(stripTags(String(html[nameRange])))
        guard !name.isEmpty else { return nil }
        return (name, URL(string: String(html[hrefRange])))
    }

    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

enum GooglePlacePhotoSessionStore {
    private static let lock = NSLock()
    private static var records: [URL: GooglePlacePhotoRecord] = [:]

    static func remember(_ photos: [GooglePlacePhotoRecord]) {
        lock.lock()
        defer { lock.unlock() }
        for photo in photos {
            records[GooglePlacesPhotoURL.persistableURL(photo.url)] = photo
        }
    }

    static func record(for url: URL) -> GooglePlacePhotoRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[GooglePlacesPhotoURL.persistableURL(url)]
    }

    static func resetForTests() {
        lock.lock()
        records.removeAll()
        lock.unlock()
    }
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
    var mapURL: String? = nil

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
        try await SAVEAnalysisScope.current?.checkAllowed()
        var results: [PlaceProviderMatch] = []
        var seen = Set<String>()
        let shouldTryChinaProviders = Self.shouldTryChinaProviders(for: query)

        if shouldTryChinaProviders,
           let appleMatches = try? await appleMapsPlaceSearchService.searchPlace(query: query, near: near) {
            append(appleMatches, to: &results, seen: &seen)
        }

        try await SAVEAnalysisScope.current?.checkAllowed()
        if shouldTryChinaProviders,
           let proxyMatches = try? await backendPlaceResolverService.searchPlace(query: query, near: near) {
            append(proxyMatches, to: &results, seen: &seen)
        }

        try await SAVEAnalysisScope.current?.checkAllowed()
        if let googleMatches = try? await googlePlacesService.searchPlace(query: query, near: near) {
            append(googleMatches.map(\.providerMatch), to: &results, seen: &seen)
        }

        try await SAVEAnalysisScope.current?.checkAllowed()
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

        let response = try await SAVEAnalysisScope.measure(.appleMaps) {
            try await MKLocalSearch(request: request).start()
        }
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
    private let apiBaseURL: String?
    private let accessTokenProvider: () async throws -> String

    init(
        apiKey: String? = nil,
        session: URLSession? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        apiBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
        accessTokenProvider: @escaping () async throws -> String = { try await PrivyAuthService.shared.accessToken() }
    ) {
        self.apiKey = Self.normalizedAPIKey(
            apiKey
                ?? ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"]
                ?? SAVEProductionConfig.keyFromPlist("GOOGLE_PLACES_API_KEY")
        )
        self.apiBaseURL = apiBaseURL
        self.accessTokenProvider = accessTokenProvider
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
        let data: Data
        if let context = SAVEAnalysisScope.current {
            try await context.checkAllowed()
            guard let apiBaseURL, let url = URL(string: "\(apiBaseURL)/v0/analysis/\(context.id.uuidString)/places") else {
                throw SAVEAnalysisError.denied
            }
            var body: [String: Any] = ["query": query]
            if let near, SaveChromeNavigation.isTrustworthyMapCoordinate(near) {
                body["latitude"] = near.latitude
                body["longitude"] = near.longitude
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(try await accessTokenProvider())", forHTTPHeaderField: "Authorization")
            request.setValue(context.id.uuidString, forHTTPHeaderField: "x-save-analysis-id")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                if SAVEAnalysisError.isControlDenial(responseData) {
                    await context.markDenied()
                    throw SAVEAnalysisError.denied
                }
                await context.markProviderFailure()
                throw GooglePlacesError.noResults
            }
            data = responseData
        } else {
            guard let apiKey, !apiKey.isEmpty else {
                throw GooglePlacesError.apiKeyMissing
            }

            var urlString = "https://maps.googleapis.com/maps/api/place/textsearch/json?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&key=\(apiKey)"

            if let location = near, SaveChromeNavigation.isTrustworthyMapCoordinate(location) {
                urlString += "&location=\(location.latitude),\(location.longitude)&radius=5000"
            }

            guard let url = URL(string: urlString) else {
                throw GooglePlacesError.noResults
            }

            (data, _) = try await session.data(for: authorizedRequest(for: url))
        }
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
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            guard SaveChromeNavigation.isTrustworthyMapCoordinate(coordinate) else { return nil }

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
        guard SAVEAnalysisScope.current == nil else { throw SAVEAnalysisError.denied }
        guard let apiKey, !apiKey.isEmpty else {
            throw GooglePlacesError.apiKeyMissing
        }

        let fields = "place_id,name,formatted_address,geometry,rating,price_level,opening_hours,formatted_phone_number,website,photos,types,url"
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
        let photos = parsedPhotos(result["photos"] as? [[String: Any]])

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
            photoReferences: photos?.map(\.photoReference),
            types: result["types"] as? [String] ?? [],
            openingPeriods: SavePlaceOpeningPeriod.periods(
                fromGooglePeriods: openingHours?["periods"] as? [[String: Any]]
            ),
            photos: photos,
            googleMapsUri: result["url"] as? String
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

    private func parsedPhotos(_ photos: [[String: Any]]?) -> [GooglePlacePhoto]? {
        let parsed = (photos ?? []).compactMap { photo -> GooglePlacePhoto? in
            guard let reference = photo["photo_reference"] as? String,
                  !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return GooglePlacePhoto(
                photoReference: reference,
                htmlAttributions: photo["html_attributions"] as? [String] ?? []
            )
        }
        return parsed.isEmpty ? nil : parsed
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

    /// Durable persistence only. Google Places photo URLs, media paths, and
    /// photo references must not be stored; `place_id` is the exempt field.
    nonisolated static func persistableString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if looksLikeGooglePlacesPhotoReference(normalized) { return nil }
        guard let url = URL(string: normalized) else { return normalized }
        if isGooglePlacesPhotoURL(url) { return nil }
        return persistableURL(url).absoluteString
    }

    nonisolated static func persistableStrings(_ values: [String]?) -> [String]? {
        guard let values else { return nil }
        let sanitized = values.compactMap(persistableString)
        return sanitized.isEmpty ? nil : sanitized
    }

    nonisolated static func isGooglePlacesPhotoURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        let hostname = url.host?.lowercased() ?? ""
        guard scheme == "https" else { return false }
        if hostname == host && url.path == path { return true }
        if hostname == "places.googleapis.com" && url.path.contains("/media") { return true }
        return false
    }

    nonisolated static func looksLikeGooglePlacesPhotoReference(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("photo_reference=") { return true }
        if lower.hasPrefix("places/") && lower.contains("/photos/") { return true }
        return false
    }

    /// Session display only. Mainland-China users never load Google photo URLs.
    nonisolated static func isDisplayable(_ value: String, mapsAllowed: Bool = GoogleMapsPlatformAvailability.isAllowed()) -> Bool {
        guard let url = URL(string: value) else { return true }
        return !isGooglePlacesPhotoURL(url) || mapsAllowed
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
    private let session: URLSession
    private let accessTokenProvider: (() async throws -> String)?

    init(
        apiBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
        session: URLSession = .shared,
        accessTokenProvider: (() async throws -> String)? = {
            try await PrivyAuthService.shared.accessToken()
        }
    ) {
        self.apiBaseURL = apiBaseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        try await SAVEAnalysisScope.current?.checkAllowed()
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

        request.setValue(SAVEAnalysisScope.current?.id.uuidString, forHTTPHeaderField: "x-save-analysis-id")
        let (data, response) = try await SAVEAnalysisScope.measure(.chinaPlaces, outcome: SAVEAnalysisScope.httpOutcome) {
            try await session.data(for: request)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if SAVEAnalysisError.isControlDenial(data) {
                await SAVEAnalysisScope.current?.markDenied()
                throw SAVEAnalysisError.denied
            }
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
