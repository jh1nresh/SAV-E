import XCTest
import SpriteKit
import Metal
@testable import SAVE

@MainActor
final class SaveHomeSearchTests: XCTestCase {
    func testConnectorsDoNotConstrainStructuredQueriesButStandaloneTextStillDoes() {
        let quiet = place(name: "Mori", address: "Taipei", category: .cafe, note: "quiet")
        let loud = place(name: "Beat", address: "Taipei", category: .cafe)
        let elsewhere = place(name: "River", address: "Tainan", category: .cafe, note: "quiet")
        let places = [quiet, loud, elsewhere]
        for query in ["quiet cafes in Taipei", "quiet cafes at Taipei"] {
            var search = SaveHomeSearch(draft: query)
            XCTAssertEqual(search.matchingPlaces(in: places).map(\.id), [quiet.id])
            search.commitDraft()
            XCTAssertEqual(Set(search.filters), Set(["cafe", "taipei", "quiet"]))
            XCTAssertEqual(search.matchingPlaces(in: places).map(\.id), [quiet.id])
        }
        let namedIn = place(name: "IN", address: "Paris", category: .shopping)
        XCTAssertEqual(SaveHomeSearch(draft: "in").matchingPlaces(in: [quiet, namedIn]).map(\.id), [namedIn.id])
    }

    func testKyotoDoesNotMatchTheSubstringInsideTokyoMetropolis() {
        let kyoto = place(name: "Window", address: "京都市下京区", category: .cafe)
        let tokyo = place(name: "Kissa", address: "東京都渋谷区", category: .cafe)
        var search = SaveHomeSearch(draft: "京都咖啡店")
        XCTAssertEqual(search.matchingPlaces(in: [tokyo, kyoto]).map(\.id), [kyoto.id])
        search.commitDraft()
        XCTAssertEqual(search.matchingPlaces(in: [tokyo, kyoto]).map(\.id), [kyoto.id])
        for query in ["東京都咖啡店", "东京都咖啡店"] {
            var tokyoSearch = SaveHomeSearch(draft: query)
            XCTAssertEqual(tokyoSearch.matchingPlaces(in: [tokyo, kyoto]).map(\.id), [tokyo.id])
            tokyoSearch.commitDraft()
            XCTAssertEqual(Set(tokyoSearch.filters), Set(["tokyo", "cafe"]))
            XCTAssertEqual(tokyoSearch.matchingPlaces(in: [tokyo, kyoto]).map(\.id), [tokyo.id])
        }
    }

    func testPluralBarsUsesCategoryInsteadOfLiteralName() {
        let bar = place(name: "Nightjar", address: "London", category: .bar)
        let cafe = place(name: "Window", address: "London", category: .cafe)
        var search = SaveHomeSearch(draft: "bars")
        XCTAssertEqual(search.matchingPlaces(in: [bar, cafe]).map(\.id), [bar.id])
        search.commitDraft()
        XCTAssertEqual(search.filters, ["bar"])
        XCTAssertEqual(search.matchingPlaces(in: [bar, cafe]).map(\.id), [bar.id])
    }

    func testHomeKeepsReviewCandidatesSeparateFromSourceClues() {
        func item(status: String, latitude: Double?) -> PlaceReviewCandidate {
            PlaceReviewCandidate(id: UUID(), captureId: nil, name: "Saved clue", address: "Taipei",
                city: "Taipei", latitude: latitude, longitude: latitude == nil ? nil : 121.5,
                evidence: [], confidence: nil, missingInfo: [], status: status, createdAt: Date())
        }
        let counts = SaveHomeReviewCounts([
            item(status: "review", latitude: 25),
            item(status: "source_only", latitude: 25),
            item(status: "review", latitude: nil),
        ])
        XCTAssertEqual(counts.candidates, 1)
        XCTAssertEqual(counts.sources, 2)
        XCTAssertEqual(counts.total, 3)
        XCTAssertEqual(SaveHomeReviewCounts([]).total, 0)
    }

