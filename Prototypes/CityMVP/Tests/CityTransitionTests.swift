import XCTest
import MapKit
import simd
import SwiftUI
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityTransitionTests: XCTestCase {
    func testMapAlignmentTimeoutDoesNotWaitForNativeCallback() async {
        var lateResult: (@Sendable (CityDistrictRegistration?) -> Void)?
        var cancelled = false
        let result = await CityDistrictRegistration.firstResult(timeout: .milliseconds(20), start: {
            lateResult = $0
        }, cancel: { cancelled = true })
        XCTAssertNil(result)
        XCTAssertTrue(cancelled)
        // A native callback arriving after the deadline must be harmless.
        lateResult?(.init(latitudeOffset: 0, longitudeOffset: 0))
    }

    func testMapAlignmentKeepsFirstResultAndCancelsNativeWork() async {
        let expected = CityDistrictRegistration(latitudeOffset: -0.003, longitudeOffset: 0.004)
        var cancelled = false
        let result = await CityDistrictRegistration.firstResult(timeout: .seconds(10), start: { finish in
            finish(expected)
            finish(nil)
        }, cancel: { cancelled = true })
        XCTAssertEqual(result, expected)
        XCTAssertTrue(cancelled)
    }

    func testMapAlignmentCancellationDoesNotWaitForDeadline() async {
        var cancelled = false
        let started = expectation(description: "Native search started")
        let lookup = Task { @MainActor in
            await CityDistrictRegistration.firstResult(timeout: .seconds(60), start: { _ in
                started.fulfill()
            }, cancel: { cancelled = true })
        }
        await fulfillment(of: [started], timeout: 1)
        let cancelledAt = ContinuousClock.now
        lookup.cancel()
        let result = await lookup.value
        XCTAssertLessThan(cancelledAt.duration(to: .now), .seconds(1))
        XCTAssertNil(result)
        XCTAssertTrue(cancelled)
    }

    private let registration = CityDistrictRegistration(latitudeOffset: -0.003, longitudeOffset: 0.004)
    private let viewport = CGSize(width: 402, height: 874)

    func testStyleHysteresisRetainsTheCurrentStyleInsideTheBand() {
        XCTAssertEqual(CityDistrictMapStyle.globe.updated(for: 3_000_000), .globe)
        XCTAssertEqual(CityDistrictMapStyle.city.updated(for: 3_000_000), .city)
        XCTAssertEqual(CityDistrictMapStyle.globe.updated(for: 2_500_000), .city)
        XCTAssertEqual(CityDistrictMapStyle.city.updated(for: 3_500_000), .globe)
        XCTAssertEqual(CityDistrictMapStyle.city.updated(for: .nan), .city)
    }

    func testStreetNameHandOffWaitsForLocalCoverageAndKeepsRoadClearance() {
        func display(width: Double, coverage: Double, along: Double = 1.4, across: Double = 1.2)
            -> (along: Double, across: Double, opacity: Double) {
            CityStreetSurface.streetNameDisplay(glyphWidth: width, sceneCoverage: coverage,
                                                alongLimit: along, acrossLimit: across)
        }
        XCTAssertEqual(display(width: 8, coverage: 0.82).opacity, 0)
        XCTAssertEqual(display(width: 8, coverage: 0.90).opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(display(width: 8, coverage: 1).opacity, 1)
        let overview = display(width: 4.5, coverage: 1)
        XCTAssertEqual(overview.along, 1.4)
        XCTAssertEqual(overview.across, 1.2)
        XCTAssertGreaterThan(overview.opacity, 0.5)
        let street = display(width: 10, coverage: 1)
        XCTAssertEqual(street.along, 1)
        XCTAssertEqual(street.across, 1)
        XCTAssertEqual(display(width: 2, coverage: 1).opacity, 0)
    }

    func testPhotoPinZoomTracksDistanceContinuouslyInBothDirections() {
        let overview = CityDistrictCamera.overviewDistance
        let close = overview / 1.42
        let distance = [overview, overview - 25, 2_475, 2_390, 2_350, 2_240, close]
        let sizes = distance.map(CityPinArtwork.zoomPhotoDiameter)
        XCTAssertEqual(sizes.first, CityPinArtwork.photoDiameter)
        XCTAssertEqual(sizes.last, CityPinArtwork.expandedPhotoDiameter)
        XCTAssertTrue(zip(sizes, sizes.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(Array(distance.reversed().map(CityPinArtwork.zoomPhotoDiameter)), Array(sizes.reversed()))
        XCTAssertEqual(CityPinArtwork.zoomPhotoDiameter(distance: .nan), CityPinArtwork.photoDiameter)
        XCTAssertEqual(CityPinArtwork.zoomPhotoDiameter(distance: 1_450), CityPinArtwork.expandedPhotoDiameter)
        XCTAssertLessThan(CityPinArtwork.zoomPhotoDiameter(distance: 2_350)
                          - CityPinArtwork.zoomPhotoDiameter(distance: 2_351), 0.03)

        let anchor = CGPoint(x: 120, y: 270)
        for size in sizes {
            let badge = CityPinLabelLayout.badge(at: anchor, diameter: size)
            XCTAssertEqual(badge.width, size)
            XCTAssertEqual(badge.midX, anchor.x, accuracy: 0.0001)
            XCTAssertEqual(badge.maxY, anchor.y + 2, accuracy: 0.0001)
        }
    }

    func testUnsavedContextPinsFadeInAtTheExistingOwnershipThresholds() {
        func reveal(_ distance: Double, _ opacity: Double, primary: Bool) -> Double {
            CityDistrictCamera.contextPinReveal(distance: distance, sceneOpacity: opacity, primary: primary)
        }

        XCTAssertEqual(reveal(3_800, 1, primary: true), 0)
        XCTAssertEqual(reveal(3_600, 0, primary: true), 0.5, accuracy: 0.0001)
        XCTAssertEqual(reveal(3_400, 0, primary: true), 1)
        XCTAssertEqual(reveal(2_900, 0.5, primary: false), 0)
        XCTAssertEqual(reveal(2_900, 0.675, primary: false), 0.5, accuracy: 0.0001)
        XCTAssertEqual(reveal(2_900, 0.85, primary: false), 1, accuracy: 0.0001)
    }

    func testPinLabelsYieldToSelectionAndReturnWhenThereIsSpace() {
        let high = CityPinLabelLayout.Entry(id: "landmark", badge: CGRect(x: 20, y: 10, width: 40, height: 48),
                                           title: CGRect(x: 15, y: 64, width: 50, height: 17), reveal: 1, priority: 2)
        func lower(x: CGFloat) -> CityPinLabelLayout.Entry {
            .init(id: "nearby", badge: CGRect(x: x + 4, y: 10, width: 32, height: 40),
                  title: CGRect(x: x, y: 64, width: 40, height: 17), reveal: 1, priority: 0)
        }
        let overlapping = CityPinLabelLayout.titleOpacities([lower(x: 54), high], selectedBounds: [])
        XCTAssertEqual(overlapping["landmark"], 1)
        XCTAssertEqual(overlapping["nearby"], 0)
        let approaching = CityPinLabelLayout.titleOpacities([high, lower(x: 68)], selectedBounds: [])
        let opacity = approaching["nearby"] ?? 0
        XCTAssertGreaterThan(opacity, 0)
        XCTAssertLessThan(opacity, 1)
        let selected = CityPinLabelLayout.titleOpacities([high, lower(x: 90)], selectedBounds: [high.title])
        XCTAssertEqual(selected["landmark"], 0)
        XCTAssertEqual(selected["nearby"], 1)
    }

    func testNativePinchSwitchesStyleAfterTheGestureSettles() {
        let globe = CityDistrictMapStyle.globe
        XCTAssertEqual(globe.observing(distance: 2_300_000, settled: false, hasDestination: false), .globe)
        XCTAssertEqual(globe.observing(distance: 2_300_000, settled: true, hasDestination: false), .city)
        let city = CityDistrictMapStyle.city
        XCTAssertEqual(city.observing(distance: 4_000_000, settled: false, hasDestination: false), .city)
        XCTAssertEqual(city.observing(distance: 4_000_000, settled: true, hasDestination: false), .globe)
    }

    func testExplicitDestinationKeepsItsPreparedStyleThroughIntermediatePoses() {
        let towardTaipei = CityDistrictMapStyle.globe.updated(for: 2_900)
        XCTAssertEqual(towardTaipei, .city)
        XCTAssertEqual(towardTaipei.observing(distance: 36_000_000, settled: true, hasDestination: true), .city)
        let towardWorld = CityDistrictMapStyle.city.updated(for: 64_000_000)
        XCTAssertEqual(towardWorld, .globe)
        XCTAssertEqual(towardWorld.observing(distance: 2_900, settled: true, hasDestination: true), .globe)
    }

    func testOnlyTheSameNativeSampleCanRetainAProjectionDuringRefresh() {
        let camera = mapCamera()
        let valid = sample(camera, project: screenPoint)
        let missing = sample(camera) { _ in nil }
        XCTAssertNotNil(valid.projection)
        XCTAssertTrue(missing.needsProjectionRefresh)
        XCTAssertTrue(valid.canRetainProjection(for: missing))
        XCTAssertFalse(valid.canRetainProjection(for: sample(mapCamera(x: 25)) { _ in nil }))
        XCTAssertFalse(valid.canRetainProjection(for: sample(camera, revision: 2) { _ in nil }))
        XCTAssertFalse(valid.canRetainProjection(for: sample(camera, viewport: .init(width: 390, height: 844)) { _ in nil }))
        XCTAssertFalse(valid.canRetainProjection(for: sample(camera, registration: .init(latitudeOffset: 0, longitudeOffset: 0)) { _ in nil }))
        XCTAssertNotNil(sample(camera, project: screenPoint).projection)
    }

    func testSceneReadinessKeepsNativeMapVisibleWithoutMovingTheCamera() {
        let ready = sample(mapCamera(), project: screenPoint)
        XCTAssertGreaterThan(ready.opacity, 0)
        let preparing = ready.withSceneReadiness(false)
        XCTAssertEqual(preparing.opacity, 0)
        XCTAssertEqual(preparing.projection, ready.projection)
        XCTAssertEqual(preparing.mapCamera.centerCoordinate.latitude, ready.mapCamera.centerCoordinate.latitude)
        XCTAssertEqual(preparing.mapCamera.centerCoordinate.longitude, ready.mapCamera.centerCoordinate.longitude)
        XCTAssertEqual(preparing.withSceneReadiness(true), ready)
    }

    func testGlobeAndUnregisteredFramesKeepTheNativeSurface() {
        let camera = mapCamera()
        let globe = CityDistrictCamera(camera: camera, registration: registration, style: .globe, viewport: viewport) { _ in
            XCTFail("Globe samples must not fit district geometry")
            return nil
        }
        let unregistered = CityDistrictCamera(camera: camera, registration: nil, viewport: viewport, project: screenPoint)
        for frame in [globe, unregistered] {
            XCTAssertNil(frame.projection)
            XCTAssertEqual(frame.opacity, 0)
            XCTAssertTrue(frame.cloudPatches.isEmpty)
            XCTAssertFalse(frame.shouldPrewarm)
        }
    }

    func testDistrictCloudsThinAsTheCameraApproachesAndStayBehindTheSelectedPin() throws {
        let pin = CityDistrictCamera.Pin(id: "city-mvp:landmark-101", coordinate: mapCamera().centerCoordinate)
        let overview = sample(mapCamera(distance: CityDistrictCamera.overviewDistance), selected: pin, project: screenPoint)
        let transition = sample(mapCamera(distance: 3_650), selected: pin, project: screenPoint)
        let native = sample(mapCamera(distance: 4_300), selected: pin, project: screenPoint)
        let approaching = sample(mapCamera(distance: 2_350), selected: pin, project: screenPoint)
        let close = sample(mapCamera(distance: 1_450), selected: pin, project: screenPoint)
        XCTAssertEqual(overview.opacity, 1)
        XCTAssertFalse(overview.showsStreetDetail)
        XCTAssertGreaterThan(transition.opacity, 0)
        XCTAssertLessThan(transition.opacity, overview.opacity)
        XCTAssertEqual(native.opacity, 0)
        XCTAssertTrue(native.shouldPrewarm)
        XCTAssertTrue(close.showsStreetDetail)
        XCTAssertGreaterThan(transition.cloudOpacity, overview.cloudOpacity)
        XCTAssertGreaterThan(overview.cloudOpacity, approaching.cloudOpacity)
        XCTAssertGreaterThan(approaching.cloudOpacity, 0)
        XCTAssertEqual(close.cloudOpacity, 0)
        XCTAssertTrue(close.cloudPatches.isEmpty)
        XCTAssertEqual(overview.withSceneReadiness(false).cloudOpacity, 0)
        XCTAssertEqual(overview.cloudPatches.count, 3)
        let farCloud = try XCTUnwrap(native.cloudPatches.first)
        let nearCloud = try XCTUnwrap(approaching.cloudPatches.first)
        let district = screenPoint(pin.coordinate)
        XCTAssertGreaterThan(hypot(nearCloud.center.x - district.x, nearCloud.center.y - district.y),
                             hypot(farCloud.center.x - district.x, farCloud.center.y - district.y))
        XCTAssertLessThan(nearCloud.radius, farCloud.radius)
        for frame in [native, transition, overview, approaching, close] {
            XCTAssertEqual(frame.selectedOverlayPoint(for: pin), screenPoint(pin.coordinate))
        }

        let panned = sample(mapCamera(x: 80, distance: 2_900)) { coordinate in
            let point = self.screenPoint(coordinate)
            return CGPoint(x: point.x - 40, y: point.y + 20)
        }
        let originalPatch = try XCTUnwrap(overview.cloudPatches.first)
        let movedPatch = try XCTUnwrap(panned.cloudPatches.first)
        XCTAssertEqual(movedPatch.center.x, originalPatch.center.x - 40, accuracy: 0.001)
        XCTAssertEqual(movedPatch.center.y, originalPatch.center.y + 20, accuracy: 0.001)
        XCTAssertEqual(movedPatch.radius, originalPatch.radius, accuracy: 0.001)
        XCTAssertTrue(sample(mapCamera(x: 900, distance: 2_900), project: screenPoint).cloudPatches.isEmpty)
        XCTAssertTrue(sample(mapCamera(distance: 5_300), project: screenPoint).cloudPatches.isEmpty)
    }

    func testCloudBanksArriveBeforeScenePreparationAndSurvivePreparation() throws {
        let far = CityDistrictCamera(camera: mapCamera(distance: 9_500), registration: registration,
                                     viewport: viewport, cloudHandoff: true, project: screenPoint)
        XCTAssertFalse(far.shouldPrewarm)
        XCTAssertNil(far.projection)
        XCTAssertGreaterThan(far.cloudOpacity, 0)
        XCTAssertEqual(far.cloudPatches.count, 8)
        XCTAssertEqual(far.withSceneReadiness(false).cloudOpacity, far.cloudOpacity)
        let prepared = CityDistrictCamera(camera: mapCamera(distance: 8_500), registration: registration,
                                          viewport: viewport, cloudHandoff: true, project: screenPoint)
        XCTAssertTrue(prepared.shouldPrewarm)
        XCTAssertNotNil(prepared.projection)
        XCTAssertGreaterThan(prepared.cloudOpacity, far.cloudOpacity)
        XCTAssertEqual(prepared.opacity, 0, "Earlier geometry must not retime the existing pin-placement curve")
    }

    func testCloudHandoffRefreshesUnavailableNativeCoordinatesOutsideModelPreparation() {
        let camera = mapCamera(distance: 9_500)
        let pin = CityDistrictCamera.Pin(id: "landmark-101", coordinate: camera.centerCoordinate)
        let pending = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                        selectedPin: pin, cloudHandoff: true) { _ in nil }
        XCTAssertFalse(pending.shouldPrewarm)
        XCTAssertNil(pending.projection)
        XCTAssertNil(pending.selectedPlacement(for: pin))
        XCTAssertTrue(pending.needsProjectionRefresh,
                      "Missing native cloud/pin samples need the single layout retry even without model preparation")
        let settled = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                        selectedPin: pin, cloudHandoff: true, project: screenPoint)
        XCTAssertFalse(settled.needsProjectionRefresh)
        XCTAssertNotNil(settled.selectedPlacement(for: pin))
        XCTAssertFalse(settled.cloudPatches.isEmpty)
    }

    func testCloudHandoffRefreshesEachPartiallyUnavailableBoundaryBank() {
        let camera = mapCamera(distance: 9_500)
        let complete = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                         cloudHandoff: true, project: screenPoint)
        XCTAssertFalse(complete.shouldPrewarm)
        XCTAssertEqual(complete.cloudPatches.count, 8)
        XCTAssertFalse(complete.needsProjectionRefresh)
        // Each missing center independently exercises compactMap's partial-drop
        // path. No selected/context pin is missing and no model fit is requested.
        for missingBank in complete.cloudPatches {
            let partial = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                            cloudHandoff: true) { coordinate in
                let point = self.screenPoint(coordinate)
                return hypot(point.x - missingBank.center.x, point.y - missingBank.center.y) < 0.001 ? nil : point
            }
            XCTAssertNil(partial.projection)
            XCTAssertEqual(partial.cloudPatches.count, 7)
            XCTAssertTrue(partial.needsProjectionRefresh,
                          "A single missing boundary bank must request the existing one-shot layout refresh")
        }
        let restored = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                         cloudHandoff: true, project: screenPoint)
        XCTAssertEqual(restored.cloudPatches, complete.cloudPatches)
        XCTAssertFalse(restored.needsProjectionRefresh)
    }

    func testCloudBanksClearAtStreetScaleAndKeepLegacyPinCoordinates() {
        let pin = CityDistrictCamera.Pin(id: "landmark-101", coordinate: mapCamera().centerCoordinate,
                                        modelContact: CityLandmark101.pinContact)
        var previous = 1.0
        for distance in [8_000.0, 7_500, 5_000, 4_150, 2_900, 1_450] {
            let camera = mapCamera(distance: distance)
            let current = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                             selectedPin: pin, cloudHandoff: true, project: screenPoint)
            let legacy = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                            selectedPin: pin, cloudHandoff: false, project: screenPoint)
            XCTAssertLessThanOrEqual(current.cloudOpacity, previous)
            previous = current.cloudOpacity
            XCTAssertEqual(current.selectedPlacement(for: pin), legacy.selectedPlacement(for: pin))
            XCTAssertEqual(current.opacity, legacy.opacity)
        }
        XCTAssertEqual(previous, 0)
        XCTAssertEqual(CityDistrictCamera.cloudHandoffTone(distance: 9_000), 0)
        XCTAssertEqual(CityDistrictCamera.cloudHandoffTone(distance: 4_500), 1)
    }

    func testCloudBankPositionsFollowNativePanAndRotation() throws {
        let camera = mapCamera(distance: 8_000)
        let base = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                     cloudHandoff: true, project: screenPoint)
        let moved = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                      cloudHandoff: true) { coordinate in
            let point = self.screenPoint(coordinate)
            return CGPoint(x: point.x - 40, y: point.y + 20)
        }
        let rotated = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                        cloudHandoff: true) { coordinate in
            let point = self.screenPoint(coordinate)
            return CGPoint(x: -point.y, y: point.x)
        }
        let a = try XCTUnwrap(base.cloudPatches.first)
        let b = try XCTUnwrap(moved.cloudPatches.first)
        let c = try XCTUnwrap(rotated.cloudPatches.first)
        XCTAssertEqual(b.center.x, a.center.x - 40, accuracy: 0.001)
        XCTAssertEqual(b.center.y, a.center.y + 20, accuracy: 0.001)
        XCTAssertEqual(c.east.dx, -a.east.dy, accuracy: 0.001)
        XCTAssertEqual(c.east.dy, a.east.dx, accuracy: 0.001)
    }

    func testCloudHandoffStillExcludesGlobeAndUnregisteredMap() {
        let camera = mapCamera(distance: 8_000)
        for (style, anchor) in [(CityDistrictMapStyle.globe, Optional(registration)), (.city, nil)] {
            let frame = CityDistrictCamera(camera: camera, registration: anchor, style: style, viewport: viewport,
                                           cloudHandoff: true) { _ in
                XCTFail("No district projection without a registered city map")
                return nil
            }
            XCTAssertFalse(frame.shouldPrewarm)
            XCTAssertNil(frame.projection)
            XCTAssertEqual(frame.cloudOpacity, 0)
            XCTAssertTrue(frame.cloudPatches.isEmpty)
        }
    }

    func testCloudPatchesFollowRotationInsteadOfFacingTheScreen() throws {
        let camera = mapCamera(distance: 3_900)
        let baseline = sample(camera, project: screenPoint)
        let rotated = sample(camera) { coordinate in
            let point = self.screenPoint(coordinate)
            return CGPoint(x: -point.y, y: point.x)
        }
        let original = try XCTUnwrap(baseline.cloudPatches.first)
        let turned = try XCTUnwrap(rotated.cloudPatches.first)
        XCTAssertEqual(original.south.dy, original.east.dx * 0.78, accuracy: 0.001)
        XCTAssertEqual(turned.east.dx, -original.east.dy, accuracy: 0.001)
        XCTAssertEqual(turned.east.dy, original.east.dx, accuracy: 0.001)
        XCTAssertEqual(turned.south.dx, -original.south.dy, accuracy: 0.001)
        XCTAssertEqual(turned.south.dy, original.south.dx, accuracy: 0.001)
        XCTAssertEqual(turned.radius, original.radius, accuracy: 0.001)
    }

    func testPanningRetainsTheVisibleDistrictAfterTheCameraCenterLeavesIt() throws {
        let pitch = 41 * Double.pi / 180
        let eyeAxis = SIMD3(0, cos(pitch), sin(pitch))
        let right = SIMD3(1.0, 0, 0)
        let up = simd_cross(eyeAxis, right)
        let distance = 1_450.0
        func frame(x: Double) -> CityDistrictCamera {
            let camera = MapCamera(centerCoordinate: mapCamera(x: x).centerCoordinate,
                                   distance: distance, heading: 0, pitch: 41)
            return sample(camera) { coordinate in
                let offset = CityDistrictCamera.world(self.registration.sceneCoordinate(coordinate)) - SIMD3(x, 0, 0)
                let depth = distance - simd_dot(eyeAxis, offset)
                return CGPoint(x: 196 + 1_531 * simd_dot(right, offset) / depth,
                               y: 379 - 1_531 * simd_dot(up, offset) / depth)
            }
        }

        XCTAssertEqual(frame(x: 0).opacity, 1)
        let edge = frame(x: 680)
        let fit = try XCTUnwrap(edge.projection)
        XCTAssertGreaterThan(fit.visibleGroundFraction(in: viewport), 0.10)
        XCTAssertEqual(edge.opacity, 1, accuracy: 0.001)
        let receding = frame(x: 720)
        XCTAssertGreaterThan(receding.opacity, 0)
        XCTAssertLessThan(receding.opacity, edge.opacity)
        XCTAssertEqual(edge.withSceneReadiness(false).opacity, 0)
        XCTAssertEqual(frame(x: 1_100).opacity, 0)
    }

    func testSelectedAnchorFallsBackUntilItHasACurrentVisiblePoint() throws {
        let pin = CityDistrictCamera.Pin(id: "city-mvp:landmark-101", coordinate: mapCamera().centerCoordinate)
        let camera = mapCamera(distance: 2_900)
        XCTAssertNil(sample(camera, selected: pin) { _ in nil }.selectedOverlayPoint(for: pin))
        let updated = sample(camera, selected: pin, project: screenPoint)
        XCTAssertEqual(updated.selectedOverlayPoint(for: pin), screenPoint(pin.coordinate))
        let other = CityDistrictCamera.Pin(id: "different-selection", coordinate: pin.coordinate)
        XCTAssertNil(updated.selectedOverlayPoint(for: other))
        let offscreen = sample(camera, selected: pin) { _ in .init(x: -4, y: 390) }
        XCTAssertNil(offscreen.selectedOverlayPoint(for: pin))

        let close = sample(mapCamera(), selected: pin) { coordinate in
            self.isSame(coordinate, pin.coordinate) ? nil : self.screenPoint(coordinate)
        }
        XCTAssertNotNil(close.projection)
        let fittedAnchor = try XCTUnwrap(close.selectedOverlayPoint(for: pin))
        XCTAssertEqual(fittedAnchor.x, 201, accuracy: 0.01)
        XCTAssertEqual(fittedAnchor.y, 380, accuracy: 0.01)
    }

    func testUnselectedContextUsesTheSameSampleAsSelectedAndModeledAnchors() throws {
        let camera = mapCamera(distance: 3_650)
        let contact = CityLandmark101.pinContact
        let pin = CityDistrictCamera.Pin(id: "landmark-101", coordinate: camera.centerCoordinate,
                                        modelContact: contact)
        let frame = sample(camera, selected: pin, context: [pin], project: screenPoint)
        let context = try XCTUnwrap(frame.contextPlacement(for: pin))
        XCTAssertGreaterThan(frame.opacity, 0)
        XCTAssertLessThan(frame.opacity, 1)
        XCTAssertEqual(context, frame.selectedPlacement(for: pin))
        XCTAssertTrue(frame.ownsContextPin(pin))

        let preparing = frame.withSceneReadiness(false)
        XCTAssertEqual(preparing.contextPlacement(for: pin)?.point, screenPoint(pin.coordinate))
        XCTAssertEqual(preparing.contextPlacement(for: pin)?.contactOpacity, 0)

        let moved = CityDistrictCamera.Pin(id: pin.id, coordinate: mapCamera(x: 12).centerCoordinate)
        XCTAssertNil(frame.contextPlacement(for: moved))
        XCTAssertFalse(frame.ownsContextPin(moved))
        let missingProjection = sample(camera, selected: pin, context: [moved]) { _ in nil }
        XCTAssertTrue(missingProjection.needsProjectionRefresh)
        XCTAssertFalse(frame.canRetainProjection(for: missingProjection))
        XCTAssertFalse(missingProjection.ownsContextPin(moved))
        XCTAssertNil(missingProjection.contextPlacement(for: moved))
    }

    func testVisibleLandmarkRejectsADeceptivelyGoodLocalFit() {
        let camera = mapCamera(x: 350)
        let landmark = mapCamera().centerCoordinate
        let baseline = sample(camera, project: screenPoint)
        XCTAssertNotNil(baseline.projection)
        let misregistered = sample(camera) { coordinate in
            let point = self.screenPoint(coordinate)
            return self.isSame(coordinate, landmark) ? .init(x: point.x + 12, y: point.y) : point
        }
        XCTAssertGreaterThan(misregistered.requestedOpacity, 0)
        XCTAssertNil(misregistered.projection)
    }

    func testCornerFitRecoversPitchFromTheMapGroundAndChecksHoldouts() throws {
        // A native corner trace reports 49° while its ground points fit 40.59°.
        let nativeDistance = 658.27147477
        let measuredPitch = 40.5922 * Double.pi / 180
        let measuredDistance = 590.848
        let focal = 1642.225
        let coordinate = CityStreetDetail.cityHall
        let target = CityDistrictCamera.world(coordinate)
        let camera = MapCamera(centerCoordinate: registration.mapCoordinate(coordinate),
                               distance: nativeDistance, heading: 0, pitch: 49)
        func project(_ coordinate: CLLocationCoordinate2D, holdoutShift: Double) -> CGPoint {
            let offset = CityDistrictCamera.world(registration.sceneCoordinate(coordinate)) - target
            let depth = measuredDistance - sin(measuredPitch) * offset.z
            let holdout = offset.x > 50 && offset.x < 58 && offset.z < -95
            return .init(x: 195.94 + focal * offset.x / depth + (holdout ? holdoutShift : 0),
                         y: 379.21 + focal * cos(measuredPitch) * offset.z / depth)
        }
        let frame = sample(camera) { project($0, holdoutShift: 0) }
        let projection = try XCTUnwrap(frame.projection)
        XCTAssertLessThan(projection.error, 0.01)
        XCTAssertEqual(projection.focalLength, focal, accuracy: 0.01)
        XCTAssertTrue(frame.showsStreetDetail)
        let inconsistent = sample(camera) { project($0, holdoutShift: 15) }
        XCTAssertNil(inconsistent.projection)
    }

    func testCornerFitFollowsTheOnscreenTurnBeforeTheReportedHeadingSettles() throws {
        let reported = MapCamera(centerCoordinate: mapCamera().centerCoordinate, distance: 500,
                                 heading: 180, pitch: 49)
        let heading = 74.6 * Double.pi / 180
        let pitch = 50.7 * Double.pi / 180
        let right = SIMD3(cos(heading), 0, sin(heading))
        let eyeAxis = SIMD3(-sin(heading) * sin(pitch), cos(pitch), cos(heading) * sin(pitch))
        let up = simd_cross(eyeAxis, right)
        func project(_ coordinate: CLLocationCoordinate2D, shiftHoldout: Bool) -> CGPoint {
            let offset = CityDistrictCamera.world(registration.sceneCoordinate(coordinate))
            let depth = 532 - simd_dot(eyeAxis, offset)
            let shift = shiftHoldout && offset.x > 38 && offset.x < 45 && offset.z < -70 ? 15.0 : 0
            return .init(x: 196 + 1_530 * simd_dot(right, offset) / depth + shift,
                         y: 379 - 1_530 * simd_dot(up, offset) / depth)
        }
        let fitted = sample(reported) { project($0, shiftHoldout: false) }
        let projection = try XCTUnwrap(fitted.projection)
        XCTAssertEqual(fitted.opacity, 1)
        XCTAssertLessThan(projection.error, 0.01)
        XCTAssertLessThan(simd_length(projection.eye - eyeAxis * 532), 0.02)
        let inconsistent = sample(reported) { project($0, shiftHoldout: true) }
        XCTAssertNil(inconsistent.projection, "A heading recovery must still match both holdouts")
    }

    func testCityHallPinUsesTheModeledRoofWithTheSameGeographicIdentity() throws {
        let place = try XCTUnwrap(CityMVPPlaceBridge.context.first { $0.id == CityMVPPlaceBridge.cityHallID })
        XCTAssertEqual(place.id, "way/142113976")
        XCTAssertEqual(place.x, -5.1, accuracy: 0.1)
        XCTAssertEqual(place.z, -397.5, accuracy: 0.1)
        let pin = CityMVPPlaceBridge.contextPin(for: place, registration: registration)
        let flat = sample(mapCamera(distance: 4_300), cityHall: pin, project: screenPoint)
        XCTAssertFalse(CityMVPPlaceBridge.showsContextPin(place.id, in: flat))
        XCTAssertNil(flat.cityHallOverlayPoint(for: pin))
        let overview = sample(mapCamera(distance: CityDistrictCamera.overviewDistance), cityHall: pin, project: screenPoint)
        XCTAssertFalse(CityMVPPlaceBridge.showsContextPin(place.id, in: overview), "Public City Hall is an ordinary sourced label, while its selected roof contact remains valid")
        let contact = try XCTUnwrap(pin.modelContact)
        XCTAssertEqual(contact.y, 38.4, accuracy: 0.001)
        XCTAssertEqual(overview.cityHallOverlayPoint(for: pin), try XCTUnwrap(overview.projection).point(at: contact))
        let close = sample(mapCamera(), cityHall: pin, project: screenPoint)
        XCTAssertEqual(close.cityHallOverlayPoint(for: pin), try XCTUnwrap(close.projection).point(at: contact))
    }

    func testSelectedLandmarkContactBlendsFromNativeAndKeepsItsIdentity() throws {
        let coordinate = mapCamera().centerCoordinate
        let pin = CityDistrictCamera.Pin(id: "landmark-101", coordinate: coordinate,
                                        modelContact: CityLandmark101.pinContact)
        let transitioning = sample(mapCamera(distance: 3_650), selected: pin, project: screenPoint)
        let placement = try XCTUnwrap(transitioning.selectedPlacement(for: pin))
        let surface = try XCTUnwrap(transitioning.projection?.point(at: CityLandmark101.pinContact))
        let native = screenPoint(coordinate)
        XCTAssertGreaterThan(transitioning.opacity, 0)
        XCTAssertLessThan(transitioning.opacity, 1)
        let blend = try XCTUnwrap(transitioning.sceneBlend)
        let reveal = blend.opacity(at: surface)
        XCTAssertGreaterThan(reveal, transitioning.opacity)
        XCTAssertEqual(placement.contactOpacity, reveal)
        XCTAssertEqual(placement.point.x, native.x + (surface.x - native.x) * reveal, accuracy: 0.001)
        XCTAssertEqual(placement.point.y, native.y + (surface.y - native.y) * reveal, accuracy: 0.001)
        XCTAssertGreaterThan(blend.opacity(at: blend.center), transitioning.opacity)
        XCTAssertLessThan(blend.opacity(at: CGPoint(x: blend.center.x + blend.outerRadius, y: blend.center.y)),
                          transitioning.opacity)
        XCTAssertNotEqual(placement.point, native)
        let unready = transitioning.withSceneReadiness(false)
        XCTAssertEqual(unready.selectedOverlayPoint(for: pin), native)
        XCTAssertEqual(unready.sceneLayerOpacity, 0)
        XCTAssertEqual(unready.sceneBlend?.outerStrength, blend.outerStrength)
        XCTAssertEqual(unready.sceneBlend?.innerRadius, blend.innerRadius)
        let full = sample(mapCamera(distance: 2_900), selected: pin, project: screenPoint)
        XCTAssertEqual(full.selectedOverlayPoint(for: pin), full.projection?.point(at: CityLandmark101.pinContact))
        XCTAssertEqual(full.selectedPlacement(for: pin)?.contactOpacity, 1)
        XCTAssertNil(full.selectedPlacement(for: .init(id: "different", coordinate: coordinate)))
    }

    func testRoofBehindCameraKeepsOwnershipWithoutDrawingAFalseGroundPin() throws {
        let camera = mapCamera(x: -180, distance: 60)
        let pin = CityDistrictCamera.Pin(id: "high-roof", coordinate: camera.centerCoordinate,
                                        modelContact: SIMD3(-180, 85, 0))
        let frame = sample(camera, selected: pin) { coordinate in
            let p = CityDistrictCamera.world(self.registration.sceneCoordinate(coordinate))
            return CGPoint(x: 201 + (p.x + 180) * 5, y: 380 + p.z * 5)
        }
        XCTAssertEqual(frame.opacity, 1)
        XCTAssertNil(try XCTUnwrap(frame.projection).point(at: try XCTUnwrap(pin.modelContact)))
        XCTAssertNil(frame.selectedPlacement(for: pin))
        XCTAssertTrue(frame.ownsSelectedPin(pin))
        let unready = frame.withSceneReadiness(false)
        let point = try XCTUnwrap(unready.selectedOverlayPoint(for: pin))
        XCTAssertEqual(point.x, 201, accuracy: 0.001)
        XCTAssertEqual(point.y, 380, accuracy: 0.001)
    }

    func testModelContactKeepsCorrectedCoordinatesAndHidesTheFarPodiumRing() {
        let original = CityDistrictCamera.coordinate(x: 0, z: 0)
        XCTAssertEqual(CityMVPPlaceBridge.modelContact(for: "landmark-101", at: original), CityLandmark101.pinContact)
        XCTAssertNil(CityMVPPlaceBridge.modelContact(for: "landmark-101", at: CityDistrictCamera.coordinate(x: 2, z: 0)))
        XCTAssertTrue(CityLandmark101.hidesPinContact(from: SIMD3(0, 1_025, -1_000)))
        XCTAssertFalse(CityLandmark101.hidesPinContact(from: SIMD3(0, 1_025, 1_000)))
        XCTAssertFalse(CityLandmark101.hidesPinContact(from: SIMD3(1_000, 1_025, -100)))
    }

    func testCivicApproachInsideTaipei101FallsBackUntilTheEyeIsClear() throws {
        let center = registration.mapCoordinate(CityMVPPlaceBridge.cityHallCoordinate)
        let pin = CityDistrictCamera.Pin(id: CityMVPPlaceBridge.cityHallID, coordinate: center)
        let blocked = civicApproach(center: center, pin: pin, heading: 0)
        XCTAssertEqual(blocked.requestedOpacity, 1)
        XCTAssertEqual(blocked.opacity, 0)
        XCTAssertNil(blocked.projection)
        XCTAssertFalse(blocked.needsProjectionRefresh)
        XCTAssertNil(blocked.cityHallOverlayPoint(for: pin))
        XCTAssertEqual(blocked.latitude, center.latitude)
        XCTAssertEqual(blocked.longitude, center.longitude)
        XCTAssertEqual(blocked.distance, 550)

        let clear = civicApproach(center: center, pin: pin, heading: 180)
        let projection = try XCTUnwrap(clear.projection)
        XCTAssertEqual(projection.eye.z, -812.59, accuracy: 1)
        XCTAssertLessThan(projection.error, 0.1)
        XCTAssertEqual(clear.opacity, 1)
        XCTAssertEqual(clear.cityHallOverlayPoint(for: pin), CGPoint(x: 201, y: 380))
    }

    private func civicApproach(center: CLLocationCoordinate2D, pin: CityDistrictCamera.Pin,
                               heading: Double) -> CityDistrictCamera {
        let camera = MapCamera(centerCoordinate: center, distance: 550, heading: heading, pitch: 49)
        let target = CityDistrictCamera.world(registration.sceneCoordinate(center))
        let direction = heading == 0 ? 1.0 : -1.0
        let pitch = 49.0 * .pi / 180
        return sample(camera, cityHall: pin) { coordinate in
            let point = CityDistrictCamera.world(self.registration.sceneCoordinate(coordinate)) - target
            let depth = 550 - direction * sin(pitch) * point.z
            guard depth > 2 else { return nil }
            return CGPoint(x: 201 + 500 * direction * point.x / depth,
                           y: 380 + 500 * direction * cos(pitch) * point.z / depth)
        }
    }

    func testRegistrationObservationIsOptInAndDoesNotChangeTheFrame() throws {
        let camera = mapCamera()
        var ordinaryCalls = 0
        let ordinary = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport) {
            ordinaryCalls += 1; return self.screenPoint($0)
        }
        var inspectedCalls = 0
        let inspected = CityDistrictCamera(camera: camera, registration: registration, viewport: viewport,
                                          inspectRegistration: true) {
            inspectedCalls += 1; return self.screenPoint($0)
        }
        XCTAssertNil(ordinary.registrationInspection)
        let observation = try XCTUnwrap(inspected.registrationInspection)
        XCTAssertEqual(inspectedCalls, ordinaryCalls + 2)
        XCTAssertEqual(observation.latitudeOffset, registration.latitudeOffset)
        XCTAssertEqual(observation.longitudeOffset, registration.longitudeOffset)
        XCTAssertEqual(observation.provenance, "live-search")
        let source = CityDistrictCamera.coordinate(x: 0, z: 0)
        XCTAssertEqual(observation.sourcePoint, screenPoint(source))
        XCTAssertEqual(observation.registeredPoint, screenPoint(registration.mapCoordinate(source)))
        XCTAssertNotEqual(observation.sourcePoint, observation.registeredPoint)
        XCTAssertEqual(inspected.projection, ordinary.projection)
        XCTAssertEqual(inspected.opacity, ordinary.opacity)
        XCTAssertEqual(inspected.cloudPatches, ordinary.cloudPatches)
        XCTAssertEqual(inspected.mapCamera, ordinary.mapCamera)
    }

    func testRegistrationObservationPreservesUnavailableAndOffscreenNativePoints() throws {
        let origin = CityDistrictCamera.coordinate(x: 0, z: 0)
        let frame = CityDistrictCamera(camera: mapCamera(), registration: registration, viewport: viewport,
                                       inspectRegistration: true) { coordinate in
            self.isSame(coordinate, origin) ? CGPoint(x: CGFloat.infinity, y: 2) : CGPoint(x: -500, y: 2_000)
        }
        let observation = try XCTUnwrap(frame.registrationInspection)
        XCTAssertNil(observation.sourcePoint)
        XCTAssertEqual(observation.registeredPoint, CGPoint(x: -500, y: 2_000))
        var calls = 0
        let unresolved = CityDistrictCamera(camera: mapCamera(), registration: nil, viewport: viewport,
                                            inspectRegistration: true) { _ in calls += 1; return nil }
        XCTAssertNil(unresolved.registrationInspection)
        XCTAssertEqual(calls, 0)
    }

    private func mapCamera(x: Double = 0, distance: Double = 1_450) -> MapCamera {
        MapCamera(centerCoordinate: registration.mapCoordinate(CityDistrictCamera.coordinate(x: x, z: 0)),
                  distance: distance, heading: 0, pitch: 0)
    }

    private func sample(_ camera: MapCamera, revision: Int = 1, viewport: CGSize? = nil,
                        registration: CityDistrictRegistration? = nil, selected: CityDistrictCamera.Pin? = nil,
                        cityHall: CityDistrictCamera.Pin? = nil, context: [CityDistrictCamera.Pin] = [],
                        project: (CLLocationCoordinate2D) -> CGPoint?) -> CityDistrictCamera {
        CityDistrictCamera(camera: camera, registration: registration ?? self.registration, styleRevision: revision,
                           viewport: viewport ?? self.viewport, selectedPin: selected, cityHallPin: cityHall,
                           contextPins: context, project: project)
    }

    private func screenPoint(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        let point = CityDistrictCamera.world(registration.sceneCoordinate(coordinate))
        return .init(x: 201 + point.x / 3, y: 380 + point.z / 3)
    }

    private func isSame(_ left: CLLocationCoordinate2D, _ right: CLLocationCoordinate2D) -> Bool {
        abs(left.latitude - right.latitude) < 1e-10 && abs(left.longitude - right.longitude) < 1e-10
    }
}
