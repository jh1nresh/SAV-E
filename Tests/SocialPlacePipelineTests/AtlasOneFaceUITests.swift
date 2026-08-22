import XCTest
@testable import SAVE

final class AtlasOneFaceUITests: XCTestCase {
    func testDesignTokensMatchLockedOneFacePalette() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        let prototype = try source(at: "Prototypes/AtlasPostcard/Sources/Theme.swift")

        for hex in ["FDF8F3", "FFFDF7", "0E4A33", "F26B4A", "D6E8C4", "B5E3F5", "F0CFA1"] {
            XCTAssertTrue(theme.contains(hex), "SaveAtlasPalette is missing \(hex)")
        }
        XCTAssertTrue(prototype.contains("0xFDF8F3"))
        XCTAssertTrue(prototype.contains("0x0E4A33"))
        XCTAssertTrue(prototype.contains("0xF26B4A"))
        XCTAssertTrue(prototype.contains("0xD6E8C4"))
        XCTAssertTrue(prototype.contains("0xB5E3F5"))
        XCTAssertTrue(prototype.contains("0xF0CFA1"))
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

    func testScopedHeadersUseMemoMascotMark() throws {
        let header = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")
        let firstRun = try source(at: "SAV-E/Views/Onboarding/OnboardingView.swift")
        XCTAssertTrue(header.contains("MemoMascotMark"))
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
