import XCTest
@testable import SAVE

@MainActor
final class RelatedPlaceSourcesPanelTests: XCTestCase {
    func testRequestIdentityChangesWhenGoogleIdentityChangesForSameMapStamp() {
        let placeID = UUID()
        let withoutGoogleIdentity = requestIdentity(placeID: placeID, googlePlaceID: nil)
        let confirmed = requestIdentity(placeID: placeID, googlePlaceID: "ChIJ-confirmed")

        XCTAssertFalse(withoutGoogleIdentity.isConfirmed)
        XCTAssertTrue(confirmed.isConfirmed)
        XCTAssertNotEqual(withoutGoogleIdentity, confirmed)
    }

    func testRequestIdentityTrimsWhitespaceButPreservesOpaqueIdentifierCase() {
        let placeID = UUID()

        XCTAssertEqual(
            requestIdentity(placeID: placeID, googlePlaceID: " ChIJ-confirmed "),
            requestIdentity(placeID: placeID, googlePlaceID: "ChIJ-confirmed")
        )
    }
    func testDifferentGoogleIdentifierCaseChangesIdentity() {
        let placeID = UUID()
        XCTAssertNotEqual(requestIdentity(placeID: placeID, googlePlaceID: "ABC"), requestIdentity(placeID: placeID, googlePlaceID: "abc"))
    }

    func testMissingGoogleIdentityIsExplainedByTheDisplayError() {
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(
                SupabaseError.apiError(409, "Confirm this place with Google Places before related-source discovery")
            ),
            .googleConfirmationRequired
        )
    }

    func testPublicVenueRejectionRemainsDistinctFromMissingIdentity() {
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(
                SupabaseError.apiError(400, "Related-source discovery only supports public venues")
            ),
            .publicVenueRequired
        )
    }

    func testRetryableFailuresRemainRetryableDisplayStates() {
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(SupabaseError.apiError(503, "unavailable")),
            .temporarilyUnavailable
        )
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(SupabaseError.apiError(429, "rate limited")),
            .rateLimited
        )
    }

    func testReceiptMustMatchConfirmedMapStampAndOpaqueGoogleIdentity() {
        let placeID = UUID()
        let current = requestIdentity(placeID: placeID, googlePlaceID: "ChIJ-B")
        func receipt(_ id: UUID, _ googleID: String?) -> RelatedSourcePlaceIdentity {
            RelatedSourcePlaceIdentity(id: id, name: "Venue", address: "Address",
                latitude: nil, longitude: nil, googlePlaceId: googleID)
        }

        XCTAssertTrue(current.matches(receipt(placeID, "  ChIJ-B\n")))
        XCTAssertFalse(current.matches(receipt(placeID, "ChIJ-A")), "Reject cached sources from the previous venue")
        XCTAssertFalse(current.matches(receipt(placeID, "chij-b")), "Google IDs are case-sensitive")
        XCTAssertFalse(current.matches(receipt(UUID(), "ChIJ-B")))
        XCTAssertFalse(current.matches(receipt(placeID, nil)))
        XCTAssertFalse(requestIdentity(placeID: placeID, googlePlaceID: nil).matches(receipt(placeID, nil)))
    }

    private func requestIdentity(placeID: UUID, googlePlaceID: String?) -> RelatedPlaceSourceRequestIdentity {
        RelatedPlaceSourceRequestIdentity(place: Place(
            id: placeID,
            name: "Kato",
            address: "Los Angeles",
            latitude: 34.035,
            longitude: -118.238,
            googlePlaceId: googlePlaceID,
            category: .food,
            status: .wantToGo,
            sourcePlatform: .other,
            createdAt: Date()
        ))
    }
}
