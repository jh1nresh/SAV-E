import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPFriendConfirmationTests: XCTestCase {
    func testActualExistingSaveIDOwnsCopiedRecommendationWithoutChangingPrivateNote() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        var existing = place(); existing.note = "recipient private memory"
        try vault.saveConfirmedPlace(existing); vm.places = [existing]
        let snapshot = try CityMVPFriendExchange.makeSnapshot(places: [existing], selectedIDs: [existing.id],
            senderLabel: "Declared sender", recommendationReason: "Quiet coffee\nI recommend the window seats.")
        let venue = try XCTUnwrap(snapshot.venues.first)
        let incoming = CityMVPFriendExchange.recipientPlace(for: venue)
        XCTAssertNotEqual(incoming.id, existing.id)
        let store = CityMVPRecommendationStore(documentsDirectory: root)
        let outcome = try await CityMVPFriendConfirmation.confirm(place: incoming, snapshot: snapshot,
            venueID: venue.id, recommendations: store) { try vm.confirmCityMVPFriendPlace($0) }
        XCTAssertEqual(outcome.savedPlace.id, existing.id); XCTAssertTrue(outcome.recommendationKept)
        XCTAssertEqual(store.recommendations(for: existing).count, 1)
        XCTAssertTrue(store.recommendations(for: incoming).isEmpty, "Do not attach context to a discarded incoming UUID")
        XCTAssertEqual(vm.places.count, 1); XCTAssertEqual(vm.places[0].note, "recipient private memory")
        let reloaded = CityMVPRecommendationStore(documentsDirectory: root)
        XCTAssertEqual(reloaded.recommendations(for: existing).first?.reason, snapshot.recommendationReason)
    }

    func testContextWriteFailureKeepsRealSaveAndRetryCannotSaveAnotherPlace() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("context")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let blocker = documents.appendingPathComponent("SavvyCityMVP")
        try Data("owned test obstruction".utf8).write(to: blocker)
        let store = CityMVPRecommendationStore(documentsDirectory: documents)
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        let source = place()
        let snapshot = try CityMVPFriendExchange.makeSnapshot(places: [source], selectedIDs: [source.id],
            senderLabel: "Declared sender", recommendationReason: "Explicit recommendation")
        let venue = try XCTUnwrap(snapshot.venues.first)
        let incoming = CityMVPFriendExchange.recipientPlace(for: venue)
        var saveCalls = 0
        let outcome = try await CityMVPFriendConfirmation.confirm(place: incoming, snapshot: snapshot,
            venueID: venue.id, recommendations: store) {
                saveCalls += 1
                return try vm.confirmCityMVPFriendPlace($0)
            }
        XCTAssertFalse(outcome.recommendationKept); XCTAssertEqual(saveCalls, 1)
        XCTAssertEqual(try vault.confirmedPlaces().count, 1); XCTAssertTrue(store.records.isEmpty)
        try FileManager.default.removeItem(at: blocker)
        for _ in 0..<2 {
            try CityMVPFriendConfirmation.retryRecommendation(snapshot: snapshot, venueID: venue.id,
                savedPlaceID: outcome.savedPlace.id, recommendations: store)
        }
        XCTAssertEqual(saveCalls, 1); XCTAssertEqual(vm.places.count, 1)
        XCTAssertEqual(store.records.count, 1); XCTAssertEqual(store.records.first?.savedPlaceID, outcome.savedPlace.id)
    }

    func testCanceledOrFailedVenueConfirmationNeverKeepsItsRecommendation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = place(), store = CityMVPRecommendationStore(documentsDirectory: root)
        let snapshot = try CityMVPFriendExchange.makeSnapshot(places: [source], selectedIDs: [source.id],
            senderLabel: "Declared sender", recommendationReason: "Explicit recommendation")
        do {
            _ = try await CityMVPFriendConfirmation.confirm(place: source, snapshot: snapshot,
                venueID: try XCTUnwrap(snapshot.venues.first?.id), recommendations: store) { _ in throw CancellationError() }
            XCTFail("Canceled saves must not report success")
        } catch is CancellationError { }
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.fileURL).path))
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("friend-outcome-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func place() -> Place {
        Place(id: UUID(), name: "Fixture cafe", address: "1 Test Road", latitude: 25.034,
              longitude: 121.564, category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
    }
}
