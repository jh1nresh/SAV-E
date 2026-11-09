#if SAVVY_CITY_MVP
import Foundation

/// Used only by the native pinch UI test. Records public landmark geometry, never vault data.
@MainActor
enum CityDistrictTrace {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--verify-xinyi")
    private static let handle: FileHandle? = {
        guard enabled else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xinyi-zoom.tsv")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return nil }
        return try? FileHandle(forWritingTo: url)
    }()

    static func write(_ row: String) {
        guard let handle else { return }
        try? handle.write(contentsOf: Data((row + "\n").utf8))
    }
}
#endif
