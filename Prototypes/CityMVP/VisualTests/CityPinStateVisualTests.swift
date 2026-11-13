import XCTest

/// Isolated native-map layout fixtures, never normal user places or a social feed.
final class CityPinStateVisualTests: XCTestCase {
    @MainActor
    func testNativeStatePinsKeepTheirAnchorAndCallbackInBothLanguagesAndPalettes() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        print("NATIVE_PIN_STATE_LAYOUT_V1")
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground { self.capture(app, "pin-state-terminal") }
            app.terminate()
        }
        // Missing the unique fixture identity must leave the normal root intact.
        app.launchArguments = ["--inspect-citylab", "--inspect-state-pin-layout", "-save.appLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.buttons["cityMVP.tab.map"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Pin layout · fixtures"].exists)
        app.terminate()
        for language in ["en", "zh-Hant"] {
            app.launchArguments = ["--inspect-citylab", "--inspect-state-pin-layout", "-save.appLanguage", language]
            app.launchEnvironment["CITY_PIN_LAYOUT_TEST_ID"] = UUID().uuidString
            app.launch()
            XCTAssertTrue(app.staticTexts["Pin layout · fixtures"].waitForExistence(timeout: 15))
            let mode = app.buttons["cityMVP.pinState.lighting"]
            XCTAssertEqual(mode.value as? String, "day")
            let selection = app.staticTexts["cityMVP.pinState.selection"]
            XCTAssertEqual(selection.value as? String, "none")
            let states: [(String, String, String)] = [
                ("saved", "map.pin.saved.00000000-0000-0000-0000-000000000101", "收藏範例"),
                ("review", "map.pin.review.00000000-0000-0000-0000-000000000102", "待確認咖啡"),
                ("search", "map.pin.unsaved.layout-search", "A very long cafe name near City Hall"),
                ("shared", "map.pin.social.00000000-0000-0000-0000-000000000103", "朋友分享範例")
            ]
            func find(_ identifier: String) -> XCUIElement {
                app.descendants(matching: .any)[identifier].firstMatch
            }
            for (_, identifier, name) in states {
                let pin = find(identifier)
                XCTAssertTrue(pin.waitForExistence(timeout: 12))
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 1)
                XCTAssertTrue(pin.label.contains(name), "Original title must remain available in full")
                XCTAssertTrue(app.frame.contains(pin.frame))
                XCTAssertGreaterThanOrEqual(pin.frame.width, 44 - 0.001)
                XCTAssertGreaterThanOrEqual(pin.frame.height, 44 - 0.001)
            }
            capture(app, "pin-state-" + language + "-day")
            var count = 0
            for (state, identifier, _) in states {
                let pin = find(identifier)
                let before = pin.frame
                // Native Map annotations may be reported as Other; prove the
                // callback with an actual touch inside the rendered control.
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: before.midX, dy: before.midY)).tap()
                let changed = NSPredicate(format: "value == %@", state)
                expectation(for: changed, evaluatedWith: selection)
                waitForExpectations(timeout: 12)
                count += 1
                XCTAssertEqual(app.staticTexts["cityMVP.pinState.callbacks"].label, "Callbacks: \(count)")
                if state != "saved" {
                    let after = find(identifier).frame
                    XCTAssertEqual(after.width, 140, accuracy: 1)
                    XCTAssertEqual(after.height, 124, accuracy: 1)
                    XCTAssertEqual(after.midX, before.midX, accuracy: 2)
                    XCTAssertEqual(after.minY + 72, before.minY + 72, accuracy: 2)
                }
                if state == "review" { capture(app, "pin-state-" + language + "-review-selected") }
            }
            mode.tap()
            XCTAssertEqual(mode.value as? String, "night")
            capture(app, "pin-state-" + language + "-night-shared-selected")
            for (_, identifier, name) in states {
                XCTAssertTrue(find(identifier).label.contains(name))
            }
            app.terminate()
        }
    }

    @MainActor
    func testFriendsCopyUsesAppLanguageWithoutChangingDraftTextV1() {
        continueAfterFailure = false
        executionTimeAllowance = 180
        print("FRIEND_COPY_LANGUAGE_V1")
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground { self.capture(app, "friends-copy-terminal") }
            app.terminate()
        }
        for (language, title, openLabel, senderPlaceholder, reasonPlaceholder) in [
            ("en", "Friends’ recommendations", "Open a recommendation file", "Your sender label (self-declared)", "Why you recommend these places"),
            ("zh-Hant", "朋友推薦", "開啟推薦檔案", "你的分享者名稱（自行填寫）", "推薦這些地點的原因")
        ] {
            app.launchArguments = ["--inspect-citylab", "-save.appLanguage", language]
            app.launch()
            let passport = app.buttons["cityMVP.tab.passport"]
            XCTAssertTrue(passport.waitForExistence(timeout: 20)); passport.tap()
            let friends = app.buttons["cityMVP.passport.friends"]
            XCTAssertTrue(friends.waitForExistence(timeout: 8)); friends.tap()
            let open = app.buttons["cityMVP.friends.import"]
            XCTAssertTrue(open.waitForExistence(timeout: 8))
            XCTAssertEqual(open.label, openLabel)
            XCTAssertTrue(app.navigationBars[title].exists)
            let sender = app.textFields["cityMVP.friends.sender"]
            let reason = app.textFields["cityMVP.friends.reason"]
            XCTAssertEqual(sender.placeholderValue, senderPlaceholder)
            XCTAssertEqual(reason.placeholderValue, reasonPlaceholder)
            capture(app, "friends-copy-" + language + "-initial")
            sender.tap(); sender.typeText("Lina 朋友")
            reason.tap(); reason.typeText("Tea 茶 original")
            app.buttons["cityMVP.friends.keyboardDone"].tap()
            XCTAssertEqual(sender.value as? String, "Lina 朋友")
            XCTAssertEqual(reason.value as? String, "Tea 茶 original")
            capture(app, "friends-copy-" + language + "-draft")
            app.buttons["cityMVP.friends.exchange.done"].tap()
            XCTAssertTrue(open.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
