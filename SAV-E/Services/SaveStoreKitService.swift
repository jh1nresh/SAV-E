import Foundation
import Observation
import StoreKit

nonisolated struct SaveEntitlementSession: Equatable, Sendable {
    let generation: Int
    let owner: String?

    @MainActor static var current: Self {
        Self(generation: PrivyAuthService.shared.sessionGeneration, owner: PrivyAuthService.shared.currentUserId)
    }
}

nonisolated enum SaveSubscriptionRegistrationError: Error {
    case ownershipConflict
    case accountBindingRequired

    static func from(status: Int, body: Data) -> Self? {
        guard status == 409,
              let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        switch value["code"] as? String {
        case "subscription_owner_conflict": return .ownershipConflict
        case "subscription_account_binding_required": return .accountBindingRequired
        default: return nil
        }
    }
}

/// Only constructed from locally verified StoreKit results in production.
nonisolated struct SaveStoreTransaction: Sendable {
    let productID: String
    let signedRepresentation: String
    let expirationDate: Date?
    let revocationDate: Date?
    let finish: @Sendable () async -> Void

    init(productID: String, signedRepresentation: String, expirationDate: Date?, revocationDate: Date?, finish: @escaping @Sendable () async -> Void) {
        self.productID = productID
        self.signedRepresentation = signedRepresentation
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.finish = finish
    }

    init?(_ verification: VerificationResult<Transaction>) {
        guard case .verified(let transaction) = verification else { return nil }
        productID = transaction.productID
        signedRepresentation = verification.jwsRepresentation
        expirationDate = transaction.expirationDate
        revocationDate = transaction.revocationDate
        finish = { await transaction.finish() }
    }
}

/// StoreKit 2 wrapper for Savvy Pro.
///
/// Deliberate boundary: this type may *observe* Apple transactions and report
/// them. Only the server response grants Pro. A successful Apple payment is
/// not reported as activated until its signed transaction is persisted by the
/// backend for the same Savvy session.
@MainActor
@Observable
final class SaveStoreKitService {
    static let shared = SaveStoreKitService()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var lastError: String?

    /// Tier confirmed by the backend for the most recent registered
    /// transaction. `nil` means no server confirmation is available yet, which
    /// must be read as "not proven Pro" rather than "free forever".
    private var registeredTier: SaveProTier?
    private var registeredTierValidUntil: Date?
    var serverVerifiedTier: SaveProTier? {
        guard stateSession == currentSession() else { return nil }
        if registeredTier == .pro {
            guard let registeredTierValidUntil, registeredTierValidUntil > now() else { return nil }
        }
        return registeredTier
    }

    private let currentSession: () -> SaveEntitlementSession
    private let readEntitlements: () async -> [SaveStoreTransaction]
    private let synchronizePurchases: () async throws -> Void
    private let purchasingAvailable: () -> Bool
    private let now: () -> Date
    private let loadAccountToken: () async throws -> UUID
    private var stateSession: SaveEntitlementSession?
    private var updatesTask: Task<Void, Never>?

    /// Injected so tests can observe registration without a network call.
    private let registerTransaction: (String) async throws -> SaveEntitlementResponse

    /// Locally observed entitlement. This is a UI hint only; the server
    /// response in `SaveEntitlementStore` is what actually grants access. The
    /// property is intentionally not named `isPro` so no caller mistakes a
    /// client signal for granted access.
    var locallyObservedTier: SaveProTier {
        stateSession == currentSession() && !purchasedProductIDs.isEmpty ? .pro : .free
    }

