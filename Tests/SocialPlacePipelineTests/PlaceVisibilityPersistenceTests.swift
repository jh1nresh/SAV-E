import XCTest
@testable import SAVE

@MainActor
final class PlaceVisibilityPersistenceTests: XCTestCase {
    func testMissingAPIRejectsVisibilityChangeInsteadOfReportingSuccess() async {
        let service = SupabaseService(apiBaseURL: nil)
        do {
            try await service.updatePlaceVisibility(.privateMemory, for: UUID())
            XCTFail("A privacy change must not report success without persistence")
        } catch SupabaseError.notConfigured {
            // The caller can restore the previous visibility and explain failure.
        } catch {
            XCTFail("Expected notConfigured, received \(error)")
        }
    }
}
