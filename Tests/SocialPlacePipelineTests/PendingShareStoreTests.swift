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
