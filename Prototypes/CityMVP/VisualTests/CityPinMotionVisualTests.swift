import XCTest

/// Ordinary touch-driven selection/release evidence. XCTest waits for idle;
/// this does not claim to exercise a reversal within the spring's first 160ms.
final class CityPinMotionVisualTests: XCTestCase {
    @MainActor
    func testFarNativePhotoReferenceAndPhysicalReselection() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        print("NATIVE_REFERENCE_PHYSICAL_RESELECT_V2")
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab", "--inspect-pin-reference"]
        app.launch()
        addTeardownBlock { @MainActor in
            self.capture(app, "native-reference-terminal"); app.terminate()
        }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        func read() throws -> [String: Any] {
            let raw = try XCTUnwrap(inspector.value as? String)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        }
        func wait(_ predicate: ([String: Any]) -> Bool) throws -> [String: Any] {
            let deadline = Date().addingTimeInterval(45)
            for _ in 0..<30 {
                guard Date() < deadline else { break }
                let value = try read()
                if predicate(value) { return value }
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
            XCTFail("Missing required real camera state"); return [:]
        }
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let ready = try wait { $0["sceneReady"] as? Bool == true && $0["projectionAvailable"] as? Bool == true }
        let pins = try XCTUnwrap(ready["pins"] as? [[String: Any]])
        let photo = try XCTUnwrap(pins.first { $0["saved"] as? Bool == true && $0["photo"] as? Bool == true })
        let identity = try XCTUnwrap(photo["id"] as? String)
        let target = app.descendants(matching: .any)["cityMVP.groundPin." + identity].firstMatch
        XCTAssertTrue(target.isHittable); target.tap()
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        var state = try wait { $0["selectedID"] as? String == identity }
        let selection = try XCTUnwrap(state["selectedID"] as? String)
        let nativeIdentity = try XCTUnwrap(state["selectedNativeIdentity"] as? String)
        let count = try XCTUnwrap(state["savedCount"] as? Int)
        for _ in 0..<4 {
            if (state["distance"] as? Double ?? 0) > 10_000 { break }
            map.pinch(withScale: 0.6, velocity: -0.6)
            state = try read()
        }
        state = try wait { ($0["distance"] as? Double ?? 0) > 9_500 && $0["projectionAvailable"] as? Bool == false }
        func sample(_ phase: String) throws {
            let state = try read()
            XCTAssertEqual(state["selectedID"] as? String, selection)
            XCTAssertEqual(state["savedCount"] as? Int, count)
            XCTAssertGreaterThan(try XCTUnwrap(state["distance"] as? Double), 9_500)
            XCTAssertEqual(state["projectionAvailable"] as? Bool, false)
            XCTAssertEqual(state["sceneOpacity"] as? Double, 0)
            XCTAssertEqual(state["selectedContactOpacity"] as? Double, 0)
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: state, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            attachment.name = "native-reference-" + phase; attachment.lifetime = .keepAlways; add(attachment)
            capture(app, "native-reference-" + phase)
        }
        try sample("before")
        print("NATIVE_PIN_REFERENCE_RECORD_BEGIN")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.30)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.38)),
            withVelocity: .slow, thenHoldForDuration: 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.38)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.30)),
            withVelocity: .slow, thenHoldForDuration: 0)
        print("NATIVE_PIN_REFERENCE_RECORD_END")
        try sample("after")
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close place", "關閉地點"])).firstMatch
        XCTAssertTrue(close.isHittable); close.tap()
        let native = app.descendants(matching: .any)["map.pin.saved." + nativeIdentity].firstMatch
        _ = try wait { ($0["selectedNativeIdentity"] as? String ?? "").isEmpty }
        XCTAssertTrue(native.waitForExistence(timeout: 8))
        // MapKit exposes this native annotation as Other with isHittable=false.
        // Exercise a real touch at its current visible head, then require a
        // fresh empty→exactUUID transition rather than trusting AX hitability.
        let nativeBounds = native.frame
        XCTAssertGreaterThanOrEqual(nativeBounds.width, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(nativeBounds.height, 44 - 0.001)
        XCTAssertTrue(app.frame.contains(nativeBounds))
        print("NATIVE_REFERENCE_PHYSICAL_TAP_BEGIN_V2")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: nativeBounds.midX, dy: nativeBounds.midY)).tap()
        _ = try wait { $0["selectedNativeIdentity"] as? String == nativeIdentity }
        try sample("native-reselected")
    }

    @MainActor
    func testNormalContextLayerOwnershipComparison() throws {
        continueAfterFailure = false
        executionTimeAllowance = 150
        let hidden = ProcessInfo.processInfo.environment["CITY_CONTEXT_HIDE"] == "yes"
        let legacy = ProcessInfo.processInfo.environment["CITY_CONTEXT_LEGACY"] == "yes"
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"] + (hidden ? ["--inspect-without-context-buildings"] : [])
            + (legacy ? ["--inspect-legacy-context-surface"] : [])
        app.launch()
        defer { app.terminate() }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        func read() -> [String: Any]? {
            guard let raw = inspector.value as? String else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        }
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        func settle() throws -> [String: Any] {
            var previous: [String: Any]?
            let deadline = Date().addingTimeInterval(50)
            for _ in 0..<40 {
                guard Date() < deadline else { break }
                if let state = read() {
                    let stable = previous.map { last in
                        ["latitude", "longitude", "distance", "heading", "pitch"].allSatisfy { key in
                            guard let a = state[key] as? Double, let b = last[key] as? Double else { return false }
                            return abs(a - b) < (key == "distance" ? 0.1 : 0.00000001)
                        }
                    } ?? false
                    previous = state
                    if stable && state["sceneReady"] as? Bool == true && state["projectionAvailable"] as? Bool == true { return state }
                }
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
            }
            XCTFail("Missing settled native scene"); return [:]
        }
        var value = try settle()
        XCTAssertEqual(value["route"] as? String, "preview")
        XCTAssertEqual(value["trace"] as? Bool, false)
        XCTAssertEqual(value["contextHideRequested"] as? Bool, hidden)
        XCTAssertEqual(value["contextSurfaceDetail"] as? Bool, !legacy)
        let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), uniformTypeIdentifier: "public.json")
        metadata.name = hidden ? "context-hidden-request-state" : "context-visible-state"
        metadata.lifetime = .keepAlways; add(metadata)
        capture(app, hidden ? "context-hidden-request" : "context-visible")
        let initial = value
        for _ in 0..<2 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.28)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34)))
            value = try settle()
        }
        let latitudeChange = abs(try XCTUnwrap(value["latitude"] as? Double) - XCTUnwrap(initial["latitude"] as? Double))
        let longitudeChange = abs(try XCTUnwrap(value["longitude"] as? Double) - XCTUnwrap(initial["longitude"] as? Double))
        XCTAssertGreaterThan(latitudeChange + longitudeChange, 0.002, "North comparison requires actual native camera movement")
        let north = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), uniformTypeIdentifier: "public.json")
        north.name = "context-north-state"; north.lifetime = .keepAlways; add(north)
        capture(app, "context-north-browse")
    }

    @MainActor
    func testNormalSavedPhotoPinInputAcrossPanZoomAndRotationV2() throws {
        print("NATIVE_SAVED_PIN_INPUT_MOTION_V2")
        continueAfterFailure = false
        executionTimeAllowance = 300
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"]
        app.launch()
        defer { capture(app, "normal-pin-motion-terminal"); app.terminate() }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        func read() -> [String: Any]? {
            guard let raw = inspector.value as? String else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        }
        func wait(_ condition: ([String: Any]) -> Bool) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(45)
            for _ in 0..<40 {
                guard Date() < deadline else { break }
                if let state = read(), condition(state) { return state }
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
            }
            return nil
        }
        let cameraLimits: [String: Double] = ["latitude": 1e-8, "longitude": 1e-8,
            "distance": 0.1, "heading": 0.01, "pitch": 0.01, "selectedPinX": 0.25, "selectedPinY": 0.25]
        func stable(_ a: [String: Any], _ b: [String: Any]) -> Bool {
            cameraLimits.allSatisfy { key, limit in
                guard let first = a[key] as? Double, let second = b[key] as? Double else { return false }
                return first.isFinite && second.isFinite && abs(first - second) <= limit
            }
        }
        func settled() throws -> [String: Any] {
            var previous = try XCTUnwrap(read())
            var count = 0
            return try XCTUnwrap(wait { current in
                defer { previous = current }
                count = stable(previous, current) ? count + 1 : 0
                return count >= 2
            }, "Native pose and selected anchor must settle before endpoint measurements")
        }
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let ready = try XCTUnwrap(wait {
            $0["sceneReady"] as? Bool == true && $0["projectionAvailable"] as? Bool == true
        })
        let entries = try XCTUnwrap(ready["pins"] as? [[String: Any]])
        let photo = try XCTUnwrap(entries.first { pin in
            guard pin["saved"] as? Bool == true, pin["photo"] as? Bool == true,
                  let x = pin["x"] as? Double, let y = pin["y"] as? Double else { return false }
            return x > 44 && x < app.frame.width - 44 && y > 160 && y < app.frame.height - 170
        }, "Select an actual existing visible saved photo, never seed a fixed fixture")
        let identity = try XCTUnwrap(photo["id"] as? String)
        let pin = app.descendants(matching: .any)["cityMVP.groundPin." + identity].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5)); pin.tap()
        let selected = app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin")
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 8))
        let original = try settled()
        let originalCount = try XCTUnwrap(original["savedCount"] as? Int)
        let originalSelection = try XCTUnwrap(original["selectedID"] as? String)
        XCTAssertFalse(originalSelection.isEmpty)
        func sample(_ phase: String) throws -> [String: Any] {
            let state = try settled()
            XCTAssertEqual(state["route"] as? String, "preview")
            XCTAssertEqual(state["trace"] as? Bool, false)
            XCTAssertEqual(state["savedCount"] as? Int, originalCount)
            let input = XCTAttachment(data: try JSONSerialization.data(withJSONObject: ["phase": phase, "expected": originalSelection, "actual": state["selectedID"] ?? "", "selectionInput": state["selectionInput"] ?? []], options: .sortedKeys), uniformTypeIdentifier: "public.json")
            input.name = "normal-pin-input-" + phase; input.lifetime = .keepAlways; add(input)
            XCTAssertEqual(state["selectedID"] as? String, originalSelection)
            let x = try XCTUnwrap(state["selectedPinX"] as? Double)
            let y = try XCTUnwrap(state["selectedPinY"] as? Double)
            if app.frame.contains(CGPoint(x: x, y: y)) {
                XCTAssertEqual(selected.count, 1)
                let bounds = selected.firstMatch.frame
                let checked = try XCTUnwrap(read())
                XCTAssertTrue(stable(state, checked), "Do not attribute a moving sampling window to pin detachment")
                XCTAssertEqual(bounds.midX, x, accuracy: 2)
                if state["geographicPinOverlay"] as? Bool == false {
                    // Native accessibility covers the104pt head+caption stack;
                    // its geographic anchor remains72pt down from the top.
                    XCTAssertEqual(bounds.height, 104, accuracy: 2)
                    XCTAssertEqual(bounds.minY + 72, y, accuracy: 2)
                } else {
                    XCTAssertEqual(bounds.maxY + 3, y, accuracy: 2)
                }
            }
            let keys = ["latitude", "longitude", "distance", "heading", "pitch", "selectedPinX", "selectedPinY", "projectionAvailable", "fitError", "geographicPinOverlay"]
            var numeric: [String: Any] = ["phase": phase, "selectionUnchanged": true, "savedCountUnchanged": true]
            for key in keys { numeric[key] = state[key] }
            let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: numeric, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            metadata.name = "normal-pin-" + phase; metadata.lifetime = .keepAlways; add(metadata)
            capture(app, "normal-pin-" + phase)
            return state
        }
        _ = try sample("before")
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        XCTAssertTrue(map.exists)
        print("PIN_MOTION_RECORD_BEGIN")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let panStart = try settled()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.28)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34)))
        let panned = try sample("panned")
        XCTAssertGreaterThan(abs(try XCTUnwrap(panned["latitude"] as? Double) - XCTUnwrap(panStart["latitude"] as? Double))
            + abs(try XCTUnwrap(panned["longitude"] as? Double) - XCTUnwrap(panStart["longitude"] as? Double)), 0.0005)
        var current = panned
        for index in 1...3 {
            if (current["distance"] as? Double ?? 0) > 9_500 { break }
            let before = try XCTUnwrap(current["distance"] as? Double)
            map.pinch(withScale: 0.6, velocity: -0.45)
            current = try sample("out-" + String(index))
            XCTAssertGreaterThan(try XCTUnwrap(current["distance"] as? Double), before * 1.05)
        }
        XCTAssertGreaterThan(try XCTUnwrap(current["distance"] as? Double), 9_500)
        for index in 1...3 {
            if (current["distance"] as? Double ?? .infinity) < 3_200 { break }
            let before = try XCTUnwrap(current["distance"] as? Double)
            map.pinch(withScale: 1 / 0.6, velocity: 0.45)
            current = try sample("back-" + String(index))
            XCTAssertLessThan(try XCTUnwrap(current["distance"] as? Double), before * 0.95)
        }
        XCTAssertLessThan(try XCTUnwrap(current["distance"] as? Double), 3_200)
        let heading = try XCTUnwrap(current["heading"] as? Double)
        map.rotate(0.35, withVelocity: 0.2)
        current = try sample("rotated")
        let turn = abs(try XCTUnwrap(current["heading"] as? Double) - heading).truncatingRemainder(dividingBy: 360)
        XCTAssertGreaterThan(min(turn, 360 - turn), 8)
        print("PIN_MOTION_RECORD_END")
    }

    @MainActor
    func testPhotoSelectionAndReleaseAtFixedCamera() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-xinyi", "--verify-xinyi-auto", "--verify-xinyi-selected",
                                "-cityMVP.night", "NO"]
        app.launch()
        let district = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND value MATCHES %@", "cityMVP.mode", "District (1449|1450) 100%" )).firstMatch
        guard district.waitForExistence(timeout: 45) else {
            capture(app, "pin-motion-FAIL-district")
            XCTFail("The normal app must reach its registered district before pin evidence")
            return
        }
        let selected = app.buttons["cityMVP.selectedGroundPin"]
        let ordinary = app.buttons["cityMVP.groundPin.landmark-101"]
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close place", "關閉地點"])).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists)
        let camera = district.value as? String
        capture(app, "pin-motion-01-selected")

        close.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(ordinary.waitForExistence(timeout: 5))
        capture(app, "pin-motion-02-released")
        XCTAssertEqual(district.value as? String, camera, "Release must retain the fixture's mode and distance")

        ordinary.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        capture(app, "pin-motion-03-selected-again")
        XCTAssertEqual(district.value as? String, camera, "Selection must retain the fixture's mode and distance")
        close.tap()
        XCTAssertTrue(ordinary.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        capture(app, "pin-motion-04-released-again")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
