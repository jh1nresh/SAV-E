import Foundation

private let firstRef = "save_account_" + String(repeating: "A", count: 43)
private let secondRef = "save_account_" + String(repeating: "B", count: 43)

private func response(_ state: AccountStatusState, ref: String?) -> AccountStatusResponse {
    AccountStatusResponse(
        version: "v0",
        state: state,
        accountRef: ref,
        profile: AccountStatusProfile(exists: state != .new, customized: state == .ready),
        counts: state == .recoveryRequired ? nil : AccountStatusCounts(stamps: 0, reviewItems: 0),
        recoveryReason: state == .recoveryRequired ? "split_profile_binding" : nil
    )
}

private func expect(_ actual: AccountGateDecision, _ expected: AccountGateDecision, _ label: String) {
    guard actual == expected else {
        fatalError("\(label): expected \(expected), got \(actual)")
    }
}

expect(
    AccountGatePolicy.decide(status: response(.ready, ref: firstRef), storedAccountRef: nil, sessionOrigin: .restored),
    .recovery(.unconfirmedRestoredAccount),
    "restored upgrade requires confirmation"
)
expect(
    AccountGatePolicy.decide(status: response(.ready, ref: firstRef), storedAccountRef: nil, sessionOrigin: .interactive),
    .confirmAccount(accountRef: firstRef, kind: .existingAccount(stamps: 0, reviewItems: 0)),
    "interactive existing account"
)
expect(
    AccountGatePolicy.decide(status: response(.ready, ref: firstRef), storedAccountRef: firstRef, sessionOrigin: .restored),
    .verified(accountRef: firstRef, shouldStore: false),
    "same account"
)
expect(
    AccountGatePolicy.decide(status: response(.ready, ref: secondRef), storedAccountRef: firstRef, sessionOrigin: .interactive),
    .recovery(.differentAccount),
    "different account"
)
expect(
    AccountGatePolicy.decide(status: response(.new, ref: firstRef), storedAccountRef: nil, sessionOrigin: .interactive),
    .confirmAccount(accountRef: firstRef, kind: .newAccount),
    "interactive first run"
)
expect(
    AccountGatePolicy.decide(status: response(.new, ref: firstRef), storedAccountRef: nil, sessionOrigin: .restored),
    .recovery(.emptyRestoredAccount),
    "restored empty account"
)
expect(
    AccountGatePolicy.decide(status: response(.empty, ref: firstRef), storedAccountRef: nil, sessionOrigin: .interactive),
    .confirmAccount(accountRef: firstRef, kind: .emptyAccount),
    "interactive empty account"
)
expect(
    AccountGatePolicy.decide(status: response(.empty, ref: firstRef), storedAccountRef: firstRef, sessionOrigin: .restored),
    .verified(accountRef: firstRef, shouldStore: false),
    "confirmed empty account"
)
expect(
    AccountGatePolicy.decide(status: response(.new, ref: firstRef), storedAccountRef: firstRef, sessionOrigin: .restored),
    .recovery(.missingConfirmedProfile),
    "missing confirmed profile"
)
expect(
    AccountGatePolicy.decide(status: response(.recoveryRequired, ref: nil), storedAccountRef: nil, sessionOrigin: .restored),
    .recovery(.splitProfileBinding),
    "split profile"
)
expect(
    AccountGatePolicy.decide(status: response(.ready, ref: "raw-user-id"), storedAccountRef: nil, sessionOrigin: .restored),
    .unavailable,
    "malformed account ref"
)

print("account-session-gate-check: 11/11 passed")
