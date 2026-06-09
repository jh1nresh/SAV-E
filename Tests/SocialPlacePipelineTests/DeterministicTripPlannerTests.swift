import XCTest
@testable import SAVE

final class DeterministicTripPlannerTests: XCTestCase {
    func testSpecificAnchorPlanningStillPullsNearbySavedMapStamps() throws {
        let anchor = makePlace(
            "一號地鍋雞",
            address: "台北市大安區忠孝東路四段",
            latitude: 25.0419,
            longitude: 121.5452,
            category: .food
        )
        let dessert = makePlace(
            "附近甜點店",
            address: "台北市大安區延吉街",
            latitude: 25.0423,
            longitude: 121.5460,
            category: .cafe
        )
        let farAway = makePlace(
            "高雄咖啡",
            address: "高雄市前鎮區",
            latitude: 22.6040,
            longitude: 120.3020,
            category: .cafe
        )

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(
            for: "幫我用一號地鍋雞附近的已存地點規劃半日行程",
            places: [farAway, dessert, anchor],
            outputLanguage: .traditionalChinese
        ))

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertTrue(response.placeIds.contains(anchor.id.uuidString))
        XCTAssertTrue(response.placeIds.contains(dessert.id.uuidString))
        XCTAssertFalse(response.placeIds.contains(farAway.id.uuidString), "Far-away place should be excluded by 25km threshold")
        XCTAssertEqual(response.placeIds.count, 2, "Should only include anchor and nearby dessert")
    }

    func testPlannerGroupsRequestedDaysAndOrdersStopsByDistance() throws {
        let places = [
            makePlace("Santa Monica Pier", address: "Santa Monica, Los Angeles, CA", latitude: 34.0100, longitude: -118.4960, category: .attraction),
            makePlace("Venice Dinner", address: "Venice, Los Angeles, CA", latitude: 33.9908, longitude: -118.4590, category: .food),
            makePlace("Downtown Coffee", address: "Los Angeles, CA", latitude: 34.0500, longitude: -118.2500, category: .cafe),
            makePlace("Arts District Bar", address: "Los Angeles, CA", latitude: 34.0417, longitude: -118.2350, category: .bar),
            makePlace("Silver Lake Shop", address: "Los Angeles, CA", latitude: 34.0860, longitude: -118.2700, category: .shopping)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "Plan a 2 day Los Angeles trip", places: places))

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertEqual(response.itineraryDays.count, 2)
        XCTAssertEqual(response.mapAction?.type, .showRoute)
        XCTAssertEqual(response.itineraryDays.first?.stops.first?.placeName, "Santa Monica Pier")
        XCTAssertEqual(response.itineraryDays.first?.stops.dropFirst().first?.placeName, "Venice Dinner")
    }

    func testPlannerFiltersDestinationWithoutDefaultCity() throws {
        let places = [
            makePlace("Disneyland Park", address: "Anaheim, CA", latitude: 33.8121, longitude: -117.9190, category: .attraction),
            makePlace("Anaheim Dinner", address: "Anaheim, CA", latitude: 33.8353, longitude: -117.9145, category: .food),
            makePlace("San Francisco Cafe", address: "San Francisco, CA", latitude: 37.7760, longitude: -122.4240, category: .cafe)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "Plan one day in Anaheim around Disneyland", places: places))
        let plannedNames = response.itineraryDays.flatMap(\.stops).map(\.placeName)

        XCTAssertTrue(plannedNames.contains("Disneyland Park"))
        XCTAssertTrue(plannedNames.contains("Anaheim Dinner"))
        XCTAssertFalse(plannedNames.contains("San Francisco Cafe"))
    }

    func testPlannerAssignsMealAndEveningSlots() throws {
        let places = [
            makePlace("Morning Coffee", address: "Tokyo", latitude: 35.6710, longitude: 139.7640, category: .cafe),
            makePlace("Lunch Ramen", address: "Tokyo", latitude: 35.6720, longitude: 139.7650, category: .food),
            makePlace("Night Bar", address: "Tokyo", latitude: 35.6730, longitude: 139.7660, category: .bar)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "Plan a Tokyo day", places: places))
        let stops = response.itineraryDays.flatMap(\.stops)

        XCTAssertEqual(stops.first(where: { $0.placeName == "Morning Coffee" })?.time, "9:00 AM")
        XCTAssertEqual(stops.first(where: { $0.placeName == "Lunch Ramen" })?.time, "12:30 PM")
        XCTAssertEqual(stops.first(where: { $0.placeName == "Night Bar" })?.time, "8:30 PM")
    }

    func testPlannerUnderstandsChineseTwoDayLAPrompt() throws {
        let places = [
            makePlace("Los Angeles Taco", address: "Los Angeles, CA", latitude: 34.0522, longitude: -118.2437, category: .food),
            makePlace("LA Coffee", address: "Los Angeles, CA", latitude: 34.0450, longitude: -118.2500, category: .cafe),
            makePlace("Irvine Dinner", address: "Irvine, CA", latitude: 33.6846, longitude: -117.8265, category: .food)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "幫我規劃 LA 兩天行程", places: places))
        let plannedNames = response.itineraryDays.flatMap(\.stops).map(\.placeName)

        XCTAssertEqual(response.itineraryDays.count, 2)
        XCTAssertTrue(plannedNames.contains("Los Angeles Taco"))
        XCTAssertTrue(plannedNames.contains("LA Coffee"))
        XCTAssertFalse(plannedNames.contains("Irvine Dinner"))
    }

    func testPlannerUsesSelectedLanguageForChineseTripFallback() throws {
        let places = [
            makePlace("Los Angeles Taco", address: "Los Angeles, CA", latitude: 34.0522, longitude: -118.2437, category: .food),
            makePlace("LA Coffee", address: "Los Angeles, CA", latitude: 34.0450, longitude: -118.2500, category: .cafe)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(
            for: "幫我規劃 LA 兩天行程",
            places: places,
            outputLanguage: .traditionalChinese
        ))

        XCTAssertEqual(response.title, "SAV-E 2 天行程")
        XCTAssertEqual(response.itineraryDays.first?.label, "第 1 天")
        XCTAssertTrue(response.aiMessage?.contains("地圖章") == true)
        XCTAssertFalse(response.aiMessage?.contains("Map Stamps") == true)
        let notes = response.itineraryDays.flatMap(\.stops).compactMap(\.note)
        XCTAssertFalse(notes.contains { $0.contains("Meal slot") || $0.contains("Good morning") })
    }

    func testPlannerDoesNotUseWrongCityWhenDestinationHasNoSavedMatches() {
        let places = [
            makePlace("Irvine Dinner", address: "Irvine, CA", latitude: 33.6846, longitude: -117.8265, category: .food),
            makePlace("Costa Mesa Coffee", address: "Costa Mesa, CA", latitude: 33.6411, longitude: -117.9187, category: .cafe)
        ]

        let response = DeterministicTripPlanner().plan(for: "Plan a Los Angeles trip", places: places)

        XCTAssertNil(response)
    }

    func testPlannerAsksForDaysOrStyleWhenTripRequestIsUnderspecified() throws {
        let places = [
            makePlace("Los Angeles Taco", address: "Los Angeles, CA", latitude: 34.0522, longitude: -118.2437, category: .food),
            makePlace("LA Coffee", address: "Los Angeles, CA", latitude: 34.0450, longitude: -118.2500, category: .cafe)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "幫我規劃 LA 行程", places: places))

        XCTAssertTrue(response.aiMessage?.contains("how many days") == true)
        XCTAssertTrue(response.aiMessage?.contains("food/drink") == true)
    }

    func testPlannerSkipsNonItineraryQueries() {
        let response = DeterministicTripPlanner().plan(
            for: "Show my food spots on the map",
            places: [makePlace("Cafe", address: "Irvine, CA", latitude: 33.6846, longitude: -117.8265, category: .cafe)]
        )

        XCTAssertNil(response)
    }

    func testPlannerDoesNotTreatTodayRecommendationAsTripPlanning() {
        let response = DeterministicTripPlanner().plan(
            for: "推薦我今天附近餐廳",
            places: [makePlace("Irvine Dinner", address: "Irvine, CA", latitude: 33.6846, longitude: -117.8265, category: .food)]
        )

        XCTAssertNil(response)
    }

    func testAIServiceFallsBackToDeterministicPlanWhenGeminiIsMissing() async throws {
        let places = [
            makePlace("Disneyland Park", address: "Anaheim, CA", latitude: 33.8121, longitude: -117.9190, category: .attraction),
            makePlace("Anaheim Dinner", address: "Anaheim, CA", latitude: 33.8353, longitude: -117.9145, category: .food)
        ]

        let response = try await SaveAIService(apiKey: "").query("Plan a one day Anaheim trip", places: places)

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertEqual(response.itineraryDays.count, 1)
        XCTAssertEqual(response.itineraryDays.first?.stops.map(\.placeName), ["Disneyland Park", "Anaheim Dinner"])
    }

    func testAIServiceTripFallbackUsesSelectedOutputLanguageWhenGeminiIsMissing() async throws {
        let places = [
            makePlace("Los Angeles Taco", address: "Los Angeles, CA", latitude: 34.0522, longitude: -118.2437, category: .food),
            makePlace("LA Coffee", address: "Los Angeles, CA", latitude: 34.0450, longitude: -118.2500, category: .cafe)
        ]

        let response = try await SaveAIService(apiKey: "").query(
            "幫我規劃 LA 兩天行程",
            places: places,
            outputLanguage: .traditionalChinese
        )

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertEqual(response.title, "SAV-E 2 天行程")
        XCTAssertEqual(response.itineraryDays.first?.label, "第 1 天")
        XCTAssertTrue(response.aiMessage?.contains("地圖章") == true)
        XCTAssertFalse(response.aiMessage?.contains("Map Stamps") == true)
    }


    func testPlannerHonorsExplicitTransitConstraintWithoutChangingSavedStops() throws {
        let places = [
            makePlace("Tokyo Coffee", address: "Tokyo", latitude: 35.6710, longitude: 139.7640, category: .cafe),
            makePlace("Tokyo Ramen", address: "Tokyo", latitude: 35.6720, longitude: 139.7650, category: .food),
            makePlace("Tokyo Museum", address: "Tokyo", latitude: 35.6730, longitude: 139.7660, category: .attraction)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "Plan a Tokyo day by transit", places: places))

        XCTAssertEqual(response.transportMode, .transit)
        XCTAssertEqual(response.itineraryDays.flatMap(\.stops).map(\.placeName), ["Tokyo Coffee", "Tokyo Ramen", "Tokyo Museum"])
        XCTAssertTrue(response.itineraryDays.flatMap(\.stops).contains { $0.note?.contains("public transit") == true })
    }

    func testPlannerRelaxedPaceCapsStopsPerDayButUsesOnlySavedPlaces() throws {
        let places = [
            makePlace("A Coffee", address: "Los Angeles, CA", latitude: 34.0000, longitude: -118.0000, category: .cafe),
            makePlace("B Lunch", address: "Los Angeles, CA", latitude: 34.0010, longitude: -118.0010, category: .food),
            makePlace("C Museum", address: "Los Angeles, CA", latitude: 34.0020, longitude: -118.0020, category: .attraction),
            makePlace("D Shop", address: "Los Angeles, CA", latitude: 34.0030, longitude: -118.0030, category: .shopping),
            makePlace("E Dinner", address: "Los Angeles, CA", latitude: 34.0040, longitude: -118.0040, category: .food)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "Plan a relaxed one day Los Angeles trip", places: places))
        let plannedStops = response.itineraryDays.flatMap(\.stops)

        XCTAssertLessThanOrEqual(plannedStops.count, 3)
        XCTAssertTrue(plannedStops.allSatisfy { stop in places.contains { $0.name == stop.placeName } })
    }

    func testPlannerAppliesRequestedStartTimeOnlyWhenExplicit() throws {
        let places = [
            makePlace("Morning Coffee", address: "Tokyo", latitude: 35.6710, longitude: 139.7640, category: .cafe),
            makePlace("Lunch Ramen", address: "Tokyo", latitude: 35.6720, longitude: 139.7650, category: .food)
        ]

        let response = try XCTUnwrap(DeterministicTripPlanner().plan(for: "Plan a Tokyo day starting at 10:30 am", places: places))
        let stops = response.itineraryDays.flatMap(\.stops)

        XCTAssertEqual(stops.first?.time, "10:30 AM")
        XCTAssertEqual(stops.first(where: { $0.placeName == "Lunch Ramen" })?.time, "12:30 PM")
    }

    func testItineraryPlanValidatorAllowsReorderDayGroupingAndPublicCandidatesOnlyFromRetrievalSet() throws {
        let museum = makePlace("Taipei Museum", address: "台北市中正區", latitude: 25.0400, longitude: 121.5200, category: .attraction)
        let lunch = makePlace("Taipei Lunch", address: "台北市大安區", latitude: 25.0410, longitude: 121.5450, category: .food)
        let cafe = makePlace("Taipei Cafe", address: "台北市信義區", latitude: 25.0330, longitude: 121.5650, category: .cafe)
        let publicPark = SaveMapCandidate(
            title: "大安森林公園",
            subtitle: "台北市大安區",
            latitude: 25.0260,
            longitude: 121.5350,
            category: .attraction
        )
        let fallback = itineraryResponse(days: [
            ItineraryDay(dayNumber: 1, label: "第 1 天", stops: [
                stop(place: lunch, time: "12:30 PM"),
                stop(place: cafe, time: "3:00 PM"),
                stop(place: museum, time: "10:00 AM")
            ])
        ])
        let llmResponse = itineraryResponse(days: [
            ItineraryDay(dayNumber: 1, label: "第 1 天", stops: [
                stop(place: museum, time: "9:30 AM"),
                publicStop("大安森林公園", time: "11:00 AM"),
                stop(place: lunch, time: "12:45 PM")
            ]),
            ItineraryDay(dayNumber: 2, label: "第 2 天", stops: [
                stop(place: cafe, time: "10:00 AM")
            ])
        ])

        let validated = try XCTUnwrap(ItineraryPlanValidator(
            savedPlaces: [museum, lunch, cafe],
            publicCandidates: [publicPark],
            fallback: fallback,
            requiredPlaceIDs: [lunch.id.uuidString]
        ).validated(llmResponse))

        XCTAssertEqual(validated.itineraryDays.count, 2)
        XCTAssertEqual(validated.itineraryDays.first?.stops.map(\.placeName), ["Taipei Museum", "大安森林公園", "Taipei Lunch"])
        XCTAssertEqual(validated.itineraryDays.first?.stops.first?.time, "9:30 AM")
        XCTAssertEqual(validated.placeIds, [museum.id.uuidString, lunch.id.uuidString, cafe.id.uuidString])
        XCTAssertEqual(validated.mapAction?.type, .showRoute)
        XCTAssertEqual(validated.mapAction?.placeIds, validated.placeIds)
    }

    func testItineraryPlanValidatorRejectsHallucinatedPublicStop() {
        let lunch = makePlace("Taipei Lunch", address: "台北市大安區", latitude: 25.0410, longitude: 121.5450, category: .food)
        let fallback = itineraryResponse(days: [
            ItineraryDay(dayNumber: 1, label: "第 1 天", stops: [stop(place: lunch, time: "12:30 PM")])
        ])
        let llmResponse = itineraryResponse(days: [
            ItineraryDay(dayNumber: 1, label: "第 1 天", stops: [
                stop(place: lunch, time: "12:30 PM"),
                publicStop("不存在的神秘景點", time: "2:00 PM")
            ])
        ])

        let validated = ItineraryPlanValidator(
            savedPlaces: [lunch],
            publicCandidates: [],
            fallback: fallback,
            requiredPlaceIDs: []
        ).validated(llmResponse)

        XCTAssertNil(validated)
    }

    func testAllFoodSavedTripPreparesPublicActivityCandidatesAndPromptPolicy() {
        let places = [
            makePlace("永樂牛肉湯", address: "台北市大同區", latitude: 25.0520, longitude: 121.5100, category: .food),
            makePlace("青山咖啡", address: "台北市萬華區", latitude: 25.0360, longitude: 121.5000, category: .cafe)
        ]

        XCTAssertTrue(ItineraryPublicDiscoveryPlanner.shouldPreparePublicActivityCandidates(
            query: "規劃 台北 3 日行程",
            savedPlaces: places
        ))
        XCTAssertTrue(ItineraryPublicDiscoveryPlanner.publicActivitySearchQueries(
            for: "規劃 台北 3 日行程",
            savedPlaces: places
        ).contains("台北 景點"))

        let policy = SaveAIService.itineraryCandidatePolicyInstruction(outputLanguage: .traditionalChinese)
        XCTAssertTrue(policy.contains("景點"))
        XCTAssertTrue(policy.contains("公開活動"))
        XCTAssertTrue(policy.contains("不可直接輸出全餐廳行程"))
    }

    private func makePlace(
        _ name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        category: PlaceCategory,
        status: PlaceStatus = .wantToGo
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
            status: status,
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

    private func itineraryResponse(days: [ItineraryDay]) -> SaveAIResponse {
        let placeIDs = days.flatMap(\.stops).compactMap(\.placeId)
        return SaveAIResponse(
            componentType: .tripItinerary,
            title: "Test itinerary",
            placeIds: placeIDs,
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: days,
            messageText: nil,
            mapAction: MapActionData(type: .showRoute, placeIds: placeIDs, lat: nil, lng: nil, span: nil),
            aiMessage: "Test"
        )
    }

    private func stop(place: Place, time: String) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeName: place.name,
            time: time,
            duration: 90,
            note: nil
        )
    }

    private func publicStop(_ name: String, time: String) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: nil,
            placeName: name,
            time: time,
            duration: 60,
            note: "公開探索候選"
        )
    }
}
