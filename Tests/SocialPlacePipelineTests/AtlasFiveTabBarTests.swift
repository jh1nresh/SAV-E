import XCTest
@testable import SAVE

/// W2/W3 from `specs/2026-08-24-save-tab-restructure-and-origin-surface-v0.md`.
///
/// These assertions exist because the four-tab bar only ever fit by luck: the
/// selection pill was hardcoded to 90pt against a ~98.5pt slot. A fifth item
/// makes the slot ~78.8pt, so a fixed pill would overflow into its neighbours.
final class AtlasFiveTabBarTests: XCTestCase {
    // MARK: - Tab shape

    @MainActor
    func testRootBarIsFiveItemsInTheSpecifiedOrder() {
        XCTAssertEqual(
            SaveRootTab.allCases,
            [.home, .map, .capture, .origin, .profile]
        )
        XCTAssertEqual(SaveRootTab.allCases.count, 5)
    }

    @MainActor
    func testCaptureIsAControlNotADestination() {
        XCTAssertTrue(SaveRootTab.capture.isCaptureControl)
        XCTAssertEqual(SaveRootTab.destinations, [.home, .map, .origin, .profile])
        for tab in SaveRootTab.destinations {
            XCTAssertFalse(tab.isCaptureControl, "\(tab) should be a destination")
        }
    }

    @MainActor
    func testCaptureSitsInTheCentreSlot() {
        // The raised capture control only reads as centre if it is literally
        // the middle item of an odd-length bar.
        let all = SaveRootTab.allCases
        XCTAssertEqual(all.count % 2, 1)
        XCTAssertEqual(all[all.count / 2], .capture)
    }

    // MARK: - Layout (the bug this work item exists to prevent)

    @MainActor
    func testSelectionPillFitsItsSlotAtFourAndFiveItems() {
        for count in 2...6 {
            XCTAssertTrue(
                AtlasTabBarMetrics.pillFitsSlot(itemCount: count),
                "pill overflows its slot at \(count) items"
            )
        }
    }

    @MainActor
    func testFixedNinetyPointPillWouldHaveOverflowedAtFiveItems() {
        // Documents the regression rather than trusting a comment: the old
        // hardcoded value fit four items and does not fit five.
        let legacyPillWidth: CGFloat = 90
        XCTAssertGreaterThan(AtlasTabBarMetrics.slotWidth(itemCount: 4), legacyPillWidth)
        XCTAssertLessThan(AtlasTabBarMetrics.slotWidth(itemCount: 5), legacyPillWidth)
    }

    @MainActor
    func testPillWidthIsDerivedFromSlotAndNeverZero() {
        let five = AtlasTabBarMetrics.pillWidth(itemCount: 5)
        let four = AtlasTabBarMetrics.pillWidth(itemCount: 4)
        XCTAssertLessThan(five, four, "more items must yield a narrower pill")
        XCTAssertGreaterThanOrEqual(five, AtlasTabBarMetrics.minimumPillWidth)
        XCTAssertEqual(AtlasTabBarMetrics.slotWidth(itemCount: 0), 0)
    }

    // MARK: - Icons (W3)

    @MainActor
    func testEveryTabHasADistinctNonDefaultGlyph() {
        let icons = SaveRootTab.allCases.map(\.atlasIcon)
        XCTAssertEqual(Set(icons).count, icons.count, "tab glyphs must be distinct")

        // The pre-W3 set was unreviewed SF Symbol defaults. Guard the two that
        // were actively wrong: a briefcase for Trips and a globe for a
        // city-scale map.
        XCTAssertFalse(icons.contains("briefcase"))
        XCTAssertFalse(icons.contains("globe"))
    }

    @MainActor
    func testOnlyOneIconSetSurvives() throws {
        // `systemImage` was a second, unread icon property. Deleting it is the
        // point of W3.1; this fails if someone reintroduces a parallel set.
        let source = try contentViewSource()
        let enumBody = try enumBody("SaveRootTab", in: source)
        XCTAssertTrue(enumBody.contains("var atlasIcon: String"))
        XCTAssertFalse(
            enumBody.contains("var systemImage: String"),
            "SaveRootTab must expose exactly one icon set"
        )
    }

