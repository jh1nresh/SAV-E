import XCTest

final class SAVEOnboardingCarouselTests: SAVEUITestCase {
    @MainActor
    func testExampleKeepsOnePlaceAcrossThreeStates() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(primary.label, "Try this example")
        XCTAssertFalse(app.textViews["onboarding.clueEditor"].exists)
        assertActionVisible(primary, in: app)
        attach(app, name: "selected-a-en-source")
        primary.tap()
        XCTAssertTrue(app.staticTexts["Review Candidate"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Hidden Moon Cafe"].exists)
        attach(app, name: "selected-a-en-review")
        primary.tap()
        XCTAssertTrue(app.staticTexts["Map Stamp · Example"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Hidden Moon Cafe"].exists)
        XCTAssertEqual(primary.label, "Save my first place")
        attach(app, name: "selected-a-en-stamp")
        primary.tap()
        let editor = app.textViews["onboarding.clueEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertFalse(app.buttons["onboarding.continueClue"].isEnabled)
        app.buttons["onboarding.cancelInput"].tap()
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["opening.loading"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testTraditionalChineseExampleAndOptionalLanguage() {
        let app = launchOnboardingApp()
        XCTAssertTrue(app.buttons["onboarding.language"].waitForExistence(timeout: launchTimeout))
        app.buttons["onboarding.language"].tap()
        app.buttons["onboarding.language.zh-Hant"].tap()
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(primary.label, "用這個範例試試")
        assertActionVisible(primary, in: app)
        attach(app, name: "selected-a-zh-source")
        primary.tap()
        XCTAssertTrue(app.staticTexts["待確認地點"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "selected-a-zh-review")
        primary.tap()
        XCTAssertTrue(app.staticTexts["地圖章・範例"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "selected-a-zh-stamp")
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["opening.loading"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testRejectBackAndSkipDoNotRequireConfirmation() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: launchTimeout))
        primary.tap()
        app.buttons["onboarding.reject"].tap()
        XCTAssertTrue(app.buttons["onboarding.backToExample"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "selected-a-reject")
        app.buttons["onboarding.backToExample"].tap()
        XCTAssertTrue(app.staticTexts["Review Candidate"].waitForExistence(timeout: stepTimeout))
        app.buttons["onboarding.back"].tap()
        XCTAssertEqual(primary.label, "Try this example")
        let skip = app.buttons["onboarding.skip"]
        assertActionVisible(skip, in: app)
        skip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opening.loading"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testOwnClueBypassesFictionalResult() {
        let app = launchOnboardingApp()
        let own = app.buttons["onboarding.ownClue"]
        XCTAssertTrue(own.waitForExistence(timeout: launchTimeout))
        own.tap()
        let editor = app.textViews["onboarding.clueEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: stepTimeout))
        let next = app.buttons["onboarding.continueClue"]
        XCTAssertFalse(next.isEnabled)
        typeText("A quiet cafe in Taipei", into: editor)
        XCTAssertTrue(next.isEnabled)
        assertActionVisible(next, in: app)
        attach(app, name: "selected-a-own-clue")
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opening.loading"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.staticTexts["Hidden Moon Cafe"].exists)
    }

    @MainActor
    func testLargeTypeKeepsPrimaryAndSkipReachable() {
        let app = launchOnboardingApp(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: launchTimeout))
        assertActionVisible(primary, in: app)
        assertActionVisible(app.buttons["onboarding.skip"], in: app)
        assertActionVisible(app.buttons["onboarding.ownClue"], in: app)
        attach(app, name: "selected-a-large-type")
        primary.tap()
        assertActionVisible(primary, in: app)
    }

    @MainActor
    private func launchOnboardingApp(extra: [String] = []) -> XCUIApplication {
        let app = makeApp(launchArguments: [
            "--uitest-reset-onboarding", "--uitest-hold-opening",
            "-save.appLanguage", "en"
        ] + extra, launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()])
        launch(app)
        return app
    }

    @MainActor
    private func assertActionVisible(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntilHittable(element), file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, file: file, line: line)
    }
}
