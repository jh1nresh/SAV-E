import XCTest

@MainActor
final class DateDemoFlowTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func tapVote(_ id: String, in app: XCUIApplication) {
        let button = app.buttons["demo.vote.\(id)"]
        if !button.isHittable { app.scrollViews["demo.choices"].swipeUp() }
        XCTAssertTrue(button.isHittable, "Vote must be reachable: \(id)")
        button.tap()
    }

    func testTwoPeopleCreateAndAdjustHalfDayWithoutSavingVotes() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication(); app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["demo.beginChoosing"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["demo.search"].isHittable)
        capture(app, "01-friend-recommendations")
        app.buttons["demo.beginChoosing"].tap()
        XCTAssertFalse(app.buttons["demo.generate"].isEnabled)
        for id in ["coffee", "park", "dinner"] { tapVote(id, in: app) }
        capture(app, "02-mutual-choices")
        app.buttons["demo.generate"].tap()
        XCTAssertTrue(app.scrollViews["demo.timeline"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["demo.budgetTotal"].label.replacingOccurrences(of: ",", with: ""), "兩人 NT$1360–1960")
        capture(app, "03-guide-timeline")
        let coffeeBrief = app.buttons["demo.brief.coffee"]
        if !coffeeBrief.isHittable { app.scrollViews["demo.timeline"].swipeUp() }
        coffeeBrief.tap()
        XCTAssertTrue(app.scrollViews["demo.placeInfo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["吃什麼・玩什麼"].exists)
        capture(app, "03b-place-brief")
        app.scrollViews["demo.placeInfo"].swipeUp()
        XCTAssertTrue(app.staticTexts["如果不順利"].exists)
        capture(app, "03b2-budget-and-backup")
        app.buttons["demo.closeBrief"].tap()
        app.buttons["demo.editStart"].tap()
        app.buttons["demo.laterStart"].tap()
        XCTAssertEqual(app.staticTexts["demo.startTime"].label, "14:15")
        app.buttons["demo.confirmStart"].tap()
        let order = app.descendants(matching: .any)["demo.order.park"].firstMatch
        if !order.isHittable { app.scrollViews["demo.timeline"].swipeUp() }
        order.tap(); app.buttons["往前移"].tap()
        let parkBrief = app.buttons["demo.brief.park"]
        if !parkBrief.isHittable { app.scrollViews["demo.timeline"].swipeDown() }
        parkBrief.tap()
        XCTAssertTrue(app.scrollViews["demo.placeInfo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "這次行程第一站")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "由午後小室出發")).firstMatch.exists)
        capture(app, "03c-reordered-first-stop")
        app.buttons["demo.closeBrief"].tap()
        app.buttons["demo.startDate"].tap()
        XCTAssertTrue(app.buttons["demo.nextStop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["demo.editStart"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["demo.order.park"].firstMatch.isEnabled)
        capture(app, "04-next-stop")
        app.buttons["demo.nextStop"].tap()
        app.buttons["demo.tab.saved"].tap()
        XCTAssertEqual(app.staticTexts["demo.savedCount"].label, "2 個收藏")
        XCTAssertTrue(app.buttons["demo.saved.park"].exists)
        XCTAssertFalse(app.buttons["demo.saved.coffee"].exists)
        capture(app, "05-saved-truth")
        app.buttons["demo.tab.passport"].tap()
        XCTAssertTrue(app.staticTexts["尚未記錄到訪"].exists)
        capture(app, "06-passport")
        app.buttons["demo.tab.map"].tap()
        XCTAssertTrue(app.buttons["demo.nextStop"].exists)
        app.buttons["demo.nextStop"].tap()
        app.buttons["demo.nextStop"].tap()
        XCTAssertTrue(app.staticTexts["demo.finished"].waitForExistence(timeout: 5))
        capture(app, "06b-outing-complete")
        app.buttons["demo.search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("咖啡")
        let result = app.buttons["demo.searchResult.coffee"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["demo.savePlace"].waitForExistence(timeout: 5))
        app.buttons["demo.savePlace"].tap(); app.buttons["確認收藏"].tap()
        XCTAssertTrue(app.staticTexts["已收藏 · 示範"].waitForExistence(timeout: 5))
        capture(app, "07-explicit-save")
        app.buttons["demo.closeBrief"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        let done = app.buttons["demo.closeSearch"]
        if done.isHittable {
            done.tap()
        } else {
            // iOS 26's active search mode replaces the navigation toolbar with Close.
            app.buttons["Close"].tap()
            if done.exists && done.isHittable { done.tap() }
        }
        XCTAssertTrue(app.buttons["demo.tab.saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["demo.tab.saved"].isHittable)
        app.buttons["demo.tab.saved"].tap()
        XCTAssertEqual(app.staticTexts["demo.savedCount"].label, "3 個收藏")
        XCTAssertTrue(app.buttons["demo.saved.coffee"].exists)
        capture(app, "08-confirmed-save-in-list")
        XCTAssertFalse(app.buttons["3D"].exists)
    }

    func testDisagreementStaysOutOfPlanAndStaleChoiceNeedsConfirmation() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication(); app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["demo.beginChoosing"].waitForExistence(timeout: 20))
        app.buttons["demo.beginChoosing"].tap()
        app.buttons["demo.person.an"].tap(); tapVote("coffee", in: app)
        app.buttons["demo.person.you"].tap(); tapVote("coffee", in: app)
        XCTAssertFalse(app.buttons["demo.generate"].isEnabled)
        app.buttons["demo.person.an"].tap(); tapVote("coffee", in: app)
        XCTAssertTrue(app.buttons["demo.generate"].isEnabled)
        app.buttons["demo.generate"].tap()
        XCTAssertTrue(app.buttons["demo.startDate"].waitForExistence(timeout: 5))
        app.buttons["demo.step.1"].tap(); tapVote("coffee", in: app)
        app.buttons["demo.step.2"].tap()
        XCTAssertTrue(app.buttons["demo.regenerate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["demo.regenerate"].isEnabled)
        XCTAssertFalse(app.buttons["demo.startDate"].isEnabled)
        capture(app, "08-stale-plan-requires-confirmation")
    }
}
