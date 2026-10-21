import AuthenticationServices
import XCTest
@testable import SAVE

@MainActor
final class ClipSignInCarryOverTests: XCTestCase {
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: "clipAppleUserID.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        ClipAppleAccountStore.clear(store)
        store = nil
        super.tearDown()
    }

    func testAuthorizedSkipsSignInAndRestoresSession() async {
        let defaults = store!
        ClipAppleAccountStore.write("001234.clip-apple-user.abcd", to: defaults)
        let restore = RestoreProbe()
        let outcome = await ClipSignInCarryOverController(
            loadAppleUserID: { ClipAppleAccountStore.read(from: defaults) },
            credentialState: { _ in .authorized },
            restoreSession: { restore.mark() }
        ).run()

        XCTAssertEqual(outcome, .skipSignIn)
        XCTAssertEqual(restore.count, 1)
        XCTAssertEqual(
            ClipSignInCarryOver.decide(
                storedAppleUserID: "001234.clip-apple-user.abcd",
                credentialState: .authorized
            ),
            .skipSignIn
        )
        XCTAssertEqual(ClipSignInCarryOver.map(.authorized), .authorized)
    }

    func testRevokedOrNotFoundFallsBackToNormalSignIn() async {
        let defaults = store!
        ClipAppleAccountStore.write("001234.clip-apple-user.abcd", to: defaults)
        let restore = RestoreProbe()

        let revoked = await ClipSignInCarryOverController(
            loadAppleUserID: { ClipAppleAccountStore.read(from: defaults) },
            credentialState: { _ in .unavailable },
            restoreSession: { restore.mark() }
        ).run()
        XCTAssertEqual(revoked, .showSignIn)
        XCTAssertEqual(ClipSignInCarryOver.map(.revoked), .unavailable)

        let notFound = await ClipSignInCarryOverController(
            loadAppleUserID: { ClipAppleAccountStore.read(from: defaults) },
            credentialState: { _ in .unavailable },
            restoreSession: { restore.mark() }
        ).run()
        XCTAssertEqual(notFound, .showSignIn)
        XCTAssertEqual(ClipSignInCarryOver.map(.notFound), .unavailable)
        XCTAssertEqual(restore.count, 0)
        XCTAssertEqual(
            ClipSignInCarryOver.decide(
                storedAppleUserID: "001234.clip-apple-user.abcd",
                credentialState: .unavailable
            ),
            .showSignIn
        )
    }

    func testStoreRoundTripWritesAppleUserIDOnly() {
        ClipAppleAccountStore.write("  001234.clip-apple-user.abcd  ", to: store)
        XCTAssertEqual(ClipAppleAccountStore.read(from: store), "001234.clip-apple-user.abcd")
        XCTAssertEqual(ClipAppleAccountStore.key, "clipAppleUserID")
        XCTAssertEqual(ClipAppleAccountStore.suiteName, PendingShareStore.suiteName)
        XCTAssertNil(store.string(forKey: "identityToken"))
        XCTAssertNil(store.string(forKey: "privyJWT"))
        ClipAppleAccountStore.clear(store)
        XCTAssertNil(ClipAppleAccountStore.read(from: store))
    }

    func testBackendHasNoAppleIdSessionExchange() async {
        let userID = await ClipAppleSessionExchange.exchange(appleUserID: "001234.clip-apple-user.abcd")
        XCTAssertNil(userID)
        XCTAssertTrue(ClipAppleSilentAuth.makeRequest().requestedScopes?.isEmpty ?? true)
    }
}

@MainActor
private final class RestoreProbe {
    private(set) var count = 0

    func mark() {
        count += 1
    }
}
