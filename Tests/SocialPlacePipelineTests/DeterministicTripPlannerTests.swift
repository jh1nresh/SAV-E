import XCTest
@testable import SAVE

final class DeterministicTripPlannerTests: XCTestCase {
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
}
