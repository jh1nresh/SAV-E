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
        XCTAssertTrue(map.contains("SaveDoodleSticker("))
        XCTAssertTrue(map.contains("placeName: place.name"))
        XCTAssertTrue(map.contains("SaveLayout.passportSlot"))
        XCTAssertFalse(map.contains("emphasis: .muted"))
        XCTAssertFalse(map.contains(".saturation"))
        XCTAssertFalse(map.contains(".colorMultiply"))
        XCTAssertFalse(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("SaveDoodleMapPinStyle"))
        XCTAssertTrue(map.contains("case coralNumbered"))
        XCTAssertTrue(map.contains("case appleDefault"))
        XCTAssertTrue(map.contains("static var current: Kind = .coralNumbered"))
        XCTAssertTrue(map.contains("SaveAtlasPalette.coral"))
        XCTAssertTrue(map.contains("map.headerBand"))
        XCTAssertTrue(map.contains("SaveAtlasPalette.paper"))
        let bodyAt = try XCTUnwrap(map.range(of: "var body: some View"))
        let headerFnAt = try XCTUnwrap(map.range(of: "private func header"))
        let eatGoAt = try XCTUnwrap(map.range(of: "private var eatGoRail"))
        let chrome = map[bodyAt.lowerBound..<headerFnAt.lowerBound]
        let header = map[headerFnAt.lowerBound..<eatGoAt.lowerBound]
        XCTAssertTrue(chrome.contains("map.headerBand"))
        XCTAssertTrue(
            chrome.contains("accessibilityElement(children: .contain)"),
            "map.headerBand must contain children so map.city stays a Button"
        )
        XCTAssertTrue(header.contains("map.city"))
        XCTAssertTrue(header.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(header.contains("accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(map.contains("SaveDoodleLollipopShape"))
        XCTAssertTrue(map.contains("anchor: .bottom"))
        XCTAssertFalse(map.contains(".fill(visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral)"))
        XCTAssertTrue(map.contains(".stroke(pinColor, lineWidth: 2)"))
        XCTAssertTrue(map.contains("map.eatGo"))
        let sheetAt = try XCTUnwrap(map.range(of: "private func placeSheet"))
        let eatGo = map[eatGoAt.lowerBound..<sheetAt.lowerBound]
        XCTAssertTrue(eatGo.contains("minHeight: SaveLayout.chipHeight"))
        XCTAssertTrue(eatGo.contains("minHeight: SaveLayout.minTap"))
        XCTAssertTrue(eatGo.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(map.contains("mapAccessibilityIdentifier"))
        XCTAssertTrue(map.contains("map.city"))
        XCTAssertTrue(map.contains("map.liveSurface"))
        XCTAssertTrue(map.contains("map.card.beenHere"))
        XCTAssertFalse(map.contains("\"map.checkIn\""))
        XCTAssertTrue(map.contains("我來過了"))
        XCTAssertTrue(map.contains("I've been here"))
        XCTAssertTrue(map.contains("map.peek.card"))
        XCTAssertTrue(map.contains("locksPointSize: true"))
        XCTAssertTrue(map.contains("shouldFocusOnUserLocation"))
        XCTAssertTrue(map.contains("focusOnUserLocationOnLaunch()"))
        XCTAssertTrue(map.contains("map.providerBackedPlaces"))
        XCTAssertTrue(map.contains("ForEach(providerBackedPlaces)"))
        XCTAssertTrue(map.contains("map.providerBackedPlaces.\\(place.id.uuidString)"))
        XCTAssertTrue(map.contains("openDirections(for: place)"))
        XCTAssertTrue(map.contains("place.providerMapDestinationURL"))
        XCTAssertTrue(map.contains("openingCityID("))
        XCTAssertTrue(root.contains("shouldFocusOnUserLocation: shouldFocusOnUserLocation"))
        XCTAssertTrue(map.contains(".accessibilityHidden(true)"))
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
        XCTAssertTrue(map.contains("session.mapFollowsHomeFilter = true"))
        XCTAssertTrue(map.contains("onMapCameraChange(frequency: .onEnd)"))
        XCTAssertTrue(map.contains("updateVisibleMapRegion(context.region)"))
        XCTAssertTrue(map.contains("let reselecting = session.lens == item"))
        XCTAssertTrue(map.contains("disabled(checkIns.isPersisting(placeID: place.id))"))
        XCTAssertTrue(map.contains("map.city.\\(group.id)"))
        XCTAssertTrue(map.contains("[.isButton, .isSelected] : .isButton"))
        XCTAssertTrue(map.contains("consumeMiniMapHandoff()"))
        XCTAssertTrue(map.contains(".id(visitResidue)"))
        XCTAssertTrue(map.contains("showsCityPicker = false"))
    }

    func testReplacementMapRendersCollaborativeListRoute() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        let pinSource = try source(at: "SAV-E/Views/Map/MapView.swift")
        XCTAssertTrue(map.contains("routePolyline"))
        XCTAssertTrue(map.contains("MapPolyline(polyline)"))
        XCTAssertTrue(map.contains("if !mapViewModel.routeCoordinates.isEmpty"))
        XCTAssertTrue(pinSource.contains("if let polyline = viewModel.routePolyline"))
        XCTAssertTrue(pinSource.contains("dash: [7, 5]"))
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

    @MainActor
    func testFailedPlaceUpdateRollsBackTodaysCheckIn() async throws {
        let defaults = UserDefaults(suiteName: "save.doodle.checkin.rollback.\(UUID().uuidString)")!
        let store = SaveDoodleCheckInStore(
            defaults: defaults,
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let placeID = UUID()
        struct OfflineError: Error {}

        let failed = await store.applyCheckIn(placeID: placeID) {
            throw OfflineError()
        }
        XCTAssertFalse(failed)
        XCTAssertEqual(store.visitCount(for: placeID), 0)
        XCTAssertTrue(store.canCheckIn(placeID: placeID))

        let succeeded = await store.applyCheckIn(placeID: placeID) {}
        XCTAssertTrue(succeeded)
        XCTAssertEqual(store.visitCount(for: placeID), 1)
        XCTAssertFalse(store.canCheckIn(placeID: placeID))

        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(map.contains("applyCheckIn("))
        XCTAssertTrue(map.contains("priorStatus: place.status"))
        XCTAssertTrue(map.contains("applyUndo(placeID: place.id)"))
        let checkInAt = try XCTUnwrap(map.range(of: "private func performCheckIn"))
        let undoAt = try XCTUnwrap(map.range(of: "private func undoCheckIn"))
        let perform = map[checkInAt.lowerBound..<undoAt.lowerBound]
        XCTAssertFalse(perform.contains("try?"))
        let undo = map[undoAt.lowerBound...]
        XCTAssertFalse(String(undo.prefix(800)).contains("try?"))
    }

    @MainActor
    func testUndoRestoresPriorVisitedStatusAndRollsBackFailedPersist() async throws {
        let defaults = UserDefaults(suiteName: "save.doodle.checkin.undo.\(UUID().uuidString)")!
        let store = SaveDoodleCheckInStore(
            defaults: defaults,
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let placeID = UUID()
        struct OfflineError: Error {}

        let checkedIn = await store.applyCheckIn(placeID: placeID, priorStatus: .visited) {}
        XCTAssertTrue(checkedIn)
        XCTAssertEqual(store.visitCount(for: placeID), 1)

        var restored: PlaceStatus?
        let undone = await store.applyUndo(placeID: placeID) { status in
            restored = status
        }
        XCTAssertTrue(undone)
        XCTAssertEqual(restored, .visited)
        XCTAssertEqual(store.visitCount(for: placeID), 0)
        XCTAssertTrue(store.canCheckIn(placeID: placeID))

        let rechecked = await store.applyCheckIn(placeID: placeID, priorStatus: .wantToGo) {}
        XCTAssertTrue(rechecked)
        let failedUndo = await store.applyUndo(placeID: placeID) { _ in
            throw OfflineError()
        }
        XCTAssertFalse(failedUndo)
        XCTAssertEqual(store.visitCount(for: placeID), 1)
        XCTAssertTrue(store.hasCheckedInToday(placeID: placeID))
    }

    @MainActor
    func testEachDaysCheckInRefreshesUndoBaseline() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = SaveDoodleCheckInStore(
            defaults: UserDefaults(suiteName: "save.doodle.checkin.baseline.\(UUID().uuidString)")!,
            calendar: Calendar(identifier: .gregorian),
            now: { now }
        )
        let placeID = UUID()
        let dayOne = await store.applyCheckIn(placeID: placeID, priorStatus: .wantToGo) {}
        XCTAssertTrue(dayOne)
        now = now.addingTimeInterval(86_400)
        let dayTwo = await store.applyCheckIn(placeID: placeID, priorStatus: .visited) {}
        XCTAssertTrue(dayTwo)
        var restored: PlaceStatus?
        let undone = await store.applyUndo(placeID: placeID) { restored = $0 }
        XCTAssertTrue(undone)
        XCTAssertEqual(restored, .visited)
    }

    @MainActor
    func testCheckInAndUndoDoNotOverlapPersist() async {
        let store = SaveDoodleCheckInStore(
            defaults: UserDefaults(suiteName: "save.doodle.checkin.serialize.\(UUID().uuidString)")!,
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let placeID = UUID()
        var release: CheckedContinuation<Void, Never>?
        let persist = Task {
            await store.applyCheckIn(placeID: placeID) {
                await withCheckedContinuation { release = $0 }
            }
        }
        while release == nil { await Task.yield() }
        XCTAssertTrue(store.isPersisting(placeID: placeID))
        let overlappingUndo = await store.applyUndo(placeID: placeID) { _ in }
        XCTAssertFalse(overlappingUndo)
        release?.resume()
        let persisted = await persist.value
        XCTAssertTrue(persisted)
        XCTAssertFalse(store.isPersisting(placeID: placeID))
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
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(parity.contains("ignoreRects"))
        XCTAssertTrue(parity.contains("--ignore-mask"))
        XCTAssertTrue(script.contains("--threshold 0.90") || script.contains("THRESHOLD=\"0.90\""))
        XCTAssertTrue(script.contains("five-tab-map*)"))
        XCTAssertTrue(script.contains("*-zh*)"))
        XCTAssertTrue(script.contains("map-doodle-similarity"))
        XCTAssertTrue(script.contains("--ignore-mask"))
        XCTAssertTrue(script.contains("map-mask.png"))
        let compose = try source(at: "Prototypes/AtlasPostcard/Scripts/compose-map-similarity.py")
        XCTAssertTrue(compose.contains("used_mask_image"))
        XCTAssertTrue(compose.contains("\"coverage\": \"mask-image\""))
        XCTAssertTrue(compose.contains("x, y, w, h = args.mask"))
        XCTAssertTrue(script.contains("status=\"REVIEW\""))
        XCTAssertTrue(script.contains("The 0.90 score is not a CI gate."))
        XCTAssertTrue(script.contains("${#extra_args[@]} -gt 0"))
        XCTAssertTrue(script.contains("${#mask_args[@]} -gt 0"))
        XCTAssertTrue(map.contains("cityOpeningPins()"))
        XCTAssertTrue(map.contains("openingCityID("))
        XCTAssertTrue(map.contains("min(max((maxLat - minLat) * 1.6, 0.012), 0.45)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"298-3-home\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-3-map\")"))
        let workflow = try source(at: ".github/workflows/ios.yml")
        XCTAssertTrue(workflow.contains("\"298-3-home\""))
        XCTAssertTrue(workflow.contains("\"298-3-map\""))
        XCTAssertTrue(rail.contains("298-7: tapping the Map tab directly must open Map"))
        XCTAssertTrue(rail.contains("map.card.beenHere"))
        XCTAssertFalse(rail.contains("\"map.checkIn\""))
        XCTAssertFalse(map.contains("taipei.isEmpty ? coordinates : taipei"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SaveTileTownRootMap.swift"
            ).path
        ))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("judged manually by DESIGN"))
        XCTAssertTrue(design.contains("0.90 visual-parity score is not evidence"))
        XCTAssertTrue(design.contains("coral outline lollipops"))
        XCTAssertFalse(design.contains("SaveTileTownRootMap"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "Prototypes/AtlasPostcard/Scripts/generate-doodle-map-target.py"
            ).path
        ))
        let targets = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets"
        )
        for name in ["map.png", "map-light.png", "map-dark.png", "map-mask.png"] {
            let image = try XCTUnwrap(UIImage(contentsOfFile: targets.appendingPathComponent(name).path))
            XCTAssertEqual(Int(image.size.width), 402, name)
            XCTAssertEqual(Int(image.size.height), 874, name)
        }
        let light = try XCTUnwrap(UIImage(contentsOfFile: targets.appendingPathComponent("map.png").path))
        XCTAssertGreaterThan(
            light.pngData()?.count ?? 0,
            50_000,
            "Map target must be DESIGN v2 map-light.png, not a generated composite"
        )
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
