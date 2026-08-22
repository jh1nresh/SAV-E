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
        let grantPathFiles: Set<String> = [
            "SAV-E/Services/SaveEntitlementStore.swift",
        ]
        let changed = try changedPathsVersusDefaultBranch()
        let touched = grantPathFiles.intersection(changed)
        XCTAssertTrue(
            touched.isEmpty,
            "One-Face PR must not touch grant-path files: \(touched.sorted().joined(separator: ", "))"
        )
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func changedPathsVersusDefaultBranch() throws -> Set<String> {
        var lastError = "git diff failed"
        for base in ["origin/main", "main"] {
            let proc = Process()
            proc.currentDirectoryURL = repositoryRoot
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["diff", "--name-only", "\(base)...HEAD"]
            let stdout = Pipe()
            let stderr = Pipe()
            proc.standardOutput = stdout
            proc.standardError = stderr
            try proc.run()
            proc.waitUntilExit()
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if proc.terminationStatus == 0 {
                return Set(
                    out.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
                )
            }
            lastError = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? lastError
        }
        throw NSError(
            domain: "AtlasOneFaceUITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: lastError]
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
