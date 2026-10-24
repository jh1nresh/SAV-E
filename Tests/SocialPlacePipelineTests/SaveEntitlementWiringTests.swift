import Foundation
#if !SAVE_ENTITLEMENT_HOST_CHECK
import XCTest
@testable import SAVE

/// Client-side entitlement contract.
///
/// The rule these tests defend: the app may *observe* a purchase, but only the
/// server may *grant* one. Every case here exists because getting it wrong
/// either gives away Pro for free or locks out someone who paid.
final class SaveEntitlementWiringTests: XCTestCase {

    // MARK: - Response decoding

    func testEntitlementResponseDecodesServerVerdict() throws {
        let json = """
        {
          "tier": "pro",
          "status": "active",
          "product_id": "savvy.pro.annual",
          "expires_at": "2027-08-19T00:00:00.000Z",
          "environment": "Sandbox"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SaveEntitlementResponse.self, from: json)
        XCTAssertEqual(response.resolvedTier, .pro)
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.productID, "savvy.pro.annual")
        XCTAssertEqual(response.environment, "Sandbox")
    }

    /// An unrecognized tier string must not be optimistically treated as Pro.
    func testUnknownTierStringResolvesToFree() throws {
        let json = """
        {
          "tier": "platinum",
          "status": "active",
          "product_id": "savvy.pro.annual",
          "expires_at": null,
          "environment": "Production"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SaveEntitlementResponse.self, from: json)
        XCTAssertEqual(response.resolvedTier, .free)
    }

    // MARK: - Tier resolution

