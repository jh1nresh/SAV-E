import XCTest

final class CityNativeOverlayProbeTests: XCTestCase {
    private enum ProbeFailure: Error { case fixtureNotReady }

    @MainActor
    func testNativeOverlayModes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-native-overlay-probe", "-cityMVP.night", "NO"]
        app.launch()
        try waitReady(app, mode: "none", distance: 1450)
        let modes = ["none", "roads-alpha001", "roads-opaque", "labels-opaque"]
        var currentMode = "none"
        for distance in [1450, 4692] {
            let previousDistanceState = app.staticTexts["nativeOverlayProbe.status"].value as? String
            app.buttons["nativeOverlayProbe.distance.\(distance)"].tap()
            try waitReady(app, mode: currentMode, distance: distance, excluding: previousDistanceState)
            for mode in modes {
                let previousModeState = app.staticTexts["nativeOverlayProbe.status"].value as? String
                app.buttons["nativeOverlayProbe.mode.\(mode)"].tap()
                try waitReady(app, mode: mode, distance: distance, excluding: previousModeState)
                try captureState(app, name: "native-overlay-\(distance)-\(mode)", mode: mode, distance: distance)
                currentMode = mode
            }
        }
        // Capture success means a matching settled native frame was available.
        // Extrusion, residual silhouette, roads and credits remain visual judgments.
    }

    @MainActor
    func testLiveBuildingFlagAndRestore() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-native-overlay-probe", "-cityMVP.night", "NO"]
        app.launch()
        try waitReady(app, mode: "none", distance: 1450)
        for distance in [1450, 4692] {
            let previousDistanceState = app.staticTexts["nativeOverlayProbe.status"].value as? String
            app.buttons["nativeOverlayProbe.distance.\(distance)"].tap()
            try waitReady(app, mode: "none", distance: distance, excluding: previousDistanceState)
            let baseline = try buildingRecord(app)
            guard let original = baseline["original"] as? Bool else {
                capture(app, "native-building-\(distance)-missing-original")
                XCTFail("The adapter must capture the real baseline before a write")
                throw ProbeFailure.fixtureNotReady
            }
            try assertBuilding(app, expectedOff: false, original: original)
            try captureState(app, name: "native-building-\(distance)-default", mode: "none", distance: distance)

            let previousOffState = app.staticTexts["nativeOverlayProbe.status"].value as? String
            app.buttons["nativeOverlayProbe.mode.buildings-off"].tap()
            try waitReady(app, mode: "buildings-off", distance: distance, excluding: previousOffState)
            try assertBuilding(app, expectedOff: true, original: original)
            try captureState(app, name: "native-building-\(distance)-off", mode: "buildings-off", distance: distance)

            let previousRestoreState = app.staticTexts["nativeOverlayProbe.status"].value as? String
            app.buttons["nativeOverlayProbe.mode.none"].tap()
            try waitReady(app, mode: "none", distance: distance, excluding: previousRestoreState)
            try assertBuilding(app, expectedOff: false, original: original)
            try captureState(app, name: "native-building-\(distance)-restored", mode: "none", distance: distance)
        }
        // Getter and restoration assertions establish the public setting only.
        // These six unoccluded frames still need independent silhouette review.
    }

    @MainActor
    private func buildingRecord(_ app: XCUIApplication) throws -> [String: Any] {
        let record = try cameraRecord(app)
        guard let building = record["buildingSetting"] as? [String: Any] else {
            capture(app, "native-building-readback-missing")
            XCTFail("Live public setting readback must accompany the camera record")
            throw ProbeFailure.fixtureNotReady
        }
        XCTAssertEqual(building["revision"] as? Int, record["revision"] as? Int)
        XCTAssertEqual(building["bindingGeneration"] as? Int, record["bindingGeneration"] as? Int)
        XCTAssertEqual(building["hostGeneration"] as? Int, record["activeHostGeneration"] as? Int)
        return building
    }

    @MainActor
    private func assertBuilding(_ app: XCUIApplication, expectedOff: Bool, original: Bool) throws {
        let building = try buildingRecord(app)
        let expected = expectedOff ? false : original
        guard building["bound"] as? Bool == true,
              building["original"] as? Bool == original,
              building["requestOff"] as? Bool == expectedOff,
              building["requested"] as? Bool == expected,
              building["actual"] as? Bool == expected,
              building["configuration"] as? String == "standard",
              building["elevation"] as? String == "flat",
              building["emphasis"] as? String == "default" else {
            capture(app, "native-building-readback-FAIL")
            let attachment = XCTAttachment(string: String(describing: building))
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Live getter/configuration must independently match showsBuildings=false or restored original=\(original)")
            throw ProbeFailure.fixtureNotReady
        }
    }

    @MainActor
    func testRegistrationFailureRequiresExplicitRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--verify-native-overlay-probe", "--probe-registration-fails-once", "-cityMVP.night", "NO"]
        app.launch()
        let failed = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND value BEGINSWITH %@",
                                                         "nativeOverlayProbe.status", "registration-failed|")).firstMatch
        guard failed.waitForExistence(timeout: 30) else {
            capture(app, "native-overlay-registration-failure-missing")
            XCTFail("The explicit first-attempt fixture must expose alignment failure")
            throw ProbeFailure.fixtureNotReady
        }
        let before = try cameraRecord(app)
        XCTAssertEqual(before["resolver"] as? String, "fixture-failure")
        XCTAssertEqual(before["resolutionAttempts"] as? Int, 1)
        XCTAssertNil(before["requested"], "A failed lookup must not supply guessed coordinates")
        capture(app, "native-overlay-registration-failure")
        let retry = app.buttons["nativeOverlayProbe.retry"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        try waitReady(app, mode: "none", distance: 1450)
        let after = try cameraRecord(app)
        XCTAssertEqual(after["resolver"] as? String, "mapkit")
        XCTAssertEqual(after["resolutionAttempts"] as? Int, 2)
        try captureState(app, name: "native-overlay-registration-retried", mode: "none", distance: 1450)
    }

    @MainActor
    private func waitReady(_ app: XCUIApplication, mode: String, distance: Int, excluding previous: String? = nil) throws {
        let value = "ready|mode=\(mode)|distance=\(distance)|revision="
        // A tap on the already-selected mode still requires a NEW2s settle.
        // Excluding the former revision prevents stale AX Ready from passing.
        let ready = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND value BEGINSWITH %@ AND value != %@",
                                                        "nativeOverlayProbe.status", value, previous ?? "")).firstMatch
        guard ready.waitForExistence(timeout: 30) else {
            capture(app, "native-overlay-FAIL-\(distance)-\(mode)")
            let state = app.staticTexts["nativeOverlayProbe.camera"]
            add(XCTAttachment(string: "Expected \(value)\n\(state.value as? String ?? state.label)"))
            XCTFail("Native fixture did not settle: \(app.staticTexts["nativeOverlayProbe.status"].value ?? "missing status"). Camera: \(state.value ?? "missing")")
            throw ProbeFailure.fixtureNotReady
        }
    }

    @MainActor
    private func captureState(_ app: XCUIApplication, name: String, mode: String, distance: Int) throws {
        let record = try cameraRecord(app)
        guard let observed = record["observed"] as? [String: Double],
              let requested = record["requested"] as? [String: Double],
              let d = observed["distance"], let h = observed["heading"], let p = observed["pitch"] else {
            capture(app, name + "-missing-camera")
            XCTFail("Exact requested and observed camera fields must accompany every capture")
            throw ProbeFailure.fixtureNotReady
        }
        XCTAssertEqual(record["mode"] as? String, mode)
        XCTAssertEqual(record["phase"] as? String, "ready")
        XCTAssertEqual(requested["distance"], Double(distance))
        XCTAssertEqual(d, Double(distance), accuracy: Double(distance) * 0.02)
        XCTAssertEqual(h, 20, accuracy: 1)
        XCTAssertEqual(p, 35, accuracy: 1, "Pitch clamping is fixture failure, not overlay success")
        capture(app, name)
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        let state = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        state.name = name + "-camera"
        state.lifetime = .keepAlways
        add(state)
    }

    @MainActor
    private func cameraRecord(_ app: XCUIApplication) throws -> [String: Any] {
        let element = app.staticTexts["nativeOverlayProbe.camera"]
        guard let value = element.value as? String, let data = value.data(using: .utf8),
              let record = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            capture(app, "native-overlay-camera-record-invalid")
            XCTFail("The probe must expose a structured exact camera record")
            throw ProbeFailure.fixtureNotReady
        }
        return record
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
