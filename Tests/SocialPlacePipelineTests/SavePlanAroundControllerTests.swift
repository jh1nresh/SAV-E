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
        XCTAssertEqual(draft.routeStops.first?.sourceLabel, "From your SAV-E")
        XCTAssertEqual(draft.newSuggestions.first?.sourceLabel, "New recommendation")
        XCTAssertEqual(draft.retrievalReceipt.candidateCount, 1)
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
        XCTAssertEqual(draft.newSuggestions.first?.sourceLabel, "New recommendation")
        XCTAssertTrue(draft.newSuggestions.first?.reason.contains("Public filler") == true)
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

    func testPlanAroundRejectsWrongCityPublicFillers() throws {
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
                    title: "Tokyo Coffee",
                    subtitle: "Tokyo · Cafe",
                    latitude: 35.6764,
                    longitude: 139.6500,
                    category: .cafe,
                    evidence: ["Public map candidate"]
                )
            ],
            request: SavePlanAroundRequest(
                anchorResultID: anchorResult.id,
                duration: .halfDay,
                intent: .balanced,
                planIntent: SavePlanIntentContract(cityOrRegion: "Los Angeles")
            )
        )

        guard case .draft(let draft) = result else {
            return XCTFail("Expected saved-only draft")
        }

        XCTAssertFalse(draft.routeStops.map(\.title).contains("Tokyo Coffee"))
        XCTAssertTrue(draft.retrievalReceipt.skippedReasons.contains { $0.contains("outside requested city") })
    }

    func testPlanAroundBlocksWhenOnlyAnchorAndNoFillers() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let anchor = place(name: "Only Anchor", address: "Los Angeles, CA", category: .food, latitude: 34.0478, longitude: -118.2386)
        let response = searchController.search(query: "", places: [anchor], localRecords: [])
        let anchorResult = try XCTUnwrap(response.fromYourSave.results.first)

        let result = planController.planAround(
            anchor: anchorResult,
            savedResults: response.fromYourSave.results,
            mapCandidates: [],
            request: SavePlanAroundRequest(anchorResultID: anchorResult.id, duration: .halfDay, intent: .balanced)
        )

        guard case .blocked(let state) = result else {
            return XCTFail("Expected honest weak-saved-set block")
        }

        XCTAssertEqual(state.title, "Not enough saved places")
        XCTAssertTrue(state.allowedActions.contains(.showNearby))
    }

    func testPlanAroundKeepsSavedOnlyDraftWhenPublicFetchFails() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let anchor = place(name: "Anchor Lunch", address: "Los Angeles, CA", category: .food, latitude: 34.0478, longitude: -118.2386)
        let savedCoffee = place(name: "Saved Coffee", address: "Los Angeles, CA", category: .cafe, latitude: 34.0480, longitude: -118.2390)
        let response = searchController.search(query: "", places: [anchor, savedCoffee], localRecords: [])
        let anchorResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Anchor Lunch" })

        let result = planController.planAround(
            anchor: anchorResult,
            savedResults: response.fromYourSave.results,
            mapCandidates: [],
            request: SavePlanAroundRequest(anchorResultID: anchorResult.id, duration: .halfDay, intent: .balanced)
        )

        guard case .draft(let draft) = result else {
            return XCTFail("Expected saved-only draft")
        }

        XCTAssertEqual(draft.routeStops.map(\.title), ["Anchor Lunch", "Saved Coffee"])
        XCTAssertFalse(draft.unfilledGaps.isEmpty)
        XCTAssertTrue(draft.retrievalReceipt.skippedReasons.contains { $0.contains("No public recommendation candidates") })
    }

    func testPlanAroundAllowsOnlyHighConfidenceReviewCandidateWithLabel() throws {
        let searchController = SaveSearchController()
        let planController = SavePlanAroundController()
        let anchor = place(name: "Anchor Lunch", address: "Los Angeles, CA", category: .food, latitude: 34.0478, longitude: -118.2386)
        let response = searchController.search(query: "", places: [anchor], localRecords: [])
        let anchorResult = try XCTUnwrap(response.fromYourSave.results.first)
        let reviewCandidate = SaveSearchResult(
            id: "review-candidate-1",
            objectType: .pendingCandidate,
            userState: .waitingReview,
            title: "Likely Gallery",
            subtitle: "Los Angeles · Gallery",
            statusLabel: "Needs review",
            sourceURL: nil,
            sourcePlatform: .googleMaps,
            category: .attraction,
            cityOrArea: "Los Angeles",
            latitude: 34.0506,
            longitude: -118.2396,
            rating: nil,
            reviewCount: nil,
            confidence: 0.72,
            missingInfo: [],
            evidence: ["Coordinates and category corroborated"],
            recoveryQueries: [],
            createdAt: Date(),
            canRunRecovery: false,
            isRecommendationShell: false,
            primaryAction: .confirmMapStamp
        )

        let result = planController.planAround(
            anchor: anchorResult,
            savedResults: response.fromYourSave.results + [reviewCandidate],
            mapCandidates: [],
            request: SavePlanAroundRequest(anchorResultID: anchorResult.id, duration: .halfDay, intent: .balanced)
        )

        guard case .draft(let draft) = result else {
            return XCTFail("Expected draft with high-confidence review candidate")
        }

        XCTAssertEqual(draft.nearbySaved.first?.title, "Likely Gallery")
        XCTAssertEqual(draft.nearbySaved.first?.sourceLabel, "Review candidate")
        XCTAssertTrue(draft.nearbySaved.first?.evidence.contains("Coordinates and category corroborated") == true)
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
