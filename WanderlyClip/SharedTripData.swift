import Foundation
import CoreLocation

/// Lightweight trip payload encoded in the App Clip URL.
/// Duplicated in WanderlyClip target — keep in sync with main app's copy.
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

    /// Decode from a wanderly.app URL with base64-encoded `data` query param.
    static func from(url: URL) -> SharedTripData? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let jsonData = Data(base64Encoded: dataParam) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedTripData.self, from: jsonData)
    }

    /// Encode to a shareable URL.
    func toURL(baseURL: String = "https://wanderly.app/trip") -> URL? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let base64 = jsonData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(baseURL)?d=\(base64)")
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
            url.host == "wanderly.app" &&
            url.path == "/list"
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
