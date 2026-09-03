import XCTest
@testable import SAVE

final class AtlasOneFaceUITests: XCTestCase {
    func testDesignTokensMatchLockedOneFacePalette() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        let prototype = try source(at: "Prototypes/AtlasPostcard/Sources/Theme.swift")
        let spec = try source(at: "Prototypes/AtlasPostcard/design.md")
        let productionHexes = ["FDF8F3", "0E4A33", "F26B4A", "B5E3F5", "2E2117", "62594F"]
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
    }

    func testHomeTripCardAndTripsTabShowBeta() throws {
        let home = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        XCTAssertTrue(home.contains("home.trip.beta"))
        XCTAssertTrue(home.contains("trips.beta.badge"))
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