    init(
        registerTransaction: @escaping (String) async throws -> SaveEntitlementResponse = { jws in
            try await SupabaseService.shared.registerAppleTransaction(signedTransaction: jws)
        },
        currentSession: @escaping () -> SaveEntitlementSession = { .current },
        readEntitlements: @escaping () async -> [SaveStoreTransaction] = {
            var transactions: [SaveStoreTransaction] = []
            for await result in Transaction.currentEntitlements {
                if let transaction = SaveStoreTransaction(result) { transactions.append(transaction) }
            }
            return transactions
        },
        synchronizePurchases: @escaping () async throws -> Void = { try await AppStore.sync() },
        purchasingAvailable: @escaping () -> Bool = { SAVEProAccessPolicy.purchasingIsAvailable },
        observeUpdates: Bool = true,
        now: @escaping () -> Date = Date.init,
        loadAccountToken: @escaping () async throws -> UUID = {
            try await SupabaseService.shared.fetchPurchaseAccountToken()
        }
    ) {
        self.registerTransaction = registerTransaction
        self.currentSession = currentSession
        self.readEntitlements = readEntitlements
        self.synchronizePurchases = synchronizePurchases
        self.purchasingAvailable = purchasingAvailable
        self.loadAccountToken = loadAccountToken
        self.now = now
        // Transaction updates must be observed for the whole app lifetime,
        // including renewals and purchases made on another device. This is a
        // singleton that outlives every screen, so the task is never cancelled;
        // a `deinit` cancel would also be MainActor-isolated and cannot run
        // from a nonisolated deinit.
        guard observeUpdates else { return }
        updatesTask = Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verificationResult: update)
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        guard purchasingAvailable() else {
            // Products do not exist in App Store Connect yet. Loading would log
            // a spurious failure on every launch, so skip it deliberately.
            products = []
            return
        }
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: SAVEProAccessPolicy.ProductID.all)
            // Keep the annual offer first; it is the primary hypothesis.
            products = loaded.sorted { lhs, rhs in
                lhs.id == SAVEProAccessPolicy.ProductID.annual && rhs.id != SAVEProAccessPolicy.ProductID.annual
            }
            lastError = nil
        } catch {
            products = []
            lastError = "Could not load subscription options."
        }
    }

    // MARK: - Purchase

    enum PurchaseOutcome: Equatable {
        case success
        case userCancelled
        case pending
        case failed(String)
        case unavailable
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard purchasingAvailable() else { return .unavailable }
        let session = prepareSession()
        guard session.owner != nil else { return .failed("Sign in to Savvy before purchasing.") }
        guard SAVEProAccessPolicy.ProductID.all.contains(product.id) else { return .unavailable }
        do {
            let token = try await purchaseAccountToken(for: session)
            let result = try await product.purchase(options: [.appAccountToken(token)])
            guard isCurrent(session) else { return sessionChangedOutcome }
            switch result {
            case .success(let verification):
                guard let transaction = SaveStoreTransaction(verification) else {
                    return .failed("Apple could not verify this purchase. Please try Restore Purchases.")
                }
                return await activate(transaction, for: session)
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unrecognized purchase result.")
            }
        } catch {
            guard isCurrent(session) else { return sessionChangedOutcome }
            return .failed("Purchase could not be completed.")
        }
    }

    /// Fetch the account token before opening Apple's purchase sheet. A token
    /// obtained for a superseded login must never be used by a new account.
    func purchaseAccountToken(for session: SaveEntitlementSession) async throws -> UUID {
        _ = prepareSession()
        guard session.owner != nil, isCurrent(session) else { throw CancellationError() }
        let token = try await loadAccountToken()
        guard isCurrent(session) else { throw CancellationError() }
        return token
    }

    /// Restore is successful only after a verified active transaction has
    /// reconciled with the backend. Local Apple ownership alone is insufficient.
    func restorePurchases() async -> PurchaseOutcome {
        guard purchasingAvailable() else { return .unavailable }
        let session = prepareSession()
        guard session.owner != nil else { return .failed("Sign in to Savvy before restoring purchases.") }
        do {
            try await synchronizePurchases()
            guard isCurrent(session) else { return sessionChangedOutcome }
            return await reconcileEntitlements(for: session)
        } catch {
            guard isCurrent(session) else { return sessionChangedOutcome }
            return .failed("Restore could not be completed. Please try again.")
        }
    }

    // MARK: - Entitlement reconciliation

    func refreshEntitlements() async {
        let session = prepareSession()
        guard session.owner != nil else { return }
        _ = await reconcileEntitlements(for: session)
    }

    func resetForSessionChange() {
        stateSession = nil
        registeredTier = nil
        registeredTierValidUntil = nil
        purchasedProductIDs = []
        lastError = nil
    }

    private func prepareSession() -> SaveEntitlementSession {
        let session = currentSession()
        if stateSession != session {
            resetForSessionChange()
            stateSession = session
        }
        return session
    }

    private func isCurrent(_ session: SaveEntitlementSession) -> Bool {
        !Task.isCancelled && currentSession() == session && stateSession == session
    }

    private var sessionChangedOutcome: PurchaseOutcome {
        .failed("Your Savvy account changed. Sign in to the purchasing account and restore purchases.")
    }

    private func reconcileEntitlements(for session: SaveEntitlementSession) async -> PurchaseOutcome {
        let transactions = await readEntitlements()
        guard isCurrent(session) else { return sessionChangedOutcome }
        let active = transactions.filter {
            SAVEProAccessPolicy.ProductID.all.contains($0.productID)
                && $0.revocationDate == nil
                && ($0.expirationDate.map { $0 > now() } ?? false)
        }
        purchasedProductIDs = Set(active.map(\.productID))
        guard !active.isEmpty else {
            registeredTier = nil
            return .failed("No active Savvy Pro subscription was found for this Apple account.")
        }
        var activated = false
        var failure: PurchaseOutcome = .failed("Purchases could not be restored. Please try again.")
        for transaction in active {
            guard isCurrent(session) else { return sessionChangedOutcome }
            let outcome = await activate(transaction, for: session)
            if outcome == .success { activated = true } else { failure = outcome }
        }
        guard isCurrent(session) else { return sessionChangedOutcome }
        return activated && serverVerifiedTier == .pro ? .success : failure
    }

    private func handle(verificationResult: VerificationResult<Transaction>) async {
        guard let transaction = SaveStoreTransaction(verificationResult) else { return }
        let session = prepareSession()
        guard session.owner != nil else { return }
        _ = await activate(transaction, for: session)
    }

    /// Internal seam also exercised with synthetic transactions by host checks.
    /// Production callers construct it only after StoreKit verifies the result.
    func activate(_ transaction: SaveStoreTransaction, for session: SaveEntitlementSession) async -> PurchaseOutcome {
        _ = prepareSession()
        guard session.owner != nil, isCurrent(session) else { return sessionChangedOutcome }
        guard SAVEProAccessPolicy.ProductID.all.contains(transaction.productID) else { return .unavailable }
        do {
            let response = try await registerTransaction(transaction.signedRepresentation)
            guard isCurrent(session) else { return sessionChangedOutcome }
            registeredTier = response.resolvedTier
            // This is only a short-lived offline display fallback. A server
            // verdict must not remain Pro indefinitely after expiry/refund.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let expiry = response.expiresAt.flatMap { formatter.date(from: $0) }
            registeredTierValidUntil = min(expiry ?? now(), now().addingTimeInterval(300))
            if transaction.revocationDate == nil, let expiry = transaction.expirationDate, expiry > now() {
                purchasedProductIDs.insert(transaction.productID)
            } else {
                purchasedProductIDs.remove(transaction.productID)
            }
            lastError = nil
            // Finish only after the server persisted the transaction for this
            // session. Failed activation remains unfinished and can be retried.
            await transaction.finish()
            guard isCurrent(session) else { return sessionChangedOutcome }
            return response.resolvedTier == .pro ? .success : .failed("This subscription is not active. Please check your Apple subscriptions.")
        } catch {
            guard isCurrent(session) else { return sessionChangedOutcome }
            // Preserve any earlier server-confirmed tier for this same session.
            // Never promote the local Apple observation to a granted tier.
            let message: String
            switch error {
            case SaveSubscriptionRegistrationError.ownershipConflict:
                message = "This subscription belongs to another Savvy account. Sign in to the account used for the purchase, then restore it."
            case SaveSubscriptionRegistrationError.accountBindingRequired:
                message = "This purchase is not linked to a Savvy account. Contact support to recover it; do not purchase again."
            default:
                message = "Your Apple purchase is saved, but Savvy could not activate it. Please try Restore Purchases."
            }
            lastError = message
            return .failed(message)
        }
    }
}
