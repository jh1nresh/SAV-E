import CoreLocation
import XCTest
@testable import SAVE

/// Regression coverage for duplicate Map Stamps.
///
/// The same real-world venue can reach the map through different entry points
/// (a social link with a `sourceUrl`, a Google map pin with a `googlePlaceId`,
/// a confirmed review candidate). `Place.matches(_:)` is the gate that stops a
/// second copy from being saved. These cases pin the identity signals it must
/// honour so the same place is never stamped twice.
final class PlaceDeduplicationTests: XCTestCase {

    // Same venue: saved once from Instagram (sourceUrl, no place id), then found
    // again via Google map search (place id, no sourceUrl). Must be one place.
    @MainActor
    func testSamePlaceFromDifferentSourcesIsDeduplicated() {
        let fromMapSearch = makePlace(
            name: "Hidden Moon Cafe",
            address: "No. 12, Yongkang Street, Da'an District, Taipei",
            googlePlaceId: "ChIJhiddenmoon123",
            sourceUrl: nil
        )
        let withSamePlaceId = makePlace(
            name: "Hidden Moon Cafe",
            address: "12 Yongkang St, Taipei",
            googlePlaceId: "ChIJhiddenmoon123",
            sourceUrl: "https://instagram.com/p/abc123"
        )

        // googlePlaceId is the strongest identity: two saves sharing it are one place,
        // even when their sourceUrl/address strings differ.
        XCTAssertTrue(withSamePlaceId.matches(fromMapSearch),
                      "Same googlePlaceId must be treated as the same place")
        XCTAssertTrue(fromMapSearch.matches(withSamePlaceId),
                      "matches(_:) must be symmetric for googlePlaceId")
    }

    // No place id on either side, but the same name at the same coordinate.
    // Address strings differ slightly (abbreviations) — must still dedupe.
    @MainActor
    func testSameNameAndCoordinateIsDeduplicatedDespiteAddressDrift() {
        let saved = makePlace(
            name: "Onibus Coffee",
            address: "2-14-1 Kamiuma, Setagaya",
            latitude: 35.6465,
            longitude: 139.6745,
            googlePlaceId: nil,
            sourceUrl: nil
        )
        let resaved = makePlace(
            name: "Onibus Coffee",
            address: "2 Chome-14-1 Kamiuma, Setagaya City, Tokyo",
            latitude: 35.6465,
            longitude: 139.6745,
            googlePlaceId: nil,
            sourceUrl: nil
        )

        XCTAssertTrue(saved.matches(resaved),
                      "Same name at the same coordinate is the same place")
    }

    // Normalised source URL: a tracking query / trailing slash must not defeat dedup.
    @MainActor
    func testSameSourceURLWithTrackingParamsIsDeduplicated() {
        let saved = makePlace(
            name: "Blue Bottle",
            address: "Tokyo",
            googlePlaceId: nil,
            sourceUrl: "https://instagram.com/p/xyz/"
        )
        let resaved = makePlace(
            name: "Blue Bottle",
            address: "Tokyo",
            googlePlaceId: nil,
            sourceUrl: "https://instagram.com/p/xyz?utm_source=ig_web"
        )

        XCTAssertTrue(saved.matches(resaved),
                      "Same source post must dedupe regardless of tracking params")
    }

    // Guard against over-matching: genuinely different places stay distinct.
    @MainActor
    func testDistinctPlacesDoNotMatch() {
        let a = makePlace(
            name: "Hidden Moon Cafe",
            address: "Taipei",
            latitude: 25.0330,
            longitude: 121.5654,
            googlePlaceId: "ChIJaaa",
            sourceUrl: nil
        )
        let b = makePlace(
            name: "Ramen Nagi",
            address: "Tokyo",
            latitude: 35.6938,
            longitude: 139.7034,
            googlePlaceId: "ChIJbbb",
            sourceUrl: nil
        )

        XCTAssertFalse(a.matches(b),
                       "Different venues must never be treated as duplicates")
    }

    // MARK: - Helper

    @MainActor
    private func makePlace(
        name: String,
        address: String,
        latitude: Double = 25.0330,
        longitude: Double = 121.5654,
        googlePlaceId: String?,
        sourceUrl: String?
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: googlePlaceId,
            category: .cafe,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: sourceUrl,
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
