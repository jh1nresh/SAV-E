import XCTest
@testable import SAVE

final class SavePlanAroundControllerTests: XCTestCase {
    func testPlanAroundSavedAnchorIncludesNearbySavedAndMapSuggestion() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let anchor = place(name: "Sushi Gen", address: "422 E 2nd St, Los Angeles, CA", category: .food, latitude: 34.0478, longitude: -118.2386)
        let coffee = place(name: "Maru Coffee", address: "1019 S Santa Fe Ave, Los Angeles, CA", category: .cafe, latitude: 34.0356, longitude: -118.2296)
        let response = searchController.search(query: "", places: [anchor, coffee], localRecords: [])
        let anchorResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Sushi Gen" })

        let result = planController.planAround(
            anchor: anchorResult,
            savedResults: response.fromYourSave.results,
            mapCandidates: [
                SaveMapCandidate(
                    title: "The Geffen Contemporary at MOCA",
                    subtitle: "Little Tokyo · Museum",
                    latitude: 34.0506,
                    longitude: -118.2396,
                    category: .attraction,
                    evidence: ["Visible nearby on map"]
                )
            ],
            request: SavePlanAroundRequest(anchorResultID: anchorResult.id, duration: .halfDay, intent: .balanced)
        )

        guard case .draft(let draft) = result else {
            return XCTFail("Expected routeable draft")
        }
        XCTAssertEqual(draft.anchor.title, "Sushi Gen")
        XCTAssertEqual(draft.nearbySaved.map(\.title), ["Maru Coffee"])
        XCTAssertEqual(draft.newSuggestions.map(\.title), ["The Geffen Contemporary at MOCA"])
        XCTAssertTrue(draft.routeStops.map(\.title).contains("Maru Coffee"))
        XCTAssertTrue(draft.routeStops.map(\.title).contains("The Geffen Contemporary at MOCA"))
        XCTAssertTrue(draft.explanation.contains("Map Stamp"))
    }

    func testAnchorWithoutCoordinatesBlocksPlan() throws {
        let planController = SavePlanAroundController()
        let anchor = SaveSearchResult(
            id: "record-no-coordinates",
            objectType: .pendingCandidate,
            userState: .waitingReview,
            title: "Possible Cafe",
            subtitle: "Taipei",
            statusLabel: "Needs review",
            sourceURL: nil,
            sourcePlatform: nil,
            category: .cafe,
            cityOrArea: "Taipei",
            latitude: nil,
            longitude: nil,
            rating: nil,
            reviewCount: nil,
            confidence: nil,
            missingInfo: ["coordinates"],
            evidence: ["Caption clue"],
            recoveryQueries: [],
            createdAt: Date(),
            canRunRecovery: false,
            isRecommendationShell: false,
            primaryAction: .savePlace
        )

        let result = planController.planAround(
            anchor: anchor,
            savedResults: [],
            mapCandidates: [],
            request: SavePlanAroundRequest(anchorResultID: anchor.id, duration: .halfDay, intent: .balanced)
        )

        guard case .blocked(let state) = result else {
            return XCTFail("Expected blocked state")
        }
        XCTAssertEqual(state.title, "Location needed")
        XCTAssertTrue(state.missingInfo.contains("coordinates"))
    }

    func testSourceOnlyClueBlocksPlan() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let response = searchController.search(
            query: "instagram",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/example/",
                    title: "Instagram Reel",
                    evidence: ["Source URL: https://www.instagram.com/reel/example/"]
                )
            ]
        )
        let sourceOnly = try XCTUnwrap(response.fromYourSave.results.first)

        let result = planController.planAround(
            anchor: sourceOnly,
            savedResults: response.fromYourSave.results,
            mapCandidates: [],
            request: SavePlanAroundRequest(anchorResultID: sourceOnly.id, duration: .quickStop, intent: .balanced)
        )

        guard case .blocked(let state) = result else {
            return XCTFail("Expected blocked state")
        }
        XCTAssertEqual(state.title, "Exact place needed")
        XCTAssertTrue(state.allowedActions.contains(.runRecovery))
    }

    func testFoodHeavyClusterAddsAttractionAsBalancedGapFiller() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let anchor = place(name: "Ruen Pair", address: "5257 Hollywood Blvd, Los Angeles, CA", category: .food, latitude: 34.1017, longitude: -118.3055)
        let dessert = place(name: "Bhan Kanom Thai", address: "5271 Hollywood Blvd, Los Angeles, CA", category: .food, latitude: 34.1020, longitude: -118.3060)
        let response = searchController.search(query: "", places: [anchor, dessert], localRecords: [])
        let anchorResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Ruen Pair" })

        let result = planController.planAround(
            anchor: anchorResult,
            savedResults: response.fromYourSave.results,
            mapCandidates: [
                SaveMapCandidate(
                    title: "Griffith Observatory",
                    subtitle: "Los Angeles · Attraction",
                    latitude: 34.1184,
                    longitude: -118.3004,
                    category: .attraction,
                    evidence: ["Nearby map suggestion"]
                )
            ],
            request: SavePlanAroundRequest(anchorResultID: anchorResult.id, duration: .halfDay, intent: .balanced)
        )

        guard case .draft(let draft) = result else {
            return XCTFail("Expected routeable draft")
        }
        XCTAssertTrue(draft.routeStops.map(\.title).contains("Griffith Observatory"))
        XCTAssertEqual(draft.newSuggestions.first?.reason, "Adds a non-food unsaved candidate between Map Stamps.")
    }


    func testPlanAroundKeepsSavedFirstAndUnsavedSuggestionsSeparate() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let anchor = place(name: "Anchor Lunch", address: "Los Angeles, CA", category: .food, latitude: 34.0478, longitude: -118.2386)
        let savedCoffee = place(name: "Saved Coffee", address: "Los Angeles, CA", category: .cafe, latitude: 34.0480, longitude: -118.2390)
        let response = searchController.search(query: "", places: [anchor, savedCoffee], localRecords: [])
        let anchorResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Anchor Lunch" })

        let result = planController.planAround(
            anchor: anchorResult,
            savedResults: response.fromYourSave.results,
            mapCandidates: [
                SaveMapCandidate(
                    title: "Unsaved Museum",
                    subtitle: "Nearby · Museum",
                    latitude: 34.0506,
                    longitude: -118.2396,
                    category: .attraction,
                    evidence: ["Visible nearby on map"]
                )
            ],
            request: SavePlanAroundRequest(anchorResultID: anchorResult.id, duration: .halfDay, intent: .balanced)
        )

        guard case .draft(let draft) = result else {
            return XCTFail("Expected routeable draft")
        }

        XCTAssertEqual(draft.nearbySaved.map(\.title), ["Saved Coffee"])
        XCTAssertEqual(draft.newSuggestions.map(\.title), ["Unsaved Museum"])
        XCTAssertEqual(draft.routeStops.prefix(2).map(\.title), ["Anchor Lunch", "Saved Coffee"])
        XCTAssertEqual(draft.newSuggestions.first?.source, .unsavedMapCandidate)
    }

    private func place(
        name: String,
        address: String,
        category: PlaceCategory,
        latitude: Double,
        longitude: Double
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}
