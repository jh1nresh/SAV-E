import Foundation
import CryptoKit

// Only the existing service signatures are stubbed; exporter code is compiled
// directly from the production source file by the runner.
@MainActor final class SupabaseService {
    static let shared = SupabaseService()
    func debugRawGET(path: String, baseURL: String) async throws -> Data { throw FixtureError.failed }
}
enum SAVEProductionConfig {
    static let defaultAPIBaseURL = "https://wanderly-api-production.up.railway.app"
    static func URLConfigValue(for keys: [String]) -> String? { nil }
}
enum FixtureError: Error { case failed }

@main struct AccountExportCheck {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("savvy-export-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = SAVEProductionConfig.defaultAPIBaseURL
        let listID = "11111111-1111-4111-8111-111111111111"
        let profile = Data(#"{"id":"fixture-account"}"#.utf8)
        let empty = Data("[]".utf8)
        func response(_ path: String, role: String = "owner") -> Data {
            if path == "/profile" { return profile }
            if path == "/v0/lists" {
                return Data("[{\"id\":\"\(listID)\",\"viewer_role\":\"\(role)\",\"items\":[]}]".utf8)
            }
            return empty
        }
        func manifest(_ dir: URL) throws -> DebugVaultExporter.Manifest {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DebugVaultExporter.Manifest.self,
                                      from: Data(contentsOf: dir.appendingPathComponent("manifest.json")))
        }
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }

        var calls: [String] = []
        let first = try await DebugVaultExporter.export(to: root, source: source) { path in
            calls.append(path); return response(path)
        }
        let good = try manifest(first)
        check(good.allRequestsSucceeded && !good.safeToCutOver, "snapshot cannot authorize cutover")
        check(calls.contains("/memory/captures") && calls.contains("/v0/recommendation-outcomes"), "core account coverage")
        check(calls.contains("/v0/lists/\(listID)/members"), "members exported")
        check(calls.contains("/v0/lists/\(listID)/share-codes"), "owner codes exported")
        for entry in good.entries {
            let data = try Data(contentsOf: first.appendingPathComponent(entry.file))
            check(data.count == entry.bytes, "byte count")
            check(entry.sha256 == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "digest")
            let attributes = try FileManager.default.attributesOfItem(atPath: first.appendingPathComponent(entry.file).path)
            check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private file")
        }
        let savedManifest = try Data(contentsOf: first.appendingPathComponent("manifest.json"))
        let second = try await DebugVaultExporter.export(to: root, source: source) { path in
            if path == "/trips" { throw FixtureError.failed }
            return response(path)
        }
        let partial = try manifest(second)
        check(first != second, "unique snapshot directories")
        check(!partial.allRequestsSucceeded && partial.failedResources.contains("trips"), "partial failure must be explicit")
        check(try Data(contentsOf: first.appendingPathComponent("manifest.json")) == savedManifest, "prior backup immutable")
        check(!FileManager.default.fileExists(atPath: second.appendingPathComponent("trips.json").path), "no stale prior trip data")

        calls = []
        let viewer = try await DebugVaultExporter.export(to: root, source: source) { path in
            calls.append(path); return response(path, role: "viewer")
        }
        check(try manifest(viewer).allRequestsSucceeded, "viewer snapshot")
        check(!calls.contains(where: { $0.hasSuffix("share-codes") }), "never request another owner's share codes")
        let denied = try await DebugVaultExporter.export(to: root, source: source) { path in
            if path.hasSuffix("share-codes") { throw FixtureError.failed }
            return response(path)
        }
        check(!(try manifest(denied).allRequestsSucceeded), "missing owner metadata blocks success")

        for badResponse in ["not json", "{\"error\":\"failed\"}", "[1,2]"] {
            let dir = try await DebugVaultExporter.export(to: root, source: source) { path in
                path == "/places" ? Data(badResponse.utf8) : response(path)
            }
            check(try manifest(dir).failedResources.contains("places"), "invalid payload cannot pass")
        }
        var profiles = 0
        let changed = try await DebugVaultExporter.export(to: root, source: source) { path in
            if path == "/profile" {
                profiles += 1
                if profiles == 2 { return Data(#"{"id":"different-account"}"#.utf8) }
            }
            return response(path)
        }
        check(try manifest(changed).failedResources.contains("account-identity-check"), "identity change blocks success")
        calls = []
        let signedOut = try await DebugVaultExporter.export(to: root, source: source) { path in
            calls.append(path); throw FixtureError.failed
        }
        let signedOutManifest = try manifest(signedOut)
        check(calls == ["/profile"] && !signedOutManifest.allRequestsSucceeded, "stop without account identity")
        let malformedList = try await DebugVaultExporter.export(to: root, source: source) { path in
            path == "/v0/lists" ? Data(#"[{"id":"../../private","viewer_role":"owner","items":[]}]"#.utf8) : response(path)
        }
        check(try manifest(malformedList).failedResources.contains("list-details-invalid"), "malformed list path rejected")
        let emptyIdentity = try await DebugVaultExporter.export(to: root, source: source) { path in
            path == "/profile" ? Data(#"{"id":""}"#.utf8) : response(path)
        }
        check(try manifest(emptyIdentity).failedResources.contains("profile"), "empty identity rejected")
        let duplicate = try await DebugVaultExporter.export(to: root, source: source) { path in
            if path == "/v0/lists" {
                let row = String(data: response(path), encoding: .utf8)!.dropFirst().dropLast()
                return Data("[\(row),\(row)]".utf8)
            }
            return response(path)
        }
        check(try manifest(duplicate).failedResources.contains("list-details-invalid"), "duplicate list cannot overwrite metadata")
        for invalid in ["http://wanderly-api-production.up.railway.app", "https://evil.example", "https://wanderly-api-production.up.railway.app.evil.example", "https://user@wanderly-api-production.up.railway.app", source + "/path", source + "?query=x"] {
            var readCalled = false
            do {
                _ = try await DebugVaultExporter.export(to: root, source: invalid) { _ in readCalled = true; return empty }
                preconditionFailure("invalid source accepted")
            } catch DebugVaultExporter.ExportError.invalidSource { }
            check(!readCalled, "invalid source rejected before authenticated access")
        }
        print("PASS: account export preserves raw bytes and isolated backups; failure, identity, list access and source-boundary fixtures passed. No live data accessed.")
    }
}
