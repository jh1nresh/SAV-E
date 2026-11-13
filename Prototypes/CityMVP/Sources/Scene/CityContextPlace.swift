#if SAVVY_CITY_MVP
import Foundation

/// Public map context only. Neither source-node positions nor footprint means
/// establish a verified entrance, recommendation, saved place or Map Stamp.
nonisolated struct CityContextPlace: Codable, Sendable, Equatable, Identifiable {
    enum ObjectType: String, Codable, Sendable { case node, way }
    enum PositionKind: String, Codable, Sendable { case sourceNode, meanFootprintVertices }
    enum Category: String, Codable, Sendable {
        case cafe, food, shopping, park, hotel, sight, transit, service, building
    }
    struct Dataset: Codable, Sendable, Equatable {
        let schemaVersion: Int
        let sourceDate: String
        let records: [CityContextPlace]
    }

    let type: ObjectType
    let osmID: Int64
    let originalName: String
    /// Only an original OSM name:en value; never a generated translation.
    let englishName: String?
    let latitude: Double
    let longitude: Double
    let category: Category
    let positionKind: PositionKind

    private enum CodingKeys: String, CodingKey {
        case type, osmID = "id", originalName, englishName, latitude, longitude, category, positionKind
    }

    var id: String { "\(type.rawValue)/\(osmID)" }
    var sourceURL: URL { URL(string: "https://www.openstreetmap.org/\(id)")! }
    var title: String {
        guard let englishName, !englishName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return originalName }
        return englishName
    }
    var symbol: String {
        switch category {
        case .cafe: "cup.and.saucer.fill"
        case .food: "fork.knife"
        case .shopping: "bag.fill"
        case .park: "leaf.fill"
        case .hotel: "bed.double.fill"
        case .sight: "binoculars.fill"
        case .transit: "tram.fill"
        case .service: "building.2.crop.circle.fill"
        case .building: "building.2.fill"
        }
    }

    static let maximumBytes = 2 * 1_024 * 1_024
    static let maximumRecords = 5_000
    static let sourceDate = "2026-11-11"
    private static let originLatitude = 25.033968
    private static let originLongitude = 121.564468

    /// Reject the entire catalogue on malformed identity, coordinates or schema.
    static func decode(_ data: Data) -> Dataset? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let dataset = try? JSONDecoder().decode(Dataset.self, from: data),
              dataset.schemaVersion == 1, dataset.sourceDate == sourceDate,
              !dataset.records.isEmpty, dataset.records.count <= maximumRecords else { return nil }
        var identities = Set<String>()
        for place in dataset.records {
            guard place.osmID > 0,
                  validText(place.originalName, required: true),
                  place.englishName.map({ validText($0, required: false) }) ?? true,
                  place.latitude.isFinite, place.longitude.isFinite,
                  (-90...90).contains(place.latitude), (-180...180).contains(place.longitude),
                  abs((place.longitude - originLongitude) * 100_850) <= 1_500,
                  abs((place.latitude - originLatitude) * 111_195) <= 1_500,
                  place.positionKind == (place.type == .node ? .sourceNode : .meanFootprintVertices),
                  identities.insert(place.id).inserted else { return nil }
        }
        return dataset
    }

    private static func validText(_ value: String, required: Bool) -> Bool {
        value.count <= 180
            && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static let catalogue: Dataset? = {
        guard let url = Bundle.main.url(forResource: "taipei-context-labels", withExtension: "json"),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maximumBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return decode(data)
    }()

    static let byID: [String: CityContextPlace] = Dictionary(uniqueKeysWithValues: (catalogue?.records ?? []).map { ($0.id, $0) })
    static let bySource: [String: CityContextPlace] = Dictionary(uniqueKeysWithValues: (catalogue?.records ?? []).map { ($0.sourceURL.absoluteString, $0) })

    @MainActor static var enabled: Bool {
        (CityMVPPreviewConfiguration.enabled || (CityDistrictTrace.enabled
            && ProcessInfo.processInfo.arguments.contains("--verify-context-labels")))
            && catalogue != nil
    }
}
#endif
