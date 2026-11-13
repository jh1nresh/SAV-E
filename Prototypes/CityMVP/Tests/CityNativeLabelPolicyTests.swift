import XCTest
import MapKit
import SwiftUI
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityNativeLabelPolicyTests: XCTestCase {
    private let registration = CityDistrictRegistration(latitudeOffset: -0.003, longitudeOffset: 0.004)
    private func update(_ mode: CityNativeLabelPolicy, x: Double = 0, z: Double = 0,
                        distance: Double = 5_000, settled: Bool = true,
                        ready: Bool = true, projection: Bool = true,
                        style: CityDistrictMapStyle = .city) -> CityNativeLabelPolicy {
        let coordinate = registration.mapCoordinate(CityDistrictCamera.coordinate(x: x, z: z))
        return mode.updated(camera: MapCamera(centerCoordinate: coordinate, distance: distance, heading: 20, pitch: 35),
                            registration: registration, style: style, sceneReady: ready,
                            projectionAvailable: projection, settled: settled)
    }

    func testRegisteredDistrictBoundsHaveADeadBand() {
        // Without reversing the provider registration, this point would be >1km east.
        XCTAssertEqual(update(.native, x: 649, z: 100), .district)
        XCTAssertEqual(update(.native, x: 651), .native)
        XCTAssertEqual(update(.district, x: 651), .district)
        XCTAssertEqual(update(.district, x: 849), .district)
        XCTAssertEqual(update(.district, x: 851), .native)
        XCTAssertEqual(update(.district, z: -851), .native)
        XCTAssertEqual(update(.native, x: -649, z: 649), .district)
    }

    func testZoomBoundsRestoreNativeLabelsBeforeTheSceneDisappears() {
        XCTAssertEqual(update(.native, distance: 8_500), .district)
        XCTAssertEqual(update(.native, distance: 8_700), .native)
        XCTAssertEqual(update(.district, distance: 8_700), .district)
        XCTAssertEqual(update(.district, distance: 9_000), .native)
    }

    func testContinuousGestureDoesNotSwitchNativeConfiguration() {
        XCTAssertEqual(update(.district, x: 1_000, settled: false), .district)
        XCTAssertEqual(update(.native, x: 0, settled: false), .native)
        XCTAssertEqual(update(.district, x: 1_000, settled: true), .native)
        XCTAssertEqual(update(.native, x: 0, settled: true), .district)
    }

    func testUnavailableSceneOrGlobeNeverSuppressesNativePlaces() {
        XCTAssertEqual(update(.district, settled: false, ready: false), .native)
        XCTAssertEqual(update(.district, projection: false), .district)
        XCTAssertEqual(update(.native, projection: false), .native)
        XCTAssertEqual(update(.district, x: 1_000, projection: false), .native)
        XCTAssertEqual(update(.district, style: .globe), .native)
        let camera = MapCamera(centerCoordinate: .init(latitude: 25, longitude: 121), distance: 5_000)
        XCTAssertEqual(CityNativeLabelPolicy.district.updated(camera: camera, registration: nil, style: .city,
            sceneReady: true, projectionAvailable: true, settled: true), .native)
    }
}
