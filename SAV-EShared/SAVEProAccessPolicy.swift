import Foundation

/// Release-time monetization boundaries for the current public build.
///
/// These constants deliberately keep UI claims separate from the StoreKit
/// entitlement implementation. `enforcementEnabled` is the single switch that
/// turns a measured allowance into a refusal; it stays `false` until real usage
/// distribution and App Store Connect products exist (spec Slice 3).
///
/// Launch posture (2026-09-04): free download, purchase path ready, trigger
/// later. Do not flip these into a launch/onboarding hard paywall. Sequence:
/// ASC products → `purchasingIsAvailable` → restore model-quota refusal →
/// `enforcementEnabled`. See `specs/2026-09-04-launch-purchase-path-trigger-later-v0.md`.
enum SAVEProAccessPolicy {
    /// No paywall may present automatically at launch, ever.
    nonisolated static let showsAutomaticLaunchPaywall = false

    /// Free: 50 places. Stated from day one and never lowered. Pro
    /// (`SaveProTier.pro` from the existing entitlement check) is unlimited.
    /// Existing accounts already over 50 keep every confirmed Map Stamp; only
    /// new saves are gated.
    nonisolated static let freeSavedPlaceLimit = 50

    /// The first Map Stamp does not require purchase. Free: 50 places.
    nonisolated static let firstMapStampRequiresPurchase = false

    /// Capture, Review, the private map, notebooks, search, deterministic
    /// parsing, and cache hits stay free. Confirmed Map Stamps on the free
    /// tier are capped at `freeSavedPlaceLimit`.
    nonisolated static let coreMemoryLoopIsFree = true

    /// Purchases are wired but products are not yet live in App Store Connect.
    /// Flip alone after ASC products attach — not with `enforcementEnabled`.
    nonisolated static let purchasingIsAvailable = false

    /// When `false`, an exhausted allowance may inform the UI but must never
    /// refuse an AI assist. Stay off until a real model-quota refusal surface
    /// ships (Ask or equivalent). Slice 1 contract.
    nonisolated static let enforcementEnabled = false

    /// Passive Passport Pro entry. Purchasing must be live, and the user must
    /// already have one confirmed Map Stamp so pricing never precedes place
    /// memory. Kept on the policy (not `SaveEntitlementStore`) so Passport
    /// source stays free of storefront types.
    nonisolated static func shouldOfferProFromPassport(hasConfirmedMapStamp: Bool) -> Bool {
        purchasingIsAvailable && hasConfirmedMapStamp
    }

    /// Product identifiers, reserved ahead of App Store Connect creation.
    enum ProductID {
        nonisolated static let annual = "savvy.pro.annual"
        nonisolated static let monthly = "savvy.pro.monthly"
        nonisolated static let all = [annual, monthly]
    }

    /// Required on any subscription paywall for App Store review.
    enum Legal {
        nonisolated static let termsURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
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

    /// Pro does not raise model allowance. Unlimited saved places is the only
    /// Pro benefit.
    var allowsUnlimitedAIAssists: Bool { false }
    var allowsUnlimitedSavedPlaces: Bool { self == .pro }
}

/// Why a new confirmed Map Stamp was allowed or parked in Review (Unplaced).
nonisolated enum SavePlaceLimitDecision: Equatable, Sendable {
    case allowed
    case overFreeLimit
}

/// The 51st free save is not dropped. Callers park it in the Review inbox
/// (the existing Unplaced queue) and present `SaveProPaywallView`.
nonisolated enum SavePlaceLimitError: LocalizedError, Equatable, Sendable {
    case parkedInUnplacedInbox

    var errorDescription: String? {
        "Free: 50 places"
    }

    /// Server `/places` and `/v0/shared-posts/:id/save` return this after the
    /// transactional count. 403 is otherwise remapped to not-authenticated.
    static func matchesServerResponse(status: Int, body: String) -> Bool {
        (status == 403 || status == 409 || status == 422)
            && (body.contains("over_free_limit") || body.contains("saved_place_limit"))
    }

    static func fromServerResponse(status: Int, body: String) -> SavePlaceLimitError? {
        matchesServerResponse(status: status, body: body) ? .parkedInUnplacedInbox : nil
    }
}

/// Pure saved-place cap shared by the app, Share Extension, and tests.
nonisolated enum SavePlaceLimitGate {
    static func decide(
        tier: SaveProTier,
        savedPlaceCount: Int,
        limit: Int = SAVEProAccessPolicy.freeSavedPlaceLimit
    ) -> SavePlaceLimitDecision {
        guard !tier.allowsUnlimitedSavedPlaces else { return .allowed }
        return savedPlaceCount < limit ? .allowed : .overFreeLimit
    }

    /// `nil` means Pro / unlimited. Otherwise the number of new Map Stamps
    /// still allowed on the free tier.
    static func remainingNewSaves(
        tier: SaveProTier,
        savedPlaceCount: Int,
        limit: Int = SAVEProAccessPolicy.freeSavedPlaceLimit
    ) -> Int? {
        guard !tier.allowsUnlimitedSavedPlaces else { return nil }
        return max(0, limit - savedPlaceCount)
    }
}

/// App Group handoff so the Share Extension can honor the cap without UI
/// and so the next app launch can open the paywall.
enum SavePlaceLimitHandoff {
    nonisolated static let pendingPaywallKey = "save.pendingSavedPlaceLimitPaywall"
    nonisolated static let cachedTierKey = "save.cachedProTier"
    nonisolated static let cachedCountKey = "save.cachedSavedPlaceCount"

#if DEBUG
    nonisolated(unsafe) static var testDefaults: UserDefaults?
#endif

