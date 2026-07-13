import XCTest
@testable import SAVE

final class SaveSearchIntentEvalTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Expected: Decodable {
            let requiredCategories: [String]?
            let locationMode: String?
            let mustMatchCategory: Bool?
            let mustMatchLocation: Bool?
            let supportedCategory: Bool?
            let shouldNotReturnCafeOrFood: Bool?
            let requiresSpecificEvidenceMatch: Bool?
            let localizedRecommendationLabel: String?
        }

        let query: String
        let expected: Expected
    }

    @MainActor
    func testDeterministicParserPassesCoreIntentFixtures() throws {
        let parser = SaveSearchIntentParser()

        for fixture in try loadFixtures() {
            let intent = try XCTUnwrap(parser.parse(fixture.query), "Missing intent for \(fixture.query)")

            if fixture.expected.supportedCategory == false {
                XCTAssertNotNil(intent.unsupportedCategoryLabel, fixture.query)
                XCTAssertTrue(intent.requiredCategories.isEmpty, fixture.query)
                XCTAssertFalse(intent.requiredCategories.contains(.cafe), fixture.query)
                XCTAssertFalse(intent.requiredCategories.contains(.food), fixture.query)
                continue
            }

            let expectedCategories = Set((fixture.expected.requiredCategories ?? []).compactMap(PlaceCategory.init(rawValue:)))
            XCTAssertEqual(intent.requiredCategories, expectedCategories, fixture.query)
            if let mustMatchCategory = fixture.expected.mustMatchCategory {
                XCTAssertEqual(intent.mustMatchCategory, mustMatchCategory, fixture.query)
            }
            if let mustMatchLocation = fixture.expected.mustMatchLocation {
                XCTAssertEqual(intent.mustMatchLocation, mustMatchLocation, fixture.query)
            }
            if let requiresSpecificEvidenceMatch = fixture.expected.requiresSpecificEvidenceMatch {
                XCTAssertEqual(intent.requiresSpecificEvidenceMatch, requiresSpecificEvidenceMatch, fixture.query)
            }
            if let localizedRecommendationLabel = fixture.expected.localizedRecommendationLabel {
                XCTAssertEqual(intent.localizedRecommendationLabel, localizedRecommendationLabel, fixture.query)
            }
            XCTAssertEqual(locationModeLabel(intent.locationMode), fixture.expected.locationMode, fixture.query)
        }
    }

    @MainActor
    func testGeminiModelOrderPrimary35FlashWith25FlashFallback() {
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, SAVEProductionConfig.defaultGeminiModelFallbacks)
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, ["gemini-3.5-flash", "gemini-2.5-flash"])
    }

    func testMemoryOutcomeFailureFixturesCoverRequiredScrubbedGroups() throws {
        struct MemoryFixture: Decodable {
            let id: String
            let failureGroup: String
            let baselinePass: Bool
            let postChangePass: Bool
            let expected: String

            enum CodingKeys: String, CodingKey {
                case id, expected
                case failureGroup = "failure_group"
                case baselinePass = "baseline_pass"
                case postChangePass = "post_change_pass"
            }
        }
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SaveMemoryOutcomeEvalFixtures.json")
        let data = try Data(contentsOf: url)
        let fixtures = try JSONDecoder().decode([MemoryFixture].self, from: data)
        let requiredGroups = Set([
            "wrong_place_entity_resolution",
            "saved_place_missing_after_import_sync",
            "relevant_saved_place_not_retrieved",
            "unrelated_memory_pollution",
            "stale_place_or_menu_fact",
            "preference_mismatch",
            "hallucinated_evidence_or_action_overclaim",
            "correction_removal_not_reflected"
        ])

        XCTAssertEqual(fixtures.count, 8)
        XCTAssertEqual(Set(fixtures.map(\.failureGroup)), requiredGroups)
        XCTAssertEqual(fixtures.filter(\.baselinePass).count, 5)
        XCTAssertTrue(fixtures.allSatisfy(\.postChangePass))
        XCTAssertTrue(fixtures.allSatisfy { !$0.id.isEmpty && !$0.expected.isEmpty })
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(raw.contains("http://"))
        XCTAssertFalse(raw.contains("https://"))
        XCTAssertNil(raw.range(of: #"\+?\d[\d\s().-]{7,}"#, options: .regularExpression))
    }

    private func loadFixtures() throws -> [Fixture] {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AskSaveIntentEvalFixtures.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode([Fixture].self, from: data)
    }

    @MainActor
    private func locationModeLabel(_ mode: SaveSearchIntent.LocationMode) -> String {
        switch mode {
        case .currentLocation:
            return "currentLocation"
        case .mapRegion:
            return "mapRegion"
        case .namedArea(let area):
            return "namedArea:\(area)"
        case .savedAnywhere:
            return "savedAnywhere"
        case .unspecified:
            return "unspecified"
        }
    }
}
