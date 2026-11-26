#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW && targetEnvironment(simulator)
import XCTest

/// Actual ContentView/root/canonical modal rail; all input and screenshots are explicitly synthetic.
final class LivePlanningReviewUITests: SAVEUITestCase {

    @MainActor
    func testReviewedVenueOriginalsFromSavedAndExplore() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SAVE_UI_TEST_LIVE_VENUE_ORIGINALS"] == "1",
                          "Explicit live test of the publisher frames in an isolated simulator fixture.")
        executionTimeAllowance = 210
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--uitest-reviewed-venue-posts", "--preview-tab-saved"],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        let saved = app.buttons["live.library.place.C77AF9C1-064A-45D0-833D-E0C809C1F013"]
        XCTAssertTrue(saved.waitForExistence(timeout: launchTimeout))
        let initialState = saved.label
        XCTAssertTrue(saved.isHittable)
        saved.coordinate(withNormalizedOffset: .init(dx: 0.40, dy: 0.28)).tap()
        XCTAssertTrue(app.buttons["live.place.close"].waitForExistence(timeout: 10),
                      "Tapping the Saved place name must open its detail")
        attach(app, name: "reviewed-venue-saved-entry")
        let section = app.descendants(matching: .any)["live.saved.venuePosts"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 12), "Saved place must load reviewed sources automatically")

        func open(_ id: String, caption: String) {
            let button = app.buttons["live.discovery.original.\(id)"]
            reveal(button, in: app)
            XCTAssertTrue(button.waitForExistence(timeout: 12))
            XCTAssertTrue(button.isHittable)
            tap(button, in: app)
            let web = app.webViews["live.sourcePost.web"].firstMatch
            XCTAssertTrue(web.waitForExistence(timeout: stepTimeout))
            let body = web.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", caption)).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 18), "Expected the publisher caption for \(id)")
            for _ in 0..<3 where !web.frame.intersects(body.frame) { web.swipeUp() }
            XCTAssertTrue(web.frame.intersects(body.frame), "The publisher caption must be on screen for \(id)")
            XCTAssertTrue(app.buttons["live.sourcePost.original"].exists)
            attach(app, name: "reviewed-venue-\(id)")
            let done = app.buttons["live.sourcePost.close"]
            tap(done, in: app)
            XCTAssertTrue(done.waitForNonExistence(timeout: 6), "Done should close the original post sheet")
        }

        open("instagram:DEzpGLmtFWf", caption: "新春限時快閃")
        open("threads:DeZTko_k3-V", caption: "不用飛馬來西亞")
        tap(app.buttons["live.place.close"], in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(saved.label, initialState)

        tap(app.buttons["demo.tab.map"], in: app)
        let group = app.buttons["live.map.pin.group.public:apple_maps:FixtureCafe"]
        XCTAssertTrue(group.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(group.value as? String, "Includes a recent topic")
        tap(group, in: app)
        tap(app.buttons["Neighbor Fixture"], in: app)
        XCTAssertTrue(app.staticTexts["Neighbor Fixture"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["live.discovery.recentTopic"].exists)
        tap(app.buttons["live.discovery.detail.close"], in: app)
        tap(group, in: app)
        tap(app.buttons["Café Fixture"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["live.discovery.recentTopic"].waitForExistence(timeout: stepTimeout))
        open("threads:DeZTko_k3-V", caption: "不用飛馬來西亞")

        let all = app.buttons["live.discovery.allPosts"]
        reveal(all, in: app)
        tap(all, in: app)
        let missing = app.buttons["live.discovery.original.threads:FixtureUnlistedSavvyB"]
        reveal(missing, in: app)
        tap(missing, in: app)
        let retry = app.buttons["live.sourcePost.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 22))
        tap(retry, in: app)
        XCTAssertTrue(app.buttons["live.sourcePost.original"].exists)
        tap(app.buttons["live.sourcePost.close"], in: app)
        tap(app.buttons["live.discovery.detail.close"], in: app)
        tap(app.buttons["demo.tab.saved"], in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(saved.label, initialState)
    }

    @MainActor
    func testSelectedMapTabExpandsItsLayerOptions() {
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--preview-tab-saved", "-save.appLanguage", "en"],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        let mapTab = app.buttons["demo.tab.map"]
        let savedTab = app.buttons["demo.tab.saved"]
        let mapSearch = app.buttons["live.search"]
        let panel = app.descendants(matching: .any)["live.map.tabOptions"].firstMatch

        tap(mapTab, in: app)
        XCTAssertTrue(mapSearch.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(panel.exists, "Entering Map should leave its layer controls collapsed")

        let collapsedTab = mapTab.frame
        tap(mapTab, in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: stepTimeout))
        let savedOnly = panel.switches["live.mode.personal"]
        XCTAssertTrue(savedOnly.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(mapTab.frame.minY, collapsedTab.minY, accuracy: 1)
        XCTAssertEqual(mapTab.frame.midX, collapsedTab.midX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(savedOnly.frame.minY, collapsedTab.maxY)
        XCTAssertEqual(savedOnly.value as? String, "0")
        savedOnly.tap()
        XCTAssertEqual(savedOnly.value as? String, "1")

        app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.78)).tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(mapSearch.exists, "Collapsing the controls must leave the Map tab open")

        tap(mapTab, in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(savedOnly.value as? String, "1", "The expanded tab and map share the same layer state")
        tap(mapTab, in: app)
        XCTAssertTrue(panel.waitForNonExistence(timeout: stepTimeout))

        tap(savedTab, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["live.library"].firstMatch.waitForExistence(timeout: stepTimeout))
        tap(mapTab, in: app)
        XCTAssertTrue(mapSearch.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(panel.exists, "Returning from Saved must not reopen the layer controls")
    }

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
