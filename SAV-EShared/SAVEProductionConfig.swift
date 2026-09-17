import Foundation

enum SAVEProductionConfig {
    // Existing App Store identifiers stay on com.wanderly until a separate app migration is planned.
    static let legacyProductionBundleID = "com.wanderly.app"
    nonisolated static let appGroupSuiteName = "group.com.wanderly.app"
    nonisolated static let currentCustomURLScheme = "savvy"
    nonisolated static let legacyCustomURLScheme = "wanderly"
    static let pendingPlacesFileName = "pending-places.json"
    static let pendingReviewCandidatesFileName = "pending-review-candidates.json"

    static let defaultPlaceShareBaseURL = "https://sav-e-app.vercel.app/p"
    static let defaultTripShareBaseURL = "https://sav-e-app.vercel.app/trip"
    static let defaultListShareBaseURL = "https://sav-e-app.vercel.app/list"
    static let defaultAPIBaseURL = "https://wanderly-api-production.up.railway.app"
    // Strongest current flash-class model first; transport falls back to the
    // next entry on 404 (model unavailable) or 429 (rate limited).
    static let defaultGeminiModelFallbacks = ["gemini-3.5-flash", "gemini-2.5-flash"]

    static func geminiGenerateContentURL(apiKey: String, model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
    }

    nonisolated static func supportsCustomURLScheme(_ url: URL) -> Bool {
        url.scheme == currentCustomURLScheme || url.scheme == legacyCustomURLScheme
    }

    static func allowsClientGeminiFallback(bundle: Bundle = .main) -> Bool {
        let value = configValue(for: ["SAVE_ALLOW_CLIENT_GEMINI"], bundle: bundle)?.lowercased()
        return value == "true" || value == "1" || value == "yes"
    }

    static func clientGeminiAPIKeyIfAllowed(bundle: Bundle = .main) -> String? {
        guard allowsClientGeminiFallback(bundle: bundle) else { return nil }
        return configValue(for: ["GEMINI_API_KEY"], bundle: bundle)
    }

    static func configValue(for keys: [String], bundle: Bundle = .main) -> String? {
        for key in keys {
            if let value = normalizedConfigValue(ProcessInfo.processInfo.environment[key]) {
                return value
            }
            if let value = normalizedConfigValue(keyFromPlist(key, bundle: bundle)) {
                return value
            }
        }
        return nil
    }

    static func URLConfigValue(for keys: [String], bundle: Bundle = .main) -> String? {
        configValue(for: keys, bundle: bundle).map(removingTrailingSlashes(from:))
    }

    static func keyFromPlist(_ key: String, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return nil }
        return dict[key]
    }

    static func normalizedConfigValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "YOUR_KEY_HERE",
              value != "REPLACE_ME"
        else { return nil }
        return value
    }

    static func removingTrailingSlashes(from value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

// Per-import correlation never enters place evidence, notes, or share payloads.
enum SAVEAnalysisScope {
    @TaskLocal static var current: SAVEAnalysisContext?

    static func measure<T>(_ operation: SAVEAnalysisClientEvent.Operation, outcome: (T) -> SAVEAnalysisClientEvent.Outcome = { _ in .success }, work: () async throws -> T) async rethrows -> T {
        guard let context = current else { return try await work() }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let result = try await work()
            await context.record(operation, outcome: outcome(result), started: started)
            return result
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            await context.record(operation, outcome: cancelled ? .cancelled : .failure, started: started)
            throw error
        }
    }

    static func httpOutcome(_ result: (Data, URLResponse)) -> SAVEAnalysisClientEvent.Outcome {
        guard let response = result.1 as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return .failure }
        return .success
    }
}

struct SAVEAnalysisClientEvent: Codable, Sendable {
    enum Operation: String, Codable, Sendable {
        case metadata, publicSearch = "public_search", appleMaps = "apple_maps"
        case chinaPlaces = "china_places", localOCR = "local_ocr"
    }
    enum Outcome: String, Codable, Sendable { case success, failure, cancelled }
    let event_id: UUID
    let operation: Operation
    let outcome: Outcome
    let duration_ms: Int
}

