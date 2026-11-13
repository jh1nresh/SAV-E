import CoreLocation
import MapKit
import SwiftUI
import XCTest
@testable import SAVE

@MainActor
final class SavvyMapRegionTests: XCTestCase {
    func testCatalogHasStableUniqueIDsAndExplicitRenderers() {
        XCTAssertEqual(SavvyMapRegion.catalog.map(\.id), [.world, .taipeiXinyi, .shanghai])
        XCTAssertEqual(Set(SavvyMapRegion.catalog.map(\.id)).count, 3)
        XCTAssertEqual(SavvyMapRegion.region(for: .world).requestedRenderer, .appleMaps)
        XCTAssertEqual(SavvyMapRegion.region(for: .taipeiXinyi).requestedRenderer, .appleMaps)
        XCTAssertEqual(SavvyMapRegion.region(for: .shanghai).requestedRenderer, .amap)
        XCTAssertTrue(SavvyMapRegion.catalog.allSatisfy { $0.appleDataProviderPolicy == .selectedByMapKit })
    }

    func testWorldAndXinyiCamerasKeepExistingNumerics() throws {
        let world = try XCTUnwrap(SavvyMapRegion.world.camera)
        assertCamera(world, latitude: 25.033968, longitude: 121.564468,
                     distance: 64_000_000, heading: 0, pitch: 0)
        let taipei = try XCTUnwrap(SavvyMapRegion.taipeiXinyi.camera)
        assertCamera(taipei, latitude: 25.033968 + 175 / 111_195,
                     longitude: 121.564468 - 15 / 100_850,
                     distance: 2_900, heading: 20, pitch: 35)
        XCTAssertEqual(taipei.centerCoordinate.latitude, CityMVPCameras.taipei.centerCoordinate.latitude)
        XCTAssertEqual(taipei.centerCoordinate.longitude, CityMVPCameras.taipei.centerCoordinate.longitude)
        XCTAssertEqual(taipei.distance, CityMVPCameras.taipei.distance)
    }

    func testXinyiCoverageDescribesExistingSourceAndOpaqueGround() throws {
        let coverage = try XCTUnwrap(SavvyMapRegion.taipeiXinyi.authoredCoverage)
        XCTAssertEqual(coverage.regionID, .taipeiXinyi)
        XCTAssertEqual(coverage.sceneID, "taipei-xinyi-101-city-hall")
        XCTAssertEqual(coverage.bounds.south, 25.033968 - 700 / 111_195, accuracy: 1e-10)
        XCTAssertEqual(coverage.bounds.north, 25.033968 + 568 / 111_195, accuracy: 1e-10)
        XCTAssertEqual(coverage.bounds.west, 121.564468 - 700 / 100_850, accuracy: 1e-10)
        XCTAssertEqual(coverage.bounds.east, 121.564468 + 700 / 100_850, accuracy: 1e-10)
        XCTAssertEqual(coverage.opaqueGroundBounds.south, 25.033968 - 550 / 111_195, accuracy: 1e-10)
        XCTAssertEqual(coverage.opaqueGroundBounds.north, 25.033968 + 518 / 111_195, accuracy: 1e-10)
        XCTAssertTrue(coverage.bounds.contains(CityDistrictCamera.coordinate(x: 0, z: 0)))
        XCTAssertFalse(coverage.bounds.contains(CityDistrictCamera.coordinate(x: 701, z: 0)))
        XCTAssertFalse(coverage.bounds.contains(CityDistrictCamera.coordinate(x: 0, z: -569)))
        XCTAssertFalse(coverage.bounds.contains(.init(latitude: .nan, longitude: 121.564468)))
        XCTAssertNil(SavvyMapRegion.world.authoredCoverage)
        XCTAssertNil(SavvyMapRegion.shanghai.authoredCoverage)
        XCTAssertNil(SavvyMapRegion.shanghai.camera)
    }

    func testOnlyShanghaiRoutesToPendingAmapForEveryConfigurationState() {
        let statuses: [CityMVPConfiguration.AmapStatus] = [.missingKey, .bundleMismatch, .sdkNotConnected]
        for status in statuses {
            for id in [SavvyMapRegion.ID.world, .taipeiXinyi] {
                guard case let .appleMaps(region) = SavvyMapRegion.selection(for: id, amapStatus: status) else {
                    return XCTFail("Apple renderer selection must not depend on Amap configuration")
                }
                XCTAssertEqual(region.id, id)
            }
            guard case let .amapPending(region, actualStatus) = SavvyMapRegion.selection(for: .shanghai, amapStatus: status) else {
                return XCTFail("Shanghai must retain its unconnected SDK boundary")
            }
            XCTAssertEqual(region.id, .shanghai)
            XCTAssertEqual(actualStatus, status)
            XCTAssertNil(region.authoredCoverage)
        }
    }

    func testMissingMainAppAmapConfigurationStaysPending() {
        let status = CityMVPConfiguration.amapStatus(values: nil, bundleID: "com.wanderly.app")
        XCTAssertEqual(status, .missingKey)
        guard case let .amapPending(region, actualStatus) = SavvyMapRegion.selection(for: .shanghai, amapStatus: status) else {
            return XCTFail("Missing main-app credentials cannot open an Amap renderer")
        }
        XCTAssertEqual(actualStatus, .missingKey)
        XCTAssertEqual(region.id, .shanghai)
        XCTAssertNil(region.camera)
        XCTAssertNil(region.authoredCoverage)
    }

    private func assertCamera(_ camera: MapCamera, latitude: Double, longitude: Double,
                              distance: Double, heading: Double, pitch: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(camera.centerCoordinate.latitude, latitude, accuracy: 1e-10, file: file, line: line)
        XCTAssertEqual(camera.centerCoordinate.longitude, longitude, accuracy: 1e-10, file: file, line: line)
        XCTAssertEqual(camera.distance, distance, file: file, line: line)
        XCTAssertEqual(camera.heading, heading, file: file, line: line)
        XCTAssertEqual(camera.pitch, pitch, file: file, line: line)
    }
}
