import XCTest
@testable import SAVE

@MainActor
final class TripPlanningIntentValidatorTests: XCTestCase {
    private let validator = TripIntentJSONValidator()

    func testParsesDaysAndTerms() throws {
        let intent = try validator.parse(#"{"days":2,"searchTerms":["taipei","food"]}"#, rawQuery: "weekend in Taipei")

        XCTAssertEqual(intent.days, 2)
        XCTAssertEqual(intent.searchTerms, ["taipei", "food"])
        XCTAssertEqual(intent.rawMessage, "weekend in Taipei")
    }

    func testNullDaysMeansLetThePlannerDecide() throws {
        let intent = try validator.parse(#"{"days":null,"searchTerms":[]}"#, rawQuery: "plan a trip")

        XCTAssertNil(intent.days)
        XCTAssertFalse(intent.hasSpecificRequest)
    }

    func testClampsAbsurdDayCounts() throws {
        XCTAssertEqual(try validator.parse(#"{"days":365}"#, rawQuery: "").days, 7)
        XCTAssertEqual(try validator.parse(#"{"days":0}"#, rawQuery: "").days, 1)
        XCTAssertEqual(try validator.parse(#"{"days":-4}"#, rawQuery: "").days, 1)
    }

    func testDropsJunkTermsAndCapsTheList() throws {
        let json = #"{"days":1,"searchTerms":["Taipei","  ","taipei","food","cafe","bar","attraction","shopping","stay","aVeryLongTermThatNoPlaceNameWouldEverMatchInPractice"]}"#

        let terms = try validator.parse(json, rawQuery: "").searchTerms

        // Lowercased, deduped, blank and overlong dropped, capped.
        XCTAssertEqual(terms, ["taipei", "food", "cafe", "bar", "attraction", "shopping"])
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try validator.parse("not json at all", rawQuery: "x"))
    }

    func testToleratesMissingFields() throws {
        let intent = try validator.parse("{}", rawQuery: "plan a trip")

        XCTAssertNil(intent.days)
        XCTAssertEqual(intent.searchTerms, [])
    }
}
