import XCTest
@testable import SAVE

final class SaveIncomingShareTests: XCTestCase {
    @MainActor
    func testIncomingShareRequiresTheSameVerifiedAccountAndGeneration() {
        let displayed = SaveIncomingShareSession(owner: "account-a", generation: 7)
        XCTAssertFalse(displayed.accepts(nil), "Sign-in or account verification is not confirmation.")
        XCTAssertTrue(displayed.accepts(.init(owner: "account-a", generation: 7)))
        XCTAssertFalse(displayed.accepts(.init(owner: "account-b", generation: 7)))
        XCTAssertFalse(displayed.accepts(.init(owner: "account-a", generation: 8)))
        XCTAssertFalse(SaveIncomingShareSession(owner: "", generation: 7).accepts(.init(owner: "", generation: 7)))
    }

    @MainActor
    func testIncomingShareDoesNotSendProviderCoordinatesToAppleMaps() {
        var payload = placePayload()
        XCTAssertTrue(payload.supportsIncomingShareLocationReference)
        XCTAssertEqual(payload.incomingShareMapURL?.host, "maps.apple.com")
        payload.coordinateSystem = PlaceCoordinateSystem.wgs84.rawValue
        XCTAssertEqual(payload.incomingShareMapURL?.host, "maps.apple.com")
        payload.coordinateSystem = PlaceCoordinateSystem.gcj02.rawValue
        payload.locationProvider = PlaceMatchProvider.amap.rawValue
        payload.providerMapUrl = "https://uri.amap.com/marker?position=121.5654,25.033"
        XCTAssertTrue(payload.supportsIncomingShareLocationReference)
        XCTAssertEqual(payload.incomingShareMapURL?.host, "uri.amap.com")
        payload.providerMapUrl = nil
        XCTAssertNil(payload.incomingShareMapURL, "A missing provider handoff must not fall back to a false Apple point.")
    }

    @MainActor
    func testUnknownReferencesAndUnsafeProviderLinksStayUnavailable() {
        var payload = placePayload()
        payload.coordinateSystem = "unsupported-reference"
        XCTAssertFalse(payload.supportsIncomingShareLocationReference)
        XCTAssertNil(payload.incomingShareMapURL)
        payload.coordinateSystem = PlaceCoordinateSystem.gcj02.rawValue
        XCTAssertFalse(payload.supportsIncomingShareLocationReference)
        payload.locationProvider = PlaceMatchProvider.amap.rawValue
        for raw in ["https://maps.apple.com/?ll=25.033,121.5654", "http://uri.amap.com/marker", "https://user:password@uri.amap.com/marker"] {
            payload.providerMapUrl = raw
            XCTAssertNil(payload.incomingShareMapURL)
        }
        let zero = SharedPlaceData(
            id: "zero", name: "Unlocated fixture", address: "", lat: 0, lng: 0, category: "cafe",
            rating: nil, reviewCount: nil, priceRange: nil, hours: nil, sourceLabel: "Fixture",
            sourceURL: nil, photoURLs: [], note: nil
        )
        XCTAssertNil(zero.incomingShareMapURL)
    }

    @MainActor
    func testRawJournalReferencesAreCheckedBeforeListNormalization() {
        var selected = PendingConfirmedPlace(
            placeId: "fixture", name: "Fixture place", address: "Synthetic address",
            latitude: 25.033, longitude: 121.5654, category: "cafe", sourceURL: nil
        )
        var journal = PendingSharePayload(
            kind: .place, shareCode: "fixture", placeId: nil, listId: nil, sender: nil,
            url: "savvy://p/fixture"
        )
        XCTAssertTrue(journal.supportsIncomingShareLocationReferences, "Legacy single-place journals have no snapshot metadata.")
        journal.kind = .list
        XCTAssertFalse(journal.supportsIncomingShareLocationReferences, "Lists require their selected raw snapshot.")
        journal.confirmedPlaces = [selected]
        XCTAssertTrue(journal.supportsIncomingShareLocationReferences)
        selected.coordinateSystem = "unsupported-reference"
        XCTAssertNil(selected.asListItem().coordinateSystem, "Normalization loses the unknown tag.")
        for kind in [PendingSharePayload.Kind.place, .list] {
            journal.kind = kind
            journal.confirmedPlaces = [selected]
            XCTAssertFalse(journal.supportsIncomingShareLocationReferences)
        }
        selected.coordinateSystem = PlaceCoordinateSystem.wgs84.rawValue
        selected.locationProvider = "unsupported-provider"
        XCTAssertFalse(selected.supportsIncomingShareLocationReference)
        selected.locationProvider = nil
        selected.latitude = .infinity
        XCTAssertFalse(selected.supportsIncomingShareLocationReference)
        selected.latitude = 91
        XCTAssertFalse(selected.supportsIncomingShareLocationReference)
    }

    @MainActor
    private func placePayload() -> SharedPlaceData {
        SharedPlaceData(
            id: "fixture", name: "Fixture place", address: "Synthetic address",
            lat: 25.033, lng: 121.5654, category: "cafe", rating: nil, reviewCount: nil,
            priceRange: nil, hours: nil, sourceLabel: "Fixture", sourceURL: nil, photoURLs: [], note: nil
        )
    }
}
