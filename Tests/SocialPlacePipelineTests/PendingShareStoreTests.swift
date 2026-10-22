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

    func testAccountGenerationChangeClearsPlaceHandoffJournal() {
        XCTAssertTrue(ClipPlaceHandoff.shouldKeepPlaceHandoff(ownerGeneration: 4, currentGeneration: 4))
        XCTAssertFalse(ClipPlaceHandoff.shouldKeepPlaceHandoff(ownerGeneration: 4, currentGeneration: 5))
        XCTAssertFalse(ClipPlaceHandoff.shouldKeepPlaceHandoff(ownerGeneration: nil, currentGeneration: 5))
        XCTAssertFalse(
            ClipPlaceHandoff.shouldResetHandoffOnAccountChange(previousUserId: nil, currentUserId: "user-a"),
            "initial restore must keep an unowned Clip journal"
        )
        XCTAssertFalse(
            ClipPlaceHandoff.shouldResetHandoffOnAccountChange(previousUserId: nil, currentUserId: nil)
        )
        XCTAssertTrue(
            ClipPlaceHandoff.shouldResetHandoffOnAccountChange(previousUserId: "user-a", currentUserId: "user-b")
        )
        XCTAssertTrue(
            ClipPlaceHandoff.shouldResetHandoffOnAccountChange(previousUserId: "user-a", currentUserId: nil)
        )
        XCTAssertFalse(
            ClipPlaceHandoff.shouldResetHandoffOnAccountChange(previousUserId: "user-a", currentUserId: "user-a")
        )
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
            ClipListHandoff.onePlaceImport(counts: ClipListHandoffCounts(
                newlySaved: 0,
                alreadySaved: 0,
                overCap: 1,
                remaining: 0,
                limit: 50
            )),
            .capReached
        )
        XCTAssertEqual(
            ClipListHandoff.onePlaceImport(counts: ClipListHandoff.planStamps(
                confirmed: [confirmed[0]],
                alreadySaved: { _ in false },
                savedPlaceCount: 50
            ).counts),
            .capReached
        )
        XCTAssertEqual(
            ClipListHandoff.onePlaceImport(counts: ClipListHandoffCounts(
                newlySaved: 1,
                alreadySaved: 0,
                overCap: 0,
                remaining: 49,
                limit: 50
            )),
            .saved
        )
        XCTAssertEqual(
            ClipListHandoff.toastEnglish(counts: planned.counts, confirmedCount: 5),
            "Saved 2 of 5. 3 over the free 50."
        )
    }

    func testMixedHandoffStillRefreshesWhenOnlyInsertedRowsAreLocal() {
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
        let insertedOnly = [
            confirmed[0].asPlace(includeSenderMemory: false),
            confirmed[1].asPlace(includeSenderMemory: false),
        ]
        XCTAssertTrue(
            ClipListHandoff.needsPlaceRefresh(
                confirmed: confirmed,
                places: insertedOnly,
                newlySaved: 2,
                alreadySaved: 3
            )
        )
        XCTAssertFalse(
            ClipListHandoff.needsPlaceRefresh(
                confirmed: confirmed,
                places: confirmed.map { $0.asPlace(includeSenderMemory: false) },
                newlySaved: 2,
                alreadySaved: 3
            )
        )
    }

    func testAlreadySavedHandoffUsesCanonicalCacheRow() {
        let item = PendingConfirmedPlace(
            placeId: "ChIJ123",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil
        ).asListItem()
        var snapshot = item.asPlace(includeSenderMemory: false)
        snapshot.note = "sender note"
        snapshot.rating = 5
        let serverID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var canonical = snapshot.rekeyed(to: serverID)
        canonical.note = "my note"
        canonical.rating = 2
        canonical.status = .visited
        let row = ClipListHandoff.SavedRow(
            id: serverID,
            providerPlaceId: "ChIJ123",
            name: "Onibus Coffee",
            latitude: 35.644,
            longitude: 139.699
        )
        let reconstructed = ClipListHandoff.placesFromRemoteRows(confirmed: [item], rows: [row])?.first
        XCTAssertNotEqual(reconstructed?.note, "my note")
        let found = ClipListHandoff.cachedAlreadySavedPlace(
            places: [canonical],
            already: [row],
            fallback: snapshot
        )
        XCTAssertEqual(found?.id, serverID)
        XCTAssertEqual(found?.note, "my note")
        XCTAssertEqual(found?.rating, 2)
        XCTAssertEqual(found?.status, .visited)
        XCTAssertNil(
            ClipListHandoff.cachedAlreadySavedPlace(
                places: [],
                already: [row],
                fallback: snapshot
            ),
            "empty cache must not invent a stamp from the share snapshot"
        )
    }

    func testSameNameDifferentCityDoesNotCountAsVisibleDuplicate() {
        let tokyo = PendingConfirmedPlace(
            placeId: "shop-tokyo",
            name: "Starbucks",
            address: "Tokyo",
            latitude: 35.68,
            longitude: 139.76,
            category: "Cafe",
            sourceURL: nil
        ).asListItem()
        var seattle = tokyo.asPlace(includeSenderMemory: false)
        seattle.latitude = 47.61
        seattle.longitude = -122.33
        seattle.providerPlaceId = "shop-seattle"
        XCTAssertFalse(tokyo.alreadySaved(in: [seattle]))
        var googleOnly = seattle
        googleOnly.googlePlaceId = "shop-tokyo"
        googleOnly.providerPlaceId = nil
        XCTAssertTrue(tokyo.alreadySaved(in: [googleOnly]))
        XCTAssertTrue(
            ClipListHandoff.needsPlaceRefresh(
                confirmed: [tokyo],
                places: [seattle],
                newlySaved: 0,
                alreadySaved: 1
            )
        )
    }

    func testPlanStampsRecordsSkippedIdentities() {
        let onibus = PendingConfirmedPlace(
            placeId: "",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil
        ).asListItem()
        let onibusWithProvider = PendingConfirmedPlace(
            placeId: "shop-b",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil
        ).asListItem()
        let katsu = PendingConfirmedPlace(
            placeId: "shop-b",
            name: "Katsu Midori",
            address: "Tokyo",
            latitude: 35.67,
            longitude: 139.77,
            category: "Cafe",
            sourceURL: nil
        ).asListItem()
        let planned = ClipListHandoff.planStamps(
            confirmed: [onibus, onibusWithProvider, katsu],
            alreadySaved: { _ in false },
            savedPlaceCount: 0
        )
        XCTAssertEqual(planned.toStamp.map(\.title), ["Onibus Coffee"])
        XCTAssertEqual(planned.counts.alreadySaved, 2)
        XCTAssertEqual(planned.counts.newlySaved, 1)
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
        XCTAssertEqual(remote?.already, [])
        XCTAssertNil(ClipListHandoff.placesFromRemoteRows(
            confirmed: Array(confirmed.prefix(1)),
            rows: rows
        ))
    }

    func testZeroInsertAlreadySavedRowsImportCanonicalIds() {
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
        let ids = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        ]
        let alreadyJSON = (1...5).map { index in
            """
            {"id":"\(ids[index - 1].uuidString)","provider_place_id":"shop-\(index)","name":"Shop \(index)","latitude":\(35.6 + Double(index) * 0.01),"longitude":139.7}
            """
        }.joined(separator: ",")
        let payload = Data(#"""
        {"newly_saved":0,"already_saved":5,"over_cap":0,"remaining":0,"limit":50,"saved":[],"already":[\#(alreadyJSON)]}
        """#.utf8)
        let remote = ClipListHandoff.parseRemote(status: 201, data: payload)
        XCTAssertEqual(remote?.counts.alreadySaved, 5)
        XCTAssertEqual(remote?.saved, [])
        XCTAssertEqual(remote?.already.map(\.id), ids)
        let imported = ClipListHandoff.placesFromRemoteRows(
            confirmed: confirmed,
            rows: (remote?.saved ?? []) + (remote?.already ?? [])
        )
        XCTAssertEqual(imported?.map(\.id), ids)
        XCTAssertEqual(imported?.map(\.name), ["Shop 1", "Shop 2", "Shop 3", "Shop 4", "Shop 5"])

        let staleEmpty = Data(#"{"newly_saved":0,"already_saved":5,"over_cap":0,"remaining":0,"limit":50,"saved":[]}"#.utf8)
        let stale = ClipListHandoff.parseRemote(status: 201, data: staleEmpty)
        XCTAssertEqual(stale?.already, [])
        XCTAssertEqual(
            ClipListHandoff.placesFromRemoteRows(confirmed: confirmed, rows: stale?.saved ?? []),
            []
        )
        XCTAssertNil(ClipListHandoff.parseRemote(
            status: 201,
            data: Data(#"{"newly_saved":0,"already_saved":5,"over_cap":0,"already":[{"name":"Shop 1"}]}"#.utf8)
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

    func testTwoHundredDetailedPlacesFitInTheJournal() throws {
        let address = String(repeating: "a", count: 200)
        let url = String(repeating: "u", count: 80)
        let places = (0..<200).map { index in
            PendingConfirmedPlace(
                placeId: "shop-\(index)",
                name: "Cafe \(index)",
                address: address,
                latitude: 35.6,
                longitude: 139.7,
                category: "Cafe",
                sourceURL: url
            )
        }
        let payload = PendingSharePayload(
            kind: .list,
            shareCode: "LiSt200z",
            placeId: nil,
            listId: "22222222-2222-2222-2222-222222222222",
            sender: "Mina",
            url: "https://sav-e-app.vercel.app/list?c=LiSt200z",
            confirmedPlaces: places
        )
        XCTAssertLessThanOrEqual(
            try JSONEncoder().encode(payload).count,
            PendingShareStore.journalByteLimit
        )
        XCTAssertTrue(PendingShareStore.write(payload, to: store))
        XCTAssertEqual(PendingShareStore.load(from: store)?.confirmedPlaces?.count, 200)
    }

    func testOversizedListJournalWriteFailsClosed() throws {
        let blob = String(repeating: "x", count: 4000)
        let places = (0..<200).map { index in
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

    func testHandoffSnapshotCarriesBridgePlaceIds() {
        let snapshot = PendingConfirmedPlace(
            placeId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil,
            extraPlaceIds: ["ChIJ123"]
        )
        let item = snapshot.asListItem()
        XCTAssertEqual(item.sourceID, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(item.extraPlaceIds, ["ChIJ123"])
        let body = ClipListHandoff.placeBody(from: item)
        XCTAssertEqual(body["provider_place_id"] as? String, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(body["google_place_id"] as? String, "ChIJ123")
        XCTAssertEqual(body["extra_place_ids"] as? [String], ["ChIJ123"])
        let googleOnly = PendingConfirmedPlace(
            placeId: "ChIJ123",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil
        )
        let googleBody = ClipListHandoff.placeBody(from: googleOnly.asListItem())
        XCTAssertEqual(googleBody["provider_place_id"] as? String, "ChIJ123")
        XCTAssertEqual(googleBody["google_place_id"] as? String, "ChIJ123")
        XCTAssertEqual(googleOnly.asListItem().asPlace(includeSenderMemory: false).googlePlaceId, "ChIJ123")
        XCTAssertTrue(ClipListHandoff.isGooglePlaceID("ChIJ123"))
        XCTAssertTrue(ClipListHandoff.isGooglePlaceID("EicABC"))
        XCTAssertTrue(ClipListHandoff.isGooglePlaceID("IhoXYZ"))
        XCTAssertTrue(ClipListHandoff.isGooglePlaceID("eicabc"))
        XCTAssertFalse(ClipListHandoff.isGooglePlaceID("id-c"))
        let aliasOnly = PendingConfirmedPlace(
            placeId: "id-a",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil,
            extraPlaceIds: ["id-c", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]
        )
        let aliasBody = ClipListHandoff.placeBody(from: aliasOnly.asListItem())
        XCTAssertNil(aliasBody["google_place_id"], "ordinary aliases must not become google_place_id")
        XCTAssertEqual(aliasBody["extra_place_ids"] as? [String], ["id-c", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"])
        let encoded = try? JSONEncoder().encode(snapshot)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(PendingConfirmedPlace.self, from: $0) }
        XCTAssertEqual(decoded?.extraPlaceIds, ["ChIJ123"])
        let legacy = PendingConfirmedPlace(
            placeId: "shop-1",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil
        )
        XCTAssertNil(legacy.extraPlaceIds)
        XCTAssertNil(legacy.asListItem().extraPlaceIds)
        let gcj = PendingConfirmedPlace(
            placeId: "amap-onibus",
            name: "Onibus Coffee",
            address: "Tokyo",
            latitude: 35.644,
            longitude: 139.699,
            category: "Cafe",
            sourceURL: nil,
            coordinateSystem: "GCJ-02",
            locationProvider: "amap",
            providerMapUrl: "https://uri.amap.com/marker?position=139.699,35.644"
        )
        let gcjItem = gcj.asListItem()
        XCTAssertEqual(gcjItem.coordinateSystem, .gcj02)
        XCTAssertEqual(gcjItem.locationProvider, .amap)
        XCTAssertFalse(gcjItem.asPlace(includeSenderMemory: false).isMapKitMappable)
        XCTAssertEqual(ClipListHandoff.placeBody(from: gcjItem)["coordinate_system"] as? String, "GCJ-02")
        let gcjEncoded = try? JSONEncoder().encode(gcj)
        let gcjDecoded = gcjEncoded.flatMap { try? JSONDecoder().decode(PendingConfirmedPlace.self, from: $0) }
        XCTAssertEqual(gcjDecoded?.coordinateSystem, "GCJ-02")
        XCTAssertEqual(gcjDecoded?.locationProvider, "amap")
        XCTAssertEqual(gcjDecoded?.providerMapUrl, "https://uri.amap.com/marker?position=139.699,35.644")
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
