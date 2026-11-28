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

#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW && targetEnvironment(simulator)
import XCTest

final class LiveCreatorOriginalsUITests: SAVEUITestCase {
    @MainActor
    func testLiveNativeSourceDisclosureAndOriginalDestinations() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SAVE_LIVE_APPLE_PLACE_PROBE"] == "1", "Explicit public native lookup")
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline", "--uitest-native-creator-sources"],
                          launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString, "SAVE_LIVE_APPLE_PLACE_PROBE": "1"])
        launch(app)
        let toggle = app.buttons["live.place.otherMentions"]
        XCTAssertTrue(toggle.waitForExistence(timeout: stepTimeout))
        let urls = ["https://www.threads.com/@zeke_6973/post/Dd_T2fQAXTU",
                    "https://www.threads.com/@zeke_6973/post/DfEObM2ID6l",
                    "https://www.threads.com/@zeke_6973/post/DfEPZk4IGxq"]
        func link(_ url: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "live.place.original." + url).firstMatch
        }
        func reveal(_ element: XCUIElement, upward: Bool = true) {
            for _ in 0..<6 {
                if element.exists && element.isHittable { return }
                if upward { app.swipeUp() } else { app.swipeDown() }
            }
            XCTAssertTrue(element.isHittable)
        }
        XCTAssertTrue(link(urls[0]).exists)
        XCTAssertFalse(link(urls[1]).exists)
        XCTAssertFalse(link(urls[2]).exists)
        reveal(toggle)
        attach(app, name: "live-jingmei-one-source-collapsed")
        toggle.tap()
        XCTAssertTrue(link(urls[1]).waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(link(urls[2]).exists)
        reveal(link(urls[2]))
        attach(app, name: "live-jingmei-other-mentions-expanded")
        for (index, url) in urls.enumerated() {
            reveal(link(url), upward: index > 0)
            link(url).tap()
            XCTAssertEqual(app.staticTexts["probe.openedURL"].label, url,
                           "Each actual Link must hand off its own original URL")
        }
        reveal(toggle, upward: false)
        toggle.tap()
        XCTAssertTrue(link(urls[1]).waitForNonExistence(timeout: stepTimeout))
        XCTAssertFalse(link(urls[2]).exists)
        XCTAssertTrue(link(urls[0]).exists)
    }
}
#endif

#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW && targetEnvironment(simulator)
final class LiveMapSearchUXUITests: SAVEUITestCase {
    @MainActor
    func testSearchSheetResultsReturnAndHistory() throws {
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline", "--uitest-map-search"],
                          launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        let map = app.buttons["demo.tab.map"]
        XCTAssertTrue(map.waitForExistence(timeout: stepTimeout)); map.tap()
        let open = app.buttons["live.search"]
        XCTAssertTrue(open.waitForExistence(timeout: stepTimeout)); open.tap()
        let food = app.buttons["live.map.search.nearby.food"]
        XCTAssertTrue(food.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["live.map.search.nearby.coffee"].exists)
        XCTAssertFalse(app.buttons["live.map.search.clearRecent"].exists)
        let close = app.buttons["live.map.search.close"]
        XCTAssertGreaterThan(close.frame.minY, app.frame.height * 0.35, "Search begins as a half sheet")
        attach(app, name: "map-search-half-sheet-initial")
        food.tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.map.search.result.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: stepTimeout)); result.tap()
        let detailClose = app.buttons["live.place.close"]
        XCTAssertTrue(detailClose.waitForExistence(timeout: stepTimeout), "Pick must open the native place detail")
        XCTAssertTrue(app.staticTexts["Search Fixture Café"].exists)
        detailClose.tap()
        XCTAssertTrue(open.waitForExistence(timeout: stepTimeout)); open.tap()
        XCTAssertTrue(result.waitForExistence(timeout: stepTimeout))
        let search = app.searchFields.firstMatch
        XCTAssertEqual(search.value as? String, "Food")
        attach(app, name: "map-search-preserved-results")
        search.tap()
        search.buttons.firstMatch.tap()
        let recent = app.buttons["live.map.search.recent.Food"]
        XCTAssertTrue(recent.waitForExistence(timeout: stepTimeout))
        app.swipeUp()
        attach(app, name: "map-search-recent-and-categories")
        let clear = app.buttons["live.map.search.clearRecent"]
        XCTAssertTrue(clear.isHittable); clear.tap()
        XCTAssertFalse(recent.exists)
        XCTAssertTrue(food.exists)
        search.tap(); search.typeText("Coffee")
        XCTAssertTrue(result.waitForExistence(timeout: stepTimeout), "Typing should produce results without submit")
        close.tap()
    }
}
#endif

#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW && targetEnvironment(simulator)
import XCTest

final class LiveSavedGalleryCordUITests: SAVEUITestCase {
    @MainActor
    func testDarkGalleryTapIlluminatesAndOpensDetailImmediately() {
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--uitest-reviewed-venue-posts", "--preview-tab-saved", "--uitest-force-light"],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString, "SAVE_UI_TEST_SOURCE_COVER": "1"])
        launch(app)
        let bulb = app.buttons["gallery.bulb"]
        XCTAssertTrue(bulb.waitForExistence(timeout: launchTimeout))
        bulb.tap()
        XCTAssertEqual(bulb.value as? String, "Off")
        let first = app.buttons["live.library.place.C77AF9C1-064A-45D0-833D-E0C809C1F013"]
        XCTAssertEqual(first.value as? String, "Dim")
        XCTAssertTrue(first.label.contains("收藏來源圖片") || first.label.contains("Saved source image"),
                      "The frame exposes source-image provenance to VoiceOver")
        first.tap()
        let close = app.buttons["live.place.close"]
        XCTAssertTrue(close.waitForExistence(timeout: stepTimeout), "A single tap opens details")
        close.tap()
        XCTAssertTrue(first.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(first.value as? String, "Illuminated", "The tapped frame stays illuminated behind its detail")
        attach(app, name: "gallery-tap-light-after-detail")
        bulb.tap(); bulb.tap()
        XCTAssertEqual(first.value as? String, "Dim", "The room switch still resets the gallery")
    }

    @MainActor
    func testGalleryCordTracksPullAndResetsForRepeatedInput() {
        let app = makeApp(launchArguments: ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--uitest-reviewed-venue-posts", "--preview-tab-saved", "--uitest-force-light"],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        let lights = app.buttons["gallery.bulb"]
        let bulb = app.buttons["gallery.bulb"]
        XCTAssertTrue(bulb.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(lights.value as? String, "On")
        let handle = bulb.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
            .withOffset(.init(dx: 0, dy: 90))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(.init(dx: -12, dy: 65)))
        XCTAssertEqual(lights.value as? String, "Off")
        attach(app, name: "gallery-cord-off")
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(.init(dx: 5, dy: 12)))
        XCTAssertEqual(lights.value as? String, "Off", "A short pull must not toggle")
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(.init(dx: 8, dy: 65)))
        XCTAssertEqual(lights.value as? String, "On", "The returned handle remains draggable")
        XCTAssertFalse(app.buttons["live.place.close"].exists, "Pulling must not open the underlying place")
        attach(app, name: "gallery-cord-on")
        bulb.tap()
        XCTAssertEqual(lights.value as? String, "Off", "Direct button remains available")
    }

}
#endif
