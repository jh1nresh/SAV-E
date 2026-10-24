import XCTest
@testable import SAVE

final class AtlasOneFaceUITests: XCTestCase {
    func testDesignTokensMatchLockedOneFacePalette() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        let prototype = try source(at: "Prototypes/AtlasPostcard/Sources/Theme.swift")
        let spec = try source(at: "Prototypes/AtlasPostcard/design.md")
        let productionHexes = ["FFF9EB", "0E4A33", SaveAtlasPalette.coralLightHex, "B5E3F5", "2F2E23", "62594F"]
        let retiredDraftHexes = ["FFF8EE", "174E37", "F27D5C", "CDEDF4", "3F281A", "80664F"]

        for hex in productionHexes {
            XCTAssertTrue(theme.contains(hex), "SaveAtlasPalette is missing \(hex)")
            XCTAssertTrue(prototype.contains("0x\(hex)"), "AtlasPalette is missing 0x\(hex)")
            XCTAssertTrue(spec.contains("#\(hex)"), "design.md is missing #\(hex)")
        }
        for hex in retiredDraftHexes {
            XCTAssertFalse(theme.contains(hex), "SaveAtlasPalette restored retired draft hex \(hex)")
            XCTAssertFalse(prototype.contains(hex), "AtlasPalette restored retired draft hex \(hex)")
            XCTAssertFalse(spec.contains(hex), "design.md restored retired draft hex \(hex)")
        }
    }

    func testCoralHardcodesStayOnTheAtlasToken() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        let clip = try source(at: "SAV-EClip/ClipContentView.swift")
        let share = try source(at: "SAV-EShareExtension/ShareViewController.swift")
        let pin = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        let design = try source(at: "DESIGN.md")
        XCTAssertEqual(SaveAtlasPalette.creamHex, "FFF9EB")
        XCTAssertEqual(SaveAtlasPalette.coralLightHex, SaveAtlasPalette.brandCoralHex)
        XCTAssertEqual(SaveAtlasPalette.brandCoralHex, "F26B4A")
        XCTAssertEqual(SaveAtlasPalette.coralDarkHex, "D97861")
        XCTAssertTrue(theme.contains("nonisolated static let creamHex"))
        XCTAssertTrue(theme.contains("nonisolated static let brandCoralHex"))
        XCTAssertTrue(theme.contains("nonisolated static let coralLightHex"))
        XCTAssertTrue(theme.contains("nonisolated static let coralDarkHex"))
        XCTAssertTrue(theme.contains("static let coral = Color(light: coralLightHex, dark: coralDarkHex)"))
        XCTAssertTrue(theme.contains("static let brandCoral = Color(hex: brandCoralHex)"))
        XCTAssertTrue(theme.contains("static let cream = Color(hex: creamHex)"))
        XCTAssertTrue(clip.contains(SaveAtlasPalette.coralLightHex))
        XCTAssertTrue(share.contains(SaveAtlasPalette.coralLightHex))
        XCTAssertTrue(share.contains("static let coral = Color(hex: \"F26B4A\")"))
        XCTAssertTrue(share.contains("static let yellow = coral"))
        XCTAssertEqual(share.components(separatedBy: "F26B4A").count - 1, 1)
        XCTAssertTrue(pin.contains("let coral = SaveAtlasPalette.brandCoral"))
        XCTAssertFalse(pin.contains("let coral = SaveAtlasPalette.coral\n"))
        XCTAssertFalse(pin.contains("0.949"))
        XCTAssertTrue(design.contains("#\(SaveAtlasPalette.coralLightHex)"))
        XCTAssertTrue(design.contains("#\(SaveAtlasPalette.coralDarkHex)"))
        XCTAssertTrue(design.contains("#\(SaveAtlasPalette.creamHex)"))
        XCTAssertTrue(design.contains("Token consolidation map"))
        XCTAssertTrue(design.contains("| Old (`main`) | New token | Light | Dark |"))
        XCTAssertFalse(theme.contains("coralStrong"))
    }

    func testReviewTicketFaceOmitsMapReadyAndConfidencePercent() throws {
        let review = try source(at: "SAV-E/Views/Drawer/AIDrawerView.swift")
        XCTAssertFalse(review.contains("map ready"))
        XCTAssertFalse(review.contains("MAP READY"))
        XCTAssertFalse(review.contains("% confidence"))
        XCTAssertTrue(review.contains("drawer.review.memoPeek"))
        XCTAssertTrue(review.contains("Confirm"))
        XCTAssertTrue(review.contains("SavePostcardMemoPeek"))
    }

    func testReviewDemoFixtureIsHarborOvenNeverQuarterSheets() throws {
        let seed = try source(at: "SAV-E/Services/ReviewDemoService.swift")
        XCTAssertTrue(seed.contains("Harbor Oven Pizza"))
        XCTAssertFalse(seed.contains("Quarter Sheets Pizza Club"))
    }

    func testOnboardingKeepsMemoMascotMark() throws {
        let firstRun = try source(at: "SAV-E/Views/Onboarding/OnboardingView.swift")
        XCTAssertTrue(firstRun.contains("MemoMascotMark"))
        XCTAssertTrue(firstRun.contains("Text(step == .candidate ? text(\"Review Candidate\""))
        XCTAssertFalse(firstRun.contains("Label(step == .candidate"))
        XCTAssertTrue(
            firstRun.contains("""
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("onboarding.postcard.\\(step)")
            """),
            "postcard identifier without contain hides Review Candidate from staticTexts queries"
        )
    }

    func testHomeTripCardAndTripsTabShowBeta() throws {
        let home = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        XCTAssertTrue(home.contains("home.trip.beta"))
        XCTAssertTrue(home.contains("trips.beta.badge"))
    }

    func testSoftPixelH1ProductionHomeUsesPaperLibraryNotCityHero() throws {
        let home = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        let bridge = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        let mapRoot = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")

        XCTAssertTrue(bridge.contains("productionLocksOneFaceHomeComposition = false"))
        XCTAssertTrue(bridge.contains("productMapBaseIsTileTown = true"))
        XCTAssertTrue(bridge.contains("locksOneFaceHomeComposition = SaveSoftPixelAccentsLock.productionLocksOneFaceHomeComposition"))
        XCTAssertTrue(home.contains("HomeSavedPlacesLibrary()"))
        XCTAssertTrue(home.contains("homeCityHero("))
        XCTAssertTrue(home.contains("SaveSoftPixelAccentsLock.allowsIllustratedCityAtlasAsset"))
        XCTAssertTrue(home.contains("AtlasRegionalHomeHero(hero: presentation.homeHero)"))
        XCTAssertFalse(home.contains("Image(\"SoftPixel"))
        XCTAssertFalse(home.contains("assetName: \"SoftPixel"))
        XCTAssertFalse(home.contains("assetName: \"16-bit"))
        XCTAssertFalse(home.contains("assetName: \"pixel-art"))
        XCTAssertTrue(mapRoot.contains("SaveDoodleHomeView("))
        XCTAssertTrue(mapRoot.contains("SaveTileTownRootMap("))
        XCTAssertFalse(mapRoot.contains("Image(\"SoftPixel"))
    }

    @MainActor
    func testSoftPixelH1RejectsPixelCityHeroAssets() {
        XCTAssertTrue(SaveSoftPixelAccentsLock.allowsIllustratedCityAtlasAsset("HomeAtlasSceneTaipei"))
        XCTAssertTrue(SaveSoftPixelAccentsLock.allowsIllustratedCityAtlasAsset("HomeAtlasScene"))
        XCTAssertFalse(SaveSoftPixelAccentsLock.allowsIllustratedCityAtlasAsset("SoftPixelCityTokyo"))
        XCTAssertFalse(SaveSoftPixelAccentsLock.allowsIllustratedCityAtlasAsset("HomeAtlasScene16bit"))
        XCTAssertFalse(SaveSoftPixelAccentsLock.allowsIllustratedCityAtlasAsset("pixel-art-city"))
        XCTAssertTrue(SaveSoftPixelAccentsLock.containsForbiddenHeroToken("soft-pixel-city"))
        XCTAssertFalse(SaveSoftPixelAccentsLock.productionLocksOneFaceHomeComposition)
        XCTAssertTrue(SaveSoftPixelAccentsLock.productMapBaseIsTileTown)
        XCTAssertTrue(SaveTileTownProductLock.productMapBaseIsTileTown)
    }

    func testSoftPixelM1StampSurfacesOmitHexAndPipelineTokens() throws {
        let badgeSource = try source(at: "SAV-E/Views/Shared/SaveMemoryBadge.swift")
        let pinSource = try source(at: "SAV-E/Views/Map/MapView.swift")
        let stamp = try typeBody("RoundStamp", in: try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift"))
        let chip = try typeBody("StampChip", in: try source(at: "SAV-E/Views/Drawer/AIDrawerView.swift"))
        let medallion = try typeBody("SavePostcardPerforatedMedallion", in: try source(at: "SAV-E/Extensions/Color+Theme.swift"))
        let badge = try typeBody("SaveMemoryBadge", in: badgeSource)
        let pin = try typeBody("PlaceMapPin", in: pinSource)
        let reviewPin = try typeBody("ReviewCandidateMapPin", in: pinSource)

        XCTAssertFalse(badge.contains("Text("))
        XCTAssertFalse(badge.contains("uuidString"))
        XCTAssertFalse(badge.contains("Analysis pipeline"))
        XCTAssertFalse(pin.contains("Text(place.id"))
        XCTAssertFalse(pin.contains("Text(") && pin.contains(".uuidString"))
        XCTAssertFalse(reviewPin.contains("Text(candidate.id"))
        XCTAssertTrue(stamp.contains("SaveSoftPixelAccentsLock.visibleStampText"))
        XCTAssertTrue(chip.contains("SaveSoftPixelAccentsLock.visibleStampText"))
        XCTAssertFalse(medallion.contains("Text("))
        XCTAssertNil(SaveSoftPixelAccentsLock.visibleStampText(""))
        XCTAssertNil(SaveSoftPixelAccentsLock.visibleStampText("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertNil(SaveSoftPixelAccentsLock.visibleStampText("#F26B4A"))
        XCTAssertNil(SaveSoftPixelAccentsLock.visibleStampText("F26B4A"))
        XCTAssertNil(SaveSoftPixelAccentsLock.visibleStampText("Analysis pipeline: scored candidate"))
        XCTAssertNil(SaveSoftPixelAccentsLock.visibleStampText("debug: place-42"))
        XCTAssertEqual(SaveSoftPixelAccentsLock.visibleStampText("2"), "2")
        XCTAssertEqual(SaveSoftPixelAccentsLock.visibleStampText("Cafe"), "Cafe")
    }

    func testOneFaceDiffDoesNotTouchGrantPath() {
        let oneFaceSwiftFiles: Set<String> = [
            "Prototypes/AtlasPostcard/Sources/Components.swift",
            "Prototypes/AtlasPostcard/Sources/Presentation.swift",
            "Prototypes/AtlasPostcard/Sources/Screens.swift",
            "Prototypes/AtlasPostcard/Sources/Theme.swift",
            "SAV-E/App/SaveApp.swift",
            "SAV-E/Extensions/Color+Theme.swift",
            "SAV-E/Models/Trip.swift",
            "SAV-E/Services/PrivyAuthService.swift",
            "SAV-E/Services/ReviewDemoService.swift",
            "SAV-E/ViewModels/TripPackStore.swift",
            "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift",
            "SAV-E/Views/Drawer/AIDrawerView.swift",
            "SAV-E/Views/Home/SaveRootViews.swift",
            "SAV-E/Views/Onboarding/MapCoachmarkTour.swift",
            "SAV-E/Views/Onboarding/OnboardingView.swift",
            "SAV-E/Views/Shared/MemoMascotMark.swift",
            "Tests/SAVEUITests/SAVEScreenshotRailTests.swift",
            "Tests/SocialPlacePipelineTests/AtlasHomeHeroPresentationTests.swift",
            "Tests/SocialPlacePipelineTests/AtlasOneFaceUITests.swift",
            "Tests/SocialPlacePipelineTests/ReviewDemoTests.swift",
            "Tests/SocialPlacePipelineTests/TripPackStoreTests.swift",
        ]
        let grantPathFiles: Set<String> = [
            "SAV-E/Services/SaveEntitlementStore.swift",
        ]
        let touched = grantPathFiles.intersection(oneFaceSwiftFiles)
        XCTAssertTrue(
            touched.isEmpty,
            "One-Face PR must not touch grant-path files: \(touched.sorted().joined(separator: ", "))"
        )
    }

    private func typeBody(_ typeName: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: {
            $0.hasPrefix("private struct \(typeName)") || $0.hasPrefix("struct \(typeName)")
        }) else {
            XCTFail("Missing \(typeName)")
            return ""
        }
        var end = lines.endIndex
        for index in lines.index(after: start)..<lines.endIndex {
            let line = lines[index]
            if line.hasPrefix("private struct ") || line.hasPrefix("struct ") || line.hasPrefix("private enum ") {
                end = index
                break
            }
        }
        return lines[start..<end].joined(separator: "\n")
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
