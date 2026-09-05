import XCTest
import CoreLocation
@testable import SAVE

@MainActor
final class SaveMapIntentFilterTests: XCTestCase {
    func testCategoryAndVisitIntentCombineWithOrInsideEachGroup() {
        let cafeWanted = place(name: "Wanted Cafe", category: .cafe, status: .wantToGo, latitude: 25.033, longitude: 121.565)
        let cafeVisited = place(name: "Visited Cafe", category: .cafe, status: .visited, latitude: 25.034, longitude: 121.566)
        let foodWanted = place(name: "Wanted Food", category: .food, status: .wantToGo, latitude: 25.035, longitude: 121.567)

        let filtered = SaveMapIntentFilter.places(
            [cafeWanted, cafeVisited, foodWanted],
            categories: [.cafe],
            intents: [.wantToGo],
            nearbyAnchor: nil
        )

        XCTAssertEqual(filtered.map(\.name), ["Wanted Cafe"])
    }

    func testWantToGoAndVisitedTogetherKeepBothStatuses() {
        let wanted = place(name: "Wanted", status: .wantToGo)
        let visited = place(name: "Visited", status: .visited)

        let filtered = SaveMapIntentFilter.places(
            [wanted, visited],
            categories: [],
            intents: [.wantToGo, .visited],
            nearbyAnchor: nil
        )

        XCTAssertEqual(Set(filtered.map(\.name)), ["Wanted", "Visited"])
    }

    func testNearbyRequiresAnAnchorAndStaysInsideTwoKilometers() {
        let anchor = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        let near = place(name: "Near", latitude: 25.0340, longitude: 121.5660)
        let far = place(name: "Far", latitude: 25.0800, longitude: 121.5600)

        XCTAssertTrue(
            SaveMapIntentFilter.places(
                [near, far],
                categories: [],
                intents: [.nearby],
                nearbyAnchor: nil
            ).isEmpty
        )

        let filtered = SaveMapIntentFilter.places(
            [near, far],
            categories: [],
            intents: [.nearby],
            nearbyAnchor: anchor
        )
        XCTAssertEqual(filtered.map(\.name), ["Near"])
    }

    func testNearbyDoesNotInventUnsavedCandidates() {
        XCTAssertEqual(SaveMapDrawerIntent.allCases.map(\.rawValue), ["wantToGo", "visited", "nearby"])
        XCTAssertEqual(SaveMapIntentFilter.nearbyRadiusMeters, 2_000)
    }

    @MainActor
    func testMapViewModelFilteredPlacesHonorVisitIntent() {
        let wanted = place(name: "Wanted Cafe", status: .wantToGo)
        let visited = place(name: "Visited Cafe", status: .visited)
        let map = MapViewModel(usesRemotePersistence: false)
        map.places = [wanted, visited]
        map.selectedIntentFilters = [.visited]

        XCTAssertEqual(map.filteredPlaces.map(\.name), ["Visited Cafe"])
    }

    private func place(
        name: String,
        category: PlaceCategory = .cafe,
        status: PlaceStatus = .wantToGo,
        latitude: Double = 25.033,
        longitude: Double = 121.565
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Taipei",
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
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
