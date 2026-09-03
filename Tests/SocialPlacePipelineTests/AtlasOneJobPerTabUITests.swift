import XCTest
@testable import SAVE

final class AtlasOneJobPerTabUITests: XCTestCase {
    func testLiveHomeLeadsWithSavedPlacesAndKeepsSecondaryManagement() throws {
        let screens = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        let home = try typeBody("HomeAtlasScreen", in: screens)
        let library = try typeBody("HomeSavedPlacesLibrary", in: screens)

        XCTAssertTrue(home.contains("HomeSavedPlacesLibrary()"))
        XCTAssertTrue(home.contains("locksOneFaceHomeComposition"))
        XCTAssertTrue(library.contains("presentation.savedPlaces"))
        XCTAssertTrue(library.contains("home.savedPlaces"))
        XCTAssertTrue(library.contains("home.saves"))
        XCTAssertTrue(library.contains("home.review"))
        XCTAssertTrue(library.contains("savedPlaceGroups"))
        XCTAssertTrue(library.contains("regionTitle"))
        XCTAssertTrue(library.contains("group.places"))
        XCTAssertTrue(library.contains("HomeFeaturedPlaceHero"))
        XCTAssertTrue(library.contains("ScrollView(.horizontal)"))
        XCTAssertFalse(library.contains("shelfGroups"))
        XCTAssertFalse(library.contains("ForEach(Array(presentation.savedPlaces.enumerated())"))
        XCTAssertTrue(
            library.contains("alignment: .top"),
            "A tall saved-place list must top-align or it covers BrandHeader."
        )
        XCTAssertTrue(library.contains(".clipped()"))
        XCTAssertFalse(home.contains("home.capture"))
        XCTAssertFalse(home.contains("Paste a link"))
    }

    func testHomeSavedPlaceUsesStoredPhotoWithFallback() throws {
        let screens = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        let row = try typeBody("HomeSavedPlaceRow", in: screens)
        let hero = try typeBody("HomeFeaturedPlaceHero", in: screens)
        let thumbnail = try typeBody("HomeSavedPlaceThumbnail", in: screens)
        let bridge = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")

        XCTAssertTrue(row.contains("HomeSavedPlaceThumbnail("))
        XCTAssertTrue(row.contains("latitude: place.latitude"))
        XCTAssertTrue(row.contains("frame(width: width, height: 112)"))
        XCTAssertTrue(row.contains("RoundStamp(text: \"\", style: .mapStamp)"))
        XCTAssertTrue(hero.contains("HomeSavedPlaceThumbnail("))
        XCTAssertTrue(hero.contains("longitude: place.longitude"))
        XCTAssertTrue(hero.contains("home.photoHero"))
        XCTAssertTrue(thumbnail.contains("CachedAsyncImage"))
        XCTAssertTrue(thumbnail.contains("HomeLocationSnapshot"))
        XCTAssertTrue(thumbnail.contains("scaledToFill"))
        XCTAssertTrue(thumbnail.contains("fallback"))
        XCTAssertTrue(screens.contains("MKLookAroundSceneRequest"))
        XCTAssertTrue(screens.contains("MKMapSnapshotter"))
        XCTAssertTrue(screens.contains("mapOptions.mapType = .hybrid"))
        XCTAssertTrue(
            bridge.contains("businessPhotoURLStrings.first.flatMap(URL.init(string:))")
        )
        XCTAssertTrue(bridge.contains("latitude: place.latitude"))
        XCTAssertTrue(bridge.contains("longitude: place.longitude"))

        let home = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(home.contains("await mapViewModel.enrichMissingHomePlacePhotos()"))
        XCTAssertTrue(home.contains("ReviewDemo.isOfflineUITestMode"))
    }

    @MainActor
    func testSavedPlacesGroupByRegionAndPreserveRecencyOrder() {
        let places = [
            place(id: "taipei-new", region: "臺北市"),
            place(id: "la-new", region: "Los Angeles"),
            place(id: "taipei-old", region: "臺北市"),
            place(id: "la-old", region: "los angeles"),
            place(id: "unknown", region: "  "),
        ]

        let groups = AtlasPlacePresentation.groupedByRegion(places)

        XCTAssertEqual(groups.map(\.region), ["臺北市", "Los Angeles", nil])
        XCTAssertEqual(groups[0].places.map(\.id), ["taipei-new", "taipei-old"])
        XCTAssertEqual(groups[1].places.map(\.id), ["la-new", "la-old"])
        XCTAssertEqual(groups[2].places.map(\.id), ["unknown"])
    }

    func testVisualParityPrefersTheLiveFiveTabHome() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        let workflow = try source(at: ".github/workflows/ci.yml")

        XCTAssertTrue(script.contains("five-tab-home*)"))
        XCTAssertTrue(script.contains("priority=1"))
        XCTAssertTrue(
            workflow.contains(
                "SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding"
            )
        )
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
        let markers = try source(at: "SAV-E/Views/Map/MapView.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(map.contains("if let place = mapViewModel.selectedPlace"))
        XCTAssertTrue(map.contains("} else if !hidesCommandShelf"))
        XCTAssertTrue(map.contains("SaveAtlasMapCommandShelf"))
        XCTAssertTrue(map.contains("Search places"))
        XCTAssertTrue(map.contains("slider.horizontal.3"))
        XCTAssertTrue(map.contains("saved Map Stamps"))
        XCTAssertTrue(markers.contains("if state == .saved"))
        XCTAssertTrue(markers.contains("frame(width: isSelected ? 36 : 32"))
        XCTAssertTrue(markers.contains(".frame(width: 44, height: 44)"))
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

    func testPassportActionsSharePlacesAndKeepBulkImportInCapture() throws {
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")

        XCTAssertTrue(passport.contains("SavePlaceShareButton(content: .place(place))"))
        XCTAssertTrue(passport.contains("profile.share.\\(place.id)"))
        XCTAssertTrue(passport.contains(".contentShape(Rectangle())"))
        XCTAssertFalse(passport.contains("profile.importGoogleTakeout"))

        XCTAssertTrue(content.contains("capture.importGoogleTakeout"))
        XCTAssertTrue(content.contains("GoogleTakeoutImportView("))
        XCTAssertTrue(content.contains("onSaveGoogleTakeoutImport: { drafts in"))
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

    @MainActor
    private func place(id: String, region: String?) -> AtlasPlacePresentation {
        AtlasPlacePresentation(
            id: id,
            name: id,
            area: region ?? "",
            region: region,
            photoURL: nil,
            relativeDay: "Today",
            note: ""
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
