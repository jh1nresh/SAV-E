import XCTest
import MapKit
import SwiftUI
@testable import SavvyCityMVP

@MainActor
final class CityMVPTests: XCTestCase {
    func testStreetlifeTrafficUsesSeparateLanesThroughBothIntersections() {
        let lanes = CityStreetTraffic.lanes(from: CityStreetSurface.roads())
        XCTAssertEqual(lanes.count, 2)
        guard lanes.count == 2 else { return }
        XCTAssertLessThan(lanes[0].position(at: 0).point.x, -250)
        XCTAssertGreaterThan(lanes[0].position(at: lanes[0].length).point.x, 280)
        XCTAssertGreaterThan(lanes[1].position(at: 0).point.x, 280)
        XCTAssertLessThan(lanes[1].position(at: lanes[1].length).point.x, -250)

        // The two fixture intersections are around x = −100 and +96, with
        // physically separate north and south Xinyi Road carriageways.
        for (x, north, south) in [(-100.0, 104.0, 122.0), (96, 109, 128)] {
            for (lane, z) in [(lanes[0], south), (lanes[1], north)] {
                let samples = stride(from: CGFloat.zero, through: lane.length, by: 1).map { lane.position(at: $0).point }
                let crossing = samples.min { abs($0.x - x) < abs($1.x - x) }
                XCTAssertLessThan(abs((crossing?.x ?? 0) - x), 1)
                XCTAssertEqual(crossing?.y ?? 0, z, accuracy: 2)
            }
        }
    }

    func testExplicitConfirmationPersistsAcrossFreshStoresWithoutSavingOtherContext() async throws {
        let namespace = "city-mvp-test-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(namespace)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: namespace))
        defer {
            defaults.removePersistentDomain(forName: namespace)
            try? FileManager.default.removeItem(at: directory)
        }
        let vaultURL = directory.appendingPathComponent("vault.json")
        func model() -> MapViewModel {
            MapViewModel(
                mapCandidatePlaceSaver: { _, _ in XCTFail("Local test must not invoke remote save") },
                mapCandidateUserIDProvider: { nil },
                pendingImportService: PendingPlaceImportService(overrideContainerURL: directory),
                mapCandidateDistanceLocationProvider: { nil },
                saveLocalVaultService: SaveLocalVaultService(overrideVaultURL: vaultURL),
                correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("corrections.json")),
                collaborativeListStore: SaveCollaborativeListStore(defaults: defaults),
                referralHandoffStore: SaveReferralHandoffStore(defaults: defaults),
                usesRemotePersistence: false
            )
        }
        let context = [scene("way/1"), scene("way/2")]
        let first = model()
        let candidate = CityMVPPlaceBridge.candidate(for: context[0])
        first.selectedMapCandidate = candidate
        first.selectedMapCandidate = nil
        XCTAssertTrue(try SaveLocalVaultService(overrideVaultURL: vaultURL).confirmedPlaces().isEmpty)
        XCTAssertTrue(first.places.isEmpty)

