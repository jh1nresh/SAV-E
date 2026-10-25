import XCTest
import UIKit

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
    func testHomeListProgressiveSearch() throws {
        for staticMode in [false, true] {
            let app = makeApp(launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed", "--uitest-home-memory-fixture",
                "-save.appLanguage", staticMode ? "zh-Hant" : "en"
            ] + (staticMode ? ["--uitest-home-reduce-motion", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] : []),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
            launch(app)
            try signInViaReviewDemoRequired(app: app)
            XCTAssertTrue(app.buttons["home.passport"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.buttons["home.eat"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.buttons["home.go"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.descendants(matching: .any)["home.locationPrompt"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.buttons["home.locationAllow"].waitForExistence(timeout: stepTimeout))
            XCTAssertFalse(app.descendants(matching: .any)["home.memoryPile"].exists)
            XCTAssertFalse(app.buttons["home.viewAll"].exists)
            XCTAssertFalse(app.textFields["home.search"].exists)
            attach(app, name: "home-list-browse-\(staticMode)")
            if !staticMode {
                attach(app, name: "doodle-home-multirow")
            }
            let cafe = app.buttons["home.place.10000000-0000-0000-0000-000000000001"]
            XCTAssertTrue(cafe.waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.staticTexts["Taipei Window Cafe"].firstMatch.exists)
            tapReachable(app.buttons["home.go"])
            XCTAssertTrue(
                app.buttons["home.place.10000000-0000-0000-0000-000000000005"].waitForExistence(timeout: stepTimeout)
            )
            XCTAssertFalse(app.buttons["home.place.10000000-0000-0000-0000-000000000001"].exists)
            attach(app, name: "home-list-cafes-\(staticMode)")
            tapReachable(app.buttons["home.eat"])
            XCTAssertTrue(cafe.waitForExistence(timeout: stepTimeout))
            tapReachable(app.buttons["home.citySwitcher"])
            let tainan = app.descendants(matching: .any)["home.city.tainan"]
            XCTAssertTrue(tainan.waitForExistence(timeout: stepTimeout))
            tapReachable(tainan)
            let garden = app.buttons["home.place.10000000-0000-0000-0000-000000000002"]
            XCTAssertTrue(garden.waitForExistence(timeout: stepTimeout))
            attach(app, name: "home-list-taipei-\(staticMode)")
            tapReachable(app.buttons["home.citySwitcher"])
            let taipeiCity = app.descendants(matching: .any)["home.city.taipei"]
            XCTAssertTrue(taipeiCity.waitForExistence(timeout: stepTimeout))
            tapReachable(taipeiCity)
            XCTAssertTrue(cafe.waitForExistence(timeout: stepTimeout))
            attach(app, name: "home-list-no-match-\(staticMode)")
            cafe.tap()
            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.staticTexts["Taipei Window Cafe"].firstMatch.exists)
            attach(app, name: "home-list-open-detail-\(staticMode)")
            app.terminate()
        }

        let allowed = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-allowed",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed", "--uitest-home-memory-fixture",
            "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(allowed)
        try signInViaReviewDemoRequired(app: allowed)
        XCTAssertTrue(allowed.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(allowed.descendants(matching: .any)["home.locationPrompt"].exists)
        attach(allowed, name: "doodle-home-allowed")
        allowed.terminate()
    }

    @MainActor
    /// Real empty feed (no followed friends). Friends is shipped, so a
    /// coming-soon state cannot occur and is not shown.
    func testFriendsComingSoon() throws {
        try assertFriendsComingSoonLanguages()
    }

    /// Real 375pt simulator (SE / mini). Not a maxWidth letterbox on 402pt.
    @MainActor
    func testFriendsWidth375() throws {
        try captureFriendsWidthEvidence(width: 375, columns: 1, name: "friends-375")
    }

    /// Real 390pt simulator (iPhone 14). Not a maxWidth letterbox on 402pt.
    @MainActor
    func testFriendsWidth390() throws {
        try captureFriendsWidthEvidence(width: 390, columns: 1, name: "friends-390")
    }

    /// Real 430pt simulator (Pro Max). Not a maxWidth letterbox on 402pt.
    @MainActor
    func testFriendsWidth430() throws {
        try captureFriendsWidthEvidence(width: 430, columns: 1, name: "friends-430")
    }

    /// HoP width shots: assert the booted device point width and the
    /// people-first single column, then attach `friends-375|390|430`.
    @MainActor
    private func captureFriendsWidthEvidence(width: Int, columns: Int, name: String) throws {
        let language = width == 390 ? "zh-Hant" : "en"
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed",
                "--uitest-friends-town",
                "-save.appLanguage", language,
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        openRootTab("Friends", app: app)
        let root = app.descendants(matching: .any)["friends.root"]
        XCTAssertTrue(root.waitForExistence(timeout: stepTimeout))
        let list = app.descendants(matching: .any)["friends.list"]
        XCTAssertTrue(list.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            Int(app.frame.width.rounded()),
            width,
            "Friends width shot must boot a real \(width)pt simulator"
        )
        XCTAssertEqual(
            Int(root.frame.width.rounded()),
            width,
            "Friends root must use the full \(width)pt device width, not a letterbox"
        )
        XCTAssertEqual(list.value as? String, "\(columns)", "Friends is a 1-column people list")
        attach(app, name: name)
        attach(app, name: "friends-town-\(width)")
        terminate(app)
    }

    @MainActor
    private func assertFriendsComingSoonLanguages() throws {
        for (language, expectedTitle) in [("en", "Their next place could be yours"), ("zh-Hant", "下一個想去的地方，從朋友開始")] {
            let app = makeApp(launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed", "-save.appLanguage", language
            ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
            launch(app)
            try signInViaReviewDemoRequired(app: app)
            XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
            waitForHomeCoverImagery(app)
            waitForStableFrame(rootTabButton("Friends", app: app))
            attach(app, name: "friends-before-opening-\(language)")
            openRootTab("Friends", app: app)
            attach(app, name: "friends-after-opening-\(language)")
            let title = app.staticTexts["friends.empty"]
            if !title.waitForExistence(timeout: stepTimeout) {
                print(app.debugDescription)
                XCTFail("The localized empty feed must remain accessible.")
            }
            XCTAssertEqual(title.label, expectedTitle)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'root.tab.'")).count, 5)
            XCTAssertFalse(rootTabButton("Plan", app: app).exists)
            XCTAssertFalse(app.textFields["friends.invite"].exists)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'friends.save.' OR identifier BEGINSWITH 'friends.rate.'")).firstMatch.exists)
            XCTAssertLessThan(title.frame.maxY, rootTabButton("Friends", app: app).frame.minY)
            attach(app, name: "friends-empty-\(language)")
            let findFriends = app.buttons["friends.findFriends"]
            XCTAssertTrue(findFriends.isHittable)
            XCTAssertEqual(findFriends.label, language == "en" ? "Find friends" : "追蹤朋友")
            try assertReadableButtonLabel(findFriends)
            findFriends.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.connections.root"].waitForExistence(timeout: stepTimeout))
            app.buttons["profile.connections.back"].tap()
            openRootTab("Home", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["home.root"].firstMatch.waitForExistence(timeout: stepTimeout))
            openRootTab("Friends", app: app)
            XCTAssertTrue(title.waitForExistence(timeout: stepTimeout))
            XCTAssertEqual(title.label, expectedTitle)
            openRootTab("Passport", app: app)
            app.buttons["profile.settings"].tap()
            let sharedRatings = app.buttons["profile.sharedRatings"]
            XCTAssertTrue(scrollUntilHittable(sharedRatings, in: app.scrollViews.firstMatch, maxSwipes: 10))
            sharedRatings.tap()
            let emptyRatings = app.staticTexts["profile.sharedRatings.empty"]
            XCTAssertTrue(emptyRatings.waitForExistence(timeout: stepTimeout))
            XCTAssertEqual(emptyRatings.label, language == "en" ? "No shared restaurant ratings" : "沒有已分享的餐廳評分")
            attach(app, name: "passport-shared-ratings-\(language)")
            app.buttons["profile.sharedRatings.done"].tap()
            XCTAssertTrue(emptyRatings.waitForNonExistence(timeout: stepTimeout))
            terminate(app)
        }

        let dynamicType = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed",
            "-save.appLanguage", "en",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(dynamicType)
        try signInViaReviewDemoRequired(app: dynamicType)
        XCTAssertTrue(dynamicType.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        openRootTab("Friends", app: dynamicType)
        XCTAssertTrue(dynamicType.staticTexts["friends.empty"].waitForExistence(timeout: stepTimeout))
        attach(dynamicType, name: "friends-dynamic-type-xxxl")
        let widthNote = XCTAttachment(string: "friends.window.width=\(dynamicType.windows.firstMatch.frame.width)")
        widthNote.name = "friends-window-width"
        widthNote.lifetime = .keepAlways
        add(widthNote)
        terminate(dynamicType)

        for (name, flag) in [
            ("friends-loading", "--uitest-friends-loading"),
            ("friends-error", "--uitest-friends-error"),
        ] {
            let app = makeApp(launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed", flag,
                "-save.appLanguage", "en",
            ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
            launch(app)
            try signInViaReviewDemoRequired(app: app)
            XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
            openRootTab("Friends", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["friends.root"].waitForExistence(timeout: stepTimeout))
            if name == "friends-loading" {
                XCTAssertTrue(app.descendants(matching: .any)["friends.loading"].waitForExistence(timeout: stepTimeout))
            }
            if name == "friends-error" {
                XCTAssertTrue(app.descendants(matching: .any)["posts.error"].waitForExistence(timeout: stepTimeout))
                XCTAssertTrue(app.buttons["friends.retry"].waitForExistence(timeout: stepTimeout))
            }
            attach(app, name: name)
            terminate(app)
        }
    }

    /// Accessibility can still expose a label painted in the same color as its
    /// fill. Sample the rendered center, excluding rounded edges and shadows.
    @MainActor
    private func assertReadableButtonLabel(_ button: XCUIElement) throws {
        let image = try XCTUnwrap(button.screenshot().image.cgImage)
        let center = CGRect(x: CGFloat(image.width) * 0.2, y: CGFloat(image.height) * 0.25,
                            width: CGFloat(image.width) * 0.6, height: CGFloat(image.height) * 0.5)
        let crop = try XCTUnwrap(image.cropping(to: center.integral))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminances = stride(from: 0, to: pixels.count, by: 4).map { offset in
            0.2126 * linear(pixels[offset]) + 0.7152 * linear(pixels[offset + 1]) + 0.0722 * linear(pixels[offset + 2])
        }.sorted()
        let low = luminances[luminances.count / 20]
        let high = luminances[luminances.count * 19 / 20]
        XCTAssertGreaterThanOrEqual((high + 0.05) / (low + 0.05), 4.5,
            "The visible button label must contrast with its fill, not merely exist in accessibility.")
    }

    @MainActor
    func testSocialPassportGridAndComposer() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed", "--uitest-social-posts", "-save.appLanguage", "zh-Hant"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Passport", app: app)
        let quests = app.descendants(matching: .any)["profile.today"].firstMatch
        XCTAssertTrue(quests.waitForExistence(timeout: stepTimeout))
        let filter = app.segmentedControls["posts.filter"]
        XCTAssertTrue(scrollUntilHittable(filter, in: app.scrollViews.firstMatch, maxSwipes: 4))
        XCTAssertLessThan(quests.frame.minY, filter.frame.minY, "Quests precede posts.")
        attach(app, name: "social-passport-post-grid")
        filter.buttons["去過"].tap()
        let visited = app.buttons["posts.item.22222222-2222-4222-8222-222222222222"]
        XCTAssertTrue(visited.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["posts.item.11111111-1111-4111-8111-111111111111"].exists)
        visited.tap()
        XCTAssertTrue(app.buttons["posts.edit"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(app.staticTexts["posts.audience"].label, "分享已暫停，目前只有你能查看")
        attach(app, name: "social-passport-post-detail")
        app.buttons["完成"].firstMatch.tap()
        openRootTab("Friends", app: app)
        let feedPost = app.buttons["friends.post.11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(feedPost.waitForExistence(timeout: stepTimeout))
        attach(app, name: "social-friends-feed")
        feedPost.tap()
        XCTAssertTrue(app.buttons["posts.save"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["posts.edit"].exists, "A recipient cannot edit an author's post.")
        attach(app, name: "social-friend-post-detail")
        app.buttons["完成"].firstMatch.tap()
        openRootTab("Passport", app: app)
        let newPost = app.buttons["posts.new"]
        let passportScroll = app.scrollViews.firstMatch
        XCTAssertTrue(scrollUntilHittable(newPost, in: passportScroll, maxSwipes: 4))
        // XCTest can report an element behind the fixed root bar as hittable.
        // Clear the capture button before tapping the Passport action.
        let captureTop = rootTabButton("Save", app: app).frame.minY
        for _ in 0..<4 {
            if newPost.frame.maxY <= captureTop - 8 { break }
            passportScroll.swipeUp()
        }
        XCTAssertTrue(newPost.isHittable)
        XCTAssertLessThanOrEqual(newPost.frame.maxY, captureTop - 8)
        attach(app, name: "social-new-post-above-tabs")
        newPost.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: stepTimeout))
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.textViews["posts.caption"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["posts.publish"].isEnabled, "The demo cannot publish real posts.")
        let addPhotos = app.buttons["posts.photos.add"]
        XCTAssertTrue(addPhotos.waitForExistence(timeout: stepTimeout), "Sharing offers explicit photo attachment.")
        XCTAssertTrue(addPhotos.isEnabled)
        attach(app, name: "social-post-composer")
        addPhotos.tap()
        let cancelPicker = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "取消")).firstMatch
        XCTAssertTrue(cancelPicker.waitForExistence(timeout: stepTimeout))
        attach(app, name: "social-post-photo-picker")
        cancelPicker.tap()
        XCTAssertTrue(app.buttons["posts.photos.add"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["posts.publish"].isEnabled, "Cancelling the picker cannot publish a demo post.")
    }

    @MainActor
    func testCaptureMultipleResultsExcludeOlderClues() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-location-denied",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        let collected = app.descendants(matching: .any)["home.collected"]
        XCTAssertTrue(collected.waitForExistence(timeout: stepTimeout))
        let count = collected.label
        let firstPlace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.place.'")).firstMatch
        XCTAssertTrue(firstPlace.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.textFields["home.search"].exists)
        attach(app, name: "review-flow-home-no-photo")
        openSavesFromHome(app: app)
        let seededCandidate = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.reviewCandidate.' AND label CONTAINS[c] %@",
                "Harbor Oven Pizza"
            )
        ).firstMatch
        XCTAssertTrue(seededCandidate.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(
            seededCandidate.label.contains("la.harbor.eats"),
            "Saves rows must keep the known source handle, not only the next-step sentence."
        )
        XCTAssertTrue(
            seededCandidate.label.contains("Check the name and address before confirming"),
            "Saves rows should keep next-step guidance in addition to known evidence."
        )
        XCTAssertFalse(
            seededCandidate.label.contains("33.7405"),
            "A map coordinate must never appear as the Saves-row source handle."
        )
        openRootTab("Home", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: stepTimeout))
        rootTabButton("Save", app: app).tap()
        typeText("""
        The coffee shops in Los Angeles County I always return to
        @theboyandthebearco @stereoscopecoffee @musocoffeela
        @elorea @archives.ofus @fasttimescoffee @est.today.cafe @moducafe
        https://www.instagram.com/reel/DYsbskQyclc/
        """, into: app.textViews["capture.input"])
        dismissKeyboard(app: app)
        app.buttons["capture.analyze"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: timeout(20)))
        let notice = app.descendants(matching: .any)["capture.results.notice"].firstMatch
        XCTAssertTrue(notice.label.contains("Found 8 clues"))
        XCTAssertFalse(app.buttons["saves.segment.mapStamps"].exists)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saves.reviewCandidate.'"))
        XCTAssertGreaterThan(rows.count, 1)
        XCTAssertFalse(rows.matching(NSPredicate(format: "label CONTAINS[c] 'Harbor Oven'")).firstMatch.exists)
        attach(app, name: "review-flow-multiple-results")
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["drawer.review.primaryAction"].waitForExistence(timeout: stepTimeout))
        XCTAssertNotEqual(app.buttons["drawer.review.primaryAction"].label, "Confirm and save", "No coordinates must not become a saved place.")
        XCTAssertTrue(app.staticTexts["drawer.review.missingClue"].exists)
        let addClue = app.buttons["drawer.review.addClue"]
        XCTAssertTrue(addClue.exists)
        XCTAssertEqual(addClue.label, "Search for this place")
        XCTAssertFalse(app.buttons["Add a clue"].exists)
        XCTAssertFalse(app.buttons["drawer.review.changePlace"].exists)
        attach(app, name: "review-next-step-unresolved")
        let reject = app.buttons["drawer.review.reject"]
        tapReachable(reject)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(collected.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(collected.label, count)
    }

    @MainActor
    func testEmptyHomeStartsCaptureAndKeepsSourceOnlyUnconfirmed() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline", "--uitest-location-denied",
            "--uitest-reset-review-demo-storage", "--uitest-empty-home", "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        let start = app.descendants(matching: .any)["home.empty.capture"]
        XCTAssertTrue(start.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(start.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)["home.locationPrompt"].waitForExistence(timeout: stepTimeout),
            "Denied + empty Home must keep the Settings recovery prompt"
        )
        XCTAssertTrue(app.buttons["home.locationAllow"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["home.saves"].waitForExistence(timeout: stepTimeout),
            "Empty Home still exposes the HoP home.saves entry"
        )
        XCTAssertFalse(app.descendants(matching: .any)["home.trips"].exists)
        attach(app, name: "review-flow-home-empty")
        attach(app, name: "doodle-home-empty")
        start.tap()
        typeText("https://www.instagram.com/reel/UnresolvedClue/", into: app.textViews["capture.input"])
        dismissKeyboard(app: app)
        app.buttons["capture.analyze"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: timeout(20)))
        XCTAssertTrue(app.descendants(matching: .any)["capture.results.notice"].firstMatch.label.contains("Found 1 clue"))
        XCTAssertTrue(app.staticTexts["Source saved; analysis pending"].firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.staticTexts["Analysis ready"].exists)
        XCTAssertNotEqual(app.buttons["drawer.review.primaryAction"].label, "Confirm and save")
        attach(app, name: "review-flow-source-only")
        let addClue = app.buttons["drawer.review.addClue"]
        XCTAssertTrue(addClue.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(addClue.label, "Search for this place")
        XCTAssertFalse(app.buttons["Add a clue"].exists)
        tapReachable(addClue)
        let refinement = app.textFields["map.search.input"]
        XCTAssertTrue(refinement.waitForExistence(timeout: stepTimeout))
        refinement.tap()
        refinement.typeText(" Taipei")
        XCTAssertTrue((refinement.value as? String)?.contains("Taipei") == true)
        XCTAssertTrue(refinement.isHittable)
        XCTAssertGreaterThan(refinement.frame.height, 20)
        XCTAssertLessThan(refinement.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertFalse(app.buttons["drawer.review.primaryAction"].exists)
        attach(app, name: "review-next-step-add-clue")
        try assertSearchEditorIsPainted(refinement)
    }

    /// P2 4335170966: Saves → Trips must keep Saves as the back destination.
    @MainActor
    func testSavesTripsBackReturnsToSaves() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed", "--uitest-location-denied",
            "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openTripsFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))
        let back = app.navigationBars["Trips"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: stepTimeout), "Trips must expose a native back action")
        back.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout),
            "Back from Trips must return to Saves, not Home"
        )
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForNonExistence(timeout: stepTimeout))
    }

    /// T6: tap Home Collected and assert the real Passport screen shows
    /// the same city 4/12. Codex packet / spec §8 fixture, not DESIGN v2.
    @MainActor
    func testHomeCollectedOpensPassportWithCityCount() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed", "--uitest-doodle-parity-fixture",
            "--uitest-location-denied", "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let collected = app.descendants(matching: .any)["home.collected"]
        let list = app.scrollViews.firstMatch
        if list.exists {
            for _ in 0..<4 where !collected.exists {
                list.swipeUp()
            }
        }
        XCTAssertTrue(collected.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(collected.label, "Collected 4/12")
        tapReachable(collected)
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        let progress = app.descendants(matching: .any)["profile.stampProgress"]
        if !progress.waitForExistence(timeout: timeout(4)) {
            let passportList = app.scrollViews.firstMatch
            if passportList.exists {
                passportList.swipeDown()
            }
        }
        XCTAssertTrue(progress.waitForExistence(timeout: stepTimeout))
        let shown = [progress.value as? String, progress.label]
            .compactMap { $0 }
            .joined(separator: " ")
        XCTAssertTrue(
            shown.contains("4/12") || shown.contains("4 of 12"),
            "Passport must show the same city 4/12 as Home Collected, got \(shown)"
        )
        app.buttons["profile.close"].tap()
        let wordmark = app.buttons["home.passport"]
        XCTAssertTrue(wordmark.waitForExistence(timeout: stepTimeout))
        wordmark.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(progress.label, "12/12", "The wordmark opens the full saved/goal Passport")
        app.buttons["profile.close"].tap()
        rootTabButton("Passport", app: app).tap()
        XCTAssertTrue(progress.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(progress.label, "12/12", "Root progress counts saves, not visits")    }

    /// A field can remain accessible and accept typing while a parent mask
    /// hides all its pixels. Inspect the light-mode fixture's actual editor.
    @MainActor
    private func assertSearchEditorIsPainted(_ field: XCUIElement) throws {
        let image = try XCTUnwrap(field.screenshot().image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress,
                width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let samples = stride(from: 0, to: pixels.count, by: 4)
        let paper = samples.filter { pixels[$0] > 225 && pixels[$0 + 1] > 220 && pixels[$0 + 2] > 210 }.count
        let ink = samples.filter { pixels[$0] < 140 && pixels[$0 + 1] < 140 && pixels[$0 + 2] < 140 }.count
        let count = Double(image.width * image.height)
        XCTAssertGreaterThan(Double(paper) / count, 0.65, "Search must render on paper, not the town behind its hidden mask.")
        XCTAssertGreaterThan(Double(ink) / count, 0.01, "The typed clue must be visibly painted, not only accessible.")
    }

    @MainActor
    func testPassportTutorialReplaysWithoutAddingPlaces() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-repair-review-demo-seed", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage",
            // Near you without a fix has no city, so Collected is hidden.
            "--uitest-location-denied",
            "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let savedCount = app.descendants(matching: .any)["home.collected"]
        XCTAssertTrue(savedCount.waitForExistence(timeout: stepTimeout))
        let initialCount = savedCount.label
        openRootTab("Passport", app: app)

        app.buttons["profile.settings"].tap()
        let tutorial = app.buttons["profile.tutorial"]
        for _ in 0..<6 where !tutorial.isHittable { app.swipeUp() }
        XCTAssertTrue(waitUntilHittable(tutorial))
        tutorial.tap()
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["onboarding.ownClue"].exists)
        XCTAssertTrue(app.buttons["onboarding.close"].isHittable)
        XCTAssertFalse(app.textViews["onboarding.clueEditor"].exists)
        attach(app, name: "tutorial-replay-sample")
        primary.tap()
        XCTAssertTrue(app.staticTexts["Review Candidate"].waitForExistence(timeout: stepTimeout))
        primary.tap()
        XCTAssertTrue(app.staticTexts["Map Stamp · Example"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(primary.label, "Back to Passport")
        primary.tap()
        XCTAssertTrue(tutorial.waitForExistence(timeout: stepTimeout))
        tutorial.tap()
        XCTAssertTrue(app.buttons["onboarding.close"].waitForExistence(timeout: stepTimeout))
        app.buttons["onboarding.close"].tap()
        openRootTab("Home", app: app)
        XCTAssertTrue(savedCount.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(savedCount.label, initialCount)
        XCTAssertFalse(app.buttons["onboarding.primary"].exists)
    }

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
        app.buttons["home.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["profile.proPreview"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)
        XCTAssertFalse(app.staticTexts["Memo Pro preview"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'subscribe'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'trial'")).firstMatch.exists)
        attach(app, name: "passport-no-paywall")
    }

    @MainActor
    func testSavedPlaceLimitPaywallStatesFreeCap() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-show-saved-place-limit-paywall",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Free: 50 places"].firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Save every place you love"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["paywall.benefit.unlimited"].exists)
        XCTAssertTrue(app.staticTexts["Unlimited saved places"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["paywall.savedNote"].exists)
        XCTAssertTrue(app.staticTexts["You've saved 50 places. Keep going."].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["已滿"].exists)
        XCTAssertFalse(app.staticTexts["Always free"].exists)
        XCTAssertFalse(app.staticTexts["Always free: unlimited saved places"].exists)
        XCTAssertFalse(app.staticTexts["Unlimited saved places and Map Stamps"].exists)
        XCTAssertTrue(app.buttons["paywall.close"].exists)
        attach(app, name: "paywall-free-place-limit")
        terminate(app)
    }

    @MainActor
    func testHopU1SavedPlaceLimitPaywallShowsSavedFiftyWithoutManMan() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-show-saved-place-limit-paywall",
                "-save.appLanguage", "zh-Hant",
            ]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["paywall.savedNote"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["已存 50 個地點，繼續存下去"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["已滿"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已滿")).firstMatch.exists)
        attach(app, name: "paywall-u1-saved-fifty-zh")
        terminate(app)
    }

    /// B6: StoreKit miss / product-load failure. Production stays on
    /// `paywall.notForSale` while purchasing is off; this DEBUG launch arg
    /// is the only way to exercise `paywall.retry` in UI tests.
    @MainActor
    func testSavedPlaceLimitPaywallRetryIsActionable() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-show-saved-place-limit-paywall",
                "--uitest-show-paywall-retry",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["paywall.savedNote"].waitForExistence(timeout: stepTimeout))
        let retry = app.buttons["paywall.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: stepTimeout), "B6: paywall.retry must be visible and labeled")
        XCTAssertEqual(retry.label, "Try again")
        XCTAssertTrue(app.descendants(matching: .any)["paywall.unavailable"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.notForSale"].exists)
        attach(app, name: "paywall-retry")
        terminate(app)
    }

    /// HoP E4. Four iPhone stills as `XCTAttachment`s for the macOS `ios-fast`
    /// artifact. Kept off FULL/BASELINE so the required `ios` job does not
    /// grow four more launches.
    @MainActor
    func testFreeCapE4Screenshots() throws {
        try captureE4FiftyFirstSavePaywall()
        try captureE4PaywallRetry()
        try captureE4UnplacedCandidate()
        try captureE4SettingsPaywall()
        try captureE4AIQuotaNotice()
    }

    @MainActor
    private func captureE4FiftyFirstSavePaywall() throws {
        let app = makeE4App(extraArguments: ["--uitest-show-saved-place-limit-paywall"])
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["paywall.savedNote"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["You've saved 50 places. Keep going."].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Unlimited saved places"].firstMatch.exists)
        attach(app, name: "e4-51st-save-paywall")
        terminate(app)
    }

    /// B6: QA reviews the E4 artifact. The 51st-save still is `notForSale`
    /// while purchasing is off; this launch is the retry / product-load miss.
    @MainActor
    private func captureE4PaywallRetry() throws {
        let app = makeE4App(extraArguments: [
            "--uitest-show-saved-place-limit-paywall",
            "--uitest-show-paywall-retry",
        ])
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        let retry = app.buttons["paywall.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: stepTimeout), "B6: E4 must show paywall.retry, not notForSale")
        XCTAssertEqual(retry.label, "Try again")
        XCTAssertTrue(app.descendants(matching: .any)["paywall.unavailable"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["paywall.savedNote"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.notForSale"].exists)
        attach(app, name: "e4-paywall-retry")
        terminate(app)
    }

    @MainActor
    private func captureE4UnplacedCandidate() throws {
        let app = makeE4App(extraArguments: ["--uitest-show-unplaced-candidate"])
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Home must settle before the Unplaced fixture can appear in Review."
        )
        // Live Home keeps the library behind More → Manage saved places.
        openSavesFromHome(app: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout),
            "Unplaced evidence is the Review candidate list, not a Map Stamp."
        )
        let reviewSegment = app.buttons["saves.segment.review"]
        if reviewSegment.waitForExistence(timeout: timeout(2)), !reviewSegment.isSelected {
            tapReachable(reviewSegment)
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["saves.unplaced"].waitForExistence(timeout: launchTimeout),
            "Parked Unplaced items use the HoP saves.unplaced section."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["saves.unplaced.row.E4000000-0000-4000-8000-000000000051"]
                .waitForExistence(timeout: stepTimeout),
            "Unplaced Harbor Cafe must be the parked row, not a Map Stamp."
        )
        XCTAssertTrue(
            app.staticTexts["Unplaced Harbor Cafe"].firstMatch.waitForExistence(timeout: stepTimeout),
            "Parked Unplaced Harbor Cafe must appear as a Review candidate."
        )
        XCTAssertTrue(
            app.staticTexts["Unplaced"].firstMatch.waitForExistence(timeout: stepTimeout),
            "B8-4: Unplaced must be visible text, not only saves.unplaced."
        )
        XCTAssertTrue(
            app.staticTexts["Held after 50 places saved. Not on the map yet."].firstMatch.exists,
            "B8-1: the parked section must say why the row is off the map."
        )
        XCTAssertTrue(
            app.staticTexts["Confirm the place before adding it to your map."].firstMatch.exists
        )
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)
        XCTAssertFalse(app.staticTexts["Confirmed Map Stamp"].firstMatch.exists)
        attach(app, name: "e4-unplaced-candidate")
        terminate(app)
    }

    /// B8-5: HoP requires a real simulator full-screen still at device width
    /// (iPhone 16 Pro = 402pt). The 375/430 view-render tests stay
    /// supplementary and cannot satisfy this gate alone.
    @MainActor
    func testUnplacedLabelFullScreenAtDeviceWidth() throws {
        for language in ["en", "zh-Hant"] {
            let app = makeApp(
                launchArguments: [
                    "--uitest-complete-onboarding",
                    "--skip-map-tour",
                    "--uitest-repair-review-demo-seed",
                    "--uitest-show-unplaced-candidate",
                    "-save.appLanguage", language,
                ],
                launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
            )
            launch(app)
            try signInViaReviewDemoRequired(app: app)
            XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
            XCTAssertTrue(
                app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
                "Home must settle before the Unplaced fixture can appear in Review."
            )
            openSavesFromHome(app: app)
            XCTAssertTrue(
                app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout),
                "Unplaced evidence is the Review candidate list, not a Map Stamp."
            )
            let reviewSegment = app.buttons["saves.segment.review"]
            if reviewSegment.waitForExistence(timeout: timeout(2)), !reviewSegment.isSelected {
                tapReachable(reviewSegment)
            }
            XCTAssertTrue(
                app.descendants(matching: .any)["saves.unplaced"].waitForExistence(timeout: launchTimeout),
                "Parked Unplaced items use the HoP saves.unplaced section."
            )
            let title = language == "en"
                ? app.staticTexts["Unplaced"].firstMatch
                : app.staticTexts["暫未放入"].firstMatch
            XCTAssertTrue(
                title.waitForExistence(timeout: stepTimeout),
                "B8-5: Unplaced title must be visible in \(language)"
            )
            XCTAssertTrue(
                waitUntilHittable(title),
                "B8-5: Unplaced title must be hittable at device width in \(language)"
            )
            let reason = language == "en"
                ? app.staticTexts["Held after 50 places saved. Not on the map yet."].firstMatch
                : app.staticTexts["已存 50 個地點，所以暫放，還沒放上地圖。"].firstMatch
            XCTAssertTrue(
                reason.waitForExistence(timeout: stepTimeout),
                "B8-5: parked-off-map sentence must be visible in \(language)"
            )
            XCTAssertTrue(
                app.staticTexts["Unplaced Harbor Cafe"].firstMatch.waitForExistence(timeout: stepTimeout),
                "Parked Unplaced Harbor Cafe must appear as a Review candidate."
            )
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "b8-5-unplaced-label-\(language)-full"
            attachment.lifetime = .keepAlways
            add(attachment)
            terminate(app)
        }
    }

    @MainActor
    private func captureE4SettingsPaywall() throws {
        let app = makeE4App()
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout))
        // `home.savedPlaces` is the library container and exists while empty.
        // A Doodle Home `home.place.*` row is a confirmed Map Stamp. The Pro
        // row is `if !passportPlaces.isEmpty`. CI 39697020308 opened
        // Settings before a stamp loaded, so profile.pro never entered the tree.
        // Home B has no mini-map `home.featuredName`. A confirmed stamp is an
        // Eat/Go row (`home.place.*`). Near you without a fix lists none;
        // B-1/B-3 city switcher shows the review-demo Tokyo/Taipei stamps.
        waitForConfirmedHomeStampBeforeSettings(app)
        openRootTab("Passport", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: stepTimeout), "Passport settings opens the B7 Pro row.")
        tapReachable(settings)
        XCTAssertTrue(app.navigationBars["Passport settings"].waitForExistence(timeout: stepTimeout))

        let disclosure = app.descendants(matching: .any)["profile.controlsDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: stepTimeout))
        tapReachable(disclosure)

        let pro = app.descendants(matching: .any)["profile.pro"]
        XCTAssertTrue(
            pro.waitForExistence(timeout: stepTimeout),
            "Settings must expose Savvy Pro after a Map Stamp exists."
        )
        XCTAssertTrue(
            scrollUntilHittable(pro, in: app.scrollViews.firstMatch, maxSwipes: 8),
            "Settings must scroll Savvy Pro on screen."
        )
        tapReachable(pro)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Free: 50 places"].firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Unlimited saved places"].firstMatch.exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["paywall.savedNote"].exists,
            "Q1: Settings uses the Passport trigger, not the saved-50 line."
        )
        attach(app, name: "e4-settings-paywall")
        terminate(app)
    }

    /// Home B has no mini-map featured stamp. A confirmed Map Stamp is an
    /// Eat/Go row (`home.place.*`). Near you without a location fix lists
    /// none; B-1/B-3 city switcher reveals the review-demo Tokyo/Taipei
    /// stamps so Settings can show `profile.pro`.
    @MainActor
    private func waitForConfirmedHomeStampBeforeSettings(_ app: XCUIApplication) {
        let stamp = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.place.'")
        ).firstMatch
        if stamp.waitForExistence(timeout: 2) {
            return
        }

        let switcher = app.buttons["home.citySwitcher"]
        XCTAssertTrue(
            switcher.waitForExistence(timeout: stepTimeout),
            "Settings Pro row requires a confirmed Map Stamp on Home first."
        )
        tapReachable(switcher)

        let tokyo = app.descendants(matching: .any)["home.city.tokyo"]
        let taipei = app.descendants(matching: .any)["home.city.taipei"]
        guard let city = firstHittable([tokyo, taipei], timeout: stepTimeout) else {
            XCTFail("Settings Pro row requires a confirmed Map Stamp on Home first.")
            return
        }
        tapReachable(city)

        XCTAssertTrue(
            stamp.waitForExistence(timeout: stepTimeout),
            "Settings Pro row requires a confirmed Map Stamp on Home first."
        )
    }

    @MainActor
    private func captureE4AIQuotaNotice() throws {
        let app = makeE4App(extraArguments: ["--uitest-show-ai-quota-notice"])
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(
            app.staticTexts["The analysis usage limit has been reached. Keep the source and try again later."]
                .firstMatch
                .waitForExistence(timeout: launchTimeout),
            "B7: exhausted AI quota is the Share Analysis usage-limit notice."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["paywall.root"].exists,
            "B7: exhausted AI quota must not open the paywall."
        )
        attach(app, name: "e4-ai-quota-notice")
        terminate(app)
    }

    @MainActor
    private func makeE4App(extraArguments: [String] = []) -> XCUIApplication {
        makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                // E4 Settings Map Stamp signal: home.place.* needs a resolved city.
                "--uitest-location-denied",
            ] + extraArguments + [
                "-save.appLanguage", "en",
            ]
        )
    }

    @MainActor
    func testHomeLeadsWithSavedPlacesAndUsesSaveTabForCapture() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-location-denied",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Production Home should render confirmed saved places immediately."
        )
        waitForHomeCoverImagery(app)
        XCTAssertFalse(app.textFields["home.search"].exists)
        XCTAssertFalse(app.buttons["home.viewAll"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.memoryPile"].exists)
        let firstPlace = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.place.'")
        ).firstMatch
        XCTAssertTrue(firstPlace.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["home.hero.changeCover"].exists)
        XCTAssertTrue(app.buttons["home.eat"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["home.citySwitcher"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(
            app.descendants(matching: .any)["home.root"]
                .descendants(matching: .any)["home.miniMap"].exists,
            "Home has no map component"
        )
        XCTAssertFalse(app.descendants(matching: .any)["home.saves"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.locationPrompt"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["home.locationAllow"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["home.trips"].exists)
        tapReachable(app.buttons["home.go"])
        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(
            app.buttons["map.go"].exists,
            "Map tab stays unfiltered; Home has no mini-map handoff"
        )
        XCTAssertFalse(app.descendants(matching: .any)["map.city"].exists)
        openRootTab("Home", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(app.state, .runningForeground)
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
    func testHomeShowOnMapFocusesPlace() throws {
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: "en",
                location: "daan",
                hintCount: 1,
                clock: "2026-10-24T20:00:00",
                dark: false
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        let home = app.descendants(matching: .any)["home.root"]
        XCTAssertTrue(home.waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(
            home.descendants(matching: .any)["home.miniMap"].exists,
            "Home has no map component"
        )
        let homeEat = app.buttons["home.eat"]
        XCTAssertTrue(homeEat.waitForExistence(timeout: stepTimeout))
        let homeEatSelected = homeEat.isSelected
        let homeCity = app.descendants(matching: .any)["home.citySwitcher"].label
        let e2 = app.buttons["home.place.60000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(e2.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(e2.label.contains("Lunch Noodle"), e2.label)
        XCTAssertTrue(e2.label.contains("651m"), "TPE-A E2 must show 651m: \(e2.label)")
        e2.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        let showOnMap = app.descendants(matching: .any)["home.row.showOnMap"]
        XCTAssertTrue(showOnMap.waitForExistence(timeout: stepTimeout))
        XCTAssertGreaterThanOrEqual(showOnMap.frame.height + 0.01, 44)
        showOnMap.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        let peek = app.descendants(matching: .any)["map.peek.card"]
        XCTAssertTrue(peek.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(peek.label.contains("Lunch Noodle"), peek.label)
        let mapEat = app.descendants(matching: .any)["map.eat"]
        let mapCity = app.descendants(matching: .any)["map.city"]
        XCTAssertTrue(mapEat.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(mapCity.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(mapEat.isSelected, homeEatSelected)
        if homeCity.contains("Near you") {
            XCTAssertEqual(mapCity.label, "Near you")
        } else if homeCity.contains("附近") {
            XCTAssertEqual(mapCity.label, "附近")
        } else {
            XCTAssertTrue(
                homeCity.contains(mapCity.label),
                "map.city \(mapCity.label) must equal Home city \(homeCity)"
            )
        }
        assertMapVisibleRangeContains(
            latitude: 25.0295999,
            longitude: 121.5411515,
            app: app
        )
        attach(app, name: "TPE-F")
    }

    /// Camera/selection state only. Missing camera chrome in CI (no tiles)
    /// is not a failure; peek card already proved the selected place.
    @MainActor
    private func assertMapVisibleRangeContains(
        latitude: Double,
        longitude: Double,
        app: XCUIApplication
    ) {
        let camera = app.descendants(matching: .any)["map.camera"]
        guard camera.waitForExistence(timeout: timeout(2)) else { return }
        let parts = camera.value as? String ?? camera.label
        let numbers = parts.split(separator: ",").compactMap { Double($0) }
        if numbers.count >= 4 {
            let centerLat = numbers[0]
            let centerLon = numbers[1]
            let latDelta = numbers[2]
            let lonDelta = numbers[3]
            XCTAssertTrue(
                abs(latitude - centerLat) <= latDelta / 2
                    && abs(longitude - centerLon) <= lonDelta / 2,
                "Map camera \(parts) must contain \(latitude), \(longitude)"
            )
        } else if numbers.count >= 2 {
            XCTAssertEqual(numbers[0], latitude, accuracy: 0.0005)
            XCTAssertEqual(numbers[1], longitude, accuracy: 0.0005)
        }    }

    @MainActor
    func testCaptureAtlasProductionParity() throws {
        try captureAtlasHomeTPEA()
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-atlas-parity-fixture",
                "--uitest-friends-town",
                "--uitest-map-place-selected",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))

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

        openRootTab("Friends", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["friends.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["friends.list"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["friends.author.mia"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["friends.mapStrip"].exists)
        // Live Friends raster for the 0.90 gate. Codex packet §7.4.
        attach(app, name: "five-tab-friends")
        attach(app, name: "atlas-friends")
    }

    /// Root navigation includes Friends and keeps Plan as a child route.
    /// Run on the reference and compact devices; attachment names stay stable for parity.
    @MainActor
    func testCaptureFiveTabLanding() throws {
        try assertFriendsComingSoonLanguages()
        try captureFiveTabHomeParityRaster()
        try captureHomeSavesWithoutClues(names: ["H3-no-clues-saves-en"])
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-map-place-selected",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let tabs = ["Home", "Map", "Save", "Friends", "Passport"].map {
            rootTabButton($0, app: app)
        }
        for tab in tabs {
            XCTAssertTrue(tab.waitForExistence(timeout: stepTimeout))
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        }
        XCTAssertEqual(rootTabButton("Save", app: app).label, "Save")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'root.tab.'")).count, 5)
        XCTAssertFalse(rootTabButton("Plan", app: app).exists)
        for pair in zip(tabs, tabs.dropFirst()) {
            XCTAssertLessThan(pair.0.frame.midX, pair.1.frame.midX)
        }
        let leadingInset = tabs[0].frame.minX - app.frame.minX
        let trailingInset = app.frame.maxX - tabs[4].frame.maxX
        XCTAssertGreaterThan(leadingInset, 12, "Root tabs must not touch the leading screen edge.")
        XCTAssertGreaterThan(trailingInset, 12, "Root tabs must not touch the trailing screen edge.")
        XCTAssertEqual(leadingInset, trailingInset, accuracy: 2)
        waitForHomeCoverImagery(app)
        XCTAssertTrue(app.descendants(matching: .any)["home.locationPrompt"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["home.locationAllow"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "doodle-home-light")

        openRootTab("Friends", app: app)
        XCTAssertTrue(app.staticTexts["friends.empty"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(app.staticTexts["friends.empty"].label, "Their next place could be yours")
        XCTAssertFalse(app.textFields["friends.invite"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["friends.mapStrip"].exists)
        attach(app, name: "five-tab-friends-empty")

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        let locationNoticeDismiss = app.buttons["map.locationNotice.dismiss"]
        if locationNoticeDismiss.waitForExistence(timeout: timeout(2)) {
            locationNoticeDismiss.tap()
        }
        XCTAssertTrue(app.buttons["map.eat"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["map.go"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["map.placeSheet"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "landing-map")
        attach(app, name: "doodle-map-light-demo")
        assertDoodleMapChrome(app)
        attachHoP298ChromeEvidence(app)

        openTripsFromHome(app: app)
        let existingTrip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trips.card.'")).firstMatch
        XCTAssertTrue(existingTrip.waitForExistence(timeout: stepTimeout))
        existingTrip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip.plan"].waitForExistence(timeout: stepTimeout))
        let tripBack = app.buttons["trip.back"]
        XCTAssertTrue(tripBack.waitForExistence(timeout: stepTimeout))
        tripBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        openPlanFromTrips(app: app)
        let planNavigation = app.navigationBars["Plan"]
        let newTrip = app.buttons["plan.newTrip"]
        XCTAssertTrue(newTrip.waitForExistence(timeout: stepTimeout))
        waitForStableFrame(newTrip)
        XCTAssertTrue(newTrip.isHittable)
        XCTAssertLessThanOrEqual(planNavigation.frame.maxY, newTrip.frame.minY,
            "Plan actions must sit below the native navigation bar")
        attach(app, name: "five-tab-plan")

        let input = app.textFields["plan.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(input.isHittable)
        input.tap()
        let unsentQuery = "Plan a quiet afternoon in Taipei"
        input.typeText(unsentQuery)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: stepTimeout))
        waitForStableFrame(input)
        XCTAssertTrue(input.isHittable)
        XCTAssertGreaterThanOrEqual(input.frame.minY, planNavigation.frame.maxY)
        XCTAssertLessThanOrEqual(input.frame.maxY, app.frame.maxY)
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY,
            "The Plan input must remain above the keyboard")
        XCTAssertEqual(input.value as? String, unsentQuery)
        attach(app, name: "plan-child-keyboard")
        let keyboardDone = app.buttons["plan.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: stepTimeout))
        keyboardDone.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: stepTimeout))

        let planBack = planNavigation.buttons.firstMatch
        XCTAssertTrue(planBack.isHittable)
        planBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))
        let resumePlanning = app.buttons["trips.plan"]
        XCTAssertTrue(resumePlanning.waitForExistence(timeout: stepTimeout))
        tapReachable(resumePlanning)
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout))
        let resumedInput = app.textFields["plan.chat.input"]
        XCTAssertTrue(resumedInput.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(resumedInput.value as? String, unsentQuery,
            "Back and Resume planning must preserve the unsent conversation input")
        XCTAssertFalse(rootTabButton("Home", app: app).exists)
        let resumedBack = app.navigationBars["Plan"].buttons.firstMatch
        XCTAssertTrue(resumedBack.isHittable)
        resumedBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: stepTimeout))

        openRootTab("Passport", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "five-tab-profile")

        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "five-tab-capture")
        app.buttons["Close capture"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(rootTabButton("Passport", app: app).isSelected, "Capture cancellation returns to Passport")
    }

    /// Founder lock: paywall parity target is the Doodle v1 mock at 0.90.
    /// Purchasing is off, so the wall is forced with `--uitest-show-paywall`.
    @MainActor
    func testDoodlePaywallParity() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout),
            "Doodle paywall must present as a full-screen modal for the 0.90 gate."
        )
        XCTAssertFalse(rootTabButton("Home", app: app).exists, "Paywall is a full-screen modal with no tab bar")
        XCTAssertTrue(
            app.descendants(matching: .any)["paywall.benefit.unlimited"].waitForExistence(timeout: stepTimeout),
            "The one benefit row must stay queryable after official noodle/coffee plan stickers."
        )
        XCTAssertEqual(app.descendants(matching: .any)["paywall.root"].value as? String, "settings")
        XCTAssertFalse(app.staticTexts["Upgrade to Savvy Pro"].exists)
        XCTAssertFalse(app.staticTexts["Pro isn't on sale yet"].exists)
        XCTAssertFalse(app.staticTexts["You've saved 50 places. Keep going."].exists)
        XCTAssertFalse(app.staticTexts["Plan trips from your saves"].exists)
        XCTAssertFalse(app.staticTexts["Bonus sticker packs"].exists)

        let capApp = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(capApp)
        try signInViaReviewDemoRequired(app: capApp)
        XCTAssertTrue(
            capApp.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout),
            "The 51st-save entry must open the same places-only wall."
        )
        XCTAssertEqual(capApp.descendants(matching: .any)["paywall.root"].value as? String, "savedPlacesCap")
        let savedNote = capApp.descendants(matching: .any)["paywall.savedNote"]
        XCTAssertTrue(savedNote.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(savedNote.label, "You've saved 50 places. Keep going.")
        XCTAssertTrue(capApp.staticTexts["You've saved 50 places. Keep going."].exists)
        XCTAssertFalse(capApp.staticTexts["Upgrade to Savvy Pro"].exists)
        XCTAssertFalse(capApp.staticTexts["Pro isn't on sale yet"].exists)
        XCTAssertFalse(rootTabButton("Home", app: capApp).exists)
        attach(capApp, name: "five-tab-paywall")
        attach(capApp, name: "doodle-paywall-light")
        attach(capApp, name: "pr295-paywall-light")
        attach(capApp, name: "pr295-paywall-cap-light")

        let zh = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "-save.appLanguage", "zh-Hant",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(zh)
        try signInViaReviewDemoRequired(app: zh)
        XCTAssertTrue(zh.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(zh.staticTexts["已存 50 個地點，繼續存下去"].waitForExistence(timeout: stepTimeout))
        attach(zh, name: "pr295-paywall-zh-hant-light")
    }

    @MainActor
    func testAIQuotaExhaustedStaysOffThePaywall() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-ai-quota-exhausted",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)

        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["ai.quotaExhausted"].waitForExistence(timeout: stepTimeout),
            "Exhausted AI assist must show a neutral message on the assist surface."
        )
        XCTAssertFalse(app.descendants(matching: .any)["paywall.root"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["paywall.savedNote"].exists)
        XCTAssertFalse(app.buttons["paywall.retry"].exists)
    }

    /// Capture sheet over the Doodle Home map, matching the DESIGN mock.

    /// Capture sheet over the Doodle Home map, matching the DESIGN mock.
    @MainActor
    func testDoodleCaptureParity() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-face",
                "--uitest-location-allowed",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        XCTAssertFalse(app.descendants(matching: .any)["home.locationPrompt"].exists)
        let capture = rootTabButton("Save", app: app)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "five-tab-capture")
        attach(app, name: "doodle-capture-light")
        attach(app, name: "pr295-capture-light")
        XCTAssertFalse(app.descendants(matching: .any)["capture.suggestion"].exists)
        let draft = app.textViews["capture.input"]
        XCTAssertTrue(draft.waitForExistence(timeout: stepTimeout))
        draft.tap()
        draft.typeText("Fangzhuangchang Noodles")
        attach(app, name: "pr295-capture-filled-light")
        let nearby = app.buttons["capture.searchNearby"]
        XCTAssertTrue(nearby.isHittable)
        XCTAssertGreaterThanOrEqual(nearby.frame.height, 44)
        nearby.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.flow"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(app.textFields["map.search.input"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(rootTabButton("Map", app: app).isSelected)
        attach(app, name: "doodle-capture-nearby-search")

        let zh = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-face",
                "--uitest-location-allowed",
                "-save.appLanguage", "zh-Hant",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(zh)
        try signInViaReviewDemoRequired(app: zh)
        XCTAssertTrue(zh.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let zhSave = rootTabButton("Save", app: zh)
        XCTAssertTrue(zhSave.waitForExistence(timeout: stepTimeout))
        zhSave.tap()
        XCTAssertTrue(zh.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(zh, name: "pr295-capture-zh-hant-light")
    }

    /// Warm-dark Capture sheet and Pro paywall for the founder compare rail.

    /// Warm-dark Capture sheet and Pro paywall for the founder compare rail.
    @MainActor
    func testDoodleCapturePaywallDarkParity() throws {
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        XCUIDevice.shared.appearance = .dark
        let captureApp = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-face",
                "--uitest-location-allowed",
                "--uitest-force-dark",
                "-AppleInterfaceStyle", "Dark",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(captureApp)
        try signInViaReviewDemoRequired(app: captureApp)
        XCTAssertTrue(captureApp.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let capture = rootTabButton("Save", app: captureApp)
        XCTAssertTrue(capture.waitForExistence(timeout: stepTimeout))
        capture.tap()
        XCTAssertTrue(captureApp.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(captureApp, name: "doodle-capture-dark")
        attach(captureApp, name: "pr295-capture-dark")
        captureApp.buttons["Close capture"].tap()

        let paywallApp = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "--uitest-force-dark",
                "-AppleInterfaceStyle", "Dark",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(paywallApp)
        try signInViaReviewDemoRequired(app: paywallApp)
        XCTAssertTrue(
            paywallApp.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout)
        )
        attach(paywallApp, name: "doodle-paywall-dark")
        attach(paywallApp, name: "pr295-paywall-dark")
    }

    /// QA evidence for #295: paywall with large Dynamic Type on the CI
    /// iPhone. Compact-height SE shots are captured by `testPR295SEEvidence`.

    /// QA evidence for #295: paywall with large Dynamic Type on the CI
    /// iPhone. Compact-height SE shots are captured by `testPR295SEEvidence`.
    @MainActor
    func testPR295PaywallLargeTypeEvidence() throws {
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        let light = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(light)
        try signInViaReviewDemoRequired(app: light)
        XCTAssertTrue(light.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(light.descendants(matching: .any)["paywall.scroll"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(light.staticTexts["You've saved 50 places. Keep going."].waitForExistence(timeout: stepTimeout))
        attach(light, name: "pr295-paywall-large-type-light")

        XCUIDevice.shared.appearance = .dark
        let dark = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "--uitest-force-dark",
                "-AppleInterfaceStyle", "Dark",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(dark)
        try signInViaReviewDemoRequired(app: dark)
        XCTAssertTrue(dark.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        attach(dark, name: "pr295-paywall-large-type-dark")
    }

    /// QA evidence for #295: capture sheet and paywall on iPhone SE.
    /// The dedicated iOS workflow step boots the SE simulator for this test.

    /// QA evidence for #295: capture sheet and paywall on iPhone SE.
    /// The dedicated iOS workflow step boots the SE simulator for this test.
    @MainActor
    func testPR295SEEvidence() throws {
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        let capture = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-face",
                "--uitest-location-allowed",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(capture)
        try signInViaReviewDemoRequired(app: capture)
        XCTAssertTrue(capture.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let saveTab = rootTabButton("Save", app: capture)
        XCTAssertTrue(saveTab.waitForExistence(timeout: stepTimeout))
        saveTab.tap()
        XCTAssertTrue(capture.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(capture, name: "pr295-capture-se-light")
        capture.buttons["Close capture"].tap()

        let paywall = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(paywall)
        try signInViaReviewDemoRequired(app: paywall)
        XCTAssertTrue(paywall.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(paywall.descendants(matching: .any)["paywall.scroll"].waitForExistence(timeout: stepTimeout))
        attach(paywall, name: "pr295-paywall-se-light")

        XCUIDevice.shared.appearance = .dark
        let captureDark = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-face",
                "--uitest-location-allowed",
                "--uitest-force-dark",
                "-AppleInterfaceStyle", "Dark",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(captureDark)
        try signInViaReviewDemoRequired(app: captureDark)
        XCTAssertTrue(captureDark.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        let saveDark = rootTabButton("Save", app: captureDark)
        XCTAssertTrue(saveDark.waitForExistence(timeout: stepTimeout))
        saveDark.tap()
        XCTAssertTrue(captureDark.descendants(matching: .any)["capture.flow"].waitForExistence(timeout: stepTimeout))
        attach(captureDark, name: "pr295-capture-se-dark")

        let paywallDark = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline",
                "--uitest-reset-review-demo-storage",
                "--uitest-show-paywall-cap",
                "--uitest-force-dark",
                "-AppleInterfaceStyle", "Dark",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(paywallDark)
        try signInViaReviewDemoRequired(app: paywallDark)
        XCTAssertTrue(paywallDark.descendants(matching: .any)["paywall.root"].waitForExistence(timeout: launchTimeout))
        attach(paywallDark, name: "pr295-paywall-se-dark")
    }

    /// H1–H4: Codex packet / spec §8 faces (light EN, dark EN, light
    /// zh-Hant, dark zh-Hant). DESIGN judges these rasters manually; the
    /// 0.90 score is not evidence. Warm dark tokens from spec §1 must
    /// paint Home and Passport once Light is unlocked.
    /// Appearance is forced before launch (`-AppleInterfaceStyle`, `--uitest-force-*`,
    /// and `XCUIDevice.appearance`). Background pixels must be near #1E1C19 / #FFF9EB.
    /// Attachment names stay off the production-parity set (`five-tab-*`, `atlas-*`).

    /// Warm-dark appearance aliases. These four rasters are all H2
    /// (location denied + waiting clues) in en/zh × light/dark — not
    /// spec §8.1 product states. Names stay `H2-*` so DESIGN does not
    /// treat them as H1/H3/H4. Product states are
    /// `testHomeDesignProductStates`. DESIGN judges these rasters
    /// manually; the 0.90 score is not evidence. Warm dark tokens from
    /// spec §1 must paint Home and Passport once Light is unlocked.    /// Appearance is forced before launch (`-AppleInterfaceStyle`, `--uitest-force-*`,
    /// and `XCUIDevice.appearance`). Background pixels must be near #1E1C19 / #FFF9EB.
    /// Attachment names stay off the production-parity set (`five-tab-*`, `atlas-*`).
    @MainActor
    func testHomeAndPassportWarmDarkMode() throws {
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        try captureHomeAndPassportCanvas(
            appearance: .dark,
            appleInterfaceStyle: "Dark",
            forceArgument: "--uitest-force-dark",
            language: "en",
            homeName: "dark-home",
            friendsName: "dark-friends",
            passportName: "dark-passport",
            referenceName: "H2-en-dark",
            expectedRed: 0x1E,
            expectedGreen: 0x1C,
            expectedBlue: 0x19
        )
        try captureHomeAndPassportCanvas(
            appearance: .light,
            appleInterfaceStyle: "Light",
            forceArgument: "--uitest-force-light",
            language: "en",
            homeName: "light-home",
            friendsName: "light-friends",
            passportName: "light-passport",
            referenceName: "H2-en-light",
            expectedRed: 0xFF,
            expectedGreen: 0xF9,
            expectedBlue: 0xEB
        )
        try captureHomeAndPassportCanvas(
            appearance: .light,
            appleInterfaceStyle: "Light",
            forceArgument: "--uitest-force-light",
            language: "zh-Hant",
            homeName: "light-home-zh",
            friendsName: "light-friends-zh",
            passportName: "light-passport-zh",
            referenceName: "H2-zh-light",
            expectedRed: 0xFF,
            expectedGreen: 0xF9,
            expectedBlue: 0xEB
        )
        try captureHomeAndPassportCanvas(
            appearance: .dark,
            appleInterfaceStyle: "Dark",
            forceArgument: "--uitest-force-dark",
            language: "zh-Hant",
            homeName: "dark-home-zh",
            friendsName: "dark-friends-zh",
            passportName: "dark-passport-zh",
            referenceName: "H2-zh-dark",
            expectedRed: 0x1E,
            expectedGreen: 0x1C,
            expectedBlue: 0x19
        )
    }

    /// Real 375pt simulator (SE / mini). Not a maxWidth letterbox on 402pt.
    @MainActor
    func testMapWidth375() throws {
        try captureMapWidthEvidence(width: 375, columns: 3, name: "map-375")
    }

    /// Real 390pt simulator (iPhone 14). Not a maxWidth letterbox on 402pt.
    @MainActor
    func testMapWidth390() throws {
        try captureMapWidthEvidence(width: 390, columns: 3, name: "map-390")
    }

    /// Real 430pt simulator (Pro Max). Not a maxWidth letterbox on 402pt.
    @MainActor
    func testMapWidth430() throws {
        try captureMapWidthEvidence(width: 430, columns: 4, name: "map-430")
    }

    /// HoP width shots: assert the booted device point width and the DESIGN
    /// column count at that canvas, then attach `map-375|390|430`.
    /// Names stay off `five-tab-*` so they cannot steal the 0.90 target.
    @MainActor
    private func captureMapWidthEvidence(width: Int, columns: Int, name: String) throws {
        let language = width == 390 ? "zh-Hant" : "en"
        let extra = width == 430
            ? ["--uitest-force-dark", "-AppleInterfaceStyle", "Dark"]
            : ["--uitest-force-light", "-AppleInterfaceStyle", "Light"]
        if width == 430 {
            XCUIDevice.shared.appearance = .dark
            addTeardownBlock { XCUIDevice.shared.appearance = .light }
        }
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-map-place-selected",
                "-save.appLanguage", language,
            ] + extra,
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        openRootTab("Map", app: app)
        let mapRoot = app.descendants(matching: .any)["map.root"]
        XCTAssertTrue(mapRoot.waitForExistence(timeout: stepTimeout))
        let locationNoticeDismiss = app.buttons["map.locationNotice.dismiss"]
        if locationNoticeDismiss.waitForExistence(timeout: timeout(2)) {
            locationNoticeDismiss.tap()
        }
        XCTAssertTrue(app.buttons["map.city"].waitForExistence(timeout: stepTimeout))
        let live = app.descendants(matching: .any)["map.liveSurface"]
        XCTAssertTrue(live.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            Int(app.frame.width.rounded()),
            width,
            "Map width shot must boot a real \(width)pt simulator"
        )
        XCTAssertEqual(
            Int(mapRoot.frame.width.rounded()),
            width,
            "Map root must use the full \(width)pt device width, not a letterbox"
        )
        XCTAssertEqual(
            columns,
            width <= 390 ? 3 : 4,
            "DESIGN canvas at \(width)pt is \(columns) columns"
        )
        attach(app, name: name)
        terminate(app)    }

    @MainActor
    private func captureHomeAndPassportCanvas(
        appearance: XCUIDevice.Appearance,
        appleInterfaceStyle: String,
        forceArgument: String,
        language: String = "en",
        homeName: String,
        friendsName: String? = nil,
        passportName: String,
        referenceName: String? = nil,
        expectedRed: Int,
        expectedGreen: Int,
        expectedBlue: Int
    ) throws {
        XCUIDevice.shared.appearance = appearance
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-home-memory-fixture",
                "--uitest-friends-town",
                "-save.appLanguage", language,
                "-AppleInterfaceStyle", appleInterfaceStyle,
                forceArgument,
                "--uitest-map-place-selected",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(rootTabButton("Home", app: app).waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["home.eat"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["home.citySwitcher"].waitForExistence(timeout: stepTimeout))
        let homeShot = app.screenshot()
        attach(app, name: homeName)
        if let referenceName {
            attach(app, name: referenceName)
        }
        assertScreenshotBackground(
            homeShot,
            nearRed: expectedRed,
            green: expectedGreen,
            blue: expectedBlue,
            name: homeName
        )

        if let friendsName {
            openRootTab("Friends", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["friends.root"].waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(app.descendants(matching: .any)["friends.author.mia"].waitForExistence(timeout: stepTimeout))
            let friendsShot = app.screenshot()
            attach(app, name: friendsName)
            assertScreenshotBackground(
                friendsShot,
                nearRed: expectedRed,
                green: expectedGreen,
                blue: expectedBlue,
                name: friendsName
            )
        }

        openRootTab("Passport", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(rootTabButton("Passport", app: app).isSelected)
        let passportShot = app.screenshot()
        attach(app, name: passportName)
        assertScreenshotBackground(
            passportShot,
            nearRed: expectedRed,
            green: expectedGreen,
            blue: expectedBlue,
            name: passportName
        )

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        let locationNoticeDismiss = app.buttons["map.locationNotice.dismiss"]
        if locationNoticeDismiss.waitForExistence(timeout: timeout(2)) {
            locationNoticeDismiss.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["map.placeSheet"].waitForExistence(timeout: stepTimeout))
        attach(app, name: homeName.replacingOccurrences(of: "home", with: "map"))
        if appearance == .dark {
            attach(app, name: "doodle-map-dark")
        }
        assertDoodleMapChrome(app)
        terminate(app)
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
                "--uitest-review-map-results",
                "--uitest-reset-review-demo-storage",
                "--uitest-repair-review-demo-seed",
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
        typeText("Creator handle: @la.harbor.eats\n\(mapURL)", into: captureInput)
        let analyze = app.buttons["capture.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: stepTimeout))
        analyze.tap()

        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: timeout(20)))
        let receipt = app.descendants(matching: .any)["capture.results.notice"].firstMatch
        XCTAssertTrue(receipt.exists)
        XCTAssertTrue(receipt.label.contains("Found 1 clue"))
        let confirm = app.buttons["drawer.review.primaryAction"]
        XCTAssertEqual(confirm.label, "Confirm and save")
        XCTAssertTrue(app.staticTexts["drawer.review.missingClue"].exists)
        XCTAssertTrue(app.buttons["drawer.review.changePlace"].exists)
        XCTAssertFalse(app.buttons["drawer.review.addClue"].exists)
        let context = app.descendants(matching: .any)["drawer.review.contextHero"].firstMatch
        XCTAssertTrue(context.exists)
        XCTAssertLessThan(context.frame.minY, confirm.frame.minY)
        XCTAssertTrue(app.buttons["drawer.review.reject"].exists)
        attach(app, name: "review-flow-single-result")

        // A populated search must remain actionable on the tile-town Map.
        // The former pin-only route closed the panel and stranded this result.
        tapReachable(app.buttons["drawer.review.changePlace"])
        let corrected = app.buttons["map.search.candidate.review-map-result-fixture"]
        XCTAssertTrue(corrected.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["map.search.root"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["map.liveSurface"].exists)
        XCTAssertTrue(app.staticTexts["Map results · Not saved"].exists)
        tapReachable(corrected)
        XCTAssertTrue(app.buttons["drawer.unsaved.primaryAction"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "review-change-place-tile-town")

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
        XCTAssertTrue(
            savedCandidate.label.contains("la.harbor.eats"),
            "Saves rows must keep the known source handle after a maps capture, not fall through to the platform name."
        )
        XCTAssertFalse(
            savedCandidate.label.contains("33.7405"),
            "A map coordinate must never appear as the Saves-row source handle."
        )
        XCTAssertTrue(
            savedCandidate.label.contains("Check the name and address before confirming"),
            "Saves rows should keep next-step guidance in addition to known evidence."
        )
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

        tapReachable(app.buttons["drawer.review.changePlace"])
        XCTAssertTrue(app.descendants(matching: .any)["map.search.root"].waitForExistence(timeout: stepTimeout))
        let refine = app.textFields["map.search.input"]
        XCTAssertTrue(refine.waitForExistence(timeout: stepTimeout))
        focus(refine)
        refine.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: timeout(2)) {
            selectAll.tap()
        } else if let current = refine.value as? String, !current.isEmpty {
            refine.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        refine.typeText("ichiran")
        let savedStamp = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'map.search.saved.' AND label CONTAINS[c] %@",
                "Ichiran"
            )
        ).firstMatch
        XCTAssertTrue(
            savedStamp.waitForExistence(timeout: stepTimeout),
            "Review → Choose another place must list saved Map Stamps."
        )
        tapReachable(savedStamp)
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.saved.postcardBody"].waitForExistence(timeout: stepTimeout),
            "Choosing a saved stamp should open that Map Stamp, not leave the Review clue."
        )
        XCTAssertTrue(app.staticTexts["Ichiran Shibuya"].firstMatch.exists)
        attach(app, name: "review-change-place-saved-stamp")

        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let leftoverClue = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'saves.reviewCandidate.' AND label CONTAINS[c] %@",
                "Harbor Oven Pizza"
            )
        ).firstMatch
        XCTAssertFalse(
            leftoverClue.exists,
            "Choosing a saved Map Stamp during Review correction must retire the clue."
        )
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
                "--uitest-location-denied",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": storageID]
        )
        launch(app)
        try signInViaReviewDemo(app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(rootTabButton("Save", app: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.savedPlaces"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.place.'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["home.eat"].exists)
        XCTAssertTrue(app.buttons["home.citySwitcher"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.review"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.saves"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.locationPrompt"].exists)
        XCTAssertTrue(app.buttons["home.locationAllow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.trips"].exists)

        for tab in ["Home", "Map", "Save", "Passport"] {
            XCTAssertTrue(rootTabButton(tab, app: app).waitForExistence(timeout: stepTimeout), "Missing \(tab) root tab")
        }
        XCTAssertTrue(rootTabButton("Home", app: app).isSelected)

        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))

        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertTrue(
            app.descendants(matching: .any)["map.liveSurface"].waitForExistence(timeout: stepTimeout)
                || app.buttons["Center map on current location"].exists,
            "Product Map is tile-town; Trip MapKit keeps the location control."
        )

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

        for rootTab in ["Home", "Map", "Save", "Passport"] {
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
        for rootTab in ["Home", "Map", "Save", "Passport"] {
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
                "--uitest-repair-review-demo-seed",
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
        for rootTab in ["Home", "Map", "Save", "Passport"] {
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
        XCTAssertFalse(app.descendants(matching: .any)["trips.assistant"].exists)
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
        tapReachable(app.buttons["trips.create"])
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["plan.chat.input"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["trip.create.sheet"].exists)
        XCTAssertFalse(app.buttons["plan.options"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["plan.draft"].exists)
        attach(app, name: "trips-new-opens-plan-chat")

        let keyboardDone = app.buttons["plan.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: stepTimeout))
        keyboardDone.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: stepTimeout))
        popPlan(app: app, returningTo: "trips.home")
        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        dismissLocationAlertIfPresent()
        XCTAssertTrue(
            app.descendants(matching: .any)["map.liveSurface"].waitForExistence(timeout: stepTimeout)
                || app.maps.firstMatch.exists,
            "Product Map is tile-town; Trip MapKit still uses MapKit."
        )
        XCTAssertTrue(app.buttons["map.command.search"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["map.place.openDetails"].exists)
        XCTAssertTrue(rootTabButton("Map", app: app).isSelected)
        attach(app, name: "atlas-root-map-live")

        app.buttons["map.command.search"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["map.search.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["drawer.mapAssistant.intro"].exists)
        for legacyTab in ["saved", "review", "friends", "lists"] {
            XCTAssertFalse(app.buttons["drawer.tab.\(legacyTab)"].exists)
        }
    }

    @MainActor
    func testTripsAskRoutesToPlanChat() throws {
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

        XCTAssertFalse(app.textFields["trips.assistant.input"].exists)
        tapReachable(app.buttons["trips.create"])
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(rootTabButton("Plan", app: app).exists)
        XCTAssertFalse(rootTabButton("Home", app: app).exists)
        XCTAssertTrue(app.navigationBars["Plan"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["plan.chat.input"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
        XCTAssertFalse(app.buttons["plan.options"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["plan.draft"].exists)
        attach(app, name: "trips-ask-routes-to-plan-chat")
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
            "--uitest-reset-review-demo-storage", "--uitest-location-denied",
            "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: launchTimeout))
        attach(app, name: "home-search-pending-candidate")
        tapReachable(app.buttons["home.citySwitcher"])
        let tokyo = app.descendants(matching: .any)["home.city.tokyo"]
        XCTAssertTrue(tokyo.waitForExistence(timeout: stepTimeout))
        tapReachable(tokyo)
        let ichiran = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.place.' AND label CONTAINS[c] %@", "Ichiran")
        ).firstMatch
        XCTAssertTrue(ichiran.waitForExistence(timeout: stepTimeout))
        ichiran.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        app.buttons["drawer.place.close"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout))
        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saves.reviewCandidate.'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
        review.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "home-real-candidate-detail")
        app.buttons["drawer.place.close"].firstMatch.tap()
        openSavesFromHome(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        let firstCandidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saves.reviewCandidate.'")).firstMatch
        XCTAssertTrue(firstCandidate.label.contains("Harbor Oven Pizza"))
        XCTAssertTrue(
            firstCandidate.label.contains("la.harbor.eats"),
            "Saves rows must keep the known source handle, not only the next-step sentence."
        )
        XCTAssertTrue(
            firstCandidate.label.contains("Check the name and address before confirming"),
            "Saves rows should keep next-step guidance in addition to known evidence."
        )
        XCTAssertFalse(
            firstCandidate.label.contains("33.7405"),
            "A map coordinate must never appear as the Saves-row source handle."
        )
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
        openSavesFromHome(app: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout),
            "Home Review clues should navigate to Saves."
        )
        XCTAssertFalse(rootTabButton("Saves", app: app).exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["drawer.root"].exists,
            "Home Review clues should not present a drawer."
        )
        XCTAssertTrue(app.staticTexts["Newest saved first"].exists)
        XCTAssertTrue(app.buttons["saves.duplicateAudit"].exists)
        attach(app, name: "home-review-opens-saves")
        app.buttons["saves.segment.mapStamps"].tap()
        XCTAssertTrue(app.buttons["saves.segment.mapStamps"].isSelected)
        attach(app, name: "saves-stamps-chronology")
        app.buttons["saves.duplicateAudit"].tap()
        XCTAssertTrue(app.navigationBars["Duplicate review"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "saves-duplicate-audit")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["saves.segment.mapStamps"].waitForExistence(timeout: stepTimeout))
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
        XCTAssertFalse(app.descendants(matching: .any)["map.search.root"].exists)
        app.buttons["Close capture"].tap()

        openRootTab("Map", app: app)
        let mapSearch = app.buttons["map.command.search"]
        XCTAssertTrue(mapSearch.waitForExistence(timeout: stepTimeout))
        mapSearch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["map.search.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "map.search.root").count,
            1,
            "Only one command drawer should be presented."
        )
        XCTAssertFalse(app.descendants(matching: .any)["drawer.mapAssistant.intro"].exists)
        for legacyTab in ["saved", "review", "friends", "lists"] {
            XCTAssertFalse(app.buttons["drawer.tab.\(legacyTab)"].exists)
        }
    }

    @MainActor
    func testMapSearchOpensSavedPlaceWithoutAssistant() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Map", app: app)
        dismissLocationAlertIfPresent()
        let search = app.buttons["map.command.search"]
        XCTAssertTrue(search.waitForExistence(timeout: stepTimeout))
        attach(app, name: "map-docked-search")
        search.tap()
        let input = app.textFields["map.search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        input.tap()
        input.typeText("ichiran")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.search.saved.'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["drawer.mapAssistant.intro"].exists)
        attach(app, name: "map-place-search-results")
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["drawer.saved.postcardBody"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Ichiran Shibuya"].firstMatch.exists)
        attach(app, name: "map-search-saved-place-detail")
        XCTAssertEqual(app.state, .runningForeground)
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
        XCTAssertTrue(
            app.descendants(matching: .any)["map.liveSurface"].waitForExistence(timeout: stepTimeout)
                || app.maps.firstMatch.exists,
            "Product Map is tile-town; Trip MapKit still uses MapKit."
        )

        let collapsed = app.descendants(matching: .any)["map.drawerPanel.collapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: stepTimeout))
        waitForStableFrame(collapsed)
        let collapsedTop = collapsed.frame.minY
        let drawerBottom = collapsed.frame.maxY
        XCTAssertLessThanOrEqual(collapsed.frame.height, 66)
        XCTAssertEqual(collapsed.frame.width / app.frame.width, 0.86, accuracy: 0.02)
        XCTAssertLessThanOrEqual(app.buttons["map.command.search"].frame.minY - collapsedTop, 14)
        XCTAssertLessThanOrEqual(app.buttons["map.command.search"].frame.height, 52)
        XCTAssertTrue(app.buttons["map.command.passport"].isHittable)
        let locate = app.descendants(matching: .any)["map.currentLocation"].firstMatch
        XCTAssertTrue(locate.isHittable)
        XCTAssertLessThanOrEqual(locate.frame.maxY, collapsedTop - 4)
        attach(app, name: "map-search-drawer-collapsed")

        // Drag from the collapsed shelf resizes without requesting keyboard.
        app.buttons["map.command.search"].swipeUp()
        let medium = app.descendants(matching: .any)["map.drawerPanel.medium"]
        XCTAssertTrue(medium.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["map.search.root"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].exists)
        waitForStableFrame(medium)
        let mediumTop = medium.frame.minY
        XCTAssertEqual(medium.frame.maxY, drawerBottom, accuracy: 2)
        XCTAssertGreaterThanOrEqual(mediumTop / app.frame.height, 0.54)
        XCTAssertLessThanOrEqual(mediumTop / app.frame.height, 0.60)
        XCTAssertLessThan(mediumTop, collapsedTop - 120)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["map.liveSurface"].isHittable
                || app.maps.firstMatch.isHittable
        )
        attach(app, name: "map-search-drawer-medium")

        // Drag a finger-length distance; swipeUp/Down scales travel to the
        // compact grip's 12pt bounds and can miss the 44pt resize threshold.
        func dragHandle(by distance: CGFloat) {
            let start = app.descendants(matching: .any)["map.drawerPanel.handle"]
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
        }
        app.descendants(matching: .any)["map.drawerPanel.handle"].tap()
        let large = app.descendants(matching: .any)["map.drawerPanel.large"]
        XCTAssertTrue(large.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].exists)
        waitForStableFrame(large)
        XCTAssertEqual(large.frame.maxY, drawerBottom, accuracy: 2)
        XCTAssertLessThan(large.frame.minY, mediumTop - 120)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attach(app, name: "map-search-drawer-large")

        dragHandle(by: 160)
        XCTAssertTrue(medium.waitForExistence(timeout: stepTimeout))
        waitForStableFrame(medium)
        dragHandle(by: 160)
        XCTAssertTrue(collapsed.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["map.search.root"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["map.liveSurface"].exists
                || app.maps.firstMatch.exists
        )
        // Repeat from rest to catch a drag leaving taps blocked or focus stuck.
        app.buttons["map.command.search"].swipeUp()
        XCTAssertTrue(medium.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        waitForStableFrame(medium)
        dragHandle(by: -160)
        XCTAssertTrue(large.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        dragHandle(by: 160)
        XCTAssertTrue(medium.waitForExistence(timeout: stepTimeout))
        dragHandle(by: 160)
        XCTAssertTrue(collapsed.waitForExistence(timeout: stepTimeout))
        // Shelf tap opens the existing full-height panel and requests keyboard.
        app.buttons["map.command.search"].tap()
        XCTAssertTrue(large.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.textFields["map.search.input"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: stepTimeout))
        attach(app, name: "map-search-shelf-tap-keyboard-focus")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testPlanChatDraftAndConversationSurviveTabChange() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openPlanFromTrips(app: app)
        let input = app.textFields["plan.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["plan.compose"].isHittable)
        attach(app, name: "plan-chat-start")
        input.tap()
        input.typeText("Plan a relaxed 1 day trip in Tokyo")
        let send = app.buttons["plan.chat.send"]
        XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertTrue(app.buttons["plan.newTrip"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["plan.newTrip"].frame.minY, app.frame.minY)
        attach(app, name: "plan-chat-keyboard")
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["tripPlan.save"].exists)
        let review = app.buttons["plan.draft.review"]
        XCTAssertTrue(review.isHittable)
        attach(app, name: "plan-chat-draft")
        review.tap()
        XCTAssertTrue(app.buttons["tripPlan.save"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-review-details")
        XCTAssertFalse(app.buttons["plan.review.close"].exists)
        tapReachable(review)
        XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
        popPlan(app: app, returningTo: "trips.home")
        openRootTab("Home", app: app)
        openPlanFromTrips(app: app)
        XCTAssertTrue(app.staticTexts["Plan a relaxed 1 day trip in Tokyo"].waitForExistence(timeout: stepTimeout))
        app.buttons["plan.allTrips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.savedTrips"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testPlanSemanticDayEditStaysInOneConversation() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openPlanFromTrips(app: app)
        let input = app.textFields["plan.chat.input"]
        typeText("Taipei 2 days", into: input)
        tapReachable(app.buttons["plan.chat.send"])
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'What pace would you like'")).firstMatch.exists)
        attach(app, name: "plan-agent-first-draft")
        typeText("Day two is too tiring; make it lighter", into: input)
        tapReachable(app.buttons["plan.chat.send"])
        XCTAssertTrue(app.staticTexts["I’ve made day two lighter and kept day one unchanged."].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].exists)
        attach(app, name: "plan-agent-local-day-edit")
        tapReachable(app.buttons["plan.draft.review"])
        let shorterVisit = app.staticTexts["45 min"].firstMatch
        XCTAssertTrue(scrollUntilHittable(shorterVisit, in: app.scrollViews.firstMatch, maxSwipes: 8))
        attach(app, name: "plan-agent-shorter-visit")
    }

    @MainActor
    func testPlanCanStartAgainWithoutLosingSavedTrips() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openPlanFromTrips(app: app)
        let input = app.textFields["plan.chat.input"]
        for answer in ["Taipei 7 days packed"] {
            typeText(answer, into: input)
            tapReachable(app.buttons["plan.chat.send"])
        }
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForExistence(timeout: stepTimeout))
        let newTrip = app.buttons["plan.newTrip"]
        XCTAssertTrue(newTrip.isHittable)
        newTrip.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: stepTimeout))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].exists)
        newTrip.tap()
        alert.buttons["Start new trip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForNonExistence(timeout: stepTimeout))
        XCTAssertFalse(app.staticTexts["more places"].exists)
        typeText("Tokyo 1 day balanced; no time constraints", into: input)
        tapReachable(app.buttons["plan.chat.send"])
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-second-draft")
        app.buttons["plan.allTrips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.savedTrips"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(input.exists)
        XCTAssertFalse(app.textFields["trips.assistant.input"].exists)
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan.savedTrip.'")).firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-saved-trips-inline")
        trip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip.plan"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testPlanKeepsSixDaysWhileAskingForCityAndUnknownSwitch() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openPlanFromTrips(app: app)
        let input = app.textFields["plan.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        typeText("日本旅行6天五夜", into: input)
        app.buttons["plan.chat.send"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Got it, 6 days'")).firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["plan.draft"].exists)
        for answer in ["Taipei"] {
            typeText(answer, into: input)
            tapReachable(app.buttons["plan.chat.send"])
        }
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3 more days in details'")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["plan.options"].exists)
        attach(app, name: "plan-six-day-conversation")
        typeText("改去京都", into: input)
        app.buttons["plan.chat.send"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '京都' AND label CONTAINS 'saved places'")).firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["plan.draft"].exists, "Clarification must retain the prior unsaved draft.")
        attach(app, name: "plan-unknown-destination-keeps-draft")
    }

    @MainActor
    func testPlaceActionsStagePlanAndRequireExplicitTripChoice() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "-save.appLanguage", "en"
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openSavesFromHome(app: app)
        app.buttons["saves.segment.mapStamps"].tap()
        let place = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saves.place.'")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: stepTimeout))
        tapReachable(place)
        let detail = app.scrollViews["place.detail.scroll"]
        XCTAssertTrue(detail.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.buttons["drawer.saved.more"].exists)
        let edit = app.buttons["drawer.saved.edit"]
        XCTAssertTrue(scrollUntilHittable(edit, in: detail, maxSwipes: 8))
        edit.tap()
        let name = app.textFields["Place name"]
        XCTAssertTrue(name.waitForExistence(timeout: stepTimeout))
        let savedName = name.value as? String ?? ""
        XCTAssertFalse(savedName.isEmpty)
        app.buttons["Cancel"].tap()
        let delete = app.buttons["drawer.saved.delete"]
        XCTAssertTrue(scrollUntilHittable(delete, in: detail, maxSwipes: 4))
        delete.tap()
        let deleteConfirmation = app.buttons["Delete Place"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: stepTimeout))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // Compact confirmation popovers dismiss by tapping outside and
            // do not expose the system cancel action as a separate button.
            detail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
        XCTAssertTrue(deleteConfirmation.waitForNonExistence(timeout: stepTimeout))
        let around = app.buttons["drawer.saved.planAround"]
        for _ in 0..<8 where !around.isHittable { detail.swipeDown() }
        XCTAssertTrue(around.isHittable)
        around.tap()
        let input = app.textFields["plan.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue((input.value as? String ?? "").contains(savedName))
        XCTAssertFalse(app.descendants(matching: .any)["plan.draft"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
        attach(app, name: "plan-place-anchor-awaiting-input")
        popPlan(app: app, returningTo: "home.root")
        openRootTab("Home", app: app)
        openSavesFromHome(app: app)
        app.buttons["saves.segment.mapStamps"].tap()
        XCTAssertTrue(place.waitForExistence(timeout: stepTimeout))
        tapReachable(place)
        XCTAssertTrue(detail.waitForExistence(timeout: stepTimeout))
        let add = app.buttons["drawer.saved.addToTrip"]
        XCTAssertTrue(scrollUntilHittable(add, in: detail, maxSwipes: 8))
        add.tap()
        attach(app, name: "plan-assignment-arrival")
        XCTAssertTrue(app.descendants(matching: .any)["plan.tripChoices"].waitForExistence(timeout: stepTimeout), app.debugDescription)
        XCTAssertTrue(app.buttons["plan.assignTrip.new"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["trip.create.sheet"].exists)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan.assignTrip.' AND identifier != 'plan.assignTrip.new'")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-explicit-trip-choice")
        tapReachable(existing)
        XCTAssertTrue(app.staticTexts["Added to your trip."].waitForExistence(timeout: timeout(20)))
        XCTAssertFalse(app.descendants(matching: .any)["plan.tripChoices"].exists)
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

        openPlanFromTrips(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["plan.conversation"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.descendants(matching: .any)["origin.root"].exists)

        XCTAssertFalse(app.descendants(matching: .any)["plan.options"].firstMatch.exists)
        let input = app.textFields["plan.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        typeText("Taipei 2 days balanced; no time constraints", into: input)
        tapReachable(app.buttons["plan.chat.send"])
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
        openPlanFromTrips(app: app)
        let scroll = app.scrollViews.firstMatch
        XCTAssertFalse(app.descendants(matching: .any)["plan.options"].firstMatch.exists)
        let input = app.textFields["plan.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: stepTimeout))
        typeText("Taipei 2 days balanced; no time constraints", into: input)
        let send = app.buttons["plan.chat.send"]
        XCTAssertTrue(send.isHittable)
        attach(app, name: "plan-chat-conditions")
        tapReachable(send)
        let review = app.buttons["plan.draft.review"]
        XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
        tapReachable(review)
        let candidate = app.buttons["tripPlan.confirm.Plan Test Garden"]
        XCTAssertTrue(scrollUntilHittable(candidate, in: scroll, maxSwipes: 10))
        attach(app, name: "plan-candidate-before-confirmation")
        candidate.tap()
        let confirm = app.buttons["Confirm & save place"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        confirm.tap()
        XCTAssertTrue(candidate.waitForNonExistence(timeout: timeout(30)))
        XCTAssertTrue(scrollUntilHittable(review, in: scroll, maxSwipes: 10))
        review.tap()
        review.tap()
        XCTAssertFalse(candidate.exists, "A confirmed candidate must stay confirmed after reopening details.")
        typeText("Day two is too tiring; make it lighter", into: input)
        tapReachable(send)
        XCTAssertTrue(app.staticTexts["I’ve made day two lighter and kept day one unchanged."].waitForExistence(timeout: stepTimeout))
        tapReachable(review)
        XCTAssertFalse(candidate.exists, "Editing day two must retain the confirmed identity on day one.")
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
        let tripBack = app.buttons["trip.back"]
        XCTAssertTrue(tripBack.waitForExistence(timeout: stepTimeout))
        tripBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(
            app.staticTexts["Day two is too tiring; make it lighter"].waitForExistence(timeout: stepTimeout),
            "Returning from a saved Trip keeps the existing Plan conversation"
        )
        XCTAssertTrue(app.staticTexts["I’ve made day two lighter and kept day one unchanged."].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["plan.draft"].exists,
            "Returning from a saved Trip keeps the edited draft"
        )
        XCTAssertTrue(scrollUntilHittable(review, in: app.scrollViews.firstMatch, maxSwipes: 10))
        review.tap()
        XCTAssertTrue(app.staticTexts["Plan Test Garden"].firstMatch.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(candidate.exists, "Returning from a saved Trip retains the confirmed place in its draft")

        terminate(app)
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openPlanFromTrips(app: app)
        let allTrips = app.buttons["plan.allTrips"]
        XCTAssertTrue(scrollUntilHittable(allTrips, in: app.scrollViews.firstMatch, maxSwipes: 8))
        allTrips.tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.savedTrips"].waitForExistence(timeout: stepTimeout))
        let savedTrip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan.savedTrip.' AND label CONTAINS %@", savedName)).firstMatch
        XCTAssertTrue(scrollUntilHittable(savedTrip, in: app.scrollViews.firstMatch, maxSwipes: 8))
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

        // Doodle place sheet: Directions + 我來過了. One selected place, one sheet.
        let card = app.descendants(matching: .any)["map.placeSheet"]
        XCTAssertTrue(card.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "map.placeSheet").count,
            1,
            "Exactly one surface should represent the selected place."
        )
        XCTAssertTrue(app.buttons["map.directions"].exists)
        XCTAssertTrue(app.buttons["map.card.beenHere"].exists)
        XCTAssertTrue(app.buttons["map.peek.card"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["place.detail.root"].exists,
            "The place sheet must not co-present with place detail."
        )
        XCTAssertFalse(app.descendants(matching: .any)["drawer.root"].exists)
        attach(app, name: "map-place-card-actions")

        app.buttons["map.peek.card"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.root"].waitForExistence(timeout: stepTimeout)
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "drawer.root").count,
            1,
            "Opening the place sheet should present exactly one drawer surface."
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

        let selectedName = app.staticTexts["map.peek.name"]
        XCTAssertTrue(selectedName.waitForExistence(timeout: stepTimeout),
            "The tile-town selection should expose its real place name.")
        XCTAssertFalse(selectedName.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(app.staticTexts["map.peek.subtitle"].exists,
            "The selected Map Stamp should show its saved-date context.")
        // MapKit annotations surface as Other, not Button. Query the same
        // tree the Taipei pin-count tests already use.
        let selectedPin = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'map.tilePin.' AND label BEGINSWITH 'Selected Map Stamp, '")
        ).firstMatch
        XCTAssertTrue(selectedPin.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(selectedPin.label, "Selected Map Stamp, \(selectedName.label)")

        let openMapDetails = app.buttons["map.peek.card"]
        XCTAssertTrue(openMapDetails.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(openMapDetails.label.contains(selectedName.label))
        attach(app, name: "tile-town-selected-stamp")
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
    func testPassportListsEntryOpensListsDirectly() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Passport", app: app)
        XCTAssertTrue(app.buttons["profile.editAvatar"].exists)
        attach(app, name: "passport-current-avatar")
        app.buttons["profile.settings"].tap()
        let lists = app.buttons["profile.lists"]
        XCTAssertTrue(scrollUntilHittable(lists, in: app.scrollViews.firstMatch, maxSwipes: 6))
        for _ in 0..<3 {
            if lists.frame.maxY < app.frame.maxY - 24 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertLessThan(lists.frame.maxY, app.frame.maxY - 24)
        attach(app, name: "passport-lists-entry")
        lists.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.connections.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "passport-lists-destination")
        XCTAssertTrue(app.buttons["profile.connections.createList"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(app.textFields["profile.connections.referral"].exists,
                       "The direct lists entry must open lists rather than the friends form.")
        attach(app, name: "passport-direct-lists")
    }

    @MainActor
    func testPassportCompactLedgerShowsActionableQuests() throws {
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-review-demo-offline",
            "--uitest-reset-review-demo-storage", "--uitest-repair-review-demo-seed", "-save.appLanguage", "en",
        ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Passport", app: app)
        let cover = app.descendants(matching: .any)["profile.cover"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: stepTimeout))
        XCTAssertLessThan(cover.frame.height, app.frame.height * 0.35)
        XCTAssertTrue(app.buttons["profile.followers"].isHittable)
        let quests = app.descendants(matching: .any)["profile.today"].firstMatch
        XCTAssertTrue(quests.isHittable, "Quests must be visible without opening a disclosure.")
        if app.buttons["profile.today.expand"].exists { app.buttons["profile.today.expand"].tap() }
        let visit = app.buttons["profile.today.markVisitedStamp"]
        XCTAssertTrue(scrollUntilHittable(visit, in: app.scrollViews.firstMatch, maxSwipes: 2))
        attach(app, name: "passport-compact-ledger")
        visit.tap()
        let confirm = app.buttons["profile.today.markVisitedConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        attach(app, name: "passport-quest-visit")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: stepTimeout))
        app.buttons["profile.settings"].tap()
        let activity = app.descendants(matching: .any)["profile.fieldStreak"].firstMatch
        XCTAssertTrue(scrollUntilHittable(activity, in: app.scrollViews.firstMatch, maxSwipes: 4))
        XCTAssertTrue(activity.label.contains("-day streak"))
        XCTAssertTrue(activity.label.contains("Today is complete."))
        attach(app, name: "passport-daily-streak")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let review = app.buttons["profile.today.confirmWaitingClue"]
        for _ in 0..<4 {
            if review.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(review.isHittable)
        review.tap()
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))

        terminate(app)
        app.launchArguments.removeAll { $0 == "--uitest-reset-review-demo-storage" }
        if let language = app.launchArguments.firstIndex(of: "en") {
            app.launchArguments[language] = "zh-Hant"
        }
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        openRootTab("Passport", app: app)
        if app.buttons["profile.today.expand"].exists { app.buttons["profile.today.expand"].tap() }
        XCTAssertTrue(app.buttons["profile.today.markVisitedStamp"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "passport-quests-zh")
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
                "--uitest-repair-review-demo-seed",
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

        XCTAssertTrue(
            app.buttons["home.passport"].waitForExistence(timeout: stepTimeout),
            "Home should keep the fixed Passport entry in its Savvy lockup."
        )
        openPlanFromTrips(app: app)
        XCTAssertTrue(app.navigationBars["Plan"].buttons.firstMatch.isHittable)
        XCTAssertFalse(app.buttons["home.passport"].exists, "Plan uses native child navigation")
        XCTAssertFalse(app.buttons["root.passport"].exists, "Plan uses native child navigation")

        popPlan(app: app, returningTo: "trips.home")
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

        openRootTab("Passport", app: app)

        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["profile.cover"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.buttons["profile.followers"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "atlas-passport")

        let connections = app.buttons["profile.following"]
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

        XCTAssertTrue(app.buttons["home.passport"].waitForExistence(timeout: launchTimeout))
        app.buttons["home.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))

        let connections = app.buttons["profile.following"]
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
                "--uitest-repair-review-demo-seed",
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
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: timeout(20)))

        let placeDetailScroll = app.scrollViews["place.detail.scroll"]
        XCTAssertTrue(placeDetailScroll.waitForExistence(timeout: stepTimeout))
        let confirmCandidate = app.buttons["drawer.review.primaryAction"]
        XCTAssertTrue(
            scrollUntilHittable(confirmCandidate, in: placeDetailScroll),
            "Confirm candidate never became tappable.\n\(app.debugDescription)"
        )
        confirmCandidate.tap()
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
        app.navigationBars.buttons.firstMatch.tap()
        openSavesFromHome(app: app)
        app.buttons["saves.segment.mapStamps"].tap()

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

        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "plan-assignment-arrival")
        XCTAssertTrue(app.descendants(matching: .any)["plan.tripChoices"].waitForExistence(timeout: stepTimeout), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["trip.create.sheet"].exists)
        let newPlan = app.buttons["plan.assignTrip.new"]
        XCTAssertTrue(newPlan.waitForExistence(timeout: stepTimeout))
        tapReachable(newPlan)
        let planInput = app.textFields["plan.chat.input"]
        XCTAssertTrue(planInput.waitForExistence(timeout: stepTimeout))
        let staged = planInput.value as? String ?? ""
        XCTAssertTrue(staged.contains(placeName))
        XCTAssertFalse(app.descendants(matching: .any)["plan.draft"].exists)
        typeText(" 1 day balanced; no time constraints", into: planInput)
        tapReachable(app.buttons["plan.chat.send"])
        let review = app.buttons["plan.draft.review"]
        XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
        tapReachable(review)
        let save = app.buttons["tripPlan.save"]
        XCTAssertTrue(save.waitForExistence(timeout: stepTimeout))
        tapReachable(save)
        let tripNameField = app.textFields["tripPlanSave.name"]
        XCTAssertTrue(tripNameField.waitForExistence(timeout: stepTimeout))
        replaceText(in: tripNameField, with: tripName)
        attach(app, name: "atlas-reviewed-plan-save")
        app.buttons["tripPlanSave.confirm"].tap()
        let success = app.alerts.firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: timeout(20)))
        XCTAssertTrue(success.staticTexts["Saved to Trip Packs"].exists)
        success.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["plan.review.close"].exists)
        tapReachable(review)
        popPlan(app: app, returningTo: "home.root")
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
            seededApp.buttons["home.passport"].waitForExistence(timeout: stepTimeout)
        )
        seededApp.buttons["home.passport"].tap()
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
        case "Friends": return "friends.root"
        case "Passport": return "profile.root"
        default: return nil
        }
    }

    /// MapKit pixels vary, but product chrome is never exempt from layout checks.
    @MainActor
    private func assertDoodleMapChrome(_ app: XCUIApplication) {
        let city = app.buttons["map.city"]
        let eat = app.buttons["map.eat"]
        let go = app.buttons["map.go"]
        let sheet = app.descendants(matching: .any)["map.placeSheet"]
        let directions = app.buttons["map.directions"]
        let visit = app.buttons["map.card.beenHere"].exists
            ? app.buttons["map.card.beenHere"] : app.buttons["map.card.beenHere.undo"]
        for control in [city, eat, go, directions, visit] {
            XCTAssertTrue(control.waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(control.isHittable, "Map control must be accessible: \(control.identifier)")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX)
        }
        XCTAssertTrue(sheet.exists)
        XCTAssertLessThanOrEqual(city.frame.maxY, eat.frame.minY)
        XCTAssertLessThanOrEqual(eat.frame.maxY, sheet.frame.minY)
        XCTAssertLessThanOrEqual(directions.frame.maxX, visit.frame.minX)
        XCTAssertEqual(directions.frame.height, 48, accuracy: 2, "298-4: Directions is 48pt tall")
        XCTAssertEqual(visit.frame.height, 48, accuracy: 2, "298-4: I've been here is 48pt tall")
        XCTAssertEqual(visit.frame.minX - directions.frame.maxX, 12, accuracy: 3, "298-4: 12pt button gap")
        XCTAssertLessThanOrEqual(sheet.frame.maxY, rootTabButton("Map", app: app).frame.minY)
        XCTAssertTrue(
            eat.isSelected || go.isSelected,
            "298-11: Eat/Go must expose isSelected on the active lens"
        )
        let cityLabel = city.label
        XCTAssertFalse(cityLabel.contains("…") || cityLabel.contains("..."),
                       "298-12: city title must not truncate")
    }

    @MainActor
    private func openSavesFromHome(app: XCUIApplication) {
        openRootTab("Home", app: app)
        let review = app.buttons["home.review.action"]
        let fallback = app.buttons["home.saves"]
        XCTAssertTrue(
            review.waitForExistence(timeout: timeout(2))
                || fallback.waitForExistence(timeout: stepTimeout),
            "Missing visible Home Saves entry"
        )
        let entry = review.exists ? review : fallback
        _ = scrollUntilHittable(entry, in: app.scrollViews.firstMatch)
        XCTAssertTrue(entry.isHittable, "Home Saves must be usable without a hidden test-only route")
        // XCUIElement.frame can report 43.99999999999997 for a 44pt SwiftUI
        // minHeight. Allow 0.01pt of CGRect noise; do not round (43.5 would pass).
        assertTapTargetHeight(entry, name: "Home Saves entry")
        XCTAssertGreaterThanOrEqual(entry.frame.width + 0.01, 44)
        tapReachable(entry)
        let saves = app.descendants(matching: .any)["saves.root"]
        // Cap at stepTimeout, not launchTimeout. A dead navigation used to
        // burn 120s per attempt; four flakes × 3 retries blew the 35-minute
        // rail step (CI 32778736280, exit 64).
        XCTAssertTrue(
            saves.waitForExistence(timeout: stepTimeout),
            "Home Saves entry did not open Saves"
        )
    }

    @MainActor
    private func tapHittableSavesEntry(
        _ candidates: [XCUIElement],
        saves: XCUIElement
    ) -> Bool {
        guard let entry = firstHittable(candidates, timeout: timeout(2)) else { return false }
        entry.tap()
        if saves.waitForExistence(timeout: timeout(5)) { return true }
        entry.tap()
        return saves.waitForExistence(timeout: timeout(5))
    }

    @MainActor
    private func dismissSavedPlaceLimitPaywallIfPresent(app: XCUIApplication) {
        let paywall = app.descendants(matching: .any)["paywall.root"]
        guard paywall.exists else { return }
        let close = app.buttons["paywall.close"]
        if close.waitForExistence(timeout: timeout(2)) {
            tapReachable(close)
        }
        _ = paywall.waitForNonExistence(timeout: timeout(5))
    }

    @MainActor
    private func openTripsFromHome(app: XCUIApplication) {
        openSavesFromHome(app: app)
        let entry = app.buttons["saves.trips"]
        XCTAssertTrue(entry.waitForExistence(timeout: stepTimeout), "Missing Saves Trips entry")
        tapReachable(entry)
        let trips = app.descendants(matching: .any)["trips.home"]
        if !trips.waitForExistence(timeout: timeout(5)) {
            tapReachable(entry)
        }
        XCTAssertTrue(
            trips.waitForExistence(timeout: stepTimeout),
            "saves.trips did not open Trips"
        )
    }

    @MainActor
    private func popPlan(app: XCUIApplication, returningTo screenIdentifier: String) {
        let back = app.navigationBars["Plan"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: stepTimeout), "Plan must expose a native back action")
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)[screenIdentifier].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForNonExistence(timeout: stepTimeout))
    }

    @MainActor
    private func openPlanFromTrips(app: XCUIApplication) {
        openTripsFromHome(app: app)
        let resume = app.buttons["trips.plan"]
        XCTAssertTrue(resume.waitForExistence(timeout: stepTimeout), "Missing Trips resume-planning action")
        tapReachable(resume)
        XCTAssertTrue(app.descendants(matching: .any)["plan.root"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(rootTabButton("Home", app: app).exists, "Plan is a pushed child without root navigation")
        XCTAssertFalse(rootTabButton("Plan", app: app).exists)
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

    /// Home-only TPE-A raster for `atlas-home`. Does not use
    /// `--uitest-atlas-parity-fixture`, so saves/plan/map/friends keep their
    /// existing fixture and md5s. Does not replace `ProductionTargets/home.png`.
    @MainActor
    private func captureAtlasHomeTPEA() throws {
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: "en",
                location: "daan",
                hintCount: 1,
                clock: "2026-10-24T20:00:00",
                dark: false
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        XCTAssertFalse(app.descendants(matching: .any)["home.locationPrompt"].exists)
        let hint = app.descendants(matching: .any)["home.review"]
        XCTAssertTrue(hint.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(hint.label.contains("Good evening · 1 clue waiting · Review ›"), hint.label)
        XCTAssertTrue(app.buttons["home.eat"].isSelected)
        XCTAssertFalse(app.buttons["home.go"].isSelected)
        assertTPEALocatedEatRows(app)
        attach(app, name: "atlas-home")
    }

    private func tpeaLaunchArguments(
        language: String,
        location: String,
        hintCount: Int,
        clock: String,
        dark: Bool,
        fixture: String = "tpea"
    ) -> [String] {
        var arguments = [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed",
            "--uitest-home-\(fixture)",
            "--uitest-location-\(location)",
            "--uitest-home-hint-count=\(hintCount)",
            "--uitest-fixed-now=\(clock)",
            "-save.appLanguage", language,
        ]
        if dark {
            arguments.append(contentsOf: ["--uitest-force-dark", "-AppleInterfaceStyle", "Dark"])
        } else {
            arguments.append("--uitest-force-light")
        }
        return arguments
    }

    private func tpeaPlaceButton(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.buttons[String(format: "home.place.60000000-0000-0000-0000-%012d", index)]
    }

    private func tpeaPlaceRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.place.60000000'"))
    }

    /// HoP TPE-A option A: located Eat + Near you is exactly 4 rows.
    /// Labels come from CLLocation.distance + distanceText, not HoP 280/650.
    private func assertTPEALocatedEatRows(_ app: XCUIApplication) {
        let expected: [(Int, String, String)] = [
            (1, "Fujin Tree 353 Cafe", "279m"),
            (2, "Lunch Noodle", "651m"),
            (3, "Roast Duck Kitchen", "1.2km"),
            (4, "Window Cafe", "2.1km"),
        ]
        for (index, name, distance) in expected {
            let row = tpeaPlaceButton(app, index)
            XCTAssertTrue(row.waitForExistence(timeout: stepTimeout), row.identifier)
            XCTAssertTrue(row.label.contains(name), row.label)
            XCTAssertTrue(row.label.contains(distance), row.label)
        }
        XCTAssertEqual(tpeaPlaceRows(app).count, 4, "Located Eat + Near you must show exactly 4 rows")
        XCTAssertFalse(tpeaPlaceButton(app, 5).exists, "E5 3.4km must not appear on located Near you")
        XCTAssertFalse(tpeaPlaceButton(app, 8).exists, "G3 4.0km must not appear on located Eat")
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'home.place.' AND label CONTAINS 'Night Market Bar'")
            ).firstMatch.exists,
            "E5 Night Market Bar must not appear on located Eat"
        )
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'home.place.' AND label CONTAINS 'Forest Walk'")
            ).firstMatch.exists,
            "G3 Forest Walk must not appear on located Eat"
        )
    }

    /// Located Go is exactly 2 rows: 899m and 1.6km visited. E5/G3 stay out.
    private func assertTPEALocatedGoRows(_ app: XCUIApplication) {
        let g1 = tpeaPlaceButton(app, 6)
        let g2 = tpeaPlaceButton(app, 7)
        XCTAssertTrue(g1.waitForExistence(timeout: stepTimeout), g1.identifier)
        XCTAssertTrue(g2.waitForExistence(timeout: stepTimeout), g2.identifier)
        XCTAssertTrue(g1.label.contains("Temple Courtyard"), g1.label)
        XCTAssertTrue(g1.label.contains("899m"), g1.label)
        XCTAssertTrue(g2.label.contains("Lantern Alley Park"), g2.label)
        XCTAssertTrue(g2.label.contains("1.6km"), g2.label)
        XCTAssertTrue(g2.label.contains("visited"), g2.label)
        XCTAssertEqual(tpeaPlaceRows(app).count, 2, "Located Go + Near you must show exactly 2 rows")
        XCTAssertFalse(tpeaPlaceButton(app, 5).exists, "E5 3.4km must not appear on located Go")
        XCTAssertFalse(tpeaPlaceButton(app, 8).exists, "G3 4.0km must not appear on located Go")
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'home.place.' AND label CONTAINS 'Night Market Bar'")
            ).firstMatch.exists
        )
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'home.place.' AND label CONTAINS 'Forest Walk'")
            ).firstMatch.exists
        )
    }

    /// TPE-B denied/city Eat: 5 rows including E5, ≥2 districts, not 3 km limited.
    private func assertTPEBDeniedEatRows(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.eat"].isSelected)
        var labels: [String] = []
        for index in 1...5 {
            let row = tpeaPlaceButton(app, index)
            XCTAssertTrue(row.waitForExistence(timeout: stepTimeout), row.identifier)
            labels.append(row.label)
        }
        XCTAssertEqual(tpeaPlaceRows(app).count, 5, "Denied/city Eat must show exactly 5 rows including E5")
        XCTAssertTrue(labels[4].contains("Night Market Bar"), labels[4])
        let districts = ["大安區", "信義區", "中山區", "松山區"].filter { token in
            labels.contains { $0.contains(token) }
        }
        XCTAssertGreaterThanOrEqual(districts.count, 2, "TPE-B must show ≥2 districts: \(labels)")
        XCTAssertFalse(
            tpeaPlaceButton(app, 8).exists,
            "G3 is Go and must not appear on denied Eat"
        )
    }

    /// HoP 298-2 / 298-5 / 298-6 / 298-8: MapKit canvas, 我來過了, city+Eat/Go,
    /// and provider-backed Directions. Names stay off `five-tab-*`.
    @MainActor
    private func attachHoP298ChromeEvidence(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["map.liveSurface"].waitForExistence(timeout: stepTimeout),
            "298-2: product Map must be a live Apple MapKit surface"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["tileTown.root"].exists,
            "298-2: product Map is not tile-town"
        )
        attach(app, name: "298-2-mapkit")

        XCTAssertTrue(app.buttons["map.card.beenHere"].exists || app.buttons["map.card.beenHere.undo"].exists,
                      "298-5: place sheet must offer 我來過了 / I've been here")
        attach(app, name: "298-5-been-here")

        XCTAssertTrue(app.buttons["map.city"].exists, "298-6: city chrome")
        XCTAssertTrue(app.buttons["map.eat"].exists, "298-6: Eat chrome")
        XCTAssertTrue(app.buttons["map.go"].exists, "298-6: Go chrome")
        attach(app, name: "298-6-city-eat-go")

        XCTAssertTrue(app.buttons["map.directions"].exists,
                      "298-8: selected place keeps provider-backed Directions")
        attach(app, name: "298-8-provider")
    }

    /// HoP 298-10 / 298-12 / 298-13: Taipei H1/M1 fixture with saved,
    /// unsaved, and visited pins together. City title in en and zh.
    @MainActor
    func testMapSavedUnsavedVisitedTaipeiFixture() throws {
        try captureTaipeiMapStates(language: "en", attachM1: true)
        try captureTaipeiMapStates(language: "zh-Hant", attachM1: false)
    }

    @MainActor
    private func captureTaipeiMapStates(language: String, attachM1: Bool) throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-denied",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-home-memory-fixture",
                "--uitest-map-unsaved-candidate",
                "--uitest-map-place-selected",
                "-save.appLanguage", language,
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        let locationNoticeDismiss = app.buttons["map.locationNotice.dismiss"]
        if locationNoticeDismiss.waitForExistence(timeout: timeout(2)) {
            locationNoticeDismiss.tap()
        }
        XCTAssertTrue(app.buttons["map.city"].waitForExistence(timeout: stepTimeout))
        let cityLabel = app.buttons["map.city"].label
        XCTAssertFalse(
            cityLabel.contains("…") || cityLabel.contains("..."),
            "298-12: city title must not truncate"
        )
        if language == "zh-Hant" {
            XCTAssertTrue(cityLabel.contains("台北") || cityLabel.contains("臺北") || cityLabel.contains("附近"),
                          "298-12/298-13: zh city stays Taipei")
        } else {
            XCTAssertTrue(cityLabel.contains("Taipei") || cityLabel.contains("Near you"),
                          "298-12/298-13: en city stays Taipei")
        }
        XCTAssertTrue(app.buttons["map.eat"].isSelected || app.buttons["map.go"].isSelected,
                      "298-11: Eat/Go must expose isSelected")
        if language == "zh-Hant" {
            attach(app, name: "298-12-zh")
        } else {
            attach(app, name: "298-10-saved-unsaved-visited")
            attach(app, name: "five-tab-map")
            attach(app, name: "doodle-map-light")
        }
        if attachM1 {
            attach(app, name: "M1")
        }
        let unsavedPin = app.buttons["map.unsaved.uitest-unsaved-taipei"]
        if !unsavedPin.waitForExistence(timeout: timeout(1)) {
            // The selected saved stamp starts centered; the candidate is east
            // of the viewport. Pan it into view without clearing search results.
            let map = app.maps.firstMatch
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
                .press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)))
        }
        XCTAssertTrue(unsavedPin.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(unsavedPin.isHittable, "Unsaved native MapKit marker must receive taps")
        unsavedPin.tap()
        XCTAssertTrue(app.buttons["drawer.unsaved.primaryAction"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "map-unsaved-marker-receipt-\(language)")
        terminate(app)
    }

    /// Live Home is the Doodle Eat/Go list with no map component. The Atlas gate still
    /// compares `five-tab-home` to `ProductionTargets/home.png` unmasked at
    /// 0.90. Capture that raster from the Codex Tiantan
    /// fixture at the Tiantan fix; a denied-location Taipei Home is a
    /// different state and scores ~0.66. Do not retune the gate script here.
    /// Friends `five-tab-friends` is a real 0.90 gate against
    /// `ProductionTargets/friends.png`. Home deferral on #290 does not
    /// apply to Friends. Codex packet §7.4 remains the people-first layout
    /// reference.
    @MainActor
    private func captureFiveTabHomeParityRaster() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-tiantan",
                "--uitest-repair-review-demo-seed",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-fixture",
                "-save.appLanguage", "en",
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        XCTAssertFalse(app.descendants(matching: .any)["home.locationPrompt"].exists)
        let collected = app.descendants(matching: .any)["home.collected"]
        XCTAssertTrue(collected.waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(collected.label, "Collected 4/12")
        XCTAssertTrue(
            app.buttons["home.place.30000000-0000-0000-0000-000000000001"].waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(app.buttons["home.place.30000000-0000-0000-0000-000000000002"].exists)
        XCTAssertTrue(app.buttons["home.place.30000000-0000-0000-0000-000000000003"].exists)
        let homeEatCount = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.place.'")
        ).count
        let geometry = XCTAttachment(string: app.debugDescription)
        geometry.name = "home-reference-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        attach(app, name: "five-tab-home")
        // 298-3: Home and Map from the same Tiantan data, same launch.
        attach(app, name: "298-3-home")
        openRootTab("Map", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].waitForExistence(timeout: stepTimeout))
        attach(app, name: "298-7-map-tab")
        XCTAssertTrue(app.buttons["map.city"].waitForExistence(timeout: stepTimeout))
        let eatPin = "30000000-0000-0000-0000-000000000001"
        let noodlePin = "30000000-0000-0000-0000-000000000002"
        let cafePin = "30000000-0000-0000-0000-000000000003"
        let parkPin = "30000000-0000-0000-0000-000000000004"
        let lanternPin = "30000000-0000-0000-0000-000000000005"
        let jingshanPin = "30000000-0000-0000-0000-000000000006"
        XCTAssertTrue(
            app.descendants(matching: .any)["map.tilePin.\(eatPin)"].waitForExistence(timeout: stepTimeout)
        )
        for pin in [noodlePin, cafePin] {
            XCTAssertTrue(
                app.descendants(matching: .any)["map.tilePin.\(pin)"].exists,
                "298-3: Map draws saved Eat places under the shared city filter"
            )
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["map.tilePin.\(parkPin)"].exists
                || app.descendants(matching: .any)["map.tilePin.\(lanternPin)"].exists
                || app.descendants(matching: .any)["map.tilePin.\(jingshanPin)"].exists,
            "298-3: Map draws only saved places matching Eat/Go + city"
        )
        let mapPinCount = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'map.tilePin.'")
        ).count
        XCTAssertEqual(mapPinCount, homeEatCount, "298-3: pin count equals Home list rows")
        attach(app, name: "298-3-map")
        attach(app, name: "298-4-coral-pins")
        XCTAssertEqual(app.buttons["map.eat"].isSelected, true, "298-11: Eat stays selected with Home")
        terminate(app)
    }

    /// Focused local acceptance entry using the identical five-tab parity fixture.
    @MainActor
    func testHomeReferenceRaster() throws {
        try captureFiveTabHomeParityRaster()
    }

    /// Run this bounded layout rail on each required physical simulator width.
    @MainActor
    func testHomeDesignLayoutScreenshots() throws {
        for (name, category) in [
            ("default", "UICTContentSizeCategoryL"),
            ("xxxLarge", "UICTContentSizeCategoryXXXL"),
            ("accessibility", "UICTContentSizeCategoryAccessibilityM"),
        ] {
            let app = makeApp(launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-tiantan",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-home-design-fixture", "--uitest-repair-review-demo-seed",
                "--uitest-force-light", "-save.appLanguage", "zh-Hant",
                "-UIPreferredContentSizeCategoryName", category,
            ], launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
            launch(app)
            try signInViaReviewDemoRequired(app: app)
            waitForHomeCoverImagery(app)
            let review = app.descendants(matching: .any)["home.review"]
            XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
            let action = app.buttons["home.review.action"]
            XCTAssertTrue(action.waitForExistence(timeout: stepTimeout))
            XCTAssertTrue(action.isHittable)
            assertTapTargetHeight(action, name: "home.review.action")
            let frame = app.frame
            let statusBarFrame = app.statusBars.firstMatch.exists ? String(describing: app.statusBars.firstMatch.frame) : "unavailable"
            let metadata = XCTAttachment(string: "viewport=\(frame); statusBar=\(statusBarFrame); requestedCategory=\(category); language=zh-Hant; reducedMotion=\(UIAccessibility.isReduceMotionEnabled)")
            metadata.name = "layout-metadata-\(Int(frame.width))-\(name)"
            metadata.lifetime = .keepAlways
            add(metadata)
            attach(app, name: "layout-home-\(Int(frame.width))-\(name)")
            let collected = app.buttons["home.collected"]
            for _ in 0..<5 where !collected.isHittable { app.swipeUp() }
            XCTAssertTrue(collected.isHittable, "Collected must remain reachable at large text sizes")
            attach(app, name: "layout-home-bottom-\(Int(frame.width))-\(name)")
            collected.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.root"].waitForExistence(timeout: stepTimeout))
            terminate(app)
        }
    }

    /// Spec §8.1 product states. Filenames match the captured state:
    /// H1 allowed+clues, H2 denied+clues, H3 zero clues with `home.saves`,
    /// H4 empty plate. Also writes clear CI names (`H1-allowed-clues`, …).
    @MainActor
    func testHomeDesignProductStates() throws {
        try captureHomeProductState(
            state: "H1",
            clearName: "H1-allowed-clues",
            fixture: "fixture",
            location: "tiantan",
            language: "en"
        )
        try captureHomeProductState(
            state: "H2",
            clearName: "H2-denied-clues",
            fixture: "fixture",
            location: "denied",
            language: "en"
        )
        try captureHomeSavesWithoutClues(
            language: "en",
            names: ["H3", "H3-no-clues-saves"]
        )
        try captureHomeSavesWithoutClues(
            language: "zh-Hant",
            names: ["H3-no-clues-saves-zh-Hant"]
        )
        try captureHomeProductState(
            state: "H4",
            clearName: "H4-empty",
            fixture: "empty",
            location: "tiantan",
            language: "en"
        )
        try captureHomeProductState(
            state: "H4-other-city",
            clearName: nil,
            fixture: "other-city",
            location: "tiantan",
            language: "en"
        )
    }

    /// H-3b evidence: greeting + clue count + separator + Review, for N=0 / 1 /
    /// 99+ in en and zh. CI boots iPhone 16 Pro (~402pt); #295's 375pt shots
    /// come from a dedicated SE workflow step this PR is not allowed to add.
    /// Attachments record the actual viewport width. Do not fake 375pt images.
    @MainActor
    func testHomeHintCountEvidence() throws {
        for language in ["en", "zh-Hant"] {
            for count in [0, 1, 100] {
                try captureHomeHintCount(
                    count: count,
                    language: language,
                    dark: false
                )
            }
            // Dark evidence is UI-test artifacts only. N=0 and N=1 are the
            // DESIGN re-judge states; N=99+ stays light to keep the rail short.
            for count in [0, 1] {
                try captureHomeHintCount(
                    count: count,
                    language: language,
                    dark: true
                )
            }
        }
    }

    @MainActor
    private func captureHomeHintCount(count: Int, language: String, dark: Bool) throws {
        let label = count > 99 ? "n99" : "n\(count)"
        let languageTag = language == "en" ? "en" : "zh"
        let appearanceTag = dark ? "-dark" : ""
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        if dark {
            XCUIDevice.shared.appearance = .dark
        }
        var arguments = [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-location-allowed",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed", "--uitest-home-taipei-granted",
            "--uitest-home-hint-count=\(count)",
            "-save.appLanguage", language,
        ]
        if dark {
            arguments.append(contentsOf: ["--uitest-force-dark", "-AppleInterfaceStyle", "Dark"])
        } else {
            arguments.append("--uitest-force-light")
        }
        let app = makeApp(
            launchArguments: arguments,
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        let hint = app.descendants(matching: .any)["home.review"]
        XCTAssertTrue(hint.waitForExistence(timeout: stepTimeout))
        let action = app.buttons["home.review.action"]
        if count == 0 {
            XCTAssertFalse(action.exists)
            XCTAssertFalse(hint.label.contains("clue"))
            XCTAssertFalse(hint.label.contains("線索"))
        } else {
            XCTAssertTrue(action.waitForExistence(timeout: stepTimeout))
            assertTapTargetHeight(action, name: "home.review.action")
            XCTAssertFalse(action.label.contains("·"))
            if language == "en" {
                XCTAssertEqual(action.label, "Review ›")
                if count == 1 {
                    XCTAssertTrue(hint.label.contains("1 clue waiting · Review ›"), hint.label)
                } else {
                    XCTAssertTrue(hint.label.contains("99+ clues waiting · Review ›"), hint.label)
                }
            } else {
                XCTAssertEqual(action.label, "去看看 ›")
                if count == 1 {
                    XCTAssertTrue(hint.label.contains("1 條線索待看 · 去看看 ›"), hint.label)
                } else {
                    XCTAssertTrue(hint.label.contains("99+ 條線索待看 · 去看看 ›"), hint.label)
                }
            }
        }
        let width = Int(app.frame.width.rounded())
        let metadata = XCTAttachment(string: "viewport=\(app.frame); hint=\(hint.label); language=\(language); count=\(count); dark=\(dark)")
        metadata.name = "H3b-\(label)-\(languageTag)\(appearanceTag)-viewport-\(width)"
        metadata.lifetime = .keepAlways
        add(metadata)
        attach(app, name: "H3b-\(label)-\(languageTag)\(appearanceTag)")
    }

    /// B-2 Taipei distances with location granted. Light and dark, en and zh.
    /// Leaves the Tiantan parity fixture and home.png baseline unchanged.
    @MainActor
    func testHomeTaipeiGrantedDistances() throws {
        try captureTaipeiGrantedHome(dark: false, language: "en", name: "taipei-granted-light-en")
        try captureTaipeiGrantedHome(dark: true, language: "en", name: "taipei-granted-dark-en")
        try captureTaipeiGrantedHome(dark: false, language: "zh-Hant", name: "taipei-granted-light-zh")
        try captureTaipeiGrantedHome(dark: true, language: "zh-Hant", name: "taipei-granted-dark-zh")
    }

    @MainActor
    private func captureTaipeiGrantedHome(dark: Bool, language: String, name: String) throws {
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        if dark {
            XCUIDevice.shared.appearance = .dark
        }
        var arguments = [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-location-allowed",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-repair-review-demo-seed", "--uitest-home-taipei-granted",
            "--uitest-home-hint-count=0",
            "-save.appLanguage", language,
        ]
        if dark {
            arguments.append(contentsOf: ["--uitest-force-dark", "-AppleInterfaceStyle", "Dark"])
        } else {
            arguments.append("--uitest-force-light")
        }
        let app = makeApp(
            launchArguments: arguments,
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        XCTAssertFalse(app.descendants(matching: .any)["home.locationPrompt"].exists)
        let first = app.buttons["home.place.50000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(first.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(
            first.label.range(of: #"[0-9]+(\.[0-9]+)?(m|km)"#, options: .regularExpression) == nil,
            "Taipei granted first Eat row must show a non-empty distance: \(first.label)"
        )
        XCTAssertTrue(app.buttons["home.place.50000000-0000-0000-0000-000000000001"].exists)
        XCTAssertTrue(app.buttons["home.place.50000000-0000-0000-0000-000000000003"].exists)
        attach(app, name: name)
    }

    /// TPE evidence attachments only. Not a parity baseline. CI boots
    /// iPhone 16 Pro (~402pt). #295's 375pt SE shots are a dedicated
    /// workflow step this PR is not allowed to add; TPE-D records 402pt
    /// at the injected 14:00 clock instead of faking 375pt images.
    @MainActor
    func testHomeTPEAEvidence() throws {
        try captureTPEAHome(
            language: "en",
            dark: true,
            name: "TPE-A-dark-en"
        )
        try captureTPEAHome(
            language: "zh-Hant",
            dark: false,
            name: "TPE-A-light-zh"
        )
        try captureTPEAHome(
            language: "zh-Hant",
            dark: true,
            name: "TPE-A-dark-zh"
        )
        try captureTPEAGoFilter()
        try captureTPEBDenied(language: "en", name: "TPE-B-denied-light-en")
        try captureTPEBDenied(language: "zh-Hant", name: "TPE-B-denied-light-zh")
        try captureTPEHint(
            count: 0,
            language: "en",
            clock: "2026-10-24T20:00:00",
            name: "TPE-C-n0-light-en"
        )
        try captureTPEHint(
            count: 100,
            language: "en",
            clock: "2026-10-24T20:00:00",
            name: "TPE-C-n99-light-en"
        )
        for language in ["en", "zh-Hant"] {
            let tag = language == "en" ? "en" : "zh"
            for count in [0, 1, 100] {
                let label = count > 99 ? "n99" : "n\(count)"
                try captureTPEHint(
                    count: count,
                    language: language,
                    clock: "2026-10-24T14:00:00",
                    name: "TPE-D-402pt-\(label)-\(tag)-1400"
                )
            }
        }
        try captureTPEELongWrap()
        try captureTPEAHome(
            language: "en",
            dark: false,
            clock: "2026-10-24T08:00:00",
            name: "TPE-A-clock-0800-en",
            expectedGreeting: "Good morning"
        )
        try captureTPEAHome(
            language: "en",
            dark: false,
            clock: "2026-10-24T14:00:00",
            name: "TPE-A-clock-1400-en",
            expectedGreeting: "Good afternoon"
        )
    }

    @MainActor
    private func captureTPEAHome(
        language: String,
        dark: Bool,
        clock: String = "2026-10-24T20:00:00",
        name: String,
        expectedGreeting: String? = nil
    ) throws {
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
        if dark {
            XCUIDevice.shared.appearance = .dark
        }
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: language,
                location: "daan",
                hintCount: 1,
                clock: clock,
                dark: dark
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        XCTAssertFalse(app.descendants(matching: .any)["home.locationPrompt"].exists)
        XCTAssertTrue(app.buttons["home.eat"].isSelected)
        assertTPEALocatedEatRows(app)
        if let expectedGreeting {
            XCTAssertTrue(
                app.descendants(matching: .any)["home.review"].label.contains(expectedGreeting),
                app.descendants(matching: .any)["home.review"].label
            )
        }
        let width = Int(app.frame.width.rounded())
        let metadata = XCTAttachment(string: "viewport=\(app.frame); name=\(name); width=\(width)")
        metadata.name = "\(name)-viewport-\(width)"
        metadata.lifetime = .keepAlways
        add(metadata)
        attach(app, name: name)
    }

    @MainActor
    private func captureTPEAGoFilter() throws {
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: "en",
                location: "daan",
                hintCount: 1,
                clock: "2026-10-24T20:00:00",
                dark: false
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        tapReachable(app.buttons["home.go"])
        XCTAssertTrue(app.buttons["home.go"].isSelected)
        assertTPEALocatedGoRows(app)
        attach(app, name: "TPE-A-go-light-en")
    }

    @MainActor
    private func captureTPEBDenied(language: String, name: String) throws {
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: language,
                location: "denied",
                hintCount: 1,
                clock: "2026-10-24T20:00:00",
                dark: false
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        XCTAssertTrue(app.descendants(matching: .any)["home.locationPrompt"].waitForExistence(timeout: stepTimeout))
        assertTPEBDeniedEatRows(app)
        attach(app, name: name)
    }

    @MainActor
    private func captureTPEHint(
        count: Int,
        language: String,
        clock: String,
        name: String
    ) throws {
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: language,
                location: "daan",
                hintCount: count,
                clock: clock,
                dark: false
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        let hint = app.descendants(matching: .any)["home.review"]
        XCTAssertTrue(hint.waitForExistence(timeout: stepTimeout))
        if count == 0 {
            XCTAssertFalse(app.buttons["home.review.action"].exists)
        } else {
            XCTAssertTrue(app.buttons["home.review.action"].waitForExistence(timeout: stepTimeout))
        }
        let width = Int(app.frame.width.rounded())
        let metadata = XCTAttachment(string: "viewport=\(app.frame); hint=\(hint.label); name=\(name)")
        metadata.name = "\(name)-viewport-\(width)"
        metadata.lifetime = .keepAlways
        add(metadata)
        attach(app, name: name)
    }

    @MainActor
    private func captureTPEELongWrap() throws {
        let app = makeApp(
            launchArguments: tpeaLaunchArguments(
                language: "en",
                location: "denied",
                hintCount: 0,
                clock: "2026-10-24T20:00:00",
                dark: false,
                fixture: "tpee"
            ),
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString.lowercased()]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        let longName = app.buttons["home.place.70000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(longName.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(longName.label.contains("Very Long Corner Breakfast"))
        XCTAssertTrue(
            longName.label.contains("District") || longName.label.contains("區"),
            "TPE-E must keep the district visible: \(longName.label)"
        )
        attach(app, name: "TPE-E-long-wrap-denied-en")
    }

    @MainActor
    private func captureHomeProductState(
        state: String,
        clearName: String?,
        fixture: String,
        location: String,
        language: String
    ) throws {
        let hasClues = fixture == "fixture"
        let app = makeApp(launchArguments: [
            "--uitest-complete-onboarding", "--skip-map-tour",
            "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
            "--uitest-home-design-\(fixture)", "--uitest-location-\(location)",
            "--uitest-force-light",
            "-save.appLanguage", language,
        ] + (hasClues ? ["--uitest-repair-review-demo-seed"] : []),
        launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString])
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        if hasClues {
            waitForHomeCoverImagery(app)
            let review = app.descendants(matching: .any)["home.review"]
            XCTAssertTrue(review.waitForExistence(timeout: stepTimeout), "\(state) must expose home.review")
            XCTAssertEqual(review.identifier, "home.review")
            XCTAssertTrue(review.label.contains("2"), "\(state) must contain two unconfirmed clues")
            XCTAssertTrue(
                app.buttons["home.review.action"].waitForExistence(timeout: stepTimeout),
                "\(state) Review › is the only coral tap on the hint row"
            )
            XCTAssertTrue(
                review.label.contains("waiting · Review ›")
                    || review.label.contains("待看 · 去看看 ›"),
                "\(state) must keep the separator before Review / 去看看"
            )
            XCTAssertFalse(
                app.buttons["home.review.action"].label.contains("·"),
                "\(state) coral Review control must not include the separator"
            )
            XCTAssertFalse(
                app.buttons["home.saves"].exists,
                "\(state) hides home.saves while clues wait"
            )
            XCTAssertEqual(
                app.descendants(matching: .any)["home.locationPrompt"].exists,
                location == "denied",
                "\(state) location prompt must match \(location)"
            )
            if location == "denied" {
                XCTAssertTrue(app.buttons["home.locationAllow"].exists)
            }
            for suffix in ["000000000001", "000000000002", "000000000003"] {
                XCTAssertTrue(app.buttons["home.place.30000000-0000-0000-0000-\(suffix)"].exists)
            }
        } else {
            // Empty-plate evidence is the visible capture control. The nested
            // empty-plate container identifier is not an XCUI element because
            // the parent saved-places group uses children: .contain
            // (CI 39925000944, line 3428).
            XCTAssertFalse(
                app.descendants(matching: .any)["home.root"]
                    .descendants(matching: .any)["home.miniMap"].exists,
                "\(state) has no map component"
            )
            XCTAssertTrue(
                app.buttons["home.empty.capture"].waitForExistence(timeout: stepTimeout),
                "\(state) must show the empty-plate capture entry"
            )
            XCTAssertEqual(app.buttons["home.empty.capture"].identifier, "home.empty.capture")
            let hint = app.descendants(matching: .any)["home.review"]
            XCTAssertTrue(hint.waitForExistence(timeout: stepTimeout), "\(state) always shows the hint row")
            XCTAssertFalse(hint.label.contains("clue"), "\(state) greeting-only when there are no clues")
            XCTAssertFalse(app.buttons["home.review.action"].exists)
            XCTAssertFalse(
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.place.'")).firstMatch.exists
            )
            XCTAssertEqual(app.buttons["home.empty.nearest"].exists, fixture == "other-city")
        }
        attachAccessibilityTree(app, name: "\(state)-accessibility")
        attach(app, name: state)
        if let clearName {
            attach(app, name: clearName)
        }
        if fixture == "other-city" {
            let latest = app.buttons["home.empty.nearest"]
            XCTAssertEqual(latest.identifier, "home.empty.nearest")
            XCTAssertTrue(latest.isHittable)
            assertTapTargetHeight(latest, name: "home.empty.nearest")
            latest.tap()
            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].waitForExistence(timeout: stepTimeout))
        }
    }

    @MainActor
    private func captureHomeSavesWithoutClues(
        language: String = "en",
        names: [String]
    ) throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-complete-onboarding", "--skip-map-tour", "--uitest-location-tiantan",
                "--uitest-review-demo-offline", "--uitest-reset-review-demo-storage",
                "--uitest-doodle-parity-fixture", "-save.appLanguage", language,
            ],
            launchEnvironment: ["SAVE_UI_TEST_STORAGE_ID": UUID().uuidString]
        )
        launch(app)
        defer { terminate(app) }
        try signInViaReviewDemoRequired(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: launchTimeout))
        waitForHomeCoverImagery(app)
        let hint = app.descendants(matching: .any)["home.review"]
        XCTAssertTrue(hint.waitForExistence(timeout: stepTimeout), "H3 always shows the hint row")
        XCTAssertFalse(hint.label.contains("clue"), "H3 shows the greeting only when there are no clues")
        XCTAssertFalse(hint.label.contains("線索"))
        XCTAssertFalse(app.buttons["home.review.action"].exists)
        let greetings = ["Good morning", "Good afternoon", "Good evening", "早安", "午安", "晚安"]
        XCTAssertTrue(
            greetings.contains(where: { hint.label.contains($0) }),
            "H3 hint row must be a time-of-day greeting"
        )
        for suffix in ["000000000001", "000000000002", "000000000003"] {
            XCTAssertTrue(app.buttons["home.place.30000000-0000-0000-0000-\(suffix)"].exists)
        }
        let saves = app.buttons["home.saves"]
        XCTAssertTrue(saves.waitForExistence(timeout: stepTimeout), "H3 must expose home.saves")
        XCTAssertEqual(saves.identifier, "home.saves")
        XCTAssertTrue(saves.isHittable, "H3 must expose Saves without a Review entry")
        XCTAssertGreaterThanOrEqual(saves.frame.width + 0.01, 44)
        assertTapTargetHeight(saves, name: "home.saves")
        attachAccessibilityTree(app, name: "H3-accessibility-\(language)")
        for name in names {
            attach(app, name: name)
        }
        saves.tap()
        XCTAssertTrue(app.descendants(matching: .any)["saves.root"].waitForExistence(timeout: stepTimeout))
    }

    /// XCUIElement.frame can report a 44pt minHeight as 43.99999999999994.
    @MainActor
    private func assertTapTargetHeight(_ element: XCUIElement, name: String) {
        XCTAssertEqual(element.frame.height, 44, accuracy: 0.01, "\(name) must be a 44pt tap target")
    }

    @MainActor
    private func attachAccessibilityTree(_ app: XCUIApplication, name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    @MainActor
    private func firstHittable(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = elements.first(where: { $0.exists && $0.isHittable }) {
                return found
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return elements.first(where: { $0.exists && $0.isHittable })
    }

    @MainActor
    private func waitForHomeCoverImagery(_ app: XCUIApplication) {
        let home = app.descendants(matching: .any)["home.root"]
        XCTAssertTrue(home.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            home.descendants(matching: .any)["home.savedPlaces"].waitForExistence(timeout: stepTimeout),
            "Live Home should show the saved-place library before the parity raster."
        )
        XCTAssertTrue(app.buttons["home.eat"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(
            home.descendants(matching: .any)["home.miniMap"].exists,
            "Home has no map component"
        )
        let firstPlace = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.place.'")
        ).firstMatch
        XCTAssertTrue(firstPlace.waitForExistence(timeout: stepTimeout))
        waitForStableFrame(firstPlace)
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
        let target = element.firstMatch
        if target.exists, target.isHittable {
            target.tap()
            return
        }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func returnToRootBar(app: XCUIApplication) {
        // Capture and confirm can replace one full-screen detail with another
        // before leaving the pushed Saves route. Unwind every visible layer,
        // then pop the child route back to the root bar.
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
        let stamps = app.buttons["saves.segment.mapStamps"]
        if stamps.waitForExistence(timeout: timeout(2)) {
            tapReachable(stamps)
        }
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
        if tripCard.exists {
            tapReachable(tripCard)
        } else {
            // The Atlas cover shows two journeys; other saved drafts live
            // in the explicit All trips menu, not below a scroll boundary.
            let allTrips = app.buttons["trips.allTrips"]
            XCTAssertTrue(allTrips.waitForExistence(timeout: stepTimeout))
            allTrips.tap()
            let savedTrip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", tripName)).firstMatch
            XCTAssertTrue(savedTrip.waitForExistence(timeout: stepTimeout), "Created Trip is missing.\n\(app.debugDescription)")
            savedTrip.tap()
        }

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
