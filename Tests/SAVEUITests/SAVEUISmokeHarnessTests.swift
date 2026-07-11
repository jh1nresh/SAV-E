import XCTest

final class SAVEUISmokeHarnessTests: XCTestCase {
    @MainActor
    func testFivePathSmokeHarnessPasses() {
        let app = XCUIApplication()
        app.launchArguments.append("-SAVEUISmokeHarness")
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["smoke-harness-root"].waitForExistence(timeout: 10))
        assertSmokePass("auth", in: app, timeout: 20)
        assertSmokePass("location", in: app)
        assertSmokePass("nearby", in: app)
        assertSmokePass("share", in: app)
        assertSmokePass("review", in: app)
    }

    @MainActor
    private func assertSmokePass(
        _ id: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pass = app.descendants(matching: .any)["smoke-\(id)-pass"]
        let fail = app.descendants(matching: .any)["smoke-\(id)-fail"]
        XCTAssertTrue(pass.waitForExistence(timeout: timeout), "Missing smoke pass marker for \(id)", file: file, line: line)
        XCTAssertFalse(fail.exists, "Smoke harness reported failure for \(id)", file: file, line: line)
    }
}
