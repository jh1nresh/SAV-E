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

    func testGeminiModelOrderPrimary35FlashWith25FlashFallback() {
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, SAVEProductionConfig.defaultGeminiModelFallbacks)
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, ["gemini-3.5-flash", "gemini-2.5-flash"])
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