actor SAVEAnalysisContext {
    nonisolated let id: UUID
    private var events: [SAVEAnalysisClientEvent] = []
    private var eventsTruncated = false
    private var captureIDs: [UUID] = []
    private var hasReviewCandidate = false
    private var providerFailed = false
    private var denied = false

    init(id: UUID) { self.id = id }
    func record(_ operation: SAVEAnalysisClientEvent.Operation, outcome: SAVEAnalysisClientEvent.Outcome, started: TimeInterval) {
        // Bound payloads and never accept arbitrary source/query/error strings.
        guard events.count < 64 else { eventsTruncated = true; return }
        events.append(SAVEAnalysisClientEvent(event_id: UUID(), operation: operation, outcome: outcome,
            duration_ms: min(300_000, max(0, Int((ProcessInfo.processInfo.systemUptime - started) * 1000)))))
    }
    func addCapture(_ id: UUID) { if !captureIDs.contains(id) { captureIDs.append(id) } }
    func foundReviewCandidate() { hasReviewCandidate = true }
    func markProviderFailure() { providerFailed = true }
    func markDenied() { denied = true; providerFailed = true }
    func checkAllowed() throws { if denied { throw SAVEAnalysisError.denied } }
    func snapshot(outcome: String? = nil) -> (outcome: String, captureIDs: [UUID], events: [SAVEAnalysisClientEvent], eventsTruncated: Bool) {
        (outcome ?? (hasReviewCandidate ? "review_candidate" : providerFailed ? "failed" : "source_only"), captureIDs, events, eventsTruncated)
    }
}

enum SAVEAnalysisError: LocalizedError {
    case denied
    var errorDescription: String? { "Your source is kept. Analysis is unavailable right now. Please try again later." }
    static func isControlDenial(_ data: Data) -> Bool {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = body["code"] as? String else { return false }
        return ["analysis_limit_exceeded", "analysis_controls_unavailable", "analysis_closed", "analysis_not_found"].contains(code)
    }
}

struct SourceSearchFailureReason: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case insufficientSource = "insufficient_source"
        case providerFailure = "provider_failure"
    }
    let kind: Kind
    let reason: String?
    let stage: String?

    var englishMessage: String {
        if kind == .providerFailure { return "Your source is kept. A lookup service could not finish. Please try again later." }
        switch reason {
        case "login_required": return "This post needs a login. Add its caption, an address, or a screenshot to identify the place."
        case "source_out_of_bounds": return "Your source is kept. The text is too long to analyze; use a shorter source or screenshot."
        case "expired": return "This link has expired. Add the post caption, an address, or a screenshot to identify the place."
        default: return "Your source is kept. Add the post caption, an address, or a screenshot to identify the place."
        }
    }
    var traditionalChineseMessage: String {
        if kind == .providerFailure { return "來源已保留。查詢服務暫時無法完成，請稍後再試。" }
        switch reason {
        case "login_required": return "這則貼文需要登入。請補上貼文文字、地址或截圖，協助辨識地點。"
        case "source_out_of_bounds": return "來源已保留。文字太長，尚未完成分析；請改用較短的原文或截圖。"
        case "expired": return "這個連結已失效。請補上貼文文字、地址或截圖，協助辨識地點。"
        default: return "來源已保留。請補上貼文文字、地址或截圖，協助辨識地點。"
        }
    }
}

struct SAVEGeminiTransport {
    var modelFallbacks: [String] = SAVEProductionConfig.defaultGeminiModelFallbacks
    var session: URLSession = .shared
    var accessTokenProvider: (() async throws -> String)?
    /// App Review demo: returns an anonymous backend guest token when available.
    /// When the normal Privy access token is missing (demo session), the proxy
    /// request authenticates with `x-save-guest-token` instead of a Bearer JWT.
    var guestTokenProvider: (() -> String?)?
    var directAPIKey: String? = SAVEProductionConfig.clientGeminiAPIKeyIfAllowed()
    var apiBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"])
    var requestTimeout: TimeInterval = 30
    var maxAttemptsPerModel: Int = 2
    var transientRetryDelayNanoseconds: UInt64 = 500_000_000

    func generateContent(body: [String: Any]) async throws -> [String: Any] {
        var lastError: Error?
        for model in modelFallbacks {
            do {
                return try await generateContentWithRetry(body: body, model: model)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                if case SAVEGeminiTransportError.unsupportedModel = error {
                    if lastError == nil { lastError = error }
                    continue
                }
                lastError = error
                if case SAVEGeminiTransportError.upstreamStatus(let status) = error,
                   status == 404 || status == 429 || (500...599).contains(status) {
                    continue
                }
                break
            }
        }
        await SAVEAnalysisScope.current?.markProviderFailure()
        throw lastError ?? SAVEGeminiTransportError.emptyResponse
    }

