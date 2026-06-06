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
    static let defaultGeminiModelFallbacks = ["gemini-3.5-flash"]

    static func geminiGenerateContentURL(apiKey: String, model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
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
