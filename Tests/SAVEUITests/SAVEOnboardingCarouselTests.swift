import XCTest

final class SAVEOnboardingCarouselTests: XCTestCase {
    @MainActor
    func testProofFirstFlowReachesOpenAppCTA() {
        let app = launchOnboardingApp()
        let primary = app.buttons["onboarding.primary"]

        // Language step comes first.
        XCTAssertTrue(app.staticTexts["Hi, I'm Memo."].waitForExistence(timeout: 10))
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.isHittable)
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
        assertFullyVisible(app.staticTexts["It stays in review until you confirm — no fake pins."], in: app)
        let reviewStage = app.descendants(matching: .any)["onboarding.pocketStage.review"]
        XCTAssertTrue(waitForReady(reviewStage))
        attach(app, name: "first-run-03-review")
        primary.tap()

        // Map Stamp demo is the final step; its CTA exits onboarding.
        assertFullyVisible(app.staticTexts["You confirmed it. Stamped."], in: app)
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
        XCTAssertTrue(opening.waitForExistence(timeout: 3))
        attach(app, name: "first-run-05-opening")
    }

    @MainActor
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

    @MainActor
    private func launchOnboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-reset-onboarding",
            "--uitest-hold-opening",
            "-save.appLanguage", "en"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 6) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: timeout)
    }

    @MainActor
    private func waitForReady(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let ready = expectation(
            for: NSPredicate(format: "value == 'ready'"),
            evaluatedWith: element
        )
        return XCTWaiter.wait(for: [ready], timeout: timeout) == .completed
    }

    @MainActor
    private func assertFullyVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, file: file, line: line)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
