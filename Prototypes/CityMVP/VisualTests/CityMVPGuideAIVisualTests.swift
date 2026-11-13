import XCTest
import UIKit

final class CityMVPGuideAIVisualTests: XCTestCase {
    @MainActor
    func testDisconnectedReviewSharesOnlyExplicitlySelectedSource() throws {
        continueAfterFailure = false
        let namespace = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_GUIDE_TEST_NAMESPACE"])
        let app = XCUIApplication(); app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = namespace + "-ai"
        app.launch(); defer { app.terminate() }
        let city = app.buttons["cityMVP.city"]
        XCTAssertTrue(city.waitForExistence(timeout: 15)); city.tap()
        app.buttons["SAV-E Agent"].tap()
        let ai = app.buttons["cityMVP.agent.ai"]
        XCTAssertTrue(ai.waitForExistence(timeout: 5)); ai.tap()
        XCTAssertTrue(app.staticTexts["cityMVP.guideAI.notConnected"].waitForExistence(timeout: 5))
        let question = app.textFields["cityMVP.guideAI.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5)); question.tap(); question.typeText("Quiet coffee with window seats")
        app.buttons["cityMVP.guideAI.keyboardDone"].tap()
        let venue = app.buttons["cityMVP.guideAI.place.3C25259E-FC46-460C-860D-9FE5C87EF4C9"]
        for _ in 0..<5 where !venue.isHittable { app.swipeUp() }
        XCTAssertTrue(venue.isHittable); venue.tap()
        let aliceID = "5eb75c08b1099a49dfe2660bfe78a6b2c96ee77d792c7db1131bf538703efb4b"
        let bobID = "cad191915400c0f4989bf6777bf29e62b2c0d455fe02cbbea1e10b9874cdcf6b"
        let alice = app.buttons["cityMVP.guideAI.source." + aliceID]
        for _ in 0..<5 where !alice.exists { app.swipeUp() }
        XCTAssertTrue(alice.waitForExistence(timeout: 5))
        XCTAssertEqual(alice.value as? String, "Not selected", "Choosing a place must not consent to copied source text")
        let review = app.buttons["cityMVP.guideAI.review"]
        for _ in 0..<6 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isHittable); review.tap()
        let preview = app.staticTexts["cityMVP.guideAI.reviewQuestion"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(preview.label, "Quiet coffee with window seats")
        XCTAssertFalse(app.staticTexts["cityMVP.guideAI.reviewSource." + aliceID].exists)
        let send = app.buttons["cityMVP.guideAI.send"]
        for _ in 0..<5 where !send.exists { app.swipeUp() }
        XCTAssertTrue(send.exists); XCTAssertFalse(send.isEnabled, "A disconnected build cannot send or imply AI success")
        capture(app, "guide-ai-review-without-copied-source")
        app.buttons["cityMVP.guideAI.reviewCancel"].tap()
        for _ in 0..<6 where !alice.isHittable { app.swipeDown() }
        XCTAssertTrue(alice.isHittable); alice.tap()
        XCTAssertEqual(alice.value as? String, "Selected")
        for _ in 0..<6 where !review.isHittable { app.swipeUp() }
        review.tap()
        let sharedAlice = app.staticTexts["cityMVP.guideAI.reviewSource." + aliceID]
        XCTAssertTrue(sharedAlice.waitForExistence(timeout: 5))
        XCTAssertEqual(sharedAlice.label, "Alice fixture")
        XCTAssertFalse(app.staticTexts["cityMVP.guideAI.reviewSource." + bobID].exists)
        for _ in 0..<5 where !send.exists { app.swipeUp() }
        XCTAssertFalse(send.isEnabled)
        capture(app, "guide-ai-review-explicit-source-only")
        app.buttons["cityMVP.guideAI.reviewCancel"].tap()
        for _ in 0..<6 where !venue.isHittable { app.swipeDown() }
        venue.tap()
        for _ in 0..<5 where !review.exists { app.swipeUp() }
        XCTAssertFalse(review.isEnabled, "Removing the venue must remove its selected source scope")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
            app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
        }
        let image = XCTAttachment(image: rendered); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
