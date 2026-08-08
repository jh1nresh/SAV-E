#if DEBUG
import Foundation

/// One-shot copy of pre-rebuild account data out of the legacy backend.
///
/// The 2026-08-04 rebuild left the old deployment running but unreachable as
/// an account: its Railway login is lost, so the database behind it cannot be
/// dumped. The service itself still answers, and both deployments verify the
/// same Privy tokens — so the one credential that can still cross the gap is
/// the signed-in user's own session, which stays inside this process.
///
/// Launch with `--debug-migrate-legacy` while signed in for a dry run that
/// only prints what would move. Add `--debug-migrate-legacy-commit` to write.
/// Records keep their original ids, and anything whose id the current backend
/// already has is skipped, so the run is idempotent and re-runnable.
enum DebugLegacyMigrator {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-migrate-legacy")
    }

    static var shouldCommit: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-migrate-legacy-commit")
    }

    static let defaultLegacyBaseURL = "https://wanderly-api-production.up.railway.app"

    static var legacyBaseURL: String {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--debug-legacy-api"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return defaultLegacyBaseURL
    }

    /// Resources that migrate, in dependency order: trips reference places.
    private static let resources = ["places", "trips"]

    static func run(service: SupabaseService = .shared) async {
        let mode = shouldCommit ? "COMMIT" : "dry-run"
        print("[legacy-migrate] mode=\(mode) legacy=\(legacyBaseURL)")

        for resource in resources {
            do {
                let legacyData = try await fetchWithRetry {
                    try await service.debugRawGET(path: "/\(resource)", baseURL: legacyBaseURL)
                }
                let currentData = try await fetchWithRetry {
                    try await service.debugRawGET(path: "/\(resource)")
                }
                let pending = try recordsToMigrate(legacy: legacyData, current: currentData)
                print("[legacy-migrate] \(resource): legacy has \(try recordCount(legacyData)), current has \(try recordCount(currentData)), missing \(pending.count)")

                guard shouldCommit else {
                    for record in pending.prefix(5) {
                        print("[legacy-migrate]   would copy: \(recordLabel(record))")
                    }
                    if pending.count > 5 {
                        print("[legacy-migrate]   … and \(pending.count - 5) more")
                    }
                    continue
                }

                var copied = 0
                var failed = 0
                for record in pending {
                    do {
                        let body = try JSONSerialization.data(withJSONObject: record)
                        _ = try await service.debugRawPOST(path: "/\(resource)", body: body)
                        copied += 1
                    } catch {
                        failed += 1
                        print("[legacy-migrate]   FAILED \(recordLabel(record)): \(error.localizedDescription)")
                    }
                }
                print("[legacy-migrate] \(resource): copied \(copied), failed \(failed)")
            } catch {
                print("[legacy-migrate] \(resource) ABORTED: \(error.localizedDescription)")
            }
        }
        print("[legacy-migrate] done")
    }

    // MARK: - Pure planning logic (unit-tested)

    /// Legacy records whose id the current backend does not have yet.
    /// Records without a string id never migrate: without one the run cannot
    /// be idempotent, and a second pass would duplicate them.
    static func recordsToMigrate(legacy: Data, current: Data) throws -> [[String: Any]] {
        let legacyRecords = try records(from: legacy)
        let currentIds = Set(try records(from: current).compactMap { $0["id"] as? String })
        return legacyRecords.filter { record in
            guard let id = record["id"] as? String, !id.isEmpty else { return false }
            return !currentIds.contains(id)
        }
    }

    static func recordCount(_ data: Data) throws -> Int {
        try records(from: data).count
    }

    private static func records(from data: Data) throws -> [[String: Any]] {
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw SupabaseError.invalidResponse("Expected a JSON array of records")
        }
        return parsed.compactMap { $0 as? [String: Any] }
    }

    private static func recordLabel(_ record: [String: Any]) -> String {
        let id = record["id"] as? String ?? "?"
        let name = (record["name"] as? String) ?? (record["title"] as? String) ?? ""
        return name.isEmpty ? id : "\(name) (\(id.prefix(8)))"
    }

    private static func fetchWithRetry(_ operation: () async throws -> Data) async throws -> Data {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
        throw lastError ?? SupabaseError.invalidResponse("Unreachable")
    }
}
#endif
