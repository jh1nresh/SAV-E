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
}
