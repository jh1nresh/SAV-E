import Foundation
import CoreLocation

/// Lightweight trip payload encoded in the App Clip URL.
/// Duplicated across targets — keep in sync with WanderlyClip's copy.
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let jsonData = Data(base64Encoded: dataParam) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedTripData.self, from: jsonData)
    }

    func toURL(baseURL: String? = nil) -> URL? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let base64 = jsonData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(baseURL ?? SaveShareLinkConfig.tripBaseURL)?d=\(base64)")
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

    static func from(place: Place) -> SharedTripData {
        SharedTripData(
            name: place.name,
            city: place.shareAreaLabel,
            stops: [
                SharedStop(
                    id: place.id.uuidString,
                    name: place.name,
                    address: place.address,
                    lat: place.latitude,
                    lng: place.longitude,
                    time: nil,
                    note: place.note
                )
            ]
        )
    }

    static func from(candidate: SaveMapCandidate) -> SharedTripData {
        SharedTripData(
            name: candidate.title,
            city: candidate.shareAreaLabel,
            stops: [
                SharedStop(
                    id: candidate.id,
                    name: candidate.title,
                    address: candidate.subtitle,
                    lat: candidate.latitude,
                    lng: candidate.longitude,
                    time: nil,
                    note: candidate.shareNote
                )
            ]
        )
    }

    static func from(result: SaveSearchResult) -> SharedTripData? {
        guard let latitude = result.latitude,
              let longitude = result.longitude,
              latitude != 0 || longitude != 0 else { return nil }

        return SharedTripData(
            name: result.title,
            city: result.cityOrArea ?? "",
            stops: [
                SharedStop(
                    id: result.id,
                    name: result.title,
                    address: result.subtitle,
                    lat: latitude,
                    lng: longitude,
                    time: nil,
                    note: result.shareNote
                )
            ]
        )
    }
}

private enum SaveShareLinkConfig {
    static let tripBaseURL: String = {
        configValue(for: ["SAVE_SHARE_BASE_URL", "WANDERLY_SHARE_BASE_URL"])
            ?? "https://wanderly.app/trip"
    }()

    private static func configValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = normalizedConfigValue(ProcessInfo.processInfo.environment[key]) {
                return removingTrailingSlashes(from: value)
            }
            if let value = normalizedConfigValue(keyFromPlist(key)) {
                return removingTrailingSlashes(from: value)
            }
        }
        return nil
    }

    private static func normalizedConfigValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "YOUR_KEY_HERE"
        else { return nil }
        return value
    }

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return nil }
        return dict[key]
    }

    private static func removingTrailingSlashes(from value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
