import XCTest
import UIKit

final class CityMVPVisualTests: XCTestCase {
    @MainActor
    func testConfirmedPhotoAndCategoryPinsAcrossSceneAndNativeMap() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The bounded runner prepares an empty task-owned simulator fixture.
        // The City Lab entry does not implement the legacy reset argument.
        app.launchArguments = ["--inspect-citylab", "--uitest-location-denied"]
        app.launch(); defer { app.terminate() }
        waitForAlignment(on: app)
        if app.buttons["cityMVP.lighting"].value as? String == "Night" { app.buttons["cityMVP.lighting"].tap() }
        chooseMapMenu("台北 Taipei", on: app)
        waitForMode("Overview", on: app, timeout: 45)
        app.buttons["cityMVP.mode"].tap()
        waitForMode("District", on: app, timeout: 45)
        func captureNormal(_ name: String) {
            // Preserve the full393x852 viewport at its normal logical size;
            // avoid staging dozens of redundant triple-resolution captures.
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
                app.screenshot().image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        func read() -> [String: Any]? {
            let e = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
            guard e.exists, let text = e.value as? String else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        }
        func sample(_ name: String, _ condition: @escaping ([String: Any]) -> Bool) throws -> [String: Any] {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                read().map(condition) ?? false
            }, object: app)
            let result = XCTWaiter.wait(for: [ready], timeout: 45)
            captureNormal(name)
            let value = try XCTUnwrap(read())
            let a = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            a.name = name + "-state"; a.lifetime = .keepAlways; add(a)
            XCTAssertEqual(result, .completed)
            return value
        }
        let initial = try sample("saved-pins-public-context") { $0["sceneReady"] as? Bool == true && $0["projectionAvailable"] as? Bool == true }
        XCTAssertEqual(initial["savedCount"] as? Int, 0)
        let publicPins = try XCTUnwrap(initial["pins"] as? [[String: Any]])
        XCTAssertEqual(publicPins.compactMap { $0["id"] as? String }, ["landmark-101"])
        func selectAndSave(_ id: String, query: String) throws {
            chooseMapMenu("Places 地點", on: app)
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap()
            if let text = search.value as? String, text != search.placeholderValue, !text.isEmpty {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
            }
            search.typeText(query)
            let row = app.buttons["cityMVP.place." + id]
            XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
            let before = try sample("saved-pins-candidate-" + id.replacingOccurrences(of: "/", with: "-")) { $0["selectedID"] as? String == id }
            let details = app.buttons["cityMVP.placeDetails"]
            if details.exists { details.tap() }
            let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save this place", "收藏這個地點"])).firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
            let done = app.buttons["cityMVP.placeDetails.done"]
            if done.exists { done.tap() }
            let confirmed = try sample("saved-pins-confirmed-camera-" + id.replacingOccurrences(of: "/", with: "-")) {
                ($0["pins"] as? [[String: Any]])?.contains { $0["id"] as? String == id && $0["saved"] as? Bool == true && $0["selected"] as? Bool == true } == true
            }
            for key in ["latitude", "longitude", "distance", "heading", "pitch"] {
                XCTAssertEqual(try XCTUnwrap(confirmed[key] as? Double), try XCTUnwrap(before[key] as? Double), accuracy: 0.001, key)
            }
        }
        try selectAndSave("way/234589397", query: "ATT")
        _ = try sample("saved-pins-photo-confirmed") { $0["savedCount"] as? Int == 1 }
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close place", "關閉地點"])).firstMatch
        XCTAssertTrue(close.exists); close.tap()
        let photo = try sample("saved-pins-photo-browse") { ($0["pins"] as? [[String: Any]])?.contains { $0["id"] as? String == "way/234589397" && $0["saved"] as? Bool == true && $0["selected"] as? Bool == false } == true }
        let photoPins = try XCTUnwrap(photo["pins"] as? [[String: Any]])
        XCTAssertEqual(photoPins.filter { $0["id"] as? String == "way/234589397" }.count, 1)
        XCTAssertEqual(photoPins.first { $0["id"] as? String == "way/234589397" }?["photo"] as? Bool, true)
        chooseMapMenu("臺北市政府 Taipei City Hall", on: app)
        waitForMode("District", on: app, timeout: 45)
        try selectAndSave("way/142113976", query: "市政府")
        let selected = try sample("saved-pins-category-confirmed") { $0["savedCount"] as? Int == 2 }
        func assertSelected(_ value: [String: Any], requiredVisible: Bool = false) throws {
            XCTAssertEqual(value["selectedID"] as? String, "way/142113976")
            XCTAssertEqual(value["savedCount"] as? Int, 2)
            let x = try XCTUnwrap(value["selectedPinX"] as? Double)
            let y = try XCTUnwrap(value["selectedPinY"] as? Double)
            let visible = CGRect(x: 0, y: 0, width: 393, height: 852).contains(CGPoint(x: x, y: y))
            if requiredVisible { XCTAssertTrue(visible, "Centered City Hall selection must project into the viewport") }
            if visible {
                let owners = app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin")
                XCTAssertEqual(owners.count, 1)
                XCTAssertEqual(owners.firstMatch.frame.midX, x, accuracy: 2)
                XCTAssertEqual(owners.firstMatch.frame.maxY + 3, y, accuracy: 2)
            }
            if value["projectionAvailable"] as? Bool == true {
                let fit = try XCTUnwrap(value["fitError"] as? Double)
                XCTAssertGreaterThanOrEqual(fit, 0); XCTAssertLessThan(fit, 2)
            }
        }
        try assertSelected(selected, requiredVisible: true)
        let selectedPins = try XCTUnwrap(selected["pins"] as? [[String: Any]])
        XCTAssertEqual(selectedPins.filter { $0["id"] as? String == "way/142113976" }.count, 1)
        XCTAssertEqual(selectedPins.first { $0["id"] as? String == "way/142113976" }?["photo"] as? Bool, false)
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        let before = try XCTUnwrap(selected["distance"] as? Double)
        map.pinch(withScale: 0.68, velocity: -0.6)
        let zoomed = try sample("saved-pins-pinch") { ($0["distance"] as? Double ?? 0) > before * 1.12 }
        try assertSelected(zoomed)
        let heading = try XCTUnwrap(zoomed["heading"] as? Double)
        map.rotate(0.35, withVelocity: 0.6)
        let rotated = try sample("saved-pins-rotate") {
            let delta = abs(($0["heading"] as? Double ?? heading) - heading).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta) > 10
        }
        try assertSelected(rotated)
        let longitude = try XCTUnwrap(rotated["longitude"] as? Double)
        map.coordinate(withNormalizedOffset: .init(dx: 0.4, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: map.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.5)))
        let moved = try sample("saved-pins-after-pan-rotate") { abs(($0["longitude"] as? Double ?? longitude) - longitude) > 0.00001 }
        try assertSelected(moved)
        map.pinch(withScale: 0.06, velocity: -1)
        let far = try sample("saved-pins-native-far") { ($0["distance"] as? Double ?? 0) > 9_100 && $0["projectionAvailable"] as? Bool == false }
        try assertSelected(far)
        close.tap()
        let native = try sample("saved-pins-native-circles") {
            $0["selectedID"] as? String == "" && ($0["pins"] as? [[String: Any]])?.filter { $0["saved"] as? Bool == true }.count == 2
        }
        for pin in try XCTUnwrap(native["pins"] as? [[String: Any]]) {
            let id = try XCTUnwrap(pin["id"] as? String)
            let owners = app.descendants(matching: .any).matching(identifier: "cityMVP.groundPin." + id)
            XCTAssertEqual(owners.count, 1)
            XCTAssertEqual(owners.firstMatch.frame.midX, try XCTUnwrap(pin["x"] as? Double), accuracy: 2)
        }
        chooseMapMenu("台北 Taipei", on: app)
        waitForMode("Overview", on: app, timeout: 45)
        app.buttons["cityMVP.mode"].tap()
        waitForMode("District", on: app, timeout: 45)
        let returned = try sample("saved-pins-scene-return") { ($0["pins"] as? [[String: Any]])?.filter { $0["saved"] as? Bool == true }.count == 2 }
        XCTAssertEqual(Set((returned["pins"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }).count, 3)
        app.buttons["cityMVP.lighting"].tap()
        _ = try sample("saved-pins-night") { $0["night"] as? Bool == true }
    }

    @MainActor
    func testSelectedSavedPinRemainsVisibleOnTheFrontSideOfGlobe() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--inspect-citylab", "--uitest-location-denied"]
        app.launch(); defer { app.terminate() }
        waitForAlignment(on: app)
        chooseMapMenu("台北 Taipei", on: app)
        waitForMode("Overview", on: app, timeout: 45)
        app.buttons["cityMVP.mode"].tap()
        waitForMode("District", on: app, timeout: 45)
        chooseMapMenu("Places 地點", on: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap()
        if let text = search.value as? String, text != search.placeholderValue, !text.isEmpty {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        search.typeText("市政府")
        let row = app.buttons["cityMVP.place.way/142113976"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        // This test is independently runnable: confirm the public candidate
        // through the real UI if an earlier test has not already saved it.
        let details = app.buttons["cityMVP.placeDetails"]
        if details.exists { details.tap() }
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save this place", "收藏這個地點"])).firstMatch
        if save.exists { save.tap() }
        let done = app.buttons["cityMVP.placeDetails.done"]
        if done.exists { done.tap() }
        let stamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Map Stamp")).firstMatch
        XCTAssertTrue(stamp.waitForExistence(timeout: 5))
        chooseMapMenu("世界 World", on: app)
        func read() -> [String: Any]? {
            let element = app.descendants(matching: .any)["cityMVP.previewInspection"].firstMatch
            guard element.exists, let raw = element.value as? String else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = read() else { return false }
            return (value["distance"] as? Double ?? 0) > 30_000_000
                && value["selectedID"] as? String == "way/142113976"
                && (value["savedCount"] as? Int ?? 0) > 0
        }, object: app)
        let result = XCTWaiter.wait(for: [ready], timeout: 45)
        capture(app, "saved-pins-front-side-globe")
        let state = try XCTUnwrap(read())
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: state, options: .sortedKeys), uniformTypeIdentifier: "public.json")
        attachment.name = "saved-pins-front-side-globe-state"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(result, .completed)
        let globeOwner = app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin")
        XCTAssertEqual(globeOwner.count, 1)
        XCTAssertGreaterThan(globeOwner.firstMatch.frame.height, 0)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 393, height: 852).contains(CGPoint(x: globeOwner.firstMatch.frame.midX, y: globeOwner.firstMatch.frame.midY)))
    }

    @MainActor
    func testOrdinaryPreviewCameraAndSelectionAcrossNativeHandoff() throws {
        continueAfterFailure = false
        let app=XCUIApplication()
        // Read-only inspection, with no --verify flags or automatic camera route.
        app.launchArguments=["--inspect-citylab"]
        app.launch();defer { app.terminate() }
        waitForAlignment(on:app)
        let mode=app.buttons["cityMVP.mode"]
        let lighting=app.buttons["cityMVP.lighting"]
        if lighting.value as? String == "Night" { lighting.tap() }
        func read() -> [String:Any]? {
            let element=app.descendants(matching:.any)["cityMVP.previewInspection"].firstMatch
            guard element.exists,let raw=element.value as? String else { return nil }
            return (try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any]
        }
        func sample(_ name:String,condition:@escaping ([String:Any])->Bool) throws -> [String:Any] {
            let ready=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
                guard let value=read() else { return false };return condition(value)
            },object:app)
            let result=XCTWaiter.wait(for:[ready],timeout:45)
            capture(app,name)
            let value=try XCTUnwrap(read())
            let attachment=XCTAttachment(data:try JSONSerialization.data(withJSONObject:value,options:.sortedKeys),uniformTypeIdentifier:"public.json")
            attachment.name=name+"-actual-state";attachment.lifetime = .keepAlways;add(attachment)
            XCTAssertEqual(result,.completed)
            XCTAssertEqual(value["route"] as? String,"preview")
            XCTAssertEqual(value["trace"] as? Bool,false)
            if value["projectionAvailable"] as? Bool == true {
                let fit=try XCTUnwrap(value["fitError"] as? Double)
                XCTAssertGreaterThanOrEqual(fit,0);XCTAssertLessThan(fit,2)
            }
            for key in ["nativeGround","opaqueReveal","materialTone","cloudHandoff","groundOwnership","contextRing","contextLabels"] {
                XCTAssertEqual(value[key] as? Bool,true,key)
            }
            return value
        }
        chooseMapMenu("台北 Taipei",on:app)
        waitForMode("Overview",on:app,timeout:45)
        _=try sample("ordinary-preview-overview") { $0["sceneReady"] as? Bool == true && ($0["contextLabelCount"] as? Int ?? 0)>0 }
        mode.tap();waitForMode("District",on:app)
        chooseMapMenu("Places 地點",on:app)
        let landmark=app.buttons["cityMVP.place.landmark-101"]
        XCTAssertTrue(landmark.waitForExistence(timeout:5));landmark.tap()
        let selected=app.descendants(matching:.any)["cityMVP.selectedGroundPin"].firstMatch
        let near=try sample("ordinary-preview-near") { $0["selectedID"] as? String == "landmark-101" && $0["projectionAvailable"] as? Bool == true }
        func assertPhoto(_ value:[String:Any],requiredVisible:Bool = false) throws {
            let x=try XCTUnwrap(value["selectedPinX"] as? Double), y=try XCTUnwrap(value["selectedPinY"] as? Double)
            let visible=CGRect(x:0,y:0,width:393,height:852).contains(CGPoint(x:x,y:y))
            if requiredVisible {
                XCTAssertTrue(visible,"Centered near selection must actually project into the viewport")
                XCTAssertTrue(selected.exists)
                XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"cityMVP.selectedGroundPin").count,1)
            }
            if visible {
                XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"cityMVP.selectedGroundPin").count,1)
                XCTAssertEqual(selected.frame.midX,x,accuracy:2)
                XCTAssertEqual(selected.frame.maxY+3,y,accuracy:2)
            }
            XCTAssertEqual(value["selectedID"] as? String,"landmark-101")
        }
        try assertPhoto(near,requiredVisible:true)
        let map=app.descendants(matching:.any)["cityMVP.pinchArea"].firstMatch
        let initial=try XCTUnwrap(near["distance"] as? Double)
        map.pinch(withScale:0.66,velocity:-0.6)
        let zoomed=try sample("ordinary-preview-pinch-out") { ($0["distance"] as? Double ?? 0)>initial*1.15 }
        try assertPhoto(zoomed)
        let heading=try XCTUnwrap(zoomed["heading"] as? Double)
        map.rotate(0.4,withVelocity:0.65)
        let rotated=try sample("ordinary-preview-rotate") {
            let delta=abs(($0["heading"] as? Double ?? heading)-heading).truncatingRemainder(dividingBy:360)
            return min(delta,360-delta)>10
        }
        try assertPhoto(rotated)
        let longitude=try XCTUnwrap(rotated["longitude"] as? Double)
        map.coordinate(withNormalizedOffset:.init(dx:0.35,dy:0.5)).press(forDuration:0.1,
            thenDragTo:map.coordinate(withNormalizedOffset:.init(dx:0.65,dy:0.5)))
        let panned=try sample("ordinary-preview-pan") { abs(($0["longitude"] as? Double ?? longitude)-longitude)>0.00001 }
        try assertPhoto(panned)
        let beforeFar=try XCTUnwrap(panned["distance"] as? Double)
        map.pinch(withScale:0.18,velocity:-1.0)
        let far=try sample("ordinary-preview-native-far") {
            ($0["distance"] as? Double ?? 0)>max(9_100,beforeFar*3)
                && $0["projectionAvailable"] as? Bool == false && $0["nativeLabelsQuiet"] as? Bool == false
        }
        try assertPhoto(far)
        let farDistance=try XCTUnwrap(far["distance"] as? Double)
        map.pinch(withScale:3.5,velocity:1.0)
        let returned=try sample("ordinary-preview-return-3d") {
            ($0["distance"] as? Double ?? farDistance)<farDistance*0.5 && $0["projectionAvailable"] as? Bool == true
        }
        try assertPhoto(returned)
        XCTAssertEqual(returned["savedCount"] as? Int,near["savedCount"] as? Int)
        app.buttons["cityMVP.tab.saved"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["cityMVP.savedPage"].firstMatch.waitForExistence(timeout:5))
        app.buttons["cityMVP.tab.passport"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout:5))
        app.buttons["cityMVP.tab.map"].tap()
        let retained=try sample("ordinary-preview-tab-return") { $0["selectedID"] as? String == "landmark-101" }
        for key in ["latitude","longitude","distance","heading","pitch","selectedPinX","selectedPinY"] {
            XCTAssertEqual(try XCTUnwrap(retained[key] as? Double),try XCTUnwrap(returned[key] as? Double),accuracy:0.001,key)
        }
        try assertPhoto(retained)
        lighting.tap()
        let night=try sample("ordinary-preview-night") { $0["night"] as? Bool == true && $0["projectionAvailable"] as? Bool == true }
        try assertPhoto(night)
    }

    @MainActor
    func testMapFirstNavigationAndAgent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        waitForAlignment(on: app)
        let lighting = app.buttons["cityMVP.lighting"]
        let isNight = NSPredicate(format: "value IN %@", ["Night", "夜晚"])
        let isDay = NSPredicate(format: "value IN %@", ["Day", "白天"])
        if isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        capture(app, "01-world")
        chooseMapMenu("台北 Taipei", on: app)
        waitForMode("Overview", on: app, timeout: 45)
        capture(app, "02-taipei")
        mode.tap()
        waitForMode("District", on: app)
        capture(app, "03-xinyi-3d")
        chooseMapMenu("Places 地點", on: app)
        let landmark = app.buttons["cityMVP.place.landmark-101"]
        XCTAssertTrue(landmark.waitForExistence(timeout: 5))
        landmark.tap()
        XCTAssertTrue(landmark.waitForNonExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        capture(app, "04-place-panel")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)], timeout: 5), .completed)
        XCTAssertTrue(panel.exists, "The selected place should stay open while switching to night")
        capture(app, "09-xinyi-night")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        XCTAssertTrue(panel.exists, "The selected place should stay open while switching back to day")
        mode.tap()
        waitForMode("Overview", on: app)
        XCTAssertTrue(panel.exists, "Zooming out should keep the same place selected")
        capture(app, "05-back-to-taipei")

        chooseMapMenu("SAV-E Agent", on: app)
        let input = app.textFields["cityMVP.agent.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Taipei quiet restaurant")
        app.buttons["cityMVP.agent.ask"].tap()
        XCTAssertTrue(app.staticTexts["cityMVP.agent.empty"].waitForExistence(timeout: 5))
        capture(app, "06-agent")
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "完成"])).firstMatch
        XCTAssertTrue(done.exists)
        done.tap()

        mode.tap()
        waitForMode("District", on: app)
        chooseMapMenu("Places 地點", on: app)
        XCTAssertTrue(landmark.waitForExistence(timeout: 5))
        landmark.tap()
        XCTAssertTrue(landmark.waitForNonExistence(timeout: 5))
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        app.buttons["cityMVP.tab.saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.savedPage"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "07-saved")
        app.buttons["cityMVP.tab.map"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 8))
        XCTAssertTrue(panel.exists, "Switching tabs must preserve the selected place, including an unsaved candidate")
        app.buttons["cityMVP.tab.passport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "08-passport")
    }

    @MainActor
    func testSlidingDockKeepsMapCameraAndSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-xinyi", "-cityMVP.night", "NO"]
        app.launch()
        waitForAlignment(on: app)
        chooseMapMenu("台北 Taipei", on: app)
        waitForMode("Overview", on: app)
        let mode = app.buttons["cityMVP.mode"]
        mode.tap()
        waitForMode("District", on: app)
        chooseMapMenu("Places 地點", on: app)
        let landmark = app.buttons["cityMVP.place.landmark-101"]
        XCTAssertTrue(landmark.waitForExistence(timeout: 5))
        landmark.tap()
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let selection = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let camera = mode.value as? String
        let selectedTitle = selection.label
        let anchor = selection.frame
        capture(app, "dock-01-map-before")

        let saved = app.buttons["cityMVP.tab.saved"]
        let map = app.buttons["cityMVP.tab.map"]
        let passport = app.buttons["cityMVP.tab.passport"]
        saved.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.savedPage"].firstMatch.waitForExistence(timeout: 3))
        capture(app, "dock-02-saved")
        XCTAssertTrue(mode.waitForNonExistence(timeout: 3), "Hidden retained map must leave the accessibility tree")
        XCTAssertFalse(panel.exists)
        XCTAssertFalse(selection.exists)
        XCTAssertFalse(app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch.exists)

        // Drag the same lens through the middle slot to the other endpoint.
        saved.press(forDuration: 0.1, thenDragTo: passport)
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.passportPage"].firstMatch.waitForExistence(timeout: 3))
        capture(app, "dock-03-drag-passport")
        let information = app.buttons["cityMVP.passport.mapInformation"]
        if !information.isHittable { app.swipeUp() }
        information.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.mapInformation.selectedSource"].firstMatch.waitForExistence(timeout: 5),
                      "The selected candidate's source must remain reachable in Passport")
        capture(app, "dock-03-selected-source")
        app.buttons["cityMVP.mapInformation.done"].tap()
        map.tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 3))
        XCTAssertTrue(panel.exists)
        XCTAssertEqual(mode.value as? String, camera, "Returning to Map must retain its zoom and scene readiness")
        XCTAssertEqual(selection.label, selectedTitle)
        XCTAssertEqual(selection.frame.midX, anchor.midX, accuracy: 2)
        XCTAssertEqual(selection.frame.midY, anchor.midY, accuracy: 2)
        capture(app, "dock-04-map-return")

        // Cycle destinations sequentially. XCTest waits for idle between taps;
        // this verifies final navigation state, not in-flight spring interruption.
        saved.tap()
        passport.tap()
        map.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertEqual(mode.value as? String, camera)
        XCTAssertEqual(selection.label, selectedTitle)
        capture(app, "dock-05-retargeted")
    }

    @MainActor
    func testCaptureDraftAndPassportInformation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SAVE_UI_TEST_STORAGE_ID"] = "capture-surfaces-" + UUID().uuidString
        app.launchArguments += ["--verify-xinyi"]
        app.launch()
        let passport = app.buttons["cityMVP.tab.passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 15))
        passport.tap()
        capture(app, "surfaces-01-passport")
        let information = app.buttons["cityMVP.passport.mapInformation"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        if !information.isHittable { app.swipeUp() }
        information.tap()
        let done = app.buttons["cityMVP.mapInformation.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "OpenStreetMap")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "AnthonySantiago101")).firstMatch.exists)
        capture(app, "surfaces-02-map-information")
        done.tap()

        app.buttons["搜尋 Search"].tap()
        let search = app.textFields["map.search.input"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["map.search.close"].isHittable)
        capture(app, "surfaces-03-search")
        app.buttons["map.search.close"].tap()

        let addPlace = app.buttons["新增收藏 Add place"]
        XCTAssertTrue(addPlace.isHittable)
        XCTAssertGreaterThanOrEqual(addPlace.frame.width, 44, "The whole visible Add control must be a touch target")
        XCTAssertGreaterThanOrEqual(addPlace.frame.height, 44)
        addPlace.tap()
        let editor = app.textViews["capture.input"]
        capture(app, "surfaces-04-capture-entry")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        editor.tap()
        editor.typeText("Taipei 101 local preview")
        let keyboardDone = app.buttons["capture.keyboardDone"]
        if keyboardDone.exists { keyboardDone.tap() }
        XCTAssertTrue(app.buttons["capture.analyze"].isEnabled)
        capture(app, "surfaces-04-add-clue")
        app.buttons["capture.close"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        app.buttons["新增收藏 Add place"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("Taipei 101 local preview"), "Closing capture must preserve the unsubmitted draft")
        capture(app, "surfaces-05-draft-restored")
        app.buttons["capture.close"].tap()
        app.buttons["cityMVP.tab.saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cityMVP.savedPage"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "surfaces-06-saved")
    }

    @MainActor
    func testLocalFriendsAndTypedMapSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let passport = app.buttons["cityMVP.tab.passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 15))
        passport.tap()
        let friends = app.buttons["cityMVP.passport.friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 5))
        friends.tap()
        let offlineStatus = app.buttons["cityMVP.friends.import"]
        XCTAssertTrue(offlineStatus.waitForExistence(timeout: 5))
        app.buttons["cityMVP.friends.exchange.done"].tap()
        XCTAssertTrue(offlineStatus.waitForNonExistence(timeout: 5))
        XCTAssertTrue(friends.isHittable)

        app.buttons["cityMVP.passport.trips"].tap()
        let tripPassport = app.buttons["root.passport"]
        XCTAssertTrue(tripPassport.waitForExistence(timeout: 5))
        tripPassport.tap()
        XCTAssertTrue(friends.waitForExistence(timeout: 5))

        app.buttons["搜尋 Search"].tap()
        XCTAssertTrue(app.textFields["map.search.input"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Talk to Savvy"].exists)
        app.buttons["map.search.close"].tap()

        let mapFriends = app.buttons["cityMVP.friends"]
        XCTAssertTrue(mapFriends.waitForExistence(timeout: 8))
        mapFriends.tap()
        XCTAssertTrue(offlineStatus.waitForExistence(timeout: 5))
    }

    @MainActor
    func testNativePinchKeepsLandmarkSelectedAcrossDistrict() throws {
        try verifyNativePinchKeepsLandmarkSelectedAcrossDistrict(additionalArguments: [])
    }

    @MainActor
    func testNativeGroundPinchKeepsLandmarkSelectedAcrossDistrict() throws {
        try verifyNativePinchKeepsLandmarkSelectedAcrossDistrict(additionalArguments: ["--verify-native-ground-owner"])
    }

    @MainActor
    func testNativeGroundPinInputDiagnostics() throws {
        try verifyNativePinchKeepsLandmarkSelectedAcrossDistrict(
            additionalArguments: ["--verify-native-ground-owner", "--verify-pin-input"])
    }

    @MainActor
    private func verifyNativePinchKeepsLandmarkSelectedAcrossDistrict(additionalArguments: [String]) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-xinyi", "--verify-xinyi-overview-journey", "-cityMVP.night", "NO"]
        app.launchArguments += additionalArguments
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        waitForAlignment(on: app)
        let lighting = app.buttons["cityMVP.lighting"].value as? String ?? ""
        XCTAssertTrue(["Day", "白天"].contains(lighting), "The overview comparison requires daytime")
        chooseMapMenu("台北 Taipei", on: app)
        let settledOverview = NSPredicate(format: "identifier == %@ AND value MATCHES %@",
                                          "cityMVP.mode", "Overview 2[89][0-9]{2} 100%")
        let reachedOverview = app.buttons.matching(settledOverview).firstMatch.waitForExistence(timeout: 9)
        if !reachedOverview { capture(app, "09-xinyi-overview-unexpected") }
        XCTAssertTrue(reachedOverview, "Expected 2.9 km at full opacity. Observed \(mode.value ?? "unavailable")")
        let unselected = app.buttons["cityMVP.groundPin.landmark-101"]
        XCTAssertTrue(unselected.waitForExistence(timeout: 9))
        if additionalArguments.contains("--verify-pin-input") {
            let bounds = unselected.frame
            let fields: [String: Any] = ["x": bounds.minX, "y": bounds.minY,
                                         "width": bounds.width, "height": bounds.height,
                                         "hittable": unselected.isHittable,
                                         "mode": mode.value as? String ?? "missing"]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
            attachment.name = "pin-input-before-physical-tap"
            attachment.lifetime = .keepAlways
            add(attachment)
            capture(app, "pin-input-before-physical-tap")
        }
        unselected.tap()
        let selection = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        let selectedAfterTap = selection.waitForExistence(timeout: 5)
        if !selectedAfterTap { capture(app, "pin-input-FAIL-after-physical-tap") }
        XCTAssertTrue(selectedAfterTap)
        let panel = app.descendants(matching: .any)["cityMVP.placePanel"].firstMatch
        XCTAssertTrue(panel.exists)
        let title = selection.label
        let initialAnchor = selection.frame
        let pinTitle = app.staticTexts["cityMVP.selectedGroundPinTitle"]
        capture(app, "10-xinyi-modeled-overview")
        XCTAssertTrue(pinTitle.exists)
        XCTAssertGreaterThan(pinTitle.frame.minY, selection.frame.maxY, "The overview title must clear the photo")

        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        XCTAssertTrue(map.exists)
        map.pinch(withScale: 1.95, velocity: 0.72)
        waitForMode("District", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertTrue(panel.exists)
        capture(app, "11-xinyi-district-selected")
        XCTAssertTrue(pinTitle.exists)
        XCTAssertEqual(pinTitle.label, title)
        assertSelectedChromeClearance(on: app, photo: selection, caption: pinTitle, panel: panel)
        XCTAssertLessThan(pinTitle.frame.maxY, selection.frame.minY, "The title should flip above the badge")
        app.buttons["cityMVP.placeDetails"].tap()
        XCTAssertTrue(app.buttons["Save this place"].waitForExistence(timeout: 5))
        capture(app, "11-xinyi-place-details")
        // Source/photo information now lives in Passport rather than on-map.
        for label in ["View source", "Photo: AnthonySantiago101"] {
            let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertFalse(link.exists)
        }
        app.buttons["cityMVP.placeDetails.done"].tap()
        XCTAssertTrue(app.buttons["cityMVP.placeDetails"].waitForExistence(timeout: 5))
        XCTAssertEqual(selection.label, title, "Dismissing details must retain selection")
        map.pinch(withScale: 0.54, velocity: -0.72)
        waitForMode("Overview", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertTrue(panel.exists)
        XCTAssertLessThan(hypot(selection.frame.midX - initialAnchor.midX,
                                selection.frame.maxY - initialAnchor.maxY), 65)
        capture(app, "12-xinyi-overview-after")

        let initialHeading = try XCTUnwrap((map.value as? String).flatMap(Int.init))
        let rotatedHeadings = (0...360).filter { heading in
            let turn = abs(heading - initialHeading)
            return min(turn, 360 - turn) > 10
        }.map(String.init)
        map.rotate(0.55, withVelocity: 0.65)
        let rotated = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND value IN %@", "cityMVP.pinchArea", rotatedHeadings)).firstMatch
        let changedHeading = rotated.waitForExistence(timeout: 6)
        capture(app, "12-xinyi-overview-rotated")
        XCTAssertTrue(changedHeading, "The two-finger rotation must change the camera heading")
        waitForMode("Overview", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)

        // Browse away from the original camera without deselecting the place.
        // The map moves; chrome must adapt without snapping back to101.
        let beforePan = selection.frame
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        waitForMode("Overview", on: app)
        XCTAssertEqual(selection.label, title)
        XCTAssertGreaterThan(hypot(selection.frame.midX - beforePan.midX,
                                   selection.frame.midY - beforePan.midY), 20,
                             "Dragging must move the map rather than return to101")
        assertSelectedChromeClearance(on: app, photo: selection, caption: pinTitle, panel: panel)
        capture(app, "12-xinyi-overview-panned")

        map.pinch(withScale: 0.55, velocity: -0.60)
        // 4,150 m is where the district fade reaches zero. A failed local fit
        // can also show zero opacity, so require the real distance as well.
        let nativeDistance = "(?:41[5-9][0-9]|4[2-9][0-9]{2}|[5-9][0-9]{3}|[1-9][0-9]{4,})"
        let flat = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value MATCHES %@",
                                                    "cityMVP.mode", "Map \(nativeDistance) 0%")).firstMatch
        let reachedFlat = flat.waitForExistence(timeout: 9)
        capture(app, "12-xinyi-native-return")
        XCTAssertTrue(reachedFlat, "Expected the native map at zero model opacity. Observed \(mode.value ?? "unavailable")")
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(panel.staticTexts[title].exists, "The selected place must remain in the card even when panned offscreen")
        if !selection.exists {
            // Free browsing may put the geographic point outside the viewport.
            // Bring it back through a real map pan, never an automatic recenter.
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(
                forDuration: 0.1,
                thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        }
        let returnedSelection = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(returnedSelection.waitForExistence(timeout: 6), "Native map pan must bring the same selected pin back")
        XCTAssertEqual(returnedSelection.label, title)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
        capture(app, "12-xinyi-native-marker-returned")
    }

    @MainActor
    private func assertSelectedChromeClearance(on app: XCUIApplication, photo: XCUIElement,
                                               caption: XCUIElement, panel: XCUIElement) {
        // Check the actual controls, not the layout helper's predicted result.
        // The shelf can be above or below a pin; neither may cover the other.
        XCTAssertFalse(photo.frame.insetBy(dx: -3, dy: -3).intersects(panel.frame), "The card must clear the photo")
        XCTAssertFalse(caption.frame.intersects(panel.frame), "The card must clear the selected caption")
        let dockButtons = [app.buttons["搜尋 Search"], app.buttons["新增收藏 Add place"],
                           app.buttons["cityMVP.tab.saved"], app.buttons["cityMVP.tab.map"],
                           app.buttons["cityMVP.tab.passport"]]
        let dockBounds = dockButtons.reduce(CGRect.null) { $0.union($1.frame) }
        XCTAssertFalse(photo.frame.insetBy(dx: -3, dy: -3).intersects(dockBounds), "The dock must clear the photo")
        XCTAssertFalse(caption.frame.intersects(dockBounds), "The dock must clear the caption")
        XCTAssertGreaterThanOrEqual(panel.frame.minY, 124, "The shelf must clear the top map controls")
        XCTAssertLessThan(panel.frame.maxY, dockBounds.minY, "The card and dock must not overlap each other")
        XCTAssertLessThanOrEqual(dockBounds.maxY, app.frame.maxY - 24, "The dock must leave the native footer visible")
    }

    @MainActor
    private func waitForAlignment(on app: XCUIApplication) {
        let mode = app.buttons["cityMVP.mode"]
        XCTAssertTrue(mode.wait(for: \.isEnabled, toEqual: true, timeout: 15))
        if mode.value as? String == "Alignment unavailable" {
            capture(app, "00-map-alignment-retry")
            XCTAssertEqual(mode.label, "Retry map alignment")
            mode.tap()
            let retryFinished = NSPredicate(format: "identifier == %@ AND enabled == true AND (value BEGINSWITH %@ OR value BEGINSWITH %@ OR value BEGINSWITH %@)",
                                            "cityMVP.mode", "Map", "Overview", "District")
            XCTAssertTrue(app.buttons.matching(retryFinished).firstMatch.waitForExistence(timeout: 15))
        }
        let ready = NSPredicate(format: "identifier == %@ AND enabled == true AND (value BEGINSWITH %@ OR value BEGINSWITH %@ OR value BEGINSWITH %@)",
                                "cityMVP.mode", "Map", "Overview", "District")
        XCTAssertTrue(app.buttons.matching(ready).firstMatch.waitForExistence(timeout: 1),
                      "Map alignment must succeed before testing the district")
    }

    @MainActor
    func testTwoXinyiCornerPreviews() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-xinyi"]
        app.launch()
        let mode = app.buttons["cityMVP.mode"]
        waitForAlignment(on: app)
        let lighting = app.buttons["cityMVP.lighting"]
        let isDay = NSPredicate(format: "value IN %@", ["Day", "白天"])
        let isNight = NSPredicate(format: "value IN %@", ["Night", "夜晚"])
        if isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
        for (name, screenshot) in [
            ("市府路 × 信義路", "13-xinyi-city-hall"),
            ("松智路 × 信義路", "14-xinyi-songzhi"),
            ("臺北市政府 Taipei City Hall", "16-xinyi-civic"),
        ] {
            chooseMapMenu(name, on: app)
            waitForMode("District", on: app)
            capture(app, screenshot)
            if screenshot == "16-xinyi-civic" {
                let daytimeCamera = mode.value as? String
                lighting.tap()
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)],
                                             timeout: 5), .completed)
                XCTAssertEqual(mode.value as? String, daytimeCamera)
                capture(app, "16-xinyi-civic-night-streets")
                lighting.tap()
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)],
                                             timeout: 5), .completed)
                XCTAssertEqual(mode.value as? String, daytimeCamera)
            }
            let viewport = app.windows.firstMatch
            if name.hasPrefix("市府路") {
                viewport.rotate(.pi * 0.85, withVelocity: 2)
            }
            viewport.pinch(withScale: 1.40, velocity: 0.75)
            waitForMode("District", on: app)
            capture(app, "\(screenshot)-closer")
            capture(app, "\(screenshot)-traffic-later")
        }
        if !isNight.evaluate(with: lighting) { lighting.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isNight, object: lighting)], timeout: 5), .completed)
        capture(app, "17-xinyi-civic-night")
        lighting.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isDay, object: lighting)], timeout: 5), .completed)
    }

    @MainActor
    private func chooseMapMenu(_ title: String, on app: XCUIApplication, line: UInt = #line) {
        let menu = app.buttons["cityMVP.city"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8), line: line)
        menu.tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), line: line)
        item.tap()
    }

    @MainActor
    private func waitForMode(_ value: String, on app: XCUIApplication, timeout: TimeInterval = 9, line: UInt = #line) {
        // Re-query the mode in each snapshot: retaining a resolved element across
        // the native/3D update can keep XCTest's pre-transition value cached.
        let matching = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND value BEGINSWITH %@", "cityMVP.mode", value)).firstMatch
        XCTAssertTrue(matching.waitForExistence(timeout: timeout), line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
