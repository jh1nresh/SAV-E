import XCTest
@testable import SAVE

final class SAVEProductionConfigTests: XCTestCase {
    /// Regrades the PR #131 no-paywall guard. A paywall now exists, but the
    /// launch-surface promises it replaced must still hold: no automatic
    /// launch paywall, core memory loop free, enforcement off until Slice 3.
    func testPaywallExistsButNeverPresentsAutomaticallyAtLaunch() throws {
        let policy = try source(at: "SAV-EShared/SAVEProAccessPolicy.swift")
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        let backend = try source(at: "backend/src/server.ts")

        XCTAssertFalse(SAVEProAccessPolicy.showsAutomaticLaunchPaywall)
        XCTAssertFalse(SAVEProAccessPolicy.firstMapStampRequiresPurchase)
        XCTAssertTrue(SAVEProAccessPolicy.coreMemoryLoopIsFree)
        // Slice 1 must not be able to refuse anyone.
        XCTAssertFalse(SAVEProAccessPolicy.enforcementEnabled)
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)

        // App Store review requirements must live on the paywall itself.
        for required in ["paywall.restore", "paywall.terms", "paywall.privacy", "paywall.close"] {
            XCTAssertTrue(paywall.contains(required), "Paywall must expose \(required)")
        }
        XCTAssertTrue(policy.contains("enforcementEnabled"))

