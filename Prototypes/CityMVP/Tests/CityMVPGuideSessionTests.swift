import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPGuideSessionTests: XCTestCase {
    private func place(_ id: UUID, name: String = "原始地點", note: String = "Private fixture") -> Place {
        Place(id: id, name: name, address: "Fixture address", latitude: 25.034, longitude: 121.564,
              category: .cafe, status: .wantToGo, note: note, sourcePlatform: .other,
              createdAt: Date(timeIntervalSince1970: 0))
    }

    func testHandoffResolvesLatestExactSaveWithoutChangingItsMemory() throws {
        let id = UUID(), other = UUID()
        let session = CityMVPGuideSession(authGeneration: 3, mapGeneration: 4)
        let current = place(id, name: "Updated 原店名", note: "User-owned text")
        let result = try XCTUnwrap(session.resolve(placeID: id, currentAuthGeneration: 3,
            currentMapGeneration: 4, places: [place(other), current]))
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.name, current.name)
        XCTAssertEqual(result.note, current.note)
        XCTAssertEqual(result.status, .wantToGo)
    }

    func testReceiptAlreadyPresentRejectsGuideBeforeRequestingPresentation() {
        let id = UUID(), session = CityMVPGuideSession(authGeneration: 3, mapGeneration: 4)
        XCTAssertNil(session.resolve(placeID: id, currentAuthGeneration: 3,
            currentMapGeneration: 4, hasIncomingReceipt: true, places: [place(id)]))
    }

    func testQueuedSelectionCannotCrossEitherSessionBoundary() {
        let id = UUID(), session = CityMVPGuideSession(authGeneration: 3, mapGeneration: 4)
        for (auth, map) in [(5, 4), (3, 5), (5, 5)] {
            XCTAssertNil(session.resolve(placeID: id, currentAuthGeneration: auth,
                currentMapGeneration: map, places: [place(id)]))
        }
    }

    func testDeletedSameNamedOrAmbiguousIdentityCannotOpenADifferentSave() {
        let id = UUID(), session = CityMVPGuideSession(authGeneration: 3, mapGeneration: 4)
        for records in [[], [place(UUID())], [place(id), place(id)]] as [[Place]] {
            XCTAssertNil(session.resolve(placeID: id, currentAuthGeneration: 3,
                currentMapGeneration: 4, places: records))
        }
    }
    func testReceiptArrivingDuringDismissalReplacesGuideAndConsumesTheSlot() async {
        enum Presentation: Equatable { case guidePlace, receipt }
        var pending: Presentation?
        let next = await CityMVPChromeResume.next(initial: Presentation.guidePlace,
            latest: { pending }, clear: { pending = nil }, afterYield: { pending = .receipt })
        XCTAssertEqual(next, .receipt)
        XCTAssertNil(pending, "A later receipt must not be left waiting for another dismissal")
    }

    func testDismissalWithoutNewRequestKeepsOriginalHandoff() async {
        var pending: String?
        let next = await CityMVPChromeResume.next(initial: "original-guide-place",
            latest: { pending }, clear: { pending = nil }, afterYield: { })
        XCTAssertEqual(next, "original-guide-place")
        XCTAssertNil(pending)
    }

}
