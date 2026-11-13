import XCTest
import UIKit

final class CityMVPGuideRetrievalVisualTests: XCTestCase {
    @MainActor
    func testSourceQueryOpensExactSaveAndForgettingUpdatesResults() throws {
        continueAfterFailure = false
        let namespace = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_GUIDE_TEST_NAMESPACE"],
            "Runner must prepare a new, isolated recommendation fixture")
        let app = XCUIApplication()
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = namespace
        app.launch(); defer { app.terminate() }
        let city = app.buttons["cityMVP.city"]
        XCTAssertTrue(city.waitForExistence(timeout: 15)); city.tap()
        app.buttons["SAV-E Agent"].tap()
        let friends = app.buttons["cityMVP.agent.mode.friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 5)); friends.tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cityMVP.agent.friendResult.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Alice fixture")); XCTAssertTrue(result.label.contains("Bob fixture"))
        search("Alice snacks", app: app)
        XCTAssertTrue(app.staticTexts["cityMVP.agent.friends.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(result.exists, "Alice's label cannot be joined to Bob's reason")
        search("Alice coffee", app: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Alice fixture")); XCTAssertFalse(result.label.contains("Bob fixture"))
        for _ in 0..<5 where !result.isHittable { app.swipeUp() }
        XCTAssertTrue(result.isHittable)
        capture(app, "guide-matching-copied-source")
        result.tap()
        XCTAssertTrue(app.buttons["cityMVP.guide.copyAddress"].waitForExistence(timeout: 5), "Open the actual Guide detail before testing its sources")
        let forget = app.buttons["cityMVP.guide.forgetRecommendation.5eb75c08b1099a49dfe2660bfe78a6b2c96ee77d792c7db1131bf538703efb4b"]
        for _ in 0..<8 where !forget.isHittable { app.swipeUp() }
        capture(app, "guide-source-detail-diagnostic")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "guide-source-detail-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(forget.isHittable, "Exact saved-place Guide must expose the matched source")
        XCTAssertTrue(app.staticTexts["Alice fixture"].exists)
        forget.tap()
        XCTAssertTrue(forget.waitForNonExistence(timeout: 5))
        app.buttons["cityMVP.guide.close"].tap()
        XCTAssertTrue(app.staticTexts["cityMVP.agent.friends.empty"].waitForExistence(timeout: 5))
        search("Bob", app: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Bob fixture")); XCTAssertFalse(result.label.contains("Alice fixture"))
        capture(app, "guide-remaining-source-after-forget")
        app.buttons["cityMVP.agent.mode.saved"].tap()
        search("ATT", app: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ATT 4 FUN")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func search(_ query: String, app: XCUIApplication) {
        let clear = app.buttons["cityMVP.agent.clear"]
        if clear.exists { clear.tap() }
        let input = app.textFields["cityMVP.agent.input"]
        input.tap(); input.typeText(query)
        app.buttons["cityMVP.agent.ask"].tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
            app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