    nonisolated static func makeDefaults() -> UserDefaults {
#if DEBUG
        if let testDefaults { return testDefaults }
#endif
        // Same App Group as `SAVEProductionConfig.appGroupSuiteName`. Kept as a
        // literal so the host entitlement checker can compile this file alone.
        return UserDefaults(suiteName: "group.com.wanderly.app") ?? .standard
    }

    nonisolated static func syncCache(
        tier: SaveProTier,
        savedPlaceCount: Int,
        defaults: UserDefaults = makeDefaults()
    ) {
        defaults.set(tier.rawValue, forKey: cachedTierKey)
        defaults.set(savedPlaceCount, forKey: cachedCountKey)
    }

    /// Missing cache fails open so a cold extension still writes the item.
    /// The main app re-checks on pending-place import.
    nonisolated static func cachedDecision(
        defaults: UserDefaults = makeDefaults()
    ) -> SavePlaceLimitDecision {
        guard defaults.object(forKey: cachedCountKey) != nil else { return .allowed }
        let tier = SaveProTier(rawValue: defaults.string(forKey: cachedTierKey) ?? "") ?? .free
        return SavePlaceLimitGate.decide(
            tier: tier,
            savedPlaceCount: defaults.integer(forKey: cachedCountKey)
        )
    }

    nonisolated static let paywallRequestedNotification = Notification.Name("save.placeLimitPaywallRequested")

    nonisolated static func markPaywallPending(
        defaults: UserDefaults = makeDefaults(),
        notify: Bool = true
    ) {
        defaults.set(true, forKey: pendingPaywallKey)
        // Nested social sheets present the paywall themselves. Skip the
        // notification so ContentView does not try to present underneath.
        guard notify else { return }
        NotificationCenter.default.post(name: paywallRequestedNotification, object: nil)
    }

    @discardableResult
    nonisolated static func consumePaywallPending(defaults: UserDefaults = makeDefaults()) -> Bool {
        let pending = defaults.bool(forKey: pendingPaywallKey)
        if pending { defaults.set(false, forKey: pendingPaywallKey) }
        return pending
    }
}

/// Where a Share Extension ready-to-save place goes when the free cap is full.
nonisolated enum SaveShareExtensionPlaceDestination: Equatable, Sendable {
    case pendingMapStamp
    case unplacedInbox

    static func resolve(
        cached: SavePlaceLimitDecision
    ) -> SaveShareExtensionPlaceDestination {
        cached == .overFreeLimit ? .unplacedInbox : .pendingMapStamp
    }
}

/// Distinct result for a social-post save that hit the free cap.
nonisolated enum SharedPostSaveOutcome: Equatable, Sendable {
    case saved
    case parkedAtFreeLimit
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

    /// Exhausted allowance is a notice whether or not enforcement refuses the
    /// request. Pro does not raise this limit.
    var showsAllowanceNotice: Bool {
        switch self {
        case .refusedAllowanceExhausted, .allowedEnforcementDisabled:
            return true
        case .allowed, .allowedWarningNearLimit:
            return false
        }
    }
}

/// Neutral notice when monthly model allowance is gone. Not a paywall.
nonisolated enum SaveAIAssistUserCopy {
    static let exhaustedEnglish = "This month's model allowance is used up. Try again next period."
    static let exhaustedTraditionalChinese = "這個月的模型額度已用完。下個週期再試。"
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
        // Pro does not unlock extra model allowance.
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
