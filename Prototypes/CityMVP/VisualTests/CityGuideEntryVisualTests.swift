import XCTest

final class CityGuideEntryVisualTests: XCTestCase {
    @MainActor
    func testSavedAndPassportGuideEntriesUseExclusiveCurrentPlaceHandoffV1() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        print("CITY_GUIDE_ENTRY_HANDOFF_V1")
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground { self.capture(app, "guide-entry-terminal") }
            app.terminate()
        }
        for (language, night, askTitle, localStatus, openTitle) in [
            ("en", "NO", "Ask SAV-E", "Preview · Saved-place search", "Open place"),
            ("zh-Hant", "YES", "詢問 SAV-E", "測試版 · 搜尋已確認收藏", "開啟地點")
        ] {
            app.launchArguments = ["--inspect-citylab", "-save.appLanguage", language, "-cityMVP.night", night]
            app.launch()
            let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
            XCTAssertTrue(inspector.waitForExistence(timeout: 20))
            func read() -> [String: Any]? {
                guard let raw = inspector.value as? String else { return nil }
                return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
            }
            func wait(_ condition: ([String: Any]) -> Bool) throws -> [String: Any] {
                let deadline = Date().addingTimeInterval(45)
                for _ in 0..<40 {
                    guard Date() < deadline else { break }
                    if let value = read(), condition(value) { return value }
                    RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
                }
                return try XCTUnwrap(nil as [String: Any]?, "Native state did not reach the requested condition")
            }
            let limits: [String: Double] = ["latitude": 1e-8, "longitude": 1e-8, "distance": 0.1, "heading": 0.01, "pitch": 0.01]
            func settled() throws -> [String: Any] {
                var previous = try XCTUnwrap(read()), count = 0
                return try wait { current in
                    let same = limits.allSatisfy { key, tolerance in
                        guard let a = previous[key] as? Double, let b = current[key] as? Double else { return false }
                        return a.isFinite && b.isFinite && abs(a - b) <= tolerance
                    }
                    count = same ? count + 1 : 0; previous = current
                    return count >= 2
                }
            }
            app.buttons["cityMVP.city"].tap()
            let taipei = app.buttons["台北 Taipei"]
            XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
            let ready = try wait { $0["sceneReady"] as? Bool == true && $0["projectionAvailable"] as? Bool == true }
            let pins = try XCTUnwrap(ready["pins"] as? [[String: Any]])
            let photo = try XCTUnwrap(pins.first { pin in
                guard pin["saved"] as? Bool == true, pin["photo"] as? Bool == true,
                      let x = pin["x"] as? Double, let y = pin["y"] as? Double else { return false }
                return x > 44 && x < app.frame.width - 44 && y > 160 && y < app.frame.height - 170
            }, "Use an actual current saved photo, never seed a collection")
            let context = try XCTUnwrap(photo["id"] as? String)
            let pin = app.descendants(matching: .any)["cityMVP.groundPin." + context].firstMatch
            XCTAssertTrue(pin.waitForExistence(timeout: 5))
            let title = pin.label
            pin.tap()
            _ = try wait { $0["selectedID"] as? String == context }
            let before = try settled()
            let identity = try XCTUnwrap(before["selectedNativeIdentity"] as? String)
            XCTAssertNotNil(UUID(uuidString: identity))
            let saved = app.buttons["cityMVP.tab.saved"]
            let passport = app.buttons["cityMVP.tab.passport"]
            let map = app.buttons["cityMVP.tab.map"]
            func entry() -> XCUIElement {
                app.buttons.matching(identifier: "cityMVP.guide.entry").firstMatch
            }
            func checkEntry(_ phase: String) throws {
                let button = entry()
                XCTAssertTrue(button.waitForExistence(timeout: 8))
                XCTAssertEqual(app.buttons.matching(identifier: "cityMVP.guide.entry").count, 1)
                XCTAssertEqual(button.label, askTitle)
                XCTAssertTrue(button.isHittable)
                XCTAssertTrue(app.frame.contains(button.frame))
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertGreaterThanOrEqual(button.frame.width, 44)
                XCTAssertLessThanOrEqual(button.frame.maxY, map.frame.minY - 8)
                capture(app, "guide-entry-" + language + "-" + phase)
            }
            saved.tap()
            try checkEntry("saved")
            let filter = app.textFields["cityMVP.saved.filter"]
            XCTAssertTrue(filter.exists); filter.tap(); filter.typeText(title + "\n")
            XCTAssertEqual(filter.value as? String, title)
            entry().tap()
            XCTAssertTrue(app.navigationBars["SAV-E Guide"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts[localStatus].exists, "Local search must not be presented as a live AI answer")
            let input = app.textFields["cityMVP.agent.input"]
            XCTAssertTrue(input.exists); input.tap(); input.typeText(title)
            app.buttons["cityMVP.agent.ask"].tap()
            let result = app.buttons["cityMVP.agent.result." + identity]
            XCTAssertTrue(result.waitForExistence(timeout: 8))
            for _ in 0..<3 where !result.isHittable { app.swipeUp() }
            result.tap()
            let open = app.buttons["cityMVP.guide.openPlace"]
            XCTAssertTrue(open.waitForExistence(timeout: 8)); XCTAssertEqual(open.label, openTitle)
            for _ in 0..<4 where !open.isHittable { app.swipeUp() }
            capture(app, "guide-entry-" + language + "-brief")
            open.tap()
            let close = app.buttons["drawer.place.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 12))
            XCTAssertFalse(app.buttons["cityMVP.agent.done"].exists, "Guide must dismiss before its place detail presents")
            capture(app, "guide-entry-" + language + "-detail")
            close.tap()
            XCTAssertTrue(entry().waitForExistence(timeout: 8))
            XCTAssertTrue(saved.isSelected)
            XCTAssertEqual(filter.value as? String, title)
            passport.tap()
            try checkEntry("passport")
            entry().tap()
            let done = app.buttons["cityMVP.agent.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
            XCTAssertTrue(entry().waitForExistence(timeout: 8)); XCTAssertTrue(passport.isSelected)
            map.tap()
            _ = try wait { $0["selectedID"] as? String == context }
            let after = try settled()
            XCTAssertEqual(after["savedCount"] as? Int, before["savedCount"] as? Int)
            XCTAssertEqual(after["selectedNativeIdentity"] as? String, identity)
            for (key, tolerance) in limits {
                XCTAssertEqual(try XCTUnwrap(after[key] as? Double), try XCTUnwrap(before[key] as? Double), accuracy: tolerance)
            }
            capture(app, "guide-entry-" + language + "-map-return")
            app.terminate()
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
