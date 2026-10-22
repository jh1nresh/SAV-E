import XCTest
@testable import SAVE

@MainActor
final class PendingShareStoreTests: XCTestCase {
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: "pendingShare.tests.\(UUID().uuidString)")
        store.removePersistentDomain(forName: store.dictionaryRepresentation().keys.joined())
    }

    override func tearDown() {
        PendingShareStore.clear(store)
        store = nil
        super.tearDown()
    }

    func testWriteLoadAndClearRoundTrip() throws {
        let payload = PendingSharePayload(
            kind: .place,
            shareCode: "AbC123_x",
            placeId: "quarter-sheets-pizza-club",
            listId: nil,
            sender: "Mina",
            url: "https://sav-e-app.vercel.app/p/AbC123_x"
        )
        PendingShareStore.write(payload, to: store)
        XCTAssertEqual(PendingShareStore.load(from: store), payload)
        XCTAssertEqual(PendingShareStore.loadURL(from: store)?.absoluteString, payload.url)
        PendingShareStore.clear(store)
        XCTAssertNil(PendingShareStore.load(from: store))
        XCTAssertNil(PendingShareStore.loadURL(from: store))
    }

    func testLegacyURLFallbackWhenPendingShareMissing() throws {
        store.set("https://sav-e-app.vercel.app/p/AbC123_x", forKey: PendingShareStore.legacyURLKey)
        XCTAssertNil(PendingShareStore.load(from: store))
        XCTAssertEqual(
            PendingShareStore.loadURL(from: store)?.absoluteString,
            "https://sav-e-app.vercel.app/p/AbC123_x"
        )
        PendingShareStore.clear(store)
        XCTAssertNil(store.string(forKey: PendingShareStore.legacyURLKey))
    }

    func testPlaceJournalMatchesIncomingURLAndIgnoresUnrelated() {
        let urlA = URL(string: "https://sav-e-app.vercel.app/p/AbC123_x")!
        let urlB = URL(string: "https://sav-e-app.vercel.app/p/ZzOther99")!
        let place = PendingSharePayload(
            kind: .place,
            shareCode: "AbC123_x",
            placeId: "quarter-sheets-pizza-club",
            listId: nil,
            sender: "Mina",
            url: urlA.absoluteString
        )
        let list = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt99_z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: "https://sav-e-app.vercel.app/l/LiSt99_z"
        )
        XCTAssertTrue(place.matchesIncomingPlace(url: urlA))
        XCTAssertTrue(place.matchesIncomingPlace(url: URL(string: "https://sav-e-app.vercel.app/p/AbC123_x/")!))
        XCTAssertFalse(place.matchesIncomingPlace(url: urlB))
        XCTAssertFalse(list.matchesIncomingPlace(url: urlA))
        XCTAssertFalse(list.matchesIncomingPlace(url: URL(string: "https://sav-e-app.vercel.app/l/LiSt99_z")!))
        let leftoverTrip = PendingSharePayload(
            kind: .place,
            shareCode: nil,
            placeId: nil,
            listId: nil,
            sender: nil,
            url: "savvy://trip"
        )
        XCTAssertFalse(leftoverTrip.matchesIncomingPlace(url: urlA))
    }

    func testListJournalMatchesIncomingURLAndIgnoresUnrelated() {
        let listURL = URL(string: "https://sav-e-app.vercel.app/list?c=LiSt99_z")!
        let otherURL = URL(string: "https://sav-e-app.vercel.app/list?c=ZzOther99")!
        let list = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt99_z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: listURL.absoluteString
        )
        let place = PendingSharePayload(
            kind: .place,
            shareCode: "AbC123_x",
            placeId: "quarter-sheets",
            listId: nil,
            sender: "Mina",
            url: "https://sav-e-app.vercel.app/p/AbC123_x"
        )
        XCTAssertTrue(list.matchesIncomingList(url: listURL))
        XCTAssertTrue(list.matchesIncomingList(url: URL(string: "https://sav-e-app.vercel.app/list?c=LiSt99_z")!))
        XCTAssertFalse(list.matchesIncomingList(url: otherURL))
        XCTAssertFalse(place.matchesIncomingList(url: listURL))
        XCTAssertTrue(ClipListHandoff.shouldSaveItems(pending: list, incomingURL: listURL))
        XCTAssertFalse(ClipListHandoff.shouldSaveItems(pending: list, incomingURL: otherURL))
        XCTAssertFalse(ClipListHandoff.shouldSaveItems(pending: nil, incomingURL: listURL))
        XCTAssertFalse(ClipListHandoff.shouldSaveItems(pending: place, incomingURL: listURL))
    }

    func testConfirmedListHandoffStampsOriginalFiveAfterOwnerAddAndDelete() {
        let listURL = URL(string: "https://sav-e-app.vercel.app/list?c=LiSt99_z")!
        let confirmed = (1...5).map { index in
            PendingConfirmedPlace(
                placeId: "shop-\(index)",
                name: "Shop \(index)",
                address: "Tokyo",
                latitude: 35.6 + Double(index) * 0.01,
                longitude: 139.7,
                category: "Cafe",
                sourceURL: nil
            )
        }
        let journal = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt99_z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: listURL.absoluteString,
            confirmedPlaceIds: confirmed.map(\.placeId),
            confirmedPlaces: confirmed
        )
        PendingShareStore.write(journal, to: store)
        let loaded = PendingShareStore.load(from: store)
        XCTAssertEqual(loaded?.confirmedPlaceIds, ["shop-1", "shop-2", "shop-3", "shop-4", "shop-5"])

        let liveAfterOwnerEdit = [
            confirmed[0],
            confirmed[1],
            confirmed[2],
            confirmed[3],
            PendingConfirmedPlace(
                placeId: "shop-6",
                name: "Owner Added",
                address: "Tokyo",
                latitude: 35.65,
                longitude: 139.71,
                category: "Cafe",
                sourceURL: nil
            ),
        ].map { $0.asListItem() }
        let stamped = ClipListHandoff.itemsToStamp(
            pending: loaded,
            incomingURL: listURL,
            liveItems: liveAfterOwnerEdit
        )
        XCTAssertEqual(stamped.map(\.sourceID), ["shop-1", "shop-2", "shop-3", "shop-4", "shop-5"])
        XCTAssertFalse(stamped.contains(where: { $0.sourceID == "shop-6" }))
        XCTAssertTrue(stamped.contains(where: { $0.sourceID == "shop-5" }))
        XCTAssertEqual(stamped.count, 5)
        XCTAssertTrue(ClipListHandoff.itemsToStamp(
            pending: loaded,
            incomingURL: URL(string: "https://sav-e-app.vercel.app/list?c=other")!,
            liveItems: liveAfterOwnerEdit
        ).isEmpty)

        let stampedWithoutJoin = ClipListHandoff.stampList(
            pending: loaded,
            incomingURL: listURL,
            joined: nil
        )
        XCTAssertEqual(stampedWithoutJoin?.items.map(\.sourceID), ["shop-1", "shop-2", "shop-3", "shop-4", "shop-5"])
        XCTAssertEqual(stampedWithoutJoin?.id, UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        XCTAssertNil(ClipListHandoff.stampList(
            pending: loaded,
            incomingURL: URL(string: "https://sav-e-app.vercel.app/list?c=other")!,
            joined: nil
        ))
    }

    func testQuotaAwareHandoffSavesFirstTwoOfFiveNearCap() {
        let confirmed = (1...5).map { index in
            PendingConfirmedPlace(
                placeId: "novel-\(index)",
                name: "Novel \(index)",
                address: "Tokyo",
                latitude: 35.6 + Double(index) * 0.01,
                longitude: 139.7,
                category: "Cafe",
                sourceURL: nil
            ).asListItem()
        }
        let planned = ClipListHandoff.planStamps(
            confirmed: confirmed,
            alreadySaved: { _ in false },
            savedPlaceCount: 48
        )
        XCTAssertEqual(planned.counts.newlySaved, 2)
        XCTAssertEqual(planned.counts.alreadySaved, 0)
        XCTAssertEqual(planned.counts.overCap, 3)
        XCTAssertEqual(planned.counts.remaining, 0)
        XCTAssertEqual(planned.counts.limit, 50)
        XCTAssertEqual(planned.toStamp.map(\.sourceID), ["novel-1", "novel-2"])
        XCTAssertEqual(
            ClipListHandoff.toastEnglish(counts: planned.counts, confirmedCount: 5),
            "Saved 2 of 5. 3 over the free 50."
        )
    }

    func testRemoteHandoffStampsServerRowsNotStaleLocalPrefix() {
        let confirmed = (1...5).map { index in
            PendingConfirmedPlace(
                placeId: "shop-\(index)",
                name: "Shop \(index)",
                address: "Tokyo",
                latitude: 35.6 + Double(index) * 0.01,
                longitude: 139.7,
                category: "Cafe",
                sourceURL: nil
            ).asListItem()
        }
        let id2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let id3 = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let rows = [
            ClipListHandoff.SavedRow(
                id: id2,
                providerPlaceId: "shop-2",
                name: "Shop 2",
                latitude: 35.62,
                longitude: 139.7
            ),
            ClipListHandoff.SavedRow(
                id: id3,
                providerPlaceId: "shop-3",
                name: "Shop 3",
                latitude: 35.63,
                longitude: 139.7
            ),
        ]
        let stamped = ClipListHandoff.placesFromRemoteRows(confirmed: confirmed, rows: rows)
        XCTAssertEqual(stamped?.map(\.id), [id2, id3])
        XCTAssertEqual(stamped?.map(\.name), ["Shop 2", "Shop 3"])
        XCTAssertEqual(stamped?.map(\.providerPlaceId), ["shop-2", "shop-3"])
        XCTAssertFalse(stamped?.contains(where: { $0.name == "Shop 1" }) == true)

        let missingRows = Data(#"{"newly_saved":2,"already_saved":0,"over_cap":3,"remaining":0,"limit":50}"#.utf8)
        XCTAssertNil(ClipListHandoff.parseRemote(status: 201, data: missingRows))
        let payload = Data(#"""
        {"newly_saved":2,"already_saved":1,"over_cap":2,"remaining":0,"limit":50,"saved":[{"id":"22222222-2222-2222-2222-222222222222","provider_place_id":"shop-2","name":"Shop 2","latitude":35.62,"longitude":139.7},{"id":"33333333-3333-3333-3333-333333333333","provider_place_id":"shop-3","name":"Shop 3","latitude":35.63,"longitude":139.7}]}
        """#.utf8)
        let remote = ClipListHandoff.parseRemote(status: 201, data: payload)
        XCTAssertEqual(remote?.counts.newlySaved, 2)
        XCTAssertEqual(remote?.saved.map(\.id), [id2, id3])
        XCTAssertNil(ClipListHandoff.placesFromRemoteRows(
            confirmed: Array(confirmed.prefix(1)),
            rows: rows
        ))
    }

    func testRemoteFailureDoesNotReportListHandoffSuccess() {
        let threeCounts = Data(#"{"newly_saved":5,"already_saved":0,"over_cap":0}"#.utf8)
        XCTAssertNil(ClipListHandoff.parseCounts(status: 500, data: threeCounts))
        XCTAssertNil(ClipListHandoff.parseCounts(status: 201, data: Data(#"{"outcome":"saved"}"#.utf8)))
        XCTAssertNil(ClipListHandoff.parseCounts(
            status: 201,
            data: Data(#"{"newly_saved":2,"already_saved":0}"#.utf8)
        ))
        let ok = ClipListHandoff.parseCounts(
            status: 201,
            data: Data(#"{"newly_saved":2,"already_saved":0,"over_cap":3,"remaining":0,"limit":50}"#.utf8)
        )
        XCTAssertEqual(ok?.newlySaved, 2)
        XCTAssertEqual(ok?.overCap, 3)
        XCTAssertFalse(
            ClipListHandoff.toastEnglish(
                counts: ClipListHandoffCounts(
                    newlySaved: 0,
                    alreadySaved: 0,
                    overCap: 0,
                    remaining: 0,
                    limit: 50
                ),
                confirmedCount: 5
            ).contains("Saved 5")
        )
    }

    func testOversizedListJournalWriteFailsClosed() throws {
        let blob = String(repeating: "x", count: 900)
        let places = (0..<80).map { index in
            PendingConfirmedPlace(
                placeId: "shop-\(index)",
                name: blob,
                address: blob,
                latitude: 35.6,
                longitude: 139.7,
                category: "Cafe",
                sourceURL: blob
            )
        }
        let oversized = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt99_z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: "https://sav-e-app.vercel.app/list?c=LiSt99_z",
            confirmedPlaceIds: places.map(\.placeId),
            confirmedPlaces: places
        )
        XCTAssertGreaterThan(
            try JSONEncoder().encode(oversized).count,
            PendingShareStore.journalByteLimit
        )
        let small = PendingSharePayload(
            kind: .list,
            shareCode: "ok",
            placeId: nil,
            listId: nil,
            sender: nil,
            url: "https://sav-e-app.vercel.app/list?c=ok"
        )
        XCTAssertTrue(PendingShareStore.write(small, to: store))
        XCTAssertFalse(PendingShareStore.write(oversized, to: store))
        XCTAssertEqual(PendingShareStore.load(from: store)?.shareCode, "ok")
    }

    func testHandoffSnapshotRestoresCafeBarStayCategories() {
        XCTAssertEqual(PlaceCategory.fromClipSnapshot("Cafe"), .cafe)
        XCTAssertEqual(PlaceCategory.fromClipSnapshot("Bar"), .bar)
        XCTAssertEqual(PlaceCategory.fromClipSnapshot("Stay"), .stay)
        XCTAssertEqual(PlaceCategory.fromClipSnapshot("hotel"), .stay)
        XCTAssertNotEqual(PlaceCategory.fromClipSnapshot("Cafe"), .food)
        XCTAssertNotEqual(PlaceCategory.fromClipSnapshot("Bar"), .food)
        XCTAssertNotEqual(PlaceCategory.fromClipSnapshot("Stay"), .food)
        let cafe = PendingConfirmedPlace(
            placeId: "c1",
            name: "Onibus",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil
        ).asListItem()
        XCTAssertEqual(cafe.category, .cafe)
        XCTAssertEqual(cafe.asPlace(includeSenderMemory: false).category, .cafe)
        let bar = PendingConfirmedPlace(
            placeId: "b1",
            name: "Blind Rabbit",
            address: "Anaheim",
            latitude: 33.83,
            longitude: -117.91,
            category: "Bar",
            sourceURL: nil
        ).asListItem()
        XCTAssertEqual(bar.asPlace(includeSenderMemory: false).category, .bar)
    }

    func testOversizedListURLIsAcceptedWhenJournalMatches() {
        let blob = String(repeating: "A", count: 9000)
        let oversized = URL(string: "https://sav-e-app.vercel.app/list?d=\(blob)&c=LiSt99_z")!
        XCTAssertGreaterThan(oversized.absoluteString.utf8.count, ClipListHandoff.listURLMaxBytes)
        let journal = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt99_z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: oversized.absoluteString
        )
        let accepted = ClipListHandoff.acceptedListURL(pending: journal, incomingURL: oversized)
        XCTAssertEqual(accepted?.absoluteString, "https://sav-e-app.vercel.app/list?c=LiSt99_z")
        XCTAssertNil(ClipListHandoff.acceptedListURL(pending: nil, incomingURL: oversized))
        XCTAssertNil(ClipListHandoff.acceptedListURL(
            pending: PendingSharePayload(
                kind: .list,
                shareCode: "other99",
                placeId: nil,
                listId: nil,
                sender: nil,
                url: "https://sav-e-app.vercel.app/list?c=other99"
            ),
            incomingURL: oversized
        ))
        let small = URL(string: "https://sav-e-app.vercel.app/list?c=LiSt99_z")!
        XCTAssertEqual(ClipListHandoff.acceptedListURL(pending: nil, incomingURL: small), small)
    }

    func testUnrelatedPlaceLinkDoesNotInheritAutoSave() {
        let urlA = URL(string: "https://sav-e-app.vercel.app/p/AbC123_x")!
        let urlB = URL(string: "https://sav-e-app.vercel.app/p/ZzOther99")!
        let journal = PendingSharePayload(
            kind: .place,
            shareCode: "AbC123_x",
            placeId: "quarter-sheets",
            listId: nil,
            sender: "Mina",
            url: urlA.absoluteString
        )
        XCTAssertTrue(ClipPlaceHandoff.shouldAutoSavePlace(pending: journal, incomingURL: urlA))
        XCTAssertFalse(ClipPlaceHandoff.shouldAutoSavePlace(pending: journal, incomingURL: urlB))
        XCTAssertFalse(ClipPlaceHandoff.shouldAutoSavePlace(pending: nil, incomingURL: urlB))
    }

    func testListPayloadKeepsShareCodeAndListId() {
        let payload = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt99_z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: "savvy://list?c=LiSt99_z"
        )
        PendingShareStore.write(payload, to: store)
        XCTAssertEqual(PendingShareStore.load(from: store)?.kind, .list)
        XCTAssertEqual(PendingShareStore.load(from: store)?.listId, payload.listId)
        XCTAssertEqual(PendingShareStore.load(from: store)?.shareCode, "LiSt99_z")
    }
}
