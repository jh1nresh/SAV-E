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
          "product_id": "com.wanderly.app.pro.annual",
          "expires_at": "2027-08-19T00:00:00.000Z",
          "environment": "Sandbox"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SaveEntitlementResponse.self, from: json)
        XCTAssertEqual(response.resolvedTier, .pro)
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.productID, "com.wanderly.app.pro.annual")
        XCTAssertEqual(response.environment, "Sandbox")
    }

    /// An unrecognized tier string must not be optimistically treated as Pro.
    func testUnknownTierStringResolvesToFree() throws {
        let json = """
        {
          "tier": "platinum",
          "status": "active",
          "product_id": "com.wanderly.app.pro.annual",
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
        let store = SaveEntitlementStore(loadQuota: { Self.quota(tier: "pro", used: 12) })
        await store.refresh()

        XCTAssertEqual(store.tier, .pro)
        XCTAssertFalse(store.isFailingOpen)
        XCTAssertEqual(store.quota?.usedUnits, 12)
    }

    /// The server saying "free" must win even if a stale local receipt exists.
    /// Otherwise a refunded or expired subscription would keep working.
    @MainActor
    func testServerFreeVerdictOverridesLocalSignal() async {
        let store = SaveEntitlementStore(loadQuota: { Self.quota(tier: "free", used: 3) })
        await store.refresh()

        XCTAssertEqual(store.tier, .free)
        XCTAssertFalse(store.isFailingOpen)
    }

    /// Network failure must not strand the user, and must not invent Pro.
    @MainActor
    func testUnreachableServerFailsOpenWithoutInventingPro() async {
        let store = SaveEntitlementStore(loadQuota: { throw URLError(.notConnectedToInternet) })
        await store.refresh()

        XCTAssertEqual(store.tier, .free, "an offline client must not grant itself Pro")
        XCTAssertTrue(store.isFailingOpen)
        XCTAssertNil(store.quota)
    }

    // MARK: - Paywall trigger policy

    /// The value proof gate. A paywall before the first Map Stamp asks someone
    /// to pay for something they have not seen work.
    @MainActor
    func testPaywallNeverPresentsBeforeFirstMapStamp() {
        let store = SaveEntitlementStore(loadQuota: { Self.quota(tier: "free", used: 0) })

        XCTAssertFalse(
            store.shouldPresentPaywall(for: .refusedAllowanceExhausted, hasConfirmedMapStamp: false),
            "a refusal must not surface a paywall until the user has seen the product work"
        )
        XCTAssertTrue(
            store.shouldPresentPaywall(for: .refusedAllowanceExhausted, hasConfirmedMapStamp: true)
        )
    }

    /// Only a refusal opens the paywall. Warnings and allowances must not.
    @MainActor
    func testOnlyRefusalOpensThePaywall() {
        let store = SaveEntitlementStore(loadQuota: { Self.quota(tier: "free", used: 0) })

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
        let store = SaveEntitlementStore(loadQuota: { Self.quota(tier: "free", used: 20, limit: 20) })
        await store.refresh()

        let decision = store.decideAIAssist()
        XCTAssertEqual(decision, .allowedEnforcementDisabled)
        XCTAssertFalse(decision.isRefusal)
        XCTAssertFalse(store.shouldPresentPaywall(for: decision, hasConfirmedMapStamp: true))
    }

    /// A Pro user is unmetered regardless of how much they used.
    @MainActor
    func testProUserIsNeverGated() async {
        let store = SaveEntitlementStore(loadQuota: { Self.quota(tier: "pro", used: 9_999, limit: 500) })
        await store.refresh()

        XCTAssertEqual(store.tier, .pro)
        XCTAssertEqual(store.decideAIAssist(), .allowed)
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
        XCTAssertTrue(storeKit.contains("serverVerifiedTier = nil"))
    }

    // MARK: - Helpers

    private static func quota(tier: String, used: Int, limit: Int = 20) -> SaveUsageQuotaPreview {
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
