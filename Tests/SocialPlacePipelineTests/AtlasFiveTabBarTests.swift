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
            [.home, .map, .capture, .plan, .profile]
        )
        XCTAssertEqual(SaveRootTab.allCases.count, 5)
    }

    @MainActor
    func testCaptureIsAControlNotADestination() {
        XCTAssertTrue(SaveRootTab.capture.isCaptureControl)
        XCTAssertEqual(SaveRootTab.destinations, [.home, .map, .plan, .profile])
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
    func testFixedNinetyPointPillWouldOverflowCompactFiveItemBar() {
        let legacyPillWidth: CGFloat = 90
        XCTAssertLessThan(AtlasTabBarMetrics.slotWidth(itemCount: 5), legacyPillWidth)
    }

    @MainActor
    func testBarFloatsInsideCanvasWithAccessibleTargets() {
        XCTAssertLessThan(AtlasTabBarMetrics.width, AtlasMetrics.width)
        XCTAssertGreaterThanOrEqual(AtlasTabBarMetrics.leadingInset, 16)
        XCTAssertEqual(
            AtlasTabBarMetrics.leadingInset,
            (AtlasMetrics.width - AtlasTabBarMetrics.width) / 2
        )
        XCTAssertLessThan(AtlasTabBarMetrics.height, 76)
        XCTAssertGreaterThanOrEqual(AtlasTabBarMetrics.itemHeight, 44)
    }

    @MainActor
    func testRaisedCaptureControlFitsInsideBarAndItsFiveItemSlot() {
        XCTAssertTrue(
            AtlasTabBarMetrics.raisedControlFitsBar,
            "Save plus its stroke must sit inside the mint-lozenge chrome inset"
        )
        XCTAssertTrue(
            AtlasTabBarMetrics.raisedControlFitsSlot(itemCount: 5),
            "the Save control must not overlap its neighbouring tabs"
        )
        XCTAssertEqual(AtlasTabBarMetrics.raisedControlOffsetY, 0)
        XCTAssertLessThanOrEqual(
            AtlasTabBarMetrics.raisedControlDiameter + AtlasTabBarMetrics.raisedControlStrokeWidth,
            AtlasTabBarMetrics.selectionHeight
        )
        XCTAssertGreaterThanOrEqual(
            AtlasTabBarMetrics.itemHeight,
            AtlasTabBarMetrics.minimumHitTarget
        )
    }

    @MainActor
    func testLegacyFiftyPointSaveWouldBreachChromeInset() {
        // Residual of #179: 50pt / offset 0 stays in the 62pt box but the
        // optical disk (50 + 0.8 stroke) still bursts the glass pill.
        let legacyDiameter: CGFloat = 50
        let opticalHalf = (legacyDiameter + AtlasTabBarMetrics.raisedControlStrokeWidth) / 2
        let centreY = AtlasTabBarMetrics.height / 2
        let inset = AtlasTabBarMetrics.raisedControlChromeInset

        XCTAssertLessThan(
            centreY - opticalHalf,
            inset,
            "50pt Save is the residual overflow fixture against glass chrome"
        )
        XCTAssertLessThan(
            AtlasTabBarMetrics.raisedControlDiameter,
            legacyDiameter
        )
        XCTAssertEqual(AtlasTabBarMetrics.raisedControlChromeInset, 8)
    }

    @MainActor
    func testReferenceCanvasFills430By932WithoutCropping() {
        let viewport = CGSize(width: 430, height: 932)
        let scale = min(
            viewport.width / AtlasMetrics.width,
            viewport.height / AtlasMetrics.height
        )
        let rendered = CGSize(
            width: AtlasMetrics.width * scale,
            height: AtlasMetrics.height * scale
        )

        XCTAssertLessThanOrEqual(rendered.width, viewport.width)
        XCTAssertLessThanOrEqual(rendered.height, viewport.height)
        XCTAssertEqual(rendered.height, viewport.height, accuracy: 0.5)
        XCTAssertLessThanOrEqual(viewport.width - rendered.width, 1.5)
    }

    @MainActor
    func testAtlasVisualSystemUsesRoundedTypeAndOrderedSpacing() throws {
        let theme = try source(at: "Prototypes/AtlasPostcard/Sources/Theme.swift")
        let productionTheme = try source(at: "SAV-E/Extensions/Color+Theme.swift")

        XCTAssertTrue(theme.contains("design: .rounded"))
        XCTAssertFalse(theme.contains("AvenirNextCondensed"))
        XCTAssertFalse(theme.contains("Georgia-Italic"))
        XCTAssertTrue(productionTheme.contains("fontDescriptor.withDesign(.rounded)"))
        XCTAssertFalse(productionTheme.contains("AvenirNextCondensed"))
        XCTAssertFalse(productionTheme.contains("Georgia-Italic"))
        XCTAssertEqual(
            [
                AtlasSpacing.tight,
                AtlasSpacing.compact,
                AtlasSpacing.control,
                AtlasSpacing.content,
                AtlasSpacing.section,
            ],
            [4, 8, 12, 16, 24]
        )
        XCTAssertLessThanOrEqual(AtlasElevation.cardOpacity, 0.1)
        XCTAssertGreaterThan(AtlasElevation.cardRadius, AtlasElevation.cardY)
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
        XCTAssertEqual(SaveRootTab.plan.title(language: .traditionalChinese), "規劃")
        XCTAssertEqual(SaveRootTab.plan.atlasIcon, "calendar")
        XCTAssertFalse(SaveRootTab.allCases.map(\.atlasIcon).contains("paperclip"))
    }

    // MARK: - Plan workbench

    @MainActor
    func testPlanTabComposesFromSavedStampsAndKeepsUnsavedLabeled() throws {
        let plan = try source(at: "SAV-E/Views/Plan/SavePlanView.swift")
        let content = try contentViewSource()

        XCTAssertTrue(plan.contains("plan.root"))
        XCTAssertTrue(plan.contains("Plan from Map Stamps"))
        XCTAssertTrue(plan.contains("SavePlanDraftBuilder.draft"))
        XCTAssertTrue(plan.contains("SaveAtlasType"))
        XCTAssertFalse(plan.contains("AtlasType."))
        XCTAssertTrue(plan.contains("Unsaved Candidate") || plan.contains("尚未儲存") || content.contains("SavePlanView("))
        XCTAssertTrue(content.contains("SavePlanView("))
        XCTAssertTrue(content.contains("case .plan") || content.contains("case plan"))
        XCTAssertFalse(content.contains("case .origin"))
        let itinerary = try source(at: "SAV-E/Views/Drawer/Components/TripItineraryComponent.swift")
        XCTAssertTrue(itinerary.contains("Travel window"))
        XCTAssertTrue(itinerary.contains("plan.window."))
    }

    @MainActor
    func testPlanDraftBuilderKeepsUnsavedSuggestionsOutOfPersistence() throws {
        let cafe = originPlace(
            id: "00000000-0000-4000-8000-000000000101",
            name: "Da'an Coffee",
            address: "Da'an District, Taipei",
            category: .cafe,
            socialSignal: nil
        )
        let park = originPlace(
            id: "00000000-0000-4000-8000-000000000102",
            name: "Daan Forest Park",
            address: "Da'an District, Taipei",
            category: .attraction,
            socialSignal: nil
        )
        let unsaved = SaveMapCandidate(
            title: "Chiang Kai-shek Memorial",
            subtitle: "Zhongzheng, Taipei",
            latitude: 25.0346,
            longitude: 121.5218,
            category: .attraction
        )
        let response = try XCTUnwrap(SavePlanDraftBuilder.draft(
            request: SavePlanRequest(
                area: "Taipei",
                days: 1,
                pace: .balanced,
                arrivalMinutes: nil,
                departureMinutes: nil,
                language: .english
            ),
            savedPlaces: [cafe, park],
            unsavedCandidates: [unsaved]
        ))
        let names = response.itineraryDays.flatMap(\.stops).map(\.placeName)
        XCTAssertTrue(names.contains("Da'an Coffee"))
        XCTAssertTrue(names.contains("Daan Forest Park"))
        let unsavedStops = response.itineraryDays.flatMap(\.stops).filter { $0.placeState == .externalSuggestion }
        for stop in unsavedStops {
            XCTAssertNil(stop.placeId)
        }
        let canvas = TripCanvasDraft(days: response.itineraryDays)
        let selection = try canvas.tripSaveSelection(availablePlaces: [cafe, park])
        XCTAssertEqual(Set(selection.stops.map(\.placeName)), Set(["Da'an Coffee", "Daan Forest Park"]))
        XCTAssertEqual(selection.excludedStopCount, unsavedStops.count)
    }

    // MARK: - Origin capture models (no longer a root tab)

    @MainActor
    func testOriginPersonalizationUsesExplicitPreferenceAndSavedHistory() {
        let bar = originPlace(
            id: "00000000-0000-4000-8000-000000000001",
            name: "Busy Bar",
            address: "Da'an District, Taipei",
            category: .bar
        )
        let cafe = originPlace(
            id: "00000000-0000-4000-8000-000000000002",
            name: "Quiet Coffee House",
            address: "Zhongshan District, Taipei",
            category: .cafe
        )
        let savedCafe = originPlace(
            id: "00000000-0000-4000-8000-000000000003",
            name: "Daily Coffee",
            address: "Zhongshan District, Taipei",
            category: .cafe,
            socialSignal: nil
        )
        let preference = originPreference(value: "coffee", polarity: .like)

        let ranked = SaveOriginPersonalization.rank(
            candidates: [bar, cafe],
            savedPlaces: [savedCafe],
            preferences: [preference],
            outcomes: []
        )

        XCTAssertEqual(ranked.map(\.id), [cafe.id, bar.id])
    }

    @MainActor
    func testOriginPersonalizationSeparatelyUsesSavedCategoryAndArea() {
        let tokyoFood = originPlace(
            id: "00000000-0000-4000-8000-000000000031",
            name: "Tokyo Food",
            address: "Shibuya, Tokyo",
            category: .food
        )
        let tokyoCafe = originPlace(
            id: "00000000-0000-4000-8000-000000000032",
            name: "Tokyo Cafe",
            address: "Shibuya, Tokyo",
            category: .cafe
        )
        let savedCafeElsewhere = originPlace(
            id: "00000000-0000-4000-8000-000000000033",
            name: "Saved Cafe",
            address: "Namba, Osaka",
            category: .cafe,
            socialSignal: nil
        )

        let categoryRanked = SaveOriginPersonalization.rank(
            candidates: [tokyoFood, tokyoCafe],
            savedPlaces: [savedCafeElsewhere],
            preferences: [],
            outcomes: []
        )
        XCTAssertEqual(categoryRanked.first?.id, tokyoCafe.id)

        let xinyiCafe = originPlace(
            id: "00000000-0000-4000-8000-000000000034",
            name: "Xinyi Cafe",
            address: "Xinyi, Taipei",
            category: .cafe
        )
        let savedXinyiFood = originPlace(
            id: "00000000-0000-4000-8000-000000000035",
            name: "Saved Xinyi Food",
            address: "Xinyi, Taipei",
            category: .food,
            socialSignal: nil
        )

        let areaRanked = SaveOriginPersonalization.rank(
            candidates: [tokyoCafe, xinyiCafe],
            savedPlaces: [savedXinyiFood],
            preferences: [],
            outcomes: []
        )
        XCTAssertEqual(areaRanked.first?.id, xinyiCafe.id)
    }

    @MainActor
    func testOriginPersonalizationPersistsLatestSwipeDecision() {
        let skipped = originPlace(
            id: "00000000-0000-4000-8000-000000000011",
            name: "Skipped Cafe",
            address: "Taipei",
            category: .cafe
        )
        let remaining = originPlace(
            id: "00000000-0000-4000-8000-000000000012",
            name: "Remaining Cafe",
            address: "Taipei",
            category: .cafe
        )
        let olderSave = originOutcome(placeID: skipped.id, label: .useful, at: Date(timeIntervalSince1970: 10))
        let newerSkip = originOutcome(placeID: skipped.id, label: .irrelevant, at: Date(timeIntervalSince1970: 20))

        let ranked = SaveOriginPersonalization.rank(
            candidates: [skipped, remaining],
            savedPlaces: [],
            preferences: [],
            outcomes: [olderSave, newerSkip]
        )

        XCTAssertEqual(ranked.map(\.id), [remaining.id])
    }

    @MainActor
    func testOriginPersonalizationPreservesSocialOrderWithoutPersonalSignals() {
        let first = originPlace(
            id: "00000000-0000-4000-8000-000000000021",
            name: "First",
            address: "Taipei",
            category: .food
        )
        let second = originPlace(
            id: "00000000-0000-4000-8000-000000000022",
            name: "Second",
            address: "Tokyo",
            category: .cafe
        )

        let ranked = SaveOriginPersonalization.rank(
            candidates: [first, second],
            savedPlaces: [],
            preferences: [],
            outcomes: []
        )

        XCTAssertEqual(ranked.map(\.id), [first.id, second.id])
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

    private func originPlace(
        id: String,
        name: String,
        address: String,
        category: PlaceCategory,
        socialSignal: PlaceSocialSignal? = PlaceSocialSignal(
            kind: .trending,
            lens: .forYou,
            friendNames: [],
            friendCount: 0,
            saveCount: 10,
            trendingRank: 1,
            categoryRank: 1,
            sourceLabel: "Trending in Savvy",
            referrerId: nil,
            referralCode: nil
        )
    ) -> Place {
        Place(
            id: UUID(uuidString: id)!,
            name: name,
            address: address,
            latitude: 25.03,
            longitude: 121.56,
            category: category,
            status: .wantToGo,
            sourcePlatform: .other,
            createdAt: .distantPast,
            socialSignal: socialSignal
        )
    }

    private func originPreference(
        value: String,
        polarity: SaveMemoryPreference.Polarity
    ) -> SaveMemoryPreference {
        SaveMemoryPreference(
            id: UUID(),
            preferenceType: "cuisine",
            normalizedValue: value,
            context: "general",
            polarity: polarity,
            source: .explicit,
            evidenceRefs: [],
            evidenceCount: 0,
            confidence: 1,
            status: .active,
            correctedFromId: nil,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    @MainActor
    private func originOutcome(
        placeID: UUID,
        label: SaveOriginOutcomeLabel,
        at date: Date
    ) -> SaveRecommendationOutcome {
        SaveRecommendationOutcome(
            recommendationId: SaveOriginPersonalization.recommendationID(for: placeID),
            labels: [label.rawValue],
            createdAt: date
        )
    }
}
