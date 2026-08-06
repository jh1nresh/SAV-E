import XCTest

final class SavePetStageVisualTests: SAVEUITestCase {
    @MainActor
    func testAllPresetAndStageVisualsRender() {
        let app = makeApp(
            launchArguments: [
                "--enable-internal-companions",
                "--uitest-pet-stage-gallery",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        XCTAssertTrue(app.descendants(matching: .any)["pet.gallery.root"].waitForExistence(timeout: timeout(15)))

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

    /// Pet P2: the capture celebration feeds the companion. The fixture
    /// replays the stamp + feeding sequence deterministically; frame diffs
    /// prove the pet motion actually renders.
    @MainActor
    func testStampFeedingAnimationRenders() {
        let app = makeApp(
            launchArguments: [
                "--enable-internal-companions",
                "--uitest-stamp-feed-fixture",
                "-save.appLanguage", "en",
            ]
        )
        launch(app)
        XCTAssertTrue(app.descendants(matching: .any)["stampFeed.root"].waitForExistence(timeout: timeout(15)))

        // Replay so we sample from a known point in the sequence.
        let replay = app.descendants(matching: .any)["stampFeed.replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: timeout(10)))
        replay.tap()
        let arrivalFrame = app.screenshot()
        Thread.sleep(forTimeInterval: 0.9)
        let nibbleFrame = app.screenshot()
        XCTAssertNotEqual(
            arrivalFrame.pngRepresentation,
            nibbleFrame.pngRepresentation,
            "Stamp feeding animation did not change the rendered frame"
        )

        for (name, screenshot) in [
            ("stamp-feed-arrival", arrivalFrame),
            ("stamp-feed-nibble", nibbleFrame),
        ] {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
