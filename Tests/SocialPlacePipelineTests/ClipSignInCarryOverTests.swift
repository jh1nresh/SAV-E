import XCTest
@testable import SAVE

@MainActor
final class ClipSignInCarryOverTests: XCTestCase {
    func testClipIdentifierNeverSubstitutesForFullAppSession() {
        let store = UserDefaults(suiteName: "clip.pending.auth.\(UUID().uuidString)")!
        defer { ClipAppleAccountStore.clear(store) }
        ClipAppleAccountStore.write("legacy-apple-subject", to: store)
        XCTAssertNotNil(ClipAppleAccountStore.read(from: store))
        XCTAssertTrue(ClipSignInCarryOver.requiresFullAppSignIn(hasAuthenticatedSession: false))
        XCTAssertFalse(ClipSignInCarryOver.requiresFullAppSignIn(hasAuthenticatedSession: true))
        XCTAssertNil(store.string(forKey: "identityToken"))
        XCTAssertNil(store.string(forKey: "privyJWT"))
    }
}
