import XCTest

/// Real iOS Simulator evidence for PR #306 Google photo attribution (G1–G4).
final class SAVEGooglePhotoAttributionTests: SAVEUITestCase {
    @MainActor
    func testCaptureLightAndDarkEvidence() {
        captureEvidence(appearance: "light", forceArgument: "--uitest-force-light")
        captureEvidence(appearance: "dark", forceArgument: "--uitest-force-dark")
    }

    @MainActor
    private func captureEvidence(appearance: String, forceArgument: String) {
        let app = makeApp(launchArguments: [
            GooglePlacesPhotoAttributionEvidenceLaunch.argument,
            forceArgument,
            "--uitest-complete-onboarding",
            "--skip-map-tour",
        ])
        launch(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.googlePhoto.root"]
                .waitForExistence(timeout: launchTimeout),
            "Attribution evidence harness never appeared."
        )

        openScene(app, "googleCarousel")
        saveEvidence(app, name: "\(appearance)-google-carousel")

        let compactRow = app.buttons["place.photo.attribution.row"]
        XCTAssertTrue(waitUntilHittable(compactRow), "Compact attribution row missing")
        XCTAssertFalse(
            app.buttons["place.photo.attribution.viewOnMaps"].exists,
            "View on Google Maps stays on the full-screen viewer"
        )
        compactRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["place.photo.viewer.image"]
                .waitForExistence(timeout: stepTimeout),
            "Compact attribution row must open the full-screen viewer"
        )

        let author = app.buttons["place.photo.attribution.author"]
        XCTAssertTrue(waitUntilHittable(author), "Author tap target missing on viewer")
        author.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.openedPage"]
                .waitForExistence(timeout: stepTimeout),
            "Author tap did not open a destination page"
        )
        saveEvidence(app, name: "\(appearance)-author-page")

        openScene(app, "fullScreen")
        let maps = app.buttons["place.photo.attribution.viewOnMaps"]
        XCTAssertTrue(waitUntilHittable(maps), "View on Google Maps tap target missing")
        maps.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.openedPage"]
                .waitForExistence(timeout: stepTimeout),
            "Maps tap did not open a destination page"
        )
        saveEvidence(app, name: "\(appearance)-maps-page")

        openScene(app, "userPhoto")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.userPhoto"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertFalse(app.buttons["place.photo.attribution.row"].exists)
        XCTAssertFalse(app.buttons["place.photo.attribution.author"].exists)
        XCTAssertFalse(app.buttons["place.photo.attribution.viewOnMaps"].exists)
        saveEvidence(app, name: "\(appearance)-user-photo")

        openScene(app, "fullScreen")
        XCTAssertTrue(
            app.descendants(matching: .any)["place.photo.viewer.image"]
                .waitForExistence(timeout: stepTimeout)
        )
        saveEvidence(app, name: "\(appearance)-full-screen")

        openScene(app, "logoCloseup")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.logoCloseup"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(app.images["place.photo.attribution.logo"].exists)
        saveEvidence(app, name: "\(appearance)-logo-closeup")

        openScene(app, "noAuthor")
        XCTAssertTrue(
            app.descendants(matching: .any)["place.photo.carousel.empty"]
                .waitForExistence(timeout: stepTimeout),
            "A Google photo with no author data must fall back to coral"
        )
        XCTAssertFalse(app.buttons["place.photo.attribution.author"].exists)
        saveEvidence(app, name: "\(appearance)-no-author")
    }

    @MainActor
    private func openScene(_ app: XCUIApplication, _ scene: String) {
        let button = app.buttons["evidence.scene.\(scene)"]
        XCTAssertTrue(waitUntilHittable(button), "Scene \(scene) missing")
        button.tap()
    }

    @MainActor
    private func saveEvidence(_ app: XCUIApplication, name: String) {
        attach(app, name: name)
        let directory = evidenceDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        if let data = app.screenshot().image.pngData() {
            try? data.write(to: url)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "Failed to write \(url.lastPathComponent)"
        )
    }

    private func evidenceDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["SAVE_GOOGLE_PHOTO_EVIDENCE_DIR"],
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("pr306-google-photo-attribution", isDirectory: true)
    }
}

private enum GooglePlacesPhotoAttributionEvidenceLaunch {
    static let argument = "--uitest-google-photo-attribution"
}