    // MARK: - Localization

    @MainActor
    func testEveryTabIsLocalizedInBothLanguages() {
        for tab in SaveRootTab.allCases {
            let english = tab.title(language: .english)
            let chinese = tab.title(language: .traditionalChinese)
            XCTAssertFalse(english.isEmpty, "\(tab) missing English title")
            XCTAssertFalse(chinese.isEmpty, "\(tab) missing zh-Hant title")
            XCTAssertNotEqual(
                english,
                chinese,
                "\(tab) zh-Hant title looks like an untranslated fallback"
            )
        }
        XCTAssertEqual(SaveRootTab.origin.title(language: .traditionalChinese), "來處")
    }

    // MARK: - Origin honesty (W4)

    @MainActor
    func testOriginDoesNotImplyOtherUsers() throws {
        let source = try source(at: "SAV-E/Views/Origin/SaveOriginView.swift")
        // Production has one user, zero place_visibility rows and zero
        // place_social_signals rows (measured 2026-08-24). Any of these strings
        // on this surface would be a fabricated social signal.
        for forbidden in ["people saved", "friends", "trending", "popular", "nearby saved"] {
            XCTAssertFalse(
                source.lowercased().contains(forbidden),
                "Origin must not imply other users: found '\(forbidden)'"
            )
        }
    }

    @MainActor
    func testOriginShowsVerbatimSourceAndExactlyTwoBacklogActions() throws {
        let source = try source(at: "SAV-E/Views/Origin/SaveOriginView.swift")
        XCTAssertTrue(source.contains("Text(rawText)"), "Origin must render the stored source text verbatim")
        XCTAssertTrue(source.contains("Link(destination: url)"), "Origin must link to the original source")
        XCTAssertTrue(source.contains("Dictionary(grouping:"), "One capture must remain one source card")
        XCTAssertTrue(source.contains("origin.backlog.plan"))
        XCTAssertTrue(source.contains("origin.backlog.archive"))
        let backlogBody = source
            .components(separatedBy: "private func backlogCard")[1]
            .components(separatedBy: "private func sectionLabel")[0]
        XCTAssertEqual(backlogBody.components(separatedBy: "Button").count - 1, 2)
    }

    @MainActor
    func testOriginCapturePayloadDecodesOwnerSourceFields() throws {
        let id = UUID()
        let payload = """
        [{
          "id": "\(id.uuidString)",
          "source_type": "url",
          "source_url": "https://example.com/post/1",
          "raw_text": "Exact original words",
          "title": "Saved post",
          "status": "review",
          "created_at": "2026-08-24T18:00:00.000Z"
        }]
        """.data(using: .utf8)!

        let captures = try SupabaseService.decodeOriginCaptures(payload)
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].id, id)
        XCTAssertEqual(captures[0].rawText, "Exact original words")
        XCTAssertEqual(captures[0].originalURL?.host, "example.com")
    }

    @MainActor
    func testOriginCaptureOnlyOpensHTTPLinks() {
        let id = UUID()
        let safe = SaveOriginCapture(
            id: id,
            sourceURL: "https://example.com/post/1",
            rawText: "Original clue",
            title: nil,
            createdAt: .distantPast
        )
        let unsafe = SaveOriginCapture(
            id: id,
            sourceURL: "file:///private/source.txt",
            rawText: nil,
            title: nil,
            createdAt: .distantPast
        )
        XCTAssertEqual(safe.originalURL?.absoluteString, "https://example.com/post/1")
        XCTAssertNil(unsafe.originalURL)
        XCTAssertFalse(unsafe.hasDisplayableSource)
    }

    // MARK: - Helpers

    private func contentViewSource() throws -> String {
        try source(at: "SAV-E/App/ContentView.swift")
    }

    private func enumBody(_ name: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("enum \(name)") }) else {
            XCTFail("Missing enum \(name)")
            return ""
        }
        var end = lines.endIndex
        for index in lines.index(after: start)..<lines.endIndex where lines[index] == "}" {
            end = lines.index(after: index)
            break
        }
        return lines[start..<end].joined(separator: "\n")
    }

    private func source(at relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
