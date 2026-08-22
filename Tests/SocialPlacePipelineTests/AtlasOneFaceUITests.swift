import XCTest
@testable import SAVE

final class AtlasOneFaceUITests: XCTestCase {
    func testDesignTokensMatchLockedOneFacePalette() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        let prototype = try source(at: "Prototypes/AtlasPostcard/Sources/Theme.swift")

        for hex in ["FFF8EE", "FFFDF7", "174E37", "F27D5C", "D9EACB", "CDEDF4", "EFD0A5"] {
            XCTAssertTrue(theme.contains(hex), "SaveAtlasPalette is missing \(hex)")
        }
        XCTAssertTrue(prototype.contains("0xFFF8EE"))
        XCTAssertTrue(prototype.contains("0x174E37"))
        XCTAssertTrue(prototype.contains("0xF27D5C"))
        XCTAssertTrue(prototype.contains("0xD9EACB"))
        XCTAssertTrue(prototype.contains("0xCDEDF4"))
        XCTAssertTrue(prototype.contains("0xEFD0A5"))
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

    func testOneFaceDiffDoesNotTouchGrantPath() throws {
        let entitlement = try source(at: "SAV-E/Services/SaveEntitlementStore.swift")
        XCTAssertFalse(entitlement.contains("serverVerifiedTier ?? locallyObservedTier"))
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
