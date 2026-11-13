import XCTest
import Foundation
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPGuideBriefTests: XCTestCase {
    private func place() -> Place {
        var place = Place(id: UUID(uuidString: "2E3763F0-B020-4D0A-90A2-38A7353D66D4")!,
            name: "街角咖啡", address: "臺北市信義區松仁路7號", latitude: 25.033968, longitude: 121.564468,
            googlePlaceId: nil, category: .cafe, status: .wantToGo, rating: 4,
            note: "PRIVATE_NOTE_不公開", sourceUrl: "https://example.com/source", sourcePlatform: .instagram,
            sourceImageUrl: "https://example.com/PRIVATE_PHOTO", extractedDishes: ["PRIVATE_DISH"],
            priceRange: "PRIVATE_PRICE", recommender: "PRIVATE_PERSON", googleRating: 4.8,
            googlePriceLevel: nil, openingHours: "PRIVATE_HOURS", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        place.placeHighlights = ["來源說有窗邊座位"]
        place.additionalSourceEvidence = ["SOURCE_STATEMENT_店家貼文"]
        return place
    }

    func testOriginalChinesePrivateNoteAndSourceStatementsStaySeparate() {
        let original = place(), brief = CityMVPGuideBrief(place: original)
        XCTAssertEqual(brief.name, original.name); XCTAssertEqual(brief.address, original.address)
        XCTAssertEqual(brief.savedAt, original.createdAt)
        XCTAssertEqual(brief.privateNote, "PRIVATE_NOTE_不公開")
        XCTAssertTrue(brief.sourceStatements.contains("Highlight: 來源說有窗邊座位"))
        XCTAssertTrue(brief.sourceStatements.contains("SOURCE_STATEMENT_店家貼文"))
        XCTAssertFalse(brief.sourceStatements.contains { $0.contains("PRIVATE_NOTE") })
        XCTAssertEqual(original.note, "PRIVATE_NOTE_不公開", "Building a brief never changes user truth")
        XCTAssertFalse(brief.visited)
    }

    func testAbsentFieldsAndUnsafeCredentialURLsAreHonest() {
        var empty = place(); empty.address = ""; empty.note = "  "
        empty.placeHighlights = nil; empty.additionalSourceEvidence = nil; empty.sourceUrl = nil
        empty.recommendedItems = []; empty.extractedDishes = nil
        let brief = CityMVPGuideBrief(place: empty)
        XCTAssertFalse(brief.hasAddress); XCTAssertFalse(brief.hasStreetNumber)
        XCTAssertNil(brief.privateNote); XCTAssertNil(brief.sourceURL); XCTAssertNil(brief.driverCardText)
        XCTAssertTrue(brief.sourceStatements.isEmpty)
        for raw in ["http://example.com", "file:///tmp/private", "javascript:alert(1)",
                    "https://user:password@example.com", "https://user@example.com", "https://", "//example.com",
                    "https://example.com/a b", "https://example.com/\nsecret", "https://example.com/\u{0000}"] {
            XCTAssertNil(CityMVPGuideBrief.safeSourceURL(raw), raw)
        }
        XCTAssertEqual(CityMVPGuideBrief.safeSourceURL("https://example.com/source?q=place")?.scheme, "https")
    }

    func testAddressCardAndMapGuardDoNotInventAnEntranceOrVerifiedVisit() {
        var value = place(); value.address = "上海市靜安區愚園路"; value.coordinateSystem = .gcj02
        value.status = .visited
        let brief = CityMVPGuideBrief(place: value)
        XCTAssertFalse(brief.hasStreetNumber); XCTAssertFalse(brief.canShowOnMap); XCTAssertTrue(brief.visited)
        XCTAssertNil(brief.driverCardText)
        value.address += "123号"
        XCTAssertTrue(CityMVPGuideBrief(place: value).hasStreetNumber)
        XCTAssertEqual(CityMVPGuideBrief(place: value).driverCardText, "师傅，请带我去：\n上海市靜安區愚園路123号\n街角咖啡")
        value.address = "臺北市 信義區 松壽路 12"
        XCTAssertTrue(CityMVPGuideBrief(place: value).hasStreetNumber)
        XCTAssertNotNil(CityMVPGuideBrief(place: value).driverCardText)
        value.address = "人民廣場 3"
        XCTAssertFalse(CityMVPGuideBrief(place: value).hasStreetNumber)
        value.coordinateSystem = .wgs84; value.latitude = .nan
        XCTAssertFalse(CityMVPGuideBrief(place: value).canShowOnMap)
        XCTAssertTrue(CityMVPGuideBrief(place: place()).canShowOnMap)
    }

    func testExportExactAllowlistOneVenueISODateAndNoPrivateOrVisitFields() throws {
        var saved = place(); saved.status = .visited
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try XCTUnwrap(CityMVPGuideExport.encode(.init(place: saved), exportedAt: date))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "guide-export-contract"; attachment.lifetime = .keepAlways; add(attachment)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["format", "version", "exportedAt", "places"]))
        XCTAssertEqual(json["format"] as? String, "savvy-guide"); XCTAssertEqual(json["version"] as? Int, 1)
        let records = try XCTUnwrap(json["places"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        let row = try XCTUnwrap(records.first)
        XCTAssertEqual(Set(row.keys), Set(["id", "name", "address", "category", "state", "savedAt", "sourceURL"]))
        XCTAssertEqual(row["id"] as? String, saved.id.uuidString)
        XCTAssertEqual(row["name"] as? String, "街角咖啡"); XCTAssertEqual(row["address"] as? String, saved.address)
        XCTAssertEqual(row["state"] as? String, "confirmed", "Saved confirmation does not export verified arrival")
        XCTAssertEqual(row["category"] as? String, PlaceCategory.cafe.rawValue)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(formatter.date(from: try XCTUnwrap(json["exportedAt"] as? String)), date)
        XCTAssertEqual(formatter.date(from: try XCTUnwrap(row["savedAt"] as? String)), saved.createdAt)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["PRIVATE_", "SOURCE_STATEMENT", "來源說有窗邊座位", "visited", "verified", "latitude", "longitude"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        let decoded = try JSONDecoder().decode(CityMVPGuideExport.self, from: data)
        XCTAssertEqual(decoded.places.count, 1)
        XCTAssertLessThanOrEqual(data.count, CityMVPGuideExport.maximumBytes)
    }

    func testExportOmitsMissingAndUnsafeSourcesAndRejectsOversize() throws {
        for control in ["\u{0000}", "\r"] {
            var invalid = place(); invalid.name += control
            XCTAssertNil(CityMVPGuideExport.encode(.init(place: invalid)))
            invalid = place(); invalid.address += control
            XCTAssertNil(CityMVPGuideExport.encode(.init(place: invalid)))
        }
        for url in [nil, "https://private:secret@example.com"] as [String?] {
            var saved = place(); saved.sourceUrl = url
            let data = try XCTUnwrap(CityMVPGuideExport.encode(.init(place: saved)))
            let decoded = try JSONDecoder().decode(CityMVPGuideExport.self, from: data)
            XCTAssertNil(decoded.places[0].sourceURL)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("sourceURL"))
        }
        var huge = place(); huge.name = String(repeating: "名", count: CityMVPGuideExport.maximumBytes)
        XCTAssertNil(CityMVPGuideExport.encode(.init(place: huge)))
        var invalid = place(); invalid.createdAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertNil(CityMVPGuideExport.encode(.init(place: invalid)))
    }
}
