import XCTest
@testable import SAVE

final class SAVEProductionConfigTests: XCTestCase {
    func testCurrentMonetizationBoundaryKeepsActivationAndTripsBetaFree() {
        XCTAssertFalse(SAVEProAccessPolicy.showsAutomaticLaunchPaywall)
        XCTAssertFalse(SAVEProAccessPolicy.firstMapStampRequiresPurchase)
        XCTAssertTrue(SAVEProAccessPolicy.tripsBetaIsFree)
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)
    }

    @MainActor
    func testUsageQuotaPreviewDecodesAsNonEnforcingBetaTelemetry() throws {
        let data = Data("""
        {
          "policy_version":"ai-assists-beta-v0",
          "period_start":"2026-08-01T00:00:00.000Z",
          "period_end":"2026-09-01T00:00:00.000Z",
          "limit_units":20,
          "warning_threshold_units":15,
          "used_units":15,
          "remaining_units":5,
          "state":"warning",
          "enforced":false,
          "metering_available":true,
          "beta_access_continues":true
        }
        """.utf8)

        let preview = try JSONDecoder.supabase.decode(SaveUsageQuotaPreview.self, from: data)

        XCTAssertEqual(preview.policyVersion, "ai-assists-beta-v0")
        XCTAssertEqual(preview.usedUnits, 15)
        XCTAssertEqual(preview.remainingUnits, 5)
        XCTAssertEqual(preview.progress, 0.75)
        XCTAssertFalse(preview.enforced)
        XCTAssertTrue(preview.betaAccessContinues)
    }

    @MainActor
    func testUsageQuotaPreviewClampsProgressWithoutCreatingAnEntitlement() throws {
        let data = Data("""
        {
          "policy_version":"ai-assists-beta-v0",
          "period_start":"2026-08-01T00:00:00.000Z",
          "period_end":"2026-09-01T00:00:00.000Z",
          "limit_units":20,
          "warning_threshold_units":15,
          "used_units":24,
          "remaining_units":0,
          "state":"preview_limit_reached",
          "enforced":false,
          "metering_available":true,
          "beta_access_continues":true
        }
        """.utf8)

        let preview = try JSONDecoder.supabase.decode(SaveUsageQuotaPreview.self, from: data)

        XCTAssertEqual(preview.progress, 1)
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)
        XCTAssertTrue(SAVEProAccessPolicy.tripsBetaIsFree)
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
