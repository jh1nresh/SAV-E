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
            sourceLabel: "SAV-E",
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
            sourceLabel: "SAV-E",
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
            sourceLabel: "SAV-E",
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
            subject: "SAV-E Map Stamp: Kato",
            fallbackURL: fallbackURL,
            fallbackText: "SAV-E Map Stamp\nKato\nOpen in SAV-E: \(fallbackURL.absoluteString)",
            payload: nil,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )

        let message = content.message(for: shortURL)

        XCTAssertTrue(message.contains(shortURL.absoluteString))
        XCTAssertFalse(message.contains(fallbackURL.absoluteString))
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
            sourceLabel: "SAV-E",
            sourceURL: nil,
            photoURLs: [],
            note: nil
        )
        let content = SavePlaceShareContent(
            subject: "SAV-E Map Stamp: Kato",
            fallbackURL: fallbackURL,
            fallbackText: "SAV-E Map Stamp\nKato\nOpen in SAV-E: \(fallbackURL.absoluteString)",
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
    func testVerifiedReceiptDecodesServerOwnedSenderAndCreatesPrivateMemory() throws {
        let data = try XCTUnwrap(Self.verifiedReceiptJSON.data(using: .utf8))

        let receipt = try SharedPlaceReceipt.decode(data: data, code: "AbC123_x")
        let savedPlace = receipt.privatePlace()

        XCTAssertEqual(receipt.verifiedSenderLabel, "Mina")
        XCTAssertEqual(receipt.sourcePlaceID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(receipt.fullAppURL?.absoluteString, "wanderly://p/AbC123_x")
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
            sourceLabel: "SAV-E",
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
        "sourceLabel": "SAV-E",
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
