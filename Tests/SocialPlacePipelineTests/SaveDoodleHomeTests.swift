import CoreLocation
import XCTest
@testable import SAVE

@MainActor
final class SaveDoodleHomeTests: XCTestCase {
    func testEatLensKeepsFoodCafeBarAndDropsGo() {
        let now = Date()
        let food = place("Duck", "Beijing, China", .food, latitude: 39.88, longitude: 116.41, createdAt: now.addingTimeInterval(-2))
        let cafe = place("Grey", "Beijing, China", .cafe, latitude: 39.88, longitude: 116.40, createdAt: now.addingTimeInterval(-1))
        let park = place("Tiantan", "Beijing, China", .attraction, latitude: 39.88, longitude: 116.41, createdAt: now)
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [food, cafe, park],
            lens: .eat,
            selection: .city("beijing"),
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(visible.map(\.name), ["Grey", "Duck"])
        XCTAssertEqual(SaveDoodleHomeCatalog.lens(for: .food), .eat)
        XCTAssertEqual(SaveDoodleHomeCatalog.lens(for: .attraction), .go)
    }

    func testGoLensKeepsAttractionStayShopping() {
        let now = Date()
        let park = place("Park", "Tokyo, Japan", .attraction, createdAt: now.addingTimeInterval(-3))
        let hotel = place("Hotel", "Tokyo, Japan", .stay, createdAt: now.addingTimeInterval(-2))
        let shop = place("Shop", "Tokyo, Japan", .shopping, createdAt: now.addingTimeInterval(-1))
        let ramen = place("Ramen", "Tokyo, Japan", .food, createdAt: now)
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [park, hotel, shop, ramen],
            lens: .go,
            selection: .city("tokyo"),
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(visible.map(\.name), ["Shop", "Hotel", "Park"])
    }

