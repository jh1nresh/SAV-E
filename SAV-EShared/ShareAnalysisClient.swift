import Foundation
import Security

/// A revocable analysis-only session. Never contains the user's Privy or model keys.
struct ShareAnalysisCredential: Codable, Equatable, Sendable {
    var token: String
    var ownerSubject: String
    var expiresAt: Date
    var apiBaseURL: String

    func isUsable(at now: Date = Date()) -> Bool {
        !token.isEmpty && !ownerSubject.isEmpty && expiresAt > now &&
            URL(string: apiBaseURL)?.scheme == "https"
    }
}

enum ShareAnalysisKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.wanderly.share-analysis",
         kSecAttrAccount as String: "active-session",
         kSecAttrAccessGroup as String: "JC6858UYM9.group.com.wanderly.app",
         kSecUseDataProtectionKeychain as String: true]
    }

    static func read() -> ShareAnalysisCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(ShareAnalysisCredential.self, from: data)
    }

    static func write(_ credential: ShareAnalysisCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ShareAnalysisError.sessionUnavailable }
    }

    static func clear() { SecItemDelete(query as CFDictionary) }
}

enum ShareAnalysisError: LocalizedError {
    case sessionUnavailable, sessionChanged, serviceUnavailable, noPlaceEvidence, analysisFailed
    case usageLimit, analysisInProgress, timedOut, networkUnavailable
    case sourceUnavailable(reason: String?)

    var errorDescription: String? {
        let zh = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        switch self {
        case .sessionUnavailable:
            return zh ? "請先開啟 Savvy 登入，再回來分享。也可以先保存這個連結。" : "Open Savvy and sign in, then share again. You can also keep this link for later."
        case .sessionChanged:
            return zh ? "帳號已變更，請重新分享以保存在目前帳號。" : "Your account changed. Share again to save to the current account."
        case .serviceUnavailable, .analysisFailed:
            return zh ? "分析暫時無法完成。請重試，或先保存來源。" : "Analysis is temporarily unavailable. Retry or keep the source."
        case .noPlaceEvidence:
            return zh ? "這次未能核對到確切地點。可重試，或先保存來源。" : "No exact place could be verified this time. Retry or keep the source."
        case .usageLimit:
            return zh ? "目前已達分析用量上限。請先保存來源，稍後再試。" : "The analysis usage limit has been reached. Keep the source and try again later."
        case .analysisInProgress:
            return zh ? "這次分析仍在處理中。請稍後重試，或先保存來源。" : "This analysis is still in progress. Retry shortly or keep the source."
        case .timedOut:
            return zh ? "分析等待逾時。請重試以取得結果，或先保存來源。" : "The analysis request timed out. Retry to retrieve the result or keep the source."
        case .networkUnavailable:
            return zh ? "連線中斷。請檢查網路後重試，或先保存來源。" : "The connection was interrupted. Check your network and retry, or keep the source."
        case .sourceUnavailable(let reason):
            switch reason {
            case "login_required":
                return zh ? "Instagram 等來源平台要求登入，暫時讀不到貼文內容。請先保存來源，再於 Savvy 補上貼文文字或地址。" : "The source platform requires a login, so the post could not be read. Keep the source, then add its caption or address in Savvy."
            case "expired":
                return zh ? "來源連結已失效或內容已移除。請先保存來源，再於 Savvy 補上貼文文字或地址。" : "The source link has expired or its content was removed. Keep the source, then add its caption or address in Savvy."
            case "source_out_of_bounds":
                return zh ? "貼文文字超過分析長度上限。請先保存來源，再於 Savvy 補上較短的原文或地址。" : "The post exceeds the analysis text limit. Keep the source, then add a shorter original caption or address in Savvy."
            default:
                return zh ? "暫時讀不到足夠的貼文內容。請先保存來源，再於 Savvy 補上貼文文字或地址。" : "There is not enough readable post content. Keep the source, then add its caption or address in Savvy."
            }
        }
    }
}

struct ShareAnalysisCandidate: Decodable, Sendable {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var placeId: String?
    var types: [String]?
    var evidence: [String]
    var confidence: Double
    var missingInfo: [String]

    var isVerified: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let placeId, !placeId.isEmpty, let latitude, let longitude else { return false }
        return latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    var category: String {
        let types = types ?? []
        if types.contains("cafe") { return "cafe" }
        if types.contains("restaurant") || types.contains("food") { return "food" }
        if types.contains("lodging") { return "stay" }
        if types.contains("bar") { return "bar" }
        if types.contains("store") || types.contains("shopping_mall") { return "shopping" }
        return "attraction"
    }
}

