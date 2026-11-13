import Foundation

/// Configuration presence is not proof of an SDK, account permission or successful connection.
enum CityMVPConfiguration {
    enum AmapStatus: Equatable { case missingKey, bundleMismatch, sdkNotConnected }
    static func amapStatus(values: [String: String]?, bundleID: String?) -> AmapStatus {
        guard let values, let key = values["APIKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty, !["YOUR_KEY_HERE", "REPLACE_ME"].contains(key) else { return .missingKey }
        guard values["BundleIdentifier"] == bundleID, ["com.wanderly.app", "local.savvy.city-mvp"].contains(bundleID ?? "") else { return .bundleMismatch }
        return .sdkNotConnected
    }
    static var amapStatus: AmapStatus {
        let values = Bundle.main.url(forResource: "Amap.local", withExtension: "plist")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: String] }
        return amapStatus(values: values, bundleID: Bundle.main.bundleIdentifier)
    }
}
