import MapKit
import SwiftUI
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
        XCTAssertTrue(map.contains(".mapStyle(.standard(emphasis: .automatic))"))
        XCTAssertFalse(map.contains(".saturation("))
        XCTAssertFalse(map.contains(".colorMultiply("))
        XCTAssertFalse(map.contains(".blendMode(.multiply)"))
        XCTAssertTrue(map.contains("SaveDoodleSticker("))
        XCTAssertTrue(map.contains("placeName: place.name"))
        XCTAssertTrue(map.contains("SaveLayout.passportSlot"))
        XCTAssertFalse(map.contains("emphasis: .muted"))
        XCTAssertFalse(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("SaveDoodleMapPinStyle"))
        XCTAssertTrue(map.contains("case coralNumbered"))
        XCTAssertTrue(map.contains("case appleDefault"))
        XCTAssertTrue(map.contains("static var current: Kind = .appleDefault"))
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
        XCTAssertTrue(header.contains(".lineLimit(2)"))
        XCTAssertTrue(header.contains(".minimumScaleFactor(1)"))
        XCTAssertFalse(header.contains("truncationMode"))
        XCTAssertFalse(header.contains("fixedSize(horizontal: true"))
        XCTAssertTrue(map.contains("SaveDoodleLollipopShape"))
        XCTAssertTrue(map.contains("anchor: .bottom"))
        XCTAssertTrue(map.contains(".fill(pinColor)"))
        XCTAssertTrue(map.contains(".foregroundStyle(Color.white)"))
        XCTAssertTrue(map.contains("visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral"))
        let pinAt = try XCTUnwrap(map.range(of: "struct SaveDoodleCoralPin: View"))
        let pinShapeAt = try XCTUnwrap(map.range(of: "nonisolated struct SaveDoodleLollipopShape"))
        let pin = map[pinAt.lowerBound..<pinShapeAt.lowerBound]
        XCTAssertFalse(
            pin.contains(".fill(SaveAtlasPalette.paper)"),
            "Numbered pins keep their coral fill; the separate place card may use paper."
        )
        XCTAssertTrue(map.contains("nativeUnsavedCandidates"))
        XCTAssertTrue(map.contains("SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: languageSettings.language)"))
        XCTAssertTrue(map.contains("item.place.status == .visited ? .triedMemory : .savedPlace"))
        XCTAssertFalse(map.contains("AsyncImage"))
        XCTAssertFalse(map.contains("photoURL"))
        XCTAssertFalse(map.contains("businessPhotoURLs"))
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
        XCTAssertTrue(map.contains("HStack(spacing: SaveSpace.sm)"))
        XCTAssertTrue(map.contains("minHeight: SaveLayout.buttonHeight"))
        XCTAssertTrue(map.contains("AtlasTabBarMetrics.height"))
        XCTAssertTrue(map.contains("seedUITestUnsavedCandidateIfNeeded"))
        XCTAssertTrue(map.contains("map.peek.card"))
        XCTAssertTrue(map.contains("locksPointSize: true"))
        XCTAssertTrue(map.contains("shouldFocusOnUserLocation"))
        XCTAssertFalse(map.contains("focusOnUserLocationOnLaunch()"))
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

    func testNativeMarkerTitlesKeepStateOnlyInAccessibilityLabel() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        let start = try XCTUnwrap(map.range(of: "private var mapCanvas"))
        let end = try XCTUnwrap(map.range(of: "if let polyline", range: start.upperBound..<map.endIndex))
        let markers = map[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(markers.contains("Marker(coordinate: item.place.coordinate)"))
        XCTAssertTrue(markers.contains("Text(item.place.name)"))
        XCTAssertTrue(markers.contains(#".accessibilityLabel("\(item.place.name), \(state.displayName(language: languageSettings.language))")"#))
        XCTAssertTrue(markers.contains("Marker(coordinate: candidate.coordinate)"))
        XCTAssertTrue(markers.contains("Text(candidate.title)"))
        XCTAssertTrue(markers.contains(#".accessibilityLabel("\(candidate.title), \(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: languageSettings.language))")"#))
        let candidateStart = try XCTUnwrap(markers.range(of: "ForEach(nativeUnsavedCandidates)"))
        let candidates = markers[candidateStart.lowerBound...]
        XCTAssertFalse(candidates.contains(".tint("), "Unsaved markers keep Apple's native color")
    }

    func testInitialFitIncludesDistantSavedPlacesWithPadding() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 25.03, longitude: 121.56),
            CLLocationCoordinate2D(latitude: 35.68, longitude: 139.69),
            CLLocationCoordinate2D(latitude: 48.86, longitude: 2.35)
        ]
        let region = SaveDoodleMapView.region(fitting: coordinates)
        for coordinate in coordinates {
            XCTAssertLessThan(abs(coordinate.latitude - region.center.latitude), region.span.latitudeDelta / 2)
            XCTAssertLessThan(abs(coordinate.longitude - region.center.longitude), region.span.longitudeDelta / 2)
        }
    }

    func testInitialFitHandlesOneOrNoSavedPlaces() {
        let coordinate = CLLocationCoordinate2D(latitude: 25.03, longitude: 121.56)
        let single = SaveDoodleMapView.region(fitting: [coordinate])
        XCTAssertEqual(single.center.latitude, coordinate.latitude)
        XCTAssertEqual(single.center.longitude, coordinate.longitude)
        XCTAssertEqual(single.span.latitudeDelta, 0.012)
        XCTAssertEqual(single.span.longitudeDelta, 0.012)
        let located = SaveDoodleMapView.region(fitting: [], fallback: coordinate)
        XCTAssertEqual(located.center.latitude, coordinate.latitude)
        XCTAssertEqual(located.center.longitude, coordinate.longitude)
        let empty = SaveDoodleMapView.region(fitting: [])
        XCTAssertEqual(empty.center.latitude, 37.7749)
        XCTAssertEqual(empty.center.longitude, -122.4194)
        XCTAssertEqual(empty.span.latitudeDelta, 0.05)
    }

    func testInitialFitPreservesExplicitCommandsAndHasNoLateLocationOverride() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(map.contains("fitVisiblePlaces(initialOpening: !session.mapFollowsHomeFilter)"))
        XCTAssertTrue(map.contains("session.mapFollowsHomeFilter = !initialOpening"))
        let listStart = try XCTUnwrap(map.range(of: "private var displayedListedPlaces"))
        let listEnd = try XCTUnwrap(map.range(of: "private var nativeUnsavedCandidates"))
        let listed = map[listStart.lowerBound..<listEnd.lowerBound]
        XCTAssertTrue(listed.contains("if !session.mapFollowsHomeFilter"))
        XCTAssertTrue(listed.contains("return mapViewModel.places.enumerated().map"))
        XCTAssertTrue(listed.contains("return SaveDoodleHomeCatalog.listedPlaces("))
        XCTAssertTrue(map.contains(#"let pins = mapViewModel.places.filter(\.isMapKitMappable).map(\.coordinate)"#))
        XCTAssertFalse(map.contains(".onChange(of: locationService.currentLocation"))
        XCTAssertFalse(map.contains(".task(id: shouldFocusOnUserLocation)"))
        XCTAssertTrue(map.contains("case .explicitCommand:"))
        XCTAssertTrue(map.contains("case .changedFilters:\n                onClearSelection()\n                fitVisiblePlaces()"))
        XCTAssertTrue(map.contains("Task { await mapViewModel.focusOnUserLocation() }"))
        XCTAssertFalse(map.contains("peekTransition"))
        XCTAssertFalse(map.contains(".transition("))
        XCTAssertFalse(map.contains("stampPulse"))
        XCTAssertTrue(map.contains("transaction.disablesAnimations = true"))
    }

    func testProductMapKeepsNativeAppleColors() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertFalse(
            map.contains(".saturation("),
            "SaveDoodleMapView HoP 298-1: no saturation wash on Apple tiles"
        )
        XCTAssertFalse(
            map.contains(".colorMultiply("),
            "SaveDoodleMapView HoP 298-1: no colorMultiply wash on Apple tiles"
        )
        XCTAssertFalse(
            map.contains("emphasis: .muted"),
            "SaveDoodleMapView HoP 298-1: no muted MapKit emphasis"
        )
        XCTAssertFalse(
            map.contains(".blendMode(.multiply)"),
            "SaveDoodleMapView HoP 298-1: no paper multiply overlay"
        )
        XCTAssertFalse(
            map.contains("PaperGrain"),
            "SaveDoodleMapView HoP 298-1: no paper-texture overlay"
        )
        XCTAssertFalse(
            map.contains("paper-grain"),
            "SaveDoodleMapView HoP 298-1: no paper-texture overlay"
        )
        XCTAssertFalse(
            map.contains("paper multiply"),
            "SaveDoodleMapView HoP 298-1: no paper multiply overlay"
        )
        let withoutPaletteMuted = map.replacingOccurrences(
            of: "SaveAtlasPalette.muted",
            with: ""
        )
        XCTAssertFalse(
            withoutPaletteMuted.contains(".muted"),
            "SaveDoodleMapView HoP 298-1: no .muted map wash"
        )
        XCTAssertTrue(map.contains(".mapStyle(.standard(emphasis: .automatic))"))
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

        let failed = await store.applyCheckIn(placeID: placeID, priorStatus: .visited) {
            throw OfflineError()
        }
        XCTAssertFalse(failed)
        XCTAssertEqual(store.visitCount(for: placeID), 0)
        XCTAssertTrue(store.canCheckIn(placeID: placeID))

        // A later visit from shared history must not inherit the failed
        // attempt's undo baseline.
        XCTAssertTrue(store.checkIn(placeID: placeID))
        var restoredAfterForeignVisit: PlaceStatus?
        let undoneForeign = await store.applyUndo(placeID: placeID) { restoredAfterForeignVisit = $0 }
        XCTAssertTrue(undoneForeign)
        XCTAssertEqual(restoredAfterForeignVisit, .wantToGo)

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
        XCTAssertTrue(parity.contains("allowedPixelScales: 1...4"))
        XCTAssertTrue(parity.contains("Map goldens are the 3× CI Taipei capture"))
        XCTAssertTrue(script.contains("--threshold 0.90") || script.contains("THRESHOLD=\"0.90\""))
        XCTAssertTrue(script.contains("five-tab-map*)"))
        XCTAssertTrue(script.contains("298-10-saved-unsaved-visited"))
        XCTAssertTrue(script.contains("*-zh*)"))
        XCTAssertTrue(script.contains("map-doodle-similarity"))
        XCTAssertTrue(script.contains("full frame, no map-mask.png"))
        XCTAssertFalse(script.contains("extra_args=(--ignore-mask \"$MAP_MASK\")"))
        XCTAssertFalse(script.contains("--mask-image \"$MAP_MASK\""))
        let compose = try source(at: "Prototypes/AtlasPostcard/Scripts/compose-map-similarity.py")
        XCTAssertTrue(compose.contains("used_mask_image"))
        XCTAssertTrue(compose.contains("\"coverage\": \"mask-image\""))
        XCTAssertTrue(compose.contains("x, y, w, h = args.mask"))
        XCTAssertFalse(script.contains("status=\"REVIEW\""))
        XCTAssertFalse(script.contains("The 0.90 score is not a CI gate."))
        XCTAssertFalse(script.contains("\"$screen\" != \"home\" && \"$screen\" != \"map\""))
        XCTAssertTrue(script.contains("gate_failed=1"))
        XCTAssertTrue(script.contains("Home, Map, Saves, Plan, and Passport all fail the job below 0.90."))
        XCTAssertTrue(script.contains("${#extra_args[@]} -gt 0"))
        XCTAssertTrue(script.contains("${#mask_args[@]} -gt 0"))
        XCTAssertTrue(map.contains("cityOpeningPins()"))
        XCTAssertTrue(map.contains("openingCityID("))
        XCTAssertTrue(map.contains("addresslessOpeningPins("))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.nearbyRadius"))
        XCTAssertTrue(map.contains("min(max((maxLat - minLat) * 1.6, 0.012), 180)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"298-3-home\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-3-map\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-2-mapkit\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-4-coral-pins\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-5-been-here\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-6-city-eat-go\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-7-map-tab\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-8-provider\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"298-10-saved-unsaved-visited\")"))
        XCTAssertTrue(rail.contains("attach(app, name: \"M1\")"))
        XCTAssertTrue(rail.contains("--uitest-home-memory-fixture"))
        XCTAssertTrue(rail.contains("--uitest-map-unsaved-candidate"))
        XCTAssertTrue(rail.contains("298-11: Eat/Go must expose isSelected"))
        XCTAssertTrue(rail.contains("298-12: city title must not truncate"))
        XCTAssertTrue(rail.contains("\"map-375\""))
        XCTAssertTrue(rail.contains("\"map-390\""))
        XCTAssertTrue(rail.contains("\"map-430\""))
        XCTAssertTrue(rail.contains("func testMapWidth375"))
        XCTAssertTrue(rail.contains("func testMapWidth390"))
        XCTAssertTrue(rail.contains("func testMapWidth430"))
        XCTAssertFalse(rail.contains("--uitest-map-width="))
        XCTAssertFalse(map.contains("--uitest-map-width="))
        XCTAssertFalse(map.contains("uiTestMapWidth"))
        let workflow = try source(at: ".github/workflows/ios.yml")
        XCTAssertTrue(workflow.contains("\"298-3-home\""))
        XCTAssertTrue(workflow.contains("\"298-3-map\""))
        XCTAssertTrue(workflow.contains("\"298-2-mapkit\""))
        XCTAssertTrue(workflow.contains("\"298-4-coral-pins\""))
        XCTAssertTrue(workflow.contains("\"298-5-been-here\""))
        XCTAssertTrue(workflow.contains("\"298-6-city-eat-go\""))
        XCTAssertTrue(workflow.contains("\"298-7-map-tab\""))
        XCTAssertTrue(workflow.contains("\"298-8-provider\""))
        XCTAssertTrue(workflow.contains("\"map-375\""))
        XCTAssertTrue(workflow.contains("\"map-390\""))
        XCTAssertTrue(workflow.contains("\"map-430\""))
        XCTAssertTrue(workflow.contains("testMapWidth375"))
        XCTAssertTrue(workflow.contains("testMapWidth390"))
        XCTAssertTrue(workflow.contains("testMapWidth430"))
        XCTAssertTrue(workflow.contains("iPhone-SE-3rd-generation"))
        XCTAssertTrue(workflow.contains("iPhone-14"))
        XCTAssertTrue(workflow.contains("iPhone-16-Pro-Max"))
        XCTAssertFalse(workflow.contains("--uitest-map-width="))
        XCTAssertFalse(rail.contains("298-7: tapping the Map tab directly must open Map"))
        XCTAssertFalse(rail.contains("Map tab uses Map's own state"))
        XCTAssertFalse(map.contains("if session.mapFollowsHomeFilter"))
        XCTAssertTrue(rail.contains("298-3: pin count equals Home list rows"))
        XCTAssertTrue(rail.contains("298-2: product Map must be a live Apple MapKit surface"))
        XCTAssertTrue(rail.contains("298-5: place sheet must offer"))
        XCTAssertTrue(rail.contains("298-6: city chrome"))
        XCTAssertTrue(rail.contains("298-8: selected place keeps provider-backed Directions"))
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
        XCTAssertTrue(design.contains("DESIGN still signs off"))
        XCTAssertTrue(design.contains("Home and Map still fail CI below 0.90"))
        XCTAssertFalse(design.contains("0.90 visual-parity score is not evidence"))
        XCTAssertTrue(design.contains("Do not apply `map-mask.png` to the 0.90 score"))
        XCTAssertTrue(design.contains("Home and Map share one Eat/Go + city state"))
        XCTAssertTrue(design.contains("pin count equals Home list rows"))
        XCTAssertFalse(design.contains("Map always uses its own state"))
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
        for name in ["map.png", "map-light.png", "map-dark.png"] {
            let image = try XCTUnwrap(UIImage(contentsOfFile: targets.appendingPathComponent(name).path))
            XCTAssertEqual(Int(image.size.width), 1206, name)
            XCTAssertEqual(Int(image.size.height), 2622, name)
        }
        let mask = try XCTUnwrap(UIImage(contentsOfFile: targets.appendingPathComponent("map-mask.png").path))
        XCTAssertEqual(Int(mask.size.width), 402)
        XCTAssertEqual(Int(mask.size.height), 874)
        let light = try XCTUnwrap(UIImage(contentsOfFile: targets.appendingPathComponent("map.png").path))
        XCTAssertGreaterThan(
            light.pngData()?.count ?? 0,
            50_000,
            "Map target must be a live Taipei Apple Maps screenshot, not a generated composite"
        )
    }

    func testPeekDuringExactSearchResolvesTheReviewClue() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-exact-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let stamp = Place(
            id: UUID(),
            name: "Review Coffee Xinyi",
            address: "Taipei",
            latitude: 25.033,
            longitude: 121.565,
            category: .cafe,
            status: .wantToGo,
            sourcePlatform: .other,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let clue = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Coffee clue",
            address: "Taipei",
            city: "Taipei",
            latitude: nil,
            longitude: nil,
            evidence: ["Original source note"],
            confidence: 0.8,
            missingInfo: ["Exact coordinates"],
            status: "review",
            createdAt: Date()
        )
        _ = try vault.saveConfirmedPlace(stamp)
        let map = MapViewModel(
            saveLocalVaultService: vault,
            usesRemotePersistence: false
        )
        map.places = [stamp]
        map.reviewCandidates = [clue]
        map.beginExactSearchResolution(for: clue)
        XCTAssertTrue(map.hasActiveExactSearchResolution)
        XCTAssertTrue(map.reviewCandidates.contains { $0.id == clue.id })

        let idle = await SaveDoodleMapPeekOpen.perform(
            place: stamp,
            mapViewModel: MapViewModel(usesRemotePersistence: false),
            isExactSearchSessionActive: false,
            exactSearchClueID: nil,
            restoreResolution: {},
            isCurrentRequest: { true }
        )
        XCTAssertEqual(idle, .openStamp(stamp.id))

        let mismatched = await SaveDoodleMapPeekOpen.perform(
            place: stamp, mapViewModel: map,
            isExactSearchSessionActive: true, exactSearchClueID: UUID(),
            restoreResolution: {}, isCurrentRequest: { true }
        )
        XCTAssertEqual(mismatched, .stayOnSearch)
        XCTAssertEqual(map.activeExactSearchClueID, clue.id)
        XCTAssertTrue(map.reviewCandidates.contains { $0.id == clue.id })

        let cancelled = await SaveDoodleMapPeekOpen.perform(
            place: stamp, mapViewModel: map,
            isExactSearchSessionActive: true, exactSearchClueID: clue.id,
            restoreResolution: { XCTFail("A stale tap must not restore a session") },
            isCurrentRequest: { false }
        )
        XCTAssertEqual(cancelled, .stayOnSearch)
        XCTAssertEqual(map.activeExactSearchClueID, clue.id)

        var restored = 0
        let outcome = await SaveDoodleMapPeekOpen.perform(
            place: stamp,
            mapViewModel: map,
            isExactSearchSessionActive: true,
            exactSearchClueID: clue.id,
            restoreResolution: { restored += 1 },
            isCurrentRequest: { true }
        )
        XCTAssertGreaterThan(restored, 0)
        XCTAssertEqual(outcome, .resolvedStamp(stamp.id))
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == clue.id })
        XCTAssertFalse(map.hasActiveExactSearchResolution)
        XCTAssertTrue(map.places.contains { $0.id == stamp.id })
    }

    func testUnsavedMarkerSelectReopensReceiptSelection() {
        let saved = Place(
            id: UUID(),
            name: "Saved Cafe",
            address: "Taipei",
            latitude: 25.033,
            longitude: 121.565,
            category: .cafe,
            status: .wantToGo,
            sourcePlatform: .other,
            createdAt: Date()
        )
        let candidate = SaveMapCandidate(
            id: "unsaved-night-market",
            title: "Unsaved Night Market",
            subtitle: "Taipei",
            latitude: 25.0378,
            longitude: 121.5672,
            category: .attraction
        )
        let map = MapViewModel(usesRemotePersistence: false)
        map.places = [saved]
        map.mapCandidates = [candidate]
        map.selectPlace(saved)
        XCTAssertEqual(map.selectedPlace?.id, saved.id)
        XCTAssertNil(map.selectedMapCandidate)
        let viewport = MapCameraPosition.region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.04, longitude: 121.56),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        ))
        map.cameraPosition = viewport

        SaveDoodleMapUnsavedMarker.select(candidate, on: map)

        XCTAssertEqual(map.selectedMapCandidate?.id, candidate.id)
        XCTAssertEqual(map.selectedMapCandidate?.title, "Unsaved Night Market")
        XCTAssertNil(map.selectedPlace)
        XCTAssertTrue(map.visibleMapCandidates.contains { $0.id == candidate.id })
        XCTAssertEqual(map.cameraPosition, viewport, "Marker taps must preserve the viewport")

        map.selectMapCandidate(candidate)
        XCTAssertEqual(map.cameraPosition.region?.center.latitude, candidate.latitude)
        XCTAssertEqual(map.cameraPosition.region?.center.longitude, candidate.longitude)
        XCTAssertEqual(map.cameraPosition.region?.span.latitudeDelta, 0.01,
                       "Explicit candidate selection must still focus the camera")
    }

    func testMapEntryReconcilesFiltersAndConsumesExplicitCommand() throws {
        let suite = "SaveDoodleMapEntry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SaveDoodleSession(defaults: defaults)
        XCTAssertFalse(session.mapFollowsHomeFilter, "First Map opening shows the whole saved collection")
        session.city = .city("tokyo")
        XCTAssertEqual(session.consumeMapEntry(), .restoreViewport)
        session.recordMapFilters() // Map -> Home; presentation mode is held by the session.
        XCTAssertEqual(session.consumeMapEntry(), .restoreViewport)
        XCTAssertFalse(session.mapFollowsHomeFilter)

        session.city = .city("taipei")
        XCTAssertEqual(session.consumeMapEntry(), .changedFilters)
        XCTAssertEqual(session.consumeMapEntry(), .restoreViewport)
        session.lens = .go
        XCTAssertEqual(session.consumeMapEntry(), .changedFilters)

        session.city = .city("tokyo")
        session.pendingExplicitMapEntry = true
        XCTAssertEqual(session.consumeMapEntry(), .explicitCommand)
        XCTAssertFalse(session.pendingExplicitMapEntry)
        XCTAssertEqual(session.consumeMapEntry(), .restoreViewport)

        session.lens = .eat
        session.recordMapFilters() // Filters changed while Map was mounted.
        XCTAssertEqual(session.consumeMapEntry(), .restoreViewport)
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
