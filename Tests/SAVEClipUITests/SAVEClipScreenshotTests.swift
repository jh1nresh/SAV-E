import XCTest

final class SAVEClipScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlaceCardLightEnglish() {
        capturePlaceCard(appearance: .light, language: "en", locale: "en_US", name: "appclip-place-light-en")
    }

    func testPlaceCardDarkEnglish() {
        capturePlaceCard(appearance: .dark, language: "en", locale: "en_US", name: "appclip-place-dark-en")
    }

    func testPlaceCardLightTraditionalChinese() {
        capturePlaceCard(appearance: .light, language: "zh-Hant", locale: "zh_TW", name: "appclip-place-light-zh-Hant")
    }

    func testPlaceCardDarkTraditionalChinese() {
        capturePlaceCard(appearance: .dark, language: "zh-Hant", locale: "zh_TW", name: "appclip-place-dark-zh-Hant")
    }

    func testShareListLinkOpensJournalPreview() {
        let app = launchClip(
            appearance: .light,
            language: "en",
            locale: "en_US",
            url: Self.listInvokeURL
        )
        let preview = app.descendants(matching: .any)["clip.list.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.open"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["clip.place.photo"].exists)
        attachScreenshot(app.screenshot(), name: "appclip-list-light-en")
        app.terminate()
    }

    private func capturePlaceCard(
        appearance: XCUIDevice.Appearance,
        language: String,
        locale: String,
        name: String
    ) {
        let app = launchClip(
            appearance: appearance,
            language: language,
            locale: locale,
            url: Self.placeInvokeURL
        )
        let preview = app.descendants(matching: .any)["clip.place.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), "place preview missing for \(name)")
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.open"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["clip.place.photo.fallback"].exists)
        attachScreenshot(app.screenshot(), name: name)
        app.terminate()
    }

    private func launchClip(
        appearance: XCUIDevice.Appearance,
        language: String,
        locale: String,
        url: String
    ) -> XCUIApplication {
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launchEnvironment["_XCAppClipURL"] = url
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
        "https://sav-e-app.vercel.app/p/eyJpZCI6InF1YXJ0ZXItc2hlZXRzLXBpenphLWNsdWIiLCJuYW1lIjoiUXVhcnRlciBTaGVldHMgUGl6emEgQ2x1YiIsImFkZHJlc3MiOiIxMzA1IFBvcnRpYSBTdCwgTG9zIEFuZ2VsZXMsIENBIDkwMDI2IiwibGF0IjozNC4wNzc5LCJsbmciOi0xMTguMjU0MywiY2F0ZWdvcnkiOiJGb29kIiwicmF0aW5nIjo0LjYsInJldmlld0NvdW50Ijo0MTIsInByaWNlUmFuZ2UiOiIkJCIsImhvdXJzIjoiV2VkLVN1biBkaW5uZXIiLCJzb3VyY2VMYWJlbCI6Ikdvb2dsZSIsInNvdXJjZVVSTCI6Imh0dHBzOi8vd3d3Lmdvb2dsZS5jb20vbWFwcy9wbGFjZS9RdWFydGVyK1NoZWV0cytQaXp6YStDbHViIiwicGhvdG9VUkxzIjpbXSwibm90ZSI6IlNhdmUgdGhpcyBmb3IgYSBzbG93IGRpbm5lciBuaWdodCJ9"

    /// Embedded SharedListPayload. Dates are Swift `deferredToDate` numbers.
    private static let listInvokeURL =
        "https://sav-e-app.vercel.app/list?d=eyJsaXN0Ijp7ImlkIjoiMjIyMjIyMjItMjIyMi0yMjIyLTIyMjItMjIyMjIyMjIyMjIyIiwidGl0bGUiOiJUb2t5byBjYWZlcyIsIm5vdGUiOiJTYXR1cmRheSB3YWxrIiwib3duZXJEaXNwbGF5TmFtZSI6Ik1pbmEiLCJ2aWV3ZXJSb2xlIjoidmlld2VyIiwiaXRlbXMiOlt7ImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwic291cmNlIjoic2F2ZWRQbGFjZSIsInNvdXJjZUlEIjoicGxhY2UxIiwidGl0bGUiOiJPbmlidXMgQ29mZmVlIiwic3VidGl0bGUiOiJOYWthbWVndXJvIiwibGF0aXR1ZGUiOjM1LjY0NCwibG9uZ2l0dWRlIjoxMzkuNjk5LCJjYXRlZ29yeSI6IkNhZmUiLCJyYXRpbmciOjQuNSwicmV2aWV3Q291bnQiOjEwMCwic291cmNlVVJMIjpudWxsLCJwaG90b1VSTHMiOlsiaHR0cHM6Ly9leGFtcGxlLmNvbS9jb2ZmZWUuanBnIl0sIm5vdGUiOm51bGwsImFkZGVkQnlEaXNwbGF5TmFtZSI6Ik1pbmEiLCJhZGRlZEF0Ijo4MTI1MDU2MDAuMH1dLCJjcmVhdGVkQXQiOjgxMjUwNTYwMC4wLCJ1cGRhdGVkQXQiOjgxMjUwNTYwMC4wfSwicm9sZSI6InZpZXdlciJ9&r=viewer"
}
