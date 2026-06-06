import XCTest
@testable import SAVE

final class SAVEProductionConfigTests: XCTestCase {
    func testTemplatesUseSaveKeysForProductionConfig() throws {
        let mainTemplate = try plistTemplate(at: "SAV-E/Resources/Secrets.plist.template")
        let shareTemplate = try plistTemplate(at: "SAV-EShareExtension/Secrets.plist.template")

        XCTAssertEqual(mainTemplate["SAVE_API_URL"] as? String, "https://wanderly-api-production.up.railway.app")
        XCTAssertEqual(shareTemplate["SAVE_API_URL"] as? String, "https://wanderly-api-production.up.railway.app")
        XCTAssertEqual(mainTemplate["SAVE_PLACE_SHARE_BASE_URL"] as? String, SAVEProductionConfig.defaultPlaceShareBaseURL)
        XCTAssertEqual(shareTemplate["SAVE_PLACE_SHARE_BASE_URL"] as? String, SAVEProductionConfig.defaultPlaceShareBaseURL)
        XCTAssertEqual(mainTemplate["PRIVY_APP_ID"] as? String, "cmnttqw3q038x0cle8vnlki39")
        XCTAssertEqual(mainTemplate["PRIVY_APP_CLIENT_ID"] as? String, "client-WY6XpSj5cs9CrZjfDUuBAcS1sWtDG5eF1RTqYs9fqmvFw")

        XCTAssertNil(mainTemplate["WANDERLY_API_URL"])
        XCTAssertNil(mainTemplate["WANDERLY_SHARE_BASE_URL"])
        XCTAssertNil(shareTemplate["WANDERLY_API_URL"])
        XCTAssertNil(shareTemplate["WANDERLY_SHARE_BASE_URL"])
    }

    func testConfigNormalizationRejectsPlaceholders() {
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("YOUR_KEY_HERE"))
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("REPLACE_ME"))
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("  "))
        XCTAssertEqual(SAVEProductionConfig.normalizedConfigValue(" https://sav-e-app.vercel.app/p "), "https://sav-e-app.vercel.app/p")
    }

    func testSharedProductionConstantsMatchExistingAppleIdentifiers() {
        XCTAssertEqual(SAVEProductionConfig.legacyProductionBundleID, "com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.appGroupSuiteName, "group.com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.pendingPlacesFileName, "pending-places.json")
        XCTAssertEqual(SAVEProductionConfig.pendingReviewCandidatesFileName, "pending-review-candidates.json")
    }

    func testSharedGeminiModelFallbacksUseAvailableGemini35Flash() {
        XCTAssertEqual(SAVEProductionConfig.defaultGeminiModelFallbacks, ["gemini-3.5-flash"])

        let url = SAVEProductionConfig.geminiGenerateContentURL(apiKey: "test-key", model: "gemini-3.5-flash")
        XCTAssertEqual(
            url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=test-key"
        )
    }

    private func plistTemplate(at relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
