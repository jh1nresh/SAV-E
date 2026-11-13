import Foundation
import XCTest
@testable import SAVE

@MainActor
final class SavvyMainIntegrationTests: XCTestCase {
    func testMainTargetKeepsItsAppGroupAndProductionConfigurationReader() {
        XCTAssertEqual(SAVEProductionConfig.appGroupSuiteName, "group.com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.defaultAPIBaseURL, "https://save-backend-production.up.railway.app")
        let key = "SAVE_MAIN_NONSECRET_CONFIGURATION_TEST"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, "synthetic-value", 1)
        defer {
            if let previous { setenv(key, previous, 1) } else { unsetenv(key) }
        }
        XCTAssertEqual(SAVEProductionConfig.configValue(for: [key]), "synthetic-value")
        if !ProcessInfo.processInfo.arguments.contains("--uitest-review-demo-offline") {
            XCTAssertFalse(ReviewDemo.isOfflineUITestMode, "The map feature flag must not force the main app into offline demo auth")
        }
    }

    func testStaleSessionCannotWritePrivateDraftOrCopiedRecommendation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var current = true
        let draft = CityMVPCaptureDraftStore(documentsDirectory: root, isCurrentSession: { current })
        XCTAssertTrue(draft.update("Original private clue"))
        let before = try Data(contentsOf: XCTUnwrap(draft.fileURL))
        let store = CityMVPRecommendationStore(documentsDirectory: root, isCurrentSession: { current })
        let place = Place(id: UUID(), name: "Fixture", address: "1 Test Road", latitude: 25.034,
            longitude: 121.564, category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        let snapshot = try CityMVPFriendExchange.makeSnapshot(places: [place], selectedIDs: [place.id],
            senderLabel: "Declared source", recommendationReason: "Shared explicitly")
        current = false
        XCTAssertFalse(draft.update("Late write after account switch"))
        XCTAssertEqual(draft.text, "Original private clue")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(draft.fileURL)), before)
        XCTAssertThrowsError(try store.remember(snapshot: snapshot, venueID: place.id, savedPlaceID: place.id))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.fileURL).path))
    }

    func testStaleRootSelectionIsRejectedBeforeAnyLocalVenueSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        let auth = PrivyAuthService.shared
        let place = Place(id: UUID(), name: "Old selection", address: "1 Test Road", latitude: 25.034,
            longitude: 121.564, category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        do {
            _ = try await vm.confirmFriendRecommendationPlace(place, expectedOwner: auth.currentUserId,
                expectedGeneration: auth.sessionGeneration - 1)
            XCTFail("A stale root cannot save any further venue")
        } catch is CancellationError { }
        XCTAssertTrue(vm.places.isEmpty)
        XCTAssertTrue(try vault.confirmedPlaces().isEmpty)
    }
}
