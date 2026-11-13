#if SAVVY_CITY_MVP
import Foundation

/// Local target only. Ordinary launches use the integrated preview; historical
/// experiments remain explicit comparisons instead of silently changing their controls.
@MainActor
enum CityMVPPreviewConfiguration {
    enum Route: String { case preview, comparison }
    static func route(arguments: [String], unitTestHost: Bool) -> Route {
        if unitTestHost || arguments.contains("--citylab-legacy-renderer")
            || arguments.contains(where: { $0.hasPrefix("--verify-") }) { return .comparison }
        return .preview
    }
    static let selectedRoute = route(arguments: ProcessInfo.processInfo.arguments,
        unitTestHost: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil)
    static var enabled: Bool { selectedRoute == .preview }
    /// Exposes read-only sampled state; it never changes route, camera or launch flow.
    static let inspectsPreview = ProcessInfo.processInfo.arguments.contains("--inspect-citylab")
}
#endif
