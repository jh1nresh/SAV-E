import UIKit
import XCTest

/// Shared lifecycle for the Savvy UI suite.
///
/// Everything here exists because of one property of the CI runner: it is
/// shared hardware, and its speed varies by several multiples between runs. The
/// same test has been observed at 44s on one main run and 166s on the next, and
/// `testPassportAndPostalImportSurfacesAreReachable` has gone from 65s to 257s
/// without a single source change. Waits tuned on a developer Mac therefore
/// expire on CI while the app is still perfectly healthy, which is why the
/// suite went red on main without a regression behind it.
///
/// Three lifecycle rules follow from that, and every test in the suite goes
/// through them:
///
/// 1. Waits go through `timeout(_:)`, which budgets them for the slowest
///    runner rather than for a developer Mac.
/// 2. A test terminates the app it launched. XCTest otherwise leaves it
///    running, and the *next* test's `launch()` inherits the job of killing it
///    — surfacing as "Failed to terminate com.wanderly.app" attributed to an
///    innocent test.
/// 3. Text is typed only once the keyboard is actually up, because tapping a
///    field does not synchronously give it focus on a loaded simulator.
class SAVEUITestCase: XCTestCase {

    /// Headroom applied to every wait in the suite.
    ///
    /// Sized from the worst slowdown seen on CI: `testProofFirstFlowReachesOpenAppCTA`
    /// has run in 44s and, unchanged, in 166s — a factor of ~3.8. Waits are
    /// therefore budgeted at 4x what a developer Mac needs.
    ///
    /// This costs nothing when a test passes, because every wait returns the
    /// moment its element appears; the budget is only ever spent on the way to
    /// a failure. It also weakens no assertion — a real regression never
    /// produces the element, however long we wait.
    ///
    /// Deliberately a constant rather than an environment variable: host
    /// environment does not reach the on-simulator test runner (neither plain
    /// env vars nor the `TEST_RUNNER_` build-setting prefix survive the trip),
    /// so a configurable knob here would silently read as "1" on CI — exactly
    /// where the headroom is needed.
    private static let timeoutScale: Double = 4

    /// Scales `base` for the slowest environment the suite runs in. Use this
    /// for every wait rather than passing a literal to
    /// `waitForExistence(timeout:)`.
    func timeout(_ base: TimeInterval) -> TimeInterval {
        base * Self.timeoutScale
    }

    /// The default budget for a single UI step (an element appearing, a screen
    /// transition settling).
    var stepTimeout: TimeInterval { timeout(10) }

    /// The budget for reaching first content after a launch. Cold start on a
    /// freshly erased simulator is far slower than a warm relaunch.
    var launchTimeout: TimeInterval { timeout(30) }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - App lifecycle

    /// Builds an app handle and registers it for termination at teardown.
    ///
    /// Prefer this over `XCUIApplication()` so no test can leak a running app
    /// into the next one.
    @MainActor
    func makeApp(
        launchArguments: [String] = [],
        launchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += launchArguments
        for (key, value) in launchEnvironment {
            app.launchEnvironment[key] = value
        }

        addTeardownBlock { @MainActor in
            self.terminate(app)
        }
        return app
    }

    /// Launches `app` from a known-stopped state.
    ///
    /// `XCUIApplication.launch()` terminates any running instance first, and it
    /// is that implicit terminate — not the launch — that intermittently fails
    /// on CI. Terminating explicitly first keeps the wait bounded and the
    /// failure attributable.
    @MainActor
    func launch(_ app: XCUIApplication) {
        terminate(app)
        app.launch()
    }

