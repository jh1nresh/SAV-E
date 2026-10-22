import XCTest

final class ClipListSaveTests: XCTestCase {
    func testSL1OneRequestBodyDedupeFirst() {
        let items = [
            item("a", "Onibus Coffee", lat: 35.644, lng: 139.699),
            item("a", "Onibus Coffee", lat: 35.644, lng: 139.699),
            item("b", "Katsu Midori", lat: 35.690, lng: 139.700),
            item(nil, "Onibus Coffee", lat: 35.644, lng: 139.699),
        ]
        let unique = ClipListSavePlanner.uniqueItems(from: items)
        XCTAssertEqual(unique.map(\.placeId), ["a", "b"])

        let body = ClipListSavePlanner.requestBody(items: items)
        let places = body["places"] as? [[String: Any]]
        XCTAssertEqual(places?.count, 2)
        XCTAssertEqual(places?.compactMap { $0["provider_place_id"] as? String }, ["a", "b"])
        XCTAssertEqual(body.keys.sorted(), ["places"], "SL1: one POST /places payload")
    }

    func testSL2OverflowUsesListOrderAndRemainingQuota() {
        let counts = ClipListSavePlanner.allocate(
            novelCount: 4,
            alreadySaved: 1,
            savedPlaceCount: 48
        )
        XCTAssertEqual(counts.newlySaved, 2)
        XCTAssertEqual(counts.alreadySaved, 1)
        XCTAssertEqual(counts.overCap, 2)
        XCTAssertEqual(counts.remaining, 0)
        XCTAssertEqual(counts.limit, 50)
    }

    func testSL2FullAccountStopsAtCap() {
        let counts = ClipListSavePlanner.allocate(
            novelCount: 5,
            alreadySaved: 0,
            savedPlaceCount: 50
        )
        XCTAssertEqual(counts.newlySaved, 0)
        XCTAssertEqual(counts.overCap, 5)
        XCTAssertEqual(counts.remaining, 0)
        XCTAssertFalse(counts.addedAnything)
    }

    func testSL3RequiresThreeRealCounts() {
        let ok = ClipListSavePlanner.parseCounts(
            status: 201,
            body: [
                "newly_saved": 3,
                "already_saved": 1,
                "over_cap": 1,
                "remaining": 12,
                "limit": 50,
            ]
        )
        XCTAssertEqual(ok, ClipListSaveCounts(newlySaved: 3, alreadySaved: 1, overCap: 1, remaining: 12, limit: 50))

        XCTAssertNil(
            ClipListSavePlanner.parseCounts(status: 201, body: ["outcome": "saved"]),
            "a 2xx without the three counts is not a list success"
        )
        XCTAssertNil(
            ClipListSavePlanner.parseCounts(
                status: 201,
                body: ["newly_saved": 3, "already_saved": 1]
            )
        )
    }

