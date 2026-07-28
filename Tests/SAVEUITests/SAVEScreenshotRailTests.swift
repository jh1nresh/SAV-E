import XCTest

/// App Store screenshot rail for the SAV-E root shell and Trip workspace.
///
/// The review-demo session is local and deterministic. The five screenshots
/// cover Home plus the exact Plan / Map / Inbox / Share Trip workspace.
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

        let home = app.descendants(matching: .any)["home.root"]
        guard home.waitForExistence(timeout: 45) else {
            attach(app, name: "debug-after-signin")
            throw XCTSkip("Home never appeared after demo sign-in.")
        }
        XCTAssertTrue(app.buttons["home.capture"].exists)
        attach(app, name: "screenshot-01-home")

        openRootTab("Trips", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

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
        XCTAssertTrue(addLinkButton(in: app).waitForExistence(timeout: stepTimeout))
        sleep(1)
        attach(app, name: "screenshot-04-trip-inbox")

        tabBar.buttons["Share"].tap()
        XCTAssertTrue(app.buttons["trip.share.link"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["trip.share.kml"].exists)
        sleep(1)
        attach(app, name: "screenshot-05-trip-share")
    }

    @MainActor
    func testAtlasHomeAndSavesRenderPersistedPlaceData() throws {
        let storageID = UUID().uuidString.lowercased()
        let mapURL = "https://www.google.com/maps/place/Quarter+Sheets+Pizza+Club/@34.0779,-118.2543,17z/data=!3m1"
        let app = XCUIApplication()
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = storageID
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage",
            "-save.appLanguage", "en",
        ]

        app.launch()
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 45))

        let capture = app.buttons["home.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()

        let commandField = app.textFields["drawer.commandField"]
        XCTAssertTrue(commandField.waitForExistence(timeout: stepTimeout))
        commandField.tap()
        commandField.typeText(mapURL)
        let submitCommand = app.buttons["drawer.submitCommand"]
        XCTAssertTrue(submitCommand.waitForExistence(timeout: stepTimeout))
        submitCommand.tap()

        let analyzedCandidate = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'drawer.review.candidate.place.'")
        ).firstMatch
        XCTAssertTrue(
            analyzedCandidate.waitForExistence(timeout: 20),
            "Expected the analyzed link to persist as a Review Candidate."
        )

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        app.launch()
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["1 clue needs your help"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-production-home")

        openRootTab("Saves", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let savedCandidate = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.reviewCandidate.' AND label CONTAINS[c] %@",
                "Quarter Sheets Pizza Club"
            )
        ).firstMatch
        XCTAssertTrue(savedCandidate.waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-production-saves")

        savedCandidate.tap()
        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "A Saves Review Candidate should open in the one global drawer."
        )
        XCTAssertTrue(
            app.buttons["drawer.review.primaryAction"].waitForExistence(timeout: stepTimeout),
            "A Saves Review Candidate should render its canonical review detail."
        )
    }

    @MainActor
    func testGlobalTabsAreReachableAndTripUsesScopedTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
        ]
        app.launchArguments += ["-save.appLanguage", "en"]
        app.launch()

        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.buttons["home.capture"].exists)
        XCTAssertTrue(app.buttons["home.review"].exists)
        XCTAssertTrue(app.buttons["home.saves"].exists)
        let continueTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.trip.'")
        ).firstMatch
        XCTAssertTrue(continueTrip.waitForExistence(timeout: 20))

        let recentSaves = app.descendants(matching: .any)["home.recentSaves"]
        if !recentSaves.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(recentSaves.waitForExistence(timeout: stepTimeout))

        let rootTabBar = app.tabBars.firstMatch
        for tab in ["Home", "Saves", "Trips", "Map"] {
            XCTAssertTrue(rootTabBar.buttons[tab].waitForExistence(timeout: stepTimeout), "Missing \(tab) root tab")
        }
        XCTAssertEqual(rootTabBar.buttons.count, 4)
        XCTAssertTrue(rootTabBar.buttons["Home"].isSelected)

        openRootTab("Saves", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))

        openRootTab("Trips", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

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
        for rootTab in ["Home", "Saves", "Trips"] {
            XCTAssertFalse(tabBar.buttons[rootTab].exists, "Root tab \(rootTab) should be hidden inside a Trip")
        }

        tabBar.buttons["Map"].tap()
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))

        tabBar.buttons["Inbox"].tap()
        let addLink = addLinkButton(in: app)
        XCTAssertTrue(addLink.waitForExistence(timeout: stepTimeout))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: stepTimeout))
        backButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        let restoredRootTabBar = app.tabBars.firstMatch
        for rootTab in ["Home", "Saves", "Trips", "Map"] {
            XCTAssertTrue(
                restoredRootTabBar.buttons[rootTab].waitForExistence(timeout: stepTimeout),
                "Missing \(rootTab) after leaving a Trip"
            )
        }
        XCTAssertEqual(restoredRootTabBar.buttons.count, 4)
    }

    @MainActor
    func testGlobalShellDefaultsToHomeAndOpensSingleDrawer() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
            "-save.appLanguage", "en",
        ]
        app.launch()

        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.descendants(matching: .any)["drawer.launcher"].exists)

        let captureButtons = app.buttons.matching(identifier: "home.capture")
        XCTAssertEqual(captureButtons.count, 1)
        XCTAssertTrue(captureButtons.firstMatch.isHittable)
        captureButtons.firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "Only one command drawer should be presented."
        )
        XCTAssertTrue(app.textFields["drawer.commandField"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["drawer.tab.saved"].exists)
        XCTAssertTrue(app.buttons["drawer.tab.review"].exists)
        XCTAssertTrue(app.buttons["drawer.tab.friends"].exists)
    }

    @MainActor
    func testSavedPlaceEntryUsesSingleCanonicalDetail() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-repair-review-demo-seed",
            "-save.appLanguage", "en",
        ]
        app.launch()

        try signInViaReviewDemo(app: app)

        openRootTab("Saves", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: 45))

        let firstMapStamp = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'saves.place.'")
        ).firstMatch
        XCTAssertTrue(firstMapStamp.waitForExistence(timeout: stepTimeout))
        firstMapStamp.tap()

        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "A Map Stamp should stay inside the one global drawer."
        )
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "place.detail.root").count,
            1,
            "Every saved-place entry should use one canonical detail renderer."
        )
        XCTAssertTrue(app.buttons["drawer.saved.addToTrip"].waitForExistence(timeout: stepTimeout))
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

        openRootTab("Trips", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

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

        let addMapStamp = app.buttons["Add saved place"]
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

        let capture = app.buttons["home.capture"]
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

        openRootTab("Trips", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

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

    @MainActor
    func testAnalyzedMapLinkPersistsAsTripStopAfterRelaunch() throws {
        let storageID = UUID().uuidString.lowercased()
        let tripName = "Link Trip \(storageID.prefix(8))"
        let placeName = "Quarter Sheets Pizza Club"
        let mapURL = "https://www.google.com/maps/place/Quarter+Sheets+Pizza+Club/@34.0779,-118.2543,17z/data=!3m1"
        let app = XCUIApplication()
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = storageID
        app.launchArguments += [
            "--uitest-complete-onboarding",
            "--skip-map-tour",
            "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage",
            "-save.appLanguage", "en",
        ]

        app.launch()
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 45))

        let capture = app.buttons["home.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()

        let commandField = app.textFields["drawer.commandField"]
        XCTAssertTrue(commandField.waitForExistence(timeout: stepTimeout))
        commandField.tap()
        commandField.typeText(mapURL)
        let submitCommand = app.buttons["drawer.submitCommand"]
        XCTAssertTrue(submitCommand.waitForExistence(timeout: stepTimeout))
        submitCommand.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.review.root"]
                .waitForExistence(timeout: stepTimeout)
        )
        let candidate = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'drawer.review.candidate.place.'")
        ).firstMatch
        XCTAssertTrue(
            candidate.waitForExistence(timeout: 20),
            "Expected a map-ready Review Candidate.\n\(app.debugDescription)"
        )
        candidate.tap()

        let placeDetailScroll = app.scrollViews["place.detail.scroll"]
        XCTAssertTrue(placeDetailScroll.waitForExistence(timeout: stepTimeout))
        let confirmCandidate = app.buttons["drawer.review.primaryAction"]
        XCTAssertTrue(
            scrollUntilHittable(confirmCandidate, in: placeDetailScroll),
            "Confirm candidate never became tappable.\n\(app.debugDescription)"
        )
        confirmCandidate.tap()

        let createTripAndAdd = app.buttons
            .matching(identifier: "saved.addToTrip.create")
            .firstMatch
        XCTAssertTrue(createTripAndAdd.waitForExistence(timeout: stepTimeout))
        createTripAndAdd.tap()

        XCTAssertTrue(app.descendants(matching: .any)["trip.create.sheet"].waitForExistence(timeout: stepTimeout))
        let tripNameField = app.textFields["trip.create.name"]
        XCTAssertTrue(tripNameField.waitForExistence(timeout: stepTimeout))
        tripNameField.tap()
        tripNameField.typeText(tripName)
        let cityField = app.textFields["trip.create.city"]
        cityField.tap()
        cityField.typeText("Los Angeles")
        app.buttons["trip.create.submit"].tap()

        XCTAssertFalse(app.descendants(matching: .any)["trip.create.sheet"].waitForExistence(timeout: 10))
        try assertSavedPlaceAndTripStopPersist(
            app: app,
            placeName: placeName,
            tripName: tripName
        )

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        app.launch()
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 45))
        try assertSavedPlaceAndTripStopPersist(
            app: app,
            placeName: placeName,
            tripName: tripName
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
            if app.descendants(matching: .any)["home.root"].waitForExistence(timeout: stepTimeout) {
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

    @MainActor
    private func signInViaReviewDemoRequired(app: XCUIApplication) throws {
        let emailField = app.textFields["signin.emailField"]
        if !emailField.waitForExistence(timeout: 20) {
            XCTAssertTrue(
                app.descendants(matching: .any)["home.root"].waitForExistence(timeout: stepTimeout),
                "Email sign-in and Home were both unavailable."
            )
            return
        }

        emailField.tap()
        emailField.typeText("appreview@wanderly.app")
        dismissKeyboard(app: app)

        let sendCode = app.buttons["signin.sendCode"]
        XCTAssertTrue(sendCode.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(sendCode.isHittable)
        sendCode.tap()

        let codeField = app.textFields["signin.codeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: stepTimeout))
        codeField.tap()
        codeField.typeText("424242")
        dismissKeyboard(app: app)

        let verify = app.buttons["signin.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(verify.isHittable)
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
    private func addLinkButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["trip.inbox.addLink"]
    }

    @MainActor
    private func openRootTab(_ title: String, app: XCUIApplication) {
        let tab = app.tabBars.firstMatch.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: stepTimeout), "Missing \(title) root tab")
        tab.tap()
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

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        for _ in 0..<5 {
            if element.exists, element.isHittable { return true }
            scrollView.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func assertSavedPlaceAndTripStopPersist(
        app: XCUIApplication,
        placeName: String,
        tripName: String
    ) throws {
        openRootTab("Saves", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let savedPlace = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.place.' AND label CONTAINS[c] %@",
                placeName
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilExists(savedPlace, app: app), "Saved Map Stamp is missing.")

        openRootTab("Trips", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))
        let tripCard = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'trips.card.' AND label CONTAINS[c] %@",
                tripName
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilExists(tripCard, app: app), "Created Trip is missing.")
        tripCard.tap()

        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: stepTimeout))
        let tripStop = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'trip.stop.' AND identifier ENDSWITH '.edit' AND label == %@",
                "Edit \(placeName)"
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilExists(tripStop, app: app), "Confirmed Trip stop is missing.")

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: stepTimeout))
        backButton.tap()
    }

    @MainActor
    private func scrollUntilExists(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 1) { return true }
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 1)
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
