import XCTest

/// App Store screenshot rail.
///
/// Drives the real app into the App Review demo session (native email + code
/// bypass, seeded local places, no real network required) and captures the
/// core screens as `.keepAlways` attachments:
///
///   1. screenshot-01-memory-inbox           — secondary review surface with recent stamps
///   2. screenshot-02-map-collapsed-drawer   — map-first home with seeded pins
///   3. screenshot-03-drawer-stamps-tab      — drawer expanded on the Stamps tab
///   4. screenshot-04-place-detail           — a seeded place's detail card
///   5. screenshot-05-passport-profile       — the SAV-E Passport / profile sheet
///
/// Extract the PNGs with `specs/capture-app-screenshots.sh`. The test skips
/// (never hard-fails) when a step of the demo flow can't be reached, so a
/// partial rail still yields whatever screenshots were captured before it.
final class SAVEScreenshotRailTests: XCTestCase {

    private let stepTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
        ]
        // Force English so label-based queries (tabs, passport button) and the
        // App Store screenshots themselves are deterministic. NSArgumentDomain
        // is fine here: the app only reads this key once at startup.
        app.launchArguments += ["-save.appLanguage", "en"]

        // The map may ask for location on first render; dismiss so the rail
        // never stalls behind a system alert.
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()

        try signInViaReviewDemo(app: app)

        // --- (a) Map-first home ---------------------------------------------
        dismissLocationAlertIfPresent()
        let passportButton = app.buttons["Open SAV-E Passport"]
        guard passportButton.waitForExistence(timeout: 45) else {
            attach(app, name: "debug-after-signin")
            throw XCTSkip("Map/drawer never appeared after demo sign-in — no screenshots captured.")
        }
        dismissLocationAlertIfPresent()
        sleep(4) // let map tiles + seeded pins finish rendering
        attach(app, name: "screenshot-02-map-collapsed-drawer")

        // --- (b) Secondary Memory Inbox ------------------------------------
        let inboxButton = app.buttons["map.returnToInbox"]
        guard inboxButton.waitForExistence(timeout: stepTimeout), inboxButton.isHittable else {
            throw XCTSkip("Memory Inbox entry was not reachable from the map.")
        }
        inboxButton.tap()

        let inboxRoot = app.descendants(matching: .any)["memory-inbox-root"]
        guard inboxRoot.waitForExistence(timeout: stepTimeout) else {
            attach(app, name: "debug-after-opening-inbox")
            throw XCTSkip("Memory Inbox never appeared from the map.")
        }
        sleep(2)
        attach(app, name: "screenshot-01-memory-inbox")

        // Return to the map before continuing the drawer/detail rail.
        let mapButton = app.buttons["memory-inbox-map"]
        guard mapButton.waitForExistence(timeout: stepTimeout), mapButton.isHittable else {
            throw XCTSkip("Map entry was not reachable from Memory Inbox.")
        }
        mapButton.tap()
        dismissLocationAlertIfPresent()
        guard passportButton.waitForExistence(timeout: 45) else {
            attach(app, name: "debug-after-opening-map")
            throw XCTSkip("Map/drawer never appeared after tapping Map.")
        }

        // --- (c) Drawer expanded on the Stamps tab --------------------------
        expandDrawer(app: app)
        let stampsTab = app.buttons["Stamps"]
        let seededRow = app.staticTexts["Ichiran Shibuya"]
        guard stampsTab.waitForExistence(timeout: stepTimeout) || seededRow.waitForExistence(timeout: stepTimeout) else {
            attach(app, name: "debug-after-expand")
            throw XCTSkip("Drawer did not expand to the Stamps tab — captured map only.")
        }
        if stampsTab.exists, stampsTab.isHittable {
            stampsTab.tap()
        }
        _ = seededRow.waitForExistence(timeout: stepTimeout)
        sleep(1)
        attach(app, name: "screenshot-03-drawer-stamps-tab")

        // --- (d) Place detail for a seeded place ----------------------------
        guard openSeededPlaceDetail(app: app) else {
            attach(app, name: "debug-stamps-rows")
            throw XCTSkip("Could not open a seeded place detail — captured Inbox, map, and Stamps tab only.")
        }
        sleep(5) // give the business-photo carousel a moment to load
        attach(app, name: "screenshot-04-place-detail")

        // --- (e) Passport / profile -----------------------------------------
        let closeDetail = app.buttons["Close place detail"]
        if closeDetail.waitForExistence(timeout: stepTimeout) {
            closeDetail.tap()
        }
        guard passportButton.waitForExistence(timeout: stepTimeout) else {
            throw XCTSkip("Passport button not reachable after closing place detail — captured 3 of 4 screens.")
        }
        passportButton.tap()
        let profileMarker = app.buttons["profile.edit"]
        _ = profileMarker.waitForExistence(timeout: stepTimeout)
        sleep(1)
        attach(app, name: "screenshot-05-passport-profile")
    }

    @MainActor
    func testMapFirstShellOpensInboxAndReturns() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
        ]
        app.launchArguments += ["-save.appLanguage", "en"]
        app.launch()

        try signInViaReviewDemo(app: app)
        dismissLocationAlertIfPresent()

        let locationButton = app.buttons["Center map on current location"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 45))

        let returnButton = app.buttons["map.returnToInbox"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: stepTimeout))
        returnButton.tap()

        let inboxRoot = app.descendants(matching: .any)["memory-inbox-root"]
        XCTAssertTrue(inboxRoot.waitForExistence(timeout: stepTimeout))

        let recentPlace = app.staticTexts["Daan Forest Park"]
        XCTAssertTrue(recentPlace.waitForExistence(timeout: stepTimeout))
        recentPlace.tap()

        let detailReturnButton = app.buttons["map.returnToInbox"]
        XCTAssertTrue(detailReturnButton.waitForExistence(timeout: 45))
        detailReturnButton.tap()
        XCTAssertTrue(inboxRoot.waitForExistence(timeout: stepTimeout))

        let mapButton = app.buttons["memory-inbox-map"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: stepTimeout))
        mapButton.tap()
        dismissLocationAlertIfPresent()
        XCTAssertTrue(locationButton.waitForExistence(timeout: 45))
    }

    @MainActor
    func testTripKmlExportMenuSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
        ]
        app.launchArguments += ["-save.appLanguage", "en"]
        app.launch()

        try signInViaReviewDemo(app: app)
        dismissLocationAlertIfPresent()

        let namedField = app.textFields["Ask saved places or paste a spot..."]
        let queryField = namedField.waitForExistence(timeout: stepTimeout) ? namedField : app.textFields.firstMatch
        XCTAssertTrue(queryField.waitForExistence(timeout: stepTimeout))
        queryField.tap()
        queryField.typeText("Plan a one day Taipei trip")
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.waitForExistence(timeout: 3) {
            searchKey.tap()
        } else {
            queryField.typeText("\n")
        }

        let shareMenu = app.buttons["Share or export trip"]
        XCTAssertTrue(shareMenu.waitForExistence(timeout: 45))
        shareMenu.tap()

        let shareSaveLink = app.buttons["Share SAV-E Link"]
        XCTAssertTrue(shareSaveLink.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(shareSaveLink.isEnabled)
        let exportKml = app.buttons["Export KML"]
        XCTAssertTrue(exportKml.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(exportKml.isEnabled)
        exportKml.tap()

        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Sign in to export your confirmed Map Stamps."].exists)
    }

    // MARK: - Demo sign-in

    /// Types the App Review demo email + code (native SwiftUI fields — the
    /// demo pair never hits Privy or the network, see ReviewDemoService).
    @MainActor
    private func signInViaReviewDemo(app: XCUIApplication) throws {
        let emailField = app.textFields["signin.emailField"]
        // The opening animation holds the screen for ~2s before SignInView.
        guard emailField.waitForExistence(timeout: 20) else {
            // A previous demo session may already be signed in (vault + seed
            // flag persist); proceed if either root surface is already up.
            if app.buttons["Open SAV-E Passport"].waitForExistence(timeout: stepTimeout) ||
                app.descendants(matching: .any)["memory-inbox-root"].exists {
                return
            }
            throw XCTSkip("Email sign-in field never appeared — cannot reach the demo session.")
        }

        emailField.tap()
        emailField.typeText("appreview@wanderly.app")
        dismissKeyboard(app: app) // sign-in layout ignores the keyboard safe area

        let sendCode = app.buttons["signin.sendCode"]
        guard sendCode.waitForExistence(timeout: stepTimeout), sendCode.isHittable else {
            throw XCTSkip("Send-code button not tappable — cannot start the demo flow.")
        }
        sendCode.tap()

        let codeField = app.textFields["signin.codeField"]
        guard codeField.waitForExistence(timeout: stepTimeout) else {
            throw XCTSkip("Verification-code field never appeared after sending the demo code.")
        }
        codeField.tap()
        codeField.typeText("424242")
        dismissKeyboard(app: app) // number pad has no return key

        let verify = app.buttons["signin.verify"]
        guard verify.waitForExistence(timeout: stepTimeout), verify.isHittable else {
            throw XCTSkip("Verify button not tappable — cannot enter the demo session.")
        }
        verify.tap()
    }

    /// Taps the keyboard-toolbar Done button (signin.keyboardDone) so the
    /// buttons hidden underneath the keyboard become hittable again. No-op if
    /// the software keyboard isn't showing (e.g. hardware keyboard connected).
    @MainActor
    private func dismissKeyboard(app: XCUIApplication) {
        let done = app.buttons["signin.keyboardDone"]
        if done.waitForExistence(timeout: 3), done.isHittable {
            done.tap()
        }
    }

    // MARK: - Helpers

    /// Dismisses the system location permission alert if it is on screen.
    /// Queried on SpringBoard because system alerts live outside the app.
    @MainActor
    private func dismissLocationAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    /// Drags the collapsed drawer sheet up towards a tall detent so the
    /// Stamps/Review tab bar and saved-place rows become visible.
    @MainActor
    private func expandDrawer(app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.15, thenDragTo: end)
        sleep(1)
    }

    /// Taps a seeded saved-place row (any of the ReviewDemoSeed names) to open
    /// its map-detail drawer card, scrolling the drawer when the rows sit
    /// below the fold.
    @MainActor
    private func openSeededPlaceDetail(app: XCUIApplication) -> Bool {
        let seededNames = [
            "Ichiran Shibuya",
            "Fujin Tree 353 Cafe",
            "Guerrilla Tacos",
            "Bar Benfiddich",
            "Daan Forest Park",
            "The Siam Hotel",
        ]
        for attempt in 0..<4 {
            for name in seededNames {
                let row = app.staticTexts[name]
                if row.exists, row.isHittable {
                    row.tap()
                    return app.buttons["Close place detail"].waitForExistence(timeout: stepTimeout)
                }
            }
            if attempt < 3 {
                // Scroll the expanded drawer's list to reveal more rows.
                app.swipeUp()
                sleep(1)
            }
        }
        return false
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
