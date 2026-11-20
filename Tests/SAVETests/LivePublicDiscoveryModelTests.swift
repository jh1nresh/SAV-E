#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import XCTest
@testable import SAVE

@MainActor
final class LivePublicDiscoveryModelTests: XCTestCase {
    func testLateViewportResponseCannotReplaceNewViewport() async throws {
        let backend = HeldDiscoveryBackend()
        let now = Date()
        let model = LivePublicDiscoveryModel(backend: backend, sessionIsCurrent: { true }, now: { now })
        let firstRead = expectation(description: "first viewport requested")
        let secondRead = expectation(description: "second viewport requested")
        backend.onRead = { $0 == 1 ? firstRead.fulfill() : secondRead.fulfill() }
        let first = Task { await model.refresh(try! Self.viewport()) }
        await fulfillment(of: [firstRead], timeout: 3)
        let second = Task { await model.refresh(try! Self.viewport(west: 121.4)) }
        await fulfillment(of: [secondRead], timeout: 3)
        backend.complete(1, page: try Self.page(now: now, title: "New viewport"))
        await second.value
        backend.complete(0, page: try Self.page(now: now, title: "Old viewport"))
        await first.value
        XCTAssertEqual(model.page?.posts.first?.title, "New viewport")
        model.clear()
    }

    func testClearAndAccountChangeDiscardInFlightPayload() async throws {
        for clear in [false, true] {
            let backend = HeldDiscoveryBackend()
            var current = true
            let now = Date()
            let model = LivePublicDiscoveryModel(backend: backend, sessionIsCurrent: { current }, now: { now })
            let called = expectation(description: "request suspended")
            backend.onRead = { _ in called.fulfill() }
            let task = Task { await model.refresh(try! Self.viewport()) }
            await fulfillment(of: [called], timeout: 3)
            if clear { model.clear() } else { current = false }
            backend.complete(0, page: try Self.page(now: now))
            await task.value
            XCTAssertNil(model.page)
            XCTAssertFalse(model.isLoading)
            model.clear()
        }
    }

    func testOutOfViewportDataFailsInsteadOfDisplayingWrongPins() async throws {
        let backend = HeldDiscoveryBackend()
        let now = Date()
        let model = LivePublicDiscoveryModel(backend: backend, sessionIsCurrent: { true }, now: { now })
        let called = expectation(description: "request suspended")
        backend.onRead = { _ in called.fulfill() }
        let task = Task { await model.refresh(try! Self.viewport(west: 1, east: 2)) }
        await fulfillment(of: [called], timeout: 3)
        backend.complete(0, page: try Self.page(now: now))
        await task.value
        XCTAssertNil(model.page)
        XCTAssertTrue(model.unavailable)
        model.clear()
    }

    func testPublicPostProjectionExportsOnlyVenueAndExplicitURL() throws {
        let value = try Self.page(now: Date()).validated(at: Date())
        let venue = try XCTUnwrap(value.venues.first)
        let pin = try XCTUnwrap(LiveMapPlace.discovery(venue))
        XCTAssertEqual(pin.origin, .publicPost)
        XCTAssertEqual(pin.place.status, .wantToGo)
        XCTAssertTrue(pin.place.note?.isEmpty ?? true)
        XCTAssertNil(pin.place.recommender)
        XCTAssertNil(pin.listPayload.note)
        XCTAssertTrue(pin.listPayload.photoURLs.isEmpty)
        XCTAssertNil(pin.listPayload.rating)
        XCTAssertNil(pin.listPayload.sourceURL)
        XCTAssertEqual(pin.confirmationCandidate?.sourceURL, venue.posts[0].sourceURL)
        XCTAssertFalse(pin.confirmationCandidate?.evidence.contains("TEST ONLY") ?? true)
        XCTAssertNotNil(LivePublicPostCover.date("2026-11-14T12:00:00.000Z"))
    }

    static func viewport(west: Double = 121.5, east: Double = 121.6) throws -> LivePublicDiscoveryViewport {
        try .init(west: west, south: 25, east: east, north: 25.1)
    }

    static func page(now: Date, title: String = "TEST ONLY · public source fixture") throws -> LivePublicDiscoveryPage {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = parser.string(from: now.addingTimeInterval(-1))
        let expiry = parser.string(from: now.addingTimeInterval(120))
        let value: [String: Any] = [
            "schemaVersion": 1, "indexRevision": String(repeating: "a", count: 64),
            "generatedAt": stamp, "expiresAt": expiry, "nextCursor": NSNull(),
            "coverage": [
                ["platform": "threads", "status": "connected", "indexedPostCount": 1],
                ["platform": "instagram", "status": "not_connected", "indexedPostCount": 0],
                ["platform": "xiaohongshu", "status": "not_connected", "indexedPostCount": 0]
            ],
            "posts": [["id": "threads:FixturePost", "platform": "threads",
                "sourceURL": "https://www.threads.com/@fixture/post/FixturePost",
                "authorName": "Fixture author", "authorHandle": "fixture", "title": title,
                "publishedAt": NSNull(), "verifiedAt": stamp, "visibility": "public",
                "locationEvidence": "reviewed_match", "cover": NSNull(),
                "place": ["provider": "apple_maps", "providerPlaceID": "fixture-venue", "name": "Fixture venue",
                          "address": "1 Fixture Road", "latitude": 25.03, "longitude": 121.54,
                          "coordinateSystem": "WGS84", "category": "cafe"]]]
        ]
        return try JSONDecoder().decode(LivePublicDiscoveryPage.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

@MainActor
private final class HeldDiscoveryBackend: LivePublicDiscoveryBackend {
    var onRead: ((Int) -> Void)?
    private var continuations: [CheckedContinuation<LivePublicDiscoveryPage, Error>?] = []
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?) async throws -> LivePublicDiscoveryPage {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            onRead?(continuations.count)
        }
    }
    func complete(_ index: Int, page: LivePublicDiscoveryPage) {
        let continuation = continuations[index]; continuations[index] = nil
        continuation?.resume(returning: page)
    }
}
#endif
