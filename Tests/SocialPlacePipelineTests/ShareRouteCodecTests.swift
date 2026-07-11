import XCTest
@testable import SAVE

final class ShareRouteCodecTests: XCTestCase {
    @MainActor
    func testSharedPlaceShortCodeKeepsPRouteWithoutDecodingAsPayload() throws {
        let url = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/AbC123_x"))

        XCTAssertEqual(SharedPlaceData.shortCode(from: url), "AbC123_x")
        XCTAssertNil(SharedPlaceData.from(url: url))
    }

    @MainActor
    func testEmbeddedSharedPlacePayloadStillRoundTrips() throws {
        let payload = SharedPlaceData(
            id: "place_1",
            name: "Kato",
            address: "777 S Alameda St, Los Angeles, CA",
            lat: 34.035,
            lng: -118.238,
            category: "Food",
            rating: 4.8,
            reviewCount: 120,
            priceRange: "$$$",
            hours: "Open",
            sourceLabel: "Instagram",
            sourceURL: "https://www.instagram.com/reel/kato/",
            photoURLs: ["https://example.com/kato.jpg"],
            note: "Tasting menu"
        )

        let url = try XCTUnwrap(payload.toURL())
        let decoded = try XCTUnwrap(SharedPlaceData.from(url: url))

        XCTAssertNil(SharedPlaceData.shortCode(from: url))
        XCTAssertEqual(decoded.name, "Kato")
        XCTAssertEqual(decoded.address, "777 S Alameda St, Los Angeles, CA")
    }

    @MainActor
    func testShareContentMessageUsesResolvedShortURL() throws {
        let fallbackURL = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/embeddedPayload"))
        let shortURL = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/AbC123_x"))
        let content = SavePlaceShareContent(
            subject: "SAV-E Map Stamp: Kato",
            fallbackURL: fallbackURL,
            fallbackText: "SAV-E Map Stamp\nKato\nOpen in SAV-E: \(fallbackURL.absoluteString)",
            payload: nil,
            sourcePlaceId: nil
        )

        let message = content.message(for: shortURL)

        XCTAssertTrue(message.contains(shortURL.absoluteString))
        XCTAssertFalse(message.contains(fallbackURL.absoluteString))
    }
}
