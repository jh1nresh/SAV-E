import XCTest

final class SAVEUISmokeHarnessTests: SAVEUITestCase {
    @MainActor
    func testRelatedSourcesRequireExplicitTapAndShowReceipt() {
        let app = makeApp(
            launchArguments: [
                "-SAVERelatedSourcesHarness",
            ]
        )
        launch(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["related-sources-harness-root"]
                .waitForExistence(timeout: timeout(10))
        )

        let findSources = app.buttons["drawer.saved.relatedSources.find"]
        XCTAssertTrue(findSources.waitForExistence(timeout: timeout(10)))
        XCTAssertFalse(app.descendants(matching: .any)["drawer.saved.relatedSources.loading"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["drawer.saved.relatedSources.coverage"].exists)

        findSources.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["drawer.saved.relatedSources.coverage"]
                .waitForExistence(timeout: timeout(10))
        )
        let expectedCoverageLabels = [
            "Instagram, searched, 1 results",
            "TikTok, partial, 0 results",
            "YouTube, searched, 0 results",
            "Xiaohongshu, searched, 0 results",
            "Douyin, searched, 0 results",
            "Threads, searched, 0 results",
            "X, failed, 0 results",
        ]
        for label in expectedCoverageLabels {
            XCTAssertTrue(
                app.descendants(matching: .any)[label].exists,
                "Missing coverage receipt: \(label)"
            )
        }
        XCTAssertTrue(app.buttons["drawer.saved.relatedSources.result.instagram.0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["drawer.saved.relatedSources.error"].exists)
    }

    @MainActor
    func testFivePathSmokeHarnessPasses() {
        let app = makeApp(
            launchArguments: [
                "-SAVEUISmokeHarness",
            ]
        )
        launch(app)
        XCTAssertTrue(app.descendants(matching: .any)["smoke-harness-root"].waitForExistence(timeout: timeout(10)))
        assertSmokePass("auth", in: app, budget: timeout(20))
        assertSmokePass("location", in: app)
        assertSmokePass("nearby", in: app)
        assertSmokePass("share", in: app)
        assertSmokePass("review", in: app)
    }

    @MainActor
    private func assertSmokePass(
        _ id: String,
        in app: XCUIApplication,
        budget: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pass = app.descendants(matching: .any)["smoke-\(id)-pass"]
        let fail = app.descendants(matching: .any)["smoke-\(id)-fail"]
        XCTAssertTrue(
            pass.waitForExistence(timeout: budget ?? stepTimeout),
            "Missing smoke pass marker for \(id)",
            file: file,
            line: line
        )
        XCTAssertFalse(fail.exists, "Smoke harness reported failure for \(id)", file: file, line: line)
    }

    /// Written for full-ios. This job does not trigger that suite.
    @MainActor
    func testP5P6MapCardFlipAndSwipeDownCollapse() {
        let app = makeApp(
            launchArguments: [
                "--uitest-map-photo-pin-card",
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
            ]
        )
        launch(app)
        let card = app.descendants(matching: .any)["map.card"]
        XCTAssertTrue(card.waitForExistence(timeout: launchTimeout), "map.card must open on the card fixture")
        XCTAssertTrue(app.descendants(matching: .any)["map.card.beenHere"].exists)
        app.descendants(matching: .any)["map.peek.subtitle"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["map.card.visits"].waitForExistence(timeout: stepTimeout),
            "tap flips to the back"
        )
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(card.waitForNonExistence(timeout: stepTimeout), "swipe-down >60pt must collapse map.card")
    }

    /// Hitch probe. Does not claim a P11 pass. Numbers belong in the XCTest report.
    @MainActor
    func testP11HitchMetricIfSimulatorCanMeasure() throws {
        let app = makeApp(
            launchArguments: [
                "--uitest-map-photo-pin-motion",
                "--uitest-complete-onboarding",
                "--skip-map-tour",
                "--uitest-location-denied",
            ]
        )
        launch(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["map.fixture.motion"].waitForExistence(timeout: launchTimeout)
        )

        if #available(iOS 26.0, *) {
            let metric = XCTHitchMetric(application: app)
            measure(metrics: [metric]) {
                let map = app.descendants(matching: .any)["map.fixture.motion"]
                map.swipeLeft()
                map.swipeRight()
            }
            let note = """
            XCTHitchMetric ran on this simulator. Read the XCTest hitch \
            numbers in the report. This is not a 30-pin live Map budget pass \
            and does not claim P11. If the report has no hitch sample, \
            模擬器無法判定.
            """
            let attachment = XCTAttachment(string: note)
            attachment.name = "p11-hitch-ui-probe"
            attachment.lifetime = .keepAlways
            add(attachment)
            throw XCTSkip("模擬器無法判定：UI hitch probe recorded if the metric emitted a sample; not a P11 pass.")
        }

        if #available(iOS 12.2, *) {
            _ = XCTOSSignpostMetric.scrollDecelerationMetric
            throw XCTSkip("XCTHitchMetric requires iOS 26+. scrollDecelerationMetric exists but this fixture is not a 30-pin live Map scroll. 模擬器無法判定.")
        }
        throw XCTSkip("XCTHitchMetric and scrollDecelerationMetric unavailable. 模擬器無法判定.")
    }
}
