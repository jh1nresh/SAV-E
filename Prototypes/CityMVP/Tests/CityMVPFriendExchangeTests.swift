import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPFriendExchangeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func place() -> Place {
        Place(id: UUID(), name: "原店名", address: "台北市信義路", latitude: 25.034, longitude: 121.564,
            category: .cafe, status: .visited, rating: 5, note: "PRIVATE-NOTE",
            sourceUrl: "https://example.com/venue", sourcePlatform: .other,
            sourceImageUrl: "https://example.com/PRIVATE-PHOTO", businessPhotoUrls: ["https://example.com/PRIVATE-BUSINESS"],
            recommender: "PRIVATE-AUTHOR", googleRating: 4.5, createdAt: now)
    }

    private func snapshot(_ places: [Place]? = nil) throws -> CityMVPFriendExchange.Snapshot {
        let items = places ?? [place()]
        return try CityMVPFriendExchange.makeSnapshot(places: items, selectedIDs: Set(items.map(\.id)),
            senderLabel: "Self-declared sender", recommendationReason: "I explicitly recommend this café.", now: now)
    }

    private func changed(_ data: Data, _ update: (inout [String: Any]) -> Void) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        update(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    func testExportIncludesOnlySelectedActualPlacesAndNoPrivateFields() throws {
        let selected = place()
        var excluded = place(); excluded.name = "UNSELECTED-PRIVATE-PLACE"
        let value = try CityMVPFriendExchange.makeSnapshot(places: [selected, excluded], selectedIDs: [selected.id],
            senderLabel: "Sender", recommendationReason: "New share-specific reason", now: now)
        XCTAssertEqual(value.venues.count, 1)
        XCTAssertEqual(value.venues[0].name, selected.name)
        XCTAssertNotEqual(value.venues[0].id, selected.id)
        let data = try CityMVPFriendExchange.encode(value)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(excluded.name))
        for privateText in ["PRIVATE-NOTE", "PRIVATE-PHOTO", "PRIVATE-BUSINESS", "PRIVATE-AUTHOR"] {
            XCTAssertFalse(text.contains(privateText))
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let row = try XCTUnwrap((root["venues"] as? [[String: Any]])?.first)
        for key in ["status", "rating", "note", "recommender", "photos", "businessPhotoUrls", "socialSignal"] {
            XCTAssertNil(row[key])
        }
        XCTAssertEqual(try CityMVPFriendExchange.decode(data), value)
        XCTAssertThrowsError(try CityMVPFriendExchange.makeSnapshot(places: [selected], selectedIDs: [excluded.id],
            senderLabel: "Sender", recommendationReason: "Reason", now: now))
        XCTAssertThrowsError(try CityMVPFriendExchange.makeSnapshot(places: [selected], selectedIDs: [],
            senderLabel: "Sender", recommendationReason: "Reason", now: now))
        var invalid = selected; invalid.latitude = .nan
        XCTAssertThrowsError(try snapshot([invalid]))
    }

    func testRecipientOwnsFreshWantToGoVenueWithoutSenderMemory() throws {
        let venue = try snapshot().venues[0]
        let first = CityMVPFriendExchange.recipientPlace(for: venue, now: now)
        let second = CityMVPFriendExchange.recipientPlace(for: venue, now: now)
        XCTAssertNotEqual(first.id, venue.id); XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.status, .wantToGo)
        XCTAssertEqual(first.name, venue.name); XCTAssertEqual(first.address, venue.address)
        XCTAssertEqual(first.latitude, venue.latitude); XCTAssertEqual(first.longitude, venue.longitude)
        XCTAssertNil(first.note); XCTAssertNil(first.rating); XCTAssertNil(first.googleRating)
        XCTAssertNil(first.recommender); XCTAssertNil(first.sourceImageUrl); XCTAssertNil(first.businessPhotoUrls)
        XCTAssertEqual(first.sourceUrl, venue.sourceURL)
        XCTAssertEqual(first.createdAt, now)
    }

    func testProviderCoordinatesArePreservedWithoutGuessingWGS84() throws {
        var source = place()
        source.coordinateSystem = .gcj02; source.locationProvider = .amap
        source.providerPlaceId = "AMAP-EXACT-ID"; source.providerMapUrl = "https://uri.amap.com/marker?name=原店名"
        source.googlePlaceId = "GOOGLE-EXACT-ID"
        let imported = try CityMVPFriendExchange.decode(CityMVPFriendExchange.encode(snapshot([source])))
        let actual = CityMVPFriendExchange.recipientPlace(for: imported.venues[0], now: now)
        XCTAssertEqual(actual.coordinateSystem, .gcj02); XCTAssertEqual(actual.locationProvider, .amap)
        XCTAssertEqual(actual.providerPlaceId, source.providerPlaceId)
        XCTAssertEqual(actual.providerMapUrl, source.providerMapUrl); XCTAssertEqual(actual.googlePlaceId, source.googlePlaceId)
        XCTAssertEqual(actual.latitude, source.latitude); XCTAssertEqual(actual.longitude, source.longitude)
        XCTAssertFalse(actual.isMapKitMappable)
    }

    func testMalformedUnknownAndOversizedInputFailsClosed() throws {
        let data = try CityMVPFriendExchange.encode(snapshot())
        for input in [Data(), Data("{broken".utf8), Data(repeating: 32, count: CityMVPFriendExchange.maximumBytes + 1)] {
            XCTAssertThrowsError(try CityMVPFriendExchange.decode(input))
        }
        for key in ["version", "senderLabel", "recommendationReason", "sharedAt", "venues"] {
            let missing = try changed(data) { $0.removeValue(forKey: key) }
            XCTAssertThrowsError(try CityMVPFriendExchange.decode(missing), key)
        }
        for (key, value) in [("version", 2), ("sharedAt", "not-a-date"), ("sharedAt", 0),
                             ("senderLabel", ""), ("recommendationReason", String(repeating: "a", count: 1_001)),
                             ("unexpectedPrivateNote", "secret")] as [(String, Any)] {
            XCTAssertThrowsError(try CityMVPFriendExchange.decode(changed(data) { $0[key] = value }), key)
        }
        let empty = try changed(data) { $0["venues"] = [] }
        XCTAssertThrowsError(try CityMVPFriendExchange.decode(empty))
        let tooMany = try changed(data) { root in
            let row = (root["venues"] as! [[String: Any]])[0]
            root["venues"] = (0...30).map { _ in var copy = row; copy["id"] = UUID().uuidString; return copy }
        }
        XCTAssertThrowsError(try CityMVPFriendExchange.decode(tooMany))
    }

    func testUnsafeURLsCoordinatesEnumsAndDuplicateIdentitiesAreRejected() throws {
        let data = try CityMVPFriendExchange.encode(snapshot())
        for (key, bad) in [("sourceURL", "javascript:alert(1)"), ("sourceURL", "http://example.com"),
                           ("providerMapURL", "file:///private"), ("sourceURL", "https://user:pass@example.com"),
                           ("sourceURL", "https://example.com?access_token=secret"), ("latitude", 91),
                           ("sourceURL", "https://example.com#access_token=secret"),
                           ("longitude", 181), ("name", "bad\nname"), ("category", "unknown"),
                           ("coordinateSystem", "guessed"), ("note", "private")] as [(String, Any)] {
            let badData = try changed(data) { root in
                var rows = root["venues"] as! [[String: Any]]; rows[0][key] = bad; root["venues"] = rows
            }
            XCTAssertThrowsError(try CityMVPFriendExchange.decode(badData), key)
        }
        let duplicate = try changed(data) { root in
            let rows = root["venues"] as! [[String: Any]]; root["venues"] = rows + rows
        }
        XCTAssertThrowsError(try CityMVPFriendExchange.decode(duplicate))
        for coordinateSystem in [nil, NSNull(), "wgs84"] as [Any?] {
            let invalidProvider = try changed(data) { root in
                var rows = root["venues"] as! [[String: Any]]
                rows[0]["locationProvider"] = "amap"
                rows[0]["coordinateSystem"] = coordinateSystem
                root["venues"] = rows
            }
            XCTAssertThrowsError(try CityMVPFriendExchange.decode(invalidProvider))
        }
        XCTAssertThrowsError(try CityMVPFriendExchange.read(from: URL(string: "https://example.com/file.json")!))
    }

    func testThirtySelectedPlacesAndBoundedFileReader() throws {
        let thirty = (0..<30).map { _ in place() }
        let data = try CityMVPFriendExchange.encode(snapshot(thirty))
        XCTAssertEqual(try CityMVPFriendExchange.decode(data).venues.count, 30)
        XCTAssertThrowsError(try snapshot(thirty + [place()]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("friend-exchange-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recommendations.json")
        try data.write(to: file)
        XCTAssertEqual(try CityMVPFriendExchange.read(from: file).venues.count, 30)
        try Data(repeating: 32, count: CityMVPFriendExchange.maximumBytes + 1).write(to: file)
        XCTAssertThrowsError(try CityMVPFriendExchange.read(from: file))
        XCTAssertThrowsError(try CityMVPFriendExchange.read(from: directory))
    }
}