    private func generateContentWithRetry(body: [String: Any], model: String) async throws -> [String: Any] {
        let attempts = max(maxAttemptsPerModel, 1)
        var lastError: Error?
        for attempt in 1...attempts {
            try Task.checkCancellation()
            do {
                return try await generateContent(body: body, model: model)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                lastError = error
                guard attempt < attempts, isTransientError(error) else { throw error }
                // Brief backoff so a momentary 429/5xx/network blip does not
                // fail the whole link parse.
                try await Task.sleep(nanoseconds: transientRetryDelayNanoseconds << UInt64(attempt - 1))
            }
        }
        throw lastError ?? SAVEGeminiTransportError.emptyResponse
    }

    private func isTransientError(_ error: Error) -> Bool {
        if case SAVEGeminiTransportError.upstreamStatus(let status) = error {
            return status == 429 || (500...599).contains(status)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func generateContent(body: [String: Any], model: String) async throws -> [String: Any] {
        if let proxied = try await generateViaBackendProxy(body: body, model: model) {
            return proxied
        }
        guard SAVEAnalysisScope.current == nil else { throw SAVEAnalysisError.denied }
        guard let directAPIKey, !directAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SAVEGeminiTransportError.notConfigured
        }
        return try await generateDirect(body: body, model: model, apiKey: directAPIKey)
    }

    private func generateViaBackendProxy(body: [String: Any], model: String) async throws -> [String: Any]? {
        try await SAVEAnalysisScope.current?.checkAllowed()
        guard let apiBaseURL else {
            return nil
        }
        // Prefer the real Privy JWT. If it's unavailable (App Review demo session,
        // where `accessTokenProvider` throws), fall back to the anonymous guest
        // token via the `x-save-guest-token` header which the proxy accepts.
        let guestToken = guestTokenProvider?().flatMap { $0.isEmpty ? nil : $0 }
        let authorization: (header: String, value: String)?
        if let accessTokenProvider {
            do {
                authorization = ("Authorization", "Bearer \(try await accessTokenProvider())")
            } catch {
                // No Privy JWT. Use the guest token if we have one (demo mode);
                // otherwise preserve the original behavior and surface the error.
                guard let guestToken else { throw error }
                authorization = ("x-save-guest-token", guestToken)
            }
        } else if let guestToken {
            authorization = ("x-save-guest-token", guestToken)
        } else {
            return nil
        }
        guard let authorization else { return nil }

        var proxyBody = body
        proxyBody["model"] = model
        let requestBody = try JSONSerialization.data(withJSONObject: proxyBody)
        guard let url = URL(string: "\(apiBaseURL)/v0/llm/gemini-generate-content") else {
            throw SAVEGeminiTransportError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.setValue(SAVEAnalysisScope.current?.id.uuidString, forHTTPHeaderField: "x-save-analysis-id")
        request.httpBody = requestBody
        return try await decodeResponse(for: request, isBackendProxy: true)
    }

    private func generateDirect(body: [String: Any], model: String, apiKey: String) async throws -> [String: Any] {
        let endpoint = SAVEProductionConfig.geminiGenerateContentURL(apiKey: apiKey, model: model)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await decodeResponse(for: request)
    }

    private struct ProxyErrorEnvelope: Decodable {
        let error: String
        let status: Int?
    }

    private func decodeResponse(for request: URLRequest, isBackendProxy: Bool = false) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SAVEGeminiTransportError.emptyResponse
        }
        guard http.statusCode == 200 else {
            if isBackendProxy, SAVEAnalysisError.isControlDenial(data) {
                await SAVEAnalysisScope.current?.markDenied()
                throw SAVEAnalysisError.denied
            }
            if isBackendProxy, http.statusCode != 401, http.statusCode != 403,
               let envelope = try? JSONDecoder().decode(ProxyErrorEnvelope.self, from: data) {
                if http.statusCode == 400, envelope.error == "Unsupported Gemini model" {
                    throw SAVEGeminiTransportError.unsupportedModel
                }
                if (500...599).contains(http.statusCode), envelope.error == "Gemini upstream request failed",
                   let status = envelope.status, (400...599).contains(status) {
                    throw SAVEGeminiTransportError.upstreamStatus(status)
                }
            }
            throw SAVEGeminiTransportError.upstreamStatus(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SAVEGeminiTransportError.emptyResponse
        }
        return json
    }
}

enum SAVEGeminiTransportError: Error {
    case notConfigured
    case unsupportedModel
    case upstreamStatus(Int)
    case emptyResponse
}
