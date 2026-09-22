import XCTest
import SpriteKit
@testable import SAVE

@MainActor
final class SaveHomeSearchTests: XCTestCase {
    func testCityChipsDisplayReadableLocalizedNames() {
        XCTAssertEqual(SaveHomeSearch.cityLabel(for: "losAngeles", traditionalChinese: false), "Los Angeles")
        XCTAssertEqual(SaveHomeSearch.cityLabel(for: "newYork", traditionalChinese: true), "紐約")
        XCTAssertEqual(SaveHomeSearch.cityLabel(for: "sanFrancisco", traditionalChinese: false), "San Francisco")
        XCTAssertEqual(SaveHomeSearch.cityLabel(for: "tokyo", traditionalChinese: true), "東京")
        XCTAssertNil(SaveHomeSearch.cityLabel(for: "quiet", traditionalChinese: false))
    }

    func testEmptySearchReturnsAllPlacesInInputOrderIncludingVisited() {
        let first = place(name: "First", address: "Taipei", category: .cafe, status: .wantToGo)
        let second = place(name: "Second", address: "New Taipei", category: .food, status: .visited)

        XCTAssertEqual(SaveHomeSearch().matchingPlaces(in: [first, second]).map(\.id), [first.id, second.id])
    }

    func testCombinedChineseAndSequentialEnglishCategoryCityQueriesAreEquivalent() {
        let taipeiCafe = place(name: "Mori", address: "Taipei City, Da'an", category: .cafe)
        let taipeiFood = place(name: "Noodle", address: "Taipei City, Da'an", category: .food)
        let newTaipeiCafe = place(name: "River", address: "New Taipei City, Banqiao", category: .cafe)
        let places = [taipeiCafe, taipeiFood, newTaipeiCafe]

        var sequential = SaveHomeSearch(draft: "cafe")
        sequential.commitDraft()
        sequential.draft = "Taipei"
        sequential.commitDraft()

        var combined = SaveHomeSearch(draft: "台北咖啡店")
        combined.commitDraft()

        var spaced = SaveHomeSearch(draft: "臺北 咖啡店")
        spaced.commitDraft()

        XCTAssertEqual(sequential.matchingPlaces(in: places).map(\.id), [taipeiCafe.id])
        XCTAssertEqual(combined.matchingPlaces(in: places).map(\.id), [taipeiCafe.id])
        XCTAssertEqual(spaced.matchingPlaces(in: places).map(\.id), [taipeiCafe.id])
        XCTAssertEqual(combined.filters.count, 2)
    }

    func testDraftAlsoIntersectsCommittedFiltersAndCategoryRemovalBroadens() {
        let taipeiCafe = place(name: "Mori", address: "Taipei City", category: .cafe)
        let taipeiFood = place(name: "Noodle", address: "Taipei City", category: .food)
        let search = SaveHomeSearch(filters: ["cafe"], draft: "Taipei")

        XCTAssertEqual(search.matchingPlaces(in: [taipeiCafe, taipeiFood]).map(\.id), [taipeiCafe.id])

        var mutable = search
        mutable.removeFilter("café")
        XCTAssertEqual(mutable.matchingPlaces(in: [taipeiCafe, taipeiFood]).map(\.id), [taipeiCafe.id, taipeiFood.id])
    }

    func testCategoryAliasesAreDeduplicatedAndAccentsNormalize() {
        var search = SaveHomeSearch(draft: "café")
        search.commitDraft()
        search.draft = "coffee shop"
        search.commitDraft()
        search.draft = "咖啡店"
        search.commitDraft()

        XCTAssertEqual(search.filters, ["cafe"])
        XCTAssertTrue(search.isActive)
    }

    func testRecognizedCategoryUsesTheSavedCategoryRatherThanAPlaceName() {
        let cafeNamedRestaurant = place(name: "Cafe in name only", address: "Taipei City", category: .food)
        let actualCafe = place(name: "Mori", address: "Taipei City", category: .cafe)

        XCTAssertEqual(
            SaveHomeSearch(draft: "cafe").matchingPlaces(in: [cafeNamedRestaurant, actualCafe]).map(\.id),
            [actualCafe.id]
        )
    }

    func testCityOnlyMatchesAddressAndTaipeiDoesNotMatchNewTaipei() {
        let taipei = place(name: "Taipei Story", address: "Taipei City, Zhongshan", category: .cafe)
        let falsePositive = place(
            name: "Elsewhere Coffee",
            address: "Taoyuan City, Taoyuan",
            category: .cafe,
            note: "Recommended during a Taipei trip",
            vibeTags: ["taipei favorite"]
        )
        let newTaipei = place(name: "Riverside", address: "New Taipei City, Banqiao", category: .cafe)

        let matches = SaveHomeSearch(draft: "Taipei").matchingPlaces(in: [taipei, falsePositive, newTaipei])

        XCTAssertEqual(matches.map(\.id), [taipei.id])
    }

