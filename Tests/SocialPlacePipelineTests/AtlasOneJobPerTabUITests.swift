import XCTest
@testable import SAVE

final class AtlasOneJobPerTabUITests: XCTestCase {
    // `AtlasHomeSheetKind` lives in the SAVE target, which builds with
    // MainActor default isolation; this test target is `nonisolated`. Without
    // this annotation the file does not compile once it is actually a member of
    // SAVETests -- which is how it shipped: the file was added to the repo but
    // never added to project.yml's generated target, so it was never built.
    @MainActor
    func testHomeSheetResolverPicksReviewThenSameCityTripThenEmpty() {
        XCTAssertEqual(
            AtlasHomeSheetKind.resolve(reviewCount: 2, tripKind: .currentTrip),
            .review
        )
        XCTAssertEqual(
            AtlasHomeSheetKind.resolve(reviewCount: 0, tripKind: .upcomingTrip),
            .sameCityTrip
        )
        XCTAssertEqual(
            AtlasHomeSheetKind.resolve(reviewCount: 0, tripKind: .planFromStamps),
            .empty
        )
        XCTAssertEqual(
            AtlasHomeSheetKind.resolve(reviewCount: 0, tripKind: .capture),
            .empty
        )
        XCTAssertEqual(
            AtlasHomeSheetKind.resolve(reviewCount: 0, tripKind: nil),
            .empty
        )
    }

    func testLiveHomeUsesOneSheetAndOmitsStamps() throws {
        let screens = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        let home = try typeBody("HomeAtlasScreen", in: screens)
        let oneJob = try typeBody("HomeOneJobSheet", in: screens)
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")

        XCTAssertTrue(home.contains("HomeOneJobSheet()"))
        XCTAssertTrue(home.contains("locksOneFaceHomeComposition"))
        XCTAssertFalse(oneJob.contains("home.recentSaves"))
        XCTAssertFalse(oneJob.contains("HomeRecentStamps"))
        XCTAssertFalse(oneJob.contains("HomeMetric"))
        XCTAssertFalse(oneJob.contains("showsStatColumns: true"))
        XCTAssertFalse(root.contains("home.recentSaves"))
        XCTAssertFalse(root.contains("Recent Map Stamps"))
        XCTAssertFalse(root.contains("CONTINUE TODAY"))
    }

    func testReviewFirstViewportInventoryKeepsTicketNotForm() throws {
        let review = try source(at: "SAV-E/Views/Drawer/AIDrawerView.swift")
        let card = try typeBody("ReviewCandidateDetailCard", in: review)
        let header = try XCTUnwrap(
            review.components(separatedBy: "private func reviewPostcardHeader").dropFirst().first
        )
        let firstMark = try XCTUnwrap(card.range(of: "drawer.review.firstViewport"))
        let belowMark = try XCTUnwrap(card.range(of: "drawer.review.belowFold"))
        XCTAssertTrue(firstMark.lowerBound < belowMark.lowerBound)

        let first = String(card[..<firstMark.lowerBound])
        let below = String(card[firstMark.upperBound..<belowMark.lowerBound])

        XCTAssertTrue(header.contains("drawer.review.memoPeek"))
        XCTAssertTrue(header.contains("drawer.review.seal"))
        XCTAssertTrue(header.contains("drawer.review.title"))
        XCTAssertTrue(header.contains("drawer.review.sourceLine"))
        XCTAssertTrue(first.contains("drawer.review.primaryAction"))
        XCTAssertTrue(first.contains("primaryActionTitle"))
        XCTAssertFalse(first.contains("ReviewCandidateNextStepPanel"))
        XCTAssertFalse(first.contains("Place name"))
        XCTAssertFalse(first.contains("More review actions"))
        XCTAssertFalse(first.contains("drawer.review.heroMap"))
        XCTAssertTrue(below.contains("ReviewCandidateNextStepPanel"))
        XCTAssertTrue(below.contains("Place name"))
        XCTAssertTrue(below.contains("More review actions"))
        XCTAssertTrue(below.contains("onOpenOnMap"))
        XCTAssertFalse(review.contains("MAP READY"))
        XCTAssertFalse(review.contains("map ready"))
        XCTAssertFalse(review.contains("% confidence"))
        XCTAssertFalse(review.contains("\"84%\""))
    }

