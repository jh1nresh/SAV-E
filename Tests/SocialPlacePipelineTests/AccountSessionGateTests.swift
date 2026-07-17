import XCTest
@testable import SAVE

@MainActor
final class AccountSessionGateTests: XCTestCase {
    private let firstRef = "save_account_" + String(repeating: "A", count: 43)
    private let secondRef = "save_account_" + String(repeating: "B", count: 43)

    func testRestoredReadyUpgradeRequiresInteractiveConfirmation() async {
        let store = InMemoryAccountReferenceStore()
        let gate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(response: response(.ready, ref: firstRef)),
            referenceStore: store
        )

        await gate.verify(sessionGeneration: 7, sessionOrigin: .restored, reviewerDemo: false)

        XCTAssertEqual(gate.state, .recoveryNeeded(.unconfirmedRestoredAccount))
        XCTAssertNil(store.value)
    }

    func testInteractiveReadyAccountIsConfirmedServerSideBeforeItIsRemembered() async {
        let store = InMemoryAccountReferenceStore()
        let provider = StubAccountStatusProvider(
            response: response(.ready, ref: firstRef, stamps: 70, reviewItems: 188),
            confirmationResponse: response(.ready, ref: firstRef, stamps: 70, reviewItems: 188)
        )
        let gate = AccountSessionGate(statusProvider: provider, referenceStore: store)

        await gate.verify(sessionGeneration: 8, sessionOrigin: .interactive, reviewerDemo: false)
        XCTAssertEqual(
            gate.state,
            .accountNeedsConfirmation(.existingAccount(stamps: 70, reviewItems: 188))
        )
        XCTAssertNil(store.value)

        await gate.confirmPendingAccount(sessionGeneration: 8)
        XCTAssertEqual(gate.state, .verified(sessionGeneration: 8))
        XCTAssertEqual(store.value, firstRef)
        XCTAssertEqual(provider.confirmedRefs, [firstRef])
    }

    func testSameConfirmedAccountOpensWithoutRewritingReference() async {
        let store = InMemoryAccountReferenceStore(value: firstRef)
        let gate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(response: response(.ready, ref: firstRef)),
            referenceStore: store
        )

        await gate.verify(sessionGeneration: 2, sessionOrigin: .restored, reviewerDemo: false)

        XCTAssertEqual(gate.state, .verified(sessionGeneration: 2))
        XCTAssertEqual(store.saveCount, 0)
    }

    func testDifferentAccountNeverOverwritesConfirmedReference() async {
        let store = InMemoryAccountReferenceStore(value: firstRef)
        let gate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(response: response(.ready, ref: secondRef)),
            referenceStore: store
        )

        await gate.verify(sessionGeneration: 3, sessionOrigin: .interactive, reviewerDemo: false)

        XCTAssertEqual(gate.state, .recoveryNeeded(.differentAccount))
        XCTAssertEqual(store.value, firstRef)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testFreshInteractiveAccountCreatesProfileBeforeOpeningContent() async {
        let store = InMemoryAccountReferenceStore()
        let provider = StubAccountStatusProvider(
            response: response(.new, ref: firstRef),
            confirmationResponse: response(.empty, ref: firstRef)
        )
        let gate = AccountSessionGate(statusProvider: provider, referenceStore: store)

        await gate.verify(sessionGeneration: 4, sessionOrigin: .interactive, reviewerDemo: false)
        XCTAssertEqual(gate.state, .accountNeedsConfirmation(.newAccount))
        XCTAssertNil(store.value)

        await gate.confirmPendingAccount(sessionGeneration: 4)
        XCTAssertEqual(gate.state, .verified(sessionGeneration: 4))
        XCTAssertEqual(store.value, firstRef)
        XCTAssertEqual(provider.confirmedRefs, [firstRef])
    }

    func testInteractiveEmptyAccountHasAnExplicitExitFromRecoveryLoop() async {
        let store = InMemoryAccountReferenceStore()
        let provider = StubAccountStatusProvider(
            response: response(.empty, ref: firstRef),
            confirmationResponse: response(.empty, ref: firstRef)
        )
        let gate = AccountSessionGate(statusProvider: provider, referenceStore: store)

        await gate.verify(sessionGeneration: 5, sessionOrigin: .interactive, reviewerDemo: false)
        XCTAssertEqual(gate.state, .accountNeedsConfirmation(.emptyAccount))

        await gate.confirmPendingAccount(sessionGeneration: 5)
        XCTAssertEqual(gate.state, .verified(sessionGeneration: 5))
        XCTAssertEqual(store.value, firstRef)
    }

    func testRestoredNewOrEmptyAccountRequiresRecovery() async {
        for statusState in [AccountStatusState.new, .empty] {
            let gate = AccountSessionGate(
                statusProvider: StubAccountStatusProvider(response: response(statusState, ref: firstRef)),
                referenceStore: InMemoryAccountReferenceStore()
            )

            await gate.verify(sessionGeneration: 6, sessionOrigin: .restored, reviewerDemo: false)
            XCTAssertEqual(gate.state, .recoveryNeeded(.emptyRestoredAccount))
        }
    }

    func testStaleConfirmationCannotApproveAnotherSessionGeneration() async {
        let store = InMemoryAccountReferenceStore()
        let provider = StubAccountStatusProvider(
            response: response(.new, ref: firstRef),
            confirmationResponse: response(.empty, ref: firstRef)
        )
        let gate = AccountSessionGate(statusProvider: provider, referenceStore: store)

        await gate.verify(sessionGeneration: 10, sessionOrigin: .interactive, reviewerDemo: false)
        await gate.confirmPendingAccount(sessionGeneration: 11)

        XCTAssertEqual(gate.state, .accountNeedsConfirmation(.newAccount))
        XCTAssertTrue(provider.confirmedRefs.isEmpty)
        XCTAssertNil(store.value)
    }

    func testFailedServerConfirmationNeverWritesKeychain() async {
        let store = InMemoryAccountReferenceStore()
        let provider = StubAccountStatusProvider(
            response: response(.new, ref: firstRef),
            confirmationError: URLError(.cannotConnectToHost)
        )
        let gate = AccountSessionGate(statusProvider: provider, referenceStore: store)

        await gate.verify(sessionGeneration: 12, sessionOrigin: .interactive, reviewerDemo: false)
        await gate.confirmPendingAccount(sessionGeneration: 12)

        XCTAssertEqual(gate.state, .unavailable)
        XCTAssertNil(store.value)
    }

    func testAuthFailureAndNetworkFailureNeverBecomeVerifiedEmptyData() async {
        let authGate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(error: SupabaseError.notAuthenticated),
            referenceStore: InMemoryAccountReferenceStore()
        )
        await authGate.verify(sessionGeneration: 13, sessionOrigin: .restored, reviewerDemo: false)
        XCTAssertEqual(authGate.state, .reauthenticationRequired)

        let networkGate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(error: URLError(.notConnectedToInternet)),
            referenceStore: InMemoryAccountReferenceStore()
        )
        await networkGate.verify(sessionGeneration: 13, sessionOrigin: .restored, reviewerDemo: false)
        XCTAssertEqual(networkGate.state, .unavailable)
    }

    func testConflictingBindingsAndReviewerDemoStayContained() async {
        for reason in ["split_profile_binding", "conflicting_profile_binding"] {
            let expected: AccountRecoveryReason = reason == "split_profile_binding"
                ? .splitProfileBinding
                : .conflictingProfileBinding
            let gate = AccountSessionGate(
                statusProvider: StubAccountStatusProvider(
                    response: response(.recoveryRequired, ref: nil, recoveryReason: reason)
                ),
                referenceStore: InMemoryAccountReferenceStore()
            )
            await gate.verify(sessionGeneration: 14, sessionOrigin: .restored, reviewerDemo: false)
            XCTAssertEqual(gate.state, .recoveryNeeded(expected))
        }

        let demoGate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(error: SupabaseError.notAuthenticated),
            referenceStore: InMemoryAccountReferenceStore()
        )
        await demoGate.verify(sessionGeneration: 15, sessionOrigin: .interactive, reviewerDemo: true)
        XCTAssertEqual(demoGate.state, .verified(sessionGeneration: 15))
    }

    func testPublishedStateNeverContainsOpaqueReference() async {
        let gate = AccountSessionGate(
            statusProvider: StubAccountStatusProvider(response: response(.new, ref: firstRef)),
            referenceStore: InMemoryAccountReferenceStore()
        )

        await gate.verify(sessionGeneration: 16, sessionOrigin: .interactive, reviewerDemo: false)

        XCTAssertFalse(String(describing: gate.state).contains(firstRef))
    }

    private func response(
        _ state: AccountStatusState,
        ref: String?,
        stamps: Int = 0,
        reviewItems: Int = 0,
        recoveryReason: String? = nil
    ) -> AccountStatusResponse {
        AccountStatusResponse(
            version: "v0",
            state: state,
            accountRef: ref,
            profile: AccountStatusProfile(exists: state != .new, customized: state == .ready),
            counts: state == .recoveryRequired
                ? nil
                : AccountStatusCounts(stamps: stamps, reviewItems: reviewItems),
            recoveryReason: state == .recoveryRequired
                ? (recoveryReason ?? "split_profile_binding")
                : nil
        )
    }
}