    func testCombinedNewTaipeiCityAndPluralCafeQueriesSurviveCommitAndCanonicalRemoval() {
        let taipeiCafe = place(name: "Mori", address: "Taipei City, Da'an", category: .cafe)
        let newTaipeiCafe = place(name: "River", address: "New Taipei City, Banqiao", category: .cafe)
        let places = [taipeiCafe, newTaipeiCafe]

        let englishDraft = SaveHomeSearch(draft: "New Taipei coffee shops")
        XCTAssertEqual(englishDraft.matchingPlaces(in: places).map(\.id), [newTaipeiCafe.id])

        var englishCommitted = englishDraft
        englishCommitted.commitDraft()
        XCTAssertEqual(englishCommitted.filters, ["newTaipei", "cafe"])
        XCTAssertEqual(englishCommitted.matchingPlaces(in: places).map(\.id), [newTaipeiCafe.id])

        let chineseDraft = SaveHomeSearch(draft: "新北咖啡店")
        XCTAssertEqual(chineseDraft.matchingPlaces(in: places).map(\.id), [newTaipeiCafe.id])

        var chineseCommitted = chineseDraft
        chineseCommitted.commitDraft()
        XCTAssertEqual(chineseCommitted.filters, ["newTaipei", "cafe"])
        XCTAssertEqual(chineseCommitted.matchingPlaces(in: places).map(\.id), [newTaipeiCafe.id])

        englishCommitted.removeFilter("newTaipei")
        XCTAssertEqual(englishCommitted.filters, ["cafe"])
        XCTAssertEqual(englishCommitted.matchingPlaces(in: places).map(\.id), [taipeiCafe.id, newTaipeiCafe.id])
    }

    func testTokyoCityQueryUsesAddressOnlyBeforeAndAfterEnglishAndChineseCommit() {
        let savedTokyo = place(name: "Kissa", address: "Tokyo, Shibuya", category: .cafe)
        let bangkokWithTokyoNote = place(
            name: "Bangkok Cafe",
            address: "Bangkok, Pathum Wan",
            category: .cafe,
            note: "A Tokyo favorite"
        )
        let places = [savedTokyo, bangkokWithTokyoNote]

        let englishDraft = SaveHomeSearch(draft: "Tokyo cafes")
        XCTAssertEqual(englishDraft.matchingPlaces(in: places).map(\.id), [savedTokyo.id])

        var englishCommitted = englishDraft
        englishCommitted.commitDraft()
        XCTAssertEqual(englishCommitted.filters, ["tokyo", "cafe"])
        XCTAssertEqual(englishCommitted.matchingPlaces(in: places).map(\.id), [savedTokyo.id])

        let chineseDraft = SaveHomeSearch(draft: "東京咖啡店")
        XCTAssertEqual(chineseDraft.matchingPlaces(in: places).map(\.id), [savedTokyo.id])

        var chineseCommitted = chineseDraft
        chineseCommitted.commitDraft()
        XCTAssertEqual(chineseCommitted.filters, ["tokyo", "cafe"])
        XCTAssertEqual(chineseCommitted.matchingPlaces(in: places).map(\.id), [savedTokyo.id])

        XCTAssertTrue(SaveHomeSearch(draft: "Tokyo").matchingPlaces(in: [bangkokWithTokyoNote]).isEmpty)
    }

    func testRecognizedGlobalCityCanonicalChipsRoundTrip() {
        let fixtures: [(query: String, canonical: String, address: String)] = [
            ("Tokyo", "tokyo", "Tokyo, Shibuya"),
            ("Los Angeles", "losAngeles", "Los Angeles, California"),
            ("Bangkok", "bangkok", "Bangkok, Pathum Wan"),
            ("Kyoto", "kyoto", "Kyoto, Sakyo"),
            ("Osaka", "osaka", "Osaka, Naniwa"),
            ("New York", "newYork", "New York, Manhattan"),
            ("San Francisco", "sanFrancisco", "San Francisco, California"),
            ("Seoul", "seoul", "Seoul, Jongno"),
            ("Singapore", "singapore", "Singapore"),
            ("Hong Kong", "hongKong", "Hong Kong, Central"),
            ("Paris", "paris", "Paris, France"),
            ("London", "london", "London, England"),
            ("Shanghai", "shanghai", "Shanghai, China"),
            ("Beijing", "beijing", "Beijing, China"),
            ("Guangzhou", "guangzhou", "Guangzhou, China"),
            ("Shenzhen", "shenzhen", "Shenzhen, China"),
            ("Chengdu", "chengdu", "Chengdu, China"),
        ]

        for fixture in fixtures {
            let savedPlace = place(name: fixture.query, address: fixture.address, category: .cafe)
            var committed = SaveHomeSearch(draft: fixture.query)
            committed.commitDraft()

            XCTAssertEqual(committed.filters, [fixture.canonical], fixture.query)
            XCTAssertEqual(committed.matchingPlaces(in: [savedPlace]).map(\.id), [savedPlace.id], fixture.query)
            XCTAssertEqual(
                SaveHomeSearch(draft: fixture.canonical).matchingPlaces(in: [savedPlace]).map(\.id),
                [savedPlace.id],
                fixture.canonical
            )
        }
    }

