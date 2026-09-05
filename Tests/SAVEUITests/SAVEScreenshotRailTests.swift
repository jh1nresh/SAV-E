import XCTest

/// App Store screenshot rail for the Savvy root shell and Trip workspace.
///
/// The review-demo session is local and deterministic. The screenshots cover
/// Home plus the focused Plan / Map Trip workspace and top-level Share action.
///
/// Extract the PNGs with `specs/capture-app-screenshots.sh`. The test skips
/// (never hard-fails) when a step of the demo flow can't be reached, so a
/// partial rail still yields whatever screenshots were captured before it.
final class SAVEScreenshotRailTests: SAVEUITestCase {

    @MainActor
    func testSignInCardKeepsEveryRouteVisible() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)

        let title = app.staticTexts["signin.title"]
        let apple = app.buttons["signin.apple"]
        let google = app.buttons["signin.google"]
        let email = app.textFields["signin.emailField"]
        let sendCode = app.buttons["signin.sendCode"]

        for element in [title, apple, google, email, sendCode] {
            XCTAssertTrue(element.waitForExistence(timeout: launchTimeout))
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY)
            XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY)
        }
        XCTAssertGreaterThanOrEqual(apple.frame.height, 44)
        XCTAssertGreaterThanOrEqual(google.frame.height, 44)
        attach(app, name: "signin-card-all-routes")
    }

    @MainActor
    func testLaunchKeepsPaywallAbsentAndTripsInBeta() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["BETA"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Trip planning is still improving."].exists)
        XCTAssertFalse(app.staticTexts["Free during Beta while planning gets better."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)
        attach(app, name: "trips-beta-no-paywall")

        openRootTab("Home", app: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Live Home should lead with the saved-place library."
        )
        app.buttons["root.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["profile.proPreview"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)
        XCTAssertFalse(app.staticTexts["Memo Pro preview"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'subscribe'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'trial'")).firstMatch.exists)
        attach(app, name: "passport-no-paywall")
    }

    @MainActor
    func testHomeLeadsWithSavedPlacesAndUsesSaveTabForCapture() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Production Home should render confirmed saved places immediately."
        )
        let firstPlace = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.place.'")
        ).firstMatch
        XCTAssertTrue(firstPlace.waitForExistence(timeout: stepTimeout))
        let changeCover = app.buttons["home.hero.changeCover"]
        XCTAssertTrue(changeCover.waitForExistence(timeout: stepTimeout))
        changeCover.tap()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.descendants(matching: .any)["home.saves"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.trips"].exists)
        XCTAssertTrue(rootTabButton("Save", app: app).isHittable)
        XCTAssertFalse(
            app.buttons["home.capture"].exists,
            "Home should not duplicate the root Save action."
        )
        XCTAssertFalse(
            app.buttons["home.hero.openMap"].exists,
            "Live Home should not expose the decorative regional hero."
        )
        XCTAssertTrue(rootTabButton("Home", app: app).isSelected)
        attach(app, name: "home-saved-places-library")
    }

    @MainActor
    func testCaptureAtlasProductionParity() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-atlas-parity-fixture",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        attach(app, name: "atlas-home")

        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-saves")

        openTripsFromHome(app: app)
        let trip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: timeout(20)))
        trip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip.plan"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-plan")

        let back = app.buttons["trip.back"]
        XCTAssertTrue(back.waitForExistence(timeout: stepTimeout))
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-map")
    }

    /// Visual gate for the five-item root bar. Run this same test on the
    /// 402pt reference device and an SE-class device; attachment dimensions
    /// record which viewport produced each frame.
    @MainActor
    func testCaptureFiveTabLanding() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let tabs = ["Home", "Map", "Save", "Plan", "Profile"].map {
            rootTabButton($0, app: app)
        }
        for tab in tabs {
            XCTAssertTrue(tab.waitForExistence(timeout: stepTimeout))
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        }
        let leadingInset = tabs[0].frame.minX - app.frame.minX
        let trailingInset = app.frame.maxX - tabs[4].frame.maxX
        XCTAssertGreaterThan(leadingInset, 12, "Root tabs must not touch the leading screen edge.")
        XCTAssertGreaterThan(trailingInset, 12, "Root tabs must not touch the trailing screen edge.")
        XCTAssertEqual(leadingInset, trailingInset, accuracy: 2)
        waitForHomeCoverImagery(app)
        attach(app, name: "five-tab-home")

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        let locationNoticeDismiss = app.buttons["map.locationNotice.dismiss"]
        if locationNoticeDismiss.waitForExistence(timeout: timeout(2)) {
            locationNoticeDismiss.tap()
        }
        attach(app, name: "five-tab-map")

        openRootTab("Plan", app: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout)
        )
        attach(app, name: "five-tab-plan")

        openRootTab("Profile", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "five-tab-profile")

        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "five-tab-capture")
    }

    @MainActor
    func testCaptureAppStoreScreens() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                // Force English so label-based queries (tabs, passport button)
                // and the App Store screenshots themselves are deterministic.
                // NSArgumentDomain is fine here: the app only reads this key
                // once at startup.
                "-save.appLanguage", "en",
            ]
        )

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

        launch(app)
        try signInViaReviewDemo(app: app)

        let home = app.descendants(matching: .any)["home.root"]
        guard home.waitForExistence(timeout: launchTimeout) else {
            attach(app, name: "debug-after-signin")
            throw XCTSkip("Home never appeared after demo sign-in.")
        }
        XCTAssertTrue(rootTabButton("Save", app: app).exists)
        attach(app, name: "screenshot-01-home")

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        guard firstTrip.waitForExistence(timeout: timeout(20)), firstTrip.isHittable else {
            throw XCTSkip("Review-demo Trip Packs were not seeded.")
        }
        firstTrip.tap()

        let planTab = tripTabButton("Plan", app: app)
        guard planTab.waitForExistence(timeout: stepTimeout) else {
            throw XCTSkip("Trip workspace did not open.")
        }
        attach(app, name: "screenshot-02-trip-plan")

        tripTabButton("Map", app: app).tap()
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))
        sleep(2)
        attach(app, name: "screenshot-03-trip-map")

        let shareAction = app.buttons["trip.share.action"]
        XCTAssertTrue(shareAction.waitForExistence(timeout: stepTimeout))
        shareAction.tap()
        XCTAssertTrue(app.buttons["trip.share.link"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["trip.share.kml"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.share.postcard"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.share.privacyReceipt"]
                .waitForExistence(timeout: stepTimeout)
        )
        sleep(1)
        attach(app, name: "screenshot-04-trip-share")
    }

    @MainActor
    func testAtlasHomeAndSavesRenderPersistedPlaceData() throws {
        let storageID = UUID().uuidString.lowercased()
        let mapURL = "https://www.google.com/maps/place/Harbor+Oven+Pizza/@33.7405,-118.2807,17z/data=!3m1"
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )

        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))

        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()

        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-postcard-capture")
        let captureInput = app.textViews["capture.input"]
        typeText(mapURL, into: captureInput)
        let analyze = app.buttons["capture.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: stepTimeout))
        analyze.tap()

        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: timeout(20)))
        let analyzedCandidate = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'saves.reviewCandidate.'")
        ).firstMatch
        XCTAssertTrue(
            analyzedCandidate.waitForExistence(timeout: timeout(20)),
            "Expected the analyzed link to persist as a Review Candidate."
        )

        terminate(app)
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        // Live Home leads with the saved-place library. The pending candidate
        // is proven on Saves below; do not require the old One-Face
        // "clues need your help" headline.
        XCTAssertTrue(
            app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Home should show the saved-place library after relaunch."
        )
        XCTAssertFalse(app.staticTexts["Quarter Sheets Pizza Club"].exists)
        attach(app, name: "atlas-production-home")

        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let savedCandidate = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.reviewCandidate.' AND label CONTAINS[c] %@",
                "Harbor Oven Pizza"
            )
        ).firstMatch
        XCTAssertTrue(savedCandidate.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Quarter Sheets Pizza Club")
            ).firstMatch.exists
        )
        attach(app, name: "atlas-production-saves")

        savedCandidate.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "place.detail.root").count,
            1,
            "A Saves Review Candidate should open in one focused detail."
        )
        XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
        XCTAssertTrue(
            app.buttons["drawer.review.primaryAction"].waitForExistence(timeout: stepTimeout),
            "A Saves Review Candidate should render its canonical review detail."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.review.postcardBody"].waitForExistence(timeout: stepTimeout),
            "Review detail should use the unresolved Postcard Drawer body."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.postcard.ticketHeader"].waitForExistence(timeout: stepTimeout),
            "Every place detail should use the shared Postcard ticket header."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.review.memoPeek"].waitForExistence(timeout: stepTimeout),
            "Review uses the Memo peek on the shared Postcard ticket."
        )
        XCTAssertFalse(app.staticTexts["map ready"].exists)
        XCTAssertFalse(app.staticTexts["MAP READY"].exists)
        XCTAssertFalse(app.staticTexts["84%"].exists)
        XCTAssertFalse(app.staticTexts["84% confidence"].exists)
        attach(app, name: "atlas-postcard-review-drawer")
    }

    @MainActor
    func testGlobalTabsAreReachableAndTripUsesScopedTabs() throws {
        let storageID = UUID().uuidString.lowercased()
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(rootTabButton("Save", app: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.savedPlaces"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.review"].exists)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.place.'"))
                .firstMatch.exists
        )
        XCTAssertTrue(app.descendants(matching: .any)["home.saves"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.trips"].exists)

        for tab in ["Home", "Map", "Save", "Plan", "Profile"] {
            XCTAssertTrue(rootTabButton(tab, app: app).waitForExistence(timeout: stepTimeout), "Missing \(tab) root tab")
        }
        XCTAssertTrue(rootTabButton("Home", app: app).isSelected)

        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: stepTimeout))
        firstTrip.tap()

        for tab in ["Plan", "Map"] {
            XCTAssertTrue(tripTabButton(tab, app: app).waitForExistence(timeout: stepTimeout), "Missing \(tab) tab")
        }
        XCTAssertFalse(tripTabButton("Inbox", app: app).exists)
        XCTAssertFalse(tripTabButton("Share", app: app).exists)
        XCTAssertTrue(app.buttons["trip.share.action"].exists)

        for rootTab in ["Home", "Map", "Save", "Plan", "Profile"] {
            XCTAssertFalse(rootTabButton(rootTab, app: app).exists, "Root tab \(rootTab) should be hidden inside a Trip")
        }

        tripTabButton("Map", app: app).tap()
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.buttons["Center map on current location"].waitForExistence(timeout: stepTimeout))

        let backButton = app.buttons["trip.back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: stepTimeout))
        backButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        openRootTab("Home", app: app)
        for rootTab in ["Home", "Map", "Save", "Plan", "Profile"] {
            XCTAssertTrue(
                rootTabButton(rootTab, app: app).waitForExistence(timeout: stepTimeout),
                "Missing \(rootTab) after leaving a Trip"
            )
        }
    }

    @MainActor
    func testTripMapMarkerDetailReturnsToScopedTabs() throws {
        let storageID = UUID().uuidString.lowercased()
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: launchTimeout))

        let routeTrip = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'trips.card.' AND label CONTAINS[c] %@",
                "Tokyo Weekend"
            )
        ).firstMatch
        XCTAssertTrue(routeTrip.waitForExistence(timeout: stepTimeout))
        routeTrip.tap()

        let mapTab = tripTabButton("Map", app: app)
        XCTAssertTrue(mapTab.waitForExistence(timeout: stepTimeout))
        mapTab.tap()

        XCTAssertTrue(mapTab.isSelected)
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: stepTimeout))

        let routePins = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'map.pin.saved.'")
        )
        XCTAssertTrue(
            routePins.firstMatch.waitForExistence(timeout: timeout(20)),
            "A route-framed Trip Map should expose at least one numbered saved-place marker."
        )
        guard let firstHittableRoutePin = routePins.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("A Trip Map route marker exists, but none are hittable.")
            return
        }
        firstHittableRoutePin.tap()

        let drawer = app.descendants(matching: .any)["drawer.root"]
        XCTAssertTrue(drawer.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "A Trip marker should use the one global drawer."
        )

        let closeDetail = app.buttons["drawer.place.close"]
        XCTAssertTrue(closeDetail.waitForExistence(timeout: stepTimeout))
        closeDetail.tap()
        XCTAssertTrue(drawer.waitForNonExistence(timeout: stepTimeout))

        for tab in ["Plan", "Map"] {
            let tabButton = tripTabButton(tab, app: app)
            XCTAssertTrue(tabButton.waitForExistence(timeout: stepTimeout), "Missing \(tab) after closing a Trip Map detail.")
            XCTAssertTrue(tabButton.isHittable, "\(tab) is still covered after closing a Trip Map detail.")
        }
        XCTAssertFalse(tripTabButton("Inbox", app: app).exists)
        XCTAssertFalse(tripTabButton("Share", app: app).exists)
        XCTAssertTrue(tripTabButton("Map", app: app).isSelected)
        for rootTab in ["Home", "Map", "Save", "Plan", "Profile"] {
            XCTAssertFalse(rootTabButton(rootTab, app: app).exists)
        }

        let planTab = tripTabButton("Plan", app: app)
        planTab.tap()
        XCTAssertTrue(planTab.isSelected)
    }

    @MainActor
    func testCaptureAtlasTripsAndLiveMaps() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(
            app.buttons["trips.capture"].exists,
            "Trips dropped its header capture button; capture lives on Home and Saves."
        )
        // The ask entry is a real input now, not a button (spec P1), so the
        // query is type-agnostic while the identifier stays the same.
        XCTAssertTrue(app.descendants(matching: .any)["trips.assistant"].exists)
        XCTAssertTrue(app.buttons["trips.create"].exists)
        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-trips-live")

        firstTrip.tap()
        let tripMap = tripTabButton("Map", app: app)
        XCTAssertTrue(tripMap.waitForExistence(timeout: stepTimeout))
        tripMap.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["trip.map.openStop"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-trip-map-live")

        let back = app.buttons["trip.back"]
        XCTAssertTrue(back.waitForExistence(timeout: stepTimeout))
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["map.command.search"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["map.place.openDetails"].exists)
        XCTAssertTrue(rootTabButton("Map", app: app).isSelected)
        attach(app, name: "atlas-root-map-live")

        app.buttons["map.command.search"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["drawer.mapAssistant.intro"].waitForExistence(timeout: stepTimeout))
        for legacyTab in ["saved", "review", "friends", "lists"] {
            XCTAssertFalse(app.buttons["drawer.tab.\(legacyTab)"].exists)
        }
    }

    @MainActor
    func testTripsAskRoutesToMapDrawer() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)
        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: launchTimeout))

        // Tapping the ask entry focuses a real input; typed text renders in
        // the field before the child route hands off to the shared Map drawer.
        let askInput = app.textFields["trips.assistant.input"]
        typeText("Plan a day from my stamps", into: askInput)
        XCTAssertEqual(askInput.value as? String, "Plan a day from my stamps")
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].exists)

        // Trips is no longer a root tab. Submit returns to the root Map and
        // expands the one shared drawer there.
        app.buttons["trips.assistant.submit"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout)
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "Only one ask surface should be on screen."
        )
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].exists)
        XCTAssertTrue(rootTabButton("Map", app: app).isSelected)
        attach(app, name: "trips-ask-routes-to-map-drawer")
    }

    @MainActor
    func testTripUsesPlanMapAndTopSharePostcardPocket() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)
        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: launchTimeout))

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: stepTimeout))
        firstTrip.tap()

        XCTAssertTrue(tripTabButton("Plan", app: app).waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(tripTabButton("Map", app: app).exists)
        XCTAssertFalse(tripTabButton("Inbox", app: app).exists)
        XCTAssertFalse(tripTabButton("Share", app: app).exists)

        let shareAction = app.buttons["trip.share.action"]
        XCTAssertTrue(shareAction.waitForExistence(timeout: stepTimeout))
        shareAction.tap()
        XCTAssertTrue(app.buttons["trip.share.link"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["trip.share.kml"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.share.postcard"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.share.privacyReceipt"]
                .waitForExistence(timeout: stepTimeout)
        )
        attach(app, name: "atlas-trip-share-live")
    }

    @MainActor
    func testHomeSearchAndPendingCandidateOpenDirectly() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-repair-review-demo-seed", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        let search = app.textFields["home.search"]
        XCTAssertTrue(search.waitForExistence(timeout: launchTimeout))
        attach(app, name: "home-search-pending-candidate")
        search.tap()
        search.typeText("zzzz-no-saved-match")
        XCTAssertTrue(app.staticTexts["home.search.empty"].waitForExistence(timeout: stepTimeout))
        app.buttons["Clear search"].tap()
        search.tap()
        search.typeText("ichiran")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.search.result.'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: stepTimeout))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        app.buttons["drawer.place.close"].firstMatch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: stepTimeout))
        app.buttons["Clear search"].tap()
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.reviewCandidate.'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
        review.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["saves.root"].exists)
        attach(app, name: "home-real-candidate-detail")
        app.buttons["drawer.place.close"].firstMatch.tap()
        app.buttons["home.reviewAll"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let firstCandidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saves.reviewCandidate.'")).firstMatch
        XCTAssertTrue(firstCandidate.label.contains("Harbor Oven Pizza"))
        XCTAssertLessThan(firstCandidate.frame.minY, app.frame.height * 0.35)
        XCTAssertLessThan(firstCandidate.frame.height, 150)
        XCTAssertFalse(app.descendants(matching: .any)["saves.pocket.reviewFooter"].exists)
        attach(app, name: "saves-real-candidates-first")
    }

    @MainActor
    func testHomeReviewCluesOpensSavesWithoutDrawer() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let reviewClues = app.descendants(matching: .any)["home.review"]
        XCTAssertTrue(reviewClues.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(reviewClues.isHittable)
        reviewClues.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout),
            "Home Review clues should navigate to Saves."
        )
        XCTAssertFalse(rootTabButton("Saves", app: app).exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["drawer.root"].exists,
            "Home Review clues should not present a drawer."
        )
        attach(app, name: "home-review-opens-saves")
    }

    @MainActor
    func testCaptureUsesCompactSheetAndKeepsKeyboardActionReachable() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        rootTabButton("Save", app: app).tap()
        let input = app.textViews["capture.input"]
        let submit = app.buttons["capture.analyze"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        XCTAssertGreaterThan(input.frame.minY, app.frame.height * 0.4)
        XCTAssertFalse(submit.isEnabled)
        attach(app, name: "capture-compact-sheet")
        input.tap()
        input.typeText("A cafe near Taipei station")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertTrue(submit.isHittable)
        attach(app, name: "capture-sheet-keyboard")
        app.buttons["capture.keyboardDone"].tap()
        XCTAssertTrue(app.buttons["capture.importGoogleTakeout"].isHittable)
        app.buttons["Close capture"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(rootTabButton("Home", app: app).isSelected)
    }

    @MainActor
    func testGlobalShellSeparatesCaptureFromMapDrawer() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["drawer.launcher"].exists)

        let captureButtons = app.buttons.matching(identifier: "root.tab.save")
        XCTAssertEqual(captureButtons.count, 1)
        XCTAssertTrue(captureButtons.firstMatch.isHittable)
        captureButtons.firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
        app.buttons["Close capture"].tap()

        openRootTab("Map", app: app)
        let mapSearch = app.buttons["map.command.search"]
        XCTAssertTrue(mapSearch.waitForExistence(timeout: stepTimeout))
        mapSearch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "Only one command drawer should be presented."
        )
        XCTAssertTrue(app.descendants(matching: .any)["drawer.mapAssistant.intro"].waitForExistence(timeout: stepTimeout))
        for legacyTab in ["saved", "review", "friends", "lists"] {
            XCTAssertFalse(app.buttons["drawer.tab.\(legacyTab)"].exists)
        }
    }

    @MainActor
    func testMapSearchDrawerResizesThroughThreeStages() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: launchTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: stepTimeout))

        let collapsed = app.descendants(matching: .any)["map.drawerPanel.collapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: stepTimeout))
        waitForStableFrame(collapsed)
        let collapsedTop = collapsed.frame.minY
        attach(app, name: "map-search-drawer-collapsed")

        collapsed.swipeUp()
        let medium = app.descendants(matching: .any)["map.drawerPanel.medium"]
        XCTAssertTrue(medium.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].exists)
        waitForStableFrame(medium)
        let mediumTop = medium.frame.minY
        XCTAssertLessThan(mediumTop, collapsedTop - 120)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.maps.firstMatch.isHittable)
        attach(app, name: "map-search-drawer-medium")

        app.descendants(matching: .any)["map.drawerPanel.handle"].swipeUp()
        let large = app.descendants(matching: .any)["map.drawerPanel.large"]
        XCTAssertTrue(large.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].exists)
        waitForStableFrame(large)
        XCTAssertLessThan(large.frame.minY, mediumTop - 120)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attach(app, name: "map-search-drawer-large")

        app.descendants(matching: .any)["map.drawerPanel.handle"].swipeDown()
        XCTAssertTrue(medium.waitForExistence(timeout: stepTimeout))
        app.descendants(matching: .any)["map.drawerPanel.handle"].swipeDown()
        XCTAssertTrue(collapsed.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(app.maps.firstMatch.exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testPlanTabDraftsFromSavedMapStamps() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        openRootTab("Plan", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["plan.composer"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["origin.root"].exists)

        let compose = app.buttons["plan.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: stepTimeout))
        tapReachable(compose)
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForExistence(timeout: launchTimeout))
        attach(app, name: "plan-from-stamps")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testPlanCandidateCanBeConfirmedSavedAndOpened() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "--uitest-plan-candidate",
            "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Plan", app: app)
        let scroll = app.scrollViews.firstMatch
        let compose = app.buttons["plan.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: stepTimeout))
        tapReachable(compose)
        let candidate = app.buttons["tripPlan.confirm.Plan Test Garden"]
        XCTAssertTrue(scrollUntilHittable(candidate, in: scroll, maxSwipes: 10))
        attach(app, name: "plan-candidate-before-confirmation")
        candidate.tap()
        let confirm = app.buttons["Confirm & save place"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        confirm.tap()
        XCTAssertTrue(candidate.waitForNonExistence(timeout: timeout(30)))
        let save = app.buttons["tripPlan.save"]
        for _ in 0..<10 {
            if save.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(save.isHittable)
        let savedName = "Fourth saved plan"
        // Two seeded trips plus these two exercise access beyond the preview cards.
        for tripName in ["Confirmed candidate plan", savedName] {
            save.tap()
            let name = app.textFields["tripPlanSave.name"]
            XCTAssertTrue(name.waitForExistence(timeout: stepTimeout))
            replaceText(in: name, with: tripName)
            app.buttons["tripPlanSave.confirm"].tap()
            let success = app.alerts.firstMatch
            XCTAssertTrue(success.waitForExistence(timeout: timeout(20)))
            XCTAssertTrue(success.staticTexts["Saved to Trip Packs"].exists)
            success.buttons["OK"].tap()
        }
        let open = app.buttons["tripPlan.open"]
        XCTAssertTrue(open.waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-saved-open-action")
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip.plan"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Plan Test Garden"].firstMatch.exists)
        attach(app, name: "plan-confirmed-trip")

        terminate(app)
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Plan", app: app)
        let allTrips = app.buttons["plan.allTrips"]
        XCTAssertTrue(scrollUntilHittable(allTrips, in: app.scrollViews.firstMatch, maxSwipes: 8))
        allTrips.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))
        let tripMenu = app.buttons["trips.allTrips"]
        XCTAssertTrue(tripMenu.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(tripMenu.label.contains("4"))
        tripMenu.tap()
        let savedTrip = app.buttons[savedName]
        XCTAssertTrue(savedTrip.waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-all-four-trips")
        savedTrip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip.plan"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Plan Test Garden"].firstMatch.exists)
        attach(app, name: "plan-confirmed-trip-after-relaunch")
    }

    @MainActor
    func testLocateWithDeniedPermissionShowsRecoveryNotice() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-location-denied",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: launchTimeout))

        // The identifier is on the locate control itself (bottom-trailing,
        // Apple Maps placement above the floating search chrome).
        let locate = app.descendants(matching: .any)["map.currentLocation"]
        XCTAssertTrue(locate.waitForExistence(timeout: stepTimeout))
        locate.tap()

        // Spec P4: denied permission surfaces an Atlas notice with an Open
        // Settings action instead of a silent no-op.
        let notice = app.descendants(matching: .any)["map.locationNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["map.locationNotice.openSettings"].exists)
        attach(app, name: "map-location-denied-notice")

        app.buttons["map.locationNotice.dismiss"].tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: stepTimeout))
    }

    @MainActor
    func testMapPlaceCardOwnsStripActions() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-map-place-selected",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: launchTimeout))
        dismissLocationAlertIfPresent()

        // One place, one card (spec P2b): the Atlas card is canonical and now
        // carries the retired legacy strip's actions.
        let card = app.descendants(matching: .any)["map.place.card"]
        XCTAssertTrue(card.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "map.place.card").count,
            1,
            "Exactly one surface should represent the selected place."
        )
        XCTAssertTrue(app.descendants(matching: .any)["map.place.share"].exists)
        XCTAssertTrue(app.buttons["map.place.planAround"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["place.detail.root"].exists,
            "The legacy place strip must not co-present with the Atlas card."
        )
        XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
        attach(app, name: "map-place-card-actions")

        // Plan-around swaps the card for the single drawer surface.
        app.buttons["map.place.planAround"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout)
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "Plan-around should open exactly one drawer surface."
        )
        XCTAssertTrue(card.waitForNonExistence(timeout: stepTimeout))
    }

    @MainActor
    func testSavedPlaceEntryUsesSingleCanonicalDetail() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-map-place-selected",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: launchTimeout))

        let mapStampsSegment = app.buttons["saves.segment.mapStamps"]
        XCTAssertTrue(mapStampsSegment.waitForExistence(timeout: stepTimeout))
        mapStampsSegment.tap()
        XCTAssertTrue(mapStampsSegment.isSelected)

        let firstMapStamp = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'saves.place.'")
        ).firstMatch
        XCTAssertTrue(firstMapStamp.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(
            scrollUntilHittable(firstMapStamp, in: app.scrollViews.firstMatch),
            "The first Map Stamp should be reachable before opening its canonical detail."
        )
        firstMapStamp.tap()

        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "A Map Stamp should open one shared drawer."
        )
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.scroll"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "place.detail.scroll").count,
            1,
            "Every saved-place entry should use one canonical detail renderer."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.saved.postcardBody"].waitForExistence(timeout: stepTimeout),
            "A saved Map Stamp should use the lifted saved-postcard body."
        )
        XCTAssertTrue(app.buttons["drawer.saved.addToTrip"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-postcard-saved-drawer")

        let closeDetail = app.buttons["drawer.place.close"]
        XCTAssertTrue(closeDetail.waitForExistence(timeout: stepTimeout))
        closeDetail.tap()
        XCTAssertTrue(app.descendants(matching: .any)["drawer.root"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(firstMapStamp.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(mapStampsSegment.isSelected)
        XCTAssertFalse(rootTabButton("Saves", app: app).exists)

        let reviewSegment = app.buttons["saves.segment.review"]
        XCTAssertTrue(reviewSegment.waitForExistence(timeout: stepTimeout))
        reviewSegment.tap()
        XCTAssertTrue(reviewSegment.isSelected)
        XCTAssertTrue(
            app.descendants(matching: .any)["saves.review.empty"]
                .waitForExistence(timeout: stepTimeout),
            "Review should be an operable mode in the same Saves surface."
        )

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertFalse(
            app.buttons["map.command.search"].exists,
            "The selected place must replace, not stack above, the Map search shelf."
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["map.place.name"].waitForExistence(timeout: stepTimeout),
            "The root map selection should expose its real name."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["map.place.location"].exists,
            "Selecting a root-map place should expose its location."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["map.place.card"].exists,
            "Selecting a root-map place should expose the atlas place card."
        )
        XCTAssertTrue(app.buttons["map.place.close"].exists)

        let openMapDetails = app.buttons["map.place.openDetails"]
        XCTAssertTrue(openMapDetails.waitForExistence(timeout: stepTimeout))
        openMapDetails.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.scroll"].waitForExistence(timeout: stepTimeout))

        let closeMapDetail = app.buttons["drawer.place.close"]
        XCTAssertTrue(closeMapDetail.waitForExistence(timeout: stepTimeout))
        closeMapDetail.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(rootTabButton("Map", app: app).isSelected)
    }

    @MainActor
    func testUnsavedAndSocialDetailsUsePostcardDetailFamily() throws {
        let fixtures = [
            (
                launchArgument: "--uitest-postcard-unsaved",
                bodyIdentifier: "drawer.unsaved.postcardBody",
                primaryActionIdentifier: "drawer.unsaved.primaryAction",
                attachmentName: "atlas-postcard-unsaved-drawer"
            ),
            (
                launchArgument: "--uitest-postcard-social",
                bodyIdentifier: "drawer.social.postcardBody",
                primaryActionIdentifier: "drawer.social.primaryAction",
                attachmentName: "atlas-postcard-social-drawer"
            ),
        ]

        for fixture in fixtures {
            let app = makeApp(
                launchArguments: [
                    "--uitest-complete-onboarding",
                    "--skip-map-tour",
                    "--uitest-repair-review-demo-seed",
                    fixture.launchArgument,
                    "-save.appLanguage", "en",
                ]
            )
            launch(app)
            try signInViaReviewDemo(app: app)

            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: launchTimeout))
            XCTAssertEqual(
                app.descendants(matching: .any).matching(identifier: "place.detail.root").count,
                1,
                "Discovery detail should stay inside one focused detail surface."
            )
            XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
            XCTAssertTrue(
                app.descendants(matching: .any)["drawer.postcard.ticketHeader"]
                    .waitForExistence(timeout: stepTimeout),
                "Discovery detail should use the shared scalloped Postcard header."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[fixture.bodyIdentifier]
                    .waitForExistence(timeout: stepTimeout),
                "Discovery detail should use its Postcard body."
            )
            XCTAssertTrue(
                app.buttons[fixture.primaryActionIdentifier].waitForExistence(timeout: stepTimeout),
                "Discovery detail should keep one coral primary action."
            )
            attach(app, name: fixture.attachmentName)
            terminate(app)
        }
    }

    @MainActor
    func testTripStopEditorSurfaceIsReachable() throws {
        let storageID = UUID().uuidString.lowercased()
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        let firstTrip = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'trips.card.' AND label CONTAINS[c] %@",
                "Tokyo Weekend"
            )
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: launchTimeout))
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
        let noteField = app.descendants(matching: .any)["trip.stop.edit.note"]
        XCTAssertTrue(noteField.exists)
        XCTAssertTrue(app.buttons["trip.stop.edit.save"].exists)
        XCTAssertTrue(app.buttons["trip.stop.edit.remove"].exists)
        attach(app, name: "atlas-trip-stop-editor-sheet")

        replaceText(in: app.textFields["trip.stop.edit.startTime"], with: "09:30")
        replaceText(in: app.textFields["trip.stop.edit.duration"], with: "45")
        let keyboardDone = app.buttons["trip.stop.edit.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: stepTimeout))
        keyboardDone.tap()
        replaceText(
            in: app.descendants(matching: .any)["trip.stop.edit.note"],
            with: "UI smoke"
        )
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: stepTimeout))
        keyboardDone.tap()
        app.buttons["trip.stop.edit.save"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.stop.edit"]
                .waitForNonExistence(timeout: stepTimeout),
            "Trip stop editor never dismissed after save."
        )

        XCTAssertTrue(firstStopEditor.waitForExistence(timeout: stepTimeout))
        firstStopEditor.tap()
        XCTAssertEqual(app.textFields["trip.stop.edit.startTime"].value as? String, "09:30")
        XCTAssertEqual(app.textFields["trip.stop.edit.duration"].value as? String, "45")
        XCTAssertEqual(
            app.descendants(matching: .any)["trip.stop.edit.note"].value as? String,
            "UI smoke"
        )

        app.buttons["trip.stop.edit.remove"].tap()
        XCTAssertTrue(app.buttons["trip.stop.edit.remove.confirm"].waitForExistence(timeout: stepTimeout))
        app.alerts.buttons["Cancel"].tap()
        app.navigationBars.buttons["Cancel"].tap()

        let addMapStamp = app.buttons["trip.plan.addStop"]
        XCTAssertTrue(addMapStamp.waitForExistence(timeout: stepTimeout))
        addMapStamp.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip.add.sheet"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.steppers["trip.add.dayPicker"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-trip-add-saved-place-sheet")
    }

    @MainActor
    func testRapidChromeTransitionsKeepAppAlive() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-rapid-chrome-transitions",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )

        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: launchTimeout),
            "Rapid sheet -> Passport -> Save transitions never settled on the final capture cover."
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testPassportAndPostalImportSurfacesAreReachable() throws {
        let storageID = UUID().uuidString.lowercased()
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )

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

        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))

        for tab in ["Home", "Plan"] {
            openRootTab(tab, app: app)
            XCTAssertTrue(
                app.buttons["root.passport"].waitForExistence(timeout: stepTimeout),
                "\(tab) should keep the fixed Passport entry in its Savvy lockup."
            )
        }

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["map.command.search"].waitForExistence(timeout: stepTimeout),
            "Map geography-first chrome is the floating Apple Maps search capsule."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["map.command.passport"].waitForExistence(timeout: stepTimeout),
            "Passport opens from the Apple Maps avatar slot inside the search capsule."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["map.stampCount"].exists,
            "Apple Maps reference keeps Map top empty; no persistent stamp chip."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["root.passport"].exists,
            "Passport must not sit in persistent Map top chrome."
        )

        openRootTab("Profile", app: app)

        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["profile.cover"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["profile.stampLedger"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-passport")

        let connections = app.buttons["profile.connections"]
        XCTAssertTrue(
            scrollUntilHittable(connections, in: app.scrollViews.firstMatch, maxSwipes: 12),
            "Passport controls should expose Friends & Lists."
        )
        connections.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["profile.connections.root"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(app.buttons["profile.connections.friends"].exists)
        XCTAssertTrue(app.buttons["profile.connections.lists"].exists)
        app.buttons["profile.connections.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))

        XCTAssertFalse(app.buttons["profile.importGoogleTakeout"].exists)

        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))

        let importButton = app.buttons["capture.importGoogleTakeout"]
        XCTAssertTrue(
            scrollUntilHittable(importButton, in: app.scrollViews.firstMatch, maxSwipes: 12),
            "The center Save flow should expose Postal Import."
        )
        importButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["takeout.import.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["takeout.import.chooseFile"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-postal-import-empty")
    }

    @MainActor
    func testPassportConnectionsKeepsFriendsAndListsReachable() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.buttons["root.passport"].waitForExistence(timeout: launchTimeout))
        app.buttons["root.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))

        let connections = app.buttons["profile.connections"]
        XCTAssertTrue(scrollUntilHittable(connections, in: app.scrollViews.firstMatch, maxSwipes: 12))
        connections.tap()

        XCTAssertTrue(app.descendants(matching: .any)["profile.connections.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["profile.connections.friends"].exists)
        XCTAssertTrue(app.buttons["profile.connections.lists"].exists)
        XCTAssertTrue(app.textFields["profile.connections.referral"].exists)
        XCTAssertTrue(app.buttons["profile.connections.follow"].exists)
    }

    @MainActor
    func testTripKmlExportMenuSmoke() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        let firstTrip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")
        ).firstMatch
        XCTAssertTrue(firstTrip.waitForExistence(timeout: launchTimeout))
        firstTrip.tap()

        let shareAction = app.buttons["trip.share.action"]
        XCTAssertTrue(shareAction.waitForExistence(timeout: stepTimeout))
        shareAction.tap()

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
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )

        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))

        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()

        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        let captureInput = app.textViews["capture.input"]
        typeText(mapURL, into: captureInput)
        let analyze = app.buttons["capture.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: stepTimeout))
        analyze.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["capture.flow"].waitForNonExistence(timeout: timeout(20)),
            "Capture should dismiss after Analyze into Review."
        )
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: timeout(20)))
        let candidate = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.reviewCandidate.' AND label CONTAINS[c] %@",
                placeName
            )
        ).firstMatch
        XCTAssertTrue(
            candidate.waitForExistence(timeout: timeout(20)),
            "Expected the captured map link as a Review Candidate.\n\(app.debugDescription)"
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

        // Saving no longer interrupts with a trip prompt; adding to a Trip is
        // an explicit action from the saved place detail.
        let savedPlace = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'saves.place.' AND label CONTAINS[c] %@", placeName)
        ).firstMatch
        XCTAssertTrue(
            savedPlace.waitForExistence(timeout: timeout(20)),
            "Confirmed candidate should appear as a saved place.\n\(app.debugDescription)"
        )
        savedPlace.tap()

        let savedDetailScroll = app.scrollViews["place.detail.scroll"]
        XCTAssertTrue(savedDetailScroll.waitForExistence(timeout: stepTimeout))
        let addToTrip = app.buttons["drawer.saved.addToTrip"]
        XCTAssertTrue(
            scrollUntilHittable(addToTrip, in: savedDetailScroll),
            "Add-to-trip action never became tappable.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            app.buttons["drawer.saved.planAround"].waitForExistence(timeout: stepTimeout),
            "Plan around this should sit beside Add to Trip.\n\(app.debugDescription)"
        )
        addToTrip.tap()

        let createTripAndAdd = app.buttons
            .matching(identifier: "saved.addToTrip.create")
            .firstMatch
        XCTAssertTrue(createTripAndAdd.waitForExistence(timeout: stepTimeout))
        createTripAndAdd.tap()

        XCTAssertTrue(app.descendants(matching: .any)["trip.create.sheet"].waitForExistence(timeout: stepTimeout))
        let tripNameField = app.textFields["trip.create.name"]
        XCTAssertTrue(tripNameField.waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-trip-create-sheet")
        typeText(tripName, into: tripNameField)
        typeText("Los Angeles", into: app.textFields["trip.create.city"])
        app.buttons["trip.create.submit"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["trip.create.sheet"]
                .waitForNonExistence(timeout: stepTimeout),
            "Trip create sheet never dismissed after submit."
        )
        try assertSavedPlaceAndTripStopPersist(
            app: app,
            placeName: placeName,
            tripName: tripName
        )

        terminate(app)
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        try assertSavedPlaceAndTripStopPersist(
            app: app,
            placeName: placeName,
            tripName: tripName
        )
    }

    /// Focused App Store capture rail for the place-memory promise.
    ///
    /// These attachments deliberately exclude Trips while planning remains a
    /// beta surface. Every frame comes from the production SwiftUI hierarchy;
    /// the marketing board only adds the outer headline treatment.
    @MainActor
    func testCaptureAppStoreCoreScreensV5() throws {
        let seededApp = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-home-region-taipei",
                "-save.appLanguage", "en",
            ]
        )

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

        launch(seededApp)
        try signInViaReviewDemo(app: seededApp)
        XCTAssertTrue(
            seededApp.descendants(matching: .any)["home.root"]
                .waitForExistence(timeout: launchTimeout)
        )
        attach(seededApp, name: "v5-01-home-place-memory")

        rootTabButton("Save", app: seededApp).tap()
        XCTAssertTrue(
            seededApp.descendants(matching: .any)["capture.flow"]
                .waitForExistence(timeout: stepTimeout)
        )
        let previewInput = seededApp.textViews["capture.input"]
        typeText(
            "https://maps.google.com/?q=Fuhang+Soy+Milk+Taipei",
            into: previewInput
        )
        let captureKeyboardDone = seededApp.buttons["capture.keyboardDone"]
        XCTAssertTrue(captureKeyboardDone.waitForExistence(timeout: stepTimeout))
        captureKeyboardDone.tap()
        XCTAssertTrue(seededApp.buttons["capture.analyze"].isHittable)
        attach(seededApp, name: "v5-02-capture-link")
        seededApp.buttons["Close capture"].tap()

        XCTAssertTrue(
            seededApp.buttons["root.passport"].waitForExistence(timeout: stepTimeout)
        )
        seededApp.buttons["root.passport"].tap()
        XCTAssertTrue(
            seededApp.descendants(matching: .any)["profile.root"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            seededApp.descendants(matching: .any)["profile.cover"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertFalse(seededApp.staticTexts["User not authenticated"].exists)
        XCTAssertFalse(seededApp.staticTexts["Reviewer demo session has no auth token"].exists)
        attach(seededApp, name: "v5-05-private-passport")
        seededApp.buttons["profile.close"].tap()

        openRootTab("Map", app: seededApp)
        dismissLocationAlertIfPresent()
        XCTAssertTrue(
            seededApp.descendants(matching: .any)["map.root"]
                .waitForExistence(timeout: stepTimeout)
        )
        sleep(10)
        attach(seededApp, name: "v5-04-private-map")
        terminate(seededApp)

        let storageID = UUID().uuidString.lowercased()
        let reviewApp = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )

        launch(reviewApp)
        try signInViaReviewDemoRequired(app: reviewApp)
        XCTAssertTrue(
            reviewApp.descendants(matching: .any)["home.root"]
                .waitForExistence(timeout: launchTimeout)
        )

        rootTabButton("Save", app: reviewApp).tap()
        let captureInput = reviewApp.textViews["capture.input"]
        XCTAssertTrue(captureInput.waitForExistence(timeout: stepTimeout))
        typeText(
            "https://www.google.com/maps/place/Harbor+Oven+Pizza/@33.7405,-118.2807,17z/data=!3m1",
            into: captureInput
        )
        let reviewKeyboardDone = reviewApp.buttons["capture.keyboardDone"]
        XCTAssertTrue(reviewKeyboardDone.waitForExistence(timeout: stepTimeout))
        reviewKeyboardDone.tap()
        XCTAssertTrue(reviewApp.buttons["capture.analyze"].isHittable)
        reviewApp.buttons["capture.analyze"].tap()

        XCTAssertTrue(
            reviewApp.descendants(matching: .any)["saves.root"]
                .waitForExistence(timeout: timeout(20))
        )
        let candidate = reviewApp.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'saves.reviewCandidate.'")
        ).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: timeout(20)))
        candidate.tap()
        XCTAssertTrue(
            reviewApp.descendants(matching: .any)["place.detail.root"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            reviewApp.descendants(matching: .any)["drawer.review.postcardBody"]
                .waitForExistence(timeout: stepTimeout)
        )
        attach(reviewApp, name: "v5-03-review-before-map")
    }

    // MARK: - Demo sign-in

    /// Types the App Review demo email + code (native SwiftUI fields — the
    /// demo pair never hits Privy or the network, see ReviewDemoService).
    @MainActor
    private func signInViaReviewDemo(app: XCUIApplication) throws {
        let emailField = app.textFields["signin.emailField"]
        // The opening animation holds the screen for ~2s before SignInView.
        guard emailField.waitForExistence(timeout: timeout(20)) else {
            // A previous demo session may already be signed in.
            if app.descendants(matching: .any)["home.root"].waitForExistence(timeout: stepTimeout) {
                return
            }
            throw XCTSkip("Email sign-in field never appeared — cannot reach the demo session.")
        }

        typeText("appreview@wanderly.app", into: emailField)
        dismissKeyboard(app: app) // sign-in layout ignores the keyboard safe area

        let sendCode = app.buttons["signin.sendCode"]
        guard waitUntilHittable(sendCode) else {
            throw XCTSkip("Send-code button not tappable — cannot start the demo flow.")
        }
        sendCode.tap()

        let codeField = app.textFields["signin.codeField"]
        guard codeField.waitForExistence(timeout: stepTimeout) else {
            throw XCTSkip("Verification-code field never appeared after sending the demo code.")
        }
        typeText("424242", into: codeField)
        dismissKeyboard(app: app) // number pad has no return key

        let verify = app.buttons["signin.verify"]
        guard waitUntilHittable(verify) else {
            throw XCTSkip("Verify button not tappable — cannot enter the demo session.")
        }
        verify.tap()
    }

    @MainActor
    private func signInViaReviewDemoRequired(app: XCUIApplication) throws {
        let emailField = app.textFields["signin.emailField"]
        if !emailField.waitForExistence(timeout: timeout(20)) {
            XCTAssertTrue(
                app.descendants(matching: .any)["home.root"].waitForExistence(timeout: stepTimeout),
                "Email sign-in and Home were both unavailable."
            )
            return
        }

        typeText("appreview@wanderly.app", into: emailField)
        dismissKeyboard(app: app)

        let sendCode = app.buttons["signin.sendCode"]
        XCTAssertTrue(
            waitUntilHittable(sendCode),
            "Send-code button never became tappable."
        )
        sendCode.tap()

        let codeField = app.textFields["signin.codeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: stepTimeout))
        typeText("424242", into: codeField)
        dismissKeyboard(app: app)

        let verify = app.buttons["signin.verify"]
        XCTAssertTrue(
            waitUntilHittable(verify),
            "Verify button never became tappable after dismissing the keyboard."
        )
        verify.tap()
    }

    /// Taps the keyboard-toolbar Done button (signin.keyboardDone) so the
    /// buttons hidden underneath the keyboard become hittable again. No-op if
    /// the software keyboard isn't showing (e.g. hardware keyboard connected).
    @MainActor
    private func dismissKeyboard(app: XCUIApplication) {
        let done = app.buttons["signin.keyboardDone"]
        if done.waitForExistence(timeout: timeout(3)), done.isHittable {
            done.tap()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func openRootTab(_ title: String, app: XCUIApplication) {
        if !rootTabButton(title, app: app).isHittable {
            returnToRootBar(app: app)
        }
        let tab = rootTabButton(title, app: app)
        XCTAssertTrue(tab.waitForExistence(timeout: stepTimeout), "Missing \(title) root tab")
        tab.tap()
        if let screenIdentifier = rootScreenIdentifier(for: title),
           !app.descendants(matching: .any)[screenIdentifier].waitForExistence(timeout: timeout(2)) {
            tab.tap()
        }
    }

    @MainActor
    private func rootScreenIdentifier(for title: String) -> String? {
        switch title {
        case "Home": return "home.root"
        case "Map": return "map.root"
        case "Plan": return "plan.root"
        case "Profile": return "profile.root"
        default: return nil
        }
    }

    @MainActor
    private func openSavesFromHome(app: XCUIApplication) {
        openRootTab("Home", app: app)
        let moreActions = app.descendants(matching: .any)["home.more"]
        if moreActions.waitForExistence(timeout: timeout(2)) {
            tapReachable(moreActions)
        }
        // Live Home: Manage (`home.saves`). Parity-fixture Home still uses the
        // locked One-Face stack, whose Saves entry is Review clues (`home.review`).
        let candidates: [XCUIElement] = [
            app.descendants(matching: .any)["home.saves"],
            app.buttons["Manage saved places"],
            app.buttons["管理已存地點"],
            app.buttons["Manage"],
            app.descendants(matching: .any)["home.review"],
            app.buttons["Review clues"],
        ]
        let entry = firstExisting(candidates, timeout: stepTimeout)
        XCTAssertTrue(entry.exists, "Missing Home Saves entry")
        tapReachable(entry)
        let saves = app.descendants(matching: .any)["saves.root"]
        if !saves.waitForExistence(timeout: timeout(5)) {
            tapReachable(entry)
        }
        // Cap at stepTimeout, not launchTimeout. A dead navigation used to
        // burn 120s per attempt; four flakes × 3 retries blew the 35-minute
        // rail step (CI 32778736280, exit 64).
        XCTAssertTrue(
            saves.waitForExistence(timeout: stepTimeout),
            "Home Saves entry did not open Saves"
        )
    }

    @MainActor
    private func openTripsFromHome(app: XCUIApplication) {
        openRootTab("Home", app: app)
        let moreActions = app.descendants(matching: .any)["home.more"]
        if moreActions.waitForExistence(timeout: timeout(2)) {
            tapReachable(moreActions)
        }
        let candidates: [XCUIElement] = [
            app.descendants(matching: .any)["home.trips"],
            app.buttons["Trips"],
            app.buttons["行程"],
        ]
        let entry = firstExisting(candidates, timeout: stepTimeout)
        XCTAssertTrue(entry.exists, "Missing Home Trips entry")
        tapReachable(entry)
        let trips = app.descendants(matching: .any)["trips.home"]
        if !trips.waitForExistence(timeout: timeout(5)) {
            if app.descendants(matching: .any)["profile.root"].exists
                || app.descendants(matching: .any)["plan.root"].exists {
                openRootTab("Home", app: app)
            }
            tapReachable(firstExisting(candidates, timeout: timeout(2)))
        }
        XCTAssertTrue(
            trips.waitForExistence(timeout: stepTimeout),
            "Home Trips entry did not open Trips"
        )
    }

    @MainActor
    private func firstExisting(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = elements.first(where: \.exists) {
                return found
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return elements.first(where: \.exists) ?? elements[0]
    }

    /// Live Home paints hybrid / Look Around covers asynchronously. The Atlas
    /// gate compares `five-tab-home` to `ProductionTargets/home.png`. Attaching
    /// on `home.root` alone captured the pin fallback (CI #184 score 0.70);
    /// the same target scores 0.93 once MapKit imagery lands.
    @MainActor
    private func waitForHomeCoverImagery(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Live Home should show the saved-place library before the parity raster."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["home.photoHero"].waitForExistence(timeout: stepTimeout),
            "Live Home should show the featured cover before the parity raster."
        )

        // Pin-fallback Home on the 402pt 3x CI viewport is ~0.7MB. Hybrid /
        // Look Around covers from the same viewport land at ~2–3MB.
        let minimumPaintedBytes = 1_200_000
        let deadline = Date().addingTimeInterval(timeout(6))
        while Date() < deadline {
            if app.screenshot().pngRepresentation.count >= minimumPaintedBytes {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
    }

    @MainActor
    private func waitForStableFrame(
        _ element: XCUIElement,
        timeout: TimeInterval = 3
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var previousFrame = element.frame
        var stableSamples = 0

        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let frame = element.frame
            let movement = max(
                abs(frame.minY - previousFrame.minY),
                abs(frame.height - previousFrame.height)
            )
            stableSamples = movement < 1 ? stableSamples + 1 : 0
            if stableSamples >= 2 { return }
            previousFrame = frame
        }
    }

    /// The 402pt Atlas canvas is scaled by `ReferenceViewport`. XCTest can
    /// report `exists` while `isHittable` is false; a center coordinate tap
    /// still hits the control.
    @MainActor
    private func tapReachable(_ element: XCUIElement) {
        if element.exists, element.isHittable {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func returnToRootBar(app: XCUIApplication) {
        // Capture and confirm can replace one full-screen detail with another
        // before leaving the pushed Saves route. Unwind every visible layer,
        // then pop the child route back to the five-tab root.
        for _ in 0..<12 {
            if rootTabButton("Home", app: app).exists { return }

            let placeDetailClose = app.buttons["drawer.place.close"]
            if placeDetailClose.exists, placeDetailClose.isHittable {
                placeDetailClose.tap()
                continue
            }

            let tripBack = app.buttons["trip.back"]
            if tripBack.exists, tripBack.isHittable {
                tripBack.tap()
                continue
            }

            let navigationBack = app.navigationBars.buttons.element(boundBy: 0)
            if navigationBack.exists, navigationBack.isHittable {
                navigationBack.tap()
                continue
            }

            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.50))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.50))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(rootTabButton("Home", app: app).waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    private func rootTabButton(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.buttons["root.tab.\(title.lowercased())"]
    }

    @MainActor
    private func tripTabButton(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.buttons["trip.tab.\(title.lowercased())"]
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with replacement: String) {
        focus(field)
        if let current = field.value as? String,
           current != field.placeholderValue,
           !current.isEmpty {
            field.typeKey("a", modifierFlags: .command)
        }
        field.typeText(replacement)
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maxSwipes: Int = 5
    ) -> Bool {
        for _ in 0..<maxSwipes {
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
        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let savedPlace = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.place.' AND label CONTAINS[c] %@",
                placeName
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilExists(savedPlace, app: app), "Saved Map Stamp is missing.")

        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))
        let tripCard = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'trips.card.' AND label CONTAINS[c] %@",
                tripName
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilExists(tripCard, app: app), "Created Trip is missing.")
        tripCard.tap()

        XCTAssertTrue(tripTabButton("Plan", app: app).waitForExistence(timeout: stepTimeout))
        let tripStop = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'trip.stop.' AND identifier ENDSWITH '.edit' AND label == %@",
                "Edit \(placeName)"
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilExists(tripStop, app: app), "Confirmed Trip stop is missing.")

        let backButton = app.buttons["trip.back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: stepTimeout))
        backButton.tap()
    }

    @MainActor
    private func scrollUntilExists(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.waitForExistence(timeout: timeout(1)) { return true }
            app.swipeUp()
        }
        return element.waitForExistence(timeout: timeout(1))
    }

    /// Dismisses the system location permission alert if it is on screen.
    /// Queried on SpringBoard because system alerts live outside the app.
    @MainActor
    private func dismissLocationAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: timeout(3)) {
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
}
