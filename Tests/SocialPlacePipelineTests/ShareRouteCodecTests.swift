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
    func testDemoPlacePathIsNeitherShortCodeNorEmbeddedPayload() throws {
        let url = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/demo"))

        XCTAssertNil(SharedPlaceData.shortCode(from: url))
        XCTAssertNil(SharedPlaceData.from(url: url))
    }

    @MainActor
    func testSAVEClipLocalInvokeURLDecodesQuarterSheetsPlace() throws {
        let url = try XCTUnwrap(URL(string: Self.saveClipLocalInvokeURL))
        let decoded = try XCTUnwrap(SharedPlaceData.from(url: url))

        XCTAssertNil(SharedPlaceData.shortCode(from: url))
        XCTAssertEqual(decoded.id, "quarter-sheets-pizza-club")
        XCTAssertEqual(decoded.name, "Quarter Sheets Pizza Club")
        XCTAssertEqual(decoded.address, "1305 Portia St, Los Angeles, CA 90026")
        XCTAssertEqual(decoded.lat, 34.0779)
        XCTAssertEqual(decoded.lng, -118.2543)
        XCTAssertEqual(decoded.category, "Food")
        XCTAssertEqual(decoded.rating, 4.6)
        XCTAssertEqual(decoded.reviewCount, 412)
        XCTAssertEqual(decoded.priceRange, "$$")
        XCTAssertEqual(decoded.hours, "Wed-Sun dinner")
        XCTAssertEqual(decoded.sourceLabel, "Google")
        XCTAssertEqual(decoded.sourceURL, "https://www.google.com/maps/place/Quarter+Sheets+Pizza+Club")
        XCTAssertEqual(decoded.note, "Save this for a slow dinner night")
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
        XCTAssertNotEqual(payload.embeddedReceiptID, payload.withShareNote("Sit at the counter").embeddedReceiptID)

        let otherSource = SharedPlaceData(
            id: payload.id,
            name: payload.name,
            address: payload.address,
            lat: payload.lat,
            lng: payload.lng,
            category: payload.category,
            rating: payload.rating,
            reviewCount: payload.reviewCount,
            priceRange: payload.priceRange,
            hours: payload.hours,
            sourceLabel: payload.sourceLabel,
            sourceURL: "https://example.com/other-source",
            photoURLs: payload.photoURLs,
            note: payload.note
        )
        XCTAssertNotEqual(payload.embeddedReceiptID, otherSource.embeddedReceiptID)
    }

    @MainActor
    func testEmbeddedPlaceRejectsInvalidCoordinatesAndUnsafeURLs() throws {
        let invalidCoordinate = SharedPlaceData(
            id: "place_bad",
            name: "Impossible Place",
            address: "Nowhere",
            lat: 999,
            lng: -118.238,
            category: "Food",
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: "javascript:alert(1)",
            photoURLs: ["file:///private/photo.jpg"],
            note: String(repeating: "a", count: 240)
        )
        let invalidURL = try XCTUnwrap(invalidCoordinate.toURL())
        XCTAssertNil(SharedPlaceData.from(url: invalidURL))

        let validCoordinate = SharedPlaceData(
            id: "place_safe",
            name: "Kato",
            address: "Los Angeles",
            lat: 34.035,
            lng: -118.238,
            category: "Food",
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: "javascript:alert(1)",
            photoURLs: ["file:///private/photo.jpg"],
            note: String(repeating: "a", count: 240)
        )
        let sanitized = try XCTUnwrap(SharedPlaceData.from(url: try XCTUnwrap(validCoordinate.toURL())))
        XCTAssertNil(sanitized.sourceURL)
        XCTAssertTrue(sanitized.photoURLs.isEmpty)
        XCTAssertLessThanOrEqual(sanitized.note?.utf16.count ?? 0, 180)
        XCTAssertNil(ShareRoutePayloadSanitizer.publicNote("Debug: private pipeline state"))
        XCTAssertLessThanOrEqual(
            ShareRoutePayloadSanitizer.publicNote(String(repeating: "🍜", count: 180))?.utf16.count ?? 0,
            180
        )

        let queryCredentialed = SharedPlaceData(
            id: "place_query_secret",
            name: "Kato",
            address: "Los Angeles",
            lat: 34.035,
            lng: -118.238,
            category: "Food",
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: "https://example.com/place?token=secret#fragment",
            photoURLs: ["https://example.com/photo.jpg?signature=secret#fragment"],
            note: "Confidence: 92%"
        )
        let safeOutgoing = try XCTUnwrap(SharedPlaceData.from(url: try XCTUnwrap(queryCredentialed.toURL())))
        XCTAssertEqual(safeOutgoing.sourceURL, "https://example.com/place")
        XCTAssertEqual(safeOutgoing.photoURLs, ["https://example.com/photo.jpg"])
        XCTAssertNil(safeOutgoing.note)
    }

    @MainActor
    func testShareContentMessageUsesResolvedShortURL() throws {
        let fallbackURL = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/embeddedPayload"))
        let shortURL = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/AbC123_x"))
        let content = SavePlaceShareContent(
            subject: "Savvy Map Stamp: Kato",
            fallbackURL: fallbackURL,
            fallbackText: "Savvy Map Stamp\nKato\nOpen in Savvy: \(fallbackURL.absoluteString)",
            payload: nil,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        let message = content.message(for: shortURL)

        XCTAssertTrue(message.contains(shortURL.absoluteString))
        XCTAssertFalse(message.contains(fallbackURL.absoluteString))
    }

    @MainActor
    func testShareContentWithoutFallbackURLKeepsImmediatePlainTextItem() {
        let content = SavePlaceShareContent(
            subject: "Savvy Map Result: Kato",
            fallbackURL: nil,
            fallbackText: "Savvy Map Result\nKato",
            payload: SharedPlaceData(
                id: "place_1",
                name: "Kato",
                address: "Los Angeles",
                lat: 34.035,
                lng: -118.238,
                category: "Food",
                rating: nil,
                reviewCount: nil,
                priceRange: nil,
                hours: nil,
                sourceLabel: "Savvy",
                sourceURL: nil,
                photoURLs: [],
                note: nil
            ),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        XCTAssertEqual(content.immediateShareText, content.fallbackText)
        XCTAssertNil(content.fallbackURL)
    }

    @MainActor
    func testPrivateShareNoteIsExcludedUntilExplicitlyIncluded() throws {
        let fallbackURL = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/p/embeddedPayload"))
        let payload = SharedPlaceData(
            id: "place_1",
            name: "Kato",
            address: "Los Angeles",
            lat: 34.035,
            lng: -118.238,
            category: "Food",
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: nil,
            photoURLs: [],
            note: nil
        )
        let content = SavePlaceShareContent(
            subject: "Savvy Map Stamp: Kato",
            fallbackURL: fallbackURL,
            fallbackText: "Savvy Map Stamp\nKato\nOpen in Savvy: \(fallbackURL.absoluteString)",
            payload: payload,
            sourcePlaceId: UUID(),
            optionalShareNote: "Order the tasting menu"
        )

        XCTAssertNil(content.payload(includingOptionalNote: false)?.note)
        XCTAssertEqual(content.payload(includingOptionalNote: true)?.note, "Order the tasting menu")
        XCTAssertFalse(content.message(for: fallbackURL).contains("Order the tasting menu"))
        XCTAssertTrue(content.message(
            for: fallbackURL,
            includingOptionalNote: true
        ).contains("Order the tasting menu"))

        let otherNoteContent = SavePlaceShareContent(
            subject: content.subject,
            fallbackURL: content.fallbackURL,
            fallbackText: content.fallbackText,
            payload: payload,
            sourcePlaceId: content.sourcePlaceId,
            optionalShareNote: "Sit at the counter"
        )
        XCTAssertNotEqual(
            content.cacheKey(includingOptionalNote: true),
            otherNoteContent.cacheKey(includingOptionalNote: true)
        )
        XCTAssertNotEqual(content.stateKey, otherNoteContent.stateKey)
    }

    @MainActor
    func testCommunityRecommendationReshareDoesNotClaimOrLeakOriginalPlace() throws {
        var place = Place(
            id: UUID(uuidString: "7B095461-6957-4C5B-9F43-0C6D9A2F459A")!,
            name: "Koffee Mameya",
            address: "Shibuya City, Tokyo",
            latitude: 35.665,
            longitude: 139.710,
            category: .cafe,
            status: .wantToGo,
            note: "Private note: surprise birthday dinner",
            sourceUrl: "https://www.instagram.com/p/example/?token=private#fragment",
            sourcePlatform: .instagram,
            sourceImageUrl: "https://example.com/photo.jpg?signature=private",
            recommender: "Mina",
            createdAt: Date(timeIntervalSince1970: 1_721_865_600),
            visibility: .publicGuide,
            socialSignal: PlaceSocialSignal(
                kind: .communityRecommendation,
                lens: .forYou,
                friendNames: [],
                friendCount: 0,
                saveCount: 0,
                trendingRank: nil,
                categoryRank: nil,
                sourceLabel: "Mina",
                referrerId: "user-2",
                referralCode: nil
            )
        )
        place.businessPhotoUrls = ["https://example.com/other.jpg?signature=private"]

        let content = SavePlaceShareContent.communityRecommendation(place)
        let payload = try XCTUnwrap(content.payload(includingOptionalNote: false))

        XCTAssertNil(content.sourcePlaceId)
        XCTAssertNil(content.optionalShareNote)
        XCTAssertEqual(payload.id, "")
        XCTAssertNil(payload.note)
        XCTAssertNil(content.payload(includingOptionalNote: true)?.note)
        XCTAssertEqual(payload.sourceURL, "https://www.instagram.com/p/example/")
        XCTAssertEqual(payload.photoURLs, ["https://example.com/other.jpg"])
        XCTAssertFalse(content.fallbackText.contains("surprise birthday"))
        XCTAssertFalse(content.fallbackText.contains(place.id.uuidString))
    }

    @MainActor
    func testVerifiedReceiptDecodesServerOwnedSenderAndCreatesPrivateMemory() throws {
        let data = try XCTUnwrap(Self.verifiedReceiptJSON.data(using: .utf8))

        let receipt = try SharedPlaceReceipt.decode(data: data, code: "AbC123_x")
        let savedPlace = receipt.privatePlace()

        XCTAssertEqual(receipt.verifiedSenderLabel, "Mina")
        XCTAssertEqual(receipt.sourcePlaceID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(receipt.fullAppURL?.absoluteString, "savvy://p/AbC123_x")
        XCTAssertEqual(savedPlace.recommender, "Mina")
        XCTAssertEqual(savedPlace.status, .wantToGo)
        XCTAssertEqual(savedPlace.visibility, .privateMemory)
        XCTAssertEqual(savedPlace.note, "Order the tasting menu")

        var placeWithCredentialedSource = savedPlace
        placeWithCredentialedSource.sourceUrl = "https://user:secret@example.com/private"
        XCTAssertNil(SharedPlaceData.from(place: placeWithCredentialedSource).sourceURL)
        XCTAssertFalse(placeWithCredentialedSource.shareText.contains("secret"))

        placeWithCredentialedSource.sourceUrl = "https://example.com/private?token=secret#fragment"
        XCTAssertEqual(
            SharedPlaceData.from(place: placeWithCredentialedSource).sourceURL,
            "https://example.com/private"
        )

        let oversized = SharedPlaceData(
            id: "oversized",
            name: String(repeating: "x", count: 20_000),
            address: "Los Angeles",
            lat: 34.035,
            lng: -118.238,
            category: "Food",
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: nil,
            photoURLs: [],
            note: nil
        )
        XCTAssertNil(oversized.toURL())
    }

    @MainActor
    func testEmbeddedPayloadCannotForgeVerifiedSender() throws {
        let data = try XCTUnwrap(Self.payloadForgedSenderJSON.data(using: .utf8))

        let receipt = try SharedPlaceReceipt.decode(data: data, code: "AbC123_x")

        XCTAssertNil(receipt.sender)
        XCTAssertNil(receipt.verifiedSenderLabel)
        XCTAssertNil(receipt.privatePlace().recommender)
    }

    private static let saveClipLocalInvokeURL =
        "https://sav-e-app.vercel.app/p/eyJpZCI6InF1YXJ0ZXItc2hlZXRzLXBpenphLWNsdWIiLCJuYW1lIjoiUXVhcnRlciBTaGVldHMgUGl6emEgQ2x1YiIsImFkZHJlc3MiOiIxMzA1IFBvcnRpYSBTdCwgTG9zIEFuZ2VsZXMsIENBIDkwMDI2IiwibGF0IjozNC4wNzc5LCJsbmciOi0xMTguMjU0MywiY2F0ZWdvcnkiOiJGb29kIiwicmF0aW5nIjo0LjYsInJldmlld0NvdW50Ijo0MTIsInByaWNlUmFuZ2UiOiIkJCIsImhvdXJzIjoiV2VkLVN1biBkaW5uZXIiLCJzb3VyY2VMYWJlbCI6Ikdvb2dsZSIsInNvdXJjZVVSTCI6Imh0dHBzOi8vd3d3Lmdvb2dsZS5jb20vbWFwcy9wbGFjZS9RdWFydGVyK1NoZWV0cytQaXp6YStDbHViIiwicGhvdG9VUkxzIjpbXSwibm90ZSI6IlNhdmUgdGhpcyBmb3IgYSBzbG93IGRpbm5lciBuaWdodCJ9"

    private static let verifiedReceiptJSON = #"""
    {
      "payload": {
        "id": "place_1",
        "name": "Kato",
        "address": "777 S Alameda St, Los Angeles, CA",
        "lat": 34.035,
        "lng": -118.238,
        "category": "Food",
        "rating": 4.8,
        "reviewCount": 120,
        "priceRange": "$$$",
        "hours": "Open",
        "sourceLabel": "Instagram",
        "sourceURL": "https://www.instagram.com/reel/kato/",
        "photoURLs": ["https://example.com/kato.jpg"],
        "note": "Order the tasting menu"
      },
      "source_place_id": "11111111-2222-3333-4444-555555555555",
      "expires_at": "2026-08-14T00:00:00.000Z",
      "sender": {
        "display_name": "Mina",
        "handle": "mina_eats"
      }
    }
    """#

    private static let payloadForgedSenderJSON = #"""
    {
      "payload": {
        "id": "place_2",
        "name": "Kato",
        "address": "Los Angeles",
        "lat": 34.035,
        "lng": -118.238,
        "category": "Food",
        "rating": null,
        "reviewCount": null,
        "priceRange": null,
        "hours": null,
        "sourceLabel": "Savvy",
        "sourceURL": null,
        "photoURLs": [],
        "note": null,
        "sender": { "display_name": "Mallory" }
      },
      "source_place_id": null,
      "expires_at": "2026-08-14T00:00:00.000Z",
      "sender": null
    }
    """#
}