    func testSavesFirstViewportCapsTicketsAndKeepsCaptureCoral() throws {
        let saves = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(saves.contains("firstViewportTicketLimit = 3"))
        XCTAssertTrue(saves.contains("SaveAtlasPalette.coral.opacity(0.92)"))
        XCTAssertTrue(saves.contains("saves.pocket.reviewFooter"))
        XCTAssertTrue(saves.contains("saves.pocket.mapStampFooter"))
    }

    func testTripsKeepsOneSecondaryTicket() throws {
        let trips = try typeBody("TripsAtlasScreen", in: try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift"))
        XCTAssertTrue(trips.contains("tripRecommendations.first"))
        XCTAssertTrue(trips.contains("tripSummaries.dropFirst().first"))
        XCTAssertFalse(trips.contains("prefix(2)"))
        XCTAssertTrue(trips.contains("trips.beta.badge"))
    }

    func testMapRestStateHasNoDefaultPlaceCard() throws {
        let map = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(map.contains("if let place = mapViewModel.selectedPlace"))
        XCTAssertTrue(map.contains("} else if !hidesCommandShelf"))
        XCTAssertTrue(map.contains("SaveAtlasMapCommandShelf"))
        XCTAssertTrue(root.contains("--uitest-map-place-selected"))
    }

    func testPassportPutsLanguageAndProBehindDisclosure() throws {
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let disclosure = try identifierBody("profile.controlsDisclosure", in: passport)
        XCTAssertTrue(passport.contains("profile.stampLedger"))
        XCTAssertTrue(disclosure.contains("profile.language"))
        XCTAssertTrue(disclosure.contains("profile.pro"))
        XCTAssertTrue(passport.range(of: "profile.stampLedger")!.lowerBound
            < passport.range(of: "profile.controlsDisclosure")!.lowerBound)
    }

    func testOneJobPerTabDoesNotTouchGrantPath() throws {
        let grantPathFiles: Set<String> = [
            "SAV-E/Services/SaveEntitlementStore.swift",
            "SAV-E/Services/SaveStoreKitService.swift",
        ]
        let oneJobSwiftFiles: Set<String> = [
            "Prototypes/AtlasPostcard/Sources/Presentation.swift",
            "Prototypes/AtlasPostcard/Sources/Screens.swift",
            "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift",
            "SAV-E/Views/Drawer/AIDrawerView.swift",
            "SAV-E/Views/Home/SaveRootViews.swift",
            "SAV-E/Views/Profile/ProfileView.swift",
            "Tests/SocialPlacePipelineTests/AtlasOneJobPerTabUITests.swift",
        ]
        XCTAssertTrue(grantPathFiles.isDisjoint(with: oneJobSwiftFiles))

        let store = try source(at: "SAV-E/Services/SaveEntitlementStore.swift")
        // The literal here must match the shipped grant path. The original
        // assertion looked for "serverVerifiedTier ?? locallyObservedTier",
        // a string that has never existed in this file (the call is qualified
        // with `storeKit.`), so it could only ever have failed. It never did,
        // because the file was not a member of any build target.
        XCTAssertTrue(
            store.contains("storeKit.serverVerifiedTier ?? storeKit.locallyObservedTier")
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
            if line.hasPrefix("private struct ") || line.hasPrefix("struct ") {
                end = index
                break
            }
        }
        return lines[start..<end].joined(separator: "\n")
    }

    private func identifierBody(_ identifier: String, in source: String) throws -> String {
        let needle = "accessibilityIdentifier(\"\(identifier)\")"
        guard let end = source.range(of: needle) else {
            XCTFail("Missing \(identifier)")
            return ""
        }
        let prefix = source[..<end.lowerBound]
        let start = prefix.range(of: "VStack", options: .backwards)?.lowerBound
            ?? prefix.range(of: "DisclosureGroup", options: .backwards)?.lowerBound
            ?? prefix.index(end.lowerBound, offsetBy: -400, limitedBy: prefix.startIndex)
            ?? prefix.startIndex
        return String(source[start..<end.upperBound])
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
