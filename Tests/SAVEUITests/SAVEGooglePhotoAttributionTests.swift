import XCTest

/// Real iOS Simulator evidence for PR #306 Google photo attribution (G1–G8).
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
        let carousel = app.descendants(matching: .any)["evidence.googleCarousel"]
        if !carousel.waitForExistence(timeout: stepTimeout) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree-missing-google-carousel"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Google carousel scene did not render. Identifier must live on a leaf, not an AX container.")
        }
        saveEvidence(app, name: "\(appearance)-google-carousel")

        let compactRow = app.buttons["place.photo.attribution.row"]
        if !waitUntilHittable(compactRow) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree-missing-attribution-row"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Compact attribution row missing. Identifier must be on the Button itself.")
        }
        XCTAssertFalse(
            app.buttons["place.photo.attribution.viewOnMaps"].exists,
            "View on Google Maps stays on the full-screen viewer"
        )
        compactRow.tap()
        let viewer = app.descendants(matching: .any)["place.photo.viewer.image"]
        if !viewer.waitForExistence(timeout: stepTimeout) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree-missing-viewer-after-compact-tap"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Compact attribution row must open the full-screen viewer")
        }

        let author = app.buttons["place.photo.attribution.author"]
        XCTAssertTrue(waitUntilHittable(author), "Author tap target missing on viewer")
        author.tap()
        if !app.descendants(matching: .any)["evidence.openedPage.author"]
            .waitForExistence(timeout: stepTimeout) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree-author-opened-maps"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Author tap must open the author page, not Maps. Route on /contrib path, not host.")
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["evidence.openedPage.maps"].exists,
            "Author page screenshot must not be the Maps tab"
        )
        saveEvidence(app, name: "\(appearance)-author-page")

        openScene(app, "fullScreen")
        let maps = app.buttons["place.photo.attribution.viewOnMaps"]
        XCTAssertTrue(waitUntilHittable(maps), "View on Google Maps tap target missing")
        maps.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.openedPage.maps"]
                .waitForExistence(timeout: stepTimeout),
            "Maps tap did not open the Maps page"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["evidence.openedPage.author"].exists,
            "Maps page must not show the author destination"
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
        let logo = app.descendants(matching: .any)["place.photo.attribution.logo"]
        if !logo.waitForExistence(timeout: stepTimeout) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree-missing-attribution-logo"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Standalone logo identifier must not be overwritten by evidence.logoCloseup")
        }
        saveEvidence(app, name: "\(appearance)-logo-closeup")

        openScene(app, "noAuthor")
        XCTAssertTrue(
            app.descendants(matching: .any)["place.photo.carousel.empty"]
                .waitForExistence(timeout: stepTimeout),
            "A Google photo with no author data must fall back to coral"
        )
        XCTAssertFalse(app.buttons["place.photo.attribution.author"].exists)
        saveEvidence(app, name: "\(appearance)-no-author")

        openScene(app, "mixedCard")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.mixedCard"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(app.buttons["place.photo.attribution.row"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["evidence.userPhoto"].exists)
        saveEvidence(app, name: "\(appearance)-mixed-card")

        openScene(app, "mapPins")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.mapPins"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["map.pin.saved.10000000-0000-0000-0000-000000000306"]
                .waitForExistence(timeout: stepTimeout),
            "Map pins must be symbol markers, not Google photos"
        )
        saveEvidence(app, name: "\(appearance)-map-pins")

        openScene(app, "cityPage")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.cityPage"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertFalse(
            app.buttons["place.photo.attribution.row"].exists,
            "City cards must not show an unattributed Google photo row"
        )
        saveEvidence(app, name: "\(appearance)-city-page")

        openScene(app, "reportEntry")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.reportEntry"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            waitUntilHittable(app.buttons["place.photo.attribution.viewOnMaps"]),
            "G8 report entry is View on Google Maps on the viewer"
        )
        saveEvidence(app, name: "\(appearance)-report-entry")

        openScene(app, "homeThumbs")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.homeThumbs"]
                .waitForExistence(timeout: stepTimeout),
            "Retained 52pt photo-stamp components must render in the harness"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.homeThumbs.recentGoogle"]
                .waitForExistence(timeout: stepTimeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.homeThumbs.recentOwn"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.homeThumbs.recentFriend"].exists
        )
        saveEvidence(app, name: "\(appearance)-home-thumbs")
        saveEvidence(app, name: "\(appearance)-home-thumbs-en")

        openScene(app, "homeThumbsZh")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.homeThumbsZh"]
                .waitForExistence(timeout: stepTimeout),
            "Photo-stamp component scene must render in zh-Hant"
        )
        saveEvidence(app, name: "\(appearance)-home-thumbs-zh-Hant")

        openScene(app, "drawerThumbs")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.drawerThumbs"]
                .waitForExistence(timeout: stepTimeout),
            "Drawer search rows must render Google and own thumbs"
        )
        XCTAssertTrue(app.descendants(matching: .any)["evidence.drawer.google"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["evidence.drawer.own"].exists)
        saveEvidence(app, name: "\(appearance)-drawer-thumbs")

        openScene(app, "tripStop")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.tripStop"]
                .waitForExistence(timeout: stepTimeout),
            "Trip stop paper cards must render Google and own thumbs"
        )
        XCTAssertTrue(app.descendants(matching: .any)["evidence.trip.google"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["evidence.trip.own"].exists)
        saveEvidence(app, name: "\(appearance)-trip-stop")

        openScene(app, "originFood")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.originFood"]
                .waitForExistence(timeout: stepTimeout),
            "Origin food cards must render Google and own photos"
        )
        XCTAssertTrue(app.descendants(matching: .any)["evidence.origin.google"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["evidence.origin.own"].exists)
        app.swipeUp()
        saveEvidence(app, name: "\(appearance)-origin-food")

        openScene(app, "atlasThumbs")
        XCTAssertTrue(
            app.descendants(matching: .any)["evidence.atlasThumbs"]
                .waitForExistence(timeout: stepTimeout),
            "Atlas selected-place card must render Google and own thumbs"
        )
        XCTAssertTrue(app.descendants(matching: .any)["evidence.atlas.google"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["evidence.atlas.own"].exists)
        saveEvidence(app, name: "\(appearance)-atlas-thumbs")

        if appearance == "light" {
            openScene(app, "layout375")
            XCTAssertTrue(
                app.descendants(matching: .any)["evidence.layout375"]
                    .waitForExistence(timeout: stepTimeout),
                "375pt layout scene must render every marked surface"
            )
            saveEvidence(app, name: "375-all-surfaces")

            openScene(app, "layoutXXXL")
            XCTAssertTrue(
                app.descendants(matching: .any)["evidence.layoutXXXL"]
                    .waitForExistence(timeout: stepTimeout),
                "XXXL Dynamic Type scene must render every marked surface"
            )
            saveEvidence(app, name: "xxxl-all-surfaces")

            openScene(app, "layoutXSmall")
            XCTAssertTrue(
                app.descendants(matching: .any)["evidence.layoutXSmall"]
                    .waitForExistence(timeout: stepTimeout),
                "Minimum Dynamic Type scene must render every marked surface"
            )
            saveEvidence(app, name: "xsmall-all-surfaces")
        }
    }

    @MainActor
    private func openScene(_ app: XCUIApplication, _ scene: String) {
        let button = app.buttons["evidence.scene.\(scene)"]
        XCTAssertTrue(button.waitForExistence(timeout: stepTimeout), "Scene \(scene) missing")
        if !button.isHittable {
            for _ in 0..<4 where !button.isHittable {
                app.swipeUp()
            }
        }
        if !waitUntilHittable(button) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree-missing-scene-\(scene)"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Scene \(scene) missing")
        }
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
