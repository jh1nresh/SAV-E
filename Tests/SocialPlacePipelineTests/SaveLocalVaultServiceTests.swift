import XCTest
@testable import SAVE

final class SaveLocalVaultServiceTests: XCTestCase {
    func testConfirmedPlaceSaveUpsertsMatchingVenueInsteadOfAppendingDuplicate() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("save-memory-records.json")
        let service = SaveLocalVaultService(overrideVaultURL: vaultURL)

        let first = makePlace(
            id: UUID(),
            name: "隱室無名滷肉飯 中山店",
            address: "103, Taiwan, Taipei City, Datong District",
            googlePlaceId: "ChIJ-sav-e-test"
        )
        let resaved = makePlace(
            id: UUID(),
            name: "隱室無名滷肉飯 中山店",
            address: "103, Taiwan, Taipei City, Datong District, Lane 33",
            googlePlaceId: "ChIJ-sav-e-test"
        )

        _ = try service.saveConfirmedPlace(first)
        _ = try service.saveConfirmedPlace(resaved)

        let places = try service.confirmedPlaces(limit: 10)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.address, resaved.address)
    }

    private func makePlace(
        id: UUID,
        name: String,
        address: String,
        googlePlaceId: String?
    ) -> Place {
        Place(
            id: id,
            name: name,
            address: address,
            latitude: 25.051,
            longitude: 121.519,
            googlePlaceId: googlePlaceId,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: "https://instagram.com/p/save-test",
            sourcePlatform: .instagram,
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
