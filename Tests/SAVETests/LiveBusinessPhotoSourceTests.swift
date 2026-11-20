#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
@testable import SAVE

/// URL policy only: synthetic metadata is never loaded, and says nothing about photo availability.
@MainActor
final class LiveBusinessPhotoSourceTests: XCTestCase {
    private let businessURL = "https://images.example.invalid/redacted-business-front.jpg"
    private let otherBusinessURL = "https://images.example.invalid/redacted-business-interior.jpg"
    private let sourceURL = "https://images.example.invalid/redacted-post-screenshot.jpg"
    private let googleURL = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=synthetic-reference"

    func testMissingBusinessMetadataHasNoSelection() {
        let cases: [[String]?] = [nil, [], [" ", "\n\t"]]
        for photos in cases {
            XCTAssertEqual(LiveBusinessPhotoSource.resolve(fixture(photos: photos)), .missingMetadata)
        }
    }

    func testSourceImageAloneCannotBecomeBusinessPhoto() {
        let place = fixture(sourceImage: sourceURL)
        XCTAssertNil(place.businessPhotoUrls)
        XCTAssertNotNil(place.sourceImageUrl)
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(place), .missingMetadata)
    }

    func testSourceImageEchoIsExcludedEvenInBusinessArray() {
        let place = fixture(photos: ["  \(sourceURL)\n"], sourceImage: "\n\(sourceURL) ")
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(place), .unsupportedMetadata)
        // A URL's presence in both fields does not establish business-photo provenance.
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(fixture(photos: [businessURL], sourceImage: businessURL)),
                       .unsupportedMetadata)
    }

    func testGooglePlacesPhotosAreProviderRestricted() throws {
        let values = [
            googleURL,
            "https://places.googleapis.com/v1/places/synthetic/photos/synthetic/media",
            "https://lh3.googleusercontent.com/p/synthetic-place-photo"
        ]
        for value in values {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(GooglePlacesPhotoSourceMarkMetrics.mapSafePhotoURL(url),
                         "The real provider gate must recognize the fixture")
            XCTAssertEqual(LiveBusinessPhotoSource.resolve(fixture(photos: [value])), .providerRestricted)
        }
        // The restriction also applies when a provider photo was copied into sourceImageUrl.
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(fixture(photos: [googleURL], sourceImage: googleURL)),
                       .providerRestricted)
    }

    func testUnsupportedAndCredentialedURLsAreNotSelected() {
        let values = [
            "not a URL", "relative/photo.jpg", "https://", "http://",
            "file:///tmp/synthetic-photo.jpg", "ftp://images.example.invalid/photo.jpg",
            "data:image/png;base64,AA==",
            "https://synthetic-user:synthetic-password@images.example.invalid/photo.jpg",
            "https://synthetic-user@images.example.invalid/photo.jpg"
        ]
        for value in values {
            XCTAssertEqual(LiveBusinessPhotoSource.resolve(fixture(photos: [value])), .unsupportedMetadata,
                           "Unsupported synthetic metadata: \(value)")
        }
    }

    func testValidHTTPSBusinessMetadataIsSelectedWithoutChangingPlace() throws {
        let place = fixture(photos: [" \(businessURL)\n"], sourceImage: sourceURL)
        let before = place
        let expected = LiveBusinessPhotoSource.available(try XCTUnwrap(URL(string: businessURL)))
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(place), expected)
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(place), expected)
        XCTAssertEqual(place, before)
        XCTAssertEqual(place.businessPhotoUrls, [" \(businessURL)\n"])
        XCTAssertEqual(place.sourceImageUrl, sourceURL)
    }

    func testEligibleBusinessPhotoSurvivesEarlierRejectedCandidates() throws {
        let place = fixture(photos: [" ", "relative/photo.jpg", googleURL, sourceURL, businessURL],
                            sourceImage: sourceURL)
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(place),
                       .available(try XCTUnwrap(URL(string: businessURL))))
    }

    func testFirstEligibleBusinessPhotoKeepsSourceOrder() throws {
        let first = fixture(photos: [businessURL, otherBusinessURL])
        let reversed = fixture(photos: [otherBusinessURL, businessURL])
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(first),
                       .available(try XCTUnwrap(URL(string: businessURL))))
        XCTAssertEqual(LiveBusinessPhotoSource.resolve(reversed),
                       .available(try XCTUnwrap(URL(string: otherBusinessURL))))
    }

    private func fixture(photos: [String]? = nil, sourceImage: String? = nil) -> Place {
        Place(id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
              name: "Redacted Business", address: "Fixture Street 1", latitude: 25.03, longitude: 121.54,
              googlePlaceId: nil, category: .cafe, status: .wantToGo, rating: nil, note: nil,
              sourceUrl: nil, sourcePlatform: .other, coordinateSystem: .wgs84,
              sourceImageUrl: sourceImage, businessPhotoUrls: photos,
              extractedDishes: nil, priceRange: nil, recommender: nil, googleRating: nil,
              googlePriceLevel: nil, openingHours: nil,
              createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
#endif
