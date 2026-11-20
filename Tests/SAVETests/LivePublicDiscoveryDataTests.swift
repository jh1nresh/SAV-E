#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
@testable import SAVE

/// Redacted wire fixtures only: no transport, account, imagery or saved-place writes.
@MainActor
final class LivePublicDiscoveryDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_657_600) // 2026-11-14 12:00 UTC
    private let revision = String(repeating: "a", count: 64)
    private let cursor = String(repeating: "c", count: 43)

    func testCamelCaseWireRoundTripCreatesOnlyValidatedPublicVenue() throws {
        let raw = try decode(page())
        let decoded = try JSONDecoder().decode(LivePublicDiscoveryPage.self, from: JSONEncoder().encode(raw))
        let result = try decoded.validated(at: now)
        XCTAssertEqual(result.posts.count, 1)
        XCTAssertEqual(result.venues.first?.id, "apple_maps:fixture-venue")
        XCTAssertEqual(result.venues.first?.posts.first?.authorName, "Fixture publisher")
        XCTAssertEqual(result.expiresAt, now.addingTimeInterval(300))
        XCTAssertNil(result.posts.first?.publishedAt, "Verification time cannot invent a publication date")
        XCTAssertNil(result.posts.first?.cover)
    }

    func testMalformedSchemaDatesFreshnessAndPublicBoundaryFailClosed() throws {
        for overrides: [String: Any] in [
            ["schemaVersion": 2], ["indexRevision": "not-a-revision"],
            ["generatedAt": "not-a-date"], ["generatedAt": timestamp(now.addingTimeInterval(1))],
            ["generatedAt": timestamp(now.addingTimeInterval(-86_401))],
            ["expiresAt": timestamp(now)], ["expiresAt": timestamp(now.addingTimeInterval(301))]
        ] {
            XCTAssertThrowsError(try decode(page(overrides: overrides)).validated(at: now))
        }
        for overrides: [String: Any] in [
            ["visibility": "friends"], ["visibility": "private"], ["locationEvidence": "inferred"],
            ["verifiedAt": timestamp(now.addingTimeInterval(1))],
            ["verifiedAt": timestamp(now.addingTimeInterval(-86_401))],
            ["verifiedAt": timestamp(now.addingTimeInterval(-86_300))], // Page outlives source check.
            ["publishedAt": timestamp(now.addingTimeInterval(1))],
            ["title": String(repeating: "x", count: 161)], ["authorName": String(repeating: "x", count: 81)]
        ] {
            XCTAssertThrowsError(try decode(page(posts: [post(overrides: overrides)])).validated(at: now))
        }
        var missing = post(); missing.removeValue(forKey: "sourceURL")
        XCTAssertThrowsError(try decode(page(posts: [missing])))
        var wrongType = post(); wrongType["verifiedAt"] = 123
        XCTAssertThrowsError(try decode(page(posts: [wrongType])))
    }

    func testCanonicalSourcesRejectProfilesShortLinksTokensAndWrongIdentity() throws {
        let cases = [
            ("instagram", "Ab_C", "https://instagram.com/reels/Ab_C?utm_source=fixture#view", "https://www.instagram.com/reel/Ab_C/"),
            ("threads", "FixtureA", "https://threads.net/@fixture/post/FixtureA?igshid=fixture#view", "https://www.threads.com/@fixture/post/FixtureA"),
            ("xiaohongshu", "abcdef0123456789abcdef01", "https://xiaohongshu.com/discovery/item/ABCDEF0123456789ABCDEF01", "https://www.xiaohongshu.com/explore/abcdef0123456789abcdef01")
        ]
        for (platform, id, url, expected) in cases {
            let result = try decode(page(posts: [post(overrides: ["id": "\(platform):\(id)", "platform": platform, "sourceURL": url])])).validated(at: now)
            XCTAssertEqual(result.posts.first?.sourceURL, expected)
            XCTAssertEqual(result.posts.first?.sourceLink?.absoluteString, expected)
        }
        for url in ["https://threads.com/@fixture", "https://threads.com/login", "https://threads.com/search?q=cafe",
                    "https://threads.com.evil.invalid/@fixture/post/FixtureA", "https://user:pass@threads.com/@fixture/post/FixtureA",
                    "http://threads.com/@fixture/post/FixtureA", "https://threads.com/@fixture/post/FixtureA?access_token=fixture",
                    "https://threads.com/@fixture/post/FixtureA#access_token=fixture", "https://threads.com/@fixture/post/FixtureA?auth=fixture",
                    "https://threads.com/@fixture/post/FixtureA?key=fixture", "https://xhslink.com/fixture",
                    "https://threads.com/@fixture/post/FixtureA/extra", "https://threads.com/@fixture/post/Fixture%2FA"] {
            XCTAssertThrowsError(try decode(page(posts: [post(overrides: ["sourceURL": url])])).validated(at: now), url)
        }
        XCTAssertThrowsError(try decode(page(posts: [post(overrides: ["id": "threads:different"])])).validated(at: now))
    }

    func testOptionalAttributionStaysUnknownAndIncompletePagesAreNotFullCoverage() throws {
        let result = try decode(page(posts: [post(overrides: ["authorName": NSNull(), "authorHandle": NSNull()])])).validated(at: now)
        XCTAssertNil(result.posts.first?.authorName)
        XCTAssertNil(result.posts.first?.authorHandle)
        XCTAssertEqual(result.coverage.first?.indexedPostCount, 10)
        XCTAssertEqual(result.posts.count, 1, "An incomplete page need not contain every indexed post")
        let emptyCoverage = ["instagram", "threads", "xiaohongshu"].map {
            ["platform": $0, "status": "not_connected", "indexedPostCount": 0] as [String: Any]
        }
        XCTAssertTrue(try decode(page(posts: [], overrides: ["coverage": emptyCoverage])).validated(at: now).venues.isEmpty)
        XCTAssertThrowsError(try decode(page(overrides: ["coverage": emptyCoverage])).validated(at: now))
        XCTAssertThrowsError(try decode(page(overrides: ["coverage": Array(emptyCoverage.prefix(2))])).validated(at: now))
        var duplicate = emptyCoverage; duplicate[2] = duplicate[0]
        XCTAssertThrowsError(try decode(page(posts: [], overrides: ["coverage": duplicate])).validated(at: now))
    }

    func testCoverGrantsExpiryHostAndPlatformAreEnforcedWithoutLosingPublicPost() throws {
        let good = cover()
        let accepted = try decode(page(posts: [post(overrides: ["cover": good])])).validated(at: now)
        XCTAssertEqual(accepted.expiresAt, now.addingTimeInterval(60), "Page cannot expose a cover after its preview grant expires")
        XCTAssertNotNil(accepted.posts.first?.cover?.previewURL(at: now, platform: "threads"))
        XCTAssertNil(accepted.posts.first?.cover?.previewURL(at: now.addingTimeInterval(60), platform: "threads"))
        for overrides: [String: Any] in [
            ["permission": "unknown"], ["expiresAt": timestamp(now)], ["expiresAt": "invalid"],
            ["url": "https://127.0.0.1/photo.jpg"], ["url": "https://cdninstagram.com.evil.invalid/photo.jpg"],
            ["url": "http://scontent.cdninstagram.com/photo.jpg"], ["url": "https://u:p@scontent.cdninstagram.com/photo.jpg"],
            ["url": "https://scontent.cdninstagram.com/photo.jpg?api_key=fixture"],
            ["url": "https://sns-webpic-qc.xhscdn.com/photo.jpg"], ["url": "https://api.xiaohongshu.com/photo.jpg"]
        ] {
            var invalid = good; overrides.forEach { invalid[$0.key] = $0.value }
            let result = try decode(page(posts: [post(overrides: ["cover": invalid])])).validated(at: now)
            XCTAssertEqual(result.posts.count, 1)
            XCTAssertNil(result.posts.first?.cover, "Rejected post cover must remain explicitly missing")
        }
        XCTAssertNotNil(LivePublicDiscoveryCover.validatedURL("https://sns-webpic-qc.xhscdn.com/photo.jpg", platform: "xiaohongshu"))
        XCTAssertNil(LivePublicDiscoveryCover.validatedURL("https://www.xiaohongshu.com/explore/fixture", platform: "xiaohongshu"))
        XCTAssertNil(LivePublicDiscoveryCover.validatedURL("https://scontent.fbcdn.net/photo.jpg", platform: "unknown"))
    }

    func testViewportHandlesDatelineAndRejectsInvalidBoundsOrOutOfRequestRecords() throws {
        let crossing = try LivePublicDiscoveryViewport(west: 170, south: -20, east: -170, north: 20)
        XCTAssertTrue(crossing.contains(latitude: 0, longitude: 179))
        XCTAssertTrue(crossing.contains(latitude: 0, longitude: -179))
        XCTAssertFalse(crossing.contains(latitude: 0, longitude: 0))
        XCTAssertEqual(try LivePublicDiscoveryViewport(west: -0.0, south: -20, east: 10, north: 20).queryValue, "0.0,-20.0,10.0,20.0")
        for bounds in [(Double.nan, -10.0, 20.0, 10.0), (-181, -10, 20, 10), (10, 20, 30, -20)] {
            XCTAssertThrowsError(try LivePublicDiscoveryViewport(west: bounds.0, south: bounds.1, east: bounds.2, north: bounds.3))
        }
        let datelineEdge = try LivePublicDiscoveryViewport(west: 180, south: -10, east: 180, north: 10)
        XCTAssertTrue(datelineEdge.contains(latitude: 0, longitude: -180))
        let local = try LivePublicDiscoveryViewport(west: 121, south: 25, east: 122, north: 26)
        XCTAssertEqual(try decode(page()).validated(at: now, viewport: local, limit: 1).posts.count, 1)
        XCTAssertThrowsError(try decode(page()).validated(at: now, viewport: crossing))
        XCTAssertThrowsError(try decode(page()).validated(at: now, limit: 0))
    }

    func testExactProviderIdentityGroupsAllAuthorsAndRejectsMetadataConflicts() throws {
        let first = post()
        let second = post(id: "FixtureB", overrides: ["authorName": "Second publisher"])
        let result = try decode(page(posts: [second, first])).validated(at: now)
        XCTAssertEqual(result.venues.count, 1)
        XCTAssertEqual(result.venues.first?.posts.map(\.id), ["threads:FixtureA", "threads:FixtureB"])
        XCTAssertEqual(Set(result.venues.first!.posts.compactMap(\.authorName)).count, 2)
        var otherProvider = place(); otherProvider["provider"] = "amap"
        let separate = try decode(page(posts: [first, post(id: "FixtureB", overrides: ["place": otherProvider])])).validated(at: now)
        XCTAssertEqual(Set(separate.venues.map(\.id)), ["apple_maps:fixture-venue", "amap:fixture-venue"])
        for field in ["name", "address", "category", "latitude"] {
            var inconsistent = place(); inconsistent[field] = field == "latitude" ? 25.031 as Any : "different" as Any
            XCTAssertThrowsError(try decode(page(posts: [first, post(id: "FixtureB", overrides: ["place": inconsistent])])).validated(at: now))
        }
        for overrides: [String: Any] in [["coordinateSystem": "GCJ02"], ["latitude": 91], ["latitude": 0, "longitude": 0], ["providerPlaceID": ""]] {
            var invalid = place(); overrides.forEach { invalid[$0.key] = $0.value }
            XCTAssertThrowsError(try decode(page(posts: [post(overrides: ["place": invalid])])).validated(at: now))
        }
    }

    func testContinuationBindsCursorRevisionCoverageAndIdenticalDuplicatesOnly() throws {
        let first = try decode(page(overrides: ["nextCursor": cursor])).validated(at: now)
        let next = try decode(page(posts: [post(), post(id: "FixtureB")])).validated(at: now)
        let appended = try next.appending(to: first, requestedCursor: cursor, at: now)
        XCTAssertEqual(appended.posts.count, 2)
        XCTAssertEqual(appended.venues.count, 1)
        XCTAssertNil(appended.nextCursor)
        XCTAssertThrowsError(try next.appending(to: first, requestedCursor: "wrong", at: now))
        XCTAssertThrowsError(try next.appending(to: first, requestedCursor: cursor, at: now.addingTimeInterval(300)))
        for overrides: [String: Any] in [["indexRevision": String(repeating: "b", count: 64)],
                                        ["generatedAt": timestamp(now.addingTimeInterval(-1))], ["nextCursor": cursor]] {
            let changedPost = post(id: "FixtureB", overrides: overrides["generatedAt"].map { ["verifiedAt": $0] } ?? [:])
            let changed = try decode(page(posts: [changedPost], overrides: overrides)).validated(at: now)
            XCTAssertThrowsError(try changed.appending(to: first, requestedCursor: cursor, at: now))
        }
        let conflict = try decode(page(posts: [post(overrides: ["title": "changed post"])] )).validated(at: now)
        XCTAssertThrowsError(try conflict.appending(to: first, requestedCursor: cursor, at: now))
        var changedPlace = place(); changedPlace["address"] = "Different branch address"
        let crossPagePlaceConflict = try decode(page(posts: [post(id: "FixtureB", overrides: ["place": changedPlace])])).validated(at: now)
        XCTAssertThrowsError(try crossPagePlaceConflict.appending(to: first, requestedCursor: cursor, at: now))
        var coverageChanged = page()
        var coverage = coverageChanged["coverage"] as! [[String: Any]]
        coverage[0]["indexedPostCount"] = 11; coverageChanged["coverage"] = coverage
        let changedCoverage = try decode(coverageChanged).validated(at: now)
        XCTAssertThrowsError(try changedCoverage.appending(to: first, requestedCursor: cursor, at: now))
        XCTAssertThrowsError(try decode(page(overrides: ["nextCursor": "not-a-server-cursor"])).validated(at: now))
        XCTAssertThrowsError(try decode(page(posts: [post(), post()])).validated(at: now))
        let secondCursor = String(repeating: "d", count: 43)
        let middle = try decode(page(posts: [post(id: "FixtureB")], overrides: ["nextCursor": secondCursor])).validated(at: now)
        let middleCombined = try middle.appending(to: first, requestedCursor: cursor, at: now)
        let replay = try decode(page(posts: [post(id: "FixtureC")], overrides: ["nextCursor": cursor])).validated(at: now)
        XCTAssertThrowsError(try replay.appending(to: middleCombined, requestedCursor: secondCursor, at: now))
    }

    func testBlankAttributionAndTitlesRemainUnknownWhileMalformedCalendarAndNonfinitePlacesFail() throws {
        let unknown = try decode(page(posts: [post(overrides: ["authorName": " \n", "authorHandle": "", "title": ""])])).validated(at: now)
        XCTAssertNil(unknown.posts.first?.authorName)
        XCTAssertNil(unknown.posts.first?.authorHandle)
        XCTAssertEqual(unknown.posts.first?.title, "")
        for value in ["2026-02-30T12:00:00Z", "2026-11-14T12:00:00+00:00", "2026-11-14", "2026-11-14T12:00:00.0001Z"] {
            XCTAssertThrowsError(try decode(page(overrides: ["generatedAt": value])).validated(at: now))
        }
        var invalidPlace = place(); invalidPlace["longitude"] = "NaN"
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let raw = try decoder.decode(LivePublicDiscoveryPage.self,
            from: JSONSerialization.data(withJSONObject: page(posts: [post(overrides: ["place": invalidPlace])])))
        XCTAssertThrowsError(try raw.validated(at: now))
    }

    private func decode(_ object: [String: Any]) throws -> LivePublicDiscoveryPage {
        try JSONDecoder().decode(LivePublicDiscoveryPage.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func timestamp(_ value: Date) -> String { ISO8601DateFormatter().string(from: value) }
    private func page(posts: [[String: Any]]? = nil, overrides: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["schemaVersion": 1, "indexRevision": revision,
            "generatedAt": timestamp(now), "expiresAt": timestamp(now.addingTimeInterval(300)),
            "coverage": ["instagram", "threads", "xiaohongshu"].map {
                ["platform": $0, "status": "connected", "indexedPostCount": 10] as [String: Any]
            }, "posts": posts ?? [post()], "nextCursor": NSNull()]
        overrides.forEach { result[$0.key] = $0.value }; return result
    }
    private func post(id: String = "FixtureA", overrides: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["id": "threads:\(id)", "platform": "threads",
            "sourceURL": "https://www.threads.com/@fixture/post/\(id)", "authorName": "Fixture publisher",
            "authorHandle": "fixture", "title": "Fixture public post", "publishedAt": NSNull(),
            "verifiedAt": timestamp(now), "visibility": "public", "locationEvidence": "reviewed_match",
            "cover": NSNull(), "place": place()]
        overrides.forEach { result[$0.key] = $0.value }; return result
    }
    private func place() -> [String: Any] {
        ["provider": "apple_maps", "providerPlaceID": "fixture-venue", "name": "Fixture Cafe",
         "address": "1 Fixture Street", "latitude": 25.03, "longitude": 121.54, "coordinateSystem": "WGS84", "category": "cafe"]
    }
    private func cover() -> [String: Any] {
        ["url": "https://scontent.cdninstagram.com/fixture.jpg", "expiresAt": timestamp(now.addingTimeInterval(60)), "permission": "author"]
    }
}
#endif
