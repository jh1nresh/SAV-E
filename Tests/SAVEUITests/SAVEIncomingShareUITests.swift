import XCTest

final class SAVEIncomingShareUITests: SAVEUITestCase {
    private let firstURL = URL(string: "savvy://p/share-fixture")!

    @MainActor
    func testPlaceWaitsForVerificationAndExplicitSave() {
        let app = fixture("clip", extra: ["--uitest-incoming-share-unverified"])
        XCUIDevice.shared.system.open(firstURL)
        XCTAssertTrue(app.buttons["incoming.fixture.verify"].waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(saveButton(app).exists)
        app.buttons["incoming.fixture.verify"].tap()
        waitForReceipt(app, name: "Fixture place A")
        app.buttons["Done"].tap()
        assertJournal(app, pending: true, saves: 0)
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        saveButton(app).tap()
        waitForLabel("Saved privately", element: saveButton(app))
        capture(app, name: "incoming-share-confirmed")
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 1)
    }

    @MainActor
    func testShortReceiptRetriesWithoutSaving() {
        let app = fixture("retry")
        XCUIDevice.shared.system.open(firstURL)
        XCTAssertTrue(app.buttons["friendShareReceipt.retry"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(saveButton(app).exists)
        app.buttons["friendShareReceipt.retry"].tap()
        waitForReceipt(app, name: "Fixture place A")
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testMalformedPlaceHasNoSaveAction() {
        let app = fixture("success")
        XCUIDevice.shared.system.open(URL(string: "savvy://p/")!)
        XCTAssertTrue(app.descendants(matching: .any)["friendShareReceipt.unavailable"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(saveButton(app).exists)
        XCTAssertFalse(app.buttons["friendShareReceipt.retry"].exists)
        capture(app, name: "incoming-share-malformed")
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testUnsupportedLocationReferenceHasNoSaveAction() {
        let app = fixture("unknown-reference")
        XCUIDevice.shared.system.open(firstURL)
        XCTAssertTrue(app.descendants(matching: .any)["friendShareReceipt.unavailable"].waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(saveButton(app).exists)
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testFailedSaveKeepsTheClipJournal() {
        let app = fixture("failure")
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        saveButton(app).tap()
        XCTAssertTrue(app.staticTexts["friendShareReceipt.saveError"].waitForExistence(timeout: stepTimeout))
        XCTAssertEqual(saveButton(app).label, "Save to my Savvy")
        app.buttons["Done"].tap()
        assertJournal(app, pending: true, saves: 1)
    }

    @MainActor
    func testOverCapSaveExplainsThatThePlaceStaysPending() {
        let app = fixture("cap")
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        saveButton(app).tap()
        let message = app.staticTexts["friendShareReceipt.saveError"]
        XCTAssertTrue(message.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(message.label.contains("stays pending"))
        XCTAssertEqual(saveButton(app).label, "Save to my Savvy")
        capture(app, name: "incoming-share-cap")
        app.buttons["Done"].tap()
        assertJournal(app, pending: true, saves: 1)
    }

    @MainActor
    func testDuplicateSaveRemainsExplicitAndCannotBeRepeated() {
        let app = fixture("duplicate")
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        saveButton(app).tap()
        waitForLabel("Already saved", element: saveButton(app))
        XCTAssertFalse(saveButton(app).isEnabled)
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 1)
    }

    @MainActor
    func testSameURLNewInvocationRejectsThePreviousCompletion() {
        checkReplacement(secondURL: firstURL, name: "Fixture place A", remainingJournal: false)
    }

    @MainActor
    func testDifferentURLDoesNotAcknowledgeThePreviousJournal() {
        checkReplacement(
            secondURL: URL(string: "savvy://p/share-fixture-b")!,
            name: "Fixture place B", remainingJournal: true
        )
    }

    @MainActor
    func testListCanBeDeferredThenExplicitlyConfirmed() {
        let app = fixture("list")
        XCTAssertTrue(app.buttons["app.handoff.confirmList"].waitForExistence(timeout: stepTimeout))
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 0)
        app.buttons["app.handoff.reviewList"].tap()
        app.buttons["app.handoff.confirmList"].tap()
        assertJournal(app, pending: false, saves: 1)
        XCTAssertTrue(app.staticTexts["app.handoff.confirmationMessage"].exists)
        app.buttons["app.handoff.dismissMessage"].tap()
        XCTAssertFalse(app.staticTexts["app.handoff.confirmationMessage"].exists)
    }

    @MainActor
    func testListCapRetainsTheSelectionForRetry() {
        let app = fixture("list-cap")
        XCTAssertTrue(app.buttons["app.handoff.confirmList"].waitForExistence(timeout: stepTimeout))
        app.buttons["app.handoff.confirmList"].tap()
        let message = app.staticTexts["app.handoff.confirmationMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(message.label.contains("stay pending"))
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 1)
        XCTAssertTrue(app.buttons["app.handoff.reviewList"].exists)
    }

    @MainActor
    func testIncomingPlaceSurvivesAnExistingLanguageSheet() {
        let app = fixture("existing-modal")
        let language = app.buttons["ink.passport.language"]
        XCTAssertTrue(language.waitForExistence(timeout: launchTimeout))
        language.tap()
        let close = app.buttons["ink.language.close"]
        XCTAssertTrue(close.waitForExistence(timeout: stepTimeout))
        XCUIDevice.shared.system.open(firstURL)
        if close.exists, close.isHittable { close.tap() }
        waitForReceipt(app, name: "Fixture place A")
        capture(app, name: "incoming-share-after-language-sheet")
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testIncomingPlaceSurvivesAnExistingParentAlert() {
        let app = fixture("existing-alert")
        let trigger = app.buttons["incoming.fixture.alert"]
        XCTAssertTrue(trigger.waitForExistence(timeout: launchTimeout))
        trigger.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: stepTimeout))
        XCUIDevice.shared.system.open(firstURL)
        let alert = app.alerts.firstMatch
        if alert.exists, alert.isHittable { alert.buttons.firstMatch.tap() }
        waitForReceipt(app, name: "Fixture place A")
        capture(app, name: "incoming-share-after-alert")
        app.buttons["Done"].tap()
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testChineseReceiptKeepsSourceTextAndLargeTypeActions() {
        let app = fixture("clip", extra: [
            "--uitest-incoming-share-zh",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCUIDevice.shared.system.open(firstURL)
        XCTAssertTrue(app.staticTexts["Fixture place A"].waitForExistence(timeout: stepTimeout))
        for _ in 0..<5 where !saveButton(app).isHittable { app.swipeUp() }
        XCTAssertEqual(saveButton(app).label, "存到我的 Savvy")
        XCTAssertTrue(saveButton(app).isHittable)
        XCTAssertGreaterThanOrEqual(saveButton(app).frame.height, 44)
        capture(app, name: "incoming-share-zh-large-type")
        app.buttons["完成"].tap()
        assertJournal(app, pending: true, saves: 0)
    }

    @MainActor
    private func checkReplacement(secondURL: URL, name: String, remainingJournal: Bool) {
        let app = fixture("replacement")
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        saveButton(app).tap()
        waitForLabel("Saving…", element: saveButton(app))
        XCUIDevice.shared.system.open(secondURL)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: stepTimeout))
        waitForLabel("Save to my Savvy", element: saveButton(app))
        saveButton(app).tap()
        waitForLabel("Saved privately", element: saveButton(app))
        capture(app, name: remainingJournal ? "incoming-share-replaced-url" : "incoming-share-replaced-invocation")
        app.buttons["Done"].tap()
        assertJournal(app, pending: remainingJournal, saves: 2)
    }

    @MainActor
    private func fixture(_ scenario: String, extra: [String] = []) -> XCUIApplication {
        let app = makeApp(
            launchArguments: ["--uitest-incoming-share", "--uitest-incoming-share-reset"] + extra,
            launchEnvironment: ["SAVE_INCOMING_SHARE_SCENARIO": scenario]
        )
        launch(app)
        return app
    }

    @MainActor
    private func saveButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "friendShareReceipt.save").firstMatch
    }

    @MainActor
    private func waitForReceipt(_ app: XCUIApplication, name: String) {
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: stepTimeout))
        waitForLabel("Save to my Savvy", element: saveButton(app))
    }

    @MainActor
    private func waitForLabel(_ label: String, element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: stepTimeout))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: stepTimeout), .completed)
    }

    @MainActor
    private func assertJournal(_ app: XCUIApplication, pending: Bool, saves: Int) {
        let counter = app.staticTexts["incoming.fixture.saves"]
        XCTAssertTrue(counter.waitForExistence(timeout: stepTimeout))
        waitForLabel("Saves: \(saves)", element: counter)
        waitForLabel(pending ? "Journal: pending" : "Journal: none", element: app.staticTexts["incoming.fixture.journal"])
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
