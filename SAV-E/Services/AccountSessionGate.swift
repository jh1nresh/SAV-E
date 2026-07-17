import Combine
import Foundation

protocol AccountStatusProviding {
    func fetchAccountStatus() async throws -> AccountStatusResponse
    func confirmAccount(expectedAccountRef: String) async throws -> AccountStatusResponse
}

protocol AccountReferenceStoring {
    func load() throws -> String?
    func save(_ accountRef: String) throws
}

enum AccountGateState: Equatable {
    case idle
    case verifying
    case verified(sessionGeneration: Int)
    case accountNeedsConfirmation(AccountConfirmationKind)
    case recoveryNeeded(AccountRecoveryReason)
    case reauthenticationRequired
    case unavailable
}

@MainActor
final class AccountSessionGate: ObservableObject {
    @Published private(set) var state: AccountGateState = .idle

    private let statusProvider: AccountStatusProviding
    private let referenceStore: AccountReferenceStoring
    private var verificationRevision = 0
    private var pendingConfirmation: PendingAccountConfirmation?

    private struct PendingAccountConfirmation: Equatable {
        let accountRef: String
        let sessionGeneration: Int
        let verificationRevision: Int
        let kind: AccountConfirmationKind
    }

    init(
        statusProvider: AccountStatusProviding = SupabaseService.shared,
        referenceStore: AccountReferenceStoring = KeychainAccountReferenceStore.shared
    ) {
        self.statusProvider = statusProvider
        self.referenceStore = referenceStore
    }

    func verify(
        sessionGeneration: Int,
        sessionOrigin: AccountSessionOrigin,
        reviewerDemo: Bool
    ) async {
        verificationRevision += 1
        let revision = verificationRevision
        pendingConfirmation = nil
        state = .verifying

        if reviewerDemo {
            state = .verified(sessionGeneration: sessionGeneration)
            return
        }

        do {
            let status = try await statusProvider.fetchAccountStatus()
            guard revision == verificationRevision, !Task.isCancelled else { return }
            let decision = AccountGatePolicy.decide(
                status: status,
                storedAccountRef: try referenceStore.load(),
                sessionOrigin: sessionOrigin
            )
            try apply(decision, sessionGeneration: sessionGeneration, revision: revision)
        } catch is CancellationError {
            return
        } catch {
            guard revision == verificationRevision else { return }
            pendingConfirmation = nil
            state = Self.isAuthenticationError(error) ? .reauthenticationRequired : .unavailable
        }
    }

    func confirmPendingAccount(sessionGeneration: Int) async {
        guard case .accountNeedsConfirmation(let kind) = state,
              let pendingConfirmation,
              pendingConfirmation.kind == kind,
              pendingConfirmation.sessionGeneration == sessionGeneration,
              pendingConfirmation.verificationRevision == verificationRevision else {
            return
        }

        let revision = verificationRevision
        state = .verifying
        do {
            let status = try await statusProvider.confirmAccount(
                expectedAccountRef: pendingConfirmation.accountRef
            )
            guard revision == verificationRevision,
                  self.pendingConfirmation == pendingConfirmation else { return }
            guard !Task.isCancelled else { return }
            guard AccountGatePolicy.isConfirmedStatus(
                status,
                expectedAccountRef: pendingConfirmation.accountRef
            ) else {
                self.pendingConfirmation = nil
                state = .unavailable
                return
            }
            try referenceStore.save(pendingConfirmation.accountRef)
            self.pendingConfirmation = nil
            state = .verified(sessionGeneration: sessionGeneration)
        } catch is CancellationError {
            return
        } catch {
            guard revision == verificationRevision else { return }
            self.pendingConfirmation = nil
            state = Self.isAuthenticationError(error) ? .reauthenticationRequired : .unavailable
        }
    }

    func invalidate() {
        verificationRevision += 1
        pendingConfirmation = nil
        state = .idle
    }

    private func apply(
        _ decision: AccountGateDecision,
        sessionGeneration: Int,
        revision: Int
    ) throws {
        switch decision {
        case .verified(let accountRef, let shouldStore):
            if shouldStore {
                try referenceStore.save(accountRef)
            }
            pendingConfirmation = nil
            state = .verified(sessionGeneration: sessionGeneration)
        case .confirmAccount(let accountRef, let kind):
            pendingConfirmation = PendingAccountConfirmation(
                accountRef: accountRef,
                sessionGeneration: sessionGeneration,
                verificationRevision: revision,
                kind: kind
            )
            state = .accountNeedsConfirmation(kind)
        case .recovery(let reason):
            pendingConfirmation = nil
            state = .recoveryNeeded(reason)
        case .unavailable:
            pendingConfirmation = nil
            state = .unavailable
        }
    }

    private static func isAuthenticationError(_ error: Error) -> Bool {
        guard let serviceError = error as? SupabaseError else { return false }
        if case .notAuthenticated = serviceError { return true }
        return false
    }
}
