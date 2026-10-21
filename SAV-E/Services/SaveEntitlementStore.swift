import Foundation
import Observation

/// Single source of truth for "may this user run an AI assist right now".
///
/// Resolution order, strictest first:
///   1. server entitlement + server usage  (authoritative)
///   2. locally observed StoreKit entitlement, only as a UI hint
///   3. free tier, fail open
///
/// Failing open is deliberate. A network error must never block a user who is
/// mid-task, and it must never block someone who has already paid.
@MainActor
@Observable
final class SaveEntitlementStore {
    static let shared = SaveEntitlementStore()

    private var confirmedTier: SaveProTier = .free
    var tier: SaveProTier {
        guard stateSession == currentSession() else { return .free }
        return isFailingOpen ? (storeKit.serverVerifiedTier ?? .free) : confirmedTier
    }

    /// Local saved-place refusal may run only after this session received a
    /// server quota. Unresolved and fail-open stay off so a Pro account is
    /// not parked as free before `refresh()`.
    var hasAuthoritativeSavedPlaceTier: Bool {
        stateSession == currentSession() && quota != nil && !isFailingOpen
    }
    private(set) var quota: SaveUsageQuotaPreview?
    private(set) var isRefreshing = false
    /// True when the server could not be reached, so the UI can avoid making
    /// confident claims about remaining allowance.
    private(set) var isFailingOpen = false

    private let storeKit: SaveStoreKitService
    private let currentSession: () -> SaveEntitlementSession
    private var stateSession: SaveEntitlementSession?
    private var refreshID: UUID?
    private let loadQuota: () async throws -> SaveUsageQuotaPreview

    init(
        storeKit: SaveStoreKitService = .shared,
        currentSession: @escaping () -> SaveEntitlementSession = { .current },
        loadQuota: @escaping () async throws -> SaveUsageQuotaPreview = {
            try await SupabaseService.shared.fetchUsageQuotaPreview()
        }
    ) {
        self.storeKit = storeKit
        self.currentSession = currentSession
        self.loadQuota = loadQuota
    }

    // MARK: - Refresh

    func resetForSessionChange() {
        stateSession = nil
        refreshID = nil
        confirmedTier = .free
        quota = nil
        isRefreshing = false
        isFailingOpen = false
    }

    func refresh() async {
        let session = currentSession()
        if stateSession != session {
            resetForSessionChange()
            stateSession = session
        }
        guard session.owner != nil, !isRefreshing else { return }
        let operation = UUID()
        refreshID = operation
        isRefreshing = true
        defer {
            if refreshID == operation {
                isRefreshing = false
                refreshID = nil
            }
        }
        await storeKit.refreshEntitlements()
        guard isCurrent(session, operation: operation) else { return }
        do {
            let preview = try await loadQuota()
            guard isCurrent(session, operation: operation) else { return }
            quota = preview
            confirmedTier = preview.resolvedTier
            isFailingOpen = false
        } catch {
            guard isCurrent(session, operation: operation) else { return }
            quota = nil
            // A local Apple observation is not backend authorization, and a
            // previous account's cached Pro tier must never cross this boundary.
            confirmedTier = .free
            isFailingOpen = true
        }
    }

    private func isCurrent(_ session: SaveEntitlementSession, operation: UUID) -> Bool {
        !Task.isCancelled && currentSession() == session && stateSession == session && refreshID == operation
    }

    // MARK: - Gate

    /// The decision for one AI assist. Callers must pass the result to
    /// `shouldPresentPaywall` rather than inspecting the tier directly, so the
    /// enforcement switch stays in one place.
    func decideAIAssist() -> SaveAIAssistDecision {
        guard stateSession == currentSession(), let quota else { return .allowed }
        return SaveAIAssistGate.decide(
            tier: tier,
            usedUnits: quota.usedUnits,
            limitUnits: quota.limitUnits,
            warningThresholdUnits: quota.warningThresholdUnits
        )
    }

    /// A paywall may only appear as a *reaction* to a refusal, and only once the
    /// user has produced a confirmed Map Stamp. Both conditions are checked here
    /// so no call site can bypass the trigger policy.
    func shouldPresentPaywall(
        for decision: SaveAIAssistDecision,
        hasConfirmedMapStamp: Bool
    ) -> Bool {
        // The value proof must exist before pricing is ever shown.
        guard hasConfirmedMapStamp else { return false }
        return decision.isRefusal
    }

    /// Passive Passport entry. Still requires a confirmed Map Stamp so pricing
    /// never appears before the place-memory loop has worked once. Does not
    /// require an AI refusal — the user opted in.
    func shouldPresentPaywallFromPassport(hasConfirmedMapStamp: Bool) -> Bool {
        hasConfirmedMapStamp
    }
}

/// Server-reported usage window. Mirrors `buildUsageQuotaPreview` in
/// `backend/src/usageQuota.ts`.
nonisolated struct SaveUsageQuotaPreview: Codable, Equatable, Sendable {
    let policyVersion: String
    let periodStart: String
    let periodEnd: String
    let limitUnits: Int
    let warningThresholdUnits: Int
    let usedUnits: Int?
    let remainingUnits: Int?
    let state: String
    let enforced: Bool
    let meteringAvailable: Bool
    let betaAccessContinues: Bool
    /// Added in Slice 2. Absent responses resolve to `.free`, which is the safe
    /// default and keeps this build compatible with the deployed backend.
    let tier: String?

    enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case limitUnits = "limit_units"
        case warningThresholdUnits = "warning_threshold_units"
        case usedUnits = "used_units"
        case remainingUnits = "remaining_units"
        case state
        case enforced
        case meteringAvailable = "metering_available"
        case betaAccessContinues = "beta_access_continues"
        case tier
    }

    var resolvedTier: SaveProTier {
        SaveProTier(rawValue: tier ?? "") ?? .free
    }

    var progress: Double {
        guard let usedUnits, limitUnits > 0 else { return 0 }
        return min(max(Double(usedUnits) / Double(limitUnits), 0), 1)
    }
}

/// Result of server-side Apple transaction verification.
///
/// Mirrors the `/v0/entitlements/apple` response. Every field is server-decided;
/// the client sent only the opaque signed transaction.
nonisolated struct SaveEntitlementResponse: Codable, Equatable, Sendable {
    let tier: String
    let status: String
    let productID: String
    let expiresAt: String?
    let environment: String

    enum CodingKeys: String, CodingKey {
        case tier
        case status
        case productID = "product_id"
        case expiresAt = "expires_at"
        case environment
    }

    var resolvedTier: SaveProTier {
        SaveProTier(rawValue: tier) ?? .free
    }
}
