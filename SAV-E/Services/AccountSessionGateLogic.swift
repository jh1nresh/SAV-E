import Foundation

enum AccountSessionOrigin: String, Hashable, Sendable {
    case restored
    case interactive
}

enum AccountStatusState: String, Decodable, Sendable {
    case ready
    case new
    case empty
    case recoveryRequired = "recovery_required"
}

struct AccountStatusResponse: Decodable, Equatable, Sendable {
    let version: String
    let state: AccountStatusState
    let accountRef: String?
    let profile: AccountStatusProfile
    let counts: AccountStatusCounts?
    let recoveryReason: String?

    enum CodingKeys: String, CodingKey {
        case version
        case state
        case accountRef = "account_ref"
        case profile
        case counts
        case recoveryReason = "recovery_reason"
    }
}

struct AccountStatusProfile: Decodable, Equatable, Sendable {
    let exists: Bool
    let customized: Bool?
}

struct AccountStatusCounts: Decodable, Equatable, Sendable {
    let stamps: Int
    let reviewItems: Int

    enum CodingKeys: String, CodingKey {
        case stamps
        case reviewItems = "review_items"
    }
}

enum AccountRecoveryReason: Equatable, Sendable {
    case emptyRestoredAccount
    case unconfirmedRestoredAccount
    case differentAccount
    case splitProfileBinding
    case conflictingProfileBinding
    case missingConfirmedProfile
}

enum AccountConfirmationKind: Equatable, Sendable {
    case newAccount
    case existingAccount(stamps: Int, reviewItems: Int)
    case emptyAccount
}

enum AccountGateDecision: Equatable, Sendable {
    case verified(accountRef: String, shouldStore: Bool)
    case confirmAccount(accountRef: String, kind: AccountConfirmationKind)
    case recovery(AccountRecoveryReason)
    case unavailable
}

enum AccountGatePolicy {
    static func decide(
        status: AccountStatusResponse,
        storedAccountRef: String?,
        sessionOrigin: AccountSessionOrigin
    ) -> AccountGateDecision {
        guard status.version == "v0" else { return .unavailable }

        if status.state == .recoveryRequired {
            switch status.recoveryReason {
            case "split_profile_binding":
                return .recovery(.splitProfileBinding)
            case "conflicting_profile_binding":
                return .recovery(.conflictingProfileBinding)
            default:
                return .unavailable
            }
        }

        guard let accountRef = status.accountRef, isValidAccountRef(accountRef) else {
            return .unavailable
        }

        if let storedAccountRef {
            guard storedAccountRef == accountRef else {
                return .recovery(.differentAccount)
            }
            if status.state == .new {
                return .recovery(.missingConfirmedProfile)
            }
            return .verified(accountRef: accountRef, shouldStore: false)
        }

        switch status.state {
        case .ready where sessionOrigin == .interactive:
            let counts = status.counts ?? AccountStatusCounts(stamps: 0, reviewItems: 0)
            return .confirmAccount(
                accountRef: accountRef,
                kind: .existingAccount(stamps: counts.stamps, reviewItems: counts.reviewItems)
            )
        case .ready:
            return .recovery(.unconfirmedRestoredAccount)
        case .new where sessionOrigin == .interactive:
            return .confirmAccount(accountRef: accountRef, kind: .newAccount)
        case .empty where sessionOrigin == .interactive:
            return .confirmAccount(accountRef: accountRef, kind: .emptyAccount)
        case .new, .empty:
            return .recovery(.emptyRestoredAccount)
        case .recoveryRequired:
            return .recovery(.splitProfileBinding)
        }
    }

    static func isValidAccountRef(_ value: String) -> Bool {
        let prefix = "save_account_"
        guard value.hasPrefix(prefix), value.count == prefix.count + 43 else { return false }
        let suffix = value.dropFirst(prefix.count)
        return suffix.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    static func isConfirmedStatus(_ status: AccountStatusResponse, expectedAccountRef: String) -> Bool {
        guard status.version == "v0",
              status.accountRef == expectedAccountRef,
              status.state == .ready || status.state == .empty else {
            return false
        }
        return true
    }
}
