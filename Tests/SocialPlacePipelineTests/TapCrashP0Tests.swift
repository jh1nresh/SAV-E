import CoreLocation
import XCTest
@testable import SAVE

/// P0 tap-to-abort harden. No .ips was available; these lock the
/// presentation, path, and MapKit guards that can terminate the process.
final class TapCrashP0Tests: XCTestCase {
    @MainActor
    func testCaptureSelectionDoesNotBecomeTheVisibleTab() {
        XCTAssertEqual(
            SaveChromeNavigation.destination(afterSelecting: .capture, current: .home),
            .home
        )
        XCTAssertEqual(
            SaveChromeNavigation.destination(afterSelecting: .map, current: .home),
            .map
        )
    }

    @MainActor
    func testRootTabSelectionClearsPushedSavesAndTrips() {
        XCTAssertEqual(SaveChromeNavigation.pathAfterSelectingRootTab(), [])
    }

    @MainActor
    func testOpeningSavesOrTripsReplacesAStaleChild() {
        XCTAssertEqual(
            SaveChromeNavigation.pathByOpening(.saves, currently: [.trips, .trip(UUID())]),
            [.saves]
        )
        XCTAssertEqual(
            SaveChromeNavigation.pathByOpening(.trips, currently: [.saves]),
            [.trips]
        )
        let tripID = UUID()
        XCTAssertEqual(
            SaveChromeNavigation.pathByOpening(.trip(tripID), currently: [.trips]),
            [.trips, .trip(tripID)]
        )
        XCTAssertEqual(
            SaveChromeNavigation.pathByOpening(.trip(tripID), currently: [.saves]),
            [.trip(tripID)]
        )
    }

    @MainActor
    func testSecondExclusiveChromeMustDismissFirst() {
        XCTAssertEqual(
            SaveChromeNavigation.occupyingExclusive(
                hasCover: false,
                isTripComposerPresented: false,
                isPassportPresented: false,
                isRootSheetPresented: false
            ),
            .none
        )
        XCTAssertEqual(
            SaveChromeNavigation.occupyingExclusive(
                hasCover: true,
                isTripComposerPresented: false,
                isPassportPresented: true,
                isRootSheetPresented: true
            ),
            .cover
        )
        XCTAssertEqual(
            SaveChromeNavigation.transition(from: .none, to: .passport),
            .presentNow
        )
        XCTAssertEqual(
            SaveChromeNavigation.transition(from: .rootSheet, to: .cover),
            .dismissThenPresent
        )
        XCTAssertEqual(
            SaveChromeNavigation.transition(from: .cover, to: .passport),
            .dismissThenPresent
        )
        XCTAssertEqual(
            SaveChromeNavigation.transition(from: .passport, to: .passport),
            .dismissThenPresent
        )
    }

    @MainActor
    func testInvalidMapCoordinatesAreRejected() {
        XCTAssertFalse(
            SaveChromeNavigation.isSafeMapCoordinate(
                CLLocationCoordinate2D(latitude: .nan, longitude: 121)
            )
        )
        XCTAssertFalse(
            SaveChromeNavigation.isSafeMapCoordinate(
                CLLocationCoordinate2D(latitude: 25, longitude: .infinity)
            )
        )
        XCTAssertFalse(
            SaveChromeNavigation.isSafeMapCoordinate(
                CLLocationCoordinate2D(latitude: 95, longitude: 0)
            )
        )
        XCTAssertTrue(
            SaveChromeNavigation.isSafeMapCoordinate(
                CLLocationCoordinate2D(latitude: 25.033, longitude: 121.565)
            )
        )
    }

    func testMapEmbeddedDrawerDoesNotCarrySheetDetents() throws {
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("presentedDrawerView"))
        XCTAssertTrue(content.contains("suppressChromeDismissSideEffects"))
        XCTAssertTrue(content.contains("SaveChromeNavigation.pathByOpening"))

        let drawerStart = try XCTUnwrap(content.range(of: "private var drawerView: some View"))
        let afterDrawer = content[drawerStart.lowerBound...]
        let firstDetents = afterDrawer.range(of: ".presentationDetents")
        XCTAssertNil(
            firstDetents,
            "Sheet detents must stay on presentedDrawerView, not the Map-embedded drawer."
        )
    }

    private func source(at relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
