import XCTest
@testable import SAVE

final class SaveLocalVaultServiceTests: XCTestCase {
    @MainActor
    func testConfirmedPlaceSaveUpsertsMatchingVenueInsteadOfAppendingDuplicate() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("save-memory-records.json")
        let service = SaveLocalVaultService(overrideVaultURL: vaultURL)

        let first = makePlace(
            id: UUID(),
            name: "隱室無名滷肉飯 中山店",
            address: "103, Taiwan, Taipei City, Datong District",
            googlePlaceId: "ChIJ-sav-e-test"
        )
        let resaved = makePlace(
            id: UUID(),
            name: "隱室無名滷肉飯 中山店",
            address: "103, Taiwan, Taipei City, Datong District, Lane 33",
            googlePlaceId: "ChIJ-sav-e-test"
        )

        _ = try service.saveConfirmedPlace(first)
        _ = try service.saveConfirmedPlace(resaved)

        let places = try service.confirmedPlaces(limit: 10)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.address, resaved.address)
    }

    @MainActor
    func testRepeatedSavePreservesBothSourcesAndOldTripIDAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let service = SaveLocalVaultService(overrideVaultURL: url)
        var first = makePlace(id: UUID(), name: "Cafe", address: "Taipei", googlePlaceId: "venue")
        first.sourceUrl = "https://example.com/first"
        first.note = "From a friend"
        var second = makePlace(id: UUID(), name: "Cafe", address: "Taipei", googlePlaceId: "venue")
        second.sourceUrl = "https://example.com/second"
        second.note = "From a guide"
        _ = try service.saveConfirmedPlace(first)
        _ = try service.saveConfirmedPlace(second)
        let reloaded = try SaveLocalVaultService(overrideVaultURL: url).confirmedPlaces()
        XCTAssertEqual(reloaded.count, 1)
        let merged = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(merged.savedIDs, [first.id, second.id])
        XCTAssertTrue(merged.sourceEvidence.contains("Source URL: https://example.com/first"))
        XCTAssertTrue(merged.sourceEvidence.contains("Source URL: https://example.com/second"))
        XCTAssertTrue(merged.sourceEvidence.contains("From a friend"))
        XCTAssertTrue(merged.sourceEvidence.contains("From a guide"))
    }

    @MainActor
    func testMissingVaultReadsAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
        )

        XCTAssertTrue(try service.recentRecords().isEmpty)
    }

    @MainActor
    func testConfirmedPlaceKeepsCanonicalIdentityAndRemovalClearsProjection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
        )
        let place = makePlace(id: UUID(), name: "Memory Cafe", address: "1 Test Way", googlePlaceId: nil)

        _ = try service.saveConfirmedPlace(place)
        XCTAssertEqual(try service.confirmedPlaces().first?.id, place.id)

        try service.removeConfirmedPlace(place)
        XCTAssertTrue(try service.confirmedPlaces().isEmpty)
    }

    @MainActor
    func testDeleteAllRecordsClearsEveryLocalMemoryState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
        )

        _ = try service.saveSourceOnly(url: URL(string: "https://example.com/place")!)
        _ = try service.saveConfirmedPlace(
            makePlace(id: UUID(), name: "Memory Cafe", address: "1 Test Way", googlePlaceId: nil)
        )

        try service.deleteAllRecords()

        XCTAssertTrue(try service.recentRecords().isEmpty)
        XCTAssertTrue(try service.confirmedPlaces().isEmpty)
        XCTAssertTrue(try service.reviewCandidates().isEmpty)
    }

    @MainActor
    private func makePlace(
        id: UUID,
        name: String,
        address: String,
        googlePlaceId: String?
    ) -> Place {
        Place(
            id: id,
            name: name,
            address: address,
            latitude: 25.051,
            longitude: 121.519,
            googlePlaceId: googlePlaceId,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: "https://instagram.com/p/save-test",
            sourcePlatform: .instagram,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}
