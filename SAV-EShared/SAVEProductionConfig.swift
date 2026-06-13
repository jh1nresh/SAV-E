import Foundation

enum SAVEProductionConfig {
    // Existing App Store identifiers stay on com.wanderly until a separate app migration is planned.
    static let legacyProductionBundleID = "com.wanderly.app"
    static let appGroupSuiteName = "group.com.wanderly.app"
    static let pendingPlacesFileName = "pending-places.json"
    static let pendingReviewCandidatesFileName = "pending-review-candidates.json"

    static let defaultPlaceShareBaseURL = "https://sav-e-app.vercel.app/p"
    static let defaultTripShareBaseURL = "https://sav-e-app.vercel.app/trip"
    static let defaultListShareBaseURL = "https://sav-e-app.vercel.app/list"
    // Strongest current flash-class model first; transport falls back to the
    // next entry on 404 (model unavailable) or 429 (rate limited).
    static let defaultGeminiModelFallbacks = ["gemini-3.5-flash", "gemini-2.5-flash"]

    static func geminiGenerateContentURL(apiKey: String, model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
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

struct SAVEGeminiTransport {
    var modelFallbacks: [String] = SAVEProductionConfig.defaultGeminiModelFallbacks
    var session: URLSession = .shared
    var accessTokenProvider: (() async throws -> String)?
    var directAPIKey: String? = SAVEProductionConfig.clientGeminiAPIKeyIfAllowed()
    var requestTimeout: TimeInterval = 30
    var maxAttemptsPerModel: Int = 2
    var transientRetryDelayNanoseconds: UInt64 = 500_000_000

    func generateContent(body: [String: Any]) async throws -> [String: Any] {
        var lastError: Error?
        for model in modelFallbacks {
            do {
                return try await generateContentWithRetry(body: body, model: model)
            } catch {
                lastError = error
                if case SAVEGeminiTransportError.upstreamStatus(let status) = error,
                   status == 404 || status == 429 || (500...599).contains(status) {
                    continue
                }
                break
            }
        }
        throw lastError ?? SAVEGeminiTransportError.emptyResponse
    }

    private func generateContentWithRetry(body: [String: Any], model: String) async throws -> [String: Any] {
        let attempts = max(maxAttemptsPerModel, 1)
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await generateContent(body: body, model: model)
            } catch {
                lastError = error
                guard attempt < attempts, isTransientError(error) else { throw error }
                // Brief backoff so a momentary 429/5xx/network blip does not
                // fail the whole link parse.
                try? await Task.sleep(nanoseconds: transientRetryDelayNanoseconds << UInt64(attempt - 1))
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
        guard let directAPIKey, !directAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SAVEGeminiTransportError.notConfigured
        }
        return try await generateDirect(body: body, model: model, apiKey: directAPIKey)
    }

    private func generateViaBackendProxy(body: [String: Any], model: String) async throws -> [String: Any]? {
        guard let apiBaseURL = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let accessTokenProvider else {
            return nil
        }
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
        request.setValue("Bearer \(try await accessTokenProvider())", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody
        return try await decodeResponse(for: request)
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

    private func decodeResponse(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SAVEGeminiTransportError.emptyResponse
        }
        guard http.statusCode == 200 else {
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
    case upstreamStatus(Int)
    case emptyResponse
}
