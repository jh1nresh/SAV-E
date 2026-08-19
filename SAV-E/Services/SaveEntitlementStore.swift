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

    private(set) var tier: SaveProTier = .free
    private(set) var quota: SaveUsageQuotaPreview?
    private(set) var isRefreshing = false
    /// True when the server could not be reached, so the UI can avoid making
    /// confident claims about remaining allowance.
    private(set) var isFailingOpen = false

    private let storeKit: SaveStoreKitService
    private let loadQuota: () async throws -> SaveUsageQuotaPreview

    init(
        storeKit: SaveStoreKitService = .shared,
        loadQuota: @escaping () async throws -> SaveUsageQuotaPreview = {
            try await SupabaseService.shared.fetchUsageQuotaPreview()
        }
    ) {
        self.storeKit = storeKit
        self.loadQuota = loadQuota
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await storeKit.refreshEntitlements()

        do {
            let preview = try await loadQuota()
            quota = preview
            tier = preview.resolvedTier
            isFailingOpen = false
        } catch {
            // No server truth available. Keep working; do not downgrade a user
            // who may legitimately be Pro, and do not upgrade one who is not.
            quota = nil
            tier = storeKit.locallyObservedTier
            isFailingOpen = true
        }
    }

    // MARK: - Gate

    /// The decision for one AI assist. Callers must pass the result to
    /// `shouldPresentPaywall` rather than inspecting the tier directly, so the
    /// enforcement switch stays in one place.
    func decideAIAssist() -> SaveAIAssistDecision {
        guard let quota else { return .allowed }
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
