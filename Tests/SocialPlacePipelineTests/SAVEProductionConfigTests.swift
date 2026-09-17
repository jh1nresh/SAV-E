import XCTest
import CoreLocation
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

    func testMissingModelsReport404OnlyAfterAllFallbacksAreExhausted() async {
        let runner = transport([(404, "{}"), (404, "{}"), (404, "{}")])
        await expectStatus(404, from: runner)
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

@MainActor
final class SAVEAnalysisTransportTests: XCTestCase {
    func testImportSummarySeparatesPendingSourcesFromGroundedCandidates() {
        let source = PlaceReviewCandidate(id: UUID(), captureId: UUID(), name: "Source clue", address: "", city: nil,
            latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: ["Analysis pending", "Exact place"], status: "source_only", createdAt: Date())
        var candidate = source
        candidate.id = UUID(); candidate.status = "review"; candidate.name = "Pikul"; candidate.missingInfo = ["User confirmation"]
        let pending = ReviewImportSummary(candidateIDs: [source.id], candidates: [source, candidate])
        XCTAssertEqual(pending.candidateCount, 0)
        XCTAssertEqual(pending.sourceCount, 1)
        XCTAssertEqual(pending.pendingCount, 1)
        let mixed = ReviewImportSummary(candidateIDs: [source.id, candidate.id], candidates: [source, candidate])
        XCTAssertEqual(mixed.candidateCount, 1)
        XCTAssertEqual(mixed.pendingCount, 1)
        var saved = source; saved.status = "confirmed"
        XCTAssertFalse(saved.isAnalysisPending, "An old marker cannot relabel a confirmed place as pending")
    }


    func testSemanticCaptionWireContractOmitsAbsentOCRAndPreservesFullText() async throws {
        let caption = "商業午餐\n📍初泰Pikul  信義象山門市\n臺北市信義區信義路五段122號"
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertEqual(body["caption"] as? String, caption)
            // Mirrors the backend's strict optional-string contract.
            XCTAssertFalse(body["ocrText"] is NSNull)
            if body["ocrText"] != nil { XCTAssertEqual(body["ocrText"] as? String, "cover text") }
            XCTAssertEqual(request.timeoutInterval, 90)
            return (200, #"{"status":"no_place_evidence","venues":[]}"#)
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let context = SAVEAnalysisContext(id: UUID())
        for ocr in [nil, "cover text"] {
            let result = try await SAVEAnalysisScope.$current.withValue(context) {
                try await service.analyzeSocialCaption(caption: caption, ocrText: ocr)
            }
            XCTAssertEqual(result.status, "no_place_evidence")
        }
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 2)
        XCTAssertNil(try AnalysisRequestURLProtocol.body(AnalysisRequestURLProtocol.requests[0])["ocrText"])
    }

    func testSemanticResponseFromPreviousAccountIsDiscarded() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original }
        auth.authState = .authenticated(userId: "semantic-account-A")
        let arrived = expectation(description: "semantic request in flight")
        let release = DispatchSemaphore(value: 0)
        AnalysisRequestURLProtocol.handler = { _ in
            arrived.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return (200, #"{"status":"ready","venues":[]}"#)
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let context = SAVEAnalysisContext(id: UUID())
        let task = Task {
            try await SAVEAnalysisScope.$current.withValue(context) {
                try await service.analyzeSocialCaption(caption: "Pikul", ocrText: nil)
            }
        }
        await fulfillment(of: [arrived], timeout: 5)
        auth.authState = .authenticated(userId: "semantic-account-B")
        release.signal()
        do { _ = try await task.value; XCTFail("Old account response must be discarded") }
        catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }

    func testImportRecoveryRejectsAccountSwitchBeforeApplyingResults() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original }
        auth.authState = .authenticated(userId: "recovery-account-A")
        let arrived = expectation(description: "recovery in flight")
        let release = DispatchSemaphore(value: 0)
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                return (200, "{\"analysis_id\":\"\(id)\"}")
            }
            if request.url?.path.hasSuffix("/search-recovery") == true {
                arrived.fulfill()
                _ = release.wait(timeout: .now() + 10)
                return (200, #"{"created_candidates":[]}"#)
            }
            XCTAssertFalse(request.httpMethod == "GET" && request.url?.path == "/memory/candidates", "Must not refresh another account after stale analysis")
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let map = MapViewModel(supabaseService: service)
        let clue = PlaceReviewCandidate(id: UUID(), captureId: UUID(), name: "Original", address: "", city: nil,
            latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [], status: "source_only", createdAt: Date())
        map.reviewCandidates = [clue]
        let task = Task { try await map.reanalyzeReviewSource(clue) }
        await fulfillment(of: [arrived], timeout: 5)
        auth.authState = .authenticated(userId: "recovery-account-B")
        release.signal()
        do { _ = try await task.value; XCTFail("Stale import must stop") }
        catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertEqual(map.reviewCandidates.map(\.id), [clue.id])
    }
    @MainActor
    func testMemoryImportSendsOriginalDateAndSourceOnlyState() async throws {
        let id = UUID()
        let capture = UUID()
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertEqual(body["created_at"] as? String, "2020-01-02T03:04:05Z")
            if request.url?.path.hasSuffix("/captures") == true {
                return (200, "{\"id\":\"\(capture)\"}")
            }
            XCTAssertEqual(body["status"] as? String, "source_only")
            return (200, "{\"id\":\"\(id)\",\"capture_id\":\"\(capture)\",\"name\":\"Clue\",\"status\":\"source_only\",\"created_at\":\"2020-01-02T03:04:05Z\"}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let pending = PendingReviewCandidate(candidateName: "Clue", address: "", category: "other",
            sourceURL: "https://example.com/post", sourceText: "clue", evidence: [], confidence: 0,
            missingInfo: [], savedAt: ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!, isSourceOnly: true)
        let captured = try await service.createMemoryCapture(from: pending, userId: "test-owner")
        XCTAssertEqual(captured, capture)
        let candidate = try await service.createPlaceCandidate(pending, captureId: captured, userId: "test-owner")
        XCTAssertEqual(candidate, id)
    }

    @MainActor
    func testExactConfirmationPublishesReconciledDateForNewAndExistingStamps() async throws {
        let oldDate = ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!
        for isExisting in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let clue = PlaceReviewCandidate(id: UUID(), captureId: UUID(), name: "Cafe", address: "1 Road", city: nil,
                latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [], status: "review",
                createdAt: oldDate.addingTimeInterval(1000))
            let candidate = SaveMapCandidate(id: "exact-cafe", title: "Cafe", subtitle: "1 Road", latitude: 25, longitude: 121, category: .cafe)
            var existing = Place.from(clue)
            existing.latitude = 25
            existing.longitude = 121
            existing.note = "Latest user note"
            var savedID = existing.id
            var saveCount = 0
            var decisionFails = !isExisting
            AnalysisRequestURLProtocol.handler = { request in
                if decisionFails, request.httpMethod == "PATCH", request.url?.path.contains("/candidates/") == true {
                    return (503, "{\"error\":\"decision offline\"}")
                }
                if request.httpMethod == "GET", request.url?.path.hasSuffix("/places") == true {
                    return (200, "[{\"id\":\"\(savedID)\",\"user_id\":\"owner\",\"name\":\"Cafe\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"cafe\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"note\":\"stale note\",\"created_at\":\"2020-01-02T03:04:05.000Z\"}]")
                }
                return (200, request.httpMethod == "GET" ? "[]" : "{}")
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let map = MapViewModel(supabaseService: service,
                mapCandidatePlaceSaver: { place, _ in savedID = place.id; saveCount += 1 }, mapCandidateUserIDProvider: { "owner" },
                saveLocalVaultService: vault, correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("corrections.json")))
            if isExisting { map.places = [existing] }
            map.reviewCandidates = [clue]
            map.mapCandidates = [candidate]
            map.beginExactSearchResolution(for: clue)
            if !isExisting {
                do {
                    _ = try await map.saveMapCandidateAsPlace(candidate)
                    XCTFail("The failed decision must keep the clue pending")
                } catch {}
                XCTAssertTrue(map.reviewCandidates.contains { $0.id == clue.id })
                XCTAssertEqual(map.places.first?.id, savedID)
                decisionFails = false
            }
            let saved = try await map.saveMapCandidateAsPlace(candidate)
            XCTAssertEqual(saveCount, isExisting ? 0 : 1, "Retry must reuse the already inserted stamp")
            XCTAssertEqual(saved.createdAt, oldDate)
            XCTAssertEqual(map.places.first?.createdAt, oldDate)
            XCTAssertEqual(try vault.confirmedPlaces().first?.createdAt, oldDate)
            XCTAssertFalse(map.reviewCandidates.contains { $0.id == clue.id })
            if isExisting { XCTAssertTrue(saved.note?.contains("Latest user note") == true) }

            AnalysisRequestURLProtocol.handler = { _ in (503, "{\"error\":\"offline\"}") }
            let fallback = await map.refreshedConfirmedPlace(saved)
            XCTAssertEqual(fallback, saved, "A readback failure must not retry a committed save")
        }
    }

    @MainActor
    func testMemoryFetchPreservesServerDatesWithAndWithoutFractionalSeconds() async throws {
        let id = UUID()
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let base = ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!
        for (timestamp, fraction) in [("2020-01-02T03:04:05Z", 0.0), ("2020-01-02T03:04:05.123Z", 0.123), ("2020-01-02T03:04:05.123456+00:00", 0.123456)] {
            AnalysisRequestURLProtocol.handler = { request in
                if request.url?.path.hasSuffix("/candidates") == true {
                    return (200, "[{\"id\":\"\(id)\",\"name\":\"Clue\",\"status\":\"review\",\"created_at\":\"\(timestamp)\"}]")
                }
                return (200, "[{\"id\":\"\(id)\",\"user_id\":\"owner\",\"name\":\"Cafe\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"food\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"created_at\":\"\(timestamp)\"}]")
            }
            let candidates = try await service.fetchReviewCandidates()
            let places = try await service.fetchPlaces(for: "owner")
            XCTAssertEqual(try XCTUnwrap(candidates.first).createdAt.timeIntervalSince(base), fraction, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(places.first).createdAt.timeIntervalSince(base), fraction, accuracy: 0.001)
        }
    }

    @MainActor
    func testRetryUsesExistingCaptureAndHidesOnlySupersededClueAfterReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var stampID = UUID()
        var readbackFails = false
        let capture = UUID(), oldID = UUID(), newID = UUID(), secondID = UUID(), run = UUID(), firstRun = UUID(), secondRun = UUID()
        let oldJSON = "{\"id\":\"\(oldID)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(run)\",\"name\":\"Clue\",\"status\":\"source_only\",\"created_at\":\"2020-01-02T03:04:05Z\",\"superseded_by_candidate_id\":\"\(newID)\",\"superseded_by_candidate_ids\":[\"\(newID)\",\"\(secondID)\"]}"
        let newJSON = "{\"id\":\"\(newID)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(firstRun)\",\"name\":\"Cafe\",\"status\":\"review\",\"created_at\":\"2020-01-02T03:04:05Z\"}"
        let secondJSON = "{\"id\":\"\(secondID)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(secondRun)\",\"name\":\"Museum\",\"status\":\"review\",\"created_at\":\"2020-01-02T03:04:05Z\"}"
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                return (200, "{\"analysis_id\":\"\(id)\"}")
            }
            if request.url?.path.hasSuffix("/search-recovery") == true {
                XCTAssertTrue(request.url!.path.contains(capture.uuidString))
                let body = try AnalysisRequestURLProtocol.body(request)
                XCTAssertEqual(body["workflow_run_id"] as? String, run.uuidString)
                XCTAssertEqual(body["explicit_retry"] as? Bool, true)
                return (200, "{\"created_candidates\":[\(newJSON),\(secondJSON)]}")
            }
            if request.url?.path.hasSuffix("/candidates") == true { return (200, "[\(oldJSON),\(newJSON),\(secondJSON)]") }
            if request.url?.path.hasSuffix("/places") == true {
                if readbackFails { return (503, "{}") }
                return (200, "[{\"id\":\"\(stampID)\",\"user_id\":\"owner\",\"name\":\"Cafe\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"cafe\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"note\":\"stale server note\",\"created_at\":\"2020-01-02T03:04:05Z\"}]")
            }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault)
        let old = PlaceReviewCandidate(id: oldID, captureId: capture, workflowRunId: run, name: "Clue", address: "",
            city: nil, latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [],
            status: "source_only", createdAt: Date(timeIntervalSince1970: 1))
        let ids = try await map.reanalyzeReviewSource(old)
        XCTAssertEqual(ids, [newID, secondID])
        XCTAssertEqual(map.reviewCandidates.map(\.id), [newID, secondID])
        XCTAssertEqual(map.reviewCandidates.map(\.workflowRunId), [firstRun, secondRun])
        let pending = PendingReviewCandidate(candidateName: "Clue", address: "", category: "other",
            sourceURL: nil, sourceText: "source", evidence: [], confidence: 0, missingInfo: [], savedAt: Date(), isSourceOnly: true)
        var stampClue = old
        stampClue.latitude = 25
        stampClue.longitude = 121
        var stamp = Place.from(stampClue)
        stampID = stamp.id
        stamp.createdAt = Date()
        stamp.note = "Latest local note"
        map.places = [stamp]
        let reusedIDs = try await map.reuseImportedCandidate(pending, captureId: capture, userId: "owner")
        XCTAssertEqual(reusedIDs, [newID, secondID], "A repeated source returns every successor, not an arbitrary first venue")
        XCTAssertEqual(map.places.first?.createdAt, ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z"))
        XCTAssertEqual(map.places.first?.note, "Latest local note")
        XCTAssertEqual(try vault.confirmedPlaces().first?.createdAt, map.places.first?.createdAt)
        readbackFails = true
        let repeatedAfterReadbackFailure = try await map.reuseImportedCandidate(pending, captureId: capture, userId: "owner")
        XCTAssertEqual(repeatedAfterReadbackFailure, reusedIDs, "Date readback failure must not retry a committed import")
        XCTAssertTrue(AnalysisRequestURLProtocol.requests.allSatisfy {
            $0.httpMethod != "POST" || !$0.url!.path.hasSuffix("/captures")
        })
        try await map.refreshReviewCandidates()
        XCTAssertEqual(map.reviewCandidates.map(\.id), [newID, secondID])
    }

    func testPlaceMergeSendsEarliestKnownDateAndOmitsUnknownFallback() async throws {
        let early = ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!
        let clue = PlaceReviewCandidate(id: UUID(), captureId: nil, name: "Cafe", address: "1 Road",
            city: nil, latitude: 25, longitude: 121, evidence: [], confidence: nil, missingInfo: [], status: "review", createdAt: early)
        var existing = Place.from(clue)
        existing.createdAt = early.addingTimeInterval(1000)
        var incoming = Place.from(clue)
        incoming.note = "Earlier source evidence"
        let merged = existing.mergingSources(from: incoming)
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        var expectsDate = true
        AnalysisRequestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try AnalysisRequestURLProtocol.body(request)
            if expectsDate {
                XCTAssertEqual(body["created_at"] as? String, "2020-01-02T03:04:05Z")
                XCTAssertTrue((body["note"] as? String)?.contains("Earlier source evidence") == true)
            } else { XCTAssertNil(body["created_at"]) }
            return (200, "{}")
        }
        try await service.updatePlace(merged)
        expectsDate = false
        var unknown = merged
        unknown.createdAt = .distantPast
        try await service.updatePlace(unknown)
    }

    func testEmptyRetryDistinguishesExistingSuccessorsFromUnresolvedSource() async throws {
        for status in ["saved", "confirmed", "rejected", "review", "missing", "unresolved"] {
            let capture = UUID(), source = UUID(), successor = UUID()
            let marker = status == "unresolved" ? "" : ",\"superseded_by_candidate_ids\":[\"\(successor)\"]"
            let sourceJSON = "{\"id\":\"\(source)\",\"capture_id\":\"\(capture)\",\"name\":\"Saved source\",\"status\":\"source_only\",\"created_at\":\"2020-01-01T00:00:00Z\"\(marker)}"
            let successorJSON = ["unresolved", "missing"].contains(status) ? "" : ",{\"id\":\"\(successor)\",\"capture_id\":\"\(capture)\",\"name\":\"Cafe\",\"status\":\"\(status)\",\"created_at\":\"2020-01-01T00:00:00Z\"}"
            AnalysisRequestURLProtocol.handler = { request in
                if request.url?.path == "/v0/analysis" {
                    let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                    return (200, "{\"analysis_id\":\"\(id)\"}")
                }
                if request.url?.path.hasSuffix("/search-recovery") == true { return (200, "{\"created_candidates\":[]}") }
                if request.url?.path.hasSuffix("/candidates") == true { return (200, "[\(sourceJSON)\(successorJSON)]") }
                if request.httpMethod == "GET" { return (200, "[]") }
                return (200, "{}")
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let map = MapViewModel(supabaseService: service, usesRemotePersistence: true)
            let clue = PlaceReviewCandidate(id: source, captureId: capture, name: "Saved source", address: "",
                city: nil, latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [], status: "source_only", createdAt: Date())
            do {
                let ids = try await map.reanalyzeReviewSource(clue)
                XCTAssertFalse(["saved", "confirmed", "rejected"].contains(status), "Terminal successors must acknowledge already reviewed")
                XCTAssertEqual(ids, status == "review" ? [successor] : [])
                if status == "unresolved" { XCTAssertTrue(map.reviewCandidates.contains { $0.id == source }) }
            } catch ReviewCandidateError.sourceAlreadyReviewed {
                XCTAssertTrue(["saved", "confirmed", "rejected"].contains(status))
            }
        }
    }

    override func tearDown() {
        AnalysisRequestURLProtocol.reset()
        super.tearDown()
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnalysisRequestURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func gemini(session: URLSession) -> SAVEGeminiTransport {
        SAVEGeminiTransport(modelFallbacks: ["first", "second"], session: session,
            accessTokenProvider: { "synthetic-token" }, directAPIKey: "must-not-be-used",
            apiBaseURL: "https://analysis.test", maxAttemptsPerModel: 2,
            transientRetryDelayNanoseconds: 0)
    }

    func testConcurrentGeminiSessionsCorrelateEveryFallbackWithoutLeakingScope() async throws {
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            if body["model"] as? String == "first" {
                return (400, #"{"error":"Unsupported Gemini model"}"#)
            }
            return (200, #"{"ok":true}"#)
        }
        let runner = gemini(session: session())
        let first = SAVEAnalysisContext(id: UUID())
        let second = SAVEAnalysisContext(id: UUID())
        let a = Task { @MainActor in
            try await SAVEAnalysisScope.$current.withValue(first) { _ = try await runner.generateContent(body: [:]) }
        }
        let b = Task { @MainActor in
            try await SAVEAnalysisScope.$current.withValue(second) { _ = try await runner.generateContent(body: [:]) }
        }
        let results = await (a.result, b.result)
        try results.0.get()
        try results.1.get()
        XCTAssertNil(SAVEAnalysisScope.current)
        let requests = AnalysisRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 4)
        for context in [first, second] {
            XCTAssertEqual(requests.filter { $0.value(forHTTPHeaderField: "x-save-analysis-id") == context.id.uuidString }.count, 2)
        }
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "analysis.test" })
    }

    func testAnalysisDenialDoesNotRetryModelOrUseDirectProvider() async {
        for code in ["analysis_limit_exceeded", "analysis_controls_unavailable", "analysis_closed", "analysis_not_found"] {
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (429, "{\"code\":\"\(code)\"}") }
            let context = SAVEAnalysisContext(id: UUID())
            do {
                _ = try await SAVEAnalysisScope.$current.withValue(context) {
                    try await gemini(session: session()).generateContent(body: [:])
                }
                XCTFail("Expected a terminal analysis denial")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.first?.url?.host, "analysis.test")
        }
    }

    func testMissingAnalysisProxyNeverUsesConfiguredDirectGeminiKey() async {
        var runner = gemini(session: session())
        runner.apiBaseURL = nil
        do {
            _ = try await SAVEAnalysisScope.$current.withValue(SAVEAnalysisContext(id: UUID())) {
                try await runner.generateContent(body: [:])
            }
            XCTFail("Expected unavailable analysis")
        } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(AnalysisRequestURLProtocol.requests.isEmpty)
    }

    func testGoogleUsesServerWithoutClientKeyAndKeepsOrdinarySearchRoute() async throws {
        let result = #"{"status":"OK","results":[{"place_id":"fixture","name":"Fixture","geometry":{"location":{"lat":25.03,"lng":121.56}}}]}"#
        AnalysisRequestURLProtocol.handler = { _ in (200, result) }
        let places = GooglePlacesService(apiKey: "REPLACE_ME", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { "synthetic-token" })
        let context = SAVEAnalysisContext(id: UUID())
        let matches = try await SAVEAnalysisScope.$current.withValue(context) {
            try await places.searchPlace(query: "Fixture", near: nil)
        }
        XCTAssertEqual(matches.first?.id, "fixture")
        let request = try XCTUnwrap(AnalysisRequestURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/v0/analysis/\(context.id.uuidString)/places")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-save-analysis-id"), context.id.uuidString)
        XCTAssertNil(request.url?.query)
        let ordinary = GooglePlacesService(apiKey: "synthetic-key", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { XCTFail("Ordinary search must keep its route"); return "unused" })
        _ = try await ordinary.searchPlace(query: "Fixture", near: nil)
        let unscoped = try XCTUnwrap(AnalysisRequestURLProtocol.requests.last)
        XCTAssertEqual(unscoped.url?.host, "maps.googleapis.com")
        XCTAssertNil(unscoped.value(forHTTPHeaderField: "x-save-analysis-id"))
    }

    func testGoogleDenialNeverFallsBackToClientKeyOrMakesLaterAnalysisCall() async {
        AnalysisRequestURLProtocol.handler = { _ in (429, #"{"code":"analysis_limit_exceeded"}"#) }
        let places = GooglePlacesService(apiKey: "must-not-be-used", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { "synthetic-token" })
        let context = SAVEAnalysisContext(id: UUID())
        for _ in 0..<2 {
            do {
                _ = try await SAVEAnalysisScope.$current.withValue(context) {
                    try await places.searchPlace(query: "Fixture", near: nil)
                }
                XCTFail("Expected denial")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.first?.url?.host, "analysis.test")
    }

    func testActualSessionStartAndCancelledFinishSendRedactedCorrelatedEvents() async throws {
        let id = UUID()
        let captureID = UUID()
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let body = try AnalysisRequestURLProtocol.body(request)
                return (200, "{\"analysis_id\":\"\(body["id"] as! String)\"}")
            }
            return (200, "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "synthetic-token" })
        let started = try await service.startAnalysis(id: id)
        XCTAssertEqual(started, id)
        let context = SAVEAnalysisContext(id: id)
        await context.addCapture(captureID)
        await SAVEAnalysisScope.$current.withValue(context) {
            _ = try? await SAVEAnalysisScope.measure(.publicSearch) {
                throw NSError(domain: "private caption or token must not enter telemetry", code: 1)
            }
            await SAVEAnalysisScope.measure(.localOCR) { () }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await service.finishAnalysis(context, outcome: "cancelled")
        }
        await task.value
        let requests = AnalysisRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        let eventsRequest = try XCTUnwrap(requests.first { $0.url?.path.hasSuffix("/client-events") == true })
        XCTAssertTrue(eventsRequest.url!.path.contains(id.uuidString))
        let events = try XCTUnwrap(try AnalysisRequestURLProtocol.body(eventsRequest)["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?["outcome"] as? String, "failure")
        for event in events { XCTAssertEqual(Set(event.keys), ["event_id", "operation", "outcome", "duration_ms"]) }
        let finish = try AnalysisRequestURLProtocol.body(try XCTUnwrap(requests.last))
        XCTAssertEqual(finish["outcome"] as? String, "cancelled")
        XCTAssertEqual(finish["capture_ids"] as? [String], [captureID.uuidString])
    }

    func testChinaControlDenialStopsGoogleAndLaterResolverAttempts() async {
        for code in ["analysis_limit_exceeded", "analysis_controls_unavailable", "analysis_closed", "analysis_not_found"] {
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (429, "{\"code\":\"\(code)\"}") }
            let google = AnalysisGoogleSpy()
            let apple = AnalysisAppleSpy()
            let china = BackendPlaceResolverService(apiBaseURL: "https://analysis.test", session: session(),
                accessTokenProvider: { "synthetic-token" })
            let resolver = PlaceResolverService(googlePlacesService: google,
                appleMapsPlaceSearchService: apple, backendPlaceResolverService: china)
            await SAVEAnalysisScope.$current.withValue(SAVEAnalysisContext(id: UUID())) {
                for _ in 0..<2 {
                    do {
                        _ = try await resolver.searchPlace(query: "台北咖啡", near: nil)
                        XCTFail("Expected terminal analysis denial")
                    } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
                }
            }
            XCTAssertEqual(google.searchCount, 0)
            XCTAssertEqual(apple.searchCount, 1)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.first?.url?.path, "/place-resolve")
        }
    }

    func testRecoveryControlDenialStopsLaterRecoveryGoogleAndGeminiRequests() async {
        AnalysisRequestURLProtocol.handler = { _ in (503, #"{"code":"analysis_controls_unavailable"}"#) }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "synthetic-token" })
        let google = GooglePlacesService(apiKey: "must-not-be-used", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { "synthetic-token" })
        let runner = gemini(session: session())
        await SAVEAnalysisScope.$current.withValue(SAVEAnalysisContext(id: UUID())) {
            for _ in 0..<2 {
                do {
                    _ = try await service.recoverSourceOnlyReviewCandidates(captureId: UUID())
                    XCTFail("Expected recovery denial")
                } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
            }
            do {
                _ = try await google.searchPlace(query: "Fixture", near: nil)
                XCTFail("Expected Google to stop before sending")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
            do {
                _ = try await runner.generateContent(body: [:])
                XCTFail("Expected Gemini to stop before sending")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
        XCTAssertTrue(AnalysisRequestURLProtocol.requests.first?.url?.path.hasSuffix("/search-recovery") == true)
    }

    func testEmptyClientEventsStillSendsReceiptBeforeFinish() async throws {
        AnalysisRequestURLProtocol.handler = { _ in (200, "{}") }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "synthetic-token" })
        await service.finishAnalysis(SAVEAnalysisContext(id: UUID()), outcome: "source_only")
        let requests = AnalysisRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.first?.url?.path.hasSuffix("/client-events") == true)
        let body = try AnalysisRequestURLProtocol.body(try XCTUnwrap(requests.first))
        XCTAssertEqual((body["events"] as? [Any])?.count, 0)
        XCTAssertEqual(body["events_truncated"] as? Bool, false)
        XCTAssertTrue(requests.last?.url?.path.hasSuffix("/finish") == true)
    }

    func testClientEventBufferReportsOverflowAndKeepsCountsPerSession() async {
        let context = SAVEAnalysisContext(id: UUID())
        for _ in 0..<65 {
            await context.record(.metadata, outcome: .success, started: ProcessInfo.processInfo.systemUptime)
        }
        let snapshot = await context.snapshot()
        XCTAssertEqual(snapshot.events.count, 64)
        XCTAssertTrue(snapshot.eventsTruncated)
        let independent = await SAVEAnalysisContext(id: UUID()).snapshot()
        XCTAssertTrue(independent.events.isEmpty)
        XCTAssertFalse(independent.eventsTruncated)
    }

    func testFailureReceiptUsesActionableCopyWithoutProviderDiagnostics() throws {
        for reason in ["login_required", "expired", "caption_missing", "unresolved_source", "no_place_evidence"] {
            let data = Data("{\"created_candidates\":[],\"receipt\":{\"failureReason\":{\"kind\":\"insufficient_source\",\"reason\":\"\(reason)\"}}}".utf8)
            let recovered = try SupabaseService.decodeSourceSearchRecoveryResponse(data)
            let failure = try XCTUnwrap(recovered.failureReason)
            XCTAssertEqual(failure.kind, .insufficientSource)
            XCTAssertTrue(failure.englishMessage.contains("caption"))
            XCTAssertTrue(failure.englishMessage.contains("screenshot"))
        }
        let data = Data(#"{"created_candidates":[],"receipt":{"failureReason":{"kind":"provider_failure","stage":"public_search"}}}"#.utf8)
        let failure = try XCTUnwrap(try SupabaseService.decodeSourceSearchRecoveryResponse(data).failureReason)
        XCTAssertTrue(failure.englishMessage.contains("try again"))
        XCTAssertFalse(failure.englishMessage.contains("public_search"))
        XCTAssertNil(try SupabaseService.decodeSourceSearchRecoveryResponse(Data(#"{"created_candidates":[]}"#.utf8)).failureReason)
    }
}

@MainActor
private final class AnalysisGoogleSpy: GooglePlacesServiceProtocol {
    var searchCount = 0
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        searchCount += 1
        return []
    }
    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails { throw GooglePlacesError.noResults }
    func photoURL(reference: String, maxWidth: Int) -> URL? { nil }
}

@MainActor
private final class AnalysisAppleSpy: AppleMapsPlaceSearchServiceProtocol {
    var searchCount = 0
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        searchCount += 1
        return []
    }
}

private final class AnalysisRequestURLProtocol: URLProtocol {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
        var handler: ((URLRequest) throws -> (Int, String))?
    }
    private static let state = State()
    static var requests: [URLRequest] { state.lock.withLock { state.requests } }
    static var handler: ((URLRequest) throws -> (Int, String))? {
        get { state.lock.withLock { state.handler } }
        set { state.lock.withLock { state.handler = newValue } }
    }
    static func reset() { state.lock.withLock { state.requests = []; state.handler = nil } }
    static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            // Materialize URLSession's stream once so assertions can inspect it after completion.
            var recorded = request
            if recorded.httpBody == nil, request.httpBodyStream != nil {
                recorded.httpBody = try JSONSerialization.data(withJSONObject: Self.body(request))
            }
            let handler = Self.state.lock.withLock { Self.state.requests.append(recorded); return Self.state.handler }
            guard let handler else { throw URLError(.badServerResponse) }
            let (status, body) = try handler(recorded)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