        // Backend metering stays intact and untouched by this slice.
        XCTAssertTrue(backend.contains("recordAIUsageEvent"))
        XCTAssertTrue(backend.contains("buildGeminiUsageEvent"))
    }

    /// The gate is the only thing allowed to refuse an AI assist, so its truth
    /// table is pinned here.
    func testAIAssistGateFailsOpenAndRespectsEnforcementSwitch() {
        // Pro is unmetered regardless of usage.
        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .pro, usedUnits: 999, limitUnits: 20, warningThresholdUnits: 15),
            .allowed
        )

        // Metering unavailable: fail open rather than guess.
        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .free, usedUnits: nil, limitUnits: 20, warningThresholdUnits: 15),
            .allowed
        )

        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .free, usedUnits: 3, limitUnits: 20, warningThresholdUnits: 15),
            .allowed
        )

        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .free, usedUnits: 16, limitUnits: 20, warningThresholdUnits: 15),
            .allowedWarningNearLimit(remaining: 4)
        )

        // Exhausted while enforcement is off: served anyway, but recorded.
        XCTAssertEqual(
            SaveAIAssistGate.decide(
                tier: .free, usedUnits: 20, limitUnits: 20, warningThresholdUnits: 15,
                enforcementEnabled: false
            ),
            .allowedEnforcementDisabled
        )

        // Only with enforcement explicitly on may a refusal happen.
        XCTAssertEqual(
            SaveAIAssistGate.decide(
                tier: .free, usedUnits: 20, limitUnits: 20, warningThresholdUnits: 15,
                enforcementEnabled: true
            ),
            .refusedAllowanceExhausted
        )
    }

    /// A missing `tier` field must resolve to free, so this build stays
    /// compatible with the currently deployed backend.
    func testQuotaPreviewWithoutTierFieldResolvesToFree() throws {
        let json = """
        {
          "policy_version": "ai-assists-beta-v0",
          "period_start": "2026-08-01T00:00:00.000Z",
          "period_end": "2026-09-01T00:00:00.000Z",
          "limit_units": 20,
          "warning_threshold_units": 15,
          "used_units": 4,
          "remaining_units": 16,
          "state": "available",
          "enforced": false,
          "metering_available": true,
          "beta_access_continues": true
        }
        """.data(using: .utf8)!

        let preview = try JSONDecoder().decode(SaveUsageQuotaPreview.self, from: json)
        XCTAssertEqual(preview.resolvedTier, .free)
        XCTAssertEqual(preview.usedUnits, 4)
        XCTAssertFalse(preview.enforced)
    }

    @MainActor
    func testTemplatesUseSaveKeysForProductionConfig() throws {
        let mainTemplate = try plistTemplate(at: "SAV-E/Resources/Secrets.plist.template")
        let shareTemplate = try plistTemplate(at: "SAV-EShareExtension/Secrets.plist.template")

        XCTAssertEqual(mainTemplate["SAVE_API_URL"] as? String, "https://wanderly-api-production.up.railway.app")
        XCTAssertEqual(shareTemplate["SAVE_API_URL"] as? String, "https://wanderly-api-production.up.railway.app")
        XCTAssertEqual(mainTemplate["SAVE_PLACE_SHARE_BASE_URL"] as? String, SAVEProductionConfig.defaultPlaceShareBaseURL)
        XCTAssertEqual(shareTemplate["SAVE_PLACE_SHARE_BASE_URL"] as? String, SAVEProductionConfig.defaultPlaceShareBaseURL)
        XCTAssertEqual(mainTemplate["PRIVY_APP_ID"] as? String, "cmnttqw3q038x0cle8vnlki39")
        XCTAssertEqual(mainTemplate["PRIVY_APP_CLIENT_ID"] as? String, "client-WY6XpSj5cs9CrZjfDUuBAcS1sWtDG5eF1RTqYs9fqmvFw")

        XCTAssertNil(mainTemplate["WANDERLY_API_URL"])
        XCTAssertNil(mainTemplate["WANDERLY_SHARE_BASE_URL"])
        XCTAssertNil(shareTemplate["WANDERLY_API_URL"])
        XCTAssertNil(shareTemplate["WANDERLY_SHARE_BASE_URL"])
        XCTAssertNil(mainTemplate["GEMINI_API_KEY"])
        XCTAssertNil(shareTemplate["GEMINI_API_KEY"])
        XCTAssertNil(mainTemplate["AMAP_WEB_SERVICE_KEY"])
        XCTAssertNil(mainTemplate["BAIDU_MAP_WEB_SERVICE_KEY"])
    }

    @MainActor
    func testConfigNormalizationRejectsPlaceholders() {
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("YOUR_KEY_HERE"))
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("REPLACE_ME"))
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("  "))
        XCTAssertEqual(SAVEProductionConfig.normalizedConfigValue(" https://sav-e-app.vercel.app/p "), "https://sav-e-app.vercel.app/p")
    }

    @MainActor
    func testClientGeminiFallbackIsOffByDefault() {
        XCTAssertFalse(SAVEProductionConfig.allowsClientGeminiFallback())
        XCTAssertNil(SAVEProductionConfig.clientGeminiAPIKeyIfAllowed())
    }

    @MainActor
    func testSharedProductionConstantsMatchExistingAppleIdentifiers() {
        XCTAssertEqual(SAVEProductionConfig.legacyProductionBundleID, "com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.appGroupSuiteName, "group.com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.pendingPlacesFileName, "pending-places.json")
        XCTAssertEqual(SAVEProductionConfig.pendingReviewCandidatesFileName, "pending-review-candidates.json")
    }

    @MainActor
    func testSharedGeminiModelFallbacksPreferStrongFlashWithStableFallback() {
        XCTAssertEqual(SAVEProductionConfig.defaultGeminiModelFallbacks, ["gemini-3.5-flash", "gemini-2.5-flash"])

        let url = SAVEProductionConfig.geminiGenerateContentURL(apiKey: "test-key", model: "gemini-3.5-flash")
        XCTAssertEqual(
            url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=test-key"
        )
    }

    @MainActor
    func testChinaProviderConfigurationUsesAppleMapsWithoutClientProviderKeys() {
        let status = ChinaPlaceResolverConfiguration.status(
            backendAPIBaseURL: nil,
            accessTokenProviderConfigured: false
        )

        XCTAssertTrue(status.canResolveChinaPOI)
        XCTAssertEqual(status.configuredProviders, ["apple_maps"])
        XCTAssertTrue(status.missingRequirements.isEmpty)
    }

    @MainActor
    func testChinaProviderConfigurationReportsOptionalBackendWithoutSecrets() {
        let status = ChinaPlaceResolverConfiguration.status(
            backendAPIBaseURL: "https://wanderly-api-production.up.railway.app",
            accessTokenProviderConfigured: true
        )

        XCTAssertTrue(status.canResolveChinaPOI)
        XCTAssertEqual(status.configuredProviders, ["apple_maps", "backend_proxy"])
        XCTAssertTrue(status.missingRequirements.isEmpty)
    }

    private func plistTemplate(at relativePath: String) throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
