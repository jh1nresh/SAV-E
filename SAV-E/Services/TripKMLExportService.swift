import Foundation

enum TripKMLExportError: LocalizedError {
    case invalidSelection
    case invalidCoordinates(String)
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            return "KML export requires 1 to 100 confirmed Map Stamps."
        case .invalidCoordinates(let name):
            return "\(name) needs valid coordinates before KML export."
        case .invalidDocument:
            return "SAV-E could not create a valid KML document."
        }
    }
}

enum TripKMLExportService {
    static func reviewerDemoData(placeIDs: [UUID], places: [Place]) throws -> Data {
        var seen = Set<UUID>()
        let orderedIDs = placeIDs.filter { seen.insert($0).inserted }
        guard (1...100).contains(orderedIDs.count) else {
            throw TripKMLExportError.invalidSelection
        }

        let placeByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let selected = try orderedIDs.map { id -> Place in
            guard let place = placeByID[id] else {
                throw TripKMLExportError.invalidSelection
            }
            guard place.latitude.isFinite,
                  place.longitude.isFinite,
                  (-90...90).contains(place.latitude),
                  (-180...180).contains(place.longitude),
                  place.latitude != 0 || place.longitude != 0
            else {
                throw TripKMLExportError.invalidCoordinates(place.name)
            }
            return place
        }

        let placemarks = selected.map { place in
            """
                <Placemark>
                  <name>\(xmlText(place.name))</name>
                  <address>\(xmlText(place.address))</address>
                  <Point><coordinates>\(place.longitude),\(place.latitude),0</coordinates></Point>
                </Placemark>
            """
        }.joined(separator: "\n")
        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
        \(placemarks)
          </Document>
        </kml>
        """
        guard let data = document.data(using: .utf8), !data.isEmpty else {
            throw TripKMLExportError.invalidDocument
        }
        return data
    }

    private static func xmlText(_ value: String) -> String {
        var cleaned = ""
        for scalar in value.unicodeScalars where isValidXMLScalar(scalar.value) {
            cleaned += String(scalar)
        }
        return cleaned
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func isValidXMLScalar(_ value: UInt32) -> Bool {
        value == 0x9 || value == 0xA || value == 0xD ||
            (0x20...0xD7FF).contains(value) ||
            (0xE000...0xFFFD).contains(value) ||
            (0x10000...0x10FFFF).contains(value)
    }
}
