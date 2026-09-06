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
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-export-vault")
    }

    struct Entry: Codable {
        let path: String
        let file: String
        let bytes: Int
        let sha256: String
    }

    struct Manifest: Codable {
        let source: String
        let startedAt: Date
        var finishedAt: Date?
        var entries: [Entry] = []
        var failedResources: [String] = []
        var allRequestsSucceeded = false
        // Even a successful API snapshot omits device-only state, binary media,
        // other accounts, and backend resources without account export routes.
        let safeToCutOver: Bool
    }

    enum ExportError: Error {
        case invalidSource, malformedResponse, identityChanged
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
            let source: String
            if let index = arguments.firstIndex(of: "--debug-export-vault-api") {
                guard arguments.indices.contains(index + 1) else { throw ExportError.invalidSource }
                source = try validatedSource(arguments[index + 1])
            } else {
                source = try validatedSource(
                    SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"])
                        ?? SAVEProductionConfig.defaultAPIBaseURL
                )
            }
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("vault-export", isDirectory: true)
            let directory = try await export(to: root, source: source) { path in
                try await service.debugRawGET(path: path, baseURL: source)
            }
            print("[vault-export] Finished; inspect manifest.json before using: \(directory.path)")
        } catch {
            // Network error descriptions may contain private response bodies.
            print("[vault-export] FAILED; no complete export was produced.")
        }
    }

    static func export(
        to root: URL,
        source: String,
        read: (String) async throws -> Data
    ) async throws -> URL {
        let source = try validatedSource(source)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        var manifest = Manifest(source: source, startedAt: Date(), safeToCutOver: false)
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
