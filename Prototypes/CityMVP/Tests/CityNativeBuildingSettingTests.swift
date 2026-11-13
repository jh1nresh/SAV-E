import XCTest
import UIKit
import MapKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

/// Adapter lifecycle tests with an explicitly writable flag test double.
/// These do NOT establish real MapKit setter compatibility or rendering;
/// the separate native UI experiment retains its observed negative result.
@MainActor
final class CityNativeBuildingSettingTests: XCTestCase {
    func testDetachRestoresAndPublishesNewUnboundGeneration() async {
        let initial = expectation(description: "Initial bound getter")
        let detached = expectation(description: "Detached binding invalidation")
        var records: [CityNativeBuildingSettingRecord] = []
        var receivedInitial = false
        var receivedDetach = false
        let fixture = makeFixture { record in
            records.append(record)
            if record.bound && !receivedInitial {
                receivedInitial = true
                initial.fulfill()
            } else if receivedInitial && record.invalidated && !receivedDetach {
                receivedDetach = true
                detached.fulfill()
            }
        }
        defer { fixture.window.isHidden = true }
        await fulfillment(of: [initial], timeout: 3)
        guard let first = records.last(where: \.bound) else { return XCTFail("Missing initial readback") }
        XCTAssertEqual(first.actual, false)
        XCTAssertEqual(first.offApplications, 1)

        fixture.host.removeFromSuperview()
        XCTAssertEqual(fixture.map.showsBuildings, fixture.original)
        await fulfillment(of: [detached], timeout: 3)
        guard let last = records.last else { return XCTFail("Missing detach event") }
        XCTAssertFalse(last.bound)
        XCTAssertTrue(last.invalidated)
        XCTAssertGreaterThan(last.bindingGeneration, first.bindingGeneration)
        XCTAssertNil(last.actual)
        XCTAssertEqual(last.restorations, 1)
    }

    func testReplacementRejectsQueuedOldBindingCallbacksAndRestoresOldMap() async {
        let replacementRead = expectation(description: "Only replacement binding publishes")
        var records: [CityNativeBuildingSettingRecord] = []
        var received = false
        let fixture = makeFixture { record in
            records.append(record)
            if record.bound && !received {
                received = true
                replacementRead.fulfill()
            }
        }
        defer { fixture.window.isHidden = true }
        // The initial invalidation/read are queued on main, but have not run:
        // this actor does not yield until after replacing the target map.
        fixture.map.removeFromSuperview()
        let replacement = WritableBuildingFlagMapView(frame: fixture.root.bounds)
        fixture.root.insertSubview(replacement, belowSubview: fixture.host)
        fixture.host.setNeedsLayout()
        fixture.host.layoutIfNeeded()
        XCTAssertEqual(fixture.map.showsBuildings, fixture.original)
        XCTAssertFalse(replacement.showsBuildings)

        // The stale queued read first clears readbackScheduled and requests a
        // fresh layout. This non-key test window has no guaranteed render pass
        // while XCTest awaits, so service exactly one later main-loop layout.
        let host = fixture.host
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                host.layoutIfNeeded()
                continuation.resume()
            }
        }
        await fulfillment(of: [replacementRead], timeout: 3)
        guard let last = records.last(where: \.bound) else { return XCTFail("Missing replacement read") }
        XCTAssertGreaterThan(last.bindingGeneration, 1)
        XCTAssertEqual(last.actual, false)
        XCTAssertEqual(last.offApplications, 2)
        XCTAssertEqual(last.restorations, 1)
        XCTAssertFalse(records.contains { $0.bindingGeneration < last.bindingGeneration },
                       "Queued callbacks from the old binding must be rejected, including invalidations")
    }

    func testGetterOverwriteIsReportedWithoutAnotherFalseWrite() async {
        let initial = expectation(description: "Initial false getter")
        let overwritten = expectation(description: "External overwrite remains observable")
        var receivedInitial = false
        var receivedOverwrite = false
        var final: CityNativeBuildingSettingRecord?
        let fixture = makeFixture { record in
            if record.bound && record.actual == false && !receivedInitial {
                receivedInitial = true
                initial.fulfill()
            } else if receivedInitial && record.bound && record.actual == true && !receivedOverwrite {
                receivedOverwrite = true
                final = record
                overwritten.fulfill()
            }
        }
        defer { fixture.window.isHidden = true }
        await fulfillment(of: [initial], timeout: 3)
        // Controlled external overwrite of the test double's stored flag.
        // This does not assert that the real SDK honors the same setter.
        fixture.map.showsBuildings = true
        fixture.host.setNeedsLayout()
        fixture.host.layoutIfNeeded()
        await fulfillment(of: [overwritten], timeout: 3)
        XCTAssertTrue(fixture.map.showsBuildings)
        XCTAssertEqual(final?.actual, true)
        XCTAssertEqual(final?.requested, false)
        XCTAssertEqual(final?.offApplications, 1, "Lifecycle/readback must not silently reapply the requested value")
    }

    private struct Fixture {
        let window: UIWindow
        let root: UIView
        let map: WritableBuildingFlagMapView
        let host: CityNativeBuildingSettingHost
        let original: Bool
    }
    private func makeFixture(onRecord: @escaping (CityNativeBuildingSettingRecord) -> Void) -> Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let controller = UIViewController()
        window.rootViewController = controller
        let root = controller.view!
        root.frame = window.bounds
        let map = WritableBuildingFlagMapView(frame: root.bounds)
        let original = map.showsBuildings
        let host = CityNativeBuildingSettingHost(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        host.configure(off: true, cameraReady: true, revision: 10, onRecord: onRecord)
        root.addSubview(map)
        root.addSubview(host)
        window.isHidden = false
        host.setNeedsLayout()
        host.layoutIfNeeded()
        return Fixture(window: window, root: root, map: map, host: host, original: original)
    }
}

/// Public-type discovery still exercises MKMapView subclass binding, while
/// this stored Bool isolates lifecycle/restore behavior from the SDK's flag.
@MainActor
private final class WritableBuildingFlagMapView: MKMapView {
    private var buildingFlag = true
    override var showsBuildings: Bool {
        get { buildingFlag }
        set { buildingFlag = newValue }
    }
}
