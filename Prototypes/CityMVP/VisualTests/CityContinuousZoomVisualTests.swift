import XCTest
import UIKit

/// Observation only: retained images/video decide geometry quality. Sampled
/// anchors and selection checks are not an every-frame or FPS claim.
final class CityContinuousZoomVisualTests: XCTestCase {
    private enum ProbeFailure: Error { case failed }

    @MainActor
    func testNormalPreviewPublicRegistrationProjection() throws {
        continueAfterFailure = false
        executionTimeAllowance = 150
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"]
        app.launch()
        defer { app.terminate() }
        func read() -> [String: Any]? {
            let element = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
            guard element.exists, let raw = element.value as? String else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        }
        func retain(_ name: String, _ state: [String: Any]?) {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
                app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
            }
            let shot = XCTAttachment(image: image); shot.name = name; shot.lifetime = .keepAlways; add(shot)
            if let data = try? JSONSerialization.data(withJSONObject: state ?? [:], options: .sortedKeys) {
                let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                metadata.name = name + "-actual-state"; metadata.lifetime = .keepAlways; add(metadata)
            }
        }
        func wait(_ name: String, timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) throws {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: app)
            guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
                retain("FAIL-" + name, read()); XCTFail("Timed out: " + name); throw ProbeFailure.failed
            }
        }
        let mode = app.buttons["cityMVP.mode"]
        try wait("registration", timeout: 35) { mode.exists && mode.isEnabled }
        let lighting = app.buttons["cityMVP.lighting"]
        if ["Night", "夜晚"].contains(lighting.value as? String ?? "") { lighting.tap() }
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        try wait("taipei-menu") { taipei.exists && taipei.isHittable }
        taipei.tap()
        try wait("overview", timeout: 45) {
            guard let state = read() else { return false }
            return state["sceneReady"] as? Bool == true && state["projectionAvailable"] as? Bool == true
        }
        let initialCount = try XCTUnwrap(read()?["savedCount"] as? Int)
        for index in 0...3 {
            var previous = read()
            try wait("stable-\(index)", timeout: 8) {
                guard let now = read(), let before = previous else { previous = read(); return false }
                defer { previous = now }
                return ["latitude", "longitude", "distance", "heading", "pitch"].allSatisfy { key in
                    guard let a = now[key] as? Double, let b = before[key] as? Double else { return false }
                    return abs(a - b) < (key == "latitude" || key == "longitude" ? 1e-8 : 0.01)
                }
            }
            let state = try XCTUnwrap(read())
            let distance = try XCTUnwrap(state["distance"] as? Double)
            retain(String(format: "registration-%02d-%.0fm", index, distance), state)
            XCTAssertEqual(state["route"] as? String, "preview")
            XCTAssertEqual(state["trace"] as? Bool, false)
            XCTAssertEqual(state["savedCount"] as? Int, initialCount)
            let observation = try XCTUnwrap(state["registrationObservation"] as? [String: Any])
            XCTAssertEqual(observation["provenance"] as? String, "live-search")
            for key in ["sourceLatitude", "sourceLongitude", "latitudeOffset", "longitudeOffset",
                        "sourceX", "sourceY", "registeredX", "registeredY"] {
                XCTAssertTrue(try XCTUnwrap(observation[key] as? Double).isFinite, key)
            }
            if index < 3 {
                let pinch = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
                XCTAssertTrue(pinch.exists)
                XCTAssertGreaterThan(pinch.frame.width, 0)
                pinch.pinch(withScale: 0.78, velocity: -0.5)
                try wait("distance-change") { (read()?["distance"] as? Double ?? 0) > distance * 1.05 }
            }
        }
    }

    @MainActor
    func testNormalPreviewContinuousNativeZoomOutAndBack() throws {
        continueAfterFailure = false
        executionTimeAllowance = 360
        let deadline = Date().addingTimeInterval(350)
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"]
        app.launch()
        defer { app.terminate() }

        func read() -> [String: Any]? {
            let element = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
            guard element.exists, let raw = element.value as? String else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        }
        func retain(_ name: String, state: [String: Any]?, failure: Bool = false) {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
                app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
            }
            let screenshot = XCTAttachment(image: image)
            screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
            let payload = state ?? ["inspectionAvailable": false]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) {
                let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                metadata.name = name + "-actual-state"; metadata.lifetime = .keepAlways; add(metadata)
            }
            if failure {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
        }
        func require(_ condition: Bool, _ message: String, _ name: String,
                     state: [String: Any]? = nil, line: UInt = #line) throws {
            guard condition else {
                // Retain evidence BEFORE XCTest aborts; defer is not an evidence strategy.
                retain("FAIL-" + name, state: state ?? read(), failure: true)
                XCTFail(message, line: line)
                throw ProbeFailure.failed
            }
        }
        func wait(_ name: String, timeout: TimeInterval, _ condition: @escaping () -> Bool) throws {
            let remaining = deadline.timeIntervalSinceNow
            try require(remaining > 0, "Continuous zoom exceeded its total deadline", name)
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: app)
            let result = XCTWaiter.wait(for: [expectation], timeout: min(timeout, remaining))
            try require(result == .completed, "Timed out: " + name, name)
        }
        func menu(_ title: String) throws {
            let menu = app.buttons["cityMVP.city"]
            try wait("menu-ready", timeout: 8) { menu.exists && menu.isHittable }
            menu.tap()
            let item = app.buttons[title]
            try wait("menu-" + title, timeout: 5) { item.exists && item.isHittable }
            item.tap()
        }
        let mode = app.buttons["cityMVP.mode"]
        try wait("alignment", timeout: 30) {
            guard mode.exists, mode.isEnabled, let value = mode.value as? String else { return false }
            return ["Map", "Overview", "District"].contains { value.hasPrefix($0) }
        }
        try require(abs(app.frame.width - 393) < 1 && abs(app.frame.height - 852) < 1,
                    "Use the normal 393×852 viewport; resizing is not device-size acceptance", "viewport")
        let lighting = app.buttons["cityMVP.lighting"]
        if ["Night", "夜晚"].contains(lighting.value as? String ?? "") { lighting.tap() }
        try menu("台北 Taipei")
        try wait("initial-scene", timeout: 45) {
            guard let state = read() else { return false }
            return state["sceneReady"] as? Bool == true && state["projectionAvailable"] as? Bool == true
        }
        let overview = read()
        retain("continuous-setup-overview", state: overview)
        guard let savedCount = overview?["savedCount"] as? Int else {
            try require(false, "Missing initial saved count", "initial-count", state: overview)
            return
        }
        if (overview?["distance"] as? Double ?? .infinity) >= 2_200 { mode.tap() }
        try wait("initial-near", timeout: 20) { (read()?["distance"] as? Double ?? .infinity) < 2_200 }
        try menu("Places 地點")
        let landmark = app.buttons["cityMVP.place.landmark-101"]
        try wait("landmark-menu", timeout: 5) { landmark.exists && landmark.isHittable }
        landmark.tap()
        try wait("landmark-selected", timeout: 10) { read()?["selectedID"] as? String == "landmark-101" }

        func sample(_ stage: String, index: Int) throws -> Double {
            func stable(_ a: [String: Any], _ b: [String: Any]) -> Bool {
                let limits: [String: Double] = ["latitude": 0.00000001, "longitude": 0.00000001,
                    "distance": 0.1, "heading": 0.01, "pitch": 0.01, "selectedPinX": 0.25, "selectedPinY": 0.25]
                return limits.allSatisfy { key, limit in
                    guard let before = a[key] as? Double, let after = b[key] as? Double else { return false }
                    return before.isFinite && after.isFinite && abs(before - after) <= limit
                }
            }
            var previous = read()
            try wait(stage + "-stable-camera", timeout: 6) {
                guard let current = read() else { return false }
                defer { previous = current }
                return previous.map { stable($0, current) } ?? false
            }
            guard let state = read(), let distance = state["distance"] as? Double else {
                try require(false, "Missing actual camera distance", stage + "-missing")
                return 0
            }
            let name = String(format: "continuous-%@-%02d-%.0fm", stage, index, distance)
            retain(name, state: state)
            try require(distance.isFinite && distance > 0, "Invalid sampled distance", name, state: state)
            try require(state["route"] as? String == "preview" && state["trace"] as? Bool == false,
                        "Must remain on ordinary preview without trace", name, state: state)
            for key in ["nativeGround", "opaqueReveal", "materialTone", "cloudHandoff", "groundOwnership", "contextRing", "contextLabels"] {
                try require(state[key] as? Bool == true, "Integrated feature missing: " + key, name, state: state)
            }
            try require(state["savedCount"] as? Int == savedCount, "Observing must not change saves", name, state: state)
            try require(state["selectedID"] as? String == "landmark-101", "Selection changed", name, state: state)
            let sceneSelection = (state["pins"] as? [[String: Any]] ?? []).filter { $0["selected"] as? Bool == true }
            try require(sceneSelection.count <= 1 && sceneSelection.allSatisfy {
                $0["id"] as? String == "landmark-101" && $0["photo"] as? Bool == true
            }, "Scene selection must keep the original landmark photo; native ownership may have no scene entry", name, state: state)
            if state["projectionAvailable"] as? Bool == true {
                let error = state["fitError"] as? Double ?? .infinity
                try require(error >= 0 && error < 2, "Sampled scene fit exceeded 2 pt", name, state: state)
            }
            guard let x = state["selectedPinX"] as? Double, let y = state["selectedPinY"] as? Double else {
                try require(false, "Missing sampled photo anchor", name, state: state)
                return distance
            }
            let owners = app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin")
            if CGRect(x: 0, y: 0, width: 393, height: 852).contains(CGPoint(x: x, y: y)) {
                try require(owners.count == 1, "Expected exactly one visible selected photo owner", name, state: state)
                let frame = owners.firstMatch.frame
                let after = read()
                try require(after.map { stable(state, $0) } == true,
                            "Camera or projected anchor changed during AX sampling; this is not pin-detachment evidence", name, state: state)
                try require(frame.width > 0 && frame.height > 0 && abs(frame.midX - x) <= 2 && abs(frame.maxY + 3 - y) <= 2,
                            "Selected photo differs from its stable sampled anchor by more than 2 pt", name, state: state)
            }
            return distance
        }

        var distance = try sample("near", index: 0)
        try require(distance < 2_200, "Near start must be below 2200 m", "near-start")
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        let target = map.frame
        try require(map.exists && !target.isNull && !target.isInfinite
                    && target.width > 0 && target.height > 0 && app.frame.contains(target),
                    "Native pinch coordinate target unavailable", "pinch-target")
        print("CONTINUOUS_ZOOM_BEGIN")
        for index in 1...10 {
            if distance > 9_500 { break }
            let before = distance
            map.pinch(withScale: 0.78, velocity: -1.2)
            try wait("out-\(index)-distance-change", timeout: 8) {
                (read()?["distance"] as? Double ?? 0) > before * 1.03
            }
            distance = try sample("out", index: index)
        }
        print("CONTINUOUS_ZOOM_END")
        try require(distance > 9_500, "Ten physical outward pinches did not reach the far band", "out-limit")

        for index in 1...10 {
            if distance < 2_200 { break }
            let before = distance
            map.pinch(withScale: 1 / 0.78, velocity: 1.2)
            try wait("back-\(index)-distance-change", timeout: 8) {
                (read()?["distance"] as? Double ?? .infinity) < before * 0.97
            }
            distance = try sample("back", index: index)
        }
        try require(distance < 2_200, "Ten physical inward pinches did not return to the near band", "back-limit")
        _ = try sample("returned", index: 0)
        // No camera/menu resets after the initial setup; no save or style actions.
        // These samples intentionally do not assert cube absence or continuous FPS.
    }
}
