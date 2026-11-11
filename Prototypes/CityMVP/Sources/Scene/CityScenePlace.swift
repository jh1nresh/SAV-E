import Foundation

/// Map context is not a saved memory. Identity is retained when names repeat.
struct CityScenePlace: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let address: String
    let latitude: Double
    let longitude: Double
    let isSaved: Bool

    static let originLatitude = 25.033968
    static let originLongitude = 121.564468
    var x: Double { (longitude - Self.originLongitude) * 100850 }
    var z: Double { -(latitude - Self.originLatitude) * 111195 }
    var isInScene: Bool {
        latitude.isFinite && longitude.isFinite && abs(x) <= 700 && abs(z) <= 700
    }
    static var contextDataAvailable: Bool { CitySceneData.elements != nil }

    static func contextPlaces() -> [CityScenePlace] {
        guard let elements = CitySceneData.elements else { return [] }
        var result = [CityScenePlace(id: "landmark-101", title: "台北 101", category: "地標", address: "入口與地址待核對", latitude: originLatitude, longitude: originLongitude, isSaved: false)]
        for way in elements {
            guard let tags = way["tags"] as? [String: String], let name = tags["name"],
                  tags["building"] != nil || tags["leisure"] == "park",
                  let geo = way["geometry"] as? [[String: Double]], geo.count > 3,
                  let wayID = way["id"] as? Int else { continue }
            let points = geo.dropLast()
            guard points.allSatisfy({ ($0["lat"]?.isFinite ?? false) && ($0["lon"]?.isFinite ?? false) }) else { continue }
            let lon = points.reduce(0.0) { $0 + ($1["lon"] ?? 0) } / Double(points.count)
            let lat = points.reduce(0.0) { $0 + ($1["lat"] ?? 0) } / Double(points.count)
            let x = (lon - originLongitude) * 100850, z = -(lat - originLatitude) * 111195
            guard abs(x) < 650, abs(z) < 650,
                  !["台北101", "臺北101"].contains(name.replacingOccurrences(of: " ", with: "")) else { continue }
            let category = tags["leisure"] == "park" ? "公園" : tags["shop"] != nil ? "購物" : tags["amenity"] == "cafe" ? "咖啡" : tags["tourism"] == "hotel" ? "住宿" : "地點"
            let address = [tags["addr:city"], tags["addr:district"], tags["addr:street"], tags["addr:housenumber"]].compactMap { $0 }.joined(separator: " ")
            result.append(.init(id: "way/\(wayID)", title: name, category: category, address: address, latitude: lat, longitude: lon, isSaved: false))
        }
        return result.sorted { $0.x * $0.x + $0.z * $0.z < $1.x * $1.x + $1.z * $1.z }
    }
}

/// Bundled public OSM data; no network, credentials or user vault access.
enum CitySceneData {
    static let att4FunWayID = 234589397

    static func buildingHeight(_ tags: [String: String], way: Int) -> Double {
        // Fujitec documents ten above-ground floors. The extract has no height,
        // so use an illustrative 4.2 m per retail floor for this authored model.
        let fallback = Double(tags["building:levels"] ?? "").map { $0 * 3.2 }
            ?? (way == att4FunWayID ? 42 : 16)
        return min(300, max(tags["building"] == "roof" ? 1 : 4,
                            Double(tags["height"]?.replacingOccurrences(of: " m", with: "") ?? "") ?? fallback))
    }

    static let elements: [[String: Any]]? = {
        guard let url = Bundle.main.url(forResource: "taipei-osm", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = object["elements"] as? [[String: Any]], !elements.isEmpty else { return nil }
        return elements
    }()
}
