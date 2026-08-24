import XCTest
@testable import SAVE

@MainActor
final class RelatedPlaceSourcesClientTests: XCTestCase {
    func testDecodesAllPlatformsAndHonestCoverageReceipt() throws {
        let placeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let data = """
        {
          "place": {
            "id": "\(placeID.uuidString)",
            "name": "Example Cafe",
            "address": "1 Example Street, Taipei",
            "latitude": 25.04,
            "longitude": 121.56,
            "google_place_id": "google-example"
          },
          "sources": [
            {
              "platform": "instagram",
              "url": "https://www.instagram.com/p/example",
              "title": "Example Cafe at 1 Example Street",
              "snippet": "A public snippet",
              "query": "site:instagram.com \\"Example Cafe\\"",
              "relation": "same_place",
              "identity_status": "candidate",
              "match_confidence": 0.91
            },
            {
              "platform": "x",
              "url": "https://x.com/example/status/123",
              "title": "Example Cafe mention",
              "snippet": null,
              "query": "site:x.com \\"Example Cafe\\"",
              "relation": "mentions_place",
              "identity_status": "candidate",
              "match_confidence": 0.58
            }
          ],
          "coverage": [
            {"platform":"instagram","method":"public_index","status":"searched","queries":["q1"],"inspected_count":2,"result_count":1,"blocked_reason":null},
            {"platform":"tiktok","method":"public_index","status":"partial","queries":["q2"],"inspected_count":1,"result_count":0,"blocked_reason":"public_search_failed"},
            {"platform":"youtube","method":"public_index","status":"searched","queries":["q3"],"inspected_count":0,"result_count":0,"blocked_reason":null},
            {"platform":"xiaohongshu","method":"public_index","status":"searched","queries":["q4"],"inspected_count":0,"result_count":0,"blocked_reason":null},
            {"platform":"douyin","method":"public_index","status":"searched","queries":["q5"],"inspected_count":0,"result_count":0,"blocked_reason":null},
            {"platform":"threads","method":"public_index","status":"searched","queries":["q6"],"inspected_count":0,"result_count":0,"blocked_reason":null},
            {"platform":"x","method":"public_index","status":"failed","queries":["q7"],"inspected_count":0,"result_count":0,"blocked_reason":"public_search_failed"}
          ],
          "receipt": {
            "source_boundary": "public_web_index",
            "privacy": "owner_private",
            "checked_at": "2026-07-24T08:00:00.000Z",
            "requested_platforms": ["instagram","tiktok","youtube","xiaohongshu","douyin","threads","x"],
            "searched_platforms": ["instagram","tiktok","youtube","xiaohongshu","douyin","threads"],
            "failed_platforms": ["x"],
            "raw_result_count": 3,
            "independent_result_count": 2,
            "missing": ["x: public search unavailable"]
          },
          "storage": {
            "persistence": "owner_private_backend",
            "fetched_at": "2026-07-24T08:00:00.000Z",
            "stale_after": "2026-07-31T08:00:00.000Z",
            "is_stale": true,
            "query_set": ["q1", "q2", "q3", "q4", "q5", "q6", "q7"]
          }
        }
        """.data(using: .utf8)!

        let pack = try JSONDecoder.supabase.decode(RelatedPlaceSourcePack.self, from: data)

        XCTAssertEqual(pack.place.id, placeID)
        XCTAssertEqual(pack.sources.count, 2)
        XCTAssertEqual(pack.sources[0].relation, .samePlace)
        XCTAssertEqual(pack.sources[1].relation, .mentionsPlace)
        XCTAssertNil(pack.sources[1].snippet)
        XCTAssertEqual(Set(pack.coverage.map(\.platform)), Set(RelatedSourcePlatform.allCases))
        XCTAssertEqual(pack.coverage.first { $0.platform == .tiktok }?.status, .partial)
        XCTAssertEqual(pack.coverage.first { $0.platform == .x }?.status, .failed)
        XCTAssertEqual(pack.receipt.failedPlatforms, [.x])
        XCTAssertEqual(pack.receipt.rawResultCount, pack.coverage.reduce(0) { $0 + $1.inspectedCount })
        XCTAssertEqual(pack.receipt.independentResultCount, 2)
        XCTAssertEqual(pack.storage?.persistence, "owner_private_backend")
        XCTAssertEqual(pack.storage?.isStale, true)
        XCTAssertEqual(pack.storage?.querySet.count, 7)
    }