    /// Terminates `app` and waits for the simulator to agree it is gone.
    ///
    /// `terminate()` only requests termination; returning before the process
    /// has actually exited is what leaves the next `launch()` racing a
    /// still-dying process.
    @MainActor
    func terminate(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.terminate()

        let stopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue),
            object: app
        )
        _ = XCTWaiter.wait(for: [stopped], timeout: timeout(30))
    }

    // MARK: - Text entry

    /// Taps `element` until it actually holds keyboard focus, so the next
    /// `typeText` has somewhere to go.
    ///
    /// Typing straight after `tap()` fails as "Neither element nor any
    /// descendant has keyboard focus" when the simulator is slow to hand focus
    /// over. Retapping is safe: a tap on an already-focused field only moves
    /// the caret.
    ///
    /// Focus is checked per element, not by asking whether a keyboard is on
    /// screen. Moving between two fields in the same form leaves the keyboard
    /// up throughout, so its presence says nothing about whether *this* tap
    /// landed — which is exactly how the Trip stop editor still failed on
    /// `trip.stop.edit.duration` after the first pass at this helper.
    @MainActor
    @discardableResult
    func focus(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        XCTAssertTrue(
            element.waitForExistence(timeout: stepTimeout),
            "Field never appeared, cannot focus it.",
            file: file,
            line: line
        )

        for _ in 0..<3 {
            // XCTest expectations are single-use, including after a timeout.
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                object: element
            )
            element.tap()
            if XCTWaiter.wait(for: [focused], timeout: timeout(5)) == .completed {
                return true
            }
        }

        XCTFail(
            "'\(element.identifier)' never took keyboard focus, so typing would drop the text.",
            file: file,
            line: line
        )
        return false
    }

    /// Focuses `element` and types `text` into it.
    @MainActor
    func typeText(
        _ text: String,
        into element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        focus(element, file: file, line: line)
        element.typeText(text)
    }

    // MARK: - Waiting

    @MainActor
    func waitUntilHittable(_ element: XCUIElement, timeout budget: TimeInterval? = nil) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: budget ?? stepTimeout) == .completed
    }

    // MARK: - Evidence

    @MainActor
    func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SAVE_SCREENSHOT_DIR"],
           !dir.isEmpty {
            let url = URL(fileURLWithPath: dir)
                .appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    /// Median RGB from several points just below the status bar on the left
    /// margin, where Home/Passport show the notebook canvas rather than cards.
    @MainActor
    func sampleScreenshotBackground(_ screenshot: XCUIScreenshot) -> SampledRGB {
        let image = screenshot.image
        guard let cgImage = image.cgImage else {
            return SampledRGB(red: 0, green: 0, blue: 0)
        }
        let scale = image.scale
        let points: [(CGFloat, CGFloat)] = [
            (3, 64), (5, 72), (4, 90), (6, 140), (3, 220),
        ]
        var reds: [Int] = []
        var greens: [Int] = []
        var blues: [Int] = []
        for (x, y) in points {
            let px = min(max(Int((x * scale).rounded()), 0), cgImage.width - 1)
            let py = min(max(Int((y * scale).rounded()), 0), cgImage.height - 1)
            guard let pixel = samplePixel(cgImage, x: px, y: py) else { continue }
            reds.append(pixel.red)
            greens.append(pixel.green)
            blues.append(pixel.blue)
        }
        guard !reds.isEmpty else {
            return SampledRGB(red: 0, green: 0, blue: 0)
        }
        return SampledRGB(
            red: medianChannel(reds),
            green: medianChannel(greens),
            blue: medianChannel(blues)
        )
    }

    @MainActor
    @discardableResult
    func assertScreenshotBackground(
        _ screenshot: XCUIScreenshot,
        nearRed red: Int,
        green: Int,
        blue: Int,
        name: String,
        tolerance: Int = 32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SampledRGB {
        let sample = sampleScreenshotBackground(screenshot)
        let note = XCTAttachment(string: "\(name) background \(sample.hex) luminance=\(Int(sample.luminance.rounded()))")
        note.name = "\(name)-bg-hex"
        note.lifetime = .keepAlways
        add(note)
        print("SAVE_CANVAS_BG \(name)=\(sample.hex)")
        let expected = String(format: "#%02X%02X%02X", red, green, blue)
        XCTAssertLessThanOrEqual(
            abs(sample.red - red),
            tolerance,
            "\(name) R \(sample.hex) is not near \(expected)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(sample.green - green),
            tolerance,
            "\(name) G \(sample.hex) is not near \(expected)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(sample.blue - blue),
            tolerance,
            "\(name) B \(sample.hex) is not near \(expected)",
            file: file,
            line: line
        )
        if red < 80 {
            XCTAssertLessThan(
                sample.luminance,
                80,
                "\(name) must be dark near #1E1C19, got \(sample.hex) luminance \(sample.luminance)",
                file: file,
                line: line
            )
        } else {
            XCTAssertGreaterThan(
                sample.luminance,
                200,
                "\(name) must be light near #FFF9EB, got \(sample.hex) luminance \(sample.luminance)",
                file: file,
                line: line
            )
        }
        return sample
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> SampledRGB? {
        guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            return nil
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let ok = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        return SampledRGB(red: Int(pixel[0]), green: Int(pixel[1]), blue: Int(pixel[2]))
    }

    private func medianChannel(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

struct SampledRGB: Equatable, CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var luminance: Double {
        0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
    }

    var description: String { hex }
}
