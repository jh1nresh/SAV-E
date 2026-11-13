import XCTest

/// Readback is a setting-retention assertion, not a native geometry assertion.
/// Inspect paired screenshots to decide whether the native 101 column vanished.
final class CityUIKitBuildingsProbeTests: XCTestCase {
    @MainActor
    func testUIKitBuildingsRetentionAtHistoricalCameras() async {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-uikit-buildings-probe", "--verify-start-day"]
        app.launch()
        guard await waitReady(app, distance: 1450, requested: true, after: -1) else {
            await capture(app, "initial-render-unavailable")
            XCTFail("Native map did not reach a fully rendered matching camera; inspect environment metadata.")
            return
        }
        let first = read(app)
        let identity = first["mapIdentity"] as? String
        XCTAssertNotNil(identity)
        for (index, distance) in [1450.0, 4692.0].enumerated() {
            if index > 0 {
                let before = integer(read(app), "revision")
                app.buttons["uikitBuildings.far"].tap()
                guard await waitReady(app, distance: distance, requested: true, after: before) else {
                    await capture(app, "\(Int(distance))-camera-unavailable")
                    XCTFail("Requested historical camera did not render and settle; inspect metadata.")
                    return
                }
            }
            await capture(app, "\(Int(distance))-on-baseline")
            let baseline = read(app)
            checkIdentityAndConfiguration(baseline, identity: identity)
            XCTAssertEqual(baseline["actualBuildings"] as? Bool, true)

            let revision = integer(baseline, "revision")
            let writes = integer(baseline, "appWriteCount")
            app.buttons["uikitBuildings.off"].tap()
            let offReady = await waitReady(app, distance: distance, requested: false, after: revision)
            await capture(app, "\(Int(distance))-off") // Always capture even if SDK restored true.
            let off = read(app)
            XCTAssertTrue(offReady, "Off phase failed to settle; no automatic retry or retap.")
            checkIdentityAndConfiguration(off, identity: identity)
            XCTAssertEqual(integer(off, "appWriteCount"), writes + 1)
            XCTAssertEqual(off["actualBuildings"] as? Bool, false,
                           "UIKit did not retain false. This failure does not identify geometry ownership.")
            assertSameCamera(baseline, off)

            let counter = integer(off, "wrapperCounter")
            app.buttons["uikitBuildings.update"].tap()
            let updated = await waitMetadata(app, timeout: 5) {
                self.integer($0, "wrapperCounter") == counter + 1
                    && $0["phase"] as? String == "ready"
                    && $0["event"] as? String == "settled"
            }
            await capture(app, "\(Int(distance))-unrelated-swiftui-update")
            let afterUpdate = read(app)
            XCTAssertTrue(updated)
            checkIdentityAndConfiguration(afterUpdate, identity: identity)
            XCTAssertEqual(integer(afterUpdate, "appWriteCount"), writes + 1)
            XCTAssertEqual(integer(afterUpdate, "cameraWriteCount"), integer(off, "cameraWriteCount"))
            XCTAssertEqual(afterUpdate["actualBuildings"] as? Bool, false)
            assertSameCamera(baseline, afterUpdate)

            let beforeRestore = integer(afterUpdate, "revision")
            app.buttons["uikitBuildings.on"].tap()
            let restored = await waitReady(app, distance: distance, requested: true, after: beforeRestore)
            await capture(app, "\(Int(distance))-on-restored")
            let on = read(app)
            XCTAssertTrue(restored)
            checkIdentityAndConfiguration(on, identity: identity)
            XCTAssertEqual(on["actualBuildings"] as? Bool, true)
            XCTAssertEqual(integer(on, "appWriteCount"), writes + 2)
            assertSameCamera(baseline, on)
        }
    }

    /// Narrow diagnostic only: complete tiles and native geometry removal are
    /// explicitly NOT claimed. The strict render-gated test above is unchanged.
    @MainActor
    func testUIKitBuildingsPropertyRetentionWithoutRenderClaim() async {
        await runPropertyRetention(legacyMapType: false)
    }

    @MainActor
    func testUIKitLegacyMapTypePropertyRetentionWithoutRenderClaim() async {
        await runPropertyRetention(legacyMapType: true)
    }