private final class StubAccountStatusProvider: AccountStatusProviding {
    private let response: AccountStatusResponse?
    private let confirmationResponse: AccountStatusResponse?
    private let error: Error?
    private let confirmationError: Error?
    private(set) var confirmedRefs: [String] = []

    init(
        response: AccountStatusResponse,
        confirmationResponse: AccountStatusResponse? = nil,
        confirmationError: Error? = nil
    ) {
        self.response = response
        self.confirmationResponse = confirmationResponse
        self.error = nil
        self.confirmationError = confirmationError
    }

    init(error: Error) {
        self.response = nil
        self.confirmationResponse = nil
        self.error = error
        self.confirmationError = error
    }

    func fetchAccountStatus() async throws -> AccountStatusResponse {
        if let error { throw error }
        return try XCTUnwrap(response)
    }

    func confirmAccount(expectedAccountRef: String) async throws -> AccountStatusResponse {
        confirmedRefs.append(expectedAccountRef)
        if let confirmationError { throw confirmationError }
        return try XCTUnwrap(confirmationResponse ?? response)
    }
}

private final class InMemoryAccountReferenceStore: AccountReferenceStoring {
    var value: String?
    private(set) var saveCount = 0

    init(value: String? = nil) {
        self.value = value
    }

    func load() throws -> String? {
        value
    }

    func save(_ accountRef: String) throws {
        value = accountRef
        saveCount += 1
    }
}
