import XCTest
@testable import SAVE

final class ReviewDemoTests: XCTestCase {
    @MainActor
    func testExactCredentialPairTriggersBypass() {
        XCTAssertTrue(ReviewDemo.isDemoCredentialPair(email: ReviewDemo.email, code: ReviewDemo.code))
    }

    @MainActor
    func testEmailMatchIsCaseAndWhitespaceTolerant() {
        XCTAssertTrue(ReviewDemo.isDemoEmail("  AppReview@Wanderly.app  "))
        XCTAssertTrue(ReviewDemo.isDemoCredentialPair(email: "APPREVIEW@WANDERLY.APP", code: " 424242 "))
    }

    @MainActor
    func testWrongCodeDoesNotTrigger() {
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: ReviewDemo.email, code: "000000"))
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: ReviewDemo.email, code: ""))
    }

    @MainActor
    func testWrongEmailDoesNotTrigger() {
        XCTAssertFalse(ReviewDemo.isDemoEmail("user@example.com"))
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: "user@example.com", code: ReviewDemo.code))
        // A real user who happens to type the demo code with their own email
        // must still go through Privy.
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: "someone@gmail.com", code: "424242"))
    }

    @MainActor
    func testSeedProducesPopulatedPlacesWithCoordinates() {
        let places = ReviewDemoSeed.places()
        XCTAssertGreaterThanOrEqual(places.count, 6)
        for place in places {
            XCTAssertFalse(place.name.isEmpty)
            XCTAssertFalse(place.address.isEmpty)
            XCTAssertTrue(place.latitude != 0 || place.longitude != 0)
        }
        // Mixed regions so the map is visibly populated.
        XCTAssertTrue(places.contains { $0.category == .food })
        XCTAssertTrue(places.contains { $0.category == .cafe })
        XCTAssertTrue(places.contains { $0.category == .stay })
    }

    @MainActor
    func testGuestTokenHolderRoundTrips() {
        let holder = ReviewDemoGuestTokenHolder()
        XCTAssertNil(holder.current)
        holder.set("guest-abc")
        XCTAssertEqual(holder.current, "guest-abc")
        holder.set(nil)
        XCTAssertNil(holder.current)
    }
}
