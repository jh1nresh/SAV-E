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
        XCTAssertEqual(SAVEProductionConfig.currentCustomURLScheme, "savvy")
        XCTAssertEqual(SAVEProductionConfig.legacyCustomURLScheme, "wanderly")
        XCTAssertEqual(PrivyAuthService.oAuthRedirectURLScheme, "wanderly")
        XCTAssertTrue(SAVEProductionConfig.supportsCustomURLScheme(URL(string: "savvy://p")!))
        XCTAssertTrue(SAVEProductionConfig.supportsCustomURLScheme(URL(string: "wanderly://p")!))
        XCTAssertFalse(SAVEProductionConfig.supportsCustomURLScheme(URL(string: "other://p")!))
        XCTAssertEqual(SAVEProductionConfig.pendingPlacesFileName, "pending-places.json")
        XCTAssertEqual(SAVEProductionConfig.pendingReviewCandidatesFileName, "pending-review-candidates.json")
    }

    @MainActor
    func testAppleFacingDisplayNamesUseSavvyWithoutChangingIdentifiers() throws {
        let mainInfo = try plistTemplate(at: "SAV-E/Info.plist")
        let shareInfo = try plistTemplate(at: "SAV-EShareExtension/Info.plist")
        let messageInfo = try plistTemplate(at: "SAV-EiMessage/Info.plist")
        let projectSpec = try source(at: "project.yml")
        let brandHeader = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")
        let storeKit = try source(at: "SAV-E/Resources/SAVEPro.storekit")

        XCTAssertEqual(mainInfo["CFBundleDisplayName"] as? String, "Savvy")
        XCTAssertEqual(shareInfo["CFBundleDisplayName"] as? String, "Savvy")
        XCTAssertEqual(messageInfo["CFBundleDisplayName"] as? String, "Savvy")
        XCTAssertTrue(projectSpec.contains("INFOPLIST_KEY_CFBundleDisplayName: Savvy"))
        XCTAssertTrue(brandHeader.contains("Text(\"Savvy\")"))
        XCTAssertTrue(storeKit.contains("Savvy Pro Annual"))
        XCTAssertTrue(storeKit.contains("Savvy Pro Monthly"))

        let urlTypes = try XCTUnwrap(mainInfo["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = try XCTUnwrap(urlTypes.first?["CFBundleURLSchemes"] as? [String])
        XCTAssertEqual(schemes, ["savvy", "wanderly"])

        XCTAssertTrue(projectSpec.contains("PRODUCT_BUNDLE_IDENTIFIER: com.wanderly.app"))
        XCTAssertTrue(storeKit.contains("com.wanderly.app.pro.annual"))
        XCTAssertTrue(storeKit.contains("com.wanderly.app.pro.monthly"))
    }

    func testShareExtensionUsesAtlasStatesWithoutConfirmingUnverifiedCandidates() throws {
        let shareView = try source(at: "SAV-EShareExtension/ShareViewController.swift")

        for token in ["FDF8F3", "FFFDF7", "0E4A33", "2E2117", "F26B4A", "B5E3F5", "D6E8C4", "F0CFA1"] {
            XCTAssertTrue(shareView.contains(token), "Share Extension must keep Atlas token \(token)")
        }
        XCTAssertTrue(shareView.contains("share.capture.loading"))
        XCTAssertTrue(shareView.contains("share.capture.error"))
        XCTAssertTrue(shareView.contains("share.capture.addToReview"))
        XCTAssertTrue(shareView.contains("Nothing becomes a Map Stamp until you confirm it in Savvy."))
        XCTAssertFalse(shareView.contains("Confirm this place"))
        XCTAssertFalse(shareView.contains("Find address"))
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

@MainActor
final class SAVEGeminiTransportFailureTests: XCTestCase {
    private let wrapped429 = #"{"error":"Gemini upstream request failed","status":429}"#
    private let unsupported = #"{"error":"Unsupported Gemini model"}"#

    private func transport(_ responses: [(Int, String)], proxy: Bool = true, attempts: Int = 1) -> SAVEGeminiTransport {
        TransportFailureURLProtocol.responses = responses
        TransportFailureURLProtocol.requestCount = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportFailureURLProtocol.self]
        return SAVEGeminiTransport(modelFallbacks: ["first", "second", "third"],
            session: URLSession(configuration: config), accessTokenProvider: nil,
            guestTokenProvider: proxy ? { "synthetic-guest" } : nil,
            directAPIKey: proxy ? nil : "synthetic-key", maxAttemptsPerModel: attempts,
            transientRetryDelayNanoseconds: 0)
    }

    private func expectStatus(_ status: Int, from transport: SAVEGeminiTransport) async {
        do {
            _ = try await transport.generateContent(body: ["contents": []])
            XCTFail("Expected failure")
        } catch SAVEGeminiTransportError.upstreamStatus(let actual) {
            XCTAssertEqual(actual, status)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testWrappedQuotaFailureSurvivesUnsupportedFallbacks() async {
        let runner = transport([(502, wrapped429), (400, unsupported), (400, unsupported)])
        await expectStatus(429, from: runner)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 3)
    }

    func testWrappedQuotaRetriesRemainBoundedAndSupportedFallbackSucceeds() async throws {
        let runner = transport([(502, wrapped429), (502, wrapped429), (200, #"{"ok":true}"#)], attempts: 2)
        let result = try await runner.generateContent(body: [:])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 3)
    }

    func testUnsupportedFirstModelAllowsSupportedFallback() async throws {
        let runner = transport([(400, unsupported), (200, #"{"ok":true}"#)])
        let result = try await runner.generateContent(body: [:])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 2)
    }

    func testMalformedAndUnknownProxyEnvelopesKeepOuterStatus() async {
        for body in ["not-json", #"{"error":"unknown","status":429}"#,
                     #"{"error":"Gemini upstream request failed","status":200}"#,
                     #"{"error":"Gemini upstream request failed","status":429.5}"#] {
            var runner = transport([(502, body)])
            runner.modelFallbacks = ["first"]
            await expectStatus(502, from: runner)
            XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
        }
    }

    func testAuthAndOrdinaryClientErrorsRemainTerminal() async {
        for status in [400, 401, 403] {
            let runner = transport([(status, wrapped429), (200, "{}")])
            await expectStatus(status, from: runner)
            XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
        }
    }

    func testDirectResponseCannotSpoofBackendEnvelope() async {
        for body in [wrapped429, unsupported] {
            let runner = transport([(400, body), (200, "{}")], proxy: false)
            await expectStatus(400, from: runner)
            XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
        }
    }

    func testCancelledRequestDoesNotStartFallback() async {
        let runner = transport([(200, "{}")])
        let task = Task<Void, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await runner.generateContent(body: [:])
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 0)
    }
}

private final class TransportFailureURLProtocol: URLProtocol {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var responses: [(Int, String)] = []
        var requestCount = 0
    }
    private static let state = State()
    static var responses: [(Int, String)] {
        get { state.lock.withLock { state.responses } }
        set { state.lock.withLock { state.responses = newValue } }
    }
    static var requestCount: Int {
        get { state.lock.withLock { state.requestCount } }
        set { state.lock.withLock { state.requestCount = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let next = Self.state.lock.withLock { () -> (Int, String)? in
            Self.state.requestCount += 1
            return Self.state.responses.isEmpty ? nil : Self.state.responses.removeFirst()
        }
        guard let (status, body) = next else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
