#if DEBUG
import Foundation

/// One-shot account data export for backend migrations.
///
/// Launch with `--debug-export-vault` while signed in: every core account
/// resource is fetched through the normal authenticated service layer and
/// written verbatim to `Documents/vault-export/`. Tokens never leave the
/// process; pull the files with
/// `xcrun simctl get_app_container <udid> com.wanderly.app data`.
enum DebugVaultExporter {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-export-vault")
    }

    private static let exports: [(name: String, path: String)] = [
        ("profile", "/profile"),
        ("places", "/places"),
        ("trips", "/trips"),
        ("memory-candidates", "/memory/candidates"),
        ("memory-preferences", "/v0/memory-preferences"),
    ]

    /// Fetches every export path, writing one JSON file per resource.
    /// Retries transient failures so a slow token refresh doesn't strand
    /// the run. Prints a per-file verdict and the output directory.
    static func run(service: SupabaseService = .shared) async {
        let directory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("vault-export", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for export in exports {
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    let data = try await service.debugRawGET(path: export.path)
                    try data.write(to: directory.appendingPathComponent("\(export.name).json"))
                    print("[vault-export] \(export.name): \(data.count) bytes")
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    if attempt < 3 {
                        try? await Task.sleep(for: .seconds(3))
                    }
                }
            }
            if let lastError {
                print("[vault-export] \(export.name) FAILED: \(lastError.localizedDescription)")
            }
        }
        print("[vault-export] done: \(directory.path)")
    }
}
#endif
