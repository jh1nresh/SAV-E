import XCTest

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
