import XCTest

/// One variable: the extra labeled snapshot is present or absent. Each method
/// registers one control app and one candidate app, then steps real fixture UI.
final class CityNativeGroundVisualTests: XCTestCase {
    @MainActor
    func testSolidRevealRendererWithoutMapRegistration() throws {
        try verifySolidRenderer(materialTone: false)
    }

    @MainActor
    func testMaterialToneRendererWithoutMapRegistration() throws {
        try verifySolidRenderer(materialTone: true)
    }

    @MainActor
    private func verifySolidRenderer(materialTone: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-start-day", "--verify-native-ground-owner",
                               "--verify-opaque-reveal", "--verify-solid-reveal-preview"]
        if materialTone { app.launchArguments.append("--verify-material-tone") }
        app.launch()
        defer { app.terminate() }
        let ready = app.staticTexts["cityMVP.solidPreview.ready"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Ready"), object: ready)
        let preparation = XCTWaiter.wait(for: [expectation], timeout: 45)
        if preparation != .completed { capture(app, "solid-renderer-FAIL-preparation") }
        XCTAssertEqual(preparation, .completed)
        func assertApplied(_ phase: Int, night: Bool) throws {
            let surface = app.descendants(matching: .any)["cityMVP.solidPreview.surface"].firstMatch
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(
                format: "value CONTAINS %@ AND value CONTAINS %@ AND value CONTAINS %@",
                "\"phase\":\(phase)", "\"night\":\(night ? "true" : "false")", "\"installed\":true"), object: surface)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
            let raw = try XCTUnwrap(surface.value as? String)
            let data = try XCTUnwrap(raw.data(using: .utf8))
            let sample = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(try XCTUnwrap(sample["width"] as? Double), 393, accuracy: 1)
            XCTAssertGreaterThan(try XCTUnwrap(sample["height"] as? Double), 500)
            XCTAssertEqual(sample["materialTone"] as? Bool, materialTone)
            XCTAssertEqual(sample["syntheticPitch"] as? Int, 35)
            XCTAssertEqual(sample["syntheticHeading"] as? Int, 20)
            XCTAssertEqual(sample["syntheticDistance"] as? Int, 1450)
            attach(sample, name: "solid-renderer-\(phase)-\(night ? "night" : "day")-applied")
        }
        for percent in [35, 70, 100] {
            app.buttons["cityMVP.solidPreview.phase.\(percent)"].tap()
            try assertApplied(percent, night: false)
            Thread.sleep(forTimeInterval: 2)
            capture(app, "solid-renderer-\(percent)-day")
        }
        let lighting = app.buttons["cityMVP.solidPreview.lighting"]
        lighting.tap()
        let night = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Night"), object: lighting)
        XCTAssertEqual(XCTWaiter.wait(for: [night], timeout: 5), .completed)
        try assertApplied(100, night: true)
        Thread.sleep(forTimeInterval: 2)
        capture(app, "solid-renderer-100-night")
        for percent in [35, 70] {
            app.buttons["cityMVP.solidPreview.phase.\(percent)"].tap()
            try assertApplied(percent, night: true)
            Thread.sleep(forTimeInterval: 2)
            capture(app, "solid-renderer-\(percent)-night")
        }
    }

    private struct Reference {
        let camera: [String: Any]
        let pin: CGRect
        let title: String
    }
    private enum FixtureFailure: Error { case unavailable(String) }

    @MainActor
    func testCompareHandoffDistances() throws {
        try compare(dayDistances: [5_200, 4_692, 4_350, 4_150], includesNight: false)
    }

    @MainActor
    func testCompareDistrictDistancesAndNight() throws {
        try compare(dayDistances: [3_650, 2_900, 1_450], includesNight: true)
    }

    @MainActor
    func testCompareOpaqueRevealAtDistrictAndNight() throws {
        try compare(dayDistances: [3_650, 2_900, 1_450], includesNight: true, opaqueRevealComparison: true)
    }

    @MainActor
    func testCompareMaterialToneOnNativeMap() throws {
        try compare(dayDistances: [4_692, 3_650, 1_450], includesNight: true,
                    opaqueRevealComparison: true, materialToneComparison: true)
    }

    @MainActor
    func testCompareMaterialToneOnSharedMapKitAnchor() throws {
        try compare(dayDistances: [4_692, 3_650, 1_450], includesNight: true,
                    opaqueRevealComparison: true, materialToneComparison: true, sharedMapKitAnchor: true, nearGestures: true)
    }

    @MainActor
    func testCompareMaterialToneHandoffOnSharedMapKitAnchor() throws {
        try compare(dayDistances: [5_200, 4_692, 4_350, 4_150], includesNight: false,
                    opaqueRevealComparison: true, materialToneComparison: true,
                    sharedMapKitAnchor: true, handoffGestures: true)
    }

    @MainActor
    func testCompareOwnedGroundOnSharedMapKitAnchor() throws {
        try compare(dayDistances: [4_692, 1_450], includesNight: true,
                    opaqueRevealComparison: true, materialToneComparison: true,
                    sharedMapKitAnchor: true, nearGestures: true, groundOwnershipComparison: true)
    }

    @MainActor
    func testCompareOwnedGroundHandoffOnSharedMapKitAnchor() throws {
        try compare(dayDistances: [5_200, 4_692, 4_150], includesNight: false,
                    opaqueRevealComparison: true, materialToneComparison: true,
                    sharedMapKitAnchor: true, handoffGestures: true, groundOwnershipComparison: true)
    }

    /// A single live registration isolates caption ownership; the separate
    /// paired tests retain camera equality and ground-comparison coverage.
    @MainActor
    func testSelectedCaptionAcrossLiveMapOwnership() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-xinyi-auto", "--verify-xinyi-selected",
                               "--verify-xinyi-far-render", "--verify-xinyi-render-distance=4150",
                               "--verify-start-day", "--verify-native-ground-owner",
                               "--verify-opaque-reveal", "--verify-material-tone", "--verify-ground-ownership"]
        app.launch()
        defer { app.terminate() }
        let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let element = object as? XCUIElement, let raw = element.value as? String,
                  let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let distance = value["distance"] as? Double, let fit = value["fitError"] as? Double else { return false }
            return value["ready"] as? Bool == true && abs(distance - 4_150) < 5 && fit >= 0 && fit < 2
                && value["selectedID"] as? String == "landmark-101"
                && value["registrationProvenance"] as? String == "live-search"
        }, object: fixture)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
        try verifySharedAnchorHandoff(app, expectedProvenance: "live-search")
        let lighting = app.buttons["cityMVP.lighting"]
        lighting.tap()
        XCTAssertTrue(lighting.waitForExistence(timeout: 5))
        XCTAssertEqual(lighting.value as? String, "Night")
        attachRawFixture(app, name: "caption-native-night-camera-raw")
        capture(app, "caption-native-night")
    }

    @MainActor
    func testCloudBanksAcrossLiveMapOwnership() throws {
        try verifyCloudBanks(nightOnly: false)
    }

    @MainActor
    func testNightCloudConsumerOnLiveMap() throws {
        try verifyCloudBanks(nightOnly: true)
    }

    @MainActor
    func testContextRingAcrossLiveMapOwnership() throws {
        try verifyCloudBanks(nightOnly: false, contextRing: true)
    }

    @MainActor
    func testContextRingAfterFootprintFiltering() throws {
        try verifyCloudBanks(nightOnly: false, contextRing: true, contextNearOnly: true)
    }

    /// Both launches use the same district renderer. Only the public native
    /// label configuration changes; the second anchor comes from this control.
    @MainActor
    func testQuietNativeLabelsOnTheSameMapKitAnchor() throws {
        continueAfterFailure = false
        var references: [String: Reference] = [:]
        for candidate in [false, true] {
            let app = XCUIApplication()
            var innerPolicyRevision: Int?
            app.launchArguments = ["--verify-xinyi", "--verify-xinyi-auto", "--verify-xinyi-selected",
                "--verify-xinyi-far-render", "--verify-xinyi-render-distance=5000", "--verify-start-day",
                "--verify-native-ground-owner", "--verify-opaque-reveal", "--verify-material-tone",
                "--verify-ground-ownership", "--verify-cloud-handoff", "--verify-context-ring"]
            if candidate {
                let control = try XCTUnwrap(references["day"])
                let latitude = try XCTUnwrap(control.camera["registrationAnchorLatitude"] as? Double)
                let longitude = try XCTUnwrap(control.camera["registrationAnchorLongitude"] as? Double)
                app.launchArguments += ["--verify-quiet-native-labels", "--verify-paired-mapkit-anchor=\(latitude),\(longitude)"]
            }
            app.launch()
            defer { app.terminate() }
            for night in [false, true] {
                let distance = night ? 1_450.0 : 5_000.0
                if night { app.buttons["cityMVP.lighting"].tap() }
                let key = night ? "night" : "day"
                let label = "quiet-labels-\(Int(distance))-\(key)-\(candidate ? "candidate" : "control")"
                try selectDistance(distance, in: app, deadline: Date().addingTimeInterval(45), label: label)
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
                    guard fixture.exists, let raw = fixture.value as? String,
                          let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                          let actual = value["distance"] as? Double else { return false }
                    return value["ready"] as? Bool == true && value["night"] as? Bool == night
                        && abs(actual - distance) < 2
                }, object: app)
                let result = XCTWaiter.wait(for: [ready], timeout: 45)
                Thread.sleep(forTimeInterval: 2)
                attachRawFixture(app, name: label + "-camera-raw")
                capture(app, label)
                XCTAssertEqual(result, .completed)
                let raw = try XCTUnwrap(app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch.value as? String)
                let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                XCTAssertEqual(value["quietNativeLabels"] as? Bool, candidate)
                XCTAssertEqual(value["nativeLabelsQuiet"] as? Bool, candidate)
                if candidate {
                    let revision = try XCTUnwrap(value["labelPolicyRevision"] as? Int)
                    if let first = innerPolicyRevision { XCTAssertEqual(revision, first, "No extra label switches within the prepared district") }
                    else { innerPolicyRevision = revision }
                }
                XCTAssertEqual(value["contextRing"] as? Bool, true)
                XCTAssertEqual(value["groundOwnership"] as? Bool, true)
                XCTAssertEqual(value["cloudHandoff"] as? Bool, true)
                XCTAssertEqual(value["selectedID"] as? String, "landmark-101")
                XCTAssertEqual(value["registrationProvenance"] as? String, candidate ? "paired-fixture" : "live-search")
                let fit = try XCTUnwrap(value["fitError"] as? Double)
                XCTAssertGreaterThanOrEqual(fit, 0); XCTAssertLessThan(fit, 2)
                let photo = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
                XCTAssertEqual(photo.frame.midX, try XCTUnwrap(value["selectedPinX"] as? Double), accuracy: 2)
                XCTAssertEqual(photo.frame.maxY + 3, try XCTUnwrap(value["selectedPinY"] as? Double), accuracy: 2)
                if candidate {
                    let reference = try XCTUnwrap(references[key])
                    for field in ["latitude", "longitude", "registrationAnchorLatitude", "registrationAnchorLongitude"] {
                        XCTAssertEqual(try XCTUnwrap(value[field] as? Double), try XCTUnwrap(reference.camera[field] as? Double), accuracy: 0.000001)
                    }
                    for field in ["distance", "heading", "pitch", "width", "height"] {
                        XCTAssertEqual(try XCTUnwrap(value[field] as? Double), try XCTUnwrap(reference.camera[field] as? Double), accuracy: 1)
                    }
                    XCTAssertEqual(photo.frame.midX, reference.pin.midX, accuracy: 2)
                    XCTAssertEqual(photo.frame.maxY, reference.pin.maxY, accuracy: 2)
                    XCTAssertEqual(photo.frame.width, reference.pin.width, accuracy: 2)
                } else { references[key] = Reference(camera: value, pin: photo.frame, title: photo.label) }
            }
            if candidate { try verifySharedAnchorGestures(app) }
        }
    }

    @MainActor
    func testNativeLabelsRestoreOutsideTheDistrictWithoutMovingTheCamera() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-xinyi-auto", "--verify-xinyi-selected",
            "--verify-xinyi-far-render", "--verify-xinyi-render-distance=5000", "--verify-start-day",
            "--verify-native-ground-owner", "--verify-opaque-reveal", "--verify-material-tone",
            "--verify-ground-ownership", "--verify-cloud-handoff", "--verify-context-ring", "--verify-quiet-native-labels"]
        app.launch(); defer { app.terminate() }
        func sample(_ label: String, quiet: Bool, requestedTarget: Bool) throws -> [String: Any] {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
                guard fixture.exists, let raw = fixture.value as? String,
                      let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                      let fit = value["fitError"] as? Double else { return false }
                guard value["nativeLabelsQuiet"] as? Bool == quiet && fit >= 0 && fit < 2 else { return false }
                if requestedTarget {
                    guard let lat = value["latitude"] as? Double, let lon = value["longitude"] as? Double,
                          let targetLat = value["requestedLatitude"] as? Double,
                          let targetLon = value["requestedLongitude"] as? Double,
                          let distance = value["distance"] as? Double else { return false }
                    // Outside the viewport the selected pin can be unprojected,
                    // so use actual native camera readiness, not scene-pin readiness.
                    return abs(lat - targetLat) < 0.000001 && abs(lon - targetLon) < 0.000001
                        && abs(distance - 5_000) < 2
                }
                return true
            }, object: app)
            let result = XCTWaiter.wait(for: [ready], timeout: 45)
            Thread.sleep(forTimeInterval: 2)
            attachRawFixture(app, name: label + "-camera-raw"); capture(app, label)
            XCTAssertEqual(result, .completed)
            let raw = try XCTUnwrap(app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch.value as? String)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            XCTAssertEqual(value["selectedID"] as? String, "landmark-101")
            XCTAssertEqual(value["nativeLabelsQuiet"] as? Bool, quiet)
            // A public native label change must not shift the camera at all.
            for (field, before) in [("latitude", "labelChangeLatitude"), ("longitude", "labelChangeLongitude")] {
                XCTAssertEqual(try XCTUnwrap(value[field] as? Double), try XCTUnwrap(value[before] as? Double), accuracy: 0.000001)
            }
            for (field, before) in [("distance", "labelChangeDistance"), ("heading", "labelChangeHeading"), ("pitch", "labelChangePitch")] {
                XCTAssertEqual(try XCTUnwrap(value[field] as? Double), try XCTUnwrap(value[before] as? Double), accuracy: 0.1)
            }
            let point = CGPoint(x: try XCTUnwrap(value["selectedPinX"] as? Double),
                                y: try XCTUnwrap(value["selectedPinY"] as? Double))
            // Geographic panning may legitimately move the selected point offscreen.
            if CGRect(x: 0, y: 0, width: 393, height: 852).contains(point) {
                let photo = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
                XCTAssertEqual(photo.frame.midX, point.x, accuracy: 2)
                XCTAssertEqual(photo.frame.maxY + 3, point.y, accuracy: 2)
            }
            return value
        }
        func east() throws {
            let menu = app.buttons["cityMVP.renderProbe.camera"]
            XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
            let target = app.buttons["cityMVP.renderProbe.east1000"]
            XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
        }
        try selectDistance(5_000, in: app, deadline: Date().addingTimeInterval(45), label: "labels-center")
        let center = try sample("labels-center-quiet", quiet: true, requestedTarget: true)
        try east()
        let outside = try sample("labels-east-native", quiet: false, requestedTarget: true)
        XCTAssertEqual(try XCTUnwrap(outside["labelPolicyRevision"] as? Int), try XCTUnwrap(center["labelPolicyRevision"] as? Int) + 1)
        try selectDistance(5_000, in: app, deadline: Date().addingTimeInterval(45), label: "labels-return-center")
        let returned = try sample("labels-center-return-quiet", quiet: true, requestedTarget: true)
        XCTAssertEqual(try XCTUnwrap(returned["labelPolicyRevision"] as? Int), try XCTUnwrap(outside["labelPolicyRevision"] as? Int) + 1)
        for key in ["latitude", "longitude", "selectedPinX", "selectedPinY"] {
            XCTAssertEqual(try XCTUnwrap(returned[key] as? Double), try XCTUnwrap(center[key] as? Double), accuracy: 0.000001)
        }
        try east()
        let beforePan = try sample("labels-east-before-pan", quiet: false, requestedTarget: true)
        XCTAssertEqual(try XCTUnwrap(beforePan["labelPolicyRevision"] as? Int), try XCTUnwrap(returned["labelPolicyRevision"] as? Int) + 1)
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        map.coordinate(withNormalizedOffset: .init(dx: 0.12, dy: 0.4)).press(forDuration: 0.1,
            thenDragTo: map.coordinate(withNormalizedOffset: .init(dx: 0.88, dy: 0.4)))
        let afterPan = try sample("labels-pan-back-quiet", quiet: true, requestedTarget: false)
        XCTAssertEqual(try XCTUnwrap(afterPan["labelPolicyRevision"] as? Int), try XCTUnwrap(beforePan["labelPolicyRevision"] as? Int) + 1)
        XCTAssertGreaterThan(abs(try XCTUnwrap(afterPan["longitude"] as? Double)
            - XCTUnwrap(beforePan["longitude"] as? Double)), 0.00001)
    }

    @MainActor
    func testContextGlyphConsumerInDayAndNight() throws {
        continueAfterFailure = false
        let app=XCUIApplication()
        app.launchArguments=["--verify-xinyi","--verify-xinyi-auto","--verify-xinyi-selected",
            "--verify-xinyi-far-render","--verify-xinyi-render-distance=5000","--verify-start-day",
            "--verify-native-ground-owner","--verify-opaque-reveal","--verify-material-tone",
            "--verify-ground-ownership","--verify-cloud-handoff","--verify-context-ring","--verify-context-labels"]
        app.launch(); defer { app.terminate() }
        try selectDistance(5_000,in:app,deadline:Date().addingTimeInterval(45),label:"glyph-consumer")
        for night in [false,true] {
            if night { app.buttons["cityMVP.lighting"].tap() }
            let expected=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
                let fixture=app.descendants(matching:.any)["cityMVP.farRenderFixture"].firstMatch
                guard fixture.exists,let raw=fixture.value as? String,
                      let value=try? JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else { return false }
                return value["ready"] as? Bool == true && value["night"] as? Bool == night
                    && value["nativeLabelsQuiet"] as? Bool == true && (value["contextLabelCount"] as? Int ?? 0) >= 2
            },object:app)
            XCTAssertEqual(XCTWaiter.wait(for:[expected],timeout:45),.completed)
            Thread.sleep(forTimeInterval:1)
            let name="context-glyph-final-" + (night ? "night" : "day")
            capture(app,name);attachRawFixture(app,name:name+"-raw")
        }
    }

    @MainActor
    func testContextNamesStayAboveTheSceneAndOpenExactUnsavedCandidate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-xinyi-auto", "--verify-xinyi-selected",
            "--verify-xinyi-far-render", "--verify-xinyi-render-distance=5000", "--verify-start-day",
            "--verify-native-ground-owner", "--verify-opaque-reveal", "--verify-material-tone",
            "--verify-ground-ownership", "--verify-cloud-handoff", "--verify-context-ring", "--verify-context-labels"]
        app.launch(); defer { app.terminate() }
        func read() -> [String: Any]? {
            let fixture=app.descendants(matching:.any)["cityMVP.farRenderFixture"].firstMatch
            guard fixture.exists,let raw=fixture.value as? String else { return nil }
            return (try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any]
        }
        func sample(_ name:String,quiet:Bool,labels:Bool) throws -> [String:Any] {
            let predicate=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
                guard let v=read(), let count=v["contextLabelCount"] as? Int,
                      let lat=v["latitude"] as? Double,let lon=v["longitude"] as? Double,
                      let tlat=v["requestedLatitude"] as? Double,let tlon=v["requestedLongitude"] as? Double,
                      let d=v["distance"] as? Double,let requested=v["requestedDistance"] as? Int else { return false }
                return v["nativeLabelsQuiet"] as? Bool == quiet && (labels ? count >= 2 : count == 0)
                    && abs(lat-tlat)<0.000001 && abs(lon-tlon)<0.000001 && abs(d-Double(requested))<2
            },object:app)
            let result=XCTWaiter.wait(for:[predicate],timeout:45)
            attachRawFixture(app,name:name+"-raw");capture(app,name)
            XCTAssertEqual(result,.completed)
            let value=try XCTUnwrap(read())
            let entries=try XCTUnwrap(value["contextLabels"] as? [[String:Any]])
            XCTAssertLessThanOrEqual(entries.count,24)
            for entry in entries {
                let id=try XCTUnwrap(entry["id"] as? String)
                let host=app.descendants(matching:.any)["cityMVP.contextLabel."+id].firstMatch
                XCTAssertTrue(host.exists)
                XCTAssertEqual(host.frame.midX,try XCTUnwrap(entry["x"] as? Double),accuracy:2)
                XCTAssertEqual(host.frame.midY,try XCTUnwrap(entry["y"] as? Double),accuracy:2)
                XCTAssertGreaterThanOrEqual(host.frame.width + 0.001,44) // Native AX conversion may differ by one floating-point ULP.
                XCTAssertGreaterThanOrEqual(host.frame.height + 0.001,44)
            }
            return value
        }
        func east(_ meters:Int) throws {
            app.buttons["cityMVP.renderProbe.camera"].tap()
            let item=app.buttons["cityMVP.renderProbe.east\(meters)"]
            XCTAssertTrue(item.waitForExistence(timeout:5));item.tap()
        }
        try selectDistance(5_000,in:app,deadline:Date().addingTimeInterval(45),label:"context-center")
        let center=try sample("context-center-day",quiet:true,labels:true)
        try east(1000)
        _=try sample("context-east-own-names",quiet:true,labels:true)
        try east(2000)
        let outside=try sample("context-outside-native",quiet:false,labels:false)
        XCTAssertEqual(outside["projectionAvailable"] as? Bool,false)
        try selectDistance(5_000,in:app,deadline:Date().addingTimeInterval(45),label:"context-return")
        let returned=try sample("context-return-day",quiet:true,labels:true)
        for key in ["latitude","longitude","selectedPinX","selectedPinY"] {
            XCTAssertEqual(try XCTUnwrap(center[key] as? Double),try XCTUnwrap(returned[key] as? Double),accuracy:0.000001)
        }
        let lighting=app.buttons["cityMVP.lighting"];lighting.tap()
        let night=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","Night"),object:lighting)
        XCTAssertEqual(XCTWaiter.wait(for:[night],timeout:5),.completed)
        _=try sample("context-center-night",quiet:true,labels:true)
        lighting.tap()
        try selectDistance(1_450,in:app,deadline:Date().addingTimeInterval(45),label:"context-gesture-start")
        _=try sample("context-gesture-start",quiet:true,labels:true)
        try verifySharedAnchorGestures(app, expectedProvenance: "live-search")
        try selectDistance(1_450,in:app,deadline:Date().addingTimeInterval(45),label:"context-tap")
        let before=try sample("context-near-tap",quiet:true,labels:true)
        let entries=try XCTUnwrap(before["contextLabels"] as? [[String:Any]])
        let entry=try XCTUnwrap(entries.first)
        let id=try XCTUnwrap(entry["id"] as? String)
        let host=app.descendants(matching:.any)["cityMVP.contextLabel."+id].firstMatch
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:host.frame.midX,dy:host.frame.midY)).tap()
        let selected=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in read()?["selectedID"] as? String == id },object:app)
        let result=XCTWaiter.wait(for:[selected],timeout:10)
        capture(app,"context-exact-unsaved-selection");attachRawFixture(app,name:"context-selected-source")
        XCTAssertEqual(result,.completed)
        let after=try XCTUnwrap(read())
        XCTAssertEqual(after["selectedSource"] as? String,"https://www.openstreetmap.org/"+id)
        XCTAssertEqual(after["savedCount"] as? Int,before["savedCount"] as? Int)
        XCTAssertTrue(app.staticTexts["Unsaved place"].firstMatch.exists)
    }

    @MainActor
    private func verifyCloudBanks(nightOnly: Bool, contextRing: Bool = false, contextNearOnly: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-xinyi-auto", "--verify-xinyi-selected",
                               "--verify-xinyi-far-render", "--verify-xinyi-render-distance=8500", "--verify-start-day",
                               "--verify-native-ground-owner", "--verify-opaque-reveal", "--verify-material-tone",
                               "--verify-ground-ownership", "--verify-cloud-handoff"]
        if nightOnly { app.launchArguments.append("--verify-cloud-consumer") }
        if contextRing { app.launchArguments.append("--verify-context-ring") }
        app.launch()
        defer { app.terminate() }
        func sample(_ distance: Double, night: Bool = false, suffix: String = "") throws {
            let label = "cloud-banks-\(Int(distance))-\(night ? "night" : "day")" + suffix
            try selectDistance(distance, in: app, deadline: Date().addingTimeInterval(45), label: label)
            let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
            // Resolve the live element each poll and parse its JSON value.
            // The native string predicate timed out even though its subsequent
            // raw attachment satisfied every clause; keep the same 45s bound.
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let current = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
                guard current.exists, let raw = current.value as? String,
                      let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                      let requested = value["requestedDistance"] as? Double,
                      let actual = value["distance"] as? Double else { return false }
                return value["ready"] as? Bool == true && value["cloudHandoff"] as? Bool == true
                    && value["night"] as? Bool == night && requested == distance && abs(actual - distance) < 2
            }, object: app)
            let result = XCTWaiter.wait(for: [ready], timeout: 45)
            attachRawFixture(app, name: label + "-camera-raw")
            capture(app, label)
            XCTAssertEqual(result, .completed)
            let raw = try XCTUnwrap(fixture.value as? String)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            XCTAssertEqual(value["ready"] as? Bool, true)
            XCTAssertEqual(value["cloudHandoff"] as? Bool, true)
            XCTAssertEqual(value["contextRing"] as? Bool, contextRing)
            XCTAssertEqual(value["night"] as? Bool, night)
            XCTAssertEqual(value["registrationProvenance"] as? String, "live-search")
            XCTAssertEqual(value["selectedID"] as? String, "landmark-101")
            XCTAssertEqual(try XCTUnwrap(value["distance"] as? Double), distance, accuracy: 2)
            XCTAssertEqual(value["projectionAvailable"] as? Bool, distance < 9_000)
            if distance < 9_000 {
                let fit = try XCTUnwrap(value["fitError"] as? Double)
                XCTAssertGreaterThanOrEqual(fit, 0)
                XCTAssertLessThan(fit, 2)
            }
            let photo = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
            XCTAssertEqual(photo.frame.midX, try XCTUnwrap(value["selectedPinX"] as? Double), accuracy: 2)
            XCTAssertEqual(photo.frame.maxY + 3, try XCTUnwrap(value["selectedPinY"] as? Double), accuracy: 2)
        }
        if contextNearOnly {
            try sample(5_000)
            app.buttons["cityMVP.lighting"].tap()
            try sample(1_450, night: true)
            return
        }
        if nightOnly {
            try sample(8_000)
            app.buttons["cityMVP.lighting"].tap()
            try sample(8_000, night: true)
            try sample(7_500, night: true, suffix: "-redraw")
            try sample(8_000, night: true, suffix: "-repeat")
            return
        }
        for distance in [8_500.0, 9_500, 8_000, 5_000, 7_500] { try sample(distance) }
        try verifySharedAnchorHandoff(app, expectedProvenance: "live-search", outsideDistance: 9_000, insideDistance: 8_500)
        app.buttons["cityMVP.lighting"].tap()
        try sample(1_450, night: true)
        try sample(8_000, night: true)
        // Same final pose after additional renders distinguishes a missing
        // first cloud frame from the intended night palette.
        try sample(7_500, night: true, suffix: "-redraw")
        try sample(8_000, night: true, suffix: "-repeat")
    }

    @MainActor
    private func compare(dayDistances: [Double], includesNight: Bool,
                         opaqueRevealComparison: Bool = false, materialToneComparison: Bool = false,
                         sharedMapKitAnchor: Bool = false, nearGestures: Bool = false,
                         handoffGestures: Bool = false, groundOwnershipComparison: Bool = false) throws {
        continueAfterFailure = false
        var references: [String: Reference] = [:]
        let firstDistance = try XCTUnwrap(dayDistances.first)
        for candidate in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--verify-xinyi", "--verify-xinyi-auto",
                                    "--verify-xinyi-selected", "--verify-xinyi-far-render",
                                    "--verify-xinyi-render-distance=\(Int(firstDistance))",
                                    "--verify-start-day"]
            if opaqueRevealComparison {
                // Hold the ground owner constant: only the solid reveal varies.
                app.launchArguments.append("--verify-native-ground-owner")
                if candidate || groundOwnershipComparison { app.launchArguments.append("--verify-opaque-reveal") }
                if (candidate || groundOwnershipComparison) && materialToneComparison { app.launchArguments.append("--verify-material-tone") }
                if candidate && groundOwnershipComparison { app.launchArguments.append("--verify-ground-ownership") }
            } else if candidate { app.launchArguments.append("--verify-native-ground-owner") }
            if candidate && sharedMapKitAnchor {
                let control = try XCTUnwrap(references["\(Int(firstDistance))-day"])
                XCTAssertEqual(control.camera["registrationProvenance"] as? String, "live-search")
                let latitude = try XCTUnwrap(control.camera["registrationAnchorLatitude"] as? Double)
                let longitude = try XCTUnwrap(control.camera["registrationAnchorLongitude"] as? Double)
                // Provenance is a live-search control from THIS test, never a
                // previous run, fixed coordinate, cache or automatic fallback.
                app.launchArguments.append("--verify-paired-mapkit-anchor=\(latitude),\(longitude)")
            }
            app.launch()
            defer { app.terminate() }
            for distance in dayDistances {
                // The same 45-second bound includes menu availability and the
                // actual requested camera. No retry or registration fallback.
                let deadline = Date().addingTimeInterval(45)
                let label = evidenceLabel(distance: distance, night: false, candidate: candidate,
                                          opaqueRevealComparison: opaqueRevealComparison)
                try selectDistance(distance, in: app, deadline: deadline, label: label)
                try captureFixture(app, distance: distance, night: false, candidate: candidate,
                                   deadline: deadline, references: &references, opaqueRevealComparison: opaqueRevealComparison,
                                   materialToneComparison: materialToneComparison, sharedMapKitAnchor: sharedMapKitAnchor,
                                   groundOwnershipComparison: groundOwnershipComparison)
            }
            if includesNight {
                let label = evidenceLabel(distance: 1_450, night: true, candidate: candidate,
                                          opaqueRevealComparison: opaqueRevealComparison)
                let deadline = Date().addingTimeInterval(45)
                let lighting = app.buttons["cityMVP.lighting"]
                guard lighting.exists && lighting.isHittable else {
                    failEvidence(app, label: label + "-FAIL-lighting")
                    throw FixtureFailure.unavailable("Lighting control unavailable")
                }
                lighting.tap()
                try captureFixture(app, distance: 1_450, night: true, candidate: candidate,
                                   deadline: deadline, references: &references, opaqueRevealComparison: opaqueRevealComparison,
                                   materialToneComparison: materialToneComparison, sharedMapKitAnchor: sharedMapKitAnchor,
                                   groundOwnershipComparison: groundOwnershipComparison)
            }
            if candidate && nearGestures { try verifySharedAnchorGestures(app) }
            if candidate && handoffGestures { try verifySharedAnchorHandoff(app) }
        }
    }

    @MainActor
    private func verifySharedAnchorHandoff(_ app: XCUIApplication, expectedProvenance: String = "paired-fixture",
                                          outsideDistance: Double = 5_200, insideDistance: Double = 4_692) throws {
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        let photo = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(map.exists)
        func wait(_ label: String, outside: Bool) throws {
            let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement, let raw = element.value as? String,
                      let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                      let distance = value["distance"] as? Double else { return false }
                if outside { return distance > outsideDistance }
                guard let fit = value["fitError"] as? Double else { return false }
                return distance < insideDistance && fit >= 0 && fit < 2
            }, object: fixture)
            let result = XCTWaiter.wait(for: [expected], timeout: 9)
            attachRawFixture(app, name: label + "-camera-raw")
            capture(app, label)
            XCTAssertEqual(result, .completed)
            let raw = try XCTUnwrap(fixture.value as? String)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            XCTAssertEqual(value["selectedID"] as? String, "landmark-101")
            XCTAssertEqual(value["registrationProvenance"] as? String, expectedProvenance)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
            XCTAssertTrue(photo.exists)
            XCTAssertEqual(photo.frame.midX, try XCTUnwrap(value["selectedPinX"] as? Double), accuracy: 2)
            XCTAssertEqual(photo.frame.maxY + 3, try XCTUnwrap(value["selectedPinY"] as? Double), accuracy: 2)
        }
        capture(app, "paired-handoff-start")
        Thread.sleep(forTimeInterval: 3)
        map.pinch(withScale: 0.68, velocity: -0.3)
        try wait("paired-handoff-outside-prewarm", outside: true)
        map.pinch(withScale: 1.55, velocity: 0.3)
        try wait("paired-handoff-inside-prewarm", outside: false)
        map.pinch(withScale: 0.65, velocity: -0.3)
        try wait("paired-handoff-outside-again", outside: true)
    }

    @MainActor
    private func verifySharedAnchorGestures(_ app: XCUIApplication, expectedProvenance: String = "paired-fixture") throws {
        let map = app.descendants(matching: .any)["cityMVP.pinchArea"].firstMatch
        let photo = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(map.exists)
        func sample() throws -> [String: Any] {
            let value = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch.value
            let raw = try XCTUnwrap(value as? String)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        }
        func number(_ value: [String: Any], _ key: String) throws -> Double { try XCTUnwrap(value[key] as? Double) }
        func wait(_ label: String, condition: @escaping ([String: Any]) -> Bool) throws -> [String: Any] {
            let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement, let raw = element.value as? String,
                      let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                      let fit = value["fitError"] as? Double, fit >= 0, fit < 2 else { return false }
                return condition(value)
            }, object: fixture)
            let result = XCTWaiter.wait(for: [expected], timeout: 9)
            attachRawFixture(app, name: label + "-camera-raw")
            capture(app, label)
            XCTAssertEqual(result, .completed)
            let value = try sample()
            XCTAssertEqual(value["selectedID"] as? String, "landmark-101")
            XCTAssertEqual(value["registrationProvenance"] as? String, expectedProvenance)
            XCTAssertEqual(value["materialTone"] as? Bool, true)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
            XCTAssertTrue(photo.exists)
            XCTAssertEqual(photo.frame.midX, try number(value, "selectedPinX"), accuracy: 2)
            XCTAssertEqual(photo.frame.maxY + 3, try number(value, "selectedPinY"), accuracy: 2)
            return value
        }
        let initial = try sample()
        capture(app, "paired-gesture-start")
        Thread.sleep(forTimeInterval: 3) // Give the external recorder time to start; no gesture timing claim.
        let initialDistance = try number(initial, "distance")
        map.pinch(withScale: 0.66, velocity: -0.6)
        let zoomedOut = try wait("paired-gesture-pinch-out") { ($0["distance"] as? Double ?? 0) > initialDistance * 1.15 }
        let heading = try number(zoomedOut, "heading")
        map.rotate(0.5, withVelocity: 0.65)
        let rotated = try wait("paired-gesture-rotate") {
            let delta = abs(($0["heading"] as? Double ?? heading) - heading).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta) > 10
        }
        let beforePan = photo.frame
        let latitude = try number(rotated, "latitude"), longitude = try number(rotated, "longitude")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45)).press(forDuration: 0.1,
            thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45)))
        let panned = try wait("paired-gesture-pan") {
            abs(($0["latitude"] as? Double ?? latitude) - latitude) > 0.00001
                || abs(($0["longitude"] as? Double ?? longitude) - longitude) > 0.00001
        }
        XCTAssertGreaterThan(hypot(photo.frame.midX - beforePan.midX, photo.frame.midY - beforePan.midY), 20,
                             "Free panning must move the selected geographic point rather than recenter101")
        let pannedDistance = try number(panned, "distance")
        map.pinch(withScale: 1.5, velocity: 0.6)
        _ = try wait("paired-gesture-pinch-in") { ($0["distance"] as? Double ?? pannedDistance) < pannedDistance * 0.85 }
    }

    @MainActor
    private func selectDistance(_ distance: Double, in app: XCUIApplication, deadline: Date, label: String) throws {
        let menu = app.buttons["cityMVP.renderProbe.camera"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: menu)
        guard XCTWaiter.wait(for: [enabled], timeout: remaining(deadline)) == .completed else {
            failEvidence(app, label: label + "-FAIL-camera-menu")
            throw FixtureFailure.unavailable("Registered camera menu unavailable")
        }
        menu.tap()
        let entry = app.buttons["cityMVP.renderProbe.distance.\(Int(distance))"]
        guard entry.waitForExistence(timeout: min(5, remaining(deadline))) else {
            failEvidence(app, label: label + "-FAIL-camera-entry")
            throw FixtureFailure.unavailable("Missing whitelisted camera entry \(Int(distance))")
        }
        entry.tap()
    }

    @MainActor
    private func captureFixture(_ app: XCUIApplication, distance: Double, night: Bool, candidate: Bool,
                                deadline: Date, references: inout [String: Reference], opaqueRevealComparison: Bool,
                                materialToneComparison: Bool, sharedMapKitAnchor: Bool, groundOwnershipComparison: Bool) throws {
        let label = evidenceLabel(distance: distance, night: night, candidate: candidate,
                                  opaqueRevealComparison: opaqueRevealComparison)
        let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
        let ready = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND value CONTAINS %@ AND value CONTAINS %@ AND value CONTAINS %@",
            "cityMVP.farRenderFixture", "\"ready\":true",
            "\"requestedDistance\":\(Int(distance))", "\"night\":\(night ? "true" : "false")")).firstMatch
        guard ready.waitForExistence(timeout: remaining(deadline)) else {
            failEvidence(app, label: label + "-FAIL-ready")
            throw FixtureFailure.unavailable("Render fixture unavailable: \(fixture.value ?? "missing")")
        }
        Thread.sleep(forTimeInterval: 2)
        // Retain raw metadata even if decoding or a later assertion fails.
        attachRawFixture(app, name: label + "-camera-raw")
        capture(app, label)
        let value = try XCTUnwrap(fixture.value as? String)
        let data = try XCTUnwrap(value.data(using: .utf8))
        let sample = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        attach(sample, name: label + "-camera")
        func number(_ key: String) throws -> Double {
            try XCTUnwrap(sample[key] as? Double, "Missing fixture field \(key)")
        }
        XCTAssertEqual(sample["ready"] as? Bool, true)
        XCTAssertEqual(sample["night"] as? Bool, night)
        XCTAssertEqual(sample["materialTone"] as? Bool, (candidate || groundOwnershipComparison) && materialToneComparison)
        XCTAssertEqual(sample["opaqueReveal"] as? Bool, (candidate || groundOwnershipComparison) && opaqueRevealComparison)
        XCTAssertEqual(sample["groundOwnership"] as? Bool, candidate && groundOwnershipComparison)
        XCTAssertEqual(sample["registrationProvenance"] as? String,
                       candidate && sharedMapKitAnchor ? "paired-fixture" : "live-search")
        XCTAssertEqual(sample["selectedID"] as? String, "landmark-101")
        XCTAssertEqual(try number("requestedDistance"), distance)
        XCTAssertEqual(try number("distance"), distance, accuracy: 2)
        XCTAssertEqual(try number("heading"), 20, accuracy: 0.1)
        XCTAssertEqual(try number("pitch"), 35, accuracy: 0.1)
        XCTAssertEqual(try number("width"), 393, accuracy: 1)
        XCTAssertEqual(try number("height"), 852, accuracy: 1)
        if distance < 5_200 {
            XCTAssertGreaterThanOrEqual(try number("fitError"), 0)
            XCTAssertLessThan(try number("fitError"), 2)
            XCTAssertGreaterThan(try number("pinX"), 0)
            XCTAssertLessThan(try number("pinX"), try number("width"))
            XCTAssertGreaterThan(try number("pinY"), 0)
            XCTAssertLessThan(try number("pinY"), try number("height"))
        }
        let selected = app.descendants(matching: .any)["cityMVP.selectedGroundPin"].firstMatch
        XCTAssertTrue(selected.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "cityMVP.selectedGroundPin").count, 1)
        let pin = selected.frame
        attach(["x": pin.minX, "y": pin.minY, "width": pin.width, "height": pin.height,
                "title": selected.label, "candidate": candidate,
                "nativeGroundOwner": opaqueRevealComparison || candidate,
                "opaqueReveal": opaqueRevealComparison && (candidate || groundOwnershipComparison),
                "groundOwnership": groundOwnershipComparison && candidate], name: label + "-selection")
        XCTAssertGreaterThan(pin.width, 0)
        XCTAssertGreaterThan(pin.height, 0)
        XCTAssertTrue(pin.intersects(CGRect(x: 0, y: 0, width: 393, height: 852)))
        let key = "\(Int(distance))-\(night ? "night" : "day")"
        if candidate {
            let reference = try XCTUnwrap(references[key], "Missing actual control capture for \(key)")
            for key in ["distance", "heading", "pitch", "width", "height"] {
                XCTAssertEqual(try number(key), try XCTUnwrap(reference.camera[key] as? Double), accuracy: 1)
            }
            for key in ["latitude", "longitude", "registrationAnchorLatitude", "registrationAnchorLongitude"] {
                XCTAssertEqual(try number(key), try XCTUnwrap(reference.camera[key] as? Double), accuracy: 0.000001)
            }
            XCTAssertEqual(sample["selectedID"] as? String, reference.camera["selectedID"] as? String)
            XCTAssertEqual(selected.label, reference.title)
            XCTAssertEqual(pin.minX, reference.pin.minX, accuracy: 1)
            XCTAssertEqual(pin.minY, reference.pin.minY, accuracy: 1)
            XCTAssertEqual(pin.width, reference.pin.width, accuracy: 1)
            XCTAssertEqual(pin.height, reference.pin.height, accuracy: 1)
        } else {
            references[key] = Reference(camera: sample, pin: pin, title: selected.label)
        }
    }

    private func evidenceLabel(distance: Double, night: Bool, candidate: Bool, opaqueRevealComparison: Bool) -> String {
        "\(opaqueRevealComparison ? "opaque-reveal" : "native-ground")-\(Int(distance))-\(night ? "night" : "day")-\(candidate ? "candidate" : "control")"
    }

    private func remaining(_ deadline: Date) -> TimeInterval { max(0, deadline.timeIntervalSinceNow) }

    @MainActor
    private func failEvidence(_ app: XCUIApplication, label: String) {
        attachRawFixture(app, name: label + "-camera-raw")
        capture(app, label)
    }

    @MainActor
    private func attachRawFixture(_ app: XCUIApplication, name: String) {
        let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
        guard fixture.exists, let value = fixture.value as? String, let data = value.data(using: .utf8) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ value: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            XCTFail("Could not encode render evidence")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
