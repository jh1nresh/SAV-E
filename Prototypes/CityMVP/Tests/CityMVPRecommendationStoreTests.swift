import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPRecommendationStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recommendation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func place() -> Place {
        Place(id: UUID(), name: "原店名", address: "台北市測試路1號", latitude: 25.034, longitude: 121.564,
            category: .cafe, status: .wantToGo, note: "PRIVATE-NOTE",
            sourceUrl: "https://example.com/venue", sourcePlatform: .other, createdAt: date)
    }

    private func snapshot(_ source: Place, reason: String = "Shared recommendation") throws -> CityMVPFriendExchange.Snapshot {
        try CityMVPFriendExchange.makeSnapshot(places: [source], selectedIDs: [source.id],
            senderLabel: "Declared sender", recommendationReason: reason, now: date)
    }

    func testTwoSourcesReplayAndReloadPreserveFirstReceipt() throws {
        let folder = try directory(), source = place()
        let store = CityMVPRecommendationStore(documentsDirectory: folder)
        let first = try snapshot(source, reason: "Quiet coffee\nWindow seats"), second = try snapshot(source, reason: "Another reason")
        XCTAssertTrue(store.records.isEmpty, "Constructing a source or store never saves context")
        try store.remember(snapshot: first, venueID: first.venues[0].id, savedPlaceID: source.id, receivedAt: date)
        let bytes = try Data(contentsOf: XCTUnwrap(store.fileURL))
        try store.remember(snapshot: first, venueID: first.venues[0].id, savedPlaceID: source.id, receivedAt: date.addingTimeInterval(60))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.fileURL)), bytes)
        try store.remember(snapshot: second, venueID: second.venues[0].id, savedPlaceID: source.id, receivedAt: date)
        XCTAssertEqual(store.recommendations(for: source).count, 2)
        XCTAssertEqual(store.records.first?.receivedAt, date)
        XCTAssertFalse(try XCTUnwrap(store.records.first).authenticatedSender)
        XCTAssertEqual(CityMVPRecommendationStore(documentsDirectory: folder).records, store.records)
    }

    func testSameVenueChangedSourceVersionCoexistsAndIdentityUsesSavedID() throws {
        let store = CityMVPRecommendationStore(documentsDirectory: try directory()), source = place()
        let first = try snapshot(source)
        let edited = CityMVPFriendExchange.Snapshot(version: 1, senderLabel: first.senderLabel,
            recommendationReason: "Changed explicit reason", sharedAt: first.sharedAt, venues: first.venues)
        let otherID = UUID()
        for (value, id) in [(first, source.id), (edited, source.id), (first, otherID)] {
            try store.remember(snapshot: value, venueID: first.venues[0].id, savedPlaceID: id)
        }
        XCTAssertEqual(Set(store.records.map(\.id)).count, 3)
        var alias = place(); alias.mergedPlaceIDs = [source.id]
        XCTAssertEqual(store.recommendations(for: alias).count, 2)
        XCTAssertTrue(store.recommendations(for: place()).isEmpty, "Same name/address is not identity")
        try store.forget(recordID: store.records[0].id)
        XCTAssertEqual(store.records.count, 2)
    }

    func testSidecarAllowlistDoesNotChangePlaceOrVenueOnlyMCPExport() throws {
        let store = CityMVPRecommendationStore(documentsDirectory: try directory()), source = place()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(source)
        let exportBefore = CityMVPGuideExport.encode(CityMVPGuideBrief(place: source), exportedAt: date)
        let value = try snapshot(source, reason: "UNSIGNED-REASON")
        try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: source.id)
        let bytes = try Data(contentsOf: XCTUnwrap(store.fileURL))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let row = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(row.keys), ["id", "savedPlaceID", "senderLabel", "reason", "sharedAt", "receivedAt", "sourceURL"])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("PRIVATE-NOTE"))
        XCTAssertEqual(try encoder.encode(source), before)
        XCTAssertNotNil(exportBefore)
        XCTAssertEqual(CityMVPGuideExport.encode(CityMVPGuideBrief(place: source), exportedAt: date), exportBefore)
        XCTAssertFalse(String(decoding: try XCTUnwrap(exportBefore), as: UTF8.self).contains("UNSIGNED-REASON"))
    }

    func testInvalidVenueAndNonfiniteDateNeverWrite() throws {
        let store = CityMVPRecommendationStore(documentsDirectory: try directory()), source = place()
        let value = try snapshot(source)
        XCTAssertThrowsError(try store.remember(snapshot: value, venueID: UUID(), savedPlaceID: source.id))
        XCTAssertThrowsError(try store.remember(snapshot: value, venueID: value.venues[0].id,
            savedPlaceID: source.id, receivedAt: Date(timeIntervalSince1970: .infinity)))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.fileURL).path))
    }

    func testCorruptUnknownVersionAndOversizedFilesArePreserved() throws {
        for bytes in [Data("broken".utf8), Data("{\"version\":2,\"records\":[]}".utf8),
                      Data(repeating: 32, count: CityMVPRecommendationStore.maximumBytes + 1)] {
            let folder = try directory()
            let url = try XCTUnwrap(CityMVPRecommendationStore(documentsDirectory: folder).fileURL)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
            let store = CityMVPRecommendationStore(documentsDirectory: folder), source = place()
            let value = try snapshot(source)
            XCTAssertNotNil(store.failure)
            XCTAssertThrowsError(try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: source.id))
            XCTAssertThrowsError(try store.forget(recordID: "anything"))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertTrue(store.records.isEmpty)
        }
    }

    func testRecordAndEncodedByteBoundsPreserveExistingFile() throws {
        for largeText in [false, true] {
            let folder = try directory(), source = place()
            let store = CityMVPRecommendationStore(documentsDirectory: folder)
            let value = try snapshot(source, reason: largeText ? String(repeating: "旅", count: 1_000) : "Reason")
            var hitBound = false
            for _ in 0...CityMVPRecommendationStore.maximumRecords {
                let previous = store.records
                let before = try store.fileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? try Data(contentsOf: $0) : nil }
                do { try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: UUID()) }
                catch {
                    XCTAssertEqual(error as? CityMVPRecommendationStore.Failure, .oversized)
                    XCTAssertEqual(store.records, previous)
                    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.fileURL)), before)
                    hitBound = true; break
                }
            }
            XCTAssertTrue(hitBound)
            if largeText { XCTAssertLessThan(store.records.count, 200) }
            else { XCTAssertEqual(store.records.count, 200) }
        }
    }

    func testWriteFailureDoesNotPublishAndRetrySucceeds() throws {
        let folder = try directory(), source = place()
        let store = CityMVPRecommendationStore(documentsDirectory: folder)
        let value = try snapshot(source)
        let blockingFile = folder.appendingPathComponent("SavvyCityMVP")
        try Data("blocked".utf8).write(to: blockingFile)
        XCTAssertThrowsError(try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: source.id))
        XCTAssertEqual(store.failure, .writeFailed); XCTAssertTrue(store.records.isEmpty)
        try FileManager.default.removeItem(at: blockingFile)
        try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: source.id)
        XCTAssertNil(store.failure); XCTAssertEqual(store.records.count, 1)
    }

    func testNamespaceCannotEscapeAndStorageIsExcludedFromBackup() throws {
        let folder = try directory()
        for id in ["../escape", "a/b", "", ".", String(repeating: "a", count: 101)] {
            let store = CityMVPRecommendationStore(documentsDirectory: folder, storageID: id)
            XCTAssertNil(store.fileURL); XCTAssertEqual(store.failure, .unavailable)
        }
        let store = CityMVPRecommendationStore(documentsDirectory: folder, storageID: "test_1")
        let source = place(), value = try snapshot(source)
        try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: source.id)
        let file = try XCTUnwrap(store.fileURL)
        XCTAssertTrue(file.path.hasSuffix("SavvyCityMVP/Recommendations/test-test_1/source-context-v1.json"))
        XCTAssertEqual(try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testActualCompleteFileProtectionRequiresAReportingRuntime() throws {
        let folder = try directory()
        let store = CityMVPRecommendationStore(documentsDirectory: folder)
        let source = place(), value = try snapshot(source)
        try store.remember(snapshot: value, venueID: value.venues[0].id, savedPlaceID: source.id)
        let file = try XCTUnwrap(store.fileURL)
        let attribute = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey]
#if targetEnvironment(simulator)
        if attribute == nil {
            throw XCTSkip("This simulator returned no file-protection attribute. Complete protection remains a real-device verification requirement.")
        }
#endif
        let protection = (attribute as? FileProtectionType)?.rawValue ?? (attribute as? String)
        XCTAssertEqual(protection, FileProtectionType.complete.rawValue,
                       "Foundation may bridge this attribute as NSString; the actual protection must still be complete")
    }
}