    func testCityGroupsUseMetroAliases() {
        let ichiran = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let siam = place(
            "The Siam Hotel",
            "3/2 Thanon Khao, Vachiraphayaban, Dusit, Bangkok 10300",
            .stay
        )
        let cafe = place("Fujin", "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei", .cafe)
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [ichiran, siam, cafe])
        XCTAssertEqual(Set(groups.map(\.id)), ["tokyo", "bangkok", "taipei"])
        XCTAssertEqual(SaveHomeSearch.metroName(in: siam.address, traditionalChinese: false), "Bangkok")
        XCTAssertEqual(SaveHomeSearch.metroName(in: ichiran.address, traditionalChinese: true), "東京")
    }

    func testNearYouKeepsOnlyWalkingDistance() {
        let here = CLLocation(latitude: 39.882, longitude: 116.407)
        let near = place("Duck", "Beijing, China", .food, latitude: 39.883, longitude: 116.408)
        let far = place("Noodles", "Beijing, China", .food, latitude: 40.01, longitude: 116.50)
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [near, far],
            lens: .eat,
            selection: .nearYou,
            location: here,
            locationDenied: false
        )
        XCTAssertEqual(visible.map(\.name), ["Duck"])
        XCTAssertTrue(
            SaveDoodleHomeCatalog.isNearbyEmpty(
                places: [far],
                lens: .eat,
                selection: .nearYou,
                location: here,
                locationDenied: false
            )
        )
    }

    func testLocationDeniedFallsBackToNewestSaveCity() {
        let older = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food,
            createdAt: Date().addingTimeInterval(-100)
        )
        let newer = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe,
            createdAt: Date()
        )
        let resolved = SaveDoodleHomeCatalog.resolvedSelection(
            .nearYou,
            places: [older, newer],
            locationDenied: true
        )
        XCTAssertEqual(resolved, .city("taipei"))
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [older, newer],
            lens: .eat,
            selection: .nearYou,
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(visible.map(\.name), ["Fujin"])
    }

    func testDistanceTextAndCollectedProgress() {
        XCTAssertEqual(SaveDoodleHomeCatalog.distanceText(450), "450m")
        XCTAssertEqual(SaveDoodleHomeCatalog.distanceText(1100), "1.1km")
        let visited = place("Duck", "Beijing, China", .food, status: .visited)
        let saved = place("Cafe", "Beijing, China", .cafe)
        let progress = SaveDoodleHomeCatalog.collectedProgress(in: [visited, saved])
        XCTAssertEqual(progress.visited, 1)
        XCTAssertEqual(progress.saved, 2)
        XCTAssertEqual(progress.goal, 12)
        XCTAssertEqual(SaveDoodleHomeCatalog.collectedStamps(in: [visited, saved]).map(\.name), ["Duck"])
    }

    func testSessionDefaultsToEatAndNearYou() {
        let suite = "save.doodle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let session = SaveDoodleSession(defaults: defaults)
        XCTAssertEqual(session.lens, .eat)
        XCTAssertEqual(session.city, .nearYou)
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)
        session.lens = .go
        session.city = .city("tokyo")
        session.mapFollowsHomeFilter = true
        let restored = SaveDoodleSession(defaults: defaults)
        XCTAssertEqual(restored.lens, .go)
        XCTAssertEqual(restored.city, .city("tokyo"))
        XCTAssertTrue(restored.mapFollowsHomeFilter)
        XCTAssertFalse(restored.pendingMiniMapHandoff)
    }

    func testProductionHomeIsDoodleNotTileTown() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("SaveDoodleHomeView("))
        XCTAssertTrue(root.contains("onOpenMap: onOpenMap"))
        XCTAssertFalse(root.contains("SaveTileTownHomeView()"))
        XCTAssertTrue(home.contains("home.miniMap"))
        XCTAssertTrue(home.contains("home.citySwitcher"))
        XCTAssertTrue(home.contains("fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(home.contains("home.passport"))
        XCTAssertFalse(home.contains("accessibilityIdentifier(\"root.passport\")"))
        XCTAssertTrue(home.contains("lens.accessibilityIdentifier"))
        XCTAssertTrue(home.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(home.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(home.contains(".accessibilityIdentifier(\"home.savedPlaces\")"))
        let catalog = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalog.contains("home.\\(rawValue)"))
        XCTAssertTrue(catalog.contains("case eat"))
        XCTAssertTrue(catalog.contains("case go"))
        XCTAssertTrue(catalog.contains("var accessibilityIdentifier: String { \"home.\\(rawValue)\" }"))
        XCTAssertTrue(home.contains("home.collected"))
        XCTAssertTrue(home.contains("home.empty.capture"))
        XCTAssertTrue(home.contains("home.review"))
        XCTAssertTrue(home.contains("home.saves"))
        XCTAssertTrue(home.contains("See all saves"))
        XCTAssertTrue(home.contains("看全部收藏"))
        XCTAssertTrue(home.contains("presentation.reviewCount > 0"))
        XCTAssertFalse(home.contains("accessibilityIdentifier(\"home.trips\")"))
        XCTAssertTrue(home.contains("SaveDisplayTitle(text: \"Savvy\", pointSize: 34"))
        XCTAssertTrue(home.contains(".mapStyle(.standard(emphasis: .automatic))"))
        XCTAssertTrue(home.contains("Marker("))
        XCTAssertTrue(home.contains("SaveDoodle.stampRed"))
        XCTAssertTrue(home.contains("SaveAtlasPalette.coral"))
        XCTAssertTrue(home.contains("interactionModes: []"))
        XCTAssertFalse(home.contains("SaveTileTownCanvas"))
        XCTAssertFalse(home.contains("home.search"))
        XCTAssertFalse(home.contains("home.tileTown"))
        XCTAssertFalse(home.contains("map.lens.nearby"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SaveTileTownHomeView.swift"
            ).path
        ))
        XCTAssertTrue(root.contains("SaveDoodleHomeView("))
        XCTAssertFalse(root.contains("HomeAtlasScreen()"))
        XCTAssertTrue(root.contains("saves.trips"))
        XCTAssertTrue(root.contains("Trips ›"))
        XCTAssertTrue(root.contains("onOpenTrips"))
        XCTAssertTrue(root.contains("accessibilityElement(children: .ignore)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("app.buttons[\"saves.trips\"]"))
        XCTAssertTrue(rail.contains("home.passport"))
        XCTAssertTrue(rail.contains("home.locationPrompt"))
        XCTAssertTrue(rail.contains("home.locationAllow"))
        XCTAssertTrue(rail.contains("home.collected"))
        XCTAssertFalse(rail.contains("doodle-home-dark"))
        XCTAssertFalse(rail.contains("confirmed places"))
    }

    func testHomeShowsLocationDeniedPromptIdentifiers() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(home.contains("home.locationPrompt"))
        XCTAssertTrue(home.contains("home.locationAllow"))
        XCTAssertTrue(home.contains("showsLocationPrompt"))
        XCTAssertTrue(home.contains("isAuthorizationDenied && !showsEmptyHome"))
        XCTAssertTrue(home.contains(".accessibilityIdentifier(\"home.locationPrompt\")"))
        XCTAssertTrue(rail.contains("func testHomeListProgressiveSearch"))
        XCTAssertTrue(rail.contains("func testCaptureFiveTabLanding"))
        XCTAssertTrue(rail.contains("home.locationPrompt"))
        XCTAssertTrue(rail.contains("home.locationAllow"))
    }

    func testMapAppliesSharedDoodleSessionFilter() throws {
        let tokyoEat = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let tokyoGo = place(
            "teamLab",
            "1-3-8 Aomi, Koto City, Tokyo, Japan",
            .attraction
        )
        let taipeiEat = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe
        )
        let session = SaveDoodleSession(
            defaults: UserDefaults(suiteName: "save.doodle.map.\(UUID().uuidString)")!
        )
        session.lens = .go
        session.city = .city("tokyo")
        let homeIDs = SaveDoodleHomeCatalog.visiblePlaces(
            from: [tokyoEat, tokyoGo, taipeiEat],
            lens: session.lens,
            selection: session.city,
            location: nil,
            locationDenied: true
        ).map(\.id)
        XCTAssertEqual(homeIDs, [tokyoGo.id])

        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(map.contains("@EnvironmentObject private var session: SaveDoodleSession"))
        XCTAssertTrue(map.contains("if session.mapFollowsHomeFilter"))
        XCTAssertTrue(map.contains("guard session.mapFollowsHomeFilter else { return places }"))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.visiblePlaces("))
        XCTAssertTrue(map.contains("session.lens"))
        XCTAssertTrue(map.contains("session.city"))
        XCTAssertTrue(map.contains("mapAccessibilityIdentifier"))
        XCTAssertTrue(map.contains("map.city"))
        XCTAssertTrue(map.contains("map.eatGo"))
        XCTAssertTrue(map.contains("showsCityPicker = true"))
        XCTAssertTrue(map.contains("map.city.\\(group.id)"))
        XCTAssertTrue(content.contains("selectRootTab(_ tab: SaveRootTab, mapFollowsHomeFilter: Bool = false)"))
        XCTAssertTrue(content.contains("applyMapTabSelection(followsHomeFilter: mapFollowsHomeFilter)"))
        XCTAssertTrue(content.contains("private func openMapFromMiniMap()"))
        XCTAssertTrue(content.contains("beginMiniMapHandoff()"))
        XCTAssertTrue(content.contains("onOpenMap: { openMapFromMiniMap() }"))
        XCTAssertTrue(content.contains(".id(doodleSession.mapSurfaceID)"))
        XCTAssertTrue(content.contains("onSelect: { selectRootTab($0) }"))
        XCTAssertTrue(content.contains("private func showMapTab()"))
        XCTAssertTrue(content.contains("abandonMiniMapHandoff()"))
        XCTAssertTrue(map.contains("consumeMiniMapHandoff()"))
        let catalogSource = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalogSource.contains("save.doodle.mapFollows."))
        XCTAssertTrue(catalogSource.contains("mapFollowsHomeFilter = defaults.bool(forKey: Self.followKey)"))
        XCTAssertTrue(catalogSource.contains("func beginMiniMapHandoff()"))
        XCTAssertTrue(catalogSource.contains("func consumeMiniMapHandoff()"))
        XCTAssertTrue(catalogSource.contains("func abandonMiniMapHandoff()"))
        XCTAssertTrue(catalogSource.contains("func applyMapTabSelection(followsHomeFilter: Bool)"))
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("session.consumeMiniMapHandoff()"))
        XCTAssertTrue(root.contains(".accessibilityIdentifier(\"map.root\")"))
        XCTAssertFalse(
            root.contains("accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"map.root\")"),
            "map.root must not wrap children in contain+id or map.eat/map.go disappear"
        )
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testHomeAndPassportWarmDarkMode"))
        XCTAssertTrue(rail.contains("home.eat"))
        XCTAssertTrue(rail.contains("home.citySwitcher"))
        XCTAssertTrue(rail.contains("captureHomeAndPassportCanvas"))
        XCTAssertTrue(rail.contains("func testMiniMapOpensMapWithCarriedFilterAndCityChange"))
        XCTAssertTrue(rail.contains("app.buttons[\"map.go\"]"))
        XCTAssertTrue(rail.contains("app.buttons[\"map.eat\"]"))
        XCTAssertEqual(
            content.components(separatedBy: "selectedRootTab = .map").count - 1,
            1,
            "Only showMapTab() may assign Map directly; other opens must go through it"
        )
        for name in [
            "func openMapSearch",
            "func openCollaborativeListOnMap",
            "func showMapCandidatesOnMap",
            "func addClueToReviewCandidate",
            "func openExactSearch",
        ] {
            XCTAssertTrue(content.contains(name), name)
        }
        XCTAssertGreaterThanOrEqual(
            content.components(separatedBy: "showMapTab()").count - 1,
            6,
            "Search, show-on-map, and list handoffs must clear the Home filter"
        )
        XCTAssertTrue(session.mapFollowsHomeFilter == false)
        session.mapFollowsHomeFilter = true
        XCTAssertTrue(session.mapFollowsHomeFilter)
        session.mapFollowsHomeFilter = false
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertTrue(map.contains("[.isButton, .isSelected] : .isButton"))
    }

    func testMiniMapHandoffSurvivesDefaultFalseAndShowOnMapClearsIt() {
        let defaults = UserDefaults(suiteName: "save.doodle.handoff.\(UUID().uuidString)")!
        let session = SaveDoodleSession(defaults: defaults)
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)
        let firstSurface = session.mapSurfaceID

        session.beginMiniMapHandoff()
        XCTAssertTrue(session.pendingMiniMapHandoff)
        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertNotEqual(session.mapSurfaceID, firstSurface)

        session.applyMapTabSelection(followsHomeFilter: false)
        XCTAssertTrue(
            session.mapFollowsHomeFilter,
            "A tab-bar default-false write must not beat a pending mini-map handoff"
        )

        session.consumeMiniMapHandoff()
        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)

        session.abandonMiniMapHandoff()
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)

        session.beginMiniMapHandoff()
        session.consumeMiniMapHandoff()
        XCTAssertTrue(session.mapFollowsHomeFilter)
        session.applyMapTabSelection(followsHomeFilter: false)
        XCTAssertFalse(
            session.mapFollowsHomeFilter,
            "Direct Map tab after a consumed handoff must clear Eat/Go"
        )

        session.beginMiniMapHandoff()
        session.abandonMiniMapHandoff()
        XCTAssertFalse(
            session.mapFollowsHomeFilter,
            "show-on-map / search must abandon a leftover mini-map filter"
        )
        XCTAssertFalse(session.pendingMiniMapHandoff)
    }

    private func place(
        _ name: String,
        _ address: String,
        _ category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        latitude: Double = 25.033,
        longitude: Double = 121.5654,
        createdAt: Date = Date()
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
            status: status,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: createdAt
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