    @MainActor
    private func runPropertyRetention(legacyMapType: Bool) async {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--verify-xinyi", "--verify-uikit-buildings-probe", "--verify-start-day"]
        if legacyMapType { app.launchArguments.append("--verify-uikit-legacy-maptype") }
        app.launch()
        guard await waitPropertyObservation(app, distance: 1450, requested: true, after: -1) else {
            await capture(app, "property-only-initial-camera-unavailable")
            XCTFail("Property-only diagnostic needs matching camera, projection and settled readback; no render claim.")
            return
        }
        let identity = read(app)["mapIdentity"] as? String
        XCTAssertNotNil(identity)
        for (index, distance) in [1450.0, 4692.0].enumerated() {
            if index > 0 {
                let before = integer(read(app), "revision")
                app.buttons["uikitBuildings.far"].tap()
                guard await waitPropertyObservation(app, distance: distance, requested: true, after: before) else {
                    await capture(app, "property-only-\(Int(distance))-camera-unavailable")
                    XCTFail("Property-only camera/settled observation unavailable; no retries.")
                    return
                }
            }
            await capture(app, "property-only-\(Int(distance))-on-baseline")
            let baseline = read(app)
            checkPropertyObservation(baseline, identity: identity, legacyMapType: legacyMapType)
            XCTAssertEqual(baseline["actualBuildings"] as? Bool, true)
            let writes = integer(baseline, "appWriteCount")
            app.buttons["uikitBuildings.off"].tap()
            let offObserved = await waitPropertyObservation(app, distance: distance, requested: false,
                                                           after: integer(baseline, "revision"))
            // Retain failed intended settings as evidence; never reapply false.
            await capture(app, "property-only-\(Int(distance))-off")
            let off = read(app)
            XCTAssertTrue(offObserved)
            checkPropertyObservation(off, identity: identity, legacyMapType: legacyMapType)
            XCTAssertEqual(off["actualBuildings"] as? Bool, false,
                           "False was not retained; property-only result makes no building visibility claim.")
            XCTAssertEqual(integer(off, "appWriteCount"), writes + 1)
            assertSameCamera(baseline, off)

            app.buttons["uikitBuildings.update"].tap()
            let updated = await waitPropertyObservation(app, distance: distance, requested: false,
                                                       after: integer(off, "revision"))
            await capture(app, "property-only-\(Int(distance))-unrelated-update")
            let afterUpdate = read(app)
            XCTAssertTrue(updated)
            checkPropertyObservation(afterUpdate, identity: identity, legacyMapType: legacyMapType)
            XCTAssertEqual(integer(afterUpdate, "wrapperCounter"), integer(off, "wrapperCounter") + 1)
            XCTAssertEqual(integer(afterUpdate, "appWriteCount"), writes + 1)
            XCTAssertEqual(integer(afterUpdate, "cameraWriteCount"), integer(off, "cameraWriteCount"))
            XCTAssertEqual(afterUpdate["actualBuildings"] as? Bool, false)
            assertSameCamera(baseline, afterUpdate)

            app.buttons["uikitBuildings.on"].tap()
            let restored = await waitPropertyObservation(app, distance: distance, requested: true,
                                                        after: integer(afterUpdate, "revision"))
            await capture(app, "property-only-\(Int(distance))-on-restored")
            let on = read(app)
            XCTAssertTrue(restored)
            checkPropertyObservation(on, identity: identity, legacyMapType: legacyMapType)
            XCTAssertEqual(on["actualBuildings"] as? Bool, true)
            XCTAssertEqual(integer(on, "appWriteCount"), writes + 2)
            assertSameCamera(baseline, on)
        }
    }

    @MainActor
    private func waitPropertyObservation(_ app: XCUIApplication, distance: Double,
                                         requested: Bool, after revision: Int) async -> Bool {
        await waitMetadata(app, timeout: 15) { fields in
            fields["event"] as? String == "settled-plus-two-seconds"
                && fields["cameraMatches"] as? Bool == true
                && fields["requestedBuildings"] as? Bool == requested
                && fields["requestedDistance"] as? Double == distance
                && self.integer(fields, "revision") > revision
                && self.hasFinitePropertyProjection(fields)
        }
    }

    private func hasFinitePropertyProjection(_ fields: [String: Any]) -> Bool {
        guard let p = fields["projection"] as? [String: Any], p["unavailable"] == nil else { return false }
        return ["x", "y", "roundtripLatitudeError", "roundtripLongitudeError"].allSatisfy {
            (p[$0] as? Double)?.isFinite == true
        }
    }

