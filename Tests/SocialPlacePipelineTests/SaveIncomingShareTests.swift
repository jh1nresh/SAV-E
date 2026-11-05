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

}
