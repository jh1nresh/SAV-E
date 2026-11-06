import XCTest

final class SAVEIncomingShareUITests: SAVEUITestCase {
    private let firstURL = URL(string: "savvy://p/share-fixture")!
    private let listURL = URL(string: "savvy://list?c=fixture-list")!

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
    func testUnsupportedClipJournalLocationStaysPending() {
        let app = fixture("clip-unknown-reference")
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        XCTAssertTrue(app.staticTexts["friendShareReceipt.locationPending"].exists)
        XCTAssertFalse(saveButton(app).isEnabled)
        app.buttons["Done"].tap()
        assertJournal(app, pending: true, saves: 0)
    }

    @MainActor
    func testUnsupportedListJournalLocationStaysPending() {
        let app = fixture("list-unknown-reference")
        XCUIDevice.shared.system.open(listURL)
        let confirm = app.buttons["app.handoff.confirmList"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["app.handoff.locationPending"].exists)
        XCTAssertFalse(confirm.isEnabled)
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 0)
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
        let app = fixture("list", extra: ["--uitest-incoming-share-unverified"])
        XCUIDevice.shared.system.open(listURL)
        let verify = app.buttons["incoming.fixture.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: launchTimeout))
        waitForLabel("Joins: 0", element: app.staticTexts["incoming.fixture.joins"])
        XCTAssertFalse(app.buttons["app.handoff.confirmList"].exists)
        verify.tap()
        XCTAssertTrue(app.buttons["app.handoff.confirmList"].waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Fixture place A"].exists, "The selected Clip snapshot survives an empty joined list.")
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 0)
        waitForLabel("Joins: 1", element: app.staticTexts["incoming.fixture.joins"])
        let review = app.buttons["app.handoff.reviewList"]
        XCTAssertTrue(review.waitForExistence(timeout: stepTimeout))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(review.frame), "The deferred-list action must fit on screen: \(review.frame) in \(window)")
        XCTAssertTrue(review.isHittable)
        capture(app, name: "incoming-share-list-deferred")
        review.tap()
        app.buttons["app.handoff.confirmList"].tap()
        assertJournal(app, pending: false, saves: 1)
        XCTAssertTrue(app.staticTexts["app.handoff.confirmationMessage"].exists)
        app.buttons["app.handoff.dismissMessage"].tap()
        XCTAssertFalse(app.staticTexts["app.handoff.confirmationMessage"].exists)
    }

    @MainActor
    func testDeferredListFooterKeepsHomeActionsUsableWithoutDiagnostics() {
        let app = fixture("list-layout")
        XCUIDevice.shared.system.open(listURL)
        XCTAssertTrue(app.buttons["app.handoff.confirmList"].waitForExistence(timeout: stepTimeout))
        app.buttons["Later"].tap()
        XCTAssertFalse(app.staticTexts["incoming.fixture.saves"].exists)
        let review = app.buttons["app.handoff.reviewList"]
        let arrival = app.buttons["ink.arrived"]
        XCTAssertTrue(waitUntilHittable(review))
        XCTAssertTrue(waitUntilHittable(arrival))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(review.frame), "Review action must fit: \(review.frame) in \(window)")
        XCTAssertTrue(window.contains(arrival.frame), "Home action must fit: \(arrival.frame) in \(window)")
        XCTAssertFalse(review.frame.intersects(arrival.frame), "The pending-list footer must not cover the Home action.")
        capture(app, name: "incoming-list-footer-without-diagnostics")
        arrival.tap()
        let done = app.buttons["ink.checkin.done"]
        XCTAssertTrue(done.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(waitUntilHittable(done))
        done.tap()
        XCTAssertTrue(waitUntilHittable(review))
        review.tap()
        XCTAssertTrue(app.buttons["app.handoff.confirmList"].waitForExistence(timeout: stepTimeout))
    }

    @MainActor
    func testListJoinFailureDoesNotClaimThatTheListWasJoined() {
        let app = fixture("list-join-failure", extra: [
            "--savvy-ink-suite=savvy.incoming-share.join-failure.\(UUID().uuidString)",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ])
        XCUIDevice.shared.system.open(listURL)
        let alert = app.alerts["Could not open list"]
        XCTAssertTrue(alert.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(alert.staticTexts["This list could not be opened. Check your connection and try the link again, or ask the sender for a new link."].exists)
        XCTAssertFalse(app.alerts["Savvy list ready"].exists)
        XCTAssertFalse(app.buttons["app.handoff.confirmList"].exists)
        capture(app, name: "incoming-list-join-failed")
        alert.buttons["OK"].tap()
        assertJournal(app, pending: false, saves: 0)
        waitForLabel("Joins: 1", element: app.staticTexts["incoming.fixture.joins"])
        XCUIDevice.shared.system.open(listURL)
        XCTAssertTrue(alert.waitForExistence(timeout: stepTimeout))
        alert.buttons["OK"].tap()
        waitForLabel("Joins: 2", element: app.staticTexts["incoming.fixture.joins"])
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testSuccessfulListRetryReplacesAnUndismissedFailure() {
        let app = fixture("list-join-recovery", extra: [
            "--savvy-ink-suite=savvy.incoming-share.join-recovery.\(UUID().uuidString)",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ])
        XCUIDevice.shared.system.open(listURL)
        let failure = app.alerts["Could not open list"]
        XCTAssertTrue(failure.waitForExistence(timeout: stepTimeout))
        // Deliberately leave the first failure visible when the retry arrives.
        XCUIDevice.shared.system.open(listURL)
        let ready = app.alerts["Savvy list ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: stepTimeout))
        XCTAssertFalse(failure.exists)
        XCTAssertTrue(ready.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic joined list")).firstMatch.exists)
        XCTAssertFalse(app.buttons["app.handoff.confirmList"].exists)
        capture(app, name: "incoming-list-join-recovered")
        ready.buttons["OK"].tap()
        waitForLabel("Joins: 2", element: app.staticTexts["incoming.fixture.joins"])
        assertJournal(app, pending: false, saves: 0)
    }

    @MainActor
    func testFailedListJoinKeepsTheClipSelectionForExplicitSave() {
        let app = fixture("list-clip-join-failure")
        XCUIDevice.shared.system.open(listURL)
        let confirm = app.buttons["app.handoff.confirmList"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Fixture place A"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        confirm.tap()
        assertJournal(app, pending: false, saves: 1)
        waitForLabel("Joins: 1", element: app.staticTexts["incoming.fixture.joins"])
    }

    @MainActor
    func testListCapRetainsTheSelectionForRetry() {
        let app = fixture("list-cap")
        XCUIDevice.shared.system.open(listURL)
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
    func testPartialListSaveReportsCountsRefreshesAndRetainsSelectionForRetry() {
        let app = fixture("list-partial")
        XCUIDevice.shared.system.open(listURL)
        let confirm = app.buttons["app.handoff.confirmList"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(app.staticTexts["Fixture place B"].exists)
        confirm.tap()
        let message = app.staticTexts["app.handoff.confirmationMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(message.label.contains("Saved 1 of 2"))
        waitForLabel("Refresh requests: 1", element: app.staticTexts["incoming.fixture.refreshes"])
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 1)
        app.buttons["app.handoff.reviewList"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        confirm.tap()
        waitForLabel("Refresh requests: 2", element: app.staticTexts["incoming.fixture.refreshes"])
        XCTAssertTrue(message.label.contains("Saved 0; already saved 1"), "The retry must report the duplicate instead of a second new save")
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 2)
    }

    @MainActor
    func testPartialListParkingFailureStillRefreshesAndKeepsTheJournal() {
        let app = fixture("list-parking-failure")
        XCUIDevice.shared.system.open(listURL)
        let confirm = app.buttons["app.handoff.confirmList"]
        XCTAssertTrue(confirm.waitForExistence(timeout: stepTimeout))
        confirm.tap()
        let message = app.staticTexts["app.handoff.confirmationMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: stepTimeout))
        XCTAssertTrue(message.label.contains("Saved 1; already saved 0"))
        XCTAssertTrue(message.label.contains("Couldn't keep the remaining places"))
        waitForLabel("Refresh requests: 1", element: app.staticTexts["incoming.fixture.refreshes"])
        app.buttons["Later"].tap()
        assertJournal(app, pending: true, saves: 1)
        XCTAssertTrue(app.buttons["app.handoff.reviewList"].exists)
    }

    @MainActor
    func testAccountChangeRejectsASuspendedSaveCompletion() {
        let app = fixture("account-switch")
        XCUIDevice.shared.system.open(firstURL)
        waitForReceipt(app, name: "Fixture place A")
        let save = saveButton(app)
        XCTAssertTrue(waitUntilHittable(save))
        XCTAssertTrue(save.isEnabled)
        capture(app, name: "incoming-account-save-ready")
        save.tap()
        let verify = app.buttons["incoming.fixture.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: stepTimeout))
        verify.tap()
        let complete = app.buttons["incoming.fixture.completePreviousSave"]
        XCTAssertTrue(complete.waitForExistence(timeout: stepTimeout))
        waitForLabel("Returned saves: 0", element: app.staticTexts["incoming.fixture.returnedSaves"])
        complete.tap()
        waitForLabel("Returned saves: 1", element: app.staticTexts["incoming.fixture.returnedSaves"])
        assertJournal(app, pending: true, saves: 1)
        XCTAssertFalse(saveButton(app).exists)
        XCTAssertFalse(app.staticTexts["app.handoff.confirmationMessage"].exists)
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
            launchArguments: ["--uitest-review-demo-offline", "--uitest-incoming-share", "--uitest-incoming-share-reset"] + extra,
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
