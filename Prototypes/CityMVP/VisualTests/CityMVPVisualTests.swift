import XCTest

final class CityMVPVisualTests: XCTestCase {
    @MainActor
    func testMapFirstNavigationAndAgent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        XCTAssertTrue(mode.wait(for: \.isEnabled, toEqual: true, timeout: 15))
        let lighting = app.buttons["cityMVP.lighting"]
        let isNight = NSPredicate(format: "value IN %@", ["Night", "夜晚"])
        let isDay = NSPredicate(format: "value IN %@", ["Day", "白天"])
        if isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        capture(app, "01-world")
        app.buttons["cityMVP.taipei"].tap()
        XCTAssertTrue(app.buttons["cityMVP.taipei"].wait(for: \.isSelected, toEqual: true, timeout: 9))
        capture(app, "02-taipei")
        mode.tap()
        XCTAssertTrue(app.buttons["cityMVP.places"].waitForExistence(timeout: 5))
        capture(app, "03-xinyi-3d")
        app.buttons["cityMVP.places"].tap()
        let landmark = app.buttons["cityMVP.place.landmark-101"]
        XCTAssertTrue(landmark.waitForExistence(timeout: 5))
        landmark.tap()
        XCTAssertTrue(landmark.waitForNonExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        capture(app, "04-place-panel")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)], timeout: 5), .completed)
        XCTAssertTrue(panel.exists, "The selected place should stay open while switching to night")
        capture(app, "09-xinyi-night")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        XCTAssertTrue(panel.exists, "The selected place should stay open while switching back to day")
        mode.tap()
        XCTAssertTrue(app.buttons["cityMVP.taipei"].wait(for: \.isSelected, toEqual: true, timeout: 9))
        XCTAssertTrue(panel.exists, "Zooming out should keep the same place selected")
        capture(app, "05-back-to-taipei")

        app.buttons["cityMVP.agent"].tap()
        let input = app.textFields["cityMVP.agent.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Taipei quiet restaurant")
        app.buttons["cityMVP.agent.ask"].tap()
        XCTAssertTrue(app.staticTexts["cityMVP.agent.empty"].waitForExistence(timeout: 5))
        capture(app, "06-agent")
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "完成"])).firstMatch
        XCTAssertTrue(done.exists)
        done.tap()

        mode.tap()
        app.buttons["cityMVP.places"].tap()
        XCTAssertTrue(landmark.waitForExistence(timeout: 5))
        landmark.tap()
        XCTAssertTrue(landmark.waitForNonExistence(timeout: 5))
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let isSaved = panel.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Map Stamp'")).firstMatch.exists

        app.buttons["cityMVP.tab.saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.savedPage"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "07-saved")
        app.buttons["cityMVP.tab.map"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 8))
        if !isSaved { XCTAssertFalse(panel.exists) }
        app.buttons["cityMVP.tab.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "08-passport")
    }

    @MainActor
    func testLocalFriendsAndTypedMapSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let passport = app.buttons["cityMVP.tab.passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 15))
        passport.tap()
        let friends = app.buttons["cityMVP.passport.friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 5))
        friends.tap()
        let offlineStatus = app.staticTexts["cityMVP.friends.offline"]
        XCTAssertTrue(offlineStatus.waitForExistence(timeout: 5))
        app.buttons["cityMVP.friends.done"].tap()
        XCTAssertTrue(offlineStatus.waitForNonExistence(timeout: 5))
        XCTAssertTrue(friends.isHittable)

        app.buttons["cityMVP.passport.trips"].tap()
        let tripPassport = app.buttons["root.passport"]
        XCTAssertTrue(tripPassport.waitForExistence(timeout: 5))
        tripPassport.tap()
        XCTAssertTrue(friends.waitForExistence(timeout: 5))

        app.buttons["搜尋 Search"].tap()
        XCTAssertTrue(app.textFields["map.search.input"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Talk to Savvy"].exists)
        app.buttons["map.search.close"].tap()

        let mapFriends = app.buttons["cityMVP.friends"]
        XCTAssertTrue(mapFriends.waitForExistence(timeout: 8))
        mapFriends.tap()
        XCTAssertTrue(offlineStatus.waitForExistence(timeout: 5))
    }

    @MainActor
    func testNativePinchKeepsLandmarkSelectedAcrossDistrict() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("--verify-xinyi")
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        XCTAssertTrue(mode.wait(for: \.isEnabled, toEqual: true, timeout: 15))
        let taipei = app.buttons["cityMVP.taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 8))
        taipei.tap()
        let unselected = app.buttons["cityMVP.groundPin.landmark-101"]
        XCTAssertTrue(unselected.waitForExistence(timeout: 9))
        unselected.tap()
        let selection = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        XCTAssertTrue(panel.exists)
        let title = selection.label
        let initialAnchor = selection.frame
        capture(app, "10-xinyi-apple-before")

        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        XCTAssertTrue(map.exists)
        map.pinch(withScale: 1.95, velocity: 0.72)
        waitForMode("District", on: mode)
        XCTAssertEqual(selection.label, title)
        XCTAssertTrue(panel.exists)
        capture(app, "11-xinyi-district-selected")
        map.pinch(withScale: 0.54, velocity: -0.72)
        waitForMode("Map", on: mode)
        XCTAssertEqual(selection.label, title)
        XCTAssertTrue(panel.exists)
        XCTAssertLessThan(hypot(selection.frame.midX - initialAnchor.midX,
                                selection.frame.maxY - initialAnchor.maxY), 65)
        capture(app, "12-xinyi-apple-after")
    }

    @MainActor
    func testTwoXinyiCornerPreviews() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        XCTAssertTrue(mode.wait(for: \.isEnabled, toEqual: true, timeout: 15))
        let lighting = app.buttons["cityMVP.lighting"]
        let isDay = NSPredicate(format: "value IN %@", ["Day", "白天"])
        let isNight = NSPredicate(format: "value IN %@", ["Night", "夜晚"])
        if isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        for (name, screenshot) in [
            ("市府路 × 信義路", "13-xinyi-city-hall"),
            ("松智路 × 信義路", "14-xinyi-songzhi"),
        ] {
            app.buttons["cityMVP.city"].tap()
            let corner = app.buttons[name]
            XCTAssertTrue(corner.waitForExistence(timeout: 5))
            corner.tap()
            waitForMode("District", on: mode)
            capture(app, screenshot)
            let viewport = app.windows.firstMatch
            if name.hasPrefix("市府路") {
                viewport.rotate(.pi * 0.85, withVelocity: 2)
            }
            viewport.pinch(withScale: 1.40, velocity: 0.75)
            waitForMode("District", on: mode)
            capture(app, "\(screenshot)-closer")
            capture(app, "\(screenshot)-traffic-later")
        }
        if !isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)], timeout: 5), .completed)
        capture(app, "15-xinyi-songzhi-night")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
    }

    @MainActor
    private func waitForMode(_ value: String, on element: XCUIElement, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 9), .completed, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