    private func checkPropertyObservation(_ fields: [String: Any], identity: String?, legacyMapType: Bool) {
        XCTAssertEqual(fields["mapIdentity"] as? String, identity)
        XCTAssertEqual(fields["event"] as? String, "settled-plus-two-seconds")
        XCTAssertEqual(fields["cameraMatches"] as? Bool, true)
        XCTAssertEqual(integer(fields, "configurationWriteCount"), legacyMapType ? 0 : 1)
        XCTAssertEqual(integer(fields, "mapTypeWriteCount"), legacyMapType ? 1 : 0)
        XCTAssertEqual(integer(fields, "mapType"), 0) // MKMapType.standard
        XCTAssertEqual(fields["initializationRoute"] as? String,
                       legacyMapType ? "legacy-maptype" : "preferred-configuration")
        XCTAssertEqual(fields["elevation"] as? String, "flat")
        XCTAssertEqual(fields["emphasis"] as? String, "default")
        XCTAssertTrue(hasFinitePropertyProjection(fields))
        let projection = fields["projection"] as? [String: Any] ?? [:]
        for key in ["roundtripLatitudeError", "roundtripLongitudeError"] {
            XCTAssertLessThan((projection[key] as? Double) ?? .infinity, 0.000001)
        }
        // Deliberately no assertion on phase, initialFullyRendered or render count.
    }

    private func integer(_ fields: [String: Any], _ key: String) -> Int {
        (fields[key] as? NSNumber)?.intValue ?? -1
    }

    @MainActor
    private func read(_ app: XCUIApplication) -> [String: Any] {
        let element = app.staticTexts["uikitBuildings.metadata"]
        guard element.exists, let value = element.value as? String,
              let data = value.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return fields
    }

    @MainActor
    private func waitMetadata(_ app: XCUIApplication, timeout: TimeInterval,
                              matches: ([String: Any]) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if matches(read(app)) { return true }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return false }
        }
        return matches(read(app))
    }

    @MainActor
    private func waitReady(_ app: XCUIApplication, distance: Double, requested: Bool, after revision: Int) async -> Bool {
        await waitMetadata(app, timeout: 25) { fields in
            fields["phase"] as? String == "ready"
                && fields["initialFullyRendered"] as? Bool == true
                && fields["cameraMatches"] as? Bool == true
                && fields["requestedBuildings"] as? Bool == requested
                && fields["requestedDistance"] as? Double == distance
                && self.integer(fields, "revision") > revision
        }
    }

    private func checkIdentityAndConfiguration(_ fields: [String: Any], identity: String?) {
        XCTAssertEqual(fields["mapIdentity"] as? String, identity)
        XCTAssertEqual(integer(fields, "configurationWriteCount"), 1)
        XCTAssertEqual(fields["elevation"] as? String, "flat")
        XCTAssertEqual(fields["emphasis"] as? String, "default")
        XCTAssertEqual(fields["initialFullyRendered"] as? Bool, true)
        let projection = fields["projection"] as? [String: Any] ?? [:]
        XCTAssertNil(projection["unavailable"])
        for key in ["roundtripLatitudeError", "roundtripLongitudeError"] {
            XCTAssertLessThan((projection[key] as? Double) ?? .infinity, 0.000001)
        }
    }

    private func assertSameCamera(_ a: [String: Any], _ b: [String: Any]) {
        let first = a["camera"] as? [String: Double] ?? [:]
        let second = b["camera"] as? [String: Double] ?? [:]
        for key in ["latitude", "longitude", "distance", "heading", "pitch"] {
            guard let lhs = first[key], let rhs = second[key] else {
                XCTFail("Missing camera field \(key)"); continue
            }
            XCTAssertEqual(lhs, rhs, accuracy: key == "distance" ? 0.1 : 0.000001)
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) async {
        // Keep observing for two seconds after the bounded settle wait. A late
        // SDK reset must appear in the evidence; never reapply the requested flag.
        do { try await Task.sleep(for: .seconds(2)) } catch {
            XCTFail("Capture observation was cancelled: \(name)")
        }
        if read(app)["phase"] as? String == "ready" {
            let observed = await waitMetadata(app, timeout: 3) {
                $0["event"] as? String == "settled-plus-two-seconds"
            }
            XCTAssertTrue(observed, "Missing live readback after two settled seconds; capture still retained.")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "uikit-buildings-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let fields = read(app)
        let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        metadata.name = "uikit-buildings-\(name)-metadata"
        metadata.lifetime = .keepAlways
        add(metadata)
    }
}
