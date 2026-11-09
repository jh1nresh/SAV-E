#if DEBUG
import CryptoKit
import Foundation

/// Account API preservation only: never imports data or switches the app backend.
/// Launch while signed in with --debug-export-vault. The optional
/// --debug-export-vault-api accepts only the two known Savvy backends.
/// Credentials remain inside SupabaseService; personal responses stay in a
/// private, unique Documents/vault-export/<UUID>/ directory on this device.
@MainActor
enum DebugVaultExporter {
    static var isServiceDiagnosisRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-diagnose-sharing")
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-export-vault")
            || ProcessInfo.processInfo.arguments.contains("--debug-export-vault-pair")
    }

    struct Entry: Codable {
        let path: String
        let file: String
        let bytes: Int
        let sha256: String
    }

    struct ServiceCheck: Codable {
        let path: String
        let result: String
        let httpStatus: Int?
        var accountState: String? = nil
        var accountReferenceValid: Bool? = nil
        var accountVersionSupported: Bool? = nil
    }

    struct Manifest: Codable {
        let source: String
        let accountSubjectSHA256: String
        let startedAt: Date
        var finishedAt: Date?
        var entries: [Entry] = []
        var failedResources: [String] = []
        var serviceChecks: [ServiceCheck] = []
        var allRequestsSucceeded = false
        // Even a successful API snapshot omits device-only state, binary media,
        // other accounts, and backend resources without account export routes.
        let safeToCutOver: Bool
    }

    enum ExportError: Error {
        case invalidSource, malformedResponse, identityChanged
    }

    /// Status-only diagnostics remain usable when account verification fails.
    /// No response bodies, credentials, or account bindings are persisted.
    static func diagnoseServices(
        source: String,
        read: (String) async throws -> Data
    ) async throws -> [ServiceCheck] {
        _ = try validatedSource(source)
        var checks: [ServiceCheck] = []
        for path in ["/v0/account-status", "/profile", "/v0/shared-posts", "/v0/shared-posts/mine", "/v0/social-profile", "/v0/lists"] {
            do {
                let data = try await read(path)
                var check = ServiceCheck(path: path, result: "http_success", httpStatus: nil)
                if path == "/v0/account-status" {
                    if let status = try? JSONDecoder().decode(AccountStatusResponse.self, from: data) {
                        check.accountState = status.state.rawValue
                        check.accountReferenceValid = status.accountRef.map(AccountGatePolicy.isValidAccountRef) ?? false
                        check.accountVersionSupported = status.version == "v0"
                    } else {
                        check.accountState = "invalid_payload"
                    }
                }
                checks.append(check)
            } catch is CancellationError {
                throw CancellationError()
            } catch ExportError.identityChanged {
                throw ExportError.identityChanged
            } catch {
                if case SupabaseError.apiError(let code, _) = error {
                    checks.append(ServiceCheck(path: path, result: "http_failure", httpStatus: code))
                } else if case SupabaseError.notAuthenticated = error {
                    checks.append(ServiceCheck(path: path, result: "authentication_failure", httpStatus: nil))
                } else {
                    checks.append(ServiceCheck(path: path, result: "request_failure", httpStatus: nil))
                }
            }
        }
        return checks
    }

    static func runServiceDiagnosis(service: SupabaseService = .shared) async {
        do {
            guard !PrivyAuthService.shared.isReviewerDemo,
                  let subject = PrivyAuthService.shared.currentUserId else { return }
            let generation = PrivyAuthService.shared.sessionGeneration
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("service-diagnosis", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for (name, source) in [("legacy", "https://wanderly-api-production.up.railway.app"),
                                   ("managed", "https://save-backend-production.up.railway.app")] {
                let checks = try await diagnoseServices(source: source) { path in
                    try Task.checkCancellation()
                    guard generation == PrivyAuthService.shared.sessionGeneration,
                          subject == PrivyAuthService.shared.currentUserId else { throw ExportError.identityChanged }
                    let data = try await service.debugRawGET(path: path, baseURL: source)
                    guard generation == PrivyAuthService.shared.sessionGeneration,
                          subject == PrivyAuthService.shared.currentUserId else { throw ExportError.identityChanged }
                    return data
                }
                try Task.checkCancellation()
                guard generation == PrivyAuthService.shared.sessionGeneration,
                      subject == PrivyAuthService.shared.currentUserId else { throw ExportError.identityChanged }
                let file = root.appendingPathComponent("\(name).json")
                try encoder.encode(checks).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            print("[service-diagnosis] Finished; status metadata only.")
        } catch {
            print("[service-diagnosis] Interrupted or incomplete.")
        }
    }

    private static let exports = [
        ("places", "/places"),
        ("trips", "/trips"),
        ("memory-candidates", "/memory/candidates"),
        ("memory-captures", "/memory/captures"),
        ("memory-preferences", "/v0/memory-preferences"),
        ("recommendation-outcomes", "/v0/recommendation-outcomes"),
        ("lists", "/v0/lists"),
    ]

    static func validatedSource(_ raw: String) throws -> String {
        guard let url = URL(string: raw), url.scheme == "https",
              ["wanderly-api-production.up.railway.app", "save-backend-production.up.railway.app"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw ExportError.invalidSource
        }
        return "https://\(url.host!)"
    }

    static func run(service: SupabaseService = .shared) async {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            guard !PrivyAuthService.shared.isReviewerDemo,
                  let subject = PrivyAuthService.shared.currentUserId else {
                throw ExportError.identityChanged
            }
            let generation = PrivyAuthService.shared.sessionGeneration
            let sources: [String]
            if arguments.contains("--debug-export-vault-pair") {
                // The same authenticated session reads both origins. No write,
                // migration or normal API configuration change happens here.
                sources = ["https://wanderly-api-production.up.railway.app",
                           "https://save-backend-production.up.railway.app"]
            } else if let index = arguments.firstIndex(of: "--debug-export-vault-api") {
                guard arguments.indices.contains(index + 1) else { throw ExportError.invalidSource }
                sources = [try validatedSource(arguments[index + 1])]
            } else {
                sources = [try validatedSource(
                    SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"])
                        ?? SAVEProductionConfig.defaultAPIBaseURL)]
            }
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("vault-export", isDirectory: true)
            for source in sources {
                let directory = try await export(to: root, source: source, accountSubject: subject) { path in
                    guard generation == PrivyAuthService.shared.sessionGeneration,
                          subject == PrivyAuthService.shared.currentUserId else { throw ExportError.identityChanged }
                    let data = try await service.debugRawGET(path: path, baseURL: source)
                    guard generation == PrivyAuthService.shared.sessionGeneration,
                          subject == PrivyAuthService.shared.currentUserId else { throw ExportError.identityChanged }
                    return data
                }
                print("[vault-export] Finished; inspect manifest.json before using: \(directory.path)")
            }
        } catch {
            // Network error descriptions may contain private response bodies.
            print("[vault-export] FAILED; no complete export was produced.")
        }
    }

    static func export(
        to root: URL,
        source: String,
        accountSubject: String,
        read: (String) async throws -> Data
    ) async throws -> URL {
        let source = try validatedSource(source)
        guard !accountSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExportError.identityChanged }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        var manifest = Manifest(source: source, accountSubjectSHA256: SHA256.hash(data: Data(accountSubject.utf8)).map { String(format: "%02x", $0) }.joined(), startedAt: Date(), safeToCutOver: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        func write(_ data: Data, file: String) throws {
            let url = directory.appendingPathComponent(file)
            try data.write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        func checkpoint() throws {
            try write(encoder.encode(manifest), file: "manifest.json")
        }
        func capture(_ name: String, path: String, profile: Bool = false) async throws -> Any? {
            do {
                let data = try await read(path)
                let json = try JSONSerialization.jsonObject(with: data)
                if profile {
                    guard let id = (json as? [String: Any])?["id"] as? String, !id.isEmpty else {
                        throw ExportError.malformedResponse
                    }
                } else if !(json is [[String: Any]]) {
                    throw ExportError.malformedResponse
                }
                try write(data, file: "\(name).json")
                manifest.entries.append(Entry(path: path, file: "\(name).json", bytes: data.count,
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
                try checkpoint()
                return json
            } catch {
                manifest.failedResources.append(name)
                try checkpoint()
                return nil
            }
        }

        // A manifest exists from the beginning; interruption never leaves a
        // previous run's successful manifest next to this run's partial files.
        try checkpoint()
        guard let profile = try await capture("profile", path: "/profile", profile: true) as? [String: Any],
              let accountID = profile["id"] as? String, !accountID.isEmpty else {
            manifest.finishedAt = Date()
            try checkpoint()
            return directory
        }
        for (name, path) in exports {
            let json = try await capture(name, path: path)
            if name == "lists", let lists = json as? [[String: Any]] {
                var seenIDs = Set<UUID>()
                for list in lists {
                    guard let rawID = list["id"] as? String, let id = UUID(uuidString: rawID),
                          let role = list["viewer_role"] as? String,
                          ["owner", "editor", "viewer"].contains(role),
                          list["items"] is [[String: Any]], seenIDs.insert(id).inserted else {
                        manifest.failedResources.append("list-details-invalid")
                        continue
                    }
                    let key = id.uuidString.lowercased()
                    _ = try await capture("list-\(key)-members", path: "/v0/lists/\(key)/members")
                    if role == "owner" {
                        _ = try await capture("list-\(key)-share-codes", path: "/v0/lists/\(key)/share-codes")
                    }
                }
            }
        }
        // Probe precisely the two reads behind Passport's generic error card.
        // Record no response body or token, and do not equate HTTP success with
        // a complete sharing/data migration verification.
        for path in ["/v0/shared-posts/mine", "/v0/social-profile"] {
            do {
                _ = try await read(path)
                manifest.serviceChecks.append(ServiceCheck(path: path, result: "http_success", httpStatus: nil))
            } catch {
                let result: String
                let status: Int?
                if case SupabaseError.apiError(let code, _) = error {
                    result = "http_failure"; status = code
                } else if case SupabaseError.notAuthenticated = error {
                    result = "authentication_failure"; status = nil
                } else {
                    result = "request_failure"; status = nil
                }
                manifest.serviceChecks.append(ServiceCheck(path: path, result: result, httpStatus: status))
            }
        }
        do {
            let finalProfile = try JSONSerialization.jsonObject(with: await read("/profile")) as? [String: Any]
            guard finalProfile?["id"] as? String == accountID else { throw ExportError.identityChanged }
        } catch {
            manifest.failedResources.append("account-identity-check")
        }
        manifest.finishedAt = Date()
        manifest.allRequestsSucceeded = manifest.failedResources.isEmpty
        try checkpoint()
        return directory
    }
}
#endif
