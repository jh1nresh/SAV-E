import XCTest

final class AtlasPostcardScreenshotTests: XCTestCase {
    private let referenceViewport = CGSize(width: 402, height: 874)

    private enum Shot: String, CaseIterable {
        case home
        case saves
        case plan
        case map

        var attachmentName: String {
            "atlas-\(rawValue)"
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureFourLockedScreens() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launchEnvironment["TZ"] = "UTC"
        app.launch()
        waitForScreen("prototype.home", in: app)
        attach(.home, from: app)

        app.buttons["Saves"].tap()
        waitForScreen("prototype.saves", in: app)
        attach(.saves, from: app)

        app.buttons["Trips"].tap()
        waitForScreen("prototype.plan", in: app)
        attach(.plan, from: app)

        app.buttons["Map"].tap()
        waitForScreen("prototype.trip.map", in: app)
        app.buttons["Plan"].tap()
        waitForScreen("prototype.plan", in: app)

        app.buttons["Back"].tap()
        waitForScreen("prototype.home", in: app)
        app.buttons["Map"].tap()
        waitForScreen("prototype.map", in: app)
        attach(.map, from: app)
    }

    @MainActor
    private func waitForScreen(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.otherElements[identifier].waitForExistence(timeout: 10),
            "Expected \(identifier) to be visible",
            file: file,
            line: line
        )
    }

    @MainActor
    private func attach(_ shot: Shot, from app: XCUIApplication) {
        let screenshot = app.screenshot()
        assertReferenceViewport(screenshot, in: app)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = shot.attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func assertReferenceViewport(
        _ screenshot: XCUIScreenshot,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 2),
            "Expected an application window",
            file: file,
            line: line
        )
        guard window.exists else {
            return
        }

        let windowSize = window.frame.size
        XCTAssertEqual(
            windowSize.width,
            referenceViewport.width,
            accuracy: 0.5,
            "Reference screenshots require a 402-point-wide window",
            file: file,
            line: line
        )
        XCTAssertEqual(
            windowSize.height,
            referenceViewport.height,
            accuracy: 0.5,
            "Reference screenshots require an 874-point-high window",
            file: file,
            line: line
        )

        let image = screenshot.image
        XCTAssertEqual(
            image.size.width,
            windowSize.width,
            accuracy: 0.5,
            "Screenshot width must match the application window",
            file: file,
            line: line
        )
        XCTAssertEqual(
            image.size.height,
            windowSize.height,
            accuracy: 0.5,
            "Screenshot height must match the application window",
            file: file,
            line: line
        )

        let horizontalPixelScale = image.size.width * image.scale / windowSize.width
        let verticalPixelScale = image.size.height * image.scale / windowSize.height
        XCTAssertGreaterThanOrEqual(
            horizontalPixelScale,
            1,
            "Screenshot must have a positive pixel scale",
            file: file,
            line: line
        )
        XCTAssertEqual(
            horizontalPixelScale,
            verticalPixelScale,
            accuracy: 0.01,
            "Screenshot must use one uniform Retina pixel scale",
            file: file,
            line: line
        )
    }
}
