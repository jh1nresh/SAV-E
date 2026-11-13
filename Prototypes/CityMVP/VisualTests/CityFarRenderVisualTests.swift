import XCTest

/// Same-binary fog control/candidate comparison; this does not approve the
/// unresolved native tower or the ownership of duplicated map labels.
final class CityFarRenderVisualTests: XCTestCase {
    @MainActor
    func testFarFogAtMatchedDayAndNightCameras() throws {
        continueAfterFailure = false
        for night in [false, true] {
            var reference: [String: Any]?
            for legacy in [true, false] {
                let app = XCUIApplication()
                app.launchArguments += ["--verify-xinyi", "--verify-xinyi-auto",
                                        "--verify-xinyi-selected", "--verify-xinyi-far-render",
                                        "-cityMVP.night", night ? "YES" : "NO"]
                if legacy { app.launchArguments.append("--verify-legacy-fog") }
                app.launch()
                let fixture = app.descendants(matching: .any)["cityMVP.farRenderFixture"].firstMatch
                // Let the accessibility query match readiness in one snapshot.
                // Reading/parsing fixture.value in a runner-side predicate made
                // multiple hierarchy requests per poll in the failed run.
                let readyFixture = app.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier == %@ AND value CONTAINS %@",
                    "cityMVP.farRenderFixture", "\"ready\":true")).firstMatch
                let label = "far-fog-\(night ? "night" : "day")-\(legacy ? "legacy" : "candidate")"
                guard readyFixture.waitForExistence(timeout: 45) else {
                    capture(app, label + "-FAIL")
                    XCTFail("Fixed far camera or prepared scene unavailable: \(fixture.value ?? "missing")")
                    return
                }
                // Readiness is not tile completion; allow the identical two-second
                // visual settle in both control and candidate before capturing.
                Thread.sleep(forTimeInterval: 2)
                let value = try XCTUnwrap(fixture.value as? String)
                let data = try XCTUnwrap(value.data(using: .utf8))
                let sample = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                metadata.name = label + "-camera"
                metadata.lifetime = .keepAlways
                add(metadata)
                capture(app, label)
                func number(_ key: String) throws -> Double {
                    try XCTUnwrap(sample[key] as? Double, "Missing camera field \(key)")
                }
                XCTAssertEqual(sample["ready"] as? Bool, true,
                               "Scene/projection readiness must survive the visual settle")
                XCTAssertEqual(try number("distance"), 4_692, accuracy: 2)
                XCTAssertEqual(try number("heading"), 20, accuracy: 0.1)
                XCTAssertEqual(try number("pitch"), 35, accuracy: 0.1)
                XCTAssertEqual(try number("width"), 393, accuracy: 1)
                XCTAssertEqual(try number("height"), 852, accuracy: 1)
                XCTAssertLessThan(try number("fitError"), 2)
                XCTAssertGreaterThanOrEqual(try number("fitError"), 0)
                XCTAssertGreaterThan(try number("pinX"), 0)
                XCTAssertLessThan(try number("pinX"), try number("width"))
                XCTAssertGreaterThan(try number("pinY"), 0)
                XCTAssertLessThan(try number("pinY"), try number("height"))
                XCTAssertTrue(app.buttons["cityMVP.selectedGroundPin"].exists)
                if let reference {
                    for key in ["distance", "heading", "pitch", "width", "height", "pinX", "pinY"] {
                        XCTAssertEqual(try number(key), try XCTUnwrap(reference[key] as? Double),
                                       accuracy: 1, "The two fog modes must retain \(key)")
                    }
                    for key in ["latitude", "longitude"] {
                        XCTAssertEqual(try number(key), try XCTUnwrap(reference[key] as? Double), accuracy: 0.000001)
                    }
                } else { reference = sample }
                app.terminate()
            }
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