    func testSL4NetworkOrIncompleteResponseIsNotSilentSuccess() {
        XCTAssertNil(ClipListSavePlanner.parseCounts(status: 500, body: [
            "newly_saved": 2,
            "already_saved": 0,
            "over_cap": 0,
        ]))
        XCTAssertNil(ClipListSavePlanner.parseCounts(status: 0, body: [:]))

        let data = Data(#"{"newly_saved":1,"already_saved":2,"over_cap":3,"remaining":0}"#.utf8)
        XCTAssertEqual(
            ClipListSavePlanner.parseOutcome(status: 201, data: data),
            .success(ClipListSaveCounts(newlySaved: 1, alreadySaved: 2, overCap: 3, remaining: 0, limit: 50))
        )
        XCTAssertEqual(ClipListSavePlanner.parseOutcome(status: 500, data: data), .failure(.unconfirmed))
        XCTAssertEqual(ClipListSavePlanner.parseOutcome(status: 200, data: Data("{}".utf8)), .failure(.unconfirmed))
        let asError: Error = ClipListSaveFailure.unconfirmed
        XCTAssertEqual((asError as? ClipListSaveFailure), .unconfirmed)
    }

    func testSL6SwipeHintOnlyOnFirstPageUntilDismissed() {
        XCTAssertTrue(ClipListSwipeHint.shouldShow(pageIndex: 0, pageCount: 5, dismissed: false))
        XCTAssertFalse(ClipListSwipeHint.shouldShow(pageIndex: 1, pageCount: 5, dismissed: false))
        XCTAssertFalse(ClipListSwipeHint.shouldShow(pageIndex: 0, pageCount: 1, dismissed: false))
        XCTAssertFalse(ClipListSwipeHint.shouldShow(pageIndex: 0, pageCount: 5, dismissed: true))
    }

    func testSL6SwipeHintPersistsDismissFlag() {
        let suite = "clip.list.swipe.test.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)
        defer { store?.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ClipListSwipeHint.suiteName, "group.com.wanderly.app")
        XCTAssertFalse(ClipListSwipeHint.isDismissed(in: store))
        ClipListSwipeHint.dismiss(in: store)
        XCTAssertTrue(ClipListSwipeHint.isDismissed(in: store))
        XCTAssertFalse(ClipListSwipeHint.shouldShow(pageIndex: 0, pageCount: 5, dismissed: ClipListSwipeHint.isDismissed(in: store)))
        ClipListSwipeHint.reset(in: store)
        XCTAssertFalse(ClipListSwipeHint.isDismissed(in: store))
    }

    func testLS4SignInCopyUsesOneLayoutAndTwoTitles() {
        XCTAssertEqual(ClipSignInKind.onePlace.titleKey, "clip.signin.saveOne")
        XCTAssertEqual(ClipSignInKind.wholeList(5).titleKey, "clip.signin.saveCount")
        XCTAssertEqual(ClipSignInKind.onePlace.placeCount, 1)
        XCTAssertEqual(ClipSignInKind.wholeList(5).placeCount, 5)
        XCTAssertNotEqual(ClipSignInKind.onePlace.titleKey, ClipSignInKind.wholeList(5).titleKey)
    }

    func testRecipientPlaceBodyOmitsSenderNoteAndRating() {
        let item = ClipListSaveItem(
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            rating: 4.6,
            note: "Mina's late-night pick",
            placeId: "source-owner-id"
        )
        let body = ClipListSavePlanner.placeBody(from: item)
        XCTAssertNil(body["note"])
        XCTAssertNil(body["rating"])
        XCTAssertEqual(body["provider_place_id"] as? String, "source-owner-id")
        XCTAssertEqual(body["name"] as? String, "Onibus Coffee")
    }

    func testRecipientOwnedPlaceIDDoesNotReuseSourceUUID() {
        let sourceId = UUID().uuidString
        let items = [item(sourceId, "Onibus Coffee", lat: 35.644, lng: 139.699)]
        let places = ClipListSavePlanner.requestBody(items: items)["places"] as? [[String: Any]]
        let id = places?.first?["id"] as? String
        XCTAssertNotNil(UUID(uuidString: id ?? ""))
        XCTAssertNotEqual(id?.lowercased(), sourceId.lowercased())
        XCTAssertEqual(places?.first?["provider_place_id"] as? String, sourceId)
        let again = ClipListSavePlanner.requestBody(items: items)["places"] as? [[String: Any]]
        XCTAssertNotEqual(again?.first?["id"] as? String, id)
    }

    func testListSignInUsesTappedDraftNotStaleListPage() {
        let page0 = item("page0", "Onibus Coffee", lat: 35.644, lng: 139.699)
        let page2 = item("page2", "Katsu Midori", lat: 35.690, lng: 139.700)
        XCTAssertEqual(
            ClipListSavePlanner.onePlaceItem(pending: page2, pageItem: page0)?.placeId,
            "page2",
            "SIWA must save the tapped shop even if listPage drifted to 0"
        )
        XCTAssertNotEqual(
            ClipListSavePlanner.onePlaceItem(pending: page2, pageItem: page0)?.placeId,
            page0.placeId
        )
        XCTAssertEqual(
            ClipListSavePlanner.onePlaceItem(pending: nil, pageItem: page0)?.placeId,
            "page0"
        )
        XCTAssertNil(ClipListSavePlanner.onePlaceItem(pending: nil, pageItem: nil))
        XCTAssertEqual(ClipListSavePlanner.visiblePage(current: 2, incoming: nil), 2)
        XCTAssertEqual(ClipListSavePlanner.visiblePage(current: 2, incoming: 3), 3)
        XCTAssertEqual(ClipListSavePlanner.visiblePage(current: 0, incoming: 0), 0)
    }

    func testSL5AlreadySavedPlacesCountOnce() {
        let items = [
            item("place1", "Onibus Coffee", lat: 35.644, lng: 139.699),
            item("PLACE1", "Onibus Coffee", lat: 35.644, lng: 139.699),
        ]
        XCTAssertEqual(ClipListSavePlanner.uniqueItems(from: items).count, 1)
        XCTAssertEqual(
            ClipListSavePlanner.identity(of: items[0]),
            ClipListSavePlanner.identity(of: items[1])
        )
    }

    private func item(
        _ placeId: String?,
        _ name: String,
        lat: Double,
        lng: Double
    ) -> ClipListSaveItem {
        ClipListSaveItem(
            name: name,
            address: "Tokyo",
            latitude: lat,
            longitude: lng,
            category: "Cafe",
            placeId: placeId
        )
    }
}
