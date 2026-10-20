import UIKit
import XCTest
@testable import SAVE

@MainActor
final class SaveDoodleMapTests: XCTestCase {
    func testProductMapIsDefaultAppleMapsWithDoodleChrome() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("SaveDoodleMapView("))
        XCTAssertFalse(root.contains("SaveTileTownRootMap("))
        XCTAssertTrue(map.contains(".mapStyle(.standard)"))
        XCTAssertFalse(map.contains("emphasis: .muted"))
        XCTAssertFalse(map.contains(".saturation"))
        XCTAssertFalse(map.contains(".colorMultiply"))
        XCTAssertFalse(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("SaveDoodleMapPinStyle"))
        XCTAssertTrue(map.contains("case coralNumbered"))
        XCTAssertTrue(map.contains("case appleDefault"))
        XCTAssertTrue(map.contains("static var current: Kind = .coralNumbered"))
        XCTAssertTrue(map.contains("SaveAtlasPalette.coral"))
        XCTAssertTrue(map.contains("map.eatGo"))
        XCTAssertTrue(map.contains("mapAccessibilityIdentifier"))
        XCTAssertTrue(map.contains("map.city"))
        XCTAssertTrue(map.contains("map.liveSurface"))
        XCTAssertTrue(map.contains("map.checkIn"))
        XCTAssertTrue(map.contains("我來過了"))
        XCTAssertTrue(map.contains("I've been here"))
        XCTAssertTrue(map.contains("map.peek.card"))
        XCTAssertTrue(map.contains("map.tilePin."))
        XCTAssertTrue(root.contains(".accessibilityIdentifier(\"map.root\")"))
        XCTAssertTrue(root.contains("accessibilityElement(children: .contain)"))
    }

    func testMiniMapHandoffStillRemountsEatGo() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(map.contains("@EnvironmentObject private var session: SaveDoodleSession"))
        XCTAssertTrue(map.contains("onChange(of: session.mapVisitResidueID)"))
        XCTAssertTrue(map.contains("applyMiniMapHandoff()"))
        XCTAssertTrue(map.contains("if session.mapFollowsHomeFilter"))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.listedPlaces("))
        XCTAssertTrue(map.contains("session.lens"))
        XCTAssertTrue(map.contains("session.city"))
        XCTAssertTrue(map.contains("showsCityPicker = true"))
        XCTAssertTrue(map.contains("map.city.\\(group.id)"))
        XCTAssertTrue(map.contains("[.isButton, .isSelected] : .isButton"))
        XCTAssertTrue(map.contains("consumeMiniMapHandoff()"))
        XCTAssertTrue(map.contains(".id(visitResidue)"))
        XCTAssertTrue(map.contains("showsCityPicker = false"))
    }

    func testCheckInIsOneVisitPerPlacePerDayAndCanUndo() {
        let defaults = UserDefaults(suiteName: "save.doodle.checkin.\(UUID().uuidString)")!
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = SaveDoodleCheckInStore(
            defaults: defaults,
            calendar: Calendar(identifier: .gregorian),
            now: { now }
        )
        let placeID = UUID()

        XCTAssertTrue(store.canCheckIn(placeID: placeID))
        XCTAssertTrue(store.checkIn(placeID: placeID))
        XCTAssertEqual(store.visitCount(for: placeID), 1)
        XCTAssertTrue(store.hasCheckedInToday(placeID: placeID))
        XCTAssertFalse(store.canCheckIn(placeID: placeID))
        XCTAssertFalse(store.checkIn(placeID: placeID), "One check-in per place per day")

        XCTAssertTrue(store.undoTodaysCheckIn(placeID: placeID))
        XCTAssertEqual(store.visitCount(for: placeID), 0)
        XCTAssertTrue(store.canCheckIn(placeID: placeID))

        XCTAssertTrue(store.checkIn(placeID: placeID))
        now = now.addingTimeInterval(86_400)
        XCTAssertTrue(store.canCheckIn(placeID: placeID), "A new calendar day allows another visit")
        XCTAssertTrue(store.checkIn(placeID: placeID))
        XCTAssertEqual(store.visitCount(for: placeID), 2)
        XCTAssertTrue(store.undoTodaysCheckIn(placeID: placeID))
        XCTAssertEqual(store.visitCount(for: placeID), 1)
        XCTAssertFalse(store.undoTodaysCheckIn(placeID: placeID))
    }

    func testMapWritesAreVisibleToSharedPassportHistory() {
        let suite = "save.doodle.cross-surface.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let map = SaveDoodleCheckInStore(defaults: defaults)
        let passportHistory = SaveDoodleVisitStore(defaults: defaults)
        let id = UUID()
        XCTAssertTrue(map.checkIn(placeID: id))
        XCTAssertEqual(passportHistory.count(for: id), 1)
        XCTAssertTrue(passportHistory.undoToday(for: id))
        XCTAssertEqual(map.visitCount(for: id), 0)
        XCTAssertTrue(map.canCheckIn(placeID: id))
    }

    func testParityMaskLeavesThePointNineGateAndPrefersLiveMap() throws {
        let parity = try source(at: "Prototypes/AtlasPostcard/Scripts/VisualParity.swift")
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(parity.contains("ignoreRects"))
        XCTAssertTrue(script.contains("--threshold 0.90") || script.contains("THRESHOLD=\"0.90\""))
        XCTAssertTrue(script.contains("five-tab-map*)"))
        XCTAssertTrue(script.contains("map-doodle-similarity"))
        XCTAssertTrue(script.contains("--ignore-rect"))
        XCTAssertTrue(script.contains("MAP_IGNORE_RECT=\"0,48,402,642\""))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SaveTileTownRootMap.swift"
            ).path
        ))
        let design = try source(at: "DESIGN.md")
        XCTAssertFalse(design.contains("SaveTileTownRootMap"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "Prototypes/AtlasPostcard/Scripts/generate-doodle-map-target.py"
            ).path
        ))
        let target = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png"
        )
        let image = try XCTUnwrap(UIImage(contentsOfFile: target.path))
        XCTAssertGreaterThan(
            image.pngData()?.count ?? 0,
            50_000,
            "Map target must be a copy of the design mock, not a generated composite"
        )
        XCTAssertEqual(Int(image.size.width), 402)
        XCTAssertEqual(Int(image.size.height), 874)
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