    func testUnknownTermsUseExistingSearchableMetadataAndUnknownTermsCanReturnNothing() {
        let cozy = place(
            name: "Mori",
            address: "Taipei City",
            category: .cafe,
            note: "A quiet courtyard",
            vibeTags: ["cozy"]
        )
        let other = place(name: "Noodle", address: "Taipei City", category: .food)

        XCTAssertEqual(SaveHomeSearch(draft: "cozy").matchingPlaces(in: [cozy, other]).map(\.id), [cozy.id])
        XCTAssertTrue(SaveHomeSearch(draft: "unrecorded phrase").matchingPlaces(in: [cozy, other]).isEmpty)
    }

    func testAllMatchesAreReturnedWithoutVisibleBudgetTruncationAndInInputOrder() {
        let places = (0..<125).map { index in
            place(
                name: "Cafe \(index)",
                address: "Taipei City",
                category: .cafe,
                status: index.isMultiple(of: 2) ? .wantToGo : .visited
            )
        }

        let matches = SaveHomeSearch(draft: "咖啡店 台北").matchingPlaces(in: places)

        XCTAssertEqual(matches.count, 125)
        XCTAssertEqual(matches.map(\.id), places.map(\.id))
    }

    func testClearResetsDraftAndCommittedFilters() {
        var search = SaveHomeSearch(filters: ["cafe"], draft: "Taipei")
        search.clear()

        XCTAssertEqual(search.filters, [])
        XCTAssertEqual(search.draft, "")
        XCTAssertFalse(search.isActive)
    }

    private func place(
        name: String,
        address: String,
        category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        note: String? = nil,
        vibeTags: [String]? = nil
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: 25.033,
            longitude: 121.5654,
            googlePlaceId: nil,
            category: category,
            status: status,
            rating: nil,
            note: note,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date(),
            vibeTags: vibeTags
        )
    }
}

@MainActor
final class SaveHomeMemorySceneTests: XCTestCase {
    func testOffscreenMatchEntersBoundedSimulationAndRepeatedQueriesKeepNodeIdentity() throws {
        let places = (0..<80).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let scene = SaveHomeMemoryScene()
        let target = places[79]
        let size = CGSize(width: 358, height: 250)
        scene.configure(places: places, liftedIDs: [], size: size, searching: false)
        XCTAssertEqual(scene.visiblePlaces.count, 24)
        XCTAssertNil(scene.childNode(withName: target.id.uuidString))

        scene.configure(places: places, liftedIDs: [target.id], size: size, searching: true)
        let original = try XCTUnwrap(scene.childNode(withName: target.id.uuidString))
        XCTAssertEqual(scene.visiblePlaces.count, 25)
        XCTAssertFalse(try XCTUnwrap(original.physicsBody).isDynamic)
        XCTAssertNotNil(original.action(forKey: "lift"))

        scene.configure(places: places, liftedIDs: [], size: size, searching: true)
        XCTAssertTrue(original === scene.childNode(withName: target.id.uuidString))
        XCTAssertNotNil(original.action(forKey: "lift"), "Returning a preview schedules its drop.")
        scene.configure(places: places, liftedIDs: [target.id], size: size, searching: true)
        XCTAssertTrue(original === scene.childNode(withName: target.id.uuidString))
        XCTAssertFalse(try XCTUnwrap(original.physicsBody).isDynamic)
        XCTAssertEqual(original.physicsBody?.collisionBitMask, 0)
        XCTAssertTrue(scene.poses[target.id]?.lifted == true)
        scene.pause()
        XCTAssertFalse(scene.isAnimating)
    }

    func testDeletedPlaceCannotRemainInPileAndConfigurationWakesAPausedScene() {
        let place = Place(id: UUID(), name: "Memory", address: "Taipei", latitude: 25, longitude: 121,
                          category: .cafe, status: .visited, sourcePlatform: .other, createdAt: Date())
        let scene = SaveHomeMemoryScene()
        scene.configure(places: [place], liftedIDs: [place.id], size: CGSize(width: 358, height: 250), searching: true)
        scene.pause()
        scene.configure(places: [], liftedIDs: [place.id], size: CGSize(width: 358, height: 250), searching: true)
        XCTAssertTrue(scene.isAnimating)
        XCTAssertTrue(scene.visiblePlaces.isEmpty)
        XCTAssertTrue(scene.poses.isEmpty)
        XCTAssertNil(scene.childNode(withName: place.id.uuidString))
        scene.pause()
    }
}
