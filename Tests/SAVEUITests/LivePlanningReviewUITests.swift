#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW && SAVVY_CITY_MVP && targetEnvironment(simulator)
import XCTest

/// Actual ContentView/root/canonical modal rail; all input and screenshots are explicitly synthetic.
final class LivePlanningReviewUITests: SAVEUITestCase {
    @MainActor
    func testActualReviewRecoveryLight() throws { try verifyRecovery(dark: false) }

    @MainActor
    func testActualReviewRecoveryDark() throws { try verifyRecovery(dark: true) }

    @MainActor
    func testActualReviewRecoveryLargeType() throws { try verifyRecovery(dark: false, largeType: true) }

    @MainActor
    func testInvalidLaunchAndAccountActionsStayOutsideSharedDestinations() throws {
        let invalid = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-reset-account-gate"],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(invalid)
        XCTAssertTrue(invalid.staticTexts["live.fixture.unavailable"].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(invalid.descendants(matching: .any)["live.library"].exists)
        terminate(invalid)

        let isolated = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--map-mode-personal", "--preview-account", "--uitest-force-light"],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(isolated)
        let passport = isolated.descendants(matching: .any)["live.passport"].firstMatch
        XCTAssertTrue(passport.waitForExistence(timeout: launchTimeout))
        let account = isolated.buttons["live.passport.account"]
        tap(account, in: isolated)
        XCTAssertTrue(passport.exists)
        XCTAssertTrue(account.isHittable, "Fixture account action must keep the read-only fixture visible")
        XCTAssertFalse(isolated.descendants(matching: .any)["live.fixture.accountUnavailable"].exists)
        attach(isolated, name: "synthetic-live-review-account-action-blocked")
    }

    @MainActor
    private func verifyRecovery(dark: Bool, largeType: Bool = false) throws {
        let theme = largeType ? "large-type" : (dark ? "dark" : "light")
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--preview-tab-saved", "--map-mode-personal", "--uitest-location-denied",
            dark ? "--uitest-force-dark" : "--uitest-force-light", "-save.appLanguage", "en"]
            + (largeType ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        addTeardownBlock { @MainActor in
            if (self.testRun?.failureCount ?? 0) > 0, app.state == .runningForeground {
                self.attach(app, name: "synthetic-live-review-\(theme)-failure")
            }
        }
        launch(app)
        let library = app.descendants(matching: .any)["live.library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: launchTimeout), "Exact fixture launch must reach the real Saved root")
        XCTAssertFalse(app.descendants(matching: .any)["live.fixture.unavailable"].exists)
        let older = reviewRows(app).matching(NSPredicate(format: "label CONTAINS %@", "Earlier fixture clue")).firstMatch
        XCTAssertTrue(older.waitForExistence(timeout: stepTimeout))
        attach(app, name: "synthetic-live-review-\(theme)-initial-root")

        tap(app.buttons["live.library.add"], in: app)
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        typeText("1. Harbor Oven Pizza\nLos Angeles\n2. Fixture Tea House\nLos Angeles", into: input)
        let keyboardDone = app.buttons["capture.keyboardDone"]
        if keyboardDone.exists { tap(keyboardDone, in: app) }
        tap(app.buttons["capture.analyze"], in: app)
        let showAll = app.buttons["live.library.review.showAll"]
        XCTAssertTrue(showAll.waitForExistence(timeout: timeout(20)))
        XCTAssertTrue(waitUntilHittable(showAll))
        XCTAssertEqual(reviewRows(app).count, 2)
        XCTAssertFalse(older.exists, "The current batch must exclude the retained older clue")
        XCTAssertEqual(savedRows(app).count, 0)
        attach(app, name: "synthetic-live-review-\(theme)-two-result-batch")

        tap(showAll, in: app)
        reveal(older, in: app)
        XCTAssertTrue(older.exists, "Show all must restore the retained older clue")
        XCTAssertFalse(showAll.exists)
        let harbor = reviewRows(app).matching(NSPredicate(format: "label CONTAINS %@", "Harbor Oven Pizza")).firstMatch
        reveal(harbor, in: app, upwards: false)
        tap(harbor, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["drawer.review.header"].firstMatch.waitForExistence(timeout: stepTimeout))
        let searchAction = app.buttons["drawer.review.addClue"].exists
            ? app.buttons["drawer.review.addClue"] : app.buttons["drawer.review.changePlace"]
        tap(searchAction, in: app)
        let search = app.descendants(matching: .any)["live.review.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: stepTimeout))
        let searchInput = app.textFields["map.search.input"]
        XCTAssertTrue(searchInput.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue((searchInput.value as? String)?.contains("Harbor Oven Pizza") == true)
        let result = app.buttons["map.search.candidate.review-map-result-fixture"]
        XCTAssertTrue(result.waitForExistence(timeout: stepTimeout))
        attach(app, name: "synthetic-live-review-\(theme)-canonical-search")
        tap(result, in: app)
        XCTAssertTrue(app.buttons["drawer.unsaved.primaryAction"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(app.staticTexts["drawer.unsaved.title"].label, "Harbor Oven Pizza — corrected branch")
        XCTAssertEqual(app.staticTexts["drawer.unsaved.state"].label, "Map search result · Not saved")
        XCTAssertFalse(app.staticTexts["Public discovery · Not saved yet"].exists,
                       "A map-search candidate is not a public social post")
        let saveAction = app.buttons["drawer.unsaved.primaryAction"]
        reveal(saveAction, in: app)
        XCTAssertTrue(saveAction.isHittable, "The unsaved result must retain a reachable Save action without saving")
        attach(app, name: "synthetic-live-review-\(theme)-unsaved-result")
        // Nil auth intentionally prevents a save-success claim. Exercise close/return only.
        let close = app.buttons["drawer.place.close"]
        XCTAssertTrue(close.waitForExistence(timeout: stepTimeout))
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        tap(close, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: stepTimeout), "Result close must restore its exact-search surface")
        XCTAssertTrue(searchInput.exists)
        tap(app.buttons["map.search.close"], in: app)
        XCTAssertTrue(library.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["live.library.review"].firstMatch.exists)
        XCTAssertEqual(savedRows(app).count, 0, "Review/search/result close cannot create a saved place")
        reveal(harbor, in: app, upwards: false)
        XCTAssertTrue(harbor.exists)
        attach(app, name: "synthetic-live-review-\(theme)-returned-root-no-save")
    }

    @MainActor
    private func reviewRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", #"^live\.library\.review\.[0-9A-Fa-f-]{36}$"#))
    }

    @MainActor
    private func savedRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", #"^live\.library\.place\.[0-9A-Fa-f-]{36}$"#))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<4 {
            if element.exists && element.isHittable { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: stepTimeout))
        reveal(element, in: app)
        XCTAssertTrue(element.isHittable, "Expected a reachable native control: \(element.identifier)")
        element.tap()
    }
}
#endif
