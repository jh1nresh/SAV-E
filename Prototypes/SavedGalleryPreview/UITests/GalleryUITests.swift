import XCTest

final class GalleryUITests: XCTestCase {
    @MainActor
    func testLightSwitchDetailAndSearchPreserveGallery() {
        let app = XCUIApplication()
        app.launch()
        let lights = app.buttons["gallery.lights"]
        XCTAssertTrue(lights.waitForExistence(timeout: 10))
        XCTAssertEqual(lights.value as? String, "On")
        capture("gallery-light")
        lights.tap()
        XCTAssertEqual(lights.value as? String, "Off")
        capture("gallery-night")
        lights.tap()
        XCTAssertEqual(lights.value as? String, "On")
        let first = app.buttons["live.library.place.00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(first.exists)
        first.tap()
        let close = app.buttons["preview.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        capture("gallery-place-photo")
        close.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let search = app.textFields["preview.search"]
        search.tap()
        search.typeText("xyz-no-match")
        XCTAssertTrue(app.staticTexts["preview.empty"].waitForExistence(timeout: 3))
        XCTAssertFalse(first.exists)
    }

    @MainActor
    func testLargeTextKeepsPlaceAndLightActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--large-text"]
        app.launch()
        let first = app.buttons["live.library.place.00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(app.buttons["gallery.lights"].isHittable)
        capture("gallery-large-text")
        first.tap()
        XCTAssertTrue(app.buttons["preview.close"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func capture(_ name: String) {
        // Wait for the specified 250–440 ms scene/cord transition before visual evidence.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCordPullAndTorchGesture() {
        let app = XCUIApplication()
        app.launch()
        let bulb = app.buttons["gallery.bulb"]
        XCTAssertTrue(bulb.waitForExistence(timeout: 10))
        let handle = bulb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 90))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: -12, dy: 65)))
        XCTAssertEqual(app.buttons["gallery.lights"].value as? String, "Off")
        let torch = app.descendants(matching: .any).matching(identifier: "gallery.torch").firstMatch
        let first = app.buttons["live.library.place.00000000-0000-0000-0000-000000000001"]
        torch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(first.exists)
        XCTAssertFalse(app.buttons["preview.close"].exists)
        XCTAssertEqual(first.value as? String, "Illuminated")
        capture("gallery-torch-reveal")
    }
}
