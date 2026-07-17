import XCTest

final class SavePetStageVisualTests: XCTestCase {
    @MainActor
    func testAllPresetAndStageVisualsRender() {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-pet-stage-gallery",
            "-save.appLanguage", "en",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["pet.gallery.root"].waitForExistence(timeout: 15))

        for stage in ["hatchling", "companion", "guardian"] {
            for preset in ["sprout", "spark", "cloud"] {
                XCTAssertTrue(
                    app.descendants(matching: .any)["pet.gallery.\(stage).\(preset)"].exists,
                    "Missing \(stage) \(preset) pet visual"
                )
            }
        }

        let firstFrame = app.screenshot()
        Thread.sleep(forTimeInterval: 0.7)
        let secondFrame = app.screenshot()
        XCTAssertNotEqual(
            firstFrame.pngRepresentation,
            secondFrame.pngRepresentation,
            "Idle pet animation did not change the rendered frame"
        )

        for (name, screenshot) in [
            ("pet-stage-visual-gallery-start", firstFrame),
            ("pet-stage-visual-gallery-motion", secondFrame),
        ] {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
