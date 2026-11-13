import XCTest
import UIKit

final class CityMVPCaptureReviewVisualTests: XCTestCase {
    @MainActor
    func testChineseCaptionRemainsUnplacedUntilConfirmedAndCanBeRejected() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let source = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_CAPTURE_TEST_SOURCE_URL"])
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"]
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = "chinese-capture-" + UUID().uuidString
        app.launch()
        defer {
            capture(app, "capture-review-terminal")
            if (testRun?.totalFailureCount ?? 0) > 0 { retainHierarchy(app, "capture-review-failure") }
            app.terminate()
        }
        XCTAssertEqual(app.frame.width, 393, accuracy: 1)
        XCTAssertEqual(app.frame.height, 852, accuracy: 1)
        func savedCount() -> Int? {
            let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
            guard inspector.exists, let raw = inspector.value as? String,
                  let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return nil }
            return value["savedCount"] as? Int
        }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        var reads: [[String: Any]] = []
        func readState(_ phase: String) -> [String: Any]? {
            let began = ProcessInfo.processInfo.systemUptime
            let raw = inspector.value as? String
            let state = raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            var record: [String: Any] = ["phase": phase, "begin": began,
                "seconds": ProcessInfo.processInfo.systemUptime - began, "parsed": state != nil]
            if let state {
                for key in ["latitude", "longitude", "distance", "heading", "pitch", "sceneReady", "projectionAvailable"] {
                    record[key] = state[key]
                }
            }
            reads.append(record)
            if let data = try? JSONSerialization.data(withJSONObject: reads, options: .sortedKeys) {
                let item = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                item.name = "capture-review-direct-reads-" + phase; item.lifetime = .keepAlways; self.add(item)
            }
            return state
        }
        func waitForState(_ phase: String, seconds: Double, condition: ([String: Any]) -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            for index in 0..<40 {
                guard Date() < deadline else { break }
                if let state = readState(phase + "-" + String(index)), condition(state) { return true }
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
            }
            return false
        }
        let before = try XCTUnwrap(savedCount())
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        XCTAssertTrue(waitForState("preparing", seconds: 45) { state in
            state["sceneReady"] as? Bool == true && state["projectionAvailable"] as? Bool == true
        })
        func cameraState() -> [String: Double]? {
            guard let raw = inspector.value as? String,
                  let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return nil }
            var sample: [String: Double] = [:]
            for key in ["latitude", "longitude", "distance", "heading", "pitch"] {
                guard let number = value[key] as? Double else { return nil }
                sample[key] = number
            }
            return sample
        }
        func nativePoints() -> [String: Double]? {
            guard let raw = inspector.value as? String,
                  let state = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let observation = state["registrationObservation"] as? [String: Any] else { return nil }
            var result: [String: Double] = [:]
            for key in ["sourceX", "sourceY", "registeredX", "registeredY"] {
                guard let value = observation[key] as? Double, value.isFinite else { return nil }
                result[key] = value
            }
            return result
        }
        let initialCamera = try XCTUnwrap(cameraState())
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.32))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.45)))
        XCTAssertTrue(waitForState("panned", seconds: 15) { state in
            guard let longitude = state["longitude"] as? Double, let latitude = state["latitude"] as? Double else { return false }
            return abs(longitude - initialCamera["longitude"]!) > 0.001
                || abs(latitude - initialCamera["latitude"]!) > 0.001
        })
        // Await the end of native inertia before capturing the resume contract.
        var previous = cameraState()
        var samples: [[String: Double]] = []
        var stableSamples = 0
        let settleLimits: [String: Double] = ["latitude": 0.00000001, "longitude": 0.00000001,
            "distance": 0.1, "heading": 0.01, "pitch": 0.01]
        let settled = waitForState("settling", seconds: 20) { state in
            var current: [String: Double] = [:]
            for key in settleLimits.keys {
                guard let number = state[key] as? Double, number.isFinite else { return false }
                current[key] = number
            }
            guard let last = previous else { previous = current; return false }
            samples.append(current)
            defer { previous = current }
            let stable = current.allSatisfy { key, number in abs(number - last[key]!) < settleLimits[key]! }
            stableSamples = stable ? stableSamples + 1 : 0
            return stableSamples >= 2
        }
        let sampleAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: samples), uniformTypeIdentifier: "public.json")
        sampleAttachment.name = "capture-review-native-settle-samples"; sampleAttachment.lifetime = .keepAlways; self.add(sampleAttachment)
        capture(app, "capture-review-camera-preparation")
        XCTAssertTrue(settled)
        let expectedCamera = try XCTUnwrap(cameraState())
        let expectedNativePoints = try XCTUnwrap(nativePoints(), "Direct native projections are required to independently check the displayed pose")
        let beforeAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject:
            ["camera": expectedCamera, "directNativeGroundPoints": expectedNativePoints]), uniformTypeIdentifier: "public.json")
        beforeAttachment.name = "capture-review-camera-before"; beforeAttachment.lifetime = .keepAlways; self.add(beforeAttachment)
        let add = app.buttons["新增收藏 Add place"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        input.typeText("📍街角咖啡（静安寺店）\n地址：上海市静安区愚园路18号\n地铁：静安寺站2号口\n" + source)
        let done = app.buttons["capture.keyboardDone"]
        if done.exists { done.tap() }
        let find = app.buttons["capture.analyze"]
        XCTAssertTrue(find.isEnabled); find.tap()
        let state = app.staticTexts["drawer.review.notSaved"]
        let appeared = state.waitForExistence(timeout: 12)
        capture(app, "capture-review-chinese-clue")
        XCTAssertTrue(appeared)
        let name = app.staticTexts["drawer.review.name"]
        XCTAssertTrue(name.label.contains("街角咖啡") && name.label.contains("静安寺"))
        XCTAssertTrue(name.isHittable && state.isHittable)
        let primary = app.buttons["drawer.review.primaryAction"]
        XCTAssertTrue(primary.isHittable)
        XCTAssertTrue(["Find exact place", "找出精確地點"].contains(primary.label))
        XCTAssertFalse(app.buttons["drawer.review.heroMap"].exists, "No coordinates means no made-up map focus")
        let reject = app.buttons["drawer.review.reject"]
        XCTAssertTrue(reject.isHittable); reject.tap()
        XCTAssertTrue(state.waitForNonExistence(timeout: 12))
        let map = app.buttons["cityMVP.tab.map"]
        if !map.exists {
            // Rejection returns to this capture's review list, which is pushed
            // above the tab root. Use its real Back action before switching tabs.
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            let canReturn = back.waitForExistence(timeout: 5)
            capture(app, "capture-review-after-rejection")
            XCTAssertTrue(canReturn && back.isHittable); back.tap()
        }
        XCTAssertTrue(map.waitForExistence(timeout: 8)); map.tap()
        let resumed = inspector.waitForExistence(timeout: 8)
        capture(app, "capture-review-returned-map")
        XCTAssertTrue(resumed)
        let returnedCamera = try XCTUnwrap(cameraState())
        let returnedNativePoints = try XCTUnwrap(nativePoints())
        let afterAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject:
            ["camera": returnedCamera, "directNativeGroundPoints": returnedNativePoints]), uniformTypeIdentifier: "public.json")
        afterAttachment.name = "capture-review-camera-after"; afterAttachment.lifetime = .keepAlways; self.add(afterAttachment)
        for key in expectedCamera.keys {
            XCTAssertEqual(returnedCamera[key]!, expectedCamera[key]!, accuracy: key == "distance" ? 0.1 : 0.000001,
                           "Returning to Map must preserve the actual panned camera")
        }
        for key in expectedNativePoints.keys {
            XCTAssertEqual(returnedNativePoints[key]!, expectedNativePoints[key]!, accuracy: 2,
                           "Fresh MapProxy points must stay attached to the same displayed camera")
        }
        XCTAssertEqual(savedCount(), before, "Reviewing/rejecting text cannot create a Map Stamp")
        capture(app, "capture-review-no-new-saved-pin")
    }

    @MainActor
    func testNormalSelectedSavedPinAndCameraSurviveSavedPassportAndMap() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"]
        app.launch()
        defer { capture(app, "selected-tab-return-terminal"); app.terminate() }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        func state() -> [String: Any]? {
            guard let raw = inspector.value as? String else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        }
        func awaitState(_ condition: ([String: Any]) -> Bool) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(45)
            for _ in 0..<40 {
                guard Date() < deadline else { break }
                if let value = state(), condition(value) { return value }
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
            }
            return nil
        }
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let ready = try XCTUnwrap(awaitState {
            $0["sceneReady"] as? Bool == true && $0["projectionAvailable"] as? Bool == true
        })
        let pins = try XCTUnwrap(ready["pins"] as? [[String: Any]])
        let saved = try XCTUnwrap(pins.first { pin in
            guard pin["saved"] as? Bool == true, let x = pin["x"] as? Double, let y = pin["y"] as? Double else { return false }
            return x > 44 && x < app.frame.width - 44 && y > 160 && y < app.frame.height - 170
        }, "Requires a real existing visible save; do not seed a fixed map pin to satisfy the test")
        let identity = try XCTUnwrap(saved["id"] as? String)
        let control = app.descendants(matching: .any)["cityMVP.groundPin." + identity].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5)); XCTAssertTrue(control.isHittable); control.tap()
        let selection = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 8))
        let selected = try XCTUnwrap(awaitState { value in
            (value["pins"] as? [[String: Any]])?.contains {
                $0["id"] as? String == identity && $0["selected"] as? Bool == true
            } == true
        })
        let cameraKeys = ["latitude", "longitude", "distance", "heading", "pitch"]
        // Two independent state reads separated in time must agree before the
        // tab journey. Selection can aim the camera through the normal action.
        var previous = selected
        var stableCount = 0
        let before = try XCTUnwrap(awaitState { current in
            defer { previous = current }
            let stable = cameraKeys.allSatisfy { key in
                guard let a = current[key] as? Double, let b = previous[key] as? Double else { return false }
                return abs(a - b) < (key == "distance" ? 0.1 : 0.00000001)
            }
            stableCount = stable ? stableCount + 1 : 0
            return stableCount >= 2
        })
        let anchor = selection.frame
        let label = selection.label
        let count = try XCTUnwrap(before["savedCount"] as? Int)
        capture(app, "selected-tab-return-before")
        app.buttons["cityMVP.tab.saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.savedPage"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(selection.exists, "Hidden map selection must leave the accessibility tree")
        app.buttons["cityMVP.tab.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["cityMVP.tab.map"].tap()
        XCTAssertTrue(inspector.waitForExistence(timeout: 8)); XCTAssertTrue(selection.waitForExistence(timeout: 8))
        let after = try XCTUnwrap(state())
        XCTAssertEqual(after["savedCount"] as? Int, count)
        XCTAssertTrue((after["pins"] as? [[String: Any]])?.contains {
            $0["id"] as? String == identity && $0["selected"] as? Bool == true
        } == true, "The same actual save must retain selection")
        XCTAssertEqual(selection.label, label)
        XCTAssertEqual(selection.frame.midX, anchor.midX, accuracy: 2)
        XCTAssertEqual(selection.frame.maxY, anchor.maxY, accuracy: 2)
        for key in cameraKeys {
            XCTAssertEqual(try XCTUnwrap(after[key] as? Double), try XCTUnwrap(before[key] as? Double),
                           accuracy: key == "distance" ? 0.1 : 0.000001)
        }
        capture(app, "selected-tab-return-after")
    }

    @MainActor
    private func retainHierarchy(_ app: XCUIApplication, _ name: String) {
        capture(app, name)
        let item = XCTAttachment(string: app.debugDescription)
        item.name = name + "-hierarchy"; item.lifetime = .keepAlways; add(item)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
            app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
        }
        let item = XCTAttachment(image: image); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
