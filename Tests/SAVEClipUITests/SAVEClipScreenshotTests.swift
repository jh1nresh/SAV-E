import XCTest

final class SAVEClipScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test01PlaceZhHantShortCodeWithSender() {
        capture(screen: "place-sender", appearance: .light, language: "zh-Hant", locale: "zh_TW", name: "01-place-zh-Hant-sender", identifier: "clip.place.preview")
    }

    func test02PlaceEnglishInline() {
        capture(screen: "place-inline", appearance: .light, language: "en", locale: "en_US", name: "02-place-en-inline", identifier: "clip.place.preview")
    }

    func testPlaceZhHantDark() {
        capture(screen: "place-sender", appearance: .dark, language: "zh-Hant", locale: "zh_TW", name: "place-zh-Hant-dark", identifier: "clip.place.preview")
    }

    func testPlaceEnglishDark() {
        capture(screen: "place-inline", appearance: .dark, language: "en", locale: "en_US", name: "place-en-dark", identifier: "clip.place.preview")
    }

    func test03ListZhHantFivePlaces() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "list")
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.preview"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.item.0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.swipe"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.saveAll"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["clip.place.photo"].exists)
        attachScreenshot(app.screenshot(), name: "03-list-zh-Hant-five-places")
        app.terminate()
    }

    func test04ListEnglishLight() {
        capture(screen: "list", appearance: .light, language: "en", locale: "en_US", name: "04-list-en-light", identifier: "clip.list.preview")
    }

    func test19ListSavedCountsZhHant() {
        capture(screen: "list-saved", appearance: .light, language: "zh-Hant", locale: "zh_TW", name: "19-list-saved-zh-Hant", identifier: "clip.list.saved")
    }

    func test19ListCapEnglish() {
        capture(screen: "list-cap", appearance: .light, language: "en", locale: "en_US", name: "19-list-cap-en", identifier: "clip.list.cap")
    }

    func testListEnglishDark() {
        capture(screen: "list", appearance: .dark, language: "en", locale: "en_US", name: "list-en-dark", identifier: "clip.list.preview")
    }

    func test05LinkStatesZhHant() {
        for screen in ["loading", "expired", "offline", "server", "malformed"] {
            let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: screen)
            let identifier = screen == "loading" ? "clip.loading" : "clip.error.\(screen)"
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20), identifier)
            if screen == "offline" || screen == "server" {
                XCTAssertTrue(app.descendants(matching: .any)["clip.error.retry"].exists)
            } else {
                XCTAssertFalse(app.descendants(matching: .any)["clip.error.retry"].exists)
            }
            attachScreenshot(app.screenshot(), name: "05-state-\(screen)")
            app.terminate()
        }
    }

    func test06PlaceMaxDynamicType() {
        let app = launchClip(
            appearance: .light,
            language: "en",
            locale: "en_US",
            screen: "place-inline",
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.preview"].waitForExistence(timeout: 20))
        attachScreenshot(app.screenshot(), name: "06-place-max-dynamic-type")
        app.terminate()
    }

    func testSavedZhHantLight() {
        capture(screen: "saved", appearance: .light, language: "zh-Hant", locale: "zh_TW", name: "saved-zh-Hant-light", identifier: "clip.saved")
    }

    func testSavedEnglishDark() {
        capture(screen: "saved", appearance: .dark, language: "en", locale: "en_US", name: "saved-en-dark", identifier: "clip.saved")
    }

    func testCap50ZhHantLight() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "cap50")
        XCTAssertTrue(app.descendants(matching: .any)["clip.cap50"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.cap50.back"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["clip.skoverlay"].exists)
        attachScreenshot(app.screenshot(), name: "cap50-zh-Hant-light")
        app.terminate()
    }

    func testCap50EnglishDark() {
        capture(screen: "cap50", appearance: .dark, language: "en", locale: "en_US", name: "cap50-en-dark", identifier: "clip.cap50")
    }

    func testDuplicateZhHantLight() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "duplicate")
        XCTAssertTrue(app.descendants(matching: .any)["clip.duplicate"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["clip.skoverlay"].exists)
        attachScreenshot(app.screenshot(), name: "duplicate-zh-Hant-light")
        app.terminate()
    }

    func testDuplicateEnglishDark() {
        capture(screen: "duplicate", appearance: .dark, language: "en", locale: "en_US", name: "duplicate-en-dark", identifier: "clip.duplicate")
    }

    func testSignInFailZhHantLight() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "signin-fail")
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.preview"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.signin.hint"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.open"].exists)
        attachScreenshot(app.screenshot(), name: "signin-fail-zh-Hant-light")
        app.terminate()
    }

    func testSignInFailEnglishDark() {
        capture(screen: "signin-fail", appearance: .dark, language: "en", locale: "en_US", name: "signin-fail-en-dark", identifier: "clip.signin.hint")
    }

    func testSaveFailZhHantLight() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "save-fail")
        XCTAssertTrue(app.descendants(matching: .any)["clip.saveFailed"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.error.retry"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["clip.skoverlay"].exists)
        attachScreenshot(app.screenshot(), name: "save-fail-zh-Hant-light")
        app.terminate()
    }

    func testSaveFailEnglishDark() {
        capture(screen: "save-fail", appearance: .dark, language: "en", locale: "en_US", name: "save-fail-en-dark", identifier: "clip.saveFailed")
    }

    func testOfflineDark() {
        capture(screen: "offline", appearance: .dark, language: "en", locale: "en_US", name: "offline-dark", identifier: "clip.error.offline")
    }

    func testSKOverlayLightZhHant() {
        capture(screen: "skoverlay", appearance: .light, language: "zh-Hant", locale: "zh_TW", name: "skoverlay-zh-Hant-light", identifier: "clip.skoverlay")
    }

    func testSKOverlayDarkEnglish() {
        capture(screen: "skoverlay", appearance: .dark, language: "en", locale: "en_US", name: "skoverlay-en-dark", identifier: "clip.skoverlay")
    }

    func testShareLinksStillOpenWithoutFixture() {
        let app = launchClip(appearance: .light, language: "en", locale: "en_US", url: Self.placeInvokeURL)
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.preview"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.open"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["clip.place.photo"].exists)
        app.terminate()

        let list = launchClip(appearance: .light, language: "en", locale: "en_US", url: Self.listInvokeURL)
        XCTAssertTrue(list.descendants(matching: .any)["clip.list.preview"].waitForExistence(timeout: 20))
        XCTAssertTrue(list.descendants(matching: .any)["clip.list.open"].exists)
        XCTAssertTrue(list.descendants(matching: .any)["clip.list.saveAll"].exists)
        list.terminate()
    }

    private func capture(
        screen: String,
        appearance: XCUIDevice.Appearance,
        language: String,
        locale: String,
        name: String,
        identifier: String
    ) {
        let app = launchClip(appearance: appearance, language: language, locale: locale, screen: screen)
        XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20), identifier)
        attachScreenshot(app.screenshot(), name: name)
        app.terminate()
    }

    private func launchClip(
        appearance: XCUIDevice.Appearance,
        language: String,
        locale: String,
        screen: String? = nil,
        url: String? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        if let screen {
            app.launchArguments += ["--uitest-clip-screen", screen]
        }
        app.launchArguments += extraArguments
        if let url {
            app.launchEnvironment["_XCAppClipURL"] = url
        }
        app.launch()
        return app
    }

    private func attachScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static let placeInvokeURL =
        "https://sav-e-app.vercel.app/p/eyJpZCI6InF1YXJ0ZXItc2hlZXRzLXBpenphLWNsdWIiLCJuYW1lIjoiUXVhcnRlciBTaGVldHMgUGl6emEgQ2x1YiIsImFkZHJlc3MiOiIxMzA1IFBvcnRpYSBTdCwgTG9zIEFuZ2VsZXMsIENBIDkwMDI2IiwibGF0IjozNC4wNzc5LCJsbmciOi0xMTguMjU0MywiY2F0ZWdvcnkiOiJGb29kIiwicmF0aW5nIjo0LjYsInJldmlld0NvdW50Ijo0MTIsInByaWNlUmFuZ2UiOiIkJCIsImhvdXJzIjoiV2VkLVN1biBkaW5uZXIiLCJzb3VyY2VMYWJlbCI6Ikdvb2dsZSIsInNvdXJjZVVSTCI6Imh0dHBzOi8vd3d3Lmdvb2dsZS5jb20vbWFwcy9wbGFjZS9RdWFydGVyK1NoZWVldHMrUGl6emErQ2x1YiIsInBob3RvVVJMcyI6W10sIm5vdGUiOiJTYXZlIHRoaXMgZm9yIGEgc2xvdyBkaW5uZXIgbmlnaHQifQ"

    private static let listInvokeURL =
        "https://sav-e-app.vercel.app/list?d=eyJsaXN0Ijp7ImlkIjoiMjIyMjIyMjItMjIyMi0yMjIyLTIyMjItMjIyMjIyMjIyMjIyIiwidGl0bGUiOiJUb2t5byBjYWZlcyIsIm5vdGUiOiJTYXR1cmRheSB3YWxrIiwib3duZXJEaXNwbGF5TmFtZSI6Ik1pbmEiLCJ2aWV3ZXJSb2xlIjoidmlld2VyIiwiaXRlbXMiOlt7ImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwic291cmNlIjoic2F2ZWRQbGFjZSIsInNvdXJjZUlEIjoicGxhY2UxIiwidGl0bGUiOiJPbmlidXMgQ29mZmVlIiwic3VidGl0bGUiOiJOYWthbWVndXJvIiwibGF0aXR1ZGUiOjM1LjY0NCwibG9uZ2l0dWRlIjoxMzkuNjk5LCJjYXRlZ29yeSI6IkNhZmUiLCJyYXRpbmciOjQuNSwicmV2aWV3Q291bnQiOjEwMCwic291cmNlVVJMIjpudWxsLCJwaG90b1VSTHMiOlsiaHR0cHM6Ly9leGFtcGxlLmNvbS9jb2ZmZWUuanBnIl0sIm5vdGUiOm51bGwsImFkZGVkQnlEaXNwbGF5TmFtZSI6Ik1pbmEiLCJhZGRlZEF0Ijo4MTI1MDU2MDAuMH1dLCJjcmVhdGVkQXQiOjgxMjUwNTYwMC4wLCJ1cGRhdGVkQXQiOjgxMjUwNTYwMC4wfSwicm9sZSI6InZpZXdlciJ9&r=viewer"
}