    @MainActor
    func testServerQuotaIsAuthoritativeWhenReachable() async {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "pro", used: 12) })
        await store.refresh()

        XCTAssertEqual(store.tier, .pro)
        XCTAssertFalse(store.isFailingOpen)
        XCTAssertEqual(store.quota?.usedUnits, 12)
    }

    @MainActor
    func testUnrecognizedQuotaTierCannotEnableLocalSavedPlaceRefusal() async {
        for value: String? in [nil, "", "platinum", "FREE"] {
            let store = Self.makeStore(loadQuota: { Self.quota(tier: value, used: 0) })
            await store.refresh()
            XCTAssertFalse(store.hasAuthoritativeSavedPlaceTier)
        }
        for value in ["free", "pro"] {
            let store = Self.makeStore(loadQuota: { Self.quota(tier: value, used: 0) })
            await store.refresh()
            XCTAssertTrue(store.hasAuthoritativeSavedPlaceTier)
        }
    }

    /// The server saying "free" must win even if a stale local receipt exists.
    /// Otherwise a refunded or expired subscription would keep working.
    @MainActor
    func testServerFreeVerdictOverridesLocalSignal() async {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 3) })
        await store.refresh()

        XCTAssertEqual(store.tier, .free)
        XCTAssertFalse(store.isFailingOpen)
    }

    /// Network failure must not strand the user, and must not invent Pro.
    @MainActor
    func testUnreachableServerFailsOpenWithoutInventingPro() async {
        let store = Self.makeStore(loadQuota: { throw URLError(.notConnectedToInternet) })
        await store.refresh()

        XCTAssertEqual(store.tier, .free, "an offline client must not grant itself Pro")
        XCTAssertTrue(store.isFailingOpen)
        XCTAssertNil(store.quota)
        XCTAssertFalse(store.hasAuthoritativeSavedPlaceTier, "fail-open must not refuse saves locally")
    }

    @MainActor
    func testAuthoritativeSavedPlaceTierRequiresASuccessfulRefresh() async {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "pro", used: 1) })
        XCTAssertFalse(store.hasAuthoritativeSavedPlaceTier)
        await store.refresh()
        XCTAssertTrue(store.hasAuthoritativeSavedPlaceTier)
        XCTAssertEqual(store.tier, .pro)
    }

    // MARK: - Paywall trigger policy

    /// The value proof gate. A paywall before the first Map Stamp asks someone
    /// to pay for something they have not seen work.
    @MainActor
    func testPaywallNeverPresentsBeforeFirstMapStamp() {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 0) })

        XCTAssertFalse(
            store.shouldPresentPaywall(for: .refusedAllowanceExhausted, hasConfirmedMapStamp: false),
            "a refusal must not surface a paywall until the user has seen the product work"
        )
        XCTAssertFalse(
            store.shouldPresentPaywall(for: .refusedAllowanceExhausted, hasConfirmedMapStamp: true),
            "exhausted model allowance is not a Pro sales trigger"
        )
    }

    /// Passport is a passive entry, but it still needs the Map Stamp proof.
    /// Policy owns the Passport UI gate (keeps storefront types out of
    /// ProfileView); the store method remains the shared stamp-only check.
    @MainActor
    func testPassportPaywallRequiresConfirmedMapStamp() {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 0) })

        XCTAssertFalse(
            store.shouldPresentPaywallFromPassport(hasConfirmedMapStamp: false),
            "Passport must not open Pro before the place-memory loop has worked once"
        )
        XCTAssertTrue(store.shouldPresentPaywallFromPassport(hasConfirmedMapStamp: true))

        // Launch posture: purchasing is off, so even a stamped account sees no Pro row.
        XCTAssertFalse(SAVEProAccessPolicy.shouldOfferProFromPassport(hasConfirmedMapStamp: false))
        XCTAssertFalse(SAVEProAccessPolicy.shouldOfferProFromPassport(hasConfirmedMapStamp: true))
    }

    /// Only a refusal opens the reactive paywall. Warnings and allowances must not.
    @MainActor
    func testOnlyRefusalOpensThePaywall() {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 0) })

        for decision: SaveAIAssistDecision in [
            .allowed,
            .allowedWarningNearLimit(remaining: 2),
            .allowedEnforcementDisabled,
        ] {
            XCTAssertFalse(
                store.shouldPresentPaywall(for: decision, hasConfirmedMapStamp: true),
                "\(decision) must not interrupt the user with a paywall"
            )
        }
    }

    /// With enforcement off, an exhausted free user is still served, so the
    /// paywall cannot appear. This is the Slice 1 promise held at the seam.
    @MainActor
    func testExhaustedFreeUserIsServedWhileEnforcementIsOff() async {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 20, limit: 20) })
        await store.refresh()

        let decision = store.decideAIAssist()
        XCTAssertEqual(decision, .allowedEnforcementDisabled)
        XCTAssertFalse(decision.isRefusal)
        XCTAssertFalse(store.shouldPresentPaywall(for: decision, hasConfirmedMapStamp: true))
    }

    /// Pro does not raise model allowance. Exhausted quota is a notice, not a paywall.
    @MainActor
    func testProUserSharesModelAllowanceAndNeverOpensPaywallForIt() async {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "pro", used: 20, limit: 20) })
        await store.refresh()

        XCTAssertEqual(store.tier, .pro)
        XCTAssertEqual(store.decideAIAssist(), .allowedEnforcementDisabled)
        XCTAssertFalse(store.shouldPresentPaywall(for: store.decideAIAssist(), hasConfirmedMapStamp: true))
        XCTAssertNil(store.allowanceNotice())
    }

    @MainActor
    func testExhaustedAllowanceShowsNeutralNoticeWithoutPaywall() async {
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 20, limit: 20) })
        await store.refresh()

        let decision = SaveAIAssistGate.decide(
            tier: .free, usedUnits: 20, limitUnits: 20, warningThresholdUnits: 15,
            enforcementEnabled: true
        )
        XCTAssertEqual(decision, .refusedAllowanceExhausted)
        XCTAssertFalse(store.shouldPresentPaywall(for: decision, hasConfirmedMapStamp: true))
        XCTAssertEqual(
            SaveEntitlementStore.exhaustedAllowanceMessage(language: .english),
            "This month's model allowance is used up. Try again next period."
        )
        XCTAssertEqual(
            SaveEntitlementStore.exhaustedAllowanceMessage(language: .traditionalChinese),
            "這個月的模型額度已用完。下個週期再試。"
        )
        XCTAssertFalse(SaveAIAssistUserCopy.exhaustedEnglish.contains("AI"))
        XCTAssertFalse(SaveAIAssistUserCopy.exhaustedEnglish.localizedCaseInsensitiveContains("assist"))
        XCTAssertFalse(SaveAIAssistUserCopy.exhaustedTraditionalChinese.contains("AI"))
        XCTAssertFalse(SaveAIAssistUserCopy.exhaustedTraditionalChinese.contains("次數"))
    }

    // MARK: - Source-level guarantees

    /// The client must post only the opaque signed transaction. If it ever
    /// started sending its own tier or product, the server could be talked
    /// into granting Pro.
    func testClientSendsOnlyTheOpaqueSignedTransaction() throws {
        let service = try source(at: "SAV-E/Services/SupabaseService.swift")
        let storeKit = try source(at: "SAV-E/Services/SaveStoreKitService.swift")

        XCTAssertTrue(service.contains("\"signed_transaction\": signedTransaction"))
        XCTAssertTrue(service.contains("/v0/entitlements/apple"))
        for forbidden in ["\"tier\":", "\"is_pro\"", "\"product_id\": product"] {
            XCTAssertFalse(
                service.contains("registerAppleTransaction") && service.contains(forbidden),
                "the client must not assert \(forbidden) to the entitlement route"
            )
        }

        // A failed registration must not finish the transaction, so StoreKit
        // redelivers it rather than silently losing a paid purchase.
        XCTAssertTrue(storeKit.contains("jwsRepresentation"))
        XCTAssertTrue(storeKit.contains("registeredTier = nil"))
    }

    /// Passport Pro entry must reuse the shared stamp gate so a zero-Stamp
    /// account cannot open the wall from Settings alone. Gate lives on the
    /// access policy so Passport never imports entitlement storefront types.
    func testPassportProEntryUsesSharedStampGate() throws {
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let policy = try source(at: "SAV-EShared/SAVEProAccessPolicy.swift")
        XCTAssertTrue(profile.contains("if !passportPlaces.isEmpty"))
        XCTAssertTrue(profile.contains("showProPaywall = true"))
        XCTAssertTrue(profile.contains("SaveProPaywallView(trigger: .passport)"))
        XCTAssertFalse(profile.contains("SaveEntitlementStore"))
        XCTAssertTrue(policy.contains("shouldOfferProFromPassport"))
        XCTAssertTrue(policy.contains("purchasingIsAvailable && hasConfirmedMapStamp"))
    }

    /// B7: Settings opens the informational paywall after a Map Stamp exists.
    /// The row is not gated on StoreKit, and exhausted AI quota is not this sheet.
    func testSettingsProRowOpensPassportPaywallWithoutPurchaseGate() throws {
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(profile.contains("if !passportPlaces.isEmpty"))
        XCTAssertTrue(profile.contains("accessibilityIdentifier: \"profile.pro\""))
        XCTAssertTrue(
            profile.contains(".accessibilityElement(children: .contain)"),
            "CI 39703881022: parent identifier flattened Savvy Pro off profile.pro"
        )
        XCTAssertTrue(profile.contains("SaveProPaywallView(trigger: .passport)"))
        XCTAssertFalse(profile.contains("shouldOfferProFromPassport"))
        XCTAssertFalse(profile.contains("if SAVEProAccessPolicy.purchasingIsAvailable"))
        XCTAssertFalse(profile.contains("SaveProPaywallView(trigger: .savedPlaceLimit)"))
        XCTAssertFalse(profile.contains("SaveProPaywallView(trigger: .aiAssistExhausted)"))
        XCTAssertFalse(content.contains("aiAssistExhausted"))
        XCTAssertTrue(content.contains("SaveProPaywallView(trigger: .savedPlaceLimit)"))
    }

    /// B7: exhausted AI quota stays a neutral analysis notice, never the Pro wall.
    @MainActor
    func testExhaustedAIQuotaIsANeutralMessageNotThePaywall() async throws {
        XCTAssertFalse(SAVEProAccessPolicy.enforcementEnabled)
        let store = Self.makeStore(loadQuota: { Self.quota(tier: "free", used: 20, limit: 20) })
        await store.refresh()

        let decision = store.decideAIAssist()
        XCTAssertEqual(decision, .allowedEnforcementDisabled)
        XCTAssertFalse(decision.isRefusal)
        XCTAssertFalse(store.shouldPresentPaywall(for: decision, hasConfirmedMapStamp: true))
        XCTAssertFalse(store.shouldPresentPaywall(for: .refusedAllowanceExhausted, hasConfirmedMapStamp: false))

        let notice = try XCTUnwrap(ShareAnalysisError.usageLimit.errorDescription)
        XCTAssertTrue(notice.contains("usage limit") || notice.contains("用量上限"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("paywall"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("Savvy Pro"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("unlimited saved places"))
    }

    func testSessionStartupRefreshesEntitlementBeforeLocalCap() throws {
        let auth = try source(at: "SAV-E/Services/PrivyAuthService.swift")
        let map = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        XCTAssertTrue(auth.contains("SaveEntitlementStore.shared.refresh()"))
        XCTAssertTrue(map.contains("hasAuthoritativeSavedPlaceTier"))
        XCTAssertTrue(map.contains("entitlementResolvedProvider"))
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        XCTAssertTrue(paywall.contains("paywall.retry"))
        XCTAssertFalse(paywall.contains("paywall.retryProducts"))
        XCTAssertTrue(paywall.contains("if trigger == .savedPlaceLimit"))
        XCTAssertTrue(paywall.contains("--uitest-show-paywall-retry"))
        XCTAssertTrue(paywall.contains("func retryOffers(message: String)"))
    }

    @MainActor
    func testPurchaseRestoreAndSessionIsolation() async throws {
        let count = try await SaveEntitlementRegressionChecks.run()
        XCTAssertGreaterThanOrEqual(count, 12)
    }

    @MainActor
    private static func makeStore(loadQuota: @escaping () async throws -> SaveUsageQuotaPreview) -> SaveEntitlementStore {
        let session = SaveEntitlementSession(generation: 1, owner: "fixture-owner")
        let storeKit = SaveStoreKitService(currentSession: { session }, readEntitlements: { [] }, observeUpdates: false)
        return SaveEntitlementStore(storeKit: storeKit, currentSession: { session }, loadQuota: loadQuota)
    }

    // MARK: - Helpers

    private static func quota(tier: String?, used: Int, limit: Int = 20) -> SaveUsageQuotaPreview {
        SaveUsageQuotaPreview(
            policyVersion: "ai-assists-beta-v0",
            periodStart: "2026-08-01T00:00:00.000Z",
            periodEnd: "2026-09-01T00:00:00.000Z",
            limitUnits: limit,
            warningThresholdUnits: max(1, Int(Double(limit) * 0.75)),
            usedUnits: used,
            remainingUnits: max(0, limit - used),
            state: "available",
            enforced: false,
            meteringAvailable: true,
            betaAccessContinues: true,
            tier: tier
        )
    }

    private func source(at relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

#endif

/// Shared behavioral cases run against the real service types in XCTest and in
/// the host-only verifier. All StoreKit/network inputs are synthetic; neither
/// route opens an Apple session or sends a provider/payment request.
@MainActor
enum SaveEntitlementRegressionChecks {
    struct Failure: Error { let message: String }
    @MainActor final class State {
        var session = SaveEntitlementSession(generation: 1, owner: "owner-a")
        var registrations = 0
        var finished = 0
        var now = Date()
    }
    @MainActor final class Gate<Value: Sendable> {
        var continuation: CheckedContinuation<Value, Never>?
        var waiting: CheckedContinuation<Void, Never>?
        var started = false
        func value() async -> Value {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started = true
                waiting?.resume()
                waiting = nil
            }
        }
        func waitUntilStarted() async {
            if started { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func resolve(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    }
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func quota(_ tier: String) -> SaveUsageQuotaPreview {
        SaveUsageQuotaPreview(policyVersion: "fixture", periodStart: "", periodEnd: "", limitUnits: 20,
            warningThresholdUnits: 15, usedUnits: 0, remainingUnits: 20, state: "available", enforced: false,
            meteringAvailable: true, betaAccessContinues: true, tier: tier)
    }
    static func run() async throws -> Int {
        var cases = 0
        let state = State()
        let transaction = SaveStoreTransaction(productID: SAVEProAccessPolicy.ProductID.annual,
            signedRepresentation: "synthetic-verified-jws", expirationDate: .distantFuture, revocationDate: nil,
            finish: { await MainActor.run { state.finished += 1 } })
        let pro = SaveEntitlementResponse(tier: "pro", status: "active", productID: transaction.productID,
            expiresAt: "2999-01-01T00:00:00.000Z", environment: "Sandbox")
        let service = SaveStoreKitService(registerTransaction: { jws in
            try check(jws == transaction.signedRepresentation, "only the signed transaction may be posted")
            state.registrations += 1; return pro
        }, currentSession: { state.session }, readEntitlements: { [transaction] },
            synchronizePurchases: {}, purchasingAvailable: { true }, observeUpdates: false)
        let restored = await service.restorePurchases()
        try check(restored == .success && state.registrations == 1 && state.finished == 1 && service.serverVerifiedTier == .pro,
            "restore must reconcile with backend before success and finish")
        cases += 1

        let failed = SaveStoreKitService(registerTransaction: { _ in throw URLError(.notConnectedToInternet) },
            currentSession: { state.session }, readEntitlements: { [transaction] }, synchronizePurchases: {},
            purchasingAvailable: { true }, observeUpdates: false)
        let finishBeforeFailure = state.finished
        let outcome = await failed.activate(transaction, for: state.session)
        try check(outcome != .success && state.finished == finishBeforeFailure && failed.serverVerifiedTier == nil,
            "failed backend activation must not succeed, grant Pro or finish")
        cases += 1
        let failedRestore = await failed.restorePurchases()
        try check(failedRestore != .success && state.finished == finishBeforeFailure,
            "restore backend outage must remain retryable")
        cases += 1
        let offlineStore = SaveEntitlementStore(storeKit: failed, currentSession: { state.session },
            loadQuota: { throw URLError(.notConnectedToInternet) })
        await offlineStore.refresh()
        try check(failed.locallyObservedTier == .pro && offlineStore.tier == .free && offlineStore.isFailingOpen,
            "local Apple ownership must not become backend authorization offline")
        cases += 1

        for kind in ["empty", "expired", "revoked", "unknown"] {
            let invalid = SaveStoreTransaction(productID: kind == "unknown" ? "not-savvy" : transaction.productID,
                signedRepresentation: "invalid-fixture", expirationDate: kind == "expired" ? .distantPast : .distantFuture,
                revocationDate: kind == "revoked" ? Date() : nil, finish: { fatalError("must not finish filtered transaction") })
            let empty = SaveStoreKitService(registerTransaction: { _ in throw Failure(message: "must not register filtered transaction") },
                currentSession: { state.session }, readEntitlements: { kind == "empty" ? [] : [invalid] },
                synchronizePurchases: {}, purchasingAvailable: { true }, observeUpdates: false)
            let result = await empty.restorePurchases()
            try check(result != .success && empty.purchasedProductIDs.isEmpty, "\(kind) must not report restored")
            cases += 1
        }

        let activationGate = Gate<SaveEntitlementResponse>()
        let delayed = SaveStoreKitService(registerTransaction: { _ in await activationGate.value() },
            currentSession: { state.session }, readEntitlements: { [] }, observeUpdates: false)
        let oldSession = state.session
        let pending = Task { await delayed.activate(transaction, for: oldSession) }
        await activationGate.waitUntilStarted()
        state.session = SaveEntitlementSession(generation: 2, owner: "owner-b")
        delayed.resetForSessionChange()
        activationGate.resolve(pro)
        let stale = await pending.value
        try check(stale != .success && delayed.serverVerifiedTier == nil && state.finished == finishBeforeFailure,
            "old-account activation must not mutate the new account or finish its receipt")
        try check(service.serverVerifiedTier == nil && service.locallyObservedTier == .free,
            "cached account-a authorization must be invisible to account-b even before refresh")
        cases += 1

        let quotaGate = Gate<SaveUsageQuotaPreview>()
        let local = SaveStoreKitService(currentSession: { state.session }, readEntitlements: { [] }, observeUpdates: false)
        var calls = 0
        let store = SaveEntitlementStore(storeKit: local, currentSession: { state.session }, loadQuota: {
            calls += 1
            if calls == 1 { return await quotaGate.value() }
            return quota("free")
        })
        let oldRefresh = Task { await store.refresh() }
        await quotaGate.waitUntilStarted()
        state.session = SaveEntitlementSession(generation: 3, owner: "owner-c")
        store.resetForSessionChange()
        await store.refresh()
        quotaGate.resolve(quota("pro"))
        await oldRefresh.value
        try check(calls == 2 && store.tier == .free && store.quota?.resolvedTier == .free && !store.isRefreshing,
            "old quota response must not overwrite a completed new-account refresh")
        cases += 1

        let logoutGate = Gate<SaveEntitlementResponse>()
        let signingOut = SaveStoreKitService(registerTransaction: { _ in await logoutGate.value() },
            currentSession: { state.session }, readEntitlements: { [] }, observeUpdates: false)
        let logoutSession = state.session
        let logoutTask = Task { await signingOut.activate(transaction, for: logoutSession) }
        await logoutGate.waitUntilStarted()
        state.session = SaveEntitlementSession(generation: 4, owner: nil)
        signingOut.resetForSessionChange()
        logoutGate.resolve(pro)
        let loggedOut = await logoutTask.value
        try check(loggedOut != .success && signingOut.serverVerifiedTier == nil && signingOut.purchasedProductIDs.isEmpty,
            "logout must discard pending subscription activation")
        cases += 1

        let signedOut = SaveStoreKitService(registerTransaction: { _ in throw Failure(message: "signed-out activation must not call backend") },
            currentSession: { state.session }, readEntitlements: { [transaction] },
            synchronizePurchases: { throw Failure(message: "signed-out restore must not open Apple sync") },
            purchasingAvailable: { true }, observeUpdates: false)
        let noSession = await signedOut.restorePurchases()
        try check(noSession != .success, "restore requires a Savvy account")
        cases += 1
        state.session = SaveEntitlementSession(generation: 5, owner: "owner-a")
        let tokenGate = Gate<UUID>()
        let tokenService = SaveStoreKitService(currentSession: { state.session }, readEntitlements: { [] },
            observeUpdates: false, loadAccountToken: { await tokenGate.value() })
        let tokenSession = state.session
        let tokenTask = Task { try await tokenService.purchaseAccountToken(for: tokenSession) }
        await tokenGate.waitUntilStarted()
        state.session = SaveEntitlementSession(generation: 6, owner: "owner-b")
        tokenGate.resolve(UUID())
        do {
            _ = try await tokenTask.value
            throw Failure(message: "account-a token must not open a purchase for account-b")
        } catch is CancellationError { }
        cases += 1
        let expectedToken = UUID()
        let boundService = SaveStoreKitService(currentSession: { state.session }, readEntitlements: { [] },
            observeUpdates: false, loadAccountToken: { expectedToken })
        let receivedToken = try await boundService.purchaseAccountToken(for: state.session)
        try check(receivedToken == expectedToken, "use the backend-issued token without generating a different account identity")
        cases += 1

        for code in ["subscription_owner_conflict", "subscription_account_binding_required"] {
            let error = SaveSubscriptionRegistrationError.from(status: 409, body: Data("{\"code\":\"\(code)\"}".utf8))
            try check(error != nil, "known binding errors must map to actionable purchase outcomes")
            let conflictService = SaveStoreKitService(registerTransaction: { _ in throw error! },
                currentSession: { state.session }, readEntitlements: { [transaction] },
                synchronizePurchases: {}, purchasingAvailable: { true }, observeUpdates: false)
            let before = state.finished
            let conflictResult = await conflictService.restorePurchases()
            try check(conflictResult != .success && state.finished == before && conflictService.serverVerifiedTier == nil,
                "wrong-account or unbound receipt must not finish or report restored")
            cases += 1
        }
        try check(SaveSubscriptionRegistrationError.from(status: 409, body: Data("{\"code\":\"other\"}".utf8)) == nil,
            "unrelated conflicts must not be mislabeled as purchase ownership")
        cases += 1
        let cached = SaveStoreKitService(registerTransaction: { _ in pro },
            currentSession: { state.session }, readEntitlements: { [transaction] },
            observeUpdates: false, now: { state.now })
        let cachedStore = SaveEntitlementStore(storeKit: cached, currentSession: { state.session },
            loadQuota: { throw URLError(.notConnectedToInternet) })
        await cachedStore.refresh()
        try check(cachedStore.tier == .pro, "recent backend verdict supports the offline store display")
        try check(cached.serverVerifiedTier == .pro, "recent server confirmation can be displayed offline")
        state.now = state.now.addingTimeInterval(301)
        try check(cached.serverVerifiedTier == nil && cachedStore.tier == .free,
            "neither service nor store may retain expired offline Pro")
        cases += 1
        let expiresSoon = SaveEntitlementResponse(tier: "pro", status: "active", productID: transaction.productID,
            expiresAt: ISO8601DateFormatter.string(from: state.now.addingTimeInterval(30), timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds]),
            environment: "Sandbox")
        let expiring = SaveStoreKitService(registerTransaction: { _ in expiresSoon },
            currentSession: { state.session }, readEntitlements: { [transaction] },
            observeUpdates: false, now: { state.now })
        let expiringStore = SaveEntitlementStore(storeKit: expiring, currentSession: { state.session },
            loadQuota: { throw URLError(.notConnectedToInternet) })
        await expiringStore.refresh()
        try check(expiringStore.tier == .pro, "offline store may use unexpired server verdict")
        state.now = state.now.addingTimeInterval(31)
        try check(expiring.serverVerifiedTier == nil && expiringStore.tier == .free,
            "server expiry must bound offline Pro in the service and its consumer")
        cases += 1
        return cases
    }
}
