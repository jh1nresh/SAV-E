import XCTest
@testable import SAVE

final class SavePlaceShareButtonTests: XCTestCase {
    @MainActor
    func testFirstTapAlwaysSharesSavvyPlaceRegardlessOfSource() throws {
        for source in [nil, "https://www.instagram.com/p/venue/", "https://maps.apple.com/?q=Other&ll=1,2",
                       "https://www.google.com/maps/place/Kato", "https://example.com/" + String(repeating: "a", count: 600)] as [String?] {
            let payload = Self.payload(sourceURL: source.flatMap(URL.init(string:)))
            let content = SavePlaceShareContent(subject: "Savvy Map Stamp: Kato", fallbackURL: nil,
                fallbackText: "Savvy Map Stamp\nKato\n777 S Alameda St", payload: payload,
                sourcePlaceId: nil, optionalShareNote: "private note")
            let url = try XCTUnwrap(content.immediateShareURL)
            XCTAssertEqual(url.host, URL(string: SaveShareLinkConfig.placeBaseURL)?.host)
            XCTAssertTrue(url.path.hasPrefix("/p/"))
            let decoded = try XCTUnwrap(SharedPlaceData.from(url: url))
            XCTAssertEqual(decoded.name, payload.name)
            XCTAssertEqual(decoded.address, payload.address)
            XCTAssertEqual(decoded.lat, payload.lat)
            XCTAssertEqual(decoded.lng, payload.lng)
            XCTAssertNil(decoded.note)
            XCTAssertEqual(content.message(for: url), "Savvy Map Stamp\nKato\n777 S Alameda St")
        }
    }

    @MainActor
    func testEvenEmbeddedPayloadCannotLeakPrivateNote() throws {
        let payload = Self.payload(sourceURL: nil).withShareNote("private note")
        let content = SavePlaceShareContent(subject: "Kato", fallbackURL: payload.toURL(), fallbackText: "Kato",
            payload: payload, sourcePlaceId: nil, optionalShareNote: "other private note")
        let decoded = try XCTUnwrap(SharedPlaceData.from(url: try XCTUnwrap(content.immediateShareURL)))
        XCTAssertNil(decoded.note)
    }

    @MainActor
    func testMissingOrInvalidIdentityStaysTextOnly() {
        for payload in [nil, Self.payload(sourceURL: nil, latitude: 0, longitude: 0),
                        Self.payload(sourceURL: nil, latitude: .nan),
                        Self.payload(sourceURL: nil, latitude: 91)] {
            let content = SavePlaceShareContent(subject: "Review Candidate: Kato", fallbackURL: nil,
                fallbackText: "Review Candidate\nKato", payload: payload,
                sourcePlaceId: nil, optionalShareNote: nil)
            XCTAssertNil(content.immediateShareURL)
            XCTAssertFalse(content.immediateShareText.contains("http"))
        }
    }

    @MainActor
    func testPreparedMessagePreservesReviewAndRecommendationState() {
        let payload = Self.payload(sourceURL: nil)
        let review = SavePlaceShareContent(
            subject: "Review Candidate: Kato",
            fallbackURL: nil,
            fallbackText: "Review Candidate\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
        let recommendation = SavePlaceShareContent(
            subject: "Savvy recommendation: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy recommendation\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertTrue(review.immediateShareText.hasPrefix("Review Candidate\nKato"))
        XCTAssertTrue(recommendation.immediateShareText.hasPrefix("Savvy recommendation\nKato"))
    }

    private static func payload(
        sourceURL: URL?,
        latitude: Double = 34.035,
        longitude: Double = -118.238
    ) -> SharedPlaceData {
        SharedPlaceData(
            id: "kato",
            name: "Kato",
            address: "777 S Alameda St",
            lat: latitude,
            lng: longitude,
            category: "Food",
            rating: 4.8,
            reviewCount: 120,
            priceRange: "$$$",
            hours: "Open",
            sourceLabel: "Google",
            sourceURL: sourceURL?.absoluteString,
            photoURLs: [],
            note: nil
        )
    }
}
