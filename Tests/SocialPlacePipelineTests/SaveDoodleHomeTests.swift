import CoreLocation
import UIKit
import XCTest
@testable import SAVE

@MainActor
final class SaveDoodleHomeTests: XCTestCase {
    func testVisitHistoryIsSharedAcrossSurfacesAndSurvivesUndoAndRelaunch() {
        let suite = "save.doodle.shared-visits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var day = Date(timeIntervalSince1970: 1_760_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let map = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: { day })
        let passport = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: { day })
        let id = UUID()
        for expected in 1...5 {
            XCTAssertTrue(map.recordVisit(for: id))
            XCTAssertFalse(passport.recordVisit(for: id), "No duplicate same-day visit from another surface")
            XCTAssertEqual(passport.count(for: id), expected)
            if expected < 5 { day = day.addingTimeInterval(86_400) }
        }
        XCTAssertTrue(passport.undoToday(for: id))
        XCTAssertEqual(map.count(for: id), 4)
        XCTAssertFalse(map.hasVisitedToday(id))
        XCTAssertTrue(map.recordVisit(for: id))
        XCTAssertEqual(SaveDoodleVisitStore(defaults: defaults).count(for: id), 5)
    }

    func testVisitHistoryPreservesLegacyCountsWithoutDoubleCounting() {
        let suite = "save.doodle.legacy-visits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        defaults.set(5, forKey: SaveDoodleVisitStore.countKey(id))
        defaults.set([id.uuidString: [1_600_000_000.0]], forKey: SaveDoodleVisitStore.datesKey)
        let store = SaveDoodleVisitStore(defaults: defaults)
        XCTAssertEqual(store.count(for: id), 5)
        XCTAssertTrue(store.recordVisit(for: id))
        XCTAssertEqual(store.count(for: id), 6)
        XCTAssertTrue(store.undoToday(for: id))
        XCTAssertEqual(store.count(for: id), 5)
    }

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
        XCTAssertEqual(progress.goal, 2)
        XCTAssertEqual(SaveDoodleHomeCatalog.collectedStamps(in: [visited, saved]).map(\.name), ["Duck"])
    }

    /// T1 extras use 0,0 so they stay off the map. The vault must still
    /// reload them or Home Collected collapses to the four nearby pins (3/4).
    func testDoodleParityExtrasSurviveVaultRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("vault.json")
        )
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let seeded = ReviewDemoSeed.doodleParityPlaces(now: now)
        XCTAssertEqual(seeded.filter { !$0.isMapKitMappable }.count, 8)
        for place in seeded {
            _ = try vault.saveConfirmedPlace(place)
        }
        let reloaded = try SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("vault.json")
        ).confirmedPlaces()
        XCTAssertEqual(reloaded.count, 12)
        let location = CLLocation(latitude: 39.8822, longitude: 116.4066)
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: reloaded,
            selection: .nearYou,
            location: location,
            locationDenied: false
        )
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertEqual(count.visited, 4)
        XCTAssertEqual(count.saved, 12)
    }

    func testNearYouWithoutLocationDoesNotReturnWorldwidePlaces() {
        let beijing = place("Duck", "Beijing, China", .food)
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [beijing, tokyo],
            lens: .eat,
            selection: .nearYou,
            location: nil,
            locationDenied: false
        )
        XCTAssertTrue(visible.isEmpty)
        XCTAssertTrue(
            SaveDoodleHomeCatalog.collectedScopePlaces(
                from: [beijing, tokyo],
                selection: .nearYou,
                location: nil,
                locationDenied: false
            ).isEmpty
        )
    }

    /// T1: city A has 12 saves and 4 visited across Eat and Go. Home reads
    /// Collected 4/12 while the Eat list still shows three nearby rows.
    func testT1HomeCollectedFourOfTwelveWithThreeEatRows() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let listed = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .eat,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(
            listed.map(\.place.name),
            ["Siji Minfu Roast Duck", "Fangzhuangchang Noodles", "Grey Cafe"]
        )
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertEqual(count.visited, 4)
        XCTAssertEqual(count.saved, 12)
        XCTAssertEqual(
            SaveDoodleHomeCatalog.collectedProgress(in: scope).goal,
            count.saved
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.cityDisplayName(for: listed[0].place, language: .english),
            "Tiantan"
        )
    }

    /// T2: switching Eat → Go must not change Collected X/Y.
    func testT2HomeCollectedUnchangedWhenSwitchingToGo() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let eat = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        let goListed = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .go,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        let go = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        XCTAssertNotEqual(goListed.count, 12)
        XCTAssertEqual(eat.visited, 4)
        XCTAssertEqual(eat.saved, 12)
        XCTAssertEqual(go.visited, eat.visited)
        XCTAssertEqual(go.saved, eat.saved)
    }

    /// T3: the production "I've been here" / Mark visited path increments
    /// X and leaves Y at 12. Do not mutate fixture `status` directly.
    func testT3HomeCollectedIncreasesAfterMarkVisited() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let suite = "save.doodle.t3.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SaveDoodleVisitStore(defaults: defaults)
        var places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let greyIndex = places.firstIndex { $0.name == "Grey Cafe" }!
        XCTAssertEqual(places[greyIndex].status, .wantToGo)
        places[greyIndex] = store.markIveBeenHere(places[greyIndex])
        XCTAssertEqual(places[greyIndex].status, .visited)
        XCTAssertEqual(store.count(for: places[greyIndex].id), 1)
        let count = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        XCTAssertEqual(count.visited, 5)
        XCTAssertEqual(count.saved, 12)
    }

    /// T4: switching to city B (3 saved, 1 visited) reads 1/3, not a
    /// hardcoded passport-goal 12.
    func testT4HomeCollectedFollowsCitySwitch() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let cityA = ReviewDemoSeed.doodleParityPlaces(now: now)
        let tokyo = "1-22-7 Jinnan, Shibuya City, Tokyo, Japan"
        let cityB = [
            place("Ichiran", tokyo, .food, status: .visited, createdAt: now),
            place("Hotel", tokyo, .stay, createdAt: now.addingTimeInterval(-1)),
            place("Shop", tokyo, .shopping, createdAt: now.addingTimeInterval(-2)),
        ]
        let all = cityA + cityB
        let tiantan = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: all,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        XCTAssertEqual(tiantan.visited, 4)
        XCTAssertEqual(tiantan.saved, 12)
        let tokyoCount = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: all,
                selection: .city("tokyo"),
                location: nil,
                locationDenied: true
            )
        )
        XCTAssertEqual(tokyoCount.visited, 1)
        XCTAssertEqual(tokyoCount.saved, 3)
        XCTAssertEqual(
            SaveDoodleHomeCatalog.collectedProgress(in: cityB).goal,
            tokyoCount.saved
        )
    }

    /// City has saves, current Eat/Go list is empty: keep Collected X/Y
    /// and show a filter-empty message instead of the whole empty Home.
    func testHomeCollectedStaysVisibleWhenLensHasNoRows() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let eatOnly = [
            place("Duck", "Beijing, China", .food, status: .visited, createdAt: now),
            place("Grey", "Beijing, China", .cafe, createdAt: now.addingTimeInterval(-1)),
        ]
        let goListed = SaveDoodleHomeCatalog.listedPlaces(
            from: eatOnly,
            lens: .go,
            selection: .city("beijing"),
            location: nil,
            locationDenied: true
        )
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: eatOnly,
            selection: .city("beijing"),
            location: nil,
            locationDenied: true
        )
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertTrue(goListed.isEmpty)
        XCTAssertEqual(count.visited, 1)
        XCTAssertEqual(count.saved, 2)
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertTrue(home.contains("showsLensEmpty"))
        XCTAssertTrue(home.contains("home.lensEmpty"))
        XCTAssertTrue(home.contains("No \\(lens) saves here"))
        let bodyAt = try XCTUnwrap(home.range(of: "var body: some View"))
        let headerAt = try XCTUnwrap(home.range(of: "private var savesButton"))
        let body = home[bodyAt.lowerBound..<headerAt.lowerBound]
        XCTAssertTrue(body.contains("if showsLensEmpty"))
        XCTAssertTrue(body.contains("else if !showsEmptyHome"))
        XCTAssertTrue(body.contains("if !collectedPlaces.isEmpty"))
        let listBranch = try XCTUnwrap(body.range(of: "else if !showsEmptyHome"))
        let collectedAt = try XCTUnwrap(body.range(of: "if !collectedPlaces.isEmpty"))
        XCTAssertTrue(
            collectedAt.lowerBound > listBranch.upperBound,
            "Collected must not sit only inside the filtered-list branch"
        )
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("keep the Collected strip and show a filter-empty message"))
    }

    /// T5: a city with no saves hides the strip (or would be 0/0) and
    /// does not crash.
    func testT5HomeCollectedHiddenWhenCityHasNoSaves() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .city("osaka"),
            location: nil,
            locationDenied: true
        )
        XCTAssertTrue(scope.isEmpty)
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertEqual(count.visited, 0)
        XCTAssertEqual(count.saved, 0)
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertTrue(home.contains("if !collectedPlaces.isEmpty"))
        XCTAssertTrue(home.contains("collectedStrip"))
    }

    /// T6: the Collected strip opens the real Passport screen with the
    /// same city numbers. `SaveDoodleHomeProgressCatalog` is the Home X/Y
    /// type; PR #295 keeps `SaveDoodlePassportCatalog` for stamp-grid layout.
    func testT6HomeCollectedOpensPassportWithSameCount() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let homeScope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        let homeCount = SaveDoodleHomeCatalog.cityCollectedCount(in: homeScope)
        let passportPlaces = SaveDoodleHomeProgressCatalog.cityPlaces(
            from: places,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        XCTAssertEqual(homeCount.visited, 4)
        XCTAssertEqual(homeCount.saved, 12)
        XCTAssertEqual(SaveDoodleHomeProgressCatalog.visitedCount(in: passportPlaces), homeCount.visited)
        XCTAssertEqual(passportPlaces.count, homeCount.saved)
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let strip = try XCTUnwrap(home.range(of: "private var collectedStrip"))
        let empty = try XCTUnwrap(home.range(of: "private var emptyHome"))
        XCTAssertTrue(home[strip.lowerBound..<empty.lowerBound].contains("presentation.onOpenPassport"))
        XCTAssertTrue(home.contains("Collected \\(progress.visited)/\\(progress.saved)"))
        let passport = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportView.swift")
        XCTAssertTrue(passport.contains("cityCollectedCount(in: cityPlaces)"))
        XCTAssertTrue(passport.contains("\\(count.visited) of \\(count.saved) visited"))
        XCTAssertTrue(passport.contains("profile.stampProgress"))
        let catalog = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalog.contains("enum SaveDoodleHomeProgressCatalog"))
        XCTAssertFalse(catalog.contains("enum SaveDoodlePassportCatalog"))
        XCTAssertTrue(catalog.contains("collectedScopePlaces"))
        XCTAssertTrue(catalog.contains("PR #295 already owns"))
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("SaveDoodlePassportPage("))
        XCTAssertTrue(profile.contains("SaveDoodleHomeProgressCatalog.cityPlaces"))
        XCTAssertTrue(profile.contains("places: cityStampPlaces"))
        XCTAssertTrue(profile.contains("markIveBeenHere"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testHomeCollectedOpensPassportWithCityCount"))
        XCTAssertTrue(rail.contains("func testSavesTripsBackReturnsToSaves"))
        XCTAssertTrue(rail.contains("home.collected"))
        XCTAssertTrue(rail.contains("profile.stampProgress"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-fixture"))
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
        XCTAssertTrue(home.contains("eatGoRow"))
        XCTAssertTrue(home.contains("fixedSize(horizontal: true, vertical: false)"))
        let headerAt = try XCTUnwrap(home.range(of: "private var header"))
        let eatRowAt = try XCTUnwrap(home.range(of: "private var eatGoRow"))
        XCTAssertTrue(home[headerAt.lowerBound..<eatRowAt.lowerBound].contains("eatGoRow"))
        let cluesAt = try XCTUnwrap(home.range(of: "cluesLine"))
        let mapAt = try XCTUnwrap(home.range(of: "miniMap"))
        let rowsAt = try XCTUnwrap(home.range(of: "placeList"))
        let collectedAt = try XCTUnwrap(home.range(of: "collectedStrip"))
        XCTAssertLessThan(cluesAt.lowerBound, mapAt.lowerBound)
        XCTAssertLessThan(mapAt.lowerBound, rowsAt.lowerBound)
        XCTAssertLessThan(rowsAt.lowerBound, collectedAt.lowerBound)
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
        XCTAssertTrue(home.contains("collectedScopePlaces"))
        XCTAssertTrue(home.contains("if !collectedPlaces.isEmpty"))
        XCTAssertTrue(home.contains("showsLensEmpty"))
        XCTAssertTrue(home.contains("home.lensEmpty"))
        XCTAssertTrue(home.contains("home.empty.capture"))
        XCTAssertTrue(home.contains("home.review"))
        let cluesFn = try XCTUnwrap(home.range(of: "private var cluesLine"))
        let locationFn = try XCTUnwrap(home.range(of: "private var locationPrompt"))
        let cluesBody = home[cluesFn.lowerBound..<locationFn.lowerBound]
        XCTAssertTrue(cluesBody.contains("minHeight: SaveLayout.minTap"))
        XCTAssertTrue(cluesBody.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(home.contains("home.openSaves"))
        XCTAssertFalse(home.contains("showsUITestSavesRoute"))
        XCTAssertFalse(home.contains("hiddenSavesRoute"))
        XCTAssertTrue(home.contains("SaveLayout.minTap"))
        XCTAssertFalse(home.contains("\"home.saves\""))
        XCTAssertFalse(home.contains("See all saves"))
        XCTAssertFalse(home.contains("看全部收藏"))
        XCTAssertTrue(home.contains("presentation.reviewCount > 0"))
        let factory = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        XCTAssertFalse(factory.contains("presentation.reviewCount = mapViewModel.reviewCandidates.count"))
        XCTAssertFalse(home.contains("accessibilityIdentifier(\"home.trips\")"))
        XCTAssertTrue(home.contains("SaveDisplayTitle("))
        XCTAssertTrue(home.contains("text: \"Savvy\""))
        XCTAssertTrue(home.contains("pointSize: 34"))
        XCTAssertTrue(home.contains("locksPointSize: true"))
        XCTAssertTrue(home.contains("pointSize: 20"))
        XCTAssertTrue(home.contains(".frame(height: 2)"))
        XCTAssertTrue(home.contains("height: SaveLayout.chipHeight"))
        XCTAssertFalse(home.contains("minWidth: SaveLayout.minTap, height:"))
        XCTAssertTrue(home.contains(".frame(height: 160)"))
        XCTAssertTrue(home.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(home.contains("SaveLayout.stickerBox"))
        XCTAssertTrue(home.contains("SaveLayout.stickerArt"))
        XCTAssertTrue(home.contains("SaveLayout.rowMinHeight"))
        XCTAssertTrue(home.contains("SaveDoodleOfficialSticker"))
        XCTAssertTrue(home.contains("DoodleSticker"))
        XCTAssertFalse(home.contains("SaveDoodleStickerShape"))
        XCTAssertFalse(home.contains("SaveDoodleElephantShape"))
        for name in ["Duck", "Noodle", "Coffee", "Temple", "Lantern", "Elephant"] {
            for suffix in ["Color", "Color48", "Outline"] {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: repositoryRoot.appendingPathComponent(
                            "SAV-E/Resources/Assets.xcassets/DoodleSticker\(name)\(suffix).imageset/Contents.json"
                        ).path
                    ),
                    "Missing official sticker imageset DoodleSticker\(name)\(suffix)"
                )
            }
        }
        XCTAssertTrue(home.contains(".frame(height: 44)"))
        XCTAssertTrue(home.contains("SaveDoodle.stampRed"))
        XCTAssertTrue(home.contains("AtlasTabBarMetrics.height"))
        XCTAssertFalse(home.contains("rootTabScrollClearance"))
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
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("Savvy + Eat/Go in the header"))
        XCTAssertTrue(design.contains("official DESIGN color die-cut"))
        XCTAssertTrue(design.contains("brand-only"))
        XCTAssertTrue(design.contains("Codex packet and spec §8"))
        XCTAssertTrue(design.contains("0.90 visual-parity score is not evidence"))
        XCTAssertTrue(home.contains("placeCases"))
        XCTAssertTrue(home.contains("SaveDoodleElephant"))
        XCTAssertTrue(home.contains("SaveDoodleEmptyPlate"))
        XCTAssertTrue(design.contains("then the city, clues"))
        XCTAssertTrue(design.contains("HoP 2026-10-21"))
        XCTAssertTrue(design.contains("every category"))
        XCTAssertTrue(design.contains("eade369"))
        XCTAssertTrue(design.contains("home-mask.png"))
        XCTAssertTrue(design.contains("judged manually by DESIGN"))
        XCTAssertTrue(design.contains("v1 is retired"))
        XCTAssertFalse(design.contains("23cca55"))
        XCTAssertTrue(design.contains("像素小鎮已經不要了"))
        XCTAssertTrue(design.contains("tile-town is abandoned"))
        XCTAssertFalse(design.contains("Home hero and Map become a full-pixel isometric"))
        let bridge = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        XCTAssertTrue(bridge.contains("Home is `SaveDoodleHomeView`"))
        XCTAssertFalse(bridge.contains("Live Home uses the tile-town peek"))
        let readme = try source(at: "Prototypes/AtlasPostcard/README.md")
        XCTAssertTrue(readme.contains("home-light.png"))
        XCTAssertTrue(readme.contains("eade369"))
        XCTAssertTrue(readme.contains("home-mask.png"))
        XCTAssertTrue(readme.contains("white = ignore"))
        XCTAssertTrue(readme.contains("position"))
        XCTAssertFalse(readme.contains("23cca55"))
        XCTAssertFalse(readme.contains("layout boxes"))
        XCTAssertTrue(readme.contains("0.90"))
        XCTAssertTrue(readme.contains("402×874") || readme.contains("402 x 874") || readme.contains("402 × 874"))
        XCTAssertFalse(readme.contains("padded with paper"))
        XCTAssertFalse(readme.contains("nearest-neighbor tile-town peek"))
        let homeTarget = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/home.png"
        )
        let homePNG = try Data(contentsOf: homeTarget)
        XCTAssertEqual([UInt8](homePNG.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(homePNG, at: 16), 402)
        XCTAssertEqual(pngDimension(homePNG, at: 20), 874)
        let homeDarkPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/home-dark.png"
        ))
        XCTAssertEqual(pngDimension(homeDarkPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(homeDarkPNG, at: 20), 874)
        let homeMaskPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/home-mask.png"
        ))
        XCTAssertEqual([UInt8](homeMaskPNG.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(homeMaskPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(homeMaskPNG, at: 20), 874)
        let parity = try source(at: "Prototypes/AtlasPostcard/Scripts/VisualParity.swift")
        XCTAssertTrue(parity.contains("--mask"))
        XCTAssertTrue(parity.contains("white = ignore"))
        XCTAssertTrue(parity.contains("\"position\""))
        XCTAssertTrue(parity.contains("\"fontStyle\""))
        let parityRunner = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(parityRunner.contains("home-mask.png"))
        XCTAssertTrue(parityRunner.contains("--mask"))
        let mapPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png"
        ))
        XCTAssertEqual(pngDimension(mapPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(mapPNG, at: 20), 874)
        XCTAssertTrue(root.contains("SaveDoodleHomeView("))
        XCTAssertFalse(root.contains("HomeAtlasScreen()"))
        XCTAssertTrue(root.contains("saves.trips"))
        XCTAssertTrue(root.contains("Trips ›"))
        XCTAssertTrue(root.contains("onOpenTrips"))
        XCTAssertTrue(design.contains("HoP acceptance H-6"))
        XCTAssertTrue(root.contains("accessibilityElement(children: .ignore)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("app.buttons[\"saves.trips\"]"))
        XCTAssertTrue(rail.contains("home.passport"))
        XCTAssertTrue(rail.contains("home.locationPrompt"))
        XCTAssertTrue(rail.contains("home.locationAllow"))
        XCTAssertTrue(rail.contains("home.collected"))
        XCTAssertTrue(rail.contains("func testHomeCollectedOpensPassportWithCityCount"))
        XCTAssertTrue(rail.contains("func testSavesTripsBackReturnsToSaves"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-fixture"))
        let chrome = try source(at: "SAV-E/App/SaveChromePresentation.swift")
        XCTAssertTrue(chrome.contains("path.contains(.saves) ? [.saves, .trips] : [.trips]"))
        let attach = try source(at: "Tests/SAVEUITests/SAVEUITestCase.swift")
        XCTAssertTrue(attach.contains("SAVE_SCREENSHOT_DIR"))
        XCTAssertTrue(attach.contains("pngRepresentation"))
        let workflow = try source(at: ".github/workflows/ios.yml")
        XCTAssertTrue(workflow.contains("SAVE_SCREENSHOT_DIR"))
        XCTAssertTrue(workflow.contains("five-tab-home"))
        XCTAssertTrue(workflow.contains("light-home"))
        XCTAssertTrue(workflow.contains("dark-home"))
        XCTAssertTrue(workflow.contains("H1"))
        XCTAssertTrue(rail.contains("\"H1\""))
        XCTAssertTrue(rail.contains("\"H2\""))
        XCTAssertTrue(rail.contains("\"H3\""))
        XCTAssertTrue(rail.contains("\"H4\""))
        XCTAssertTrue(rail.contains("44 - 0.01"))
        XCTAssertTrue(rail.contains("doodle-home-empty"))
        XCTAssertTrue(rail.contains("doodle-home-allowed"))
        XCTAssertTrue(rail.contains("doodle-home-multirow"))
        XCTAssertTrue(rail.contains("--uitest-location-allowed"))
        XCTAssertFalse(rail.contains("doodle-home-dark"))
        XCTAssertFalse(rail.contains("confirmed places"))
        let location = try source(at: "SAV-E/Services/LocationService.swift")
        XCTAssertTrue(location.contains("--uitest-location-allowed"))
        XCTAssertTrue(location.contains("simulatesAllowedAuthorization"))
        let seed = try source(at: "SAV-E/Services/ReviewDemoService.swift")
        XCTAssertTrue(seed.contains("--uitest-doodle-parity-fixture"))
        XCTAssertTrue(seed.contains("Codex packet / spec §8"))
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("SaveDoodleHomeProgressCatalog.cityPlaces"))
        XCTAssertTrue(profile.contains("markIveBeenHere"))
        let contentView = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(contentView.contains(".environmentObject(doodleSession)"))
    }

    func testElephantStickerExistsLoadsAndIsNeverAPlaceMark() throws {
        let color = repositoryRoot.appendingPathComponent(
            "SAV-E/Resources/Assets.xcassets/DoodleStickerElephantColor48.imageset/elephant-color-48.png"
        )
        let outline = repositoryRoot.appendingPathComponent(
            "SAV-E/Resources/Assets.xcassets/DoodleStickerElephantOutline.imageset/elephant-outline.pdf"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: color.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outline.path))
        let png = try Data(contentsOf: color)
        XCTAssertEqual([UInt8](png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertFalse(SaveDoodleOfficialSticker.placeCases.contains(.elephant))
        let elephantNames = ["Elephant Cafe", "White Elephant", "小象", ""]
        for category in PlaceCategory.allCases {
            for name in elephantNames {
                XCTAssertNotEqual(
                    SaveDoodleOfficialSticker.named(for: category, placeName: name),
                    .elephant,
                    "\(category.rawValue) / \(name) must not map to the brand elephant"
                )
            }
        }
    }

    func testHomeShowsLocationDeniedPromptIdentifiers() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(home.contains("home.locationPrompt"))
        XCTAssertTrue(home.contains("home.locationAllow"))
        XCTAssertTrue(home.contains("showsLocationPrompt"))
        XCTAssertTrue(home.contains("if locationService.isAuthorizationDenied"))
        XCTAssertFalse(home.contains("isAuthorizationDenied && !showsEmptyHome"))
        XCTAssertTrue(home.contains("needsLocationToResolveNearYou"))
        XCTAssertTrue(home.contains(".accessibilityIdentifier(\"home.locationPrompt\")"))
        XCTAssertTrue(rail.contains("func testHomeListProgressiveSearch"))
        XCTAssertTrue(rail.contains("func testCaptureFiveTabLanding"))
        XCTAssertTrue(rail.contains("home.locationPrompt"))
        XCTAssertTrue(rail.contains("home.locationAllow"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-face"))
        XCTAssertTrue(rail.contains("--uitest-location-allowed"))
    }

    func testDoodleParityFixtureListsThreeTiantanEatRowsAndTempleOfHeaven() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        XCTAssertEqual(
            places.map(\.name),
            [
                "Siji Minfu Roast Duck",
                "Fangzhuangchang Noodles",
                "Grey Cafe",
                "Temple of Heaven Park",
                "Lantern Alley",
                "Jingshan",
                "Houhai Bridge",
                "Page One",
                "Houhai Bicycle",
                "Chaoyang Park Wheel",
                "Summer Palace",
                "Beihai Park",
            ]
        )
        XCTAssertEqual(places.count, 12)
        XCTAssertEqual(places.filter { $0.status == .visited }.count, 4)
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: places[0], language: .english), "Tiantan")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: places[3]), SaveDoodleHomeCatalog.cityID(for: places[0]))
        XCTAssertEqual(places[3].address, "Tiantan")
        let location = CLLocation(latitude: 39.8822, longitude: 116.4066)
        let listed = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .eat,
            selection: .nearYou,
            location: location,
            locationDenied: false
        )
        XCTAssertEqual(
            listed.map(\.place.name),
            ["Siji Minfu Roast Duck", "Fangzhuangchang Noodles", "Grey Cafe"]
        )
        XCTAssertEqual(listed[0].distance ?? 0, 450, accuracy: 8)
        XCTAssertEqual(listed[1].distance ?? 0, 800, accuracy: 8)
        XCTAssertEqual(listed[2].distance ?? 0, 1_100, accuracy: 8)
        XCTAssertEqual(places.first { $0.name.contains("Temple of Heaven") }?.name, "Temple of Heaven Park")
        XCTAssertEqual(ReviewDemoSeed.doodleParityReviewCandidates(now: now).count, 2)
        let seed = try source(at: "SAV-E/Services/ReviewDemoService.swift")
        XCTAssertTrue(seed.contains("usesDoodleParityFace"))
        XCTAssertTrue(seed.contains("Temple of Heaven"))
        let locationSource = try source(at: "SAV-E/Services/LocationService.swift")
        XCTAssertTrue(locationSource.contains("uiTestTiantan"))
        XCTAssertTrue(locationSource.contains("39.8822"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("XCTAssertFalse(app.descendants(matching: .any)[\"home.locationPrompt\"].exists)"))
        XCTAssertTrue(rail.contains("Temple of Heaven Park"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-face"))
        XCTAssertTrue(rail.contains("Collected 4/12"))
        XCTAssertTrue(rail.contains("doodle-home-go"))
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: places)
        XCTAssertEqual(count.visited, 4)
        XCTAssertEqual(count.saved, 12)
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

        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(map.contains("@EnvironmentObject private var session: SaveDoodleSession"))
        XCTAssertTrue(map.contains("header(followsHomeFilter: followsHomeFilter)"))
        XCTAssertTrue(map.contains("onChange(of: session.mapVisitResidueID)"))
        XCTAssertTrue(map.contains("applyMiniMapHandoff()"))
        XCTAssertTrue(map.contains("if session.mapFollowsHomeFilter"))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.listedPlaces("))
        XCTAssertTrue(map.contains("session.lens"))
        XCTAssertTrue(map.contains("session.city"))
        XCTAssertTrue(map.contains("mapAccessibilityIdentifier"))
        XCTAssertTrue(map.contains("map.city"))
        XCTAssertTrue(map.contains("map.eatGo"))
        XCTAssertTrue(map.contains("onChange(of: session.lens)"))
        XCTAssertTrue(map.contains("onChange(of: session.city)"))
        XCTAssertTrue(map.contains("onClearSelection()"))
        XCTAssertTrue(map.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(map.contains("showsCityPicker = true"))
        XCTAssertTrue(map.contains("map.city.\\(group.id)"))
        XCTAssertTrue(content.contains("selectRootTab(_ tab: SaveRootTab, mapFollowsHomeFilter: Bool = false)"))
        XCTAssertTrue(content.contains("applyMapTabSelection(followsHomeFilter: mapFollowsHomeFilter)"))
        XCTAssertTrue(content.contains("private func openMapFromMiniMap()"))
        XCTAssertTrue(content.contains("beginMiniMapHandoff()"))
        XCTAssertTrue(content.contains("onOpenMap: { openMapFromMiniMap() }"))
        XCTAssertTrue(content.contains("let mapIdentity = doodleSession.mapSurfaceID"))
        XCTAssertTrue(content.contains(".id(mapIdentity)"))
        XCTAssertTrue(content.contains("resetMapVisitResidue()"))
        XCTAssertTrue(content.contains("clearSelectedMapObject()"))
        XCTAssertTrue(content.contains("onSelect: { selectRootTab($0) }"))
        XCTAssertTrue(content.contains("SaveDoodleTabIcon("))
        XCTAssertFalse(content.contains("SavePixelChromeIcon("))
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
        XCTAssertTrue(catalogSource.contains("mapVisitResidueID = UUID()"))
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("session.consumeMiniMapHandoff()"))
        XCTAssertTrue(root.contains(".accessibilityIdentifier(\"map.root\")"))
        XCTAssertTrue(
            root.contains("accessibilityElement(children: .contain)"),
            "map.root must keep the contain container the other Map UI tests query"
        )
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testHomeAndPassportWarmDarkMode"))
        XCTAssertTrue(rail.contains("home.eat"))
        XCTAssertTrue(rail.contains("home.citySwitcher"))
        XCTAssertTrue(rail.contains("captureHomeAndPassportCanvas"))
        XCTAssertTrue(rail.contains("func testMiniMapOpensMapWithCarriedFilterAndCityChange"))
        XCTAssertTrue(rail.contains("app.buttons[\"map.go\"]"))
        XCTAssertTrue(rail.contains("app.buttons[\"map.eat\"]"))
        XCTAssertFalse(rail.contains("recordQ5ReusedMapTree"))
        XCTAssertFalse(rail.contains("q5-reused-map-debugDescription"))
        XCTAssertFalse(rail.contains("q5-reused-map"))
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

    func testBeginMiniMapHandoffResetsPriorMapVisitResidue() throws {
        let defaults = UserDefaults(suiteName: "save.doodle.residue.\(UUID().uuidString)")!
        let session = SaveDoodleSession(defaults: defaults)
        session.mapFollowsHomeFilter = false
        let leftoverSurface = session.mapSurfaceID
        let leftoverResidue = session.mapVisitResidueID

        session.beginMiniMapHandoff()

        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertTrue(session.pendingMiniMapHandoff)
        XCTAssertNotEqual(
            session.mapSurfaceID,
            leftoverSurface,
            "Mini-map must give Map a new identity so a reused tab remounts Eat/Go"
        )
        XCTAssertNotEqual(
            session.mapVisitResidueID,
            leftoverResidue,
            "Mini-map must drop leftover selected-pin / drawer / first-appear chrome"
        )

        session.consumeMiniMapHandoff()
        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)

        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("onChange(of: doodleSession.mapVisitResidueID)"))
        XCTAssertTrue(content.contains("mapVM.clearSelectedMapObject()"))
        XCTAssertTrue(content.contains("isMapPanelExpanded = false"))
        XCTAssertTrue(content.contains("drawerVM.returnToCommands()"))
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(map.contains("showsCityPicker = false"))
        XCTAssertTrue(map.contains(".id(visitResidue)"))
    }

    private var tiantanFix: CLLocation {
        CLLocation(latitude: 39.8822, longitude: 116.4066)
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

    private func pngDimension(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
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
