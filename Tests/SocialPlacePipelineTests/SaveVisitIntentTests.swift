import XCTest
@testable import SAVE

@MainActor
final class SaveVisitIntentTests: XCTestCase {
    func testVisitIntentLabelsStayMapStampSubstates() {
        XCTAssertEqual(
            PlaceStatus.wantToGo.visitIntentLabel(language: .english),
            "Want to try"
        )
        XCTAssertEqual(
            PlaceStatus.wantToGo.visitIntentLabel(language: .traditionalChinese),
            "想找時間去"
        )
        XCTAssertEqual(
            PlaceStatus.visited.visitIntentLabel(language: .english),
            "Visited"
        )
        XCTAssertEqual(
            PlaceStatus.visited.visitIntentLabel(language: .traditionalChinese),
            "去過"
        )
    }

    func testVisitIntentIdentifiersStayOnTheMemoryCard() {
        XCTAssertEqual(
            PlaceStatus.wantToGo.visitIntentAccessibilityIdentifier(),
            "drawer.saved.wantToGo"
        )
        XCTAssertEqual(
            PlaceStatus.visited.visitIntentAccessibilityIdentifier(),
            "drawer.saved.visited"
        )
    }

    func testMemoryCardLabelDoesNotCollapseVisitedIntoAGenericSavedItem() {
        XCTAssertEqual(
            PlaceStatus.wantToGo.memoryCardLabel(language: .english),
            "Map Stamp"
        )
        XCTAssertEqual(
            PlaceStatus.visited.memoryCardLabel(language: .english),
            "Visited"
        )
        XCTAssertNotEqual(
            PlaceStatus.wantToGo.visitIntentLabel(language: .english),
            PlaceStatus.wantToGo.memoryCardLabel(language: .english)
        )
    }
}
