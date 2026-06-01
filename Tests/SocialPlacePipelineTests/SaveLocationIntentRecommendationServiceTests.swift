import CoreLocation
import XCTest
@testable import SAVE

final class SaveLocationIntentRecommendationServiceTests: XCTestCase {
    func testNearbyCafeExcludesWrongCategoryAndFarCafeFromPrimaryResults() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 34.0522, longitude: -118.2437)
        let nearbyCafe = place(
            name: "Cafe A",
            category: .cafe,
            latitude: 34.0580,
            longitude: -118.2440
        )
        let nearbyNonCafe = place(
            name: "Gym B",
            category: .attraction,
            latitude: 34.0530,
            longitude: -118.2438
        )
        let farCafe = place(
            name: "Cafe C",
            category: .cafe,
            latitude: 34.2000,
            longitude: -118.2437
        )

        let response = try XCTUnwrap(service.recommendationResponse(
            for: "附近咖啡廳",
            places: [nearbyCafe, nearbyNonCafe, farCafe],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.componentType, .placeList)
        XCTAssertEqual(response.placeIds, [nearbyCafe.id.uuidString])
        XCTAssertEqual(response.mapAction?.type, .filterPins)
        XCTAssertEqual(response.mapAction?.placeIds, [nearbyCafe.id.uuidString])

        let sectioned = try XCTUnwrap(service.recommendationSearchResponse(
            for: "附近咖啡廳",
            places: [nearbyCafe, nearbyNonCafe, farCafe],
            currentLocation: currentLocation
        ))
        XCTAssertEqual(sectioned.fromYourSave.title, "From your SAV-E nearby")
        XCTAssertEqual(sectioned.fromYourSave.results.map(\.title), ["Cafe A"])
        XCTAssertEqual(sectioned.additionalSections.first?.title, "Saved but not nearby")
        XCTAssertEqual(sectioned.additionalSections.first?.results.map(\.title), ["Cafe C"])
        XCTAssertFalse(sectioned.newRecommendations.showsNearbySearchAction)
    }

    func testNoNearbyCafeDoesNotRecommendWrongCategory() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 34.0522, longitude: -118.2437)
        let nearbyNonCafe = place(
            name: "Gym B",
            category: .attraction,
            latitude: 34.0530,
            longitude: -118.2438
        )
        let farCafe = place(
            name: "Cafe C",
            category: .cafe,
            latitude: 34.2000,
            longitude: -118.2437
        )

        let response = try XCTUnwrap(service.recommendationResponse(
            for: "附近咖啡廳",
            places: [nearbyNonCafe, farCafe],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.componentType, .message)
        XCTAssertEqual(response.placeIds, [])
        XCTAssertNil(response.mapAction)
        XCTAssertTrue(response.messageText?.contains("附近沒有咖啡廳") == true)
        XCTAssertTrue(response.messageText?.contains("did not recommend other categories") == true)

        let sectioned = try XCTUnwrap(service.recommendationSearchResponse(
            for: "附近咖啡廳",
            places: [nearbyNonCafe, farCafe],
            currentLocation: currentLocation
        ))
        XCTAssertTrue(sectioned.fromYourSave.results.isEmpty)
        XCTAssertTrue(sectioned.fromYourSave.showsNearbySearchAction)
        XCTAssertEqual(sectioned.additionalSections.first?.results.map(\.title), ["Cafe C"])
        XCTAssertTrue(sectioned.newRecommendations.showsNearbySearchAction)
    }

    func testNearbyCafeWithoutCurrentLocationReturnsLocationNeededMessage() throws {
        let service = SaveLocationIntentRecommendationService()

        let response = try XCTUnwrap(service.recommendationResponse(
            for: "coffee near me",
            places: [place(name: "Cafe A", category: .cafe)],
            currentLocation: nil
        ))

        XCTAssertEqual(response.componentType, .message)
        XCTAssertEqual(response.title, "Location needed")
        XCTAssertEqual(response.placeIds, [])
    }

    func testMilkTeaWithCurrentLocationRanksSpecificEvidenceBeforeGenericCafe() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 34.0522, longitude: -118.2437)
        let genericCafe = place(
            name: "Generic Coffee",
            category: .cafe,
            note: "Espresso and pastries"
        )
        let bobaCafe = place(
            name: "Half and Half Tea Express",
            category: .cafe,
            note: "Honey boba and milk tea",
            extractedDishes: ["milk tea", "boba"]
        )
        let dinner = place(name: "Dinner C", category: .food)

        let response = try XCTUnwrap(service.recommendationResponse(
            for: "我今天想喝奶茶",
            places: [genericCafe, bobaCafe, dinner],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.componentType, .placeList)
        XCTAssertEqual(response.placeIds, [bobaCafe.id.uuidString, genericCafe.id.uuidString])
        XCTAssertFalse(response.placeIds.contains(dinner.id.uuidString))
    }

    func testCoffeeCravingTodayRequiresCurrentLocation() throws {
        let service = SaveLocationIntentRecommendationService()

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "我今天想喝咖啡推薦一家咖啡給我",
            places: [],
            currentLocation: nil
        ))

        XCTAssertEqual(response.fromYourSave.title, "Location needed")
        XCTAssertTrue(response.fromYourSave.results.isEmpty)
        XCTAssertFalse(response.newRecommendations.showsNearbySearchAction)
        XCTAssertTrue(response.newRecommendations.results.isEmpty)
    }

    func testCoffeeCravingTodayFallsBackToExplicitUnsavedSearchWhenNoNearbySavedCafe() throws {
        let service = SaveLocationIntentRecommendationService()

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "我今天想喝咖啡推薦一家咖啡給我",
            places: [],
            currentLocation: CLLocation(latitude: 33.6846, longitude: -117.8265)
        ))

        XCTAssertEqual(response.fromYourSave.title, "From your SAV-E nearby")
        XCTAssertTrue(response.fromYourSave.results.isEmpty)
        XCTAssertTrue(response.fromYourSave.showsNearbySearchAction)
        XCTAssertTrue(response.newRecommendations.showsNearbySearchAction)
        XCTAssertTrue(response.shouldAutoSearchNearbyUnsavedCandidates)
    }

    func testCoffeeCravingTodayShowsSavedCafeFirstWhenNearby() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let nearbyCafe = place(
            name: "Bright Coffee Bar",
            category: .cafe,
            latitude: 33.6849,
            longitude: -117.8262
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "我今天想喝咖啡推薦一家咖啡給我",
            places: [nearbyCafe],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Bright Coffee Bar"])
        XCTAssertEqual(response.fromYourSave.results.first?.userState.displayName, "Saved")
        XCTAssertTrue(response.assistantMessage?.localizedCaseInsensitiveContains("saved") == true)
        XCTAssertTrue(response.assistantMessage?.contains("Bright Coffee Bar") == true)
        XCTAssertTrue(response.assistantMessage?.contains("Next:") == true)
        XCTAssertFalse(response.newRecommendations.showsNearbySearchAction)
        XCTAssertFalse(response.shouldAutoSearchNearbyUnsavedCandidates)
    }

    func testRestaurantRecommendationUsesCurrentLocationAndIncludesReviewCandidates() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let savedRestaurant = place(
            name: "HiroNori Craft Ramen",
            category: .food,
            latitude: 33.6849,
            longitude: -117.8262
        )
        let reviewRestaurant = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Review Ramen",
            address: "123 Main St",
            city: "Irvine",
            latitude: 33.6851,
            longitude: -117.8264,
            evidence: ["TikTok caption says restaurant near Irvine"],
            confidence: 0.78,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        let unsavedRestaurant = SaveMapCandidate(
            title: "Unsaved Ramen",
            subtitle: "Irvine, CA",
            latitude: 33.6848,
            longitude: -117.8266,
            category: .food,
            rating: 4.7,
            reviewCount: 220,
            distanceMeters: 320,
            evidence: ["Apple Maps result"]
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我餐廳",
            places: [savedRestaurant],
            reviewCandidates: [reviewRestaurant],
            mapCandidates: [unsavedRestaurant],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["HiroNori Craft Ramen"])
        XCTAssertEqual(response.additionalSections.first?.id, "review-candidates")
        XCTAssertEqual(response.additionalSections.first?.results.map(\.title), ["Review Ramen"])
        XCTAssertEqual(response.additionalSections.first?.results.first?.objectType, .pendingCandidate)
        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["Unsaved Ramen"])
        XCTAssertEqual(response.newRecommendations.results.first?.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(response.fromYourSave.results.first?.userState.displayName, "Saved")
        XCTAssertTrue(response.assistantMessage?.localizedCaseInsensitiveContains("saved") == true)
        XCTAssertTrue(response.assistantMessage?.contains("Review") == true)
        XCTAssertTrue(response.assistantMessage?.contains("unsaved") == true)
    }

    func testVisitedTasteSignalsCanBeatCloserGenericSavedRestaurant() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let lovedRamen = place(
            name: "Black Garlic Ramen Memory",
            category: .food,
            latitude: 33.6847,
            longitude: -117.8264,
            note: "Loved spicy ramen and black garlic broth",
            extractedDishes: ["spicy ramen", "black garlic"],
            status: .visited,
            rating: 4.8,
            priceRange: "$$"
        )
        let genericNearby = place(
            name: "Closest Generic Grill",
            category: .food,
            latitude: 33.68461,
            longitude: -117.82651,
            note: "burgers and fries",
            priceRange: "$"
        )
        let similarRamen = place(
            name: "Future Ramen Shop",
            category: .food,
            latitude: 33.6860,
            longitude: -117.8272,
            note: "spicy ramen, black garlic broth",
            extractedDishes: ["black garlic ramen"],
            priceRange: "$$"
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近餐廳",
            places: [genericNearby, similarRamen, lovedRamen],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title).prefix(2), ["Black Garlic Ramen Memory", "Future Ramen Shop"])
        XCTAssertTrue(response.fromYourSave.results[1].evidence.contains("Taste match from places you visited"))
    }

    func testSharedGeminiFallbacksUseGemini3ProOnly() {
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, ["gemini-3-pro"])
    }

    func testUnsupportedGymQueryDoesNotMapToFoodOrCafe() throws {
        let service = SaveLocationIntentRecommendationService()

        let response = try XCTUnwrap(service.recommendationResponse(
            for: "附近健身房",
            places: [
                place(name: "Nearby Cafe", category: .cafe),
                place(name: "Nearby Restaurant", category: .food)
            ],
            currentLocation: CLLocation(latitude: 34.0522, longitude: -118.2437)
        ))

        XCTAssertEqual(response.componentType, .message)
        XCTAssertEqual(response.title, "Unsupported category")
        XCTAssertEqual(response.placeIds, [])
        XCTAssertTrue(response.messageText?.contains("won't map this to food or cafe") == true)
    }

    func testDeterministicParserRecognizesNearbyCafeIntent() throws {
        let parser = SaveSearchIntentParser()
        let intent = try XCTUnwrap(parser.parse("附近咖啡廳"))

        XCTAssertEqual(intent.requiredCategories, [.cafe])
        XCTAssertTrue(intent.mustMatchCategory)
        XCTAssertTrue(intent.mustMatchLocation)
        XCTAssertEqual(intent.locationMode, .currentLocation(radiusMeters: 2_000))

        let restaurantSearch = try XCTUnwrap(parser.parse("我想找餐廳"))
        XCTAssertEqual(restaurantSearch.requiredCategories, [.food])
        XCTAssertTrue(restaurantSearch.mustMatchLocation)
        XCTAssertEqual(restaurantSearch.locationMode, .currentLocation(radiusMeters: 2_000))

        let restaurantRecommendation = try XCTUnwrap(parser.parse("推薦我餐廳"))
        XCTAssertEqual(restaurantRecommendation.requiredCategories, [.food])
        XCTAssertTrue(restaurantRecommendation.mustMatchLocation)
        XCTAssertEqual(restaurantRecommendation.locationMode, .currentLocation(radiusMeters: 2_000))
    }

    func testDeterministicParserHandlesMilkTeaWithoutLocationAndNamedArea() throws {
        let parser = SaveSearchIntentParser()
        let milkTea = try XCTUnwrap(parser.parse("我今天想喝奶茶"))
        XCTAssertEqual(milkTea.requiredCategories, [.cafe])
        XCTAssertEqual(milkTea.locationMode, .currentLocation(radiusMeters: 2_000))
        XCTAssertTrue(milkTea.mustMatchLocation)

        let laCoffee = try XCTUnwrap(parser.parse("coffee in LA"))
        XCTAssertEqual(laCoffee.requiredCategories, [.cafe])
        XCTAssertEqual(laCoffee.locationMode, .namedArea("Los Angeles"))
    }

    func testIntentJSONValidatorRejectsUnsafeModelOutput() throws {
        let validator = SaveSearchIntentJSONValidator()
        let valid = """
        {
          "kind": "categoryRecommendation",
          "requiredCategories": ["cafe"],
          "optionalCategories": [],
          "locationMode": {"type": "currentLocation", "radiusMeters": 2000},
          "sourceScope": "savedFirstAllowPublicFallback",
          "mustMatchCategory": true,
          "mustMatchLocation": true,
          "confidence": 0.94
        }
        """
        let intent = try validator.parseIntentJSON(valid, rawText: "附近咖啡廳")
        XCTAssertEqual(intent.requiredCategories, [.cafe])
        XCTAssertEqual(intent.locationMode, .currentLocation(radiusMeters: 2_000))

        let unknownCategory = valid.replacingOccurrences(of: #""cafe""#, with: #""gym""#)
        XCTAssertThrowsError(try validator.parseIntentJSON(unknownCategory, rawText: "附近健身房"))

        let unsafeLocationGate = valid.replacingOccurrences(of: #""mustMatchLocation": true"#, with: #""mustMatchLocation": false"#)
        XCTAssertThrowsError(try validator.parseIntentJSON(unsafeLocationGate, rawText: "附近咖啡廳"))

        let unsafeRadius = valid.replacingOccurrences(of: #""radiusMeters": 2000"#, with: #""radiusMeters": 100000"#)
        XCTAssertThrowsError(try validator.parseIntentJSON(unsafeRadius, rawText: "附近咖啡廳"))

        let invalidKind = valid.replacingOccurrences(of: #""categoryRecommendation""#, with: #""venueMagic""#)
        XCTAssertThrowsError(try validator.parseIntentJSON(invalidKind, rawText: "附近咖啡廳"))

        let invalidSourceScope = valid.replacingOccurrences(of: #""savedFirstAllowPublicFallback""#, with: #""anythingGoes""#)
        XCTAssertThrowsError(try validator.parseIntentJSON(invalidSourceScope, rawText: "附近咖啡廳"))
    }

    private func place(
        name: String,
        category: PlaceCategory,
        latitude: Double = 34.0522,
        longitude: Double = -118.2437,
        note: String? = nil,
        extractedDishes: [String]? = nil,
        status: PlaceStatus = .wantToGo,
        rating: Double? = nil,
        googleRating: Double? = nil,
        priceRange: String? = nil
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Los Angeles, CA",
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
            status: status,
            rating: rating,
            note: note,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: extractedDishes,
            priceRange: priceRange,
            recommender: nil,
            googleRating: googleRating,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}
