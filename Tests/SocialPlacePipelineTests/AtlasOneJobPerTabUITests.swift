import CoreLocation
import SwiftUI
import XCTest
@testable import SAVE

final class AtlasOneJobPerTabUITests: XCTestCase {
    func testLiveHomeLeadsWithSavedPlacesAndKeepsSecondaryManagement() throws {
        let screens = try source(at: "Prototypes/AtlasPostcard/Sources/Screens.swift")
        let home = try typeBody("HomeAtlasScreen", in: screens)
        let library = try typeBody("HomeSavedPlacesLibrary", in: screens)
        let reviewTicket = try typeBody("ReviewTicket", in: screens)

        XCTAssertTrue(home.contains("HomeSavedPlacesLibrary()"))
        XCTAssertTrue(home.contains("locksOneFaceHomeComposition"))
        XCTAssertTrue(library.contains("presentation.savedPlaces"))
        XCTAssertTrue(library.contains("home.savedPlaces"))
        XCTAssertTrue(home.contains("home.more"))
        XCTAssertTrue(home.contains("home.trips"))
        XCTAssertTrue(home.contains("home.saves"))
        XCTAssertTrue(home.contains("presentation.onOpenTrips"))
        XCTAssertTrue(home.contains("presentation.onOpenSaves"))
        XCTAssertTrue(home.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(library.contains("home.reviewQueue"))
        XCTAssertTrue(library.contains("home.reviewCandidate"))
        XCTAssertTrue(library.contains("presentation.reviewItems.first"))
        XCTAssertTrue(library.contains("Waiting for review"))
        XCTAssertTrue(reviewTicket.contains("item.kind == .sourceOnly"))
        XCTAssertTrue(reviewTicket.contains("Text(item.eyebrow)"))
        XCTAssertTrue(reviewTicket.contains("Text(item.actionTitle)"))
        XCTAssertFalse(library.contains("Image(systemName: \"sparkles\")"))
        XCTAssertFalse(library.contains("Image(systemName: \"slider.horizontal.3\")"))
        XCTAssertTrue(library.contains("savedPlaceGroups"))
        XCTAssertTrue(library.contains("cityRowsExcludingFeatured"))
        XCTAssertTrue(library.contains("featuredID: featuredPlace?.id"))
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
        XCTAssertTrue(row.contains("placeID: \"row.\\(place.id)\""))
        XCTAssertTrue(row.contains("photoURL: place.photoURL"))
        XCTAssertTrue(row.contains("latitude: place.latitude"))
        XCTAssertTrue(row.contains("frame(width: width, height: 112)"))
        XCTAssertTrue(row.contains("RoundStamp(text: \"\", style: .mapStamp)"))
        XCTAssertTrue(hero.contains("HomeSavedPlaceThumbnail("))
        XCTAssertTrue(hero.contains("placeID: \"hero.\\(place.id)\""))
        XCTAssertTrue(hero.contains("photoURL: place.photoURL"))
        XCTAssertTrue(hero.contains("longitude: place.longitude"))
        XCTAssertTrue(hero.contains("home.photoHero"))
        XCTAssertFalse(hero.contains("home.hero.changeCover"))
        XCTAssertFalse(hero.contains("photo.stack"))
        XCTAssertTrue(screens.contains("presentation.savedPlaces.first"))
        XCTAssertFalse(screens.contains("placesWithPhotos"))
        XCTAssertFalse(screens.contains("cycleFeaturedPlace"))
        XCTAssertTrue(thumbnail.contains("CachedAsyncImage"))
        XCTAssertTrue(thumbnail.contains("HomeLocationSnapshot"))
        XCTAssertTrue(thumbnail.contains("if photoURL == nil"))
        XCTAssertTrue(thumbnail.contains("placeID: placeID"))
        XCTAssertTrue(thumbnail.contains(".id(placeID)"))
        XCTAssertTrue(thumbnail.contains("scaledToFill"))
        XCTAssertTrue(thumbnail.contains("fallback"))
        let snapshot = try typeBody("HomeLocationSnapshot", in: screens)
        XCTAssertTrue(snapshot.contains("placeID"))
        XCTAssertTrue(snapshot.contains("snapshotImage = nil"))
        XCTAssertTrue(snapshot.contains("loadedPlaceID = nil"))
        XCTAssertTrue(snapshot.contains("HomeLocationSnapshotDisplay.shouldShow"))
        XCTAssertTrue(snapshot.contains("MKLookAroundSceneRequest"))
        XCTAssertTrue(snapshot.contains("MKMapSnapshotter"))
        XCTAssertTrue(screens.contains("mapOptions.mapType = .hybrid"))
        XCTAssertTrue(bridge.contains("HomePlaceCardArt.photoURL(for: place)"))

        let home = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(home.contains("await mapViewModel.enrichMissingHomePlacePhotos()"))
        XCTAssertTrue(home.contains("ReviewDemo.isOfflineUITestMode"))

        let imageLoader = try source(at: "SAV-E/Views/Components/CachedAsyncImage.swift")
        XCTAssertTrue(imageLoader.contains("CachedAsyncImageDisplay.phase"))
        XCTAssertTrue(imageLoader.contains("requestedURL == loadedURL"))
    }

    @MainActor
    func testHomePlaceCardArtBindsEachPlaceToItsOwnPhotoOrPlaceholder() throws {
        var noodles = savedPlace(name: "竣師父牛肉麵-大安店")
        noodles.businessPhotoUrls = ["https://example.com/jun-shifu.jpg"]
        noodles.sourceImageUrl = "https://example.com/unrelated-ceiling.jpg"

        var yakiniku = savedPlace(name: "利庭園燒肉")
        yakiniku.businessPhotoUrls = ["https://example.com/li-ting-yuan.jpg"]

        var missingPhoto = savedPlace(name: "No Photo Cafe")
        var sourceOnly = savedPlace(name: "Source Only Noodles")
        sourceOnly.sourceImageUrl = "https://example.com/jun-shifu-source.jpg"

        XCTAssertEqual(
            HomePlaceCardArt.photoURL(for: noodles)?.absoluteString,
            "https://example.com/jun-shifu.jpg"
        )
        XCTAssertEqual(
            HomePlaceCardArt.photoURL(for: yakiniku)?.absoluteString,
            "https://example.com/li-ting-yuan.jpg"
        )
        XCTAssertEqual(
            HomePlaceCardArt.photoURL(for: sourceOnly)?.absoluteString,
            "https://example.com/jun-shifu-source.jpg"
        )
        XCTAssertNil(HomePlaceCardArt.photoURL(for: missingPhoto))
        XCTAssertNotEqual(
            HomePlaceCardArt.photoURL(for: noodles),
            HomePlaceCardArt.photoURL(for: yakiniku)
        )
    }

    func testHomeLocationSnapshotDoesNotKeepAnotherPlaceUnderlay() {
        XCTAssertTrue(
            HomeLocationSnapshotDisplay.shouldShow(
                loadedPlaceID: "place-a",
                placeID: "place-a"
            )
        )
        XCTAssertFalse(
            HomeLocationSnapshotDisplay.shouldShow(
                loadedPlaceID: "place-a",
                placeID: "place-b"
            )
        )
        XCTAssertFalse(
            HomeLocationSnapshotDisplay.shouldShow(
                loadedPlaceID: nil,
                placeID: "place-b"
            )
        )
    }

    func testPlaceBusinessMatchPolicyRejectsLooseSameNameAndNamelessNeighbors() {
        let daan = CLLocationCoordinate2D(latitude: 25.0410, longitude: 121.5434)
        let nearbySame = GooglePlaceMatch(
            id: "same-block",
            name: "竣師父牛肉麵",
            address: "Da'an",
            latitude: 25.0414,
            longitude: 121.5434
        )
        let distantBranch = GooglePlaceMatch(
            id: "other-branch",
            name: "竣師父牛肉麵",
            address: "Zhongxiao",
            latitude: 25.0545,
            longitude: 121.5434
        )
        let namelessNeighbor = GooglePlaceMatch(
            id: "neighbor",
            name: "Ceiling Grid Cafe",
            address: "Next door",
            latitude: 25.04115,
            longitude: 121.5434
        )

        XCTAssertNotNil(
            PlaceBusinessMatchPolicy.score(
                name: "竣師父牛肉麵-大安店",
                coordinate: daan,
                match: nearbySame
            )
        )
        XCTAssertNil(
            PlaceBusinessMatchPolicy.score(
                name: "竣師父牛肉麵-大安店",
                coordinate: daan,
                match: distantBranch
            )
        )
        XCTAssertNil(
            PlaceBusinessMatchPolicy.score(
                name: "竣師父牛肉麵-大安店",
                coordinate: daan,
                match: namelessNeighbor
            )
        )
    }

    func testCachedAsyncImageDoesNotPaintAnotherURLWhileReused() {
        let first = URL(string: "https://example.com/place-a.jpg")
        let second = URL(string: "https://example.com/place-b.jpg")
        let stale = AsyncImagePhase.success(Image(systemName: "photo"))

        switch CachedAsyncImageDisplay.phase(
            requestedURL: first,
            loadedURL: first,
            loadedPhase: stale
        ) {
        case .success:
            break
        default:
            XCTFail("The loaded URL may keep its own image")
        }

        switch CachedAsyncImageDisplay.phase(
            requestedURL: second,
            loadedURL: first,
            loadedPhase: stale
        ) {
        case .empty:
            break
        default:
            XCTFail("A reused view must not keep another place's photo")
        }
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

    @MainActor
    func testCityRowsOmitTheFeaturedHeroSoThumbnailsDoNotDedupeAcrossSlots() {
        let featured = place(id: "jun-shifu", region: "台北市")
        let seoul = place(id: "li-ting-yuan", region: "Seoul")
        let taipeiOlder = place(id: "other-taipei", region: "台北市")

        let groups = AtlasPlacePresentation.cityRowsExcludingFeatured(
            [featured, seoul, taipeiOlder],
            featuredID: featured.id
        )

        XCTAssertEqual(groups.map(\.region), ["Seoul", "台北市"])
        XCTAssertFalse(groups.contains { $0.places.contains(where: { $0.id == featured.id }) })
        XCTAssertEqual(groups[0].places.map(\.id), ["li-ting-yuan"])
        XCTAssertEqual(groups[1].places.map(\.id), ["other-taipei"])
        XCTAssertTrue(
            AtlasPlacePresentation.cityRowsExcludingFeatured(
                [featured],
                featuredID: featured.id
            ).isEmpty
        )
    }

    func testVisualParityPrefersTheLiveFiveTabHome() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        let workflow = try source(at: ".github/workflows/ci.yml")
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")

        XCTAssertTrue(script.contains("five-tab-home*)"))
        XCTAssertTrue(script.contains("priority=1"))
        XCTAssertTrue(
            workflow.contains(
                "SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding"
            )
        )
        XCTAssertTrue(rail.contains("waitForHomeCoverImagery(app)"))
        XCTAssertTrue(rail.contains("home.photoHero"))
        XCTAssertTrue(rail.contains("pngRepresentation.count"))
        XCTAssertTrue(
            rail.contains("1_200_000"),
            "Parity attach must wait for painted Home covers, not the pin fallback."
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
        XCTAssertTrue(map.contains("mic.fill"))
        XCTAssertTrue(map.contains(".ultraThinMaterial, in: Capsule()"))
        XCTAssertTrue(map.contains("saved Map Stamps"))
        XCTAssertFalse(
            map.contains("slider.horizontal.3"),
            "Collapsed Map search is a floating pill, not a filter rail."
        )
        XCTAssertTrue(markers.contains("if state == .saved"))
        XCTAssertTrue(markers.contains("frame(width: isSelected ? 36 : 32"))
        XCTAssertTrue(markers.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(root.contains("--uitest-map-place-selected"))
    }

    func testMapSearchIsBottomFloatingChromeWithParkedDetents() throws {
        let shelf = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        let panel = try source(at: "SAV-E/Views/Map/SaveMapDrawerPanel.swift")
        let map = try source(at: "SAV-E/Views/Map/MapView.swift")
        let root = try source(at: "SAV-E/App/ContentView.swift")
        let tabBar = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")

        XCTAssertTrue(root.contains("SaveMapDrawerPanel("))
        XCTAssertTrue(root.contains("hidesCommandShelf: true"))
        XCTAssertTrue(panel.contains("case collapsed"))
        XCTAssertTrue(panel.contains("case medium"))
        XCTAssertTrue(panel.contains("case large"))
        XCTAssertTrue(panel.contains("map.drawerPanel.collapsed"))
        XCTAssertTrue(panel.contains("SaveAtlasMapCommandShelf("))
        XCTAssertTrue(panel.contains("alignment: .bottom"))
        XCTAssertTrue(shelf.contains("map.command.search"))
        XCTAssertTrue(shelf.contains(".ultraThinMaterial, in: Capsule()"))
        XCTAssertFalse(shelf.contains(".glassEffect("))
        XCTAssertFalse(map.contains("TextField"))
        XCTAssertFalse(map.contains(".searchable"))
        XCTAssertFalse(map.contains("map.command.search"))
        XCTAssertTrue(
            tabBar.contains(".glassEffect("),
            "Tab-bar glass stays parked on AtlasTabBar; this ticket must not move it."
        )
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

    func testPassportTodayOnSavvySitsBetweenStampLedgerAndControlPocket() throws {
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")

        XCTAssertTrue(passport.contains("if !todayMissions.isEmpty"))
        XCTAssertTrue(passport.contains("PassportTodayOnSavvyStrip"))
        XCTAssertTrue(passport.contains("TODAY ON SAVVY"))
        XCTAssertTrue(passport.contains("今日 Savvy"))
        XCTAssertTrue(passport.contains("Up to three real next steps"))
        XCTAssertTrue(passport.contains("最多三件真正要做的事"))
        XCTAssertTrue(passport.contains("Uses existing review queue count"))
        XCTAssertTrue(passport.contains("Fills Origin for peers"))
        XCTAssertTrue(passport.contains("Feeds Origin + connections"))
        XCTAssertTrue(passport.contains("profile.today.confirmWaitingClue"))
        XCTAssertTrue(passport.contains("profile.today.shareRecommendation"))
        XCTAssertTrue(passport.contains("profile.today.inviteFriend"))
        XCTAssertTrue(passport.contains("profile.connections"))
        XCTAssertTrue(passport.contains("opensConnections = true"))
        XCTAssertTrue(passport.contains("onReviewAll()"))
        XCTAssertTrue(content.contains("onReviewAll:"))
        XCTAssertTrue(content.contains("pathByOpening"))
        XCTAssertTrue(content.contains(".saves"))

        XCTAssertTrue(passport.range(of: "profile.stampLedger")!.lowerBound
            < passport.range(of: "PassportTodayOnSavvyStrip")!.lowerBound)
        XCTAssertTrue(passport.range(of: "PassportTodayOnSavvyStrip")!.lowerBound
            < passport.range(of: "profile.controlPocket")!.lowerBound)
        XCTAssertTrue(passport.range(of: "profile.controlPocket")!.lowerBound
            < passport.range(of: "PassportCountingRulesPanel")!.lowerBound)
        XCTAssertTrue(passport.range(of: "PassportCountingRulesPanel")!.lowerBound
            < passport.range(of: "PassportVisibilityPanel")!.lowerBound)

        XCTAssertFalse(passport.contains("\"XP\""))
        XCTAssertFalse(passport.contains("gems"))
        XCTAssertFalse(passport.contains("streak calendar"))
        XCTAssertFalse(passport.contains("quest board"))
        XCTAssertFalse(passport.contains("SaveStoreKitService"))
        XCTAssertFalse(passport.contains("SaveEntitlementStore"))
        XCTAssertFalse(passport.contains("serverVerifiedTier"))
    }

    func testPrimaryHeadersUseTheCurrentSavvyLogo() throws {
        let components = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")
        let brandHeader = try typeBody("BrandHeader", in: components)
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        let rootHeader = try typeBody("SaveAtlasBrandHeader", in: root)
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let passportTopBar = try typeBody("PassportTopBar", in: profile)

        XCTAssertTrue(brandHeader.contains("Image(\"SavvyLogo\")"))
        XCTAssertFalse(brandHeader.contains("MemoMascotMark"))
        XCTAssertTrue(rootHeader.contains("Image(\"SavvyLogo\")"))
        XCTAssertFalse(rootHeader.contains("MemoMascotMark"))
        XCTAssertTrue(passportTopBar.contains("Image(\"SavvyLogo\")"))
        XCTAssertTrue(passportTopBar.contains("profile.brandLogo"))
    }

    func testOriginCommunityCardCanReshareWithoutPublishingPrivateClues() throws {
        let origin = try source(at: "SAV-E/Views/Origin/SaveOriginView.swift")

        XCTAssertTrue(origin.contains("SavePlaceShareButton(content: .communityRecommendation(place))"))
        XCTAssertTrue(origin.contains("origin.reshare.\\(place.id.uuidString)"))
        XCTAssertTrue(origin.contains("Private clues never publish automatically."))
        XCTAssertTrue(origin.contains("Confirmed Map Stamps people explicitly choose to Share recommendation"))
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

    private func savedPlace(name: String) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Taipei",
            latitude: 25.033,
            longitude: 121.5654,
            googlePlaceId: nil,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
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
