import XCTest

final class CityMVPVisualTests: XCTestCase {
    @MainActor
    func testMapFirstNavigationAndAgent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        waitForAlignment(on: app)
        let lighting = app.buttons["cityMVP.lighting"]
        let isNight = NSPredicate(format: "value IN %@", ["Night", "夜晚"])
        let isDay = NSPredicate(format: "value IN %@", ["Day", "白天"])
        if isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        capture(app, "01-world")
        chooseMapMenu("台北 Taipei", on: app)
        waitForMode("Overview", on: app)
        capture(app, "02-taipei")
        mode.tap()
        waitForMode("District", on: app)
        capture(app, "03-xinyi-3d")
        chooseMapMenu("Places 地點", on: app)
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
        waitForMode("Overview", on: app)
        XCTAssertTrue(panel.exists, "Zooming out should keep the same place selected")
        capture(app, "05-back-to-taipei")

        chooseMapMenu("SAV-E Agent", on: app)
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
        waitForMode("District", on: app)
        chooseMapMenu("Places 地點", on: app)
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
    func testNativePinchKeepsLandmarkSelectedAcrossDistrict() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-xinyi", "--verify-xinyi-overview-journey", "-cityMVP.night", "NO"]
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        waitForAlignment(on: app)
        let lighting = app.buttons["cityMVP.lighting"].value as? String ?? ""
        XCTAssertTrue(["Day", "白天"].contains(lighting), "The overview comparison requires daytime")
        chooseMapMenu("台北 Taipei", on: app)
        let settledOverview = NSPredicate(format: "identifier == %@ AND value MATCHES %@",
                                          "cityMVP.mode", "Overview 2[89][0-9]{2} 100%")
        let reachedOverview = app.buttons.matching(settledOverview).firstMatch.waitForExistence(timeout: 9)
        if !reachedOverview { capture(app, "09-xinyi-overview-unexpected") }
        XCTAssertTrue(reachedOverview, "Expected 2.9 km at full opacity. Observed \(mode.value ?? "unavailable")")
        let unselected = app.buttons["cityMVP.groundPin.landmark-101"]
        XCTAssertTrue(unselected.waitForExistence(timeout: 9))
        unselected.tap()
        let selection = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        XCTAssertTrue(panel.exists)
        let title = selection.label
        let initialAnchor = selection.frame
        let pinTitle = app.staticTexts["cityMVP.selectedGroundPinTitle"]
        capture(app, "10-xinyi-modeled-overview")
        XCTAssertTrue(pinTitle.exists)
        XCTAssertGreaterThan(pinTitle.frame.minY, selection.frame.maxY, "The overview title must clear the photo")

        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        XCTAssertTrue(map.exists)
        map.pinch(withScale: 1.95, velocity: 0.72)
        waitForMode("District", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertTrue(panel.exists)
        capture(app, "11-xinyi-district-selected")
        XCTAssertTrue(pinTitle.exists)
        XCTAssertEqual(pinTitle.label, title)
        XCTAssertLessThan(selection.frame.maxY, panel.frame.minY, "The photo badge must clear the card")
        XCTAssertLessThan(pinTitle.frame.maxY, selection.frame.minY, "The title should flip above the badge")
        app.buttons["cityMVP.placeDetails"].tap()
        XCTAssertTrue(app.buttons["Save this place"].waitForExistence(timeout: 5))
        capture(app, "11-xinyi-place-details")
        // SwiftUI exposes links as controls whose AX type varies by OS.
        for label in ["View source", "Photo: AnthonySantiago101"] {
            let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(link.exists, app.debugDescription)
            XCTAssertTrue(link.isHittable)
        }
        app.buttons["cityMVP.placeDetails.done"].tap()
        XCTAssertTrue(app.buttons["cityMVP.placeDetails"].waitForExistence(timeout: 5))
        XCTAssertEqual(selection.label, title, "Dismissing details must retain selection")
        map.pinch(withScale: 0.54, velocity: -0.72)
        waitForMode("Overview", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertTrue(panel.exists)
        XCTAssertLessThan(hypot(selection.frame.midX - initialAnchor.midX,
                                selection.frame.maxY - initialAnchor.maxY), 65)
        capture(app, "12-xinyi-overview-after")

        let initialHeading = try XCTUnwrap((map.value as? String).flatMap(Int.init))
        let rotatedHeadings = (0...360).filter { heading in
            let turn = abs(heading - initialHeading)
            return min(turn, 360 - turn) > 10
        }.map(String.init)
        map.rotate(0.55, withVelocity: 0.65)
        let rotated = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND value IN %@", "cityMVP.pinchArea", rotatedHeadings)).firstMatch
        let changedHeading = rotated.waitForExistence(timeout: 6)
        capture(app, "12-xinyi-overview-rotated")
        XCTAssertTrue(changedHeading, "The two-finger rotation must change the camera heading")
        waitForMode("Overview", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)

        map.pinch(withScale: 0.55, velocity: -0.60)
        // 4,150 m is where the district fade reaches zero. A failed local fit
        // can also show zero opacity, so require the real distance as well.
        let nativeDistance = "(?:41[5-9][0-9]|4[2-9][0-9]{2}|[5-9][0-9]{3}|[1-9][0-9]{4,})"
        let flat = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value MATCHES %@",
                                                    "cityMVP.mode", "Map \(nativeDistance) 0%")).firstMatch
        let reachedFlat = flat.waitForExistence(timeout: 9)
        capture(app, "12-xinyi-native-return")
        XCTAssertTrue(reachedFlat, "Expected the native map at zero model opacity. Observed \(mode.value ?? "unavailable")")
        XCTAssertEqual(selection.label, title)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
    }

    @MainActor
    private func waitForAlignment(on app: XCUIApplication) {
        let mode = app.buttons["cityMVP.mode"]
        XCTAssertTrue(mode.wait(for: \.isEnabled, toEqual: true, timeout: 15))
        if mode.value as? String == "Alignment unavailable" {
            capture(app, "00-map-alignment-retry")
            XCTAssertEqual(mode.label, "Retry map alignment")
            mode.tap()
            let retryFinished = NSPredicate(format: "identifier == %@ AND enabled == true AND (value BEGINSWITH %@ OR value BEGINSWITH %@ OR value BEGINSWITH %@)",
                                            "cityMVP.mode", "Map", "Overview", "District")
            XCTAssertTrue(app.buttons.matching(retryFinished).firstMatch.waitForExistence(timeout: 15))
        }
        let ready = NSPredicate(format: "identifier == %@ AND enabled == true AND (value BEGINSWITH %@ OR value BEGINSWITH %@ OR value BEGINSWITH %@)",
                                "cityMVP.mode", "Map", "Overview", "District")
        XCTAssertTrue(app.buttons.matching(ready).firstMatch.waitForExistence(timeout: 1),
                      "Map alignment must succeed before testing the district")
    }

    @MainActor
    func testTwoXinyiCornerPreviews() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-xinyi"]
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        waitForAlignment(on: app)
        let lighting = app.buttons["cityMVP.lighting"]
        let isDay = NSPredicate(format: "value IN %@", ["Day", "白天"])
        let isNight = NSPredicate(format: "value IN %@", ["Night", "夜晚"])
        if isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        for (name, screenshot) in [
            ("市府路 × 信義路", "13-xinyi-city-hall"),
            ("松智路 × 信義路", "14-xinyi-songzhi"),
            ("臺北市政府 Taipei City Hall", "16-xinyi-civic"),
        ] {
            chooseMapMenu(name, on: app)
            waitForMode("District", on: app)
            capture(app, screenshot)
            if screenshot == "16-xinyi-civic" {
                let daytimeCamera = mode.value as? String
                lighting.tap()
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)],
                                             timeout: 5), .completed)
                XCTAssertEqual(mode.value as? String, daytimeCamera)
                capture(app, "16-xinyi-civic-night-streets")
                lighting.tap()
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)],
                                             timeout: 5), .completed)
                XCTAssertEqual(mode.value as? String, daytimeCamera)
            }
            let viewport = app.windows.firstMatch
            if name.hasPrefix("市府路") {
                viewport.rotate(.pi * 0.85, withVelocity: 2)
            }
            viewport.pinch(withScale: 1.40, velocity: 0.75)
            waitForMode("District", on: app)
            capture(app, "\(screenshot)-closer")
            capture(app, "\(screenshot)-traffic-later")
        }
        if !isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)], timeout: 5), .completed)
        capture(app, "17-xinyi-civic-night")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
    }

    @MainActor
    private func chooseMapMenu(_ title: String, on app: XCUIApplication, line: UInt = #line) {
        let menu = app.buttons["cityMVP.city"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8), line: line)
        menu.tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), line: line)
        item.tap()
    }

    @MainActor
    private func waitForMode(_ value: String, on app: XCUIApplication, line: UInt = #line) {
        // Re-query the mode in each snapshot: retaining a resolved element across
        // the native/3D update can keep XCTest's pre-transition value cached.
        let matching = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND value BEGINSWITH %@", "cityMVP.mode", value)).firstMatch
        XCTAssertTrue(matching.waitForExistence(timeout: 9), line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