struct ShareAnalysisResponse: Decodable, Sendable {
    struct Receipt: Decodable, Sendable {
        struct FailureReason: Decodable, Sendable {
            var kind: String
            var reason: String?
        }
        var failureReason: FailureReason?
    }
    var ownerSubject: String
    var candidates: [ShareAnalysisCandidate]
    var semanticStatus: String?
    var receipt: Receipt?
    var pendingError: ShareAnalysisError {
        guard let failure = receipt?.failureReason, failure.kind == "insufficient_source" else {
            return .serviceUnavailable
        }
        return .sourceUnavailable(reason: failure.reason)
    }
    enum CodingKeys: String, CodingKey { case ownerSubject = "owner_subject", candidates, semanticStatus, receipt }
}

struct ShareAnalysisClient: Sendable {
    var session: URLSession = .shared

    func issue(bearer: String, ownerSubject: String, installationID: String, apiBaseURL: String) async throws -> ShareAnalysisCredential {
        var request = try request(base: apiBaseURL, path: "sessions", method: "POST")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["installation_id": installationID])
        let data = try await send(request)
        struct Issued: Decodable { let token: String; let owner_subject: String; let expires_at: String }
        let issued = try JSONDecoder().decode(Issued.self, from: data)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard issued.owner_subject == ownerSubject,
              let expiresAt = fractional.date(from: issued.expires_at) ?? ISO8601DateFormatter().date(from: issued.expires_at) else {
            throw ShareAnalysisError.sessionChanged
        }
        let credential = ShareAnalysisCredential(token: issued.token, ownerSubject: ownerSubject, expiresAt: expiresAt, apiBaseURL: apiBaseURL)
        guard credential.isUsable() else { throw ShareAnalysisError.sessionUnavailable }
        return credential
    }

    func revoke(_ credential: ShareAnalysisCredential) async {
        guard var request = try? request(base: credential.apiBaseURL, path: "sessions", method: "DELETE") else { return }
        request.setValue(credential.token, forHTTPHeaderField: "x-save-share-token")
        _ = try? await send(request)
    }

    func analyze(sourceURL: String, caption: String, credential: ShareAnalysisCredential, analysisID: UUID = UUID()) async throws -> ShareAnalysisResponse {
        guard credential.isUsable() else { throw ShareAnalysisError.sessionUnavailable }
        var request = try request(base: credential.apiBaseURL, path: "analyze", method: "POST")
        request.timeoutInterval = 90
        request.setValue(credential.token, forHTTPHeaderField: "x-save-share-token")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "source_url": sourceURL, "caption": caption, "analysis_id": analysisID.uuidString
        ])
        let result = try JSONDecoder().decode(ShareAnalysisResponse.self, from: await send(request))
        guard result.ownerSubject == credential.ownerSubject else { throw ShareAnalysisError.sessionChanged }
        return result
    }

    private func request(base: String, path: String, method: String) throws -> URLRequest {
        guard let origin = URL(string: base), origin.scheme == "https", origin.host != nil,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v0/share-extension/" + path) else {
            throw ShareAnalysisError.serviceUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: ShareAnalysisNoRedirect())
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw ShareAnalysisError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw ShareAnalysisError.networkUnavailable
            default: throw error
            }
        }
        guard let http = response as? HTTPURLResponse else { throw ShareAnalysisError.serviceUnavailable }
        if http.statusCode == 401 { throw ShareAnalysisError.sessionUnavailable }
        guard data.count <= 1_000_000 else { throw ShareAnalysisError.serviceUnavailable }
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
        if http.statusCode == 429, code == "analysis_limit_exceeded" { throw ShareAnalysisError.usageLimit }
        if http.statusCode == 409 {
            if code == "analysis_failed" { throw ShareAnalysisError.analysisFailed }
            if code == "analysis_in_progress" { throw ShareAnalysisError.analysisInProgress }
        }
        guard (200..<300).contains(http.statusCode), data.count <= 1_000_000 else { throw ShareAnalysisError.serviceUnavailable }
        return data
    }
}

private final class ShareAnalysisNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the scoped credential or Privy bearer to a redirect.
        completionHandler(nil)
    }
}
