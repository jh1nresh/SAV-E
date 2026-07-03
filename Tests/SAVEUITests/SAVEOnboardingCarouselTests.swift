import XCTest

final class SAVEOnboardingCarouselTests: XCTestCase {
    func testProofFirstFlowReachesOpenAppCTA() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]

        // Language step comes first.
        XCTAssertTrue(app.staticTexts["Hi, I'm Memo."].waitForExistence(timeout: 10))
        let englishChoice = app.buttons["onboarding.language.en"]
        XCTAssertTrue(englishChoice.exists)
        englishChoice.tap()
        primary.tap()

        // Clue step: cannot continue without a clue, sample fills it.
        XCTAssertTrue(app.staticTexts["Drop one messy clue"].waitForExistence(timeout: 5))
        XCTAssertFalse(primary.isEnabled)
        app.buttons["onboarding.sampleClue"].tap()
        XCTAssertTrue(primary.isEnabled)
        primary.tap()

        // Review Candidate demo.
        XCTAssertTrue(app.staticTexts["Memo found a likely place"].waitForExistence(timeout: 5))
        primary.tap()

        // Map Stamp demo is the final step; its CTA exits onboarding.
        XCTAssertTrue(app.staticTexts["You confirmed it. Stamped."].waitForExistence(timeout: 5))
        primary.tap()

        waitForDisappearance(of: primary)
    }

    func testNonLanguageStepsSkipOneAtATime() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]
        let skip = app.buttons["onboarding.skip"]

        // Language step is not skippable.
        XCTAssertTrue(app.staticTexts["Hi, I'm Memo."].waitForExistence(timeout: 10))
        XCTAssertFalse(skip.exists)
        primary.tap()

        XCTAssertTrue(app.staticTexts["Drop one messy clue"].waitForExistence(timeout: 5))
        skip.tap()

        XCTAssertTrue(app.staticTexts["Memo found a likely place"].waitForExistence(timeout: 5))
        skip.tap()

        // Skipping the final Map Stamp step exits onboarding.
        XCTAssertTrue(app.staticTexts["You confirmed it. Stamped."].waitForExistence(timeout: 5))
        skip.tap()

        waitForDisappearance(of: primary)
    }

    private func launchOnboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-reset-onboarding",
            "-save.appLanguage", "en"
        ]
        app.launch()
        return app
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 6) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: timeout)
    }
}
