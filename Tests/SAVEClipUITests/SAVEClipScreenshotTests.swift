import CoreGraphics
import UIKit
import XCTest

final class SAVEClipScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }
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

        let swiped = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "list-swiped")
        XCTAssertTrue(swiped.descendants(matching: .any)["clip.list.preview"].waitForExistence(timeout: 20))
        XCTAssertFalse(swiped.descendants(matching: .any)["clip.list.swipe"].exists)
        swiped.terminate()
    }

    func test04ListEnglishLight() {
        capture(screen: "list", appearance: .light, language: "en", locale: "en_US", name: "04-list-en-light", identifier: "clip.list.preview")
    }

    func test19ListSavedCountsZhHant() {
        capture(screen: "list-saved", appearance: .light, language: "zh-Hant", locale: "zh_TW", name: "19-list-saved-zh-Hant", identifier: "clip.list.saved")
    }

    func test19bListPartialZhHant() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "list-partial")
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.partial"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.counts"].exists)
        attachScreenshot(app.screenshot(), name: "19b-list-partial-zh-Hant")
        app.terminate()
    }

    func test19bListPartialEnglishDark() {
        let app = launchClip(appearance: .dark, language: "en", locale: "en_US", screen: "list-partial")
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.partial"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.counts"].exists)
        attachScreenshot(app.screenshot(), name: "19b-list-partial-en-dark", appearance: .dark)
        app.terminate()
    }

    func test19ListSavedEnglishDark() {
        let app = launchClip(appearance: .dark, language: "en", locale: "en_US", screen: "list-saved")
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.saved"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.list.counts"].exists)
        attachScreenshot(app.screenshot(), name: "19-list-saved-en-dark", appearance: .dark)
        app.terminate()
    }

    func testListEnglishDark() {
        capture(screen: "list", appearance: .dark, language: "en", locale: "en_US", name: "list-en-dark", identifier: "clip.list.preview")
    }

    func testEmptyListShowsExplanationAndPlaceholderOwnerIsHidden() {
        let empty = launchClip(appearance: .light, language: "en", locale: "en_US", screen: "list-empty")
        XCTAssertTrue(empty.descendants(matching: .any)["clip.error.empty"].waitForExistence(timeout: 20))
        XCTAssertFalse(empty.descendants(matching: .any)["clip.list.preview"].exists)
        attachScreenshot(empty.screenshot(), name: "list-empty-en")
        empty.terminate()
        let placeholder = launchClip(appearance: .light, language: "en", locale: "en_US", screen: "list-placeholder-owner")
        XCTAssertTrue(placeholder.descendants(matching: .any)["clip.list.preview"].waitForExistence(timeout: 20))
        XCTAssertFalse(placeholder.staticTexts["Shared list shared with you"].exists)
        attachScreenshot(placeholder.screenshot(), name: "list-placeholder-owner-en")
        placeholder.terminate()
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

    func test05LinkStatesEnglishDark() {
        for screen in ["loading", "expired", "offline", "server", "malformed"] {
            let app = launchClip(appearance: .dark, language: "en", locale: "en_US", screen: screen)
            let identifier = screen == "loading" ? "clip.loading" : "clip.error.\(screen)"
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20), identifier)
            attachScreenshot(app.screenshot(), name: "05-state-\(screen)-dark", appearance: .dark)
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
        XCTAssertTrue(app.descendants(matching: .any)["clip.cap50.saved"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.cap50.back"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["clip.skoverlay"].exists)
        attachScreenshot(app.screenshot(), name: "cap50-zh-Hant-light")
        app.terminate()
    }

    func testCap50EnglishDark() {
        let app = launchClip(appearance: .dark, language: "en", locale: "en_US", screen: "cap50")
        XCTAssertTrue(app.descendants(matching: .any)["clip.cap50"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.cap50.saved"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        attachScreenshot(app.screenshot(), name: "cap50-en-dark")
        app.terminate()
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

    func testSignInOnePlaceZhHant() {
        let app = launchClip(appearance: .light, language: "zh-Hant", locale: "zh_TW", screen: "signin")
        XCTAssertTrue(app.descendants(matching: .any)["clip.signin"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.signin.continue"].exists)
        attachScreenshot(app.screenshot(), name: "signin-one-zh-Hant")
        app.terminate()
    }

    func testSignInWholeListEnglish() {
        let app = launchClip(appearance: .light, language: "en", locale: "en_US", screen: "signin-list")
        XCTAssertTrue(app.descendants(matching: .any)["clip.signin"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.signin.continue"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        attachScreenshot(app.screenshot(), name: "signin-list-en")
        app.terminate()
    }

    func testSignInOnePlaceEnglishDark() {
        let app = launchClip(appearance: .dark, language: "en", locale: "en_US", screen: "signin")
        XCTAssertTrue(app.descendants(matching: .any)["clip.signin"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["clip.wordmark"].exists)
        attachScreenshot(app.screenshot(), name: "signin-one-en-dark", appearance: .dark)
        app.terminate()
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
        attachScreenshot(app.screenshot(), name: name, appearance: appearance)
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
        let style = appearance == .dark ? "Dark" : "Light"
        let force = appearance == .dark ? "--uitest-force-dark" : "--uitest-force-light"
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-AppleInterfaceStyle", style,
            force,
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

    private func attachScreenshot(
        _ screenshot: XCUIScreenshot,
        name: String,
        appearance: XCUIDevice.Appearance? = nil
    ) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if (appearance == .dark || name.contains("dark")), !name.contains("skoverlay") {
            assertDarkCanvas(screenshot, name: name)
        }
    }

    /// Named-dark captures must actually resolve `ClipCanvas` dark `#1E1C17`.
    /// `XCUIDevice.appearance` alone left CI shots on light paper.
    private func assertDarkCanvas(_ screenshot: XCUIScreenshot, name: String) {
        guard let image = screenshot.image.cgImage else {
            XCTFail("\(name): missing CGImage")
            return
        }
        let points = [(0.03, 0.72), (0.97, 0.72), (0.03, 0.88), (0.97, 0.88)]
        var luminances: [Double] = []
        var samples: [(Int, Int, Int)] = []
        for (nx, ny) in points {
            let x = min(max(Int((Double(image.width) * nx).rounded()), 0), image.width - 1)
            let y = min(max(Int((Double(image.height) * ny).rounded()), 0), image.height - 1)
            guard let rgb = samplePixel(image, x: x, y: y) else { continue }
            samples.append(rgb)
            luminances.append(0.2126 * Double(rgb.0) + 0.7152 * Double(rgb.1) + 0.0722 * Double(rgb.2))
        }
        XCTAssertFalse(luminances.isEmpty, "\(name): no canvas samples")
        let median = luminances.sorted()[luminances.count / 2]
        let note = XCTAttachment(string: "\(name) canvas luminance=\(Int(median.rounded())) samples=\(samples)")
        note.name = "\(name)-canvas-luminance"
        note.lifetime = .keepAlways
        add(note)
        let looksLikeLightPaper = samples.contains { $0.0 > 220 && $0.1 > 210 && $0.2 > 200 }
        XCTAssertFalse(looksLikeLightPaper, "\(name) is labeled dark but sampled light paper #FFF9EB")
        XCTAssertLessThan(
            median,
            90,
            "\(name) is labeled dark but canvas luminance \(Int(median.rounded())) is not near #1E1C17"
        )
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int)? {
        guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let ok = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    private static let placeInvokeURL =
        "https://sav-e-app.vercel.app/p/eyJpZCI6InF1YXJ0ZXItc2hlZXRzLXBpenphLWNsdWIiLCJuYW1lIjoiUXVhcnRlciBTaGVldHMgUGl6emEgQ2x1YiIsImFkZHJlc3MiOiIxMzA1IFBvcnRpYSBTdCwgTG9zIEFuZ2VsZXMsIENBIDkwMDI2IiwibGF0IjozNC4wNzc5LCJsbmciOi0xMTguMjU0MywiY2F0ZWdvcnkiOiJGb29kIiwicmF0aW5nIjo0LjYsInJldmlld0NvdW50Ijo0MTIsInByaWNlUmFuZ2UiOiIkJCIsImhvdXJzIjoiV2VkLVN1biBkaW5uZXIiLCJzb3VyY2VMYWJlbCI6Ikdvb2dsZSIsInNvdXJjZVVSTCI6Imh0dHBzOi8vd3d3Lmdvb2dsZS5jb20vbWFwcy9wbGFjZS9RdWFydGVyK1NoZWVldHMrUGl6emErQ2x1YiIsInBob3RvVVJMcyI6W10sIm5vdGUiOiJTYXZlIHRoaXMgZm9yIGEgc2xvdyBkaW5uZXIgbmlnaHQifQ"

    private static let listInvokeURL =
        "https://sav-e-app.vercel.app/list?d=eyJsaXN0Ijp7ImlkIjoiMjIyMjIyMjItMjIyMi0yMjIyLTIyMjItMjIyMjIyMjIyMjIyIiwidGl0bGUiOiJUb2t5byBjYWZlcyIsIm5vdGUiOiJTYXR1cmRheSB3YWxrIiwib3duZXJEaXNwbGF5TmFtZSI6Ik1pbmEiLCJ2aWV3ZXJSb2xlIjoidmlld2VyIiwiaXRlbXMiOlt7ImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwic291cmNlIjoic2F2ZWRQbGFjZSIsInNvdXJjZUlEIjoicGxhY2UxIiwidGl0bGUiOiJPbmlidXMgQ29mZmVlIiwic3VidGl0bGUiOiJOYWthbWVndXJvIiwibGF0aXR1ZGUiOjM1LjY0NCwibG9uZ2l0dWRlIjoxMzkuNjk5LCJjYXRlZ29yeSI6IkNhZmUiLCJyYXRpbmciOjQuNSwicmV2aWV3Q291bnQiOjEwMCwic291cmNlVVJMIjpudWxsLCJwaG90b1VSTHMiOlsiaHR0cHM6Ly9leGFtcGxlLmNvbS9jb2ZmZWUuanBnIl0sIm5vdGUiOm51bGwsImFkZGVkQnlEaXNwbGF5TmFtZSI6Ik1pbmEiLCJhZGRlZEF0Ijo4MTI1MDU2MDAuMH1dLCJjcmVhdGVkQXQiOjgxMjUwNTYwMC4wLCJ1cGRhdGVkQXQiOjgxMjUwNTYwMC4wfSwicm9sZSI6InZpZXdlciJ9&r=viewer"
}
