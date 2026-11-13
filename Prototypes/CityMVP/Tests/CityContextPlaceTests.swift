import XCTest
import Foundation
import CryptoKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityContextPlaceTests: XCTestCase {
    private var node: [String: Any] {
        ["type": "node", "id": 42, "originalName": "同名咖啡", "latitude": 25.033968,
         "longitude": 121.564468, "category": "cafe", "positionKind": "sourceNode"]
    }

    private func data(_ records: [[String: Any]], version: Int = 1,
                      date: String = "2026-11-11") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": version, "sourceDate": date, "records": records])
    }

    func testSameNameBranchesAndDifferentObjectTypesRetainIdentity() throws {
        var branch = node; branch["id"] = 43
        var building = node; building["type"] = "way"; building["positionKind"] = "meanFootprintVertices"
        let dataset = try XCTUnwrap(CityContextPlace.decode(data([node, branch, building])))
        XCTAssertEqual(dataset.records.map(\.id), ["node/42", "node/43", "way/42"])
        XCTAssertEqual(Set(dataset.records.map(\.originalName)).count, 1)
        XCTAssertEqual(dataset.records[0].sourceURL.absoluteString, "https://www.openstreetmap.org/node/42")
        XCTAssertEqual(dataset.records[2].sourceURL.absoluteString, "https://www.openstreetmap.org/way/42")
    }

    func testOriginalEnglishOnlyAndMissingEnglishFallback() throws {
        var english = node; english["id"] = 43; english["englishName"] = "Actual source name"
        var empty = node; empty["id"] = 44; empty["englishName"] = "   "
        let records = try XCTUnwrap(CityContextPlace.decode(data([node, english, empty]))).records
        XCTAssertNil(records[0].englishName)
        XCTAssertEqual(records.map(\.title), ["同名咖啡", "Actual source name", "同名咖啡"])
        XCTAssertEqual(records[1].originalName, "同名咖啡")
        XCTAssertEqual(records[0].category, .cafe)
        XCTAssertEqual(records[0].symbol, "cup.and.saucer.fill")
        var suppliedURL = node; suppliedURL["sourceURL"] = "https://untrusted.invalid/not-osm"
        XCTAssertEqual(try XCTUnwrap(CityContextPlace.decode(data([suppliedURL]))).records[0].sourceURL.host,
                       "www.openstreetmap.org", "Source URL is computed from identity, never accepted from input")
    }

    func testMalformedIdentitySchemaEnumsAndPositionFailClosed() throws {
        XCTAssertNil(CityContextPlace.decode(try data([node, node])))
        XCTAssertNil(CityContextPlace.decode(try data([node], version: 2)))
        XCTAssertNil(CityContextPlace.decode(try data([node], date: "2026-02-30")))
        XCTAssertNil(CityContextPlace.decode(try data([])))
        XCTAssertNil(CityContextPlace.decode(Data("{broken".utf8)))
        for (key, value) in [("type", "relation"), ("category", "unknown"),
                             ("positionKind", "centroid"), ("positionKind", "meanFootprintVertices")] {
            var invalid = node; invalid["id"] = 43; invalid[key] = value
            XCTAssertNil(CityContextPlace.decode(try data([node, invalid])), key)
        }
        for value in [0, -1, 1.5, "42"] as [Any] {
            var invalid = node; invalid["id"] = value
            XCTAssertNil(CityContextPlace.decode(try data([invalid])))
        }
        var missing = node; missing.removeValue(forKey: "originalName")
        XCTAssertNil(CityContextPlace.decode(try data([missing])))
    }

    func testCoordinateBoundsNonfiniteTextAndResourceCapsFailClosed() throws {
        for (key, value) in [("latitude", 91.0), ("longitude", 181.0),
                             ("latitude", 25.033968 + 1501.0 / 111195),
                             ("longitude", 121.564468 - 1501.0 / 100850)] {
            var invalid = node; invalid[key] = value
            XCTAssertNil(CityContextPlace.decode(try data([invalid])), key)
        }
        let json = String(decoding: try data([node]), as: UTF8.self)
        for nonfinite in ["1e999", "NaN", "Infinity"] {
            let invalid = json.replacingOccurrences(of: "25.033968", with: nonfinite)
            XCTAssertNil(CityContextPlace.decode(Data(invalid.utf8)))
        }
        for bad in ["", "   ", "name\nwith control", String(repeating: "店", count: 181)] {
            var invalid = node; invalid["originalName"] = bad
            XCTAssertNil(CityContextPlace.decode(try data([invalid])))
        }
        var longEnglish = node; longEnglish["englishName"] = String(repeating: "a", count: 181)
        XCTAssertNil(CityContextPlace.decode(try data([longEnglish])))
        var maximumText = node; maximumText["originalName"] = String(repeating: "店", count: 180)
        XCTAssertNotNil(CityContextPlace.decode(try data([maximumText])))
        let tooMany = (1...5001).map { id in var value = node; value["id"] = id; return value }
        XCTAssertNil(CityContextPlace.decode(try data(tooMany)))
        XCTAssertNil(CityContextPlace.decode(Data(repeating: 32, count: CityContextPlace.maximumBytes + 1)))
    }

    func testBundledCatalogueRetainsSourceNamesIdentityAndProvenance() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "taipei-context-labels", withExtension: "json"))
        let bytes = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(bytes.count, CityContextPlace.maximumBytes)
        let dataset = try XCTUnwrap(CityContextPlace.decode(bytes))
        XCTAssertEqual(dataset, CityContextPlace.catalogue)
        XCTAssertEqual(dataset.schemaVersion, 1); XCTAssertEqual(dataset.sourceDate, "2026-11-11")
        XCTAssertEqual(dataset.records.count, 4070)
        XCTAssertEqual(dataset.records.filter { $0.type == .node }.count, 3507)
        XCTAssertEqual(dataset.records.filter { $0.type == .way }.count, 563)
        XCTAssertEqual(dataset.records.filter { $0.englishName != nil }.count, 1325)
        XCTAssertEqual(Set(dataset.records.map(\.id)).count, 4070)
        let station = try XCTUnwrap(dataset.records.first { $0.id == "node/253385544" })
        XCTAssertEqual(station.originalName, "市政府"); XCTAssertEqual(station.englishName, "Taipei City Hall")
        XCTAssertEqual(station.latitude, 25.0412081); XCTAssertEqual(station.longitude, 121.5661055)
        XCTAssertEqual(station.positionKind, .sourceNode); XCTAssertEqual(station.category, .transit)
        let hospital = try XCTUnwrap(dataset.records.first { $0.id == "way/111507105" })
        XCTAssertEqual(hospital.originalName, "國泰綜合醫院"); XCTAssertNil(hospital.englishName)
        XCTAssertEqual(hospital.title, hospital.originalName)
        XCTAssertEqual(hospital.positionKind, .meanFootprintVertices)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, "a0f1c35e116a9ae2e58101c29a611de2912711a34ead217cf12a7a8a46b04ae6",
                       "Frozen derivative verified against all 42 original source hashes; no generated names")
        let provenanceURL = try XCTUnwrap(Bundle.main.url(forResource: "ContextLabelProvenance", withExtension: "txt"))
        let provenance = try String(contentsOf: provenanceURL, encoding: .utf8)
        XCTAssertTrue(provenance.contains("ODbL 1.0")); XCTAssertTrue(provenance.contains(hash))
        XCTAssertEqual(provenance.components(separatedBy: "\n").filter { $0.hasPrefix("north/tile-") && !$0.contains("->") }.count, 12)
        XCTAssertEqual(provenance.components(separatedBy: "\n").filter { $0.hasPrefix("south/tile-") && !$0.contains("->") }.count, 30)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let records = try XCTUnwrap(json["records"] as? [[String: Any]])
        let allowed = Set(["type", "id", "originalName", "englishName", "latitude", "longitude", "category", "positionKind"])
        XCTAssertTrue(records.allSatisfy { Set($0.keys).isSubset(of: allowed) }, "No address/contact/photo/user fields")
    }
}
