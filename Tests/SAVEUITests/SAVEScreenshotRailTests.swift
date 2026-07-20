import XCTest

/// App Store screenshot rail for the Trip Pack-first product shell.
///
/// The review-demo session is local and deterministic. The five screenshots
/// cover Trips home plus the exact Plan / Map / Inbox / Share workspace.
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

        let tripsHome = app.descendants(matching: .any)["trips.home"]
        guard tripsHome.waitForExistence(timeout: 45) else {
            attach(app, name: "debug-after-signin")
            throw XCTSkip("Trips home never appeared after demo sign-in.")
        }
        XCTAssertTrue(app.buttons["trips.capture"].exists)
        attach(app, name: "screenshot-01-trips-home")

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        guard firstTrip.waitForExistence(timeout: 20), firstTrip.isHittable else {
            throw XCTSkip("Review-demo Trip Packs were not seeded.")
        }
        firstTrip.tap()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.buttons["Plan"].waitForExistence(timeout: stepTimeout) else {
            throw XCTSkip("Trip workspace did not open.")
        }
        attach(app, name: "screenshot-02-trip-plan")

        tabBar.buttons["Map"].tap()
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))
        sleep(2)
        attach(app, name: "screenshot-03-trip-map")

        tabBar.buttons["Inbox"].tap()
        XCTAssertTrue(pasteShareLinkButton(in: app).waitForExistence(timeout: stepTimeout))
        sleep(1)
        attach(app, name: "screenshot-04-trip-inbox")

        tabBar.buttons["Share"].tap()
        XCTAssertTrue(app.buttons["trip.share.link"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["trip.share.kml"].exists)
        sleep(1)
        attach(app, name: "screenshot-05-trip-share")
    }

    @MainActor
    func testTripPackFirstShellKeepsCaptureAndMapReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
        ]
        app.launchArguments += ["-save.appLanguage", "en"]
        app.launch()

        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.buttons["trips.capture"].isHittable)

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: stepTimeout))
        firstTrip.tap()

        let tabBar = app.tabBars.firstMatch
        for tab in ["Plan", "Map", "Inbox", "Share"] {
            XCTAssertTrue(tabBar.buttons[tab].waitForExistence(timeout: stepTimeout), "Missing \(tab) tab")
        }
        XCTAssertEqual(tabBar.buttons.count, 4)

        tabBar.buttons["Map"].tap()
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))

        tabBar.buttons["Inbox"].tap()
        XCTAssertTrue(pasteShareLinkButton(in: app).waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testTripStopEditorSurfaceIsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
            "-save.appLanguage", "en",
        ]
        app.launch()

        try signInViaReviewDemo(app: app)

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: 45))
        firstTrip.tap()

        let firstStopEditor = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trip.stop.' AND identifier ENDSWITH '.edit'")
        ).firstMatch
        XCTAssertTrue(firstStopEditor.waitForExistence(timeout: stepTimeout))
        firstStopEditor.tap()

        XCTAssertTrue(app.descendants(matching: .any)["trip.stop.edit"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.steppers["trip.stop.edit.dayPicker"].exists)
        XCTAssertTrue(app.textFields["trip.stop.edit.startTime"].exists)
        XCTAssertTrue(app.textFields["trip.stop.edit.duration"].exists)
        XCTAssertTrue(app.textFields["trip.stop.edit.note"].exists)
        XCTAssertTrue(app.buttons["trip.stop.edit.save"].exists)
        XCTAssertTrue(app.buttons["trip.stop.edit.remove"].exists)

        replaceText(in: app.textFields["trip.stop.edit.startTime"], with: "09:30")
        replaceText(in: app.textFields["trip.stop.edit.duration"], with: "45")
        replaceText(in: app.textFields["trip.stop.edit.note"], with: "UI smoke")
        app.buttons["trip.stop.edit.save"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["trip.stop.edit"].waitForExistence(timeout: 2))

        XCTAssertTrue(firstStopEditor.waitForExistence(timeout: stepTimeout))
        firstStopEditor.tap()
        XCTAssertEqual(app.textFields["trip.stop.edit.startTime"].value as? String, "09:30")
        XCTAssertEqual(app.textFields["trip.stop.edit.duration"].value as? String, "45")
        XCTAssertEqual(app.textFields["trip.stop.edit.note"].value as? String, "UI smoke")

        app.buttons["trip.stop.edit.remove"].tap()
        XCTAssertTrue(app.buttons["trip.stop.edit.remove.confirm"].waitForExistence(timeout: stepTimeout))
        app.alerts.buttons["Cancel"].tap()
        app.navigationBars.buttons["Cancel"].tap()

        let addMapStamp = app.buttons["Add confirmed Map Stamp"]
        XCTAssertTrue(addMapStamp.waitForExistence(timeout: stepTimeout))
        addMapStamp.tap()
        XCTAssertTrue(app.steppers["trip.add.dayPicker"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testFriendsSurfaceIsReachableAndKeepsFollowEntryVisible() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
            "-save.appLanguage", "en",
        ]
        app.launch()

        try signInViaReviewDemo(app: app)

        let capture = app.buttons["trips.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 45))
        capture.tap()

        let friendsTab = app.buttons["drawer.tab.friends"]
        XCTAssertTrue(friendsTab.waitForExistence(timeout: stepTimeout))
        friendsTab.tap()

        XCTAssertTrue(app.descendants(matching: .any)["drawer.friends.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["drawer.friends.following"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["drawer.friends.sharedPlaces"].exists)
        XCTAssertTrue(app.textFields["drawer.friends.search"].exists)
        XCTAssertTrue(app.textFields["drawer.friends.referral"].exists)
        XCTAssertTrue(app.buttons["drawer.friends.follow"].exists)
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

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: 45))
        firstTrip.tap()

        let shareTab = app.tabBars.buttons["Share"]
        XCTAssertTrue(shareTab.waitForExistence(timeout: stepTimeout))
        shareTab.tap()

        let shareSaveLink = app.buttons["trip.share.link"]
        XCTAssertTrue(shareSaveLink.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(shareSaveLink.isEnabled)
        let exportKml = app.buttons["trip.share.kml"]
        XCTAssertTrue(exportKml.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(exportKml.isEnabled)
        exportKml.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.share.kml.sheet"]
                .waitForExistence(timeout: stepTimeout),
            "Reviewer demo KML should create a file and open the share sheet."
        )
    }

    // MARK: - Demo sign-in

    /// Types the App Review demo email + code (native SwiftUI fields — the
    /// demo pair never hits Privy or the network, see ReviewDemoService).
    @MainActor
    private func signInViaReviewDemo(app: XCUIApplication) throws {
        let emailField = app.textFields["signin.emailField"]
        // The opening animation holds the screen for ~2s before SignInView.
        guard emailField.waitForExistence(timeout: 20) else {
            // A previous demo session may already be signed in.
            if app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout) {
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

    @MainActor
    private func pasteShareLinkButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Paste' AND label CONTAINS[c] 'Share Link'")
        ).firstMatch
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with replacement: String) {
        field.tap()
        if let current = field.value as? String,
           current != field.placeholderValue,
           !current.isEmpty {
            field.typeKey("a", modifierFlags: .command)
        }
        field.typeText(replacement)
    }

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
