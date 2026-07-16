import XCTest
@testable import SAVE

@MainActor
final class SavePetCompanionTests: XCTestCase {
    func testEvolutionMatchesTomaThresholds() {
        XCTAssertEqual(SavePetStage(xp: 0), .hatchling)
        XCTAssertEqual(SavePetStage(xp: 19), .hatchling)
        XCTAssertEqual(SavePetStage(xp: 20), .companion)
        XCTAssertEqual(SavePetStage(xp: 59), .companion)
        XCTAssertEqual(SavePetStage(xp: 60), .guardian)
    }

    func testStageProgressIsBounded() {
        XCTAssertEqual(SavePetStage.hatchling.progress(xp: -20), 0)
        XCTAssertEqual(SavePetStage.hatchling.progress(xp: 10), 0.5)
        XCTAssertEqual(SavePetStage.companion.progress(xp: 40), 0.5)
        XCTAssertEqual(SavePetStage.guardian.progress(xp: 60), 1)
    }

    func testProfileDerivesStageFromReceiptBackedXP() {
        var profile = UserProfile.mock
        profile.petXP = 60

        XCTAssertEqual(profile.petStage, .guardian)
    }
}