    func testFullTaipeiCityNamesDoNotLeaveResidualTextFilters() {
        for query in ["台北市咖啡店", "臺北市咖啡店", "Taipei City cafes"] {
            var search = SaveHomeSearch(draft: query)
            search.commitDraft()
            XCTAssertEqual(Set(search.filters), Set(["taipei", "cafe"]), query)
        }
    }

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
    func testLiftMovesThroughIntermediatePoseAndDropEvictsOffBudgetPreview() throws {
        let renderer = SKRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()))
        let scene = SaveHomeMemoryScene()
        renderer.scene = scene
        defer { scene.pause(); renderer.scene = nil }
        let places = (0..<49).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let id = places[48].id
        let size = CGSize(width: 358, height: 250)
        let liftedY = size.height - min(74, size.height * 0.22)
        scene.configure(places: places, liftedIDs: [id], size: size, searching: true)
        let start = try XCTUnwrap(scene.poses[id])
        for step in 0...12 { renderer.update(atTime: 100 + Double(step) / 60) }
        let middle = try XCTUnwrap(scene.poses[id])
        XCTAssertGreaterThan(middle.y, start.y)
        XCTAssertLessThan(middle.y, liftedY)
        for step in 13...60 { renderer.update(atTime: 100 + Double(step) / 60) }
        let lifted = try XCTUnwrap(scene.poses[id])
        XCTAssertEqual(lifted.y, liftedY, accuracy: 0.1)
        XCTAssertEqual(lifted.rotation, 0, accuracy: 0.01)
        scene.configure(places: places, liftedIDs: [], size: size, searching: false)
        XCTAssertNotNil(scene.poses[id], "Keep the same preview while it drops.")
        let dropping = try XCTUnwrap(scene.poses[id])
        scene.beginDrag(at: CGPoint(x: dropping.x, y: dropping.y))
        scene.moveDrag(to: CGPoint(x: dropping.x + 30, y: dropping.y - 30))
        scene.endDrag()
        XCTAssertNotNil(scene.childNode(withName: id.uuidString)?.action(forKey: "transition"),
                        "Touching an off-budget returning preview must not cancel its eviction.")
        for step in 61...120 { renderer.update(atTime: 100 + Double(step) / 60) }
        XCTAssertNil(scene.poses[id])
        XCTAssertNil(scene.childNode(withName: id.uuidString))
        XCTAssertEqual(scene.visiblePlaces.count, 48)
    }

    func testOffscreenMatchEntersBoundedSimulationAndRepeatedQueriesKeepNodeIdentity() throws {
        let places = (0..<80).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let scene = SaveHomeMemoryScene()
        let target = places[79]
        let size = CGSize(width: 358, height: 250)
        scene.configure(places: places, liftedIDs: [], size: size, searching: false)
        XCTAssertEqual(scene.visiblePlaces.count, 48)
        XCTAssertNil(scene.childNode(withName: target.id.uuidString))

        scene.configure(places: places, liftedIDs: [target.id], size: size, searching: true)
        let original = try XCTUnwrap(scene.childNode(withName: target.id.uuidString))
        XCTAssertEqual(scene.visiblePlaces.count, 49)
        XCTAssertFalse(try XCTUnwrap(original.physicsBody).isDynamic)
        XCTAssertNotNil(original.action(forKey: "transition"))

        scene.configure(places: places, liftedIDs: [], size: size, searching: true)
        XCTAssertTrue(original === scene.childNode(withName: target.id.uuidString))
        XCTAssertNotNil(original.action(forKey: "transition"), "Returning a preview schedules its drop.")
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

    func testDragReleaseRemainsInWorldAndTapOpensTheExactStamp() throws {
        let places = (0..<6).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let scene = SaveHomeMemoryScene()
        let size = CGSize(width: 402, height: 550)
        scene.configure(places: places, liftedIDs: [], size: size, searching: false)
        let id = places[0].id
        let start = try XCTUnwrap(scene.poses[id])
        XCTAssertEqual(start.scale, 0.95, accuracy: 0.01)

        scene.beginDrag(at: CGPoint(x: start.x, y: start.y))
        scene.moveDrag(to: CGPoint(x: -200, y: 900))
        let moved = try XCTUnwrap(scene.poses[id])
        XCTAssertGreaterThan(moved.x, 0)
        XCTAssertLessThan(moved.x, size.width)
        XCTAssertGreaterThan(moved.y, 0)
        XCTAssertLessThan(moved.y, size.height)
        scene.endDrag()
        XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: id.uuidString)).physicsBody?.isDynamic == true)

        var openedID: UUID?
        var wasRestoredBeforeOpen = false
        let restingNode = try XCTUnwrap(scene.childNode(withName: id.uuidString))
        scene.onOpenPlace = { opened in
            openedID = opened
            wasRestoredBeforeOpen = restingNode.physicsBody?.isDynamic == true && restingNode.zPosition == 0
        }
        let released = try XCTUnwrap(scene.poses[id])
        scene.beginDrag(at: CGPoint(x: released.x, y: released.y))
        scene.endDrag()
        XCTAssertEqual(openedID, id)
        XCTAssertTrue(wasRestoredBeforeOpen, "A resting tap restores its body and pile depth before navigation.")

        openedID = nil
        scene.configure(places: places, liftedIDs: [id], size: size, searching: true)
        let liftedStart = try XCTUnwrap(scene.poses[id])
        scene.beginDrag(at: CGPoint(x: liftedStart.x, y: liftedStart.y))
        scene.endDrag()
        XCTAssertEqual(openedID, id, "A lifted stamp still opens its exact saved place.")
        scene.pause()
    }

    func testCancelledAndLiftedSwipeInteractionsNeverOpenOrFreezeStamps() throws {
        let places = (0..<3).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let scene = SaveHomeMemoryScene()
        let size = CGSize(width: 402, height: 550)
        var openedID: UUID?
        scene.onOpenPlace = { openedID = $0 }
        scene.configure(places: places, liftedIDs: [], size: size, searching: false)

        let restingID = places[0].id
        let restingPose = try XCTUnwrap(scene.poses[restingID])
        scene.beginDrag(at: CGPoint(x: restingPose.x, y: restingPose.y))
        XCTAssertFalse(try XCTUnwrap(scene.childNode(withName: restingID.uuidString)).physicsBody?.isDynamic == true)
        scene.cancelInteraction()
        XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: restingID.uuidString)).physicsBody?.isDynamic == true)
        scene.endDrag()
        XCTAssertNil(openedID)

        let liftedID = places[1].id
        scene.configure(places: places, liftedIDs: [liftedID], size: size, searching: true)
        let liftedPose = try XCTUnwrap(scene.poses[liftedID])
        scene.beginDrag(at: CGPoint(x: liftedPose.x, y: liftedPose.y))
        scene.moveDrag(to: CGPoint(x: liftedPose.x + 18, y: liftedPose.y))
        scene.endDrag()
        XCTAssertNil(openedID, "A lifted swipe is not a detail tap.")

        let pausePose = try XCTUnwrap(scene.poses[restingID])
        scene.beginDrag(at: CGPoint(x: pausePose.x, y: pausePose.y))
        scene.pause()
        XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: restingID.uuidString)).physicsBody?.isDynamic == true)
        scene.endDrag()
        XCTAssertNil(openedID, "Inactive/offscreen cleanup cannot navigate.")
    }

    func testRotatedOverlappingStampHitUsesHighestVisibleExactID() throws {
        let places = (0..<2).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let scene = SaveHomeMemoryScene()
        scene.configure(places: places, liftedIDs: [], size: CGSize(width: 402, height: 550), searching: false)
        let lower = try XCTUnwrap(scene.childNode(withName: places[0].id.uuidString))
        let upper = try XCTUnwrap(scene.childNode(withName: places[1].id.uuidString))
        lower.position = CGPoint(x: 201, y: 220)
        lower.zRotation = .pi / 4
        lower.zPosition = 1
        upper.position = CGPoint(x: 201, y: 220)
        upper.zRotation = -.pi / 5
        upper.zPosition = 2

        var openedID: UUID?
        scene.onOpenPlace = { openedID = $0 }
        let transformedPoint = upper.convert(CGPoint(x: 38, y: 0), to: scene)
        scene.beginDrag(at: transformedPoint)
        scene.endDrag()
        XCTAssertEqual(openedID, places[1].id)
        scene.pause()
    }

    func testResizeAndQueryReseatNonmatchingRestingStampBelowComposer() throws {
        let places = (0..<4).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let scene = SaveHomeMemoryScene()
        let fullSize = CGSize(width: 402, height: 550)
        let keyboardSize = CGSize(width: 402, height: 250)
        scene.configure(places: places, liftedIDs: [], size: fullSize, searching: false)

        let nonmatchingID = places[3].id
        let staleNode = try XCTUnwrap(scene.childNode(withName: nonmatchingID.uuidString))
        staleNode.position = CGPoint(x: 201, y: fullSize.height - 36)
        staleNode.physicsBody?.velocity = CGVector(dx: 40, dy: 80)

        scene.configure(places: places, liftedIDs: Array(places.prefix(3).map(\.id)), size: keyboardSize, searching: true)
        let reflowed = try XCTUnwrap(scene.poses[nonmatchingID])
        XCTAssertLessThanOrEqual(reflowed.y, keyboardSize.height * 0.42)
        XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: nonmatchingID.uuidString)).physicsBody?.isDynamic == true)
        XCTAssertEqual(try XCTUnwrap(scene.childNode(withName: nonmatchingID.uuidString)).physicsBody?.velocity.dx, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(scene.childNode(withName: nonmatchingID.uuidString)).physicsBody?.velocity.dy, 0, accuracy: 0.001)
        scene.pause()
    }

    func testLargeCollectionSettlesBelowTheSearchArea() throws {
        let renderer = SKRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()))
        let scene = SaveHomeMemoryScene()
        renderer.scene = scene
        defer { scene.pause(); renderer.scene = nil }
        let places = (0..<85).map { index in
            Place(id: UUID(), name: "Memory \(index)", address: "Taipei", latitude: 25, longitude: 121,
                  category: .cafe, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        let size = CGSize(width: 402, height: 540)
        scene.configure(places: places, liftedIDs: [], size: size, searching: false)
        for step in 0...600 { renderer.update(atTime: 100 + Double(step) / 60) }
        XCTAssertEqual(scene.visiblePlaces.count, 48)
        XCTAssertEqual(Set(scene.visiblePlaces.map(\.id)).count, 48)
        XCTAssertTrue(scene.poses.values.allSatisfy { $0.y < size.height / 2 },
                      "A large resting collection must not occupy the retrieval area above search.")
        XCTAssertFalse(scene.isAnimating, "The dense resting pile must still settle and pause.")
    }

}
