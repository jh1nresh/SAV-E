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
        XCTAssertTrue(response.messageText?.contains("不會拿泛用咖啡廳或其他類別亂推") == true)

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

    func testTraditionalChineseCafeRecommendationKeepsFallbackAnswerLocalized() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let savedCoffee = place(
            name: "Bright Coffee Bar",
            category: .cafe,
            latitude: 33.6849,
            longitude: -117.8262,
            note: "Pour-over coffee and quiet tables",
            googleRating: 4.6
        )
        let publicCoffee = mapCandidate(name: "Public Coffee", category: .cafe)

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我咖啡廳",
            places: [savedCoffee],
            mapCandidates: [publicCoffee],
            currentLocation: currentLocation,
            outputLanguage: .traditionalChinese
        ))

        let message = try XCTUnwrap(response.assistantMessage)
        XCTAssertTrue(message.contains("我會先推 Bright Coffee Bar"))
        XCTAssertTrue(message.contains("公開探索會分開"))
        XCTAssertFalse(message.contains("Saved Map Stamp"))
        XCTAssertFalse(message.contains("Public discovery"))
        XCTAssertFalse(message.contains("rating"))
        XCTAssertEqual(response.fromYourSave.title, "來自 SAV-E 的附近記憶")
        XCTAssertEqual(response.newRecommendations.title, "附近公開探索")
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
        XCTAssertEqual(response.placeIds, [bobaCafe.id.uuidString])
        XCTAssertFalse(response.placeIds.contains(genericCafe.id.uuidString))
        XCTAssertFalse(response.placeIds.contains(dinner.id.uuidString))
    }

    func testNearbyHotPotRequiresSpecificEvidenceBeforeGenericFood() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let genericRestaurant = place(
            name: "Fonda Moderna",
            category: .food,
            latitude: 33.6847,
            longitude: -117.8266,
            note: "Mexican restaurant"
        )
        let hotPot = place(
            name: "Happy Lamb Hot Pot",
            category: .food,
            latitude: 33.6848,
            longitude: -117.8267,
            note: "Mongolian hot pot"
        )
        let unsavedWrongFood = SaveMapCandidate(
            title: "Aloha Hawaiian BBQ",
            subtitle: "Tustin, CA",
            latitude: 33.6849,
            longitude: -117.8268,
            category: .food,
            rating: 4.4,
            reviewCount: 300,
            distanceMeters: 300,
            evidence: ["Google Places result", "Search: hot pot"]
        )
        let unsavedHotPot = SaveMapCandidate(
            title: "All That Shabu",
            subtitle: "Irvine, CA",
            latitude: 33.6850,
            longitude: -117.8269,
            category: .food,
            rating: 4.7,
            reviewCount: 800,
            distanceMeters: 350,
            evidence: ["Google Places result", "Search: hot pot"]
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近火鍋",
            places: [genericRestaurant, hotPot],
            mapCandidates: [unsavedWrongFood, unsavedHotPot],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Happy Lamb Hot Pot"])
        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["All That Shabu"])
        XCTAssertFalse(response.fromYourSave.results.map(\.title).contains("Fonda Moderna"))
        XCTAssertFalse(response.newRecommendations.results.map(\.title).contains("Aloha Hawaiian BBQ"))
        XCTAssertEqual(response.resolvedAgentAnswer?.grounding.allowedResultIDs, ["place-\(hotPot.id.uuidString)"])
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

    func testCoffeeCravingTodayOffersExplicitUnsavedSearchWhenNoNearbySavedCafe() throws {
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
        XCTAssertTrue(response.newRecommendations.results.isEmpty)
    }

    func testSavedNearbyRecommendationDoesNotIncludePublicScoutUntilCandidatesArePrepared() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let savedCafe = place(
            name: "Saved Coffee",
            category: .cafe,
            latitude: 33.6847,
            longitude: -117.8266
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近咖啡",
            places: [savedCafe],
            mapCandidates: [],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Saved Coffee"])
        XCTAssertTrue(response.newRecommendations.results.isEmpty)
        XCTAssertFalse(response.newRecommendations.showsNearbySearchAction)
        XCTAssertEqual(response.groundedAnswerSections.map(\.id), ["from-your-save-nearby"])
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
        XCTAssertFalse(response.assistantMessage?.contains("Next:") == true)
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
        XCTAssertTrue(response.assistantMessage?.contains("Public discovery stays separate") == true)
        XCTAssertFalse(response.assistantMessage?.contains("unsaved nearby option") == true)
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

    func testGenericNearbyRecommendationUsesFrequentlySavedCategory() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let savedCafeA = place(
            name: "Saved Cafe A",
            category: .cafe,
            latitude: 33.6847,
            longitude: -117.8265
        )
        let savedCafeB = place(
            name: "Saved Cafe B",
            category: .cafe,
            latitude: 33.6848,
            longitude: -117.8265
        )
        let savedCafeC = place(
            name: "Saved Cafe C",
            category: .cafe,
            latitude: 33.6849,
            longitude: -117.8265
        )
        let closerRestaurant = place(
            name: "Closer Restaurant",
            category: .food,
            latitude: 33.68461,
            longitude: -117.8265
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近",
            places: [closerRestaurant, savedCafeA, savedCafeB, savedCafeC],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(Set(response.fromYourSave.results.map(\.title)), Set(["Saved Cafe A", "Saved Cafe B", "Saved Cafe C"]))
        XCTAssertFalse(response.fromYourSave.results.map(\.title).contains("Closer Restaurant"))
        XCTAssertTrue(response.fromYourSave.results.first?.evidence.contains("Category matches places you often save") == true)
    }

    func testLowRatedVisitedPlaceDoesNotSeedVisitedTasteEvidence() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let dislikedRamen = place(
            name: "Disliked Ramen Memory",
            category: .food,
            latitude: 33.6900,
            longitude: -117.8300,
            note: "spicy ramen and black garlic broth",
            extractedDishes: ["black garlic ramen"],
            status: .visited,
            rating: 3.0,
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
            places: [genericNearby, similarRamen, dislikedRamen],
            currentLocation: currentLocation
        ))

        let similarResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Future Ramen Shop" })
        XCTAssertFalse(similarResult.evidence.contains("Taste match from places you visited"))
        let dislikedResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Disliked Ramen Memory" })
        XCTAssertFalse(dislikedResult.evidence.contains("Visited place you rated well"))
    }

    func testHighRatingPriceAndTasteTagsRankAheadOfCloserGenericSavedPlace() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let lovedSushi = place(
            name: "Loved Sushi Memory",
            category: .food,
            latitude: 33.6848,
            longitude: -117.8266,
            note: "Omakase counter with uni hand roll",
            extractedDishes: ["uni hand roll", "omakase"],
            status: .visited,
            rating: 4.9,
            priceRange: "$$$"
        )
        let matchingSushi = place(
            name: "Future Sushi Counter",
            category: .food,
            latitude: 33.6860,
            longitude: -117.8270,
            note: "Uni hand roll and omakase set",
            extractedDishes: ["uni hand roll"],
            rating: 4.6,
            priceRange: "$$$"
        )
        let closerGeneric = place(
            name: "Closest Generic Grill",
            category: .food,
            latitude: 33.68461,
            longitude: -117.82651,
            note: "burgers and fries",
            priceRange: "$"
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近餐廳",
            places: [closerGeneric, matchingSushi, lovedSushi],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), [
            "Loved Sushi Memory",
            "Future Sushi Counter",
            "Closest Generic Grill"
        ])
        let matchingResult = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Future Sushi Counter" })
        XCTAssertTrue(matchingResult.evidence.contains("Taste match from places you visited"))
        XCTAssertTrue(matchingResult.evidence.contains("High rating 4.6"))
        XCTAssertTrue(matchingResult.evidence.contains("Taste tags match hand / omakase"))
        XCTAssertTrue(matchingResult.evidence.contains("Price matches places you liked ($$$)"))
    }

    func testTasteSignalsDoNotCrossCategoryOrLocationGates() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let lovedCafe = place(
            name: "Loved Cafe Memory",
            category: .cafe,
            latitude: 33.6847,
            longitude: -117.8265,
            note: "Omakase uni hand roll",
            extractedDishes: ["uni hand roll"],
            status: .visited,
            rating: 5.0,
            priceRange: "$$$"
        )
        let nearbyRestaurant = place(
            name: "Nearby Restaurant",
            category: .food,
            latitude: 33.6848,
            longitude: -117.8267,
            note: "simple lunch",
            priceRange: "$"
        )
        let farLovedRestaurant = place(
            name: "Far Loved Restaurant",
            category: .food,
            latitude: 33.7400,
            longitude: -117.8267,
            note: "Omakase uni hand roll",
            extractedDishes: ["uni hand roll"],
            status: .visited,
            rating: 4.9,
            priceRange: "$$$"
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近餐廳",
            places: [lovedCafe, farLovedRestaurant, nearbyRestaurant],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Nearby Restaurant"])
        XCTAssertFalse(response.fromYourSave.results.map(\.title).contains("Loved Cafe Memory"))
        XCTAssertEqual(response.additionalSections.first { $0.id == "saved-but-not-nearby" }?.results.map(\.title), ["Far Loved Restaurant"])
    }

    func testSharedGeminiFallbacksUseGemini35FlashOnly() {
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, SAVEProductionConfig.defaultGeminiModelFallbacks)
        XCTAssertEqual(SaveAIService.defaultModelFallbacks, ["gemini-3.5-flash"])
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
        XCTAssertEqual(response.title, "尚未支援的類別")
        XCTAssertEqual(response.placeIds, [])
        XCTAssertTrue(response.messageText?.contains("不會誤判成餐廳或咖啡廳") == true)
    }

    func testNearbyMilkTeaKeepsFarSavedPlacesOutOfPrimaryAnswer() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let nearbyBoba = place(
            name: "Nearby Boba",
            category: .cafe,
            latitude: 33.6848,
            longitude: -117.8267,
            note: "Brown sugar boba milk tea",
            extractedDishes: ["milk tea", "boba"]
        )
        let farBoba = place(
            name: "Tainan Milk Tea",
            category: .cafe,
            latitude: 22.9997,
            longitude: 120.2270,
            note: "Milk tea memory from Taiwan",
            extractedDishes: ["milk tea"]
        )
        let nearbyRamen = place(
            name: "Nearby Ramen",
            category: .food,
            latitude: 33.6847,
            longitude: -117.8266
        )
        let publicBoba = SaveMapCandidate(
            title: "Public Boba",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8269,
            category: .cafe,
            rating: 4.7,
            reviewCount: 240,
            distanceMeters: 180,
            evidence: ["Apple Maps result", "Search: milk tea"]
        )
        let genericCafe = SaveMapCandidate(
            title: "The Lost Bean",
            subtitle: "1705 Flight Way Suite #1, Tustin, CA",
            latitude: 33.6849,
            longitude: -117.8268,
            category: .cafe,
            rating: 4.6,
            reviewCount: 800,
            distanceMeters: 220,
            evidence: ["Apple Maps result", "Search: milk tea"]
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我一家附近奶茶",
            places: [farBoba, nearbyRamen, nearbyBoba],
            mapCandidates: [genericCafe, publicBoba],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.id, "from-your-save-nearby")
        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Nearby Boba"])
        XCTAssertFalse(response.fromYourSave.results.map(\.title).contains("Tainan Milk Tea"))
        XCTAssertEqual(response.additionalSections.first { $0.id == "saved-but-not-nearby" }?.results.map(\.title), ["Tainan Milk Tea"])
        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["Public Boba"])
        XCTAssertFalse(response.newRecommendations.results.map(\.title).contains("The Lost Bean"))
        XCTAssertTrue(response.assistantMessage?.contains("Nearby Boba") == true)
    }

    func testNearbyMilkTeaKeepsFarReviewCandidatesOutOfNearbyContext() throws {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let nearbyBoba = place(
            name: "Nearby Boba",
            category: .cafe,
            latitude: 33.6848,
            longitude: -117.8267,
            note: "Brown sugar boba milk tea",
            extractedDishes: ["milk tea", "boba"]
        )
        let nearbyReviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Irvine Review Boba",
            address: "12 Main St",
            city: "Irvine",
            latitude: 33.6849,
            longitude: -117.8268,
            evidence: ["Caption says milk tea in Irvine"],
            confidence: 0.82,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        let farReviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Taipei Review Boba",
            address: "Da'an District",
            city: "Taipei",
            latitude: 25.0330,
            longitude: 121.5654,
            evidence: ["Caption says milk tea in Taipei"],
            confidence: 0.86,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        let unlocatedReviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Unlocated Review Boba",
            address: "",
            city: "Taiwan",
            latitude: nil,
            longitude: nil,
            evidence: ["Caption says milk tea"],
            confidence: 0.54,
            missingInfo: ["coordinates"],
            status: "pending",
            createdAt: Date()
        )

        let response = try XCTUnwrap(service.recommendationSearchResponse(
            for: "推薦我附近的奶茶店",
            places: [nearbyBoba],
            reviewCandidates: [farReviewCandidate, unlocatedReviewCandidate, nearbyReviewCandidate],
            currentLocation: currentLocation
        ))

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Nearby Boba"])
        XCTAssertEqual(response.additionalSections.first { $0.id == "review-candidates" }?.results.map(\.title), ["Irvine Review Boba"])
        XCTAssertFalse(response.additionalSections.flatMap(\.results).map(\.title).contains("Taipei Review Boba"))
        XCTAssertFalse(response.additionalSections.flatMap(\.results).map(\.title).contains("Unlocated Review Boba"))
        XCTAssertTrue(response.assistantMessage?.contains("Nearby Boba") == true)
        XCTAssertFalse(response.assistantMessage?.contains("Taipei Review Boba") == true)
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

    func testAskSaveRecommendationQualityRegressionFixtures() throws {
        struct Fixture {
            let name: String
            let query: String
            let places: [Place]
            let reviewCandidates: [PlaceReviewCandidate]
            let mapCandidates: [SaveMapCandidate]
            let expectedSavedTitles: [String]
            let expectedReviewTitles: [String]
            let expectedPublicTitles: [String]
            let expectedFarSavedTitles: [String]
            let shouldShowPublicFallback: Bool
        }

        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let nearbyBoba = place(
            name: "Omomo Tea Shoppe",
            category: .cafe,
            latitude: 33.6848,
            longitude: -117.8267,
            note: "Brown sugar boba and milk tea",
            extractedDishes: ["boba", "milk tea"]
        )
        let nearbyCoffee = place(
            name: "Bright Coffee Bar",
            category: .cafe,
            latitude: 33.6849,
            longitude: -117.8262,
            note: "Pour-over coffee and quiet tables",
            extractedDishes: ["latte", "pour over"]
        )
        let nearbyRestaurant = place(
            name: "HiroNori Craft Ramen",
            category: .food,
            latitude: 33.6849,
            longitude: -117.8262,
            note: "Tonkotsu ramen and crispy chicken"
        )
        let farSavedBoba = place(
            name: "Tainan Milk Tea",
            category: .cafe,
            latitude: 22.9997,
            longitude: 120.2270,
            note: "Milk tea memory from Taiwan",
            extractedDishes: ["milk tea"]
        )
        let farSavedCoffee = place(
            name: "LA Coffee Archive",
            category: .cafe,
            latitude: 34.0522,
            longitude: -118.2437,
            note: "Saved coffee memory outside today's radius"
        )
        let reviewOnlyRestaurant = reviewCandidate(name: "Review Ramen", categoryEvidence: "TikTok caption says restaurant near Irvine")
        let reviewOnlyCoffee = reviewCandidate(name: "Review Coffee", categoryEvidence: "Instagram caption mentions coffee near Irvine")
        let publicCoffee = mapCandidate(name: "Public Coffee", category: .cafe)
        let publicRestaurant = mapCandidate(name: "Public Ramen", category: .food)

        let fixtures: [Fixture] = [
            Fixture(
                name: "boba keeps exact nearby saved first and far saved separate",
                query: "推薦我附近奶茶",
                places: [farSavedBoba, nearbyRestaurant, nearbyBoba],
                reviewCandidates: [],
                mapCandidates: [publicCoffee],
                expectedSavedTitles: ["Omomo Tea Shoppe"],
                expectedReviewTitles: [],
                expectedPublicTitles: [],
                expectedFarSavedTitles: ["Tainan Milk Tea"],
                shouldShowPublicFallback: false
            ),
            Fixture(
                name: "coffee returns nearby saved coffee without restaurant bleed",
                query: "我今天想喝咖啡推薦一家咖啡給我",
                places: [nearbyRestaurant, nearbyCoffee],
                reviewCandidates: [],
                mapCandidates: [publicCoffee],
                expectedSavedTitles: ["Bright Coffee Bar"],
                expectedReviewTitles: [],
                expectedPublicTitles: ["Public Coffee"],
                expectedFarSavedTitles: [],
                shouldShowPublicFallback: false
            ),
            Fixture(
                name: "restaurant uses food category and excludes cafes",
                query: "推薦我附近餐廳",
                places: [nearbyCoffee, nearbyRestaurant],
                reviewCandidates: [],
                mapCandidates: [publicRestaurant],
                expectedSavedTitles: ["HiroNori Craft Ramen"],
                expectedReviewTitles: [],
                expectedPublicTitles: ["Public Ramen"],
                expectedFarSavedTitles: [],
                shouldShowPublicFallback: false
            ),
            Fixture(
                name: "nearby generic falls back to dominant saved cafe category",
                query: "推薦我附近",
                places: [nearbyRestaurant, nearbyCoffee, nearbyBoba, farSavedCoffee],
                reviewCandidates: [],
                mapCandidates: [],
                expectedSavedTitles: ["Omomo Tea Shoppe", "Bright Coffee Bar"],
                expectedReviewTitles: [],
                expectedPublicTitles: [],
                expectedFarSavedTitles: ["LA Coffee Archive"],
                shouldShowPublicFallback: false
            ),
            Fixture(
                name: "far saved is context only when no saved place is nearby",
                query: "推薦我附近咖啡",
                places: [farSavedCoffee],
                reviewCandidates: [],
                mapCandidates: [publicCoffee],
                expectedSavedTitles: [],
                expectedReviewTitles: [],
                expectedPublicTitles: ["Public Coffee"],
                expectedFarSavedTitles: ["LA Coffee Archive"],
                shouldShowPublicFallback: false
            ),
            Fixture(
                name: "review-only candidate is usable but not promoted to saved",
                query: "推薦我附近餐廳",
                places: [],
                reviewCandidates: [reviewOnlyRestaurant],
                mapCandidates: [],
                expectedSavedTitles: [],
                expectedReviewTitles: ["Review Ramen"],
                expectedPublicTitles: [],
                expectedFarSavedTitles: [],
                shouldShowPublicFallback: true
            ),
            Fixture(
                name: "public fallback stays in unsaved section",
                query: "推薦我附近咖啡",
                places: [],
                reviewCandidates: [reviewOnlyCoffee],
                mapCandidates: [publicCoffee],
                expectedSavedTitles: [],
                expectedReviewTitles: ["Review Coffee"],
                expectedPublicTitles: ["Public Coffee"],
                expectedFarSavedTitles: [],
                shouldShowPublicFallback: false
            )
        ]

        for fixture in fixtures {
            let response = try XCTUnwrap(
                service.recommendationSearchResponse(
                    for: fixture.query,
                    places: fixture.places,
                    reviewCandidates: fixture.reviewCandidates,
                    mapCandidates: fixture.mapCandidates,
                    currentLocation: currentLocation
                ),
                fixture.name
            )

            XCTAssertEqual(response.fromYourSave.results.map(\.title), fixture.expectedSavedTitles, fixture.name)
            XCTAssertEqual(
                response.additionalSections.first { $0.id == "review-candidates" }?.results.map(\.title) ?? [],
                fixture.expectedReviewTitles,
                fixture.name
            )
            XCTAssertEqual(response.newRecommendations.results.map(\.title), fixture.expectedPublicTitles, fixture.name)
            XCTAssertEqual(
                response.additionalSections.first { $0.id == "saved-but-not-nearby" }?.results.map(\.title) ?? [],
                fixture.expectedFarSavedTitles,
                fixture.name
            )
            XCTAssertEqual(response.newRecommendations.showsNearbySearchAction, fixture.shouldShowPublicFallback, fixture.name)
            XCTAssertFalse(response.fromYourSave.results.contains { result in
                fixture.expectedFarSavedTitles.contains(result.title)
            }, fixture.name)
        }
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

    private func reviewCandidate(name: String, categoryEvidence: String) -> PlaceReviewCandidate {
        PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: name,
            address: "123 Main St",
            city: "Irvine",
            latitude: 33.6851,
            longitude: -117.8264,
            evidence: [categoryEvidence],
            confidence: 0.78,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
    }

    private func mapCandidate(name: String, category: PlaceCategory) -> SaveMapCandidate {
        SaveMapCandidate(
            title: name,
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: category,
            rating: 4.7,
            reviewCount: 240,
            distanceMeters: 180,
            evidence: ["Apple Maps result"]
        )
    }
}
