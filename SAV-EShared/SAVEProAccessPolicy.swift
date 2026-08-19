import Foundation

/// Release-time monetization boundaries for the current public build.
///
/// These constants deliberately keep UI claims separate from the StoreKit
/// entitlement implementation. `enforcementEnabled` is the single switch that
/// turns a measured allowance into a refusal; it stays `false` until real usage
/// distribution and App Store Connect products exist (spec Slice 3).
enum SAVEProAccessPolicy {
    /// No paywall may present automatically at launch, ever.
    nonisolated static let showsAutomaticLaunchPaywall = false

    /// The saved-place memory loop is free forever. Locking it would stop the
    /// place-memory asset from compounding.
    nonisolated static let firstMapStampRequiresPurchase = false

    /// Capture, Review, Map Stamps, the private map, notebooks, search over
    /// saved places, deterministic parsing, and cache hits are never metered.
    nonisolated static let coreMemoryLoopIsFree = true

    /// Purchases are wired but products are not yet live in App Store Connect.
    /// Flip together with the App Store Connect product IDs below.
    nonisolated static let purchasingIsAvailable = false

    /// When `false`, an exhausted allowance may inform the UI but must never
    /// refuse an AI assist. Slice 1 ships with enforcement off by contract.
    nonisolated static let enforcementEnabled = false

    /// Product identifiers, reserved ahead of App Store Connect creation.
    enum ProductID {
        nonisolated static let annual = "com.wanderly.app.pro.annual"
        nonisolated static let monthly = "com.wanderly.app.pro.monthly"
        nonisolated static let all = [annual, monthly]
    }

    /// Required on any subscription paywall for App Store review.
    enum Legal {
        nonisolated static let termsURL = "https://sav-e-app.vercel.app/terms"
        nonisolated static let privacyURL = "https://sav-e-app.vercel.app/privacy"
        nonisolated static let manageSubscriptionsURL =
            "https://apps.apple.com/account/subscriptions"
    }
}

/// What the user is allowed to do right now.
///
/// The server is authoritative. `free` is the safe default and is what the app
/// falls back to whenever entitlement cannot be resolved, so a network failure
/// never strands a user mid-task.
nonisolated enum SaveProTier: String, Codable, Equatable, Sendable {
    case free
    case pro

    var allowsUnlimitedAIAssists: Bool { self == .pro }
}

/// The reason an AI assist was allowed or would be refused.
///
/// `wouldBeRefused` exists so Slice 1 can prove the decision path is correct
/// while `enforcementEnabled` is still false: the app computes the refusal,
/// records it, and then serves the request anyway.
nonisolated enum SaveAIAssistDecision: Equatable, Sendable {
    case allowed
    case allowedWarningNearLimit(remaining: Int)
    /// Enforcement is off, so this was served despite exhausting the allowance.
    case allowedEnforcementDisabled
    case refusedAllowanceExhausted

    var isRefusal: Bool { self == .refusedAllowanceExhausted }
}

/// Pure decision function shared by the app and its tests.
///
/// Kept free of StoreKit, networking, and SwiftUI so the policy can be tested
/// without a simulator or a purchase.
nonisolated enum SaveAIAssistGate {
    static func decide(
        tier: SaveProTier,
        usedUnits: Int?,
        limitUnits: Int,
        warningThresholdUnits: Int,
        enforcementEnabled: Bool = SAVEProAccessPolicy.enforcementEnabled
    ) -> SaveAIAssistDecision {
        // Pro is unmetered.
        guard !tier.allowsUnlimitedAIAssists else { return .allowed }

        // Metering unavailable or still warming up: fail open.
        guard let usedUnits, limitUnits > 0 else { return .allowed }

        let remaining = max(0, limitUnits - usedUnits)
        if remaining > 0 {
            if usedUnits >= warningThresholdUnits {
                return .allowedWarningNearLimit(remaining: remaining)
            }
            return .allowed
        }

        return enforcementEnabled ? .refusedAllowanceExhausted : .allowedEnforcementDisabled
    }
}
