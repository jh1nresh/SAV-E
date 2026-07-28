import XCTest

@MainActor
final class AtlasPostcardScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        XCTAssertTrue(app.otherElements["prototype.home"].waitForExistence(timeout: 10))
    }

    func testCaptureFourLockedScreens() {
        attach("01-home-little-atlas")

        app.buttons["Saves"].tap()
        XCTAssertTrue(app.staticTexts["YOUR PLACE MEMORY"].waitForExistence(timeout: 5))
        attach("02-saves-postcard-pocket")

        app.buttons["Trips"].tap()
        XCTAssertTrue(app.staticTexts["Tokyo highlights"].waitForExistence(timeout: 5))
        attach("03-trip-plan-little-atlas")

        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["3 clues need your help"].waitForExistence(timeout: 5))
        app.buttons["Map"].tap()
        XCTAssertTrue(app.staticTexts["18 Map Stamps"].waitForExistence(timeout: 5))
        attach("04-root-map-little-atlas")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
