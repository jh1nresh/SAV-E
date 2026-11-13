import XCTest
import UIKit

final class CityMVPFunctionVisualTests: XCTestCase {
    @MainActor
    func testSavedDetailAccessibilitySizeKeepsBothVisitChoicesReachable() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication(); app.launchArguments = ["--inspect-citylab"]; app.launch()
        addTeardownBlock { @MainActor in
            self.image(app, "neutral-detail-accessibility-terminal")
            app.terminate()
        }
        let saved = app.buttons["cityMVP.tab.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 20)); saved.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ATT 4 FUN")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let name = app.staticTexts["drawer.saved.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8)); XCTAssertTrue(name.isHittable)
        XCTAssertGreaterThan(name.frame.height, 35, "Must actually render larger text, not merely request a content-size setting")
        XCTAssertTrue(app.staticTexts["drawer.saved.state"].isHittable)
        self.image(app, "neutral-detail-accessibility-first-viewport")
        let want = app.buttons["drawer.saved.wantToGo"]
        let visited = app.buttons["drawer.saved.visited"]
        for _ in 0..<6 where !visited.isHittable { app.swipeUp() }
        XCTAssertTrue(want.isHittable && visited.isHittable)
        // AX reports fractional point coordinates; tolerate only floating-point rounding.
        XCTAssertGreaterThanOrEqual(want.frame.height, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(visited.frame.height, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(visited.frame.minY, want.frame.maxY,
                                  "Accessibility sizes stack these choices so their labels do not compete for width")
        XCTAssertTrue(app.frame.contains(want.frame)); XCTAssertTrue(app.frame.contains(visited.frame))
        self.image(app, "neutral-detail-accessibility-visit-options")
        let close = app.buttons["drawer.place.close"]
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForNonExistence(timeout: 10))
    }

    @MainActor
    func testNeutralSavedDetailShowsOriginalMemoryAndActionsInDayAndNight() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication(); app.launchArguments = ["--inspect-citylab"]; app.launch()
        addTeardownBlock { @MainActor in
            self.image(app, "neutral-detail-terminal")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "neutral-detail-terminal-hierarchy"; hierarchy.lifetime = .keepAlways; self.add(hierarchy)
            app.terminate()
        }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        func state() throws -> [String: Any] {
            let raw = try XCTUnwrap(inspector.value as? String)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        }
        func setNight(_ night: Bool) throws {
            if try state()["night"] as? Bool != night { app.buttons["cityMVP.lighting"].tap() }
            let deadline = Date().addingTimeInterval(15)
            var matched = false
            for _ in 0..<12 {
                guard Date() < deadline else { break }
                if try state()["night"] as? Bool == night { matched = true; break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
            XCTAssertTrue(matched)
        }
        let initial = try state()
        let originalNight = try XCTUnwrap(initial["night"] as? Bool)
        let count = try XCTUnwrap(initial["savedCount"] as? Int)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ATT 4 FUN")).firstMatch
        func openActualSave() {
            app.buttons["cityMVP.tab.saved"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 8), "Requires the actual existing save; never seed a fixture to satisfy the UI")
            row.tap()
            XCTAssertTrue(app.descendants(matching: .any)["drawer.saved.prototypeBody"].firstMatch.waitForExistence(timeout: 8))
        }
        func closeToMap() {
            app.buttons["drawer.place.close"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForNonExistence(timeout: 10))
            app.buttons["cityMVP.tab.map"].tap()
            XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        }
        try setNight(false); openActualSave()
        XCTAssertEqual(app.staticTexts["drawer.saved.name"].label, "ATT 4 FUN")
        let address = app.staticTexts["drawer.saved.address"]
        XCTAssertTrue(address.label.contains("松壽路")); XCTAssertTrue(address.isHittable)
        let dayAddress = address.label
        XCTAssertTrue(app.staticTexts["drawer.saved.state"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["drawer.saved.liftedPostcard"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["place.detail.postcardChrome"].firstMatch.exists)
        let close = app.buttons["drawer.place.close"]
        XCTAssertGreaterThanOrEqual(close.frame.width, 44); XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        XCTAssertTrue(app.buttons["home.row.showOnMap"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["drawer.saved.visitIntent"].firstMatch.exists)
        let want = app.buttons["drawer.saved.wantToGo"]
        XCTAssertEqual(want.label, "Want to go")
        XCTAssertGreaterThanOrEqual(want.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["drawer.saved.visited"].frame.height, 44)
        image(app, "neutral-detail-day-first-viewport")
        let edit = app.buttons["drawer.saved.edit"]
        for _ in 0..<4 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        XCTAssertTrue(app.buttons["drawer.saved.delete"].exists)
        let plan = app.buttons["drawer.saved.planAround"]
        for _ in 0..<5 where !plan.isHittable { app.swipeUp() }
        XCTAssertTrue(plan.isHittable); XCTAssertTrue(app.buttons["drawer.saved.addToTrip"].exists)
        let list = app.descendants(matching: .any)["drawer.saved.list"].firstMatch
        for _ in 0..<5 where !list.isHittable { app.swipeUp() }
        XCTAssertTrue(list.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["drawer.saved.relatedSources"].firstMatch.exists)
        XCTAssertFalse(app.buttons["drawer.saved.relatedSources.find"].isEnabled,
                       "This existing save has no confirmed Google identity; restyling must not bypass that boundary")
        image(app, "neutral-detail-management-and-organization")
        closeToMap(); try setNight(true); openActualSave()
        XCTAssertEqual(app.staticTexts["drawer.saved.name"].label, "ATT 4 FUN")
        XCTAssertEqual(dayAddress, app.staticTexts["drawer.saved.address"].label)
        image(app, "neutral-detail-night-first-viewport")
        closeToMap(); try setNight(originalNight)
        XCTAssertEqual(try state()["savedCount"] as? Int, count)
    }

    @MainActor
    func testConfirmedCapturePrivateMemoryAndDeletedMapStayConsistent() throws {
        continueAfterFailure = false
        executionTimeAllowance = 360
        let marker = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LOOP_FIXTURE_NAME"])
        let source = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LOOP_FIXTURE_URL"])
        XCTAssertTrue(marker.hasPrefix("City Loop Fixture "))
        XCTAssertTrue(source.hasPrefix("https://maps.apple.com/"))
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab"]
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = "full-loop-" + UUID().uuidString
        app.launch()
        addTeardownBlock { @MainActor in
            self.image(app, "full-loop-always-terminal")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "full-loop-terminal-hierarchy"; hierarchy.lifetime = .keepAlways; self.add(hierarchy)
            app.terminate()
        }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        func readState() -> [String: Any]? {
            guard inspector.exists, let raw = inspector.value as? String else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        }
        func awaitState(_ condition: ([String: Any]) -> Bool) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(45)
            for _ in 0..<35 {
                guard Date() < deadline else { break }
                if let state = readState(), condition(state) { return state }
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
            }
            return nil
        }
        func returnToMap() {
            // Confirmation/rejection/deletion dismisses the actual cover.
            // Its outgoing AX close node may briefly exist with no hit point.
            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForNonExistence(timeout: 10))
            let map = app.buttons["cityMVP.tab.map"]
            if !map.exists {
                let back = app.navigationBars.buttons["BackButton"].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable); back.tap()
            }
            XCTAssertTrue(map.waitForExistence(timeout: 8)); map.tap()
            XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        }
        func openSavedPlace(named name: String) {
            app.buttons["cityMVP.tab.saved"].tap()
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForExistence(timeout: 8))
        }
        func openFixture() { openSavedPlace(named: marker) }
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        let priorNamesJSON = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LOOP_PRIOR_REVIEW_NAMES"])
        let priorNames = try JSONDecoder().decode([String].self, from: Data(priorNamesJSON.utf8))
        let priorSavedJSON = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LOOP_PRIOR_SAVED_NAMES"])
        let priorSavedNames = try JSONDecoder().decode([String].self, from: Data(priorSavedJSON.utf8))
        let identity = XCTAttachment(string: "confirmed-private-memory-dismissal; priorReviews=\(priorNames.count); priorSaves=\(priorSavedNames.count)")
        identity.name = "full-loop-verifier-identity"; identity.lifetime = .keepAlways; add(identity)
        for prior in priorNames {
            XCTAssertTrue(prior.hasPrefix("City Loop Fixture "))
            app.buttons["cityMVP.tab.saved"].tap()
            let review = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Needs review")).firstMatch
            XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prior)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
            let reject = app.buttons["drawer.review.reject"]
            XCTAssertTrue(reject.waitForExistence(timeout: 8) && reject.isHittable); reject.tap()
            XCTAssertTrue(reject.waitForNonExistence(timeout: 8))
            returnToMap()
        }
        for prior in priorSavedNames {
            XCTAssertTrue(prior.hasPrefix("City Loop Fixture "))
            openSavedPlace(named: prior)
            let delete = app.buttons["drawer.saved.delete"]
            for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
            XCTAssertTrue(delete.isHittable); delete.tap()
            let commit = app.buttons["Delete Place"].firstMatch
            XCTAssertTrue(commit.waitForExistence(timeout: 5)); commit.tap()
            XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForNonExistence(timeout: 10))
            returnToMap()
        }
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let initial = try XCTUnwrap(awaitState {
            $0["sceneReady"] as? Bool == true && $0["projectionAvailable"] as? Bool == true
        })
        let before = try XCTUnwrap(initial["savedCount"] as? Int)
        let originalIDs = Set((initial["pins"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        let addPlace = app.buttons["新增收藏 Add place"]
        XCTAssertTrue(addPlace.isHittable); addPlace.tap()
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(source)
        if app.buttons["capture.keyboardDone"].exists { app.buttons["capture.keyboardDone"].tap() }
        app.buttons["capture.analyze"].tap()
        let notSaved = app.staticTexts["drawer.review.notSaved"]
        XCTAssertTrue(notSaved.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["drawer.review.name"].label.contains(marker))
        let confirm = app.buttons["drawer.review.primaryAction"]
        XCTAssertTrue(confirm.isHittable && confirm.isEnabled)
        image(app, "full-loop-before-explicit-confirmation")
        XCTAssertTrue(["Confirm and save", "確認並儲存"].contains(confirm.label),
                      "The primary action must explicitly save a located candidate, got: \(confirm.label)")
        confirm.tap()
        XCTAssertTrue(notSaved.waitForNonExistence(timeout: 12))
        returnToMap()
        let afterSave = try XCTUnwrap(awaitState { $0["savedCount"] as? Int == before + 1 })
        let savedPins = try XCTUnwrap(afterSave["pins"] as? [[String: Any]])
        // Keep the actual source-confirmed save; no fixture pin or ID is seeded.
        let fixturePin = try XCTUnwrap(savedPins.first {
            guard let id = $0["id"] as? String else { return false }
            return id.hasPrefix("saved:") && !originalIDs.contains(id) && $0["saved"] as? Bool == true
        })
        let pinID = try XCTUnwrap(fixturePin["id"] as? String)
        let checkpoint = XCTAttachment(data: try JSONSerialization.data(withJSONObject: afterSave), uniformTypeIdentifier: "public.json")
        checkpoint.name = "full-loop-actual-map-after-save"; checkpoint.lifetime = .keepAlways; add(checkpoint)
        openFixture()
        let edit = app.buttons["drawer.saved.edit"]
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); edit.tap()
        let note = app.textFields["drawer.saved.edit.note"]
        for _ in 0..<5 where !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.isHittable)
        XCTAssertFalse(app.buttons["drawer.saved.edit.clearNote"].isEnabled,
                       "Fresh source evidence must not populate the private-note field")
        image(app, "full-loop-new-private-note-empty")
        note.tap(); note.typeText("Private note for " + marker)
        let keyboardDone = app.buttons["drawer.saved.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5)); keyboardDone.tap()
        let save = app.buttons["drawer.saved.edit.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        app.buttons["cityMVP.city"].tap()
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let reloaded = try XCTUnwrap(awaitState {
            $0["savedCount"] as? Int == before + 1 && $0["sceneReady"] as? Bool == true
                && ($0["pins"] as? [[String: Any]])?.contains { $0["id"] as? String == pinID } == true
        })
        XCTAssertTrue((reloaded["pins"] as? [[String: Any]])?.contains { $0["id"] as? String == pinID } == true)
        openFixture()
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); edit.tap()
        for _ in 0..<5 where !note.isHittable { app.swipeUp() }
        XCTAssertEqual(note.value as? String, "Private note for " + marker)
        image(app, "full-loop-note-reloaded")
        let delete = app.buttons["drawer.saved.delete"]
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable); delete.tap()
        let deletePlace = app.buttons["Delete Place"].firstMatch
        XCTAssertTrue(deletePlace.waitForExistence(timeout: 5)); deletePlace.tap()
        returnToMap()
        let removed = try XCTUnwrap(awaitState { $0["savedCount"] as? Int == before })
        XCTAssertFalse((removed["pins"] as? [[String: Any]])?.contains { $0["id"] as? String == pinID } == true)
        app.buttons["cityMVP.tab.saved"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.exists)
        app.buttons["cityMVP.tab.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["cityMVP.tab.map"].tap()
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        XCTAssertEqual(readState()?["savedCount"] as? Int, before)
        image(app, "full-loop-fixture-deleted-and-tabs-returned")
    }

    /// Continues the retained actual UI save/edit after the old verifier
    /// incorrectly required district render pins while the map showed Earth.
    @MainActor
    func testRetainedGeneratedSaveReloadsInTaipeiAndDeletesThroughNormalUI() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let marker = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LOOP_RETAINED_NAME"])
        let pinID = try XCTUnwrap(ProcessInfo.processInfo.environment["CITY_LOOP_RETAINED_PIN_ID"])
        XCTAssertTrue(marker.hasPrefix("City Loop Fixture ") && pinID.hasPrefix("saved:"))
        let app = XCUIApplication(); app.launchArguments = ["--inspect-citylab"]; app.launch()
        addTeardownBlock { @MainActor in
            self.image(app, "retained-save-terminal")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "retained-save-hierarchy"; hierarchy.lifetime = .keepAlways; self.add(hierarchy)
            app.terminate()
        }
        let inspector = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
        func state() -> [String: Any]? {
            guard let raw = inspector.value as? String else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        }
        func awaitState(_ predicate: ([String: Any]) -> Bool) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(45)
            for _ in 0..<35 {
                guard Date() < deadline else { break }
                if let value = state(), predicate(value) { return value }
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
            }
            return nil
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 20))
        let before = try XCTUnwrap(state()?["savedCount"] as? Int)
        app.buttons["cityMVP.city"].tap()
        let taipei = app.buttons["台北 Taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 5)); taipei.tap()
        let reloaded = try XCTUnwrap(awaitState {
            $0["sceneReady"] as? Bool == true && ($0["pins"] as? [[String: Any]])?.contains {
                $0["id"] as? String == pinID && $0["saved"] as? Bool == true
            } == true
        })
        let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: reloaded), uniformTypeIdentifier: "public.json")
        metadata.name = "retained-save-exact-pin-after-restart"; metadata.lifetime = .keepAlways; add(metadata)
        app.buttons["cityMVP.tab.saved"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let edit = app.buttons["drawer.saved.edit"]
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); edit.tap()
        let note = app.textFields["drawer.saved.edit.note"]
        for _ in 0..<5 where !note.isHittable { app.swipeUp() }
        XCTAssertEqual(note.value as? String, "Private note for " + marker)
        image(app, "retained-save-note-reloaded")
        let delete = app.buttons["drawer.saved.delete"]
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable); delete.tap()
        let commit = app.buttons["Delete Place"].firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 5)); commit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForNonExistence(timeout: 10))
        XCTAssertFalse(row.exists)
        app.buttons["cityMVP.tab.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["cityMVP.tab.map"].tap()
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        let removed = try XCTUnwrap(awaitState { $0["savedCount"] as? Int == before - 1 })
        XCTAssertFalse((removed["pins"] as? [[String: Any]])?.contains { $0["id"] as? String == pinID } == true)
        image(app, "retained-save-deleted-map")
    }

    @MainActor
    func testUnsubmittedCaptureSurvivesRestartWithRemoteQuotaExhausted() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = "draft-restart-" + UUID().uuidString
        app.launchArguments += ["--uitest-ai-quota-exhausted"]
        app.launch(); defer { image(app, "functions-draft-terminal"); app.terminate() }
        let addPlace = app.buttons["新增收藏 Add place"]
        XCTAssertTrue(addPlace.waitForExistence(timeout: 15)); addPlace.tap()
        let editor = app.textViews["capture.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let draft = "Private unfinished Taipei cafe clue"
        editor.typeText(draft)
        if app.buttons["capture.keyboardDone"].exists { app.buttons["capture.keyboardDone"].tap() }
        XCTAssertTrue(app.buttons["capture.analyze"].isEnabled, "Local text/OCR must not require remote AI quota")
        app.buttons["capture.close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(addPlace.waitForExistence(timeout: 15)); addPlace.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, draft, "A process restart must restore the actual draft")
        image(app, "functions-draft-restored")
        let clearDraft = app.buttons["capture.clearDraft"]
        XCTAssertTrue(clearDraft.isHittable); clearDraft.tap()
        XCTAssertFalse(app.buttons["capture.analyze"].isEnabled)
        app.buttons["capture.close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(addPlace.waitForExistence(timeout: 15)); addPlace.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse((editor.value as? String ?? "").contains(draft), "Explicit draft clear must persist")
    }

    @MainActor
    func testSavedManagementAndFriendExchangeAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); defer { image(app, "functions-management-terminal"); app.terminate() }
        let saved = app.buttons["cityMVP.tab.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15)); saved.tap()
        // These identities were explicitly confirmed by the task's saved-pin
        // journey on this isolated simulator, never the attached iPhone.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "臺北市政府")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["place.detail.root"].firstMatch.waitForExistence(timeout: 8))
        let edit = app.buttons["drawer.saved.edit"]
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); XCTAssertTrue(app.buttons["drawer.saved.delete"].exists)
        image(app, "functions-saved-management")
        edit.tap()
        let note = app.textFields["drawer.saved.edit.note"]
        for _ in 0..<4 where !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.isHittable)
        let clearNote = app.buttons["drawer.saved.edit.clearNote"]
        if clearNote.isEnabled { clearNote.tap() }
        note.tap()
        note.typeText("Local private note fixture")
        let keyboardDone = app.buttons["drawer.saved.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5)); keyboardDone.tap()
        let save = app.buttons["drawer.saved.edit.save"]
        for _ in 0..<3 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(saved.waitForExistence(timeout: 15)); saved.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); edit.tap()
        for _ in 0..<4 where !note.isHittable { app.swipeUp() }
        XCTAssertEqual(note.value as? String, "Local private note fixture", "The local note must survive a process restart")
        app.buttons["drawer.place.close"].tap()
        app.buttons["cityMVP.tab.passport"].tap()
        app.buttons["cityMVP.passport.friends"].tap()
        let open = app.buttons["cityMVP.friends.import"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["cityMVP.friends.sender"].exists)
        let export = app.buttons["cityMVP.friends.export"]
        for _ in 0..<4 where !export.exists { app.swipeUp() }
        XCTAssertTrue(export.exists)
        XCTAssertFalse(export.isEnabled, "Sharing must require explicit selections and reason")
        image(app, "functions-friends-exchange")
        app.buttons["cityMVP.friends.exchange.done"].tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testGuideOriginalAddressCopyCardAndMapAction() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); defer { app.terminate() }
        let menu = app.buttons["cityMVP.city"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15)); menu.tap()
        app.buttons["SAV-E Agent"].tap()
        let input = app.textFields["cityMVP.agent.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("ATT")
        app.buttons["cityMVP.agent.ask"].tap()
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ATT")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        let copy = app.buttons["cityMVP.guide.copyAddress"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        XCTAssertTrue(app.staticTexts["cityMVP.guide.notice"].exists)
        let driver = app.buttons["cityMVP.guide.driverCard"]
        XCTAssertTrue(driver.isEnabled, "The sourced street address includes house number 12")
        if driver.isEnabled {
            driver.tap()
            XCTAssertTrue(app.buttons["cityMVP.guide.copyDriverCard"].waitForExistence(timeout: 5))
            app.buttons["Done"].firstMatch.tap()
        }
        image(app, "functions-guide-original-address")
        let show = app.buttons["cityMVP.guide.showMap"]
        for _ in 0..<5 where !show.isHittable { app.swipeUp() }
        XCTAssertTrue(show.isHittable); show.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "Guide must return to its selected saved place on the map")
    }

    @MainActor
    func testRecommendationFileExportChooserCanBeCanceledWithoutSharing() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        let app = XCUIApplication()
        let namespace = ProcessInfo.processInfo.environment["CITY_FRIEND_TEST_NAMESPACE"]
            ?? "friend-roundtrip-" + UUID().uuidString
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = namespace
        let nonce = String(UUID().uuidString.prefix(8))
        let senderLabel = "Fixture sender " + nonce
        let recommendation = "Quiet coffee\nI recommend the window seats. " + nonce
        let filename = "savvy-friend-" + nonce
        app.launch()
        defer { image(app, "functions-friend-export-terminal"); app.terminate() }
        XCTAssertEqual(app.frame.width, 393, accuracy: 1)
        XCTAssertEqual(app.frame.height, 852, accuracy: 1)
        func hierarchy(_ name: String) {
            image(app, name)
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = name + "-hierarchy"; attachment.lifetime = .keepAlways; add(attachment)
        }
        let passport = app.buttons["cityMVP.tab.passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 15)); passport.tap()
        app.buttons["cityMVP.passport.friends"].tap()
        let sender = app.textFields["cityMVP.friends.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 5)); sender.tap(); sender.typeText(senderLabel)
        let reason = app.textFields["cityMVP.friends.reason"]
        reason.tap(); reason.typeText(recommendation)
        app.buttons["cityMVP.friends.keyboardDone"].tap()
        let venue = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "cityMVP.friends.export.", "ATT 4 FUN")).firstMatch
        XCTAssertTrue(venue.waitForExistence(timeout: 5)); venue.tap()
        let export = app.buttons["cityMVP.friends.export"]
        for _ in 0..<5 where !export.isHittable { app.swipeUp() }
        XCTAssertEqual(venue.value as? String, "Selected", "The selected venue must actually be checked")
        XCTAssertTrue(export.isHittable); XCTAssertTrue(export.isEnabled); export.tap()
        let nativeFilename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(nativeFilename.waitForExistence(timeout: 8))
        hierarchy("functions-friend-before-native-dismissal")
        // iOS26 exposes an AX Other named Cancel at the More button's location,
        // but no visible cancellation button. Dismiss the actual system sheet.
        let panel = app.otherElements["Browse View (Picker)"].firstMatch
        XCTAssertTrue(panel.exists)
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)))
        let dismissed = nativeFilename.waitForNonExistence(timeout: 8)
        hierarchy("functions-friend-after-native-dismissal")
        XCTAssertTrue(dismissed, "Native exporter must actually dismiss")
        XCTAssertTrue(app.buttons["cityMVP.friends.exchange.done"].isHittable)
        XCTAssertFalse(app.buttons["cityMVP.friends.previewExport"].exists, "Dismissal cannot report a completed export")
        for _ in 0..<5 where !export.isHittable { app.swipeUp() }
        export.tap()
        XCTAssertTrue(nativeFilename.waitForExistence(timeout: 8))
        // Never save into iCloud or a third-party provider during this local test.
        let localProvider = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage")).firstMatch
        XCTAssertTrue(localProvider.exists, "Use a local On My iPhone destination only")
        nativeFilename.tap()
        nativeFilename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80) + filename)
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.isHittable); save.tap()
        let preview = app.buttons["cityMVP.friends.previewExport"]
        for _ in 0..<6 where !preview.exists { app.swipeDown() }
        XCTAssertTrue(preview.waitForExistence(timeout: 8), "Actual system Save must complete")
        hierarchy("functions-friend-file-exported")
        let open = app.buttons["cityMVP.friends.import"]
        for _ in 0..<6 where !open.isHittable { app.swipeDown() }
        XCTAssertTrue(open.isHittable); open.tap()
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", filename)).firstMatch
        _ = file.waitForExistence(timeout: 8)
        hierarchy("functions-friend-native-import-picker")
        XCTAssertTrue(file.exists, "Choose the exact file written by the system exporter")
        XCTAssertTrue(file.isHittable); file.tap()
        let received = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cityMVP.friends.receive.")).firstMatch
        for _ in 0..<6 where !received.exists { app.swipeUp() }
        XCTAssertTrue(received.waitForExistence(timeout: 5))
        XCTAssertEqual(received.value as? String, "Not selected", "Import preview cannot select or save")
        received.tap()
        XCTAssertEqual(received.value as? String, "Selected")
        let confirm = app.buttons["cityMVP.friends.confirm"]
        for _ in 0..<5 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable); confirm.tap()
        for _ in 0..<6 where !received.exists { app.swipeDown() }
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            received.exists && received.label.contains("Saved by you") && !received.isEnabled
        }, object: app)
        let savedResult = XCTWaiter.wait(for: [saved], timeout: 8)
        hierarchy("functions-friend-copy-confirmed")
        XCTAssertEqual(savedResult, .completed)
        app.terminate(); app.launch()
        let menu = app.buttons["cityMVP.city"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15)); menu.tap()
        app.buttons["SAV-E Agent"].tap()
        let input = app.textFields["cityMVP.agent.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("ATT")
        app.buttons["cityMVP.agent.ask"].tap()
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ATT 4 FUN")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["cityMVP.guide.copyAddress"].waitForExistence(timeout: 5))
        let source = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "cityMVP.guide.recommendation.")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5), "The new source must survive restart and resolve the saved ID")
        let visibleSender = app.staticTexts[senderLabel]
        let visibleReason = app.staticTexts[recommendation]
        hierarchy("functions-friend-guide-after-restart")
        let visibleBounds = app.frame.insetBy(dx: 16, dy: 16)
        for item in [visibleSender, visibleReason] {
            XCTAssertTrue(item.exists && item.isHittable, "Recommendation text must be visible on opening, not merely present offscreen")
            XCTAssertFalse(item.frame.isEmpty)
            XCTAssertTrue(visibleBounds.contains(item.frame), "The complete sender and reason must fit the initial screen")
        }
    }

    @MainActor
    private func image(_ app: XCUIApplication, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
            app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