    func testRejectsNonAllowlistedOrInsecureSourceURL() throws {
        let crossPlatform = sourceJSON(
            platform: "instagram",
            url: "https://example.com/not-instagram",
            confidence: 0.8
        )
        let insecure = sourceJSON(
            platform: "youtube",
            url: "http://youtube.com/watch?v=example",
            confidence: 0.8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(RelatedPlaceSource.self, from: crossPlatform))
        XCTAssertThrowsError(try JSONDecoder().decode(RelatedPlaceSource.self, from: insecure))
    }

    func testRejectsOutOfRangeConfidence() throws {
        let data = sourceJSON(
            platform: "threads",
            url: "https://threads.net/@example/post/123",
            confidence: 1.01
        )

        XCTAssertThrowsError(try JSONDecoder().decode(RelatedPlaceSource.self, from: data))
    }

    func testRequestBodyContainsOnlyBoundedContractFieldsAndDedupesPlatforms() throws {
        let data = try SupabaseService.relatedPlaceSourcesRequestBody(
            platforms: [.instagram, .youtube, .instagram],
            maxResultsPerPlatform: 3,
            forceRefresh: true
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), Set(["platforms", "max_results_per_platform", "force_refresh"]))
        XCTAssertEqual(object["platforms"] as? [String], ["instagram", "youtube"])
        XCTAssertEqual(object["max_results_per_platform"] as? Int, 3)
        XCTAssertEqual(object["force_refresh"] as? Bool, true)
        XCTAssertNil(object["aliases"])
        XCTAssertNil(object["name"])
        XCTAssertNil(object["address"])
    }

    func testRequestBodyRejectsEmptyPlatformsAndOutOfRangeLimit() {
        XCTAssertThrowsError(
            try SupabaseService.relatedPlaceSourcesRequestBody(
                platforms: [],
                maxResultsPerPlatform: 3
            )
        ) { error in
            XCTAssertEqual(error as? RelatedPlaceSourcesClientError, .invalidPlatforms)
        }

        for invalidLimit in [0, 6] {
            XCTAssertThrowsError(
                try SupabaseService.relatedPlaceSourcesRequestBody(
                    platforms: [.instagram],
                    maxResultsPerPlatform: invalidLimit
                )
            ) { error in
                XCTAssertEqual(error as? RelatedPlaceSourcesClientError, .invalidMaxResults)
            }
        }
    }

    func testErrorsMapToBoundedPresentationWithoutRawBody() {
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(SupabaseError.notAuthenticated),
            .signInRequired
        )
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(SupabaseError.apiError(409, #"{"error":"private detail"}"#)),
            .googleConfirmationRequired
        )
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(SupabaseError.apiError(429, #"{"error":"quota"}"#)),
            .rateLimited
        )
        XCTAssertEqual(
            RelatedPlaceSourcesDisplayError.classify(SupabaseError.apiError(503, #"{"error":"provider secret"}"#)),
            .temporarilyUnavailable
        )

        let rendered = RelatedPlaceSourcesDisplayError
            .classify(SupabaseError.apiError(503, #"{"error":"provider secret"}"#))
            .message(language: .english)
        XCTAssertFalse(rendered.contains("provider secret"))
        XCTAssertFalse(rendered.contains("{"))
    }

    private func sourceJSON(
        platform: String,
        url: String,
        confidence: Double
    ) -> Data {
        """
        {
          "platform": "\(platform)",
          "url": "\(url)",
          "title": "Example",
          "snippet": null,
          "query": "example query",
          "relation": "mentions_place",
          "identity_status": "candidate",
          "match_confidence": \(confidence)
        }
        """.data(using: .utf8)!
    }
}
