import Foundation
import StoreKit

/// StoreKit 2 wrapper for SAV-E Pro.
///
/// Deliberate boundary: this type may *observe* Apple transactions and report
/// them. It may not decide entitlement on its own. Slice 2 adds
/// `POST /v0/entitlements/apple`, and from then on the server response is the
/// only thing that grants Pro. Until that exists, `verifiedTier` stays `.free`
/// unless a locally verified transaction is present AND purchasing is enabled,
/// which keeps sandbox builds honest.
@MainActor
@Observable
final class SaveStoreKitService {
    static let shared = SaveStoreKitService()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    /// Locally observed entitlement. Slice 2 replaces this with the verified
    /// server response; the property is intentionally not named `isPro` so no
    /// caller mistakes a client signal for granted access.
    var locallyObservedTier: SaveProTier {
        purchasedProductIDs.isEmpty ? .free : .pro
    }

    init() {
        // Transaction updates must be observed for the whole app lifetime,
        // including renewals and purchases made on another device. This is a
        // singleton that outlives every screen, so the task is never cancelled;
        // a `deinit` cancel would also be MainActor-isolated and cannot run
        // from a nonisolated deinit.
        updatesTask = Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verificationResult: update)
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        guard SAVEProAccessPolicy.purchasingIsAvailable else {
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
        guard SAVEProAccessPolicy.purchasingIsAvailable else { return .unavailable }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verificationResult: verification)
                return .success
            case .userCancelled:
                return .userCancelled
            case .pending:
                // Ask-to-buy / SCA. Entitlement arrives later via
                // Transaction.updates, so do not report success here.
                return .pending
            @unknown default:
                return .failed("Unrecognized purchase result.")
            }
        } catch {
            return .failed("Purchase could not be completed.")
        }
    }

    /// Required by App Store review on every subscription paywall.
    func restorePurchases() async -> PurchaseOutcome {
        guard SAVEProAccessPolicy.purchasingIsAvailable else { return .unavailable }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return .success
        } catch {
            return .failed("Restore could not be completed.")
        }
    }

    // MARK: - Entitlement observation

    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
    }

    private func handle(verificationResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verificationResult else {
            // An unverified transaction is not evidence of anything. Ignore it
            // rather than guessing.
            return
        }
        await refreshEntitlements()
        await transaction.finish()
    }
}
