import XCTest
import UIKit

/// Collects timing evidence; a passing collection is not a fluidity or resume PASS.
final class CityLatencyObservationVisualTests: XCTestCase {
    private enum Failure: Error { case missingState, notReady }

    @MainActor
    func testTimeNativeSceneAccessibilityReadsWithoutPredicatePolling() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let id = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LATENCY_TEST_ID"])
        let enabled = ProcessInfo.processInfo.environment["CITY_LATENCY_OBSERVATION"] == "enabled"
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"] + (enabled ? ["--inspect-citylab-latency"] : [])
        app.launchEnvironment["CITY_LATENCY_TEST_ID"] = id
        app.launch()
        defer { app.terminate() }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        var measurements: [[String: Any]] = []
        func read(_ phase: String) throws -> [String: Any] {
            let began = ProcessInfo.processInfo.systemUptime
            let raw = inspector.value as? String
            let ended = ProcessInfo.processInfo.systemUptime
            let state = raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            var measurement: [String: Any] = ["phase": phase, "begin": began, "end": ended,
                "seconds": ended - began, "probeEnabled": enabled, "parsed": state != nil]
            if let state {
                var camera: [String: Double] = [:]
                for key in ["latitude", "longitude", "distance", "heading", "pitch"] { camera[key] = state[key] as? Double }
                measurement["camera"] = camera
                measurement["sceneReady"] = state["sceneReady"] as? Bool ?? false
                measurement["projectionAvailable"] = state["projectionAvailable"] as? Bool ?? false
            }
            measurements.append(measurement)
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: measurements, options: .sortedKeys),
                                           uniformTypeIdentifier: "public.json")
            attachment.name = "latency-reads-" + phase; attachment.lifetime = .keepAlways; add(attachment)
            guard let state else { XCTFail("Missing sampled inspection; timings retained"); throw Failure.missingState }
            XCTAssertEqual(state["route"] as? String, "preview")
            XCTAssertEqual(state["trace"] as? Bool, false)
            return state
        }
        let first = try read("world")
        let count = try XCTUnwrap(first["savedCount"] as? Int)
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let deadline = Date().addingTimeInterval(60)
        var ready: [String: Any]?
        for index in 0..<12 {
            guard Date() < deadline else { break }
            let state = try read("preparing-\(index)")
            if state["sceneReady"] as? Bool == true && state["projectionAvailable"] as? Bool == true {
                ready = state; break
            }
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(5)))
        }
        guard let before = ready else {
            let failure = XCTAttachment(screenshot: app.screenshot())
            failure.name = "latency-readiness-failure"; failure.lifetime = .keepAlways; add(failure)
            XCTFail("No real scene/projection readiness within collection budget"); throw Failure.notReady
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.32))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.45)))
        var moved = false
        for index in 0..<3 {
            let state = try read("after-pan-\(index)")
            XCTAssertEqual(state["savedCount"] as? Int, count)
            if let longitude = state["longitude"] as? Double, let prior = before["longitude"] as? Double,
               abs(longitude - prior) > 0.001 { moved = true }
            if let latitude = state["latitude"] as? Double, let prior = before["latitude"] as? Double,
               abs(latitude - prior) > 0.001 { moved = true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(moved, "Collect the actual native-pan scenario, not a static launch")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = enabled ? "latency-probe-enabled-scene" : "latency-control-scene"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
