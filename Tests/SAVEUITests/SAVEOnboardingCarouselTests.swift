import XCTest

final class SAVEOnboardingCarouselTests: SAVEUITestCase {
    @MainActor
    func testProofFirstFlowReachesOpenAppCTA() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]

        // Language step comes first.
        XCTAssertTrue(app.staticTexts["Hi, I'm Memo."].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(primary.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(waitUntilHittable(primary))
        XCTAssertLessThanOrEqual(primary.frame.maxY, app.frame.maxY - 8)
        attach(app, name: "first-run-01-language")
        let englishChoice = app.buttons["onboarding.language.en"]
        XCTAssertTrue(englishChoice.exists)
        englishChoice.tap()
        primary.tap()

        // Clue step: cannot continue without a clue, sample fills it.
        assertFullyVisible(app.staticTexts["Drop one messy clue"], in: app)
        let clueSubtitle = app.staticTexts["A link, caption, or note is enough."]
        assertFullyVisible(clueSubtitle, in: app)
        XCTAssertFalse(primary.isEnabled)
        app.buttons["onboarding.sampleClue"].tap()
        XCTAssertTrue(primary.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.pocketStage.clue"].exists)
        let clueEditor = app.textViews["onboarding.clueEditor"]
        XCTAssertTrue(clueEditor.exists)
        XCTAssertLessThanOrEqual(clueSubtitle.frame.maxY + 12, clueEditor.frame.minY)
        attach(app, name: "first-run-02-clue")
        primary.tap()

        // Review Candidate demo.
        assertFullyVisible(app.staticTexts["Memo found a likely place"], in: app)
        assertFullyVisible(app.staticTexts["It stays in review until you confirm."], in: app)
        let reviewStage = app.descendants(matching: .any)["onboarding.pocketStage.review"]
        XCTAssertTrue(waitForReady(reviewStage))
        attach(app, name: "first-run-03-review")
        primary.tap()

        // Map Stamp demo is the final step; its CTA exits onboarding.
        assertFullyVisible(app.staticTexts["Demo complete. Stamped."], in: app)
        assertFullyVisible(
            app.staticTexts["Only places you confirm become private Map Stamps."],
            in: app
        )
        let mapStampStage = app.descendants(matching: .any)["onboarding.pocketStage.mapStamp"]
        XCTAssertTrue(waitForReady(mapStampStage))
        attach(app, name: "first-run-04-map-stamp")
        primary.tap()

        waitForDisappearance(of: primary)
        let opening = app.descendants(matching: .any)["opening.loading"]
        XCTAssertTrue(opening.waitForExistence(timeout: stepTimeout))
        attach(app, name: "first-run-05-opening")
    }

    @MainActor
    func testNonLanguageStepsSkipOneAtATime() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]
        let skip = app.buttons["onboarding.skip"]

        // Language step is not skippable.
        XCTAssertTrue(app.staticTexts["Hi, I'm Memo."].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(skip.exists)
        primary.tap()

        XCTAssertTrue(app.staticTexts["Drop one messy clue"].waitForExistence(timeout: stepTimeout))
        skip.tap()

        XCTAssertTrue(app.staticTexts["Memo found a likely place"].waitForExistence(timeout: stepTimeout))
        skip.tap()

        // Skipping the final Map Stamp step exits onboarding.
        XCTAssertTrue(app.staticTexts["Demo complete. Stamped."].waitForExistence(timeout: stepTimeout))
        skip.tap()

        waitForDisappearance(of: primary)
    }

    @MainActor
    private func launchOnboardingApp() -> XCUIApplication {
        let app = makeApp(launchArguments: [
            "--uitest-reset-onboarding",
            "--uitest-hold-opening",
            "-save.appLanguage", "en"
        ])
        launch(app)
        return app
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: stepTimeout)
    }

    @MainActor
    private func waitForReady(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: stepTimeout) else { return false }
        let ready = expectation(
            for: NSPredicate(format: "value == 'ready'"),
            evaluatedWith: element
        )
        return XCTWaiter.wait(for: [ready], timeout: stepTimeout) == .completed
    }

    @MainActor
    private func assertFullyVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            waitUntilHittable(element),
            "Element never settled into a hittable state.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, file: file, line: line)
    }
}