        let saved = try await first.saveMapCandidateAsPlace(candidate)
        XCTAssertEqual(try SaveLocalVaultService(overrideVaultURL: vaultURL).confirmedPlaces().count, 1)
        let restarted = model()
        await restarted.loadPlaces(force: true)
        XCTAssertEqual(restarted.places.map(\.id), [saved.id])
        XCTAssertEqual(restarted.places.first?.sourceUrl, candidate.sourceURL)
        let rendered = CityMVPPlaceBridge.places(context: context, saved: restarted.places)
        XCTAssertEqual(rendered.map(\.isSaved), [true, false])
    }

    func testProviderOffsetKeepsDistrictEdgeAndProjectionInTheSameSpace() throws {
        let registration = try XCTUnwrap(CityDistrictRegistration.fromLandmark(
            .init(latitude: 25.030941, longitude: 121.568341)
        ))
        let coordinate = registration.mapCoordinate(CityDistrictCamera.coordinate(x: 520, z: 0))
        let camera = MapCamera(centerCoordinate: coordinate, distance: 1_450, heading: 0, pitch: 0)
        let frame = CityDistrictCamera(camera: camera, registration: registration) { native in
            let world = CityDistrictCamera.world(registration.sceneCoordinate(native))
            return CGPoint(x: 195 + (world.x - 520) / 3, y: 378 + world.z / 3)
        }
        XCTAssertTrue(frame.shouldPrewarm)
        XCTAssertGreaterThan(frame.opacity, 0.6)
        XCTAssertLessThan(try XCTUnwrap(frame.projection).error, 0.01)

        let unregistered = CityDistrictCamera(camera: camera, registration: nil) { _ in .zero }
        XCTAssertFalse(unregistered.shouldPrewarm)
        XCTAssertEqual(unregistered.opacity, 0)
        XCTAssertNil(unregistered.projection)
        XCTAssertNil(CityDistrictRegistration.fromLandmark(.init(latitude: 31.23, longitude: 121.47)))
    }

    func testAmapConfigurationNeverClaimsConnection() {
        XCTAssertEqual(CityMVPConfiguration.amapStatus(values: nil, bundleID: "local.savvy.city-mvp"), .missingKey)
        XCTAssertEqual(CityMVPConfiguration.amapStatus(values: ["APIKey": "  "], bundleID: "local.savvy.city-mvp"), .missingKey)
        XCTAssertEqual(CityMVPConfiguration.amapStatus(values: ["APIKey": "test", "BundleIdentifier": "com.wanderly.app"], bundleID: "local.savvy.city-mvp"), .bundleMismatch)
        XCTAssertEqual(CityMVPConfiguration.amapStatus(values: ["APIKey": "test", "BundleIdentifier": "local.savvy.city-mvp"], bundleID: "local.savvy.city-mvp"), .sdkNotConnected)
    }
    func testContextDoesNotBecomeSavedAndSameNameBranchesStayDistinct() {
        let context = [scene("way/1"), scene("way/2")]
        XCTAssertTrue(CityMVPPlaceBridge.places(context: context, saved: []).allSatisfy { !$0.isSaved })
        let saved = place(source: CityMVPPlaceBridge.sourceURL(for: context[0]))
        let rendered = CityMVPPlaceBridge.places(context: context, saved: [saved])
        XCTAssertEqual(rendered.map(\.id), ["way/1", "way/2"])
        XCTAssertTrue(rendered[0].isSaved)
        XCTAssertFalse(rendered[1].isSaved)
        XCTAssertEqual(CityMVPPlaceBridge.savedMatch(for: rendered[0], in: [saved])?.id, saved.id)
    }
    func testGCJ02AndOutsideTilePlacesAreNotPlottedInTaipeiScene() {
        var wrongSystem = place(source: "https://www.openstreetmap.org/way/1")
        wrongSystem.coordinateSystem = .gcj02
        var outside = place(source: nil)
        outside.latitude = 31.23; outside.longitude = 121.47
        XCTAssertFalse(CityMVPPlaceBridge.inScene(wrongSystem))
        XCTAssertFalse(CityMVPPlaceBridge.inScene(outside))
        XCTAssertTrue(CityMVPPlaceBridge.places(context: [], saved: [wrongSystem, outside]).isEmpty)
    }
    func testLocalBuildCannotUseProductionConfig() {
        XCTAssertTrue(ReviewDemo.isOfflineUITestMode)
        XCTAssertEqual(ReviewDemo.uiTestStorageIdentifier, "city-mvp-local")
        XCTAssertEqual(SAVEProductionConfig.defaultAPIBaseURL, "http://127.0.0.1:9")
        XCTAssertNotEqual(SAVEProductionConfig.appGroupSuiteName, "group.com.wanderly.app")
        XCTAssertNil(SAVEProductionConfig.configValue(for: ["PRIVY_APP_ID", "GOOGLE_PLACES_API_KEY"]))
    }
    func testBundledSceneHasUniqueUnsavedFinitePlaces() {
        XCTAssertTrue(CityScenePlace.contextDataAvailable)
        let context = CityScenePlace.contextPlaces()
        XCTAssertTrue(context.contains { $0.id == "landmark-101" })
        XCTAssertEqual(Set(context.map(\.id)).count, context.count)
        XCTAssertGreaterThan(context.count, 100)
        XCTAssertTrue(context.allSatisfy { !$0.isSaved && $0.latitude.isFinite && $0.longitude.isFinite })
    }
    func testAgentOnlyReturnsConfirmedPlacesWithEveryTerm() {
        let confirmed = CityMVPAgentMemory(id: "stamp", name: "測試 Café", address: "信義區",
                                           category: "咖啡", state: "confirmed")
        let decoys = ["candidate", "public", "unknown"].map {
            CityMVPAgentMemory(id: $0, name: confirmed.name, address: confirmed.address,
                               category: confirmed.category, state: $0)
        }
        let records = decoys + [confirmed]
        XCTAssertEqual(CityMVPAgentSearch.matches("我在信義收藏了什麼？", in: records), [confirmed])
        XCTAssertEqual(CityMVPAgentSearch.matches("信義 cafe", in: records), [confirmed])
        XCTAssertTrue(CityMVPAgentSearch.matches("信義 bookshop", in: records).isEmpty)
        XCTAssertTrue(CityMVPAgentSearch.matches("What did I save in?", in: records).isEmpty)
        XCTAssertTrue(CityMVPAgentSearch.matches("信義", in: []).isEmpty)
        let duplicates = (0...6).reversed().map {
            CityMVPAgentMemory(id: "\($0)", name: confirmed.name, address: confirmed.address,
                               category: confirmed.category, state: "confirmed")
        }
        XCTAssertEqual(CityMVPAgentSearch.matches("信義", in: duplicates).map(\.id), ["0", "1", "2", "3", "4"])
    }

    private func scene(_ id: String) -> CityScenePlace {
        CityScenePlace(id: id, title: "Same branch name", category: "cafe", address: "Taipei", latitude: 25.034, longitude: 121.564, isSaved: false)
    }
    private func place(source: String?) -> Place {
        Place(id: UUID(), name: "Same branch name", address: "Taipei", latitude: 25.034, longitude: 121.564,
              category: .cafe, status: .wantToGo, rating: nil, note: nil, sourceUrl: source, sourcePlatform: .other,
              createdAt: Date())
    }
}
