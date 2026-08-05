import XCTest
@testable import SAVE

final class SavedPlaceTripRecommenderTests: XCTestCase {
    @MainActor
    func testRecommendsAreasWithEnoughConfirmedStamps() {
        let places = [
            place("Genghis Cohen", area: "Los Angeles"),
            place("Berenjak", area: "Los Angeles"),
            place("Maru Coffee", area: "Los Angeles"),
            place("一號地鍋雞", area: "台北市"),
        ]

        let recommendations = SavedPlaceTripRecommender().recommendations(from: places)

        // Taipei has 1 stamp — one lunch is not a day worth planning.
        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations.first?.area, "Los Angeles")
        XCTAssertEqual(recommendations.first?.stampCount, 3)
    }

    @MainActor
    func testRecommendationQueryIsOneThePlannerCanParse() {
        let places = (0..<3).map { place("Spot \($0)", area: "Los Angeles") }
        let recommendation = try? XCTUnwrap(
            SavedPlaceTripRecommender().recommendations(from: places).first
        )

        let query = try? XCTUnwrap(recommendation?.planningQuery)
        XCTAssertEqual(query, "Plan a day in Los Angeles")

        // The whole point: tapping the card must actually produce a plan.
        let planner = DeterministicTripPlanner()
        XCTAssertTrue(planner.isItineraryRequest(query ?? ""))
        XCTAssertNotNil(planner.plan(for: query ?? "", places: places))
    }

    @MainActor
    func testSuggestsMoreDaysForDenserAreasButCapsThem() {
        let modest = (0..<4).map { place("Spot \($0)", area: "Osaka") }
        XCTAssertEqual(SavedPlaceTripRecommender().recommendations(from: modest).first?.suggestedDays, 1)

        let dense = (0..<40).map { place("Spot \($0)", area: "Osaka") }
        XCTAssertEqual(
            SavedPlaceTripRecommender().recommendations(from: dense).first?.suggestedDays,
            SavedPlaceTripRecommender.maximumSuggestedDays
        )
    }

    @MainActor
    func testDoesNotRecommendAnAreaThatAlreadyHasATrip() {
        let places = (0..<5).map { place("Spot \($0)", area: "Los Angeles") }
        let existing = trip(city: "los angeles")

        XCTAssertTrue(
            SavedPlaceTripRecommender()
                .recommendations(from: places, excludingAreasFrom: [existing])
                .isEmpty
        )
    }

    @MainActor
    func testSkipsPlacesWithoutRealCoordinates() {
        let places = [
            place("Genghis Cohen", area: "Los Angeles"),
            place("Berenjak", area: "Los Angeles"),
            place("No coordinates", area: "Los Angeles", latitude: 0, longitude: 0),
        ]

        XCTAssertTrue(SavedPlaceTripRecommender().recommendations(from: places).isEmpty)
    }

    @MainActor
    func testRanksDenserAreasFirstAndCapsTheList() {
        var places: [Place] = []
        for (area, count) in [("Los Angeles", 9), ("Tokyo", 6), ("Osaka", 4), ("Seoul", 3)] {
            places += (0..<count).map { place("\(area) \($0)", area: area) }
        }

        let recommendations = SavedPlaceTripRecommender().recommendations(from: places)

        XCTAssertEqual(recommendations.count, SavedPlaceTripRecommender.maximumRecommendations)
        XCTAssertEqual(recommendations.map(\.area), ["Los Angeles", "Tokyo", "Osaka"])
    }

    @MainActor
    func testEmptyVaultRecommendsNothing() {
        XCTAssertTrue(SavedPlaceTripRecommender().recommendations(from: []).isEmpty)
    }

    // MARK: - Helpers

    @MainActor
    private func place(
        _ name: String,
        area: String,
        latitude: Double = 34.0793,
        longitude: Double = -118.3613
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "123 Main St, \(area), CA 90036",
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: .food,
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

    @MainActor
    private func trip(city: String) -> Trip {
        Trip(
            id: UUID(),
            name: "Existing",
            city: city,
            startDate: nil,
            endDate: nil,
            places: [],
            isOptimized: false,
            createdAt: Date()
        )
    }

    // MARK: - Area labels people would actually say

    @MainActor
    func testCJKAddressesClusterByCityNotDistrict() {
        // shareAreaLabel returns "110台灣臺北市信義區西村里" for these, which
        // both reads as garbage and never clusters — two restaurants on the
        // same street land in different village suffixes.
        let places = [
            placeWithAddress("樂葵法式鐵板燒", "110台灣臺北市信義區西村里松高路16號"),
            placeWithAddress("鼎泰豐", "106台灣臺北市大安區信義路二段194號"),
            placeWithAddress("一號地鍋雞", "106台灣臺北市大安區忠孝東路四段"),
        ]

        let recommendations = SavedPlaceTripRecommender().recommendations(from: places)

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations.first?.area, "臺北市")
        XCTAssertEqual(recommendations.first?.stampCount, 3)
    }

    @MainActor
    func testAreaLabelStripsLeadingPostalCodes() {
        let place = placeWithAddress("Somewhere", "1 Main St, 90036 Los Angeles, USA")
        XCTAssertEqual(SavedPlaceTripRecommender.areaLabel(for: place), "Los Angeles")
    }

    @MainActor
    private func placeWithAddress(_ name: String, _ address: String) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: 25.033,
            longitude: 121.5654,
            googlePlaceId: nil,
            category: .food,
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
