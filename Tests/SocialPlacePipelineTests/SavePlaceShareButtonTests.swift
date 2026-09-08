import XCTest
@testable import SAVE

final class SavePlaceShareButtonTests: XCTestCase {
    @MainActor
    func testImmediateShareUsesCompactPublicSourceInsteadOfEmbeddedPayload() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://www.google.com/maps/place/Kato"))
        let payload = Self.payload(sourceURL: sourceURL)
        let embeddedURL = try XCTUnwrap(payload.toURL())
        let content = SavePlaceShareContent(
            subject: "Savvy Map Stamp: Kato",
            fallbackURL: embeddedURL,
            fallbackText: "Savvy Map Stamp\nKato\n777 S Alameda St\nOpen in Savvy: \(embeddedURL.absoluteString)",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: "private note"
        )

        XCTAssertEqual(content.immediateShareURL, sourceURL)
        XCTAssertEqual(content.immediateShareText, "Savvy Map Stamp\nKato\n777 S Alameda St\n\(sourceURL.absoluteString)")
        XCTAssertFalse(content.immediateShareText.contains(embeddedURL.absoluteString))
        XCTAssertEqual(content.message(for: embeddedURL), "Savvy Map Stamp\nKato\n777 S Alameda St")
        XCTAssertFalse(content.message(for: embeddedURL).contains("http"))
    }

    @MainActor
    func testImmediateShareFallsBackToAppleMapsWhenSourceIsUnavailable() throws {
        let payload = Self.payload(sourceURL: nil)
        let content = SavePlaceShareContent(
            subject: "Savvy Place: Kato",
            fallbackURL: try XCTUnwrap(payload.toURL()),
            fallbackText: "Savvy Place\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        let immediateURL = try XCTUnwrap(content.immediateShareURL)
        XCTAssertEqual(immediateURL.host, "maps.apple.com")
        XCTAssertLessThan(immediateURL.absoluteString.count, 256)
        XCTAssertTrue(content.immediateShareText.hasPrefix("Savvy Place\nKato\n777 S Alameda St\nhttps://maps.apple.com/"))
    }

    @MainActor
    func testNoPayloadKeepsOfflineShareConciseWithoutInventingLink() {
        let content = SavePlaceShareContent(
            subject: "Savvy Source Clue: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Source Clue\nKato\nLong evidence URL should not be shared",
            payload: nil,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertNil(content.immediateShareURL)
        XCTAssertEqual(content.immediateShareText, "Savvy Source Clue\nKato")
    }

    @MainActor
    func testUnknownCoordinatesDoNotCreateAGlobalAppleMapsPin() {
        let payload = Self.payload(sourceURL: nil, latitude: 0, longitude: 0)
        let content = SavePlaceShareContent(
            subject: "Savvy Place: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Place\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertNil(content.immediateShareURL)
        XCTAssertEqual(content.immediateShareText, "Savvy Place\nKato\n777 S Alameda St")
    }

    @MainActor
    func testNonFiniteCoordinatesDoNotCreateAppleMapsFallback() {
        let payload = Self.payload(sourceURL: nil, latitude: .nan, longitude: 1)
        let content = SavePlaceShareContent(
            subject: "Savvy Place: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Place\nKato",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertNil(content.immediateShareURL)
    }

    @MainActor
    func testOversizedSourceUsesCompactMapsFallbackWhenCoordinatesAreKnown() throws {
        let oversizedSource = "https://example.com/" + String(repeating: "a", count: 600)
        let payload = Self.payload(sourceURL: URL(string: oversizedSource))
        let content = SavePlaceShareContent(
            subject: "Savvy Place: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Place\nKato",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        let immediateURL = try XCTUnwrap(content.immediateShareURL)
        XCTAssertEqual(immediateURL.host, "maps.apple.com")
        XCTAssertLessThanOrEqual(immediateURL.absoluteString.count, 512)
    }

    @MainActor
    func testProviderMapRootFallsBackToSpecificAppleMapsURL() throws {
        let payload = Self.payload(sourceURL: URL(string: "https://www.google.com/maps?query_place_id=abc"))
        let content = SavePlaceShareContent(
            subject: "Savvy Map Stamp: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Map Stamp\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        let immediateURL = try XCTUnwrap(content.immediateShareURL)
        XCTAssertEqual(immediateURL, payload.appleMapsURL)
        XCTAssertTrue(immediateURL.absoluteString.contains("q=Kato"))
        XCTAssertTrue(content.immediateShareText.contains("Savvy Map Stamp"))
    }

    @MainActor
    func testAppleMapsQueryOnlySourceFallsBackToSpecificAppleMapsURL() throws {
        let payload = Self.payload(sourceURL: URL(string: "https://maps.apple.com/?q=Other&ll=1,2"))
        let content = SavePlaceShareContent(
            subject: "Savvy Map Stamp: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Map Stamp\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertEqual(content.immediateShareURL, payload.appleMapsURL)
    }

    @MainActor
    func testUnknownCoordinatesWithGenericMapSourceStayTextOnly() {
        let payload = Self.payload(
            sourceURL: URL(string: "https://maps.apple.com/?q=Kato&ll=0,0"),
            latitude: 0,
            longitude: 0
        )
        let content = SavePlaceShareContent(
            subject: "Savvy Source Clue: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Source Clue\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertNil(content.immediateShareURL)
        XCTAssertEqual(content.immediateShareText, "Savvy Source Clue\nKato\n777 S Alameda St")
    }

    @MainActor
    func testIdentityFreeProviderPathsWithUnknownCoordinatesStayTextOnly() {
        for sourceURL in [
            "https://www.google.com/maps/place/?q=Kato",
            "https://maps.apple.com/place?auid=123",
            "https://uri.amap.com/marker?position=121.5,31.2&name=Kato"
        ] {
            let payload = Self.payload(sourceURL: URL(string: sourceURL), latitude: 0, longitude: 0)
            let content = SavePlaceShareContent(
                subject: "Savvy Source Clue: Kato",
                fallbackURL: nil,
                fallbackText: "Savvy Source Clue\nKato\n777 S Alameda St",
                payload: payload,
                sourcePlaceId: nil,
                optionalShareNote: nil
            )

            XCTAssertNil(content.immediateShareURL, sourceURL)
            XCTAssertEqual(content.immediateShareText, "Savvy Source Clue\nKato\n777 S Alameda St", sourceURL)
        }
    }

    @MainActor
    func testAmapMarkerQueryFallsBackToSpecificAppleMapsURL() throws {
        let payload = Self.payload(
            sourceURL: URL(string: "https://uri.amap.com/marker?position=121.5,31.2&name=Kato")
        )
        let content = SavePlaceShareContent(
            subject: "Savvy Map Stamp: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Map Stamp\nKato\n777 S Alameda St",
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertEqual(content.immediateShareURL, payload.appleMapsURL)
        XCTAssertTrue(content.immediateShareText.contains("https://maps.apple.com/"))
        XCTAssertFalse(content.immediateShareText.contains("uri.amap.com/marker"))
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
