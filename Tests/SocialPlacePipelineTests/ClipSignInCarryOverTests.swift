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

    func testAuthorizedStillShowsSignInSoJournalLandsOnPhoneEmail() async {
        let defaults = store!
        ClipAppleAccountStore.write("001234.clip-apple-user.abcd", to: defaults)
        let restore = RestoreProbe()
        let outcome = await ClipSignInCarryOverController(
            loadAppleUserID: { ClipAppleAccountStore.read(from: defaults) },
            credentialState: { _ in .authorized },
            restoreSession: { restore.mark() }
        ).run()

        XCTAssertEqual(outcome, .showSignIn)
        XCTAssertEqual(restore.count, 0)
        XCTAssertEqual(
            ClipSignInCarryOver.decide(
                storedAppleUserID: "001234.clip-apple-user.abcd",
                credentialState: .authorized
            ),
            .showSignIn
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

    func testSilentAppleRequestHasNoNameOrEmailScopes() {
        XCTAssertTrue(ClipAppleSilentAuth.makeRequest().requestedScopes?.isEmpty ?? true)
    }

    func testExchangeResolvesLinkedPrivyDIDFromSilentAppleToken() async {
        let session = await ClipAppleSessionExchange.exchange(
            appleUserID: "001234.clip-apple-user.abcd",
            dependencies: .init(
                requestIdentityToken: { "silent-apple-identity-token" },
                resolvePrivyUserId: { token in
                    XCTAssertEqual(token, "silent-apple-identity-token")
                    return "did:privy:linked-clip-user"
                }
            )
        )
        XCTAssertEqual(session?.privyUserId, "did:privy:linked-clip-user")
        XCTAssertEqual(session?.identityToken, "silent-apple-identity-token")
    }

    func testExchangeRejectsRawAppleSubjectAndEmptyUser() async {
        let empty = await ClipAppleSessionExchange.exchange(
            appleUserID: "   ",
            dependencies: .init(
                requestIdentityToken: { "nope" },
                resolvePrivyUserId: { _ in "nope" }
            )
        )
        XCTAssertNil(empty)

        let rawSubject = await ClipAppleSessionExchange.exchange(
            appleUserID: "001234.clip-apple-user.abcd",
            dependencies: .init(
                requestIdentityToken: { "silent-apple-identity-token" },
                resolvePrivyUserId: { _ in "001234.clip-apple-user.abcd" }
            )
        )
        XCTAssertNil(rawSubject)
    }

    func testExchangeFailureFallsBackToSignIn() async {
        let restore = RestoreProbe()
        let outcome = await ClipSignInCarryOverController(
            loadAppleUserID: { "001234.clip-apple-user.abcd" },
            credentialState: { _ in .authorized },
            restoreSession: {
                guard await ClipAppleSessionExchange.exchange(
                    appleUserID: "001234.clip-apple-user.abcd",
                    dependencies: .init(
                        requestIdentityToken: { throw ClipAppleSessionError.failed },
                        resolvePrivyUserId: { _ in "did:privy:unused" }
                    )
                ) != nil else {
                    throw ClipAppleSessionError.failed
                }
                restore.mark()
            }
        ).run()
        XCTAssertEqual(outcome, .showSignIn)
        XCTAssertEqual(restore.count, 0)
    }

    func testIdentityTokenExpiryUsesExpClaimWithoutStoringJWT() {
        let header = Data("{\"alg\":\"none\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"exp\":1}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let expired = "\(header).\(payload).sig"
        XCTAssertTrue(ClipAppleIdentityToken.isExpired(expired, now: Date(timeIntervalSince1970: 100)))
        XCTAssertNil(store.string(forKey: "identityToken"))
    }
}

@MainActor
private final class RestoreProbe {
    private(set) var count = 0

    func mark() {
        count += 1
    }
}
