import XCTest
import CoreLocation
@testable import Wanderly

private final class StubGooglePlacesService: GooglePlacesServiceProtocol {
    var queries: [String] = []

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        queries.append(query)
        if query.contains("Known Cafe") {
            return [
                GooglePlaceMatch(
                    id: "wrong-first",
                    name: "Wrong Tea House",
                    address: "999 Wrong Road",
                    latitude: 25.0,
                    longitude: 121.0,
                    rating: 4.8,
                    priceLevel: 2
                ),
                GooglePlaceMatch(
                    id: "known-cafe",
                    name: "Known Cafe",
                    address: "123 Known Street",
                    latitude: 24.2,
                    longitude: 120.7,
                    rating: 4.6,
                    priceLevel: 2
                )
            ]
        }
        if query.contains("新咖啡實驗室") {
            return [
                GooglePlaceMatch(
                    id: "new-cafe-lab",
                    name: "新咖啡實驗室",
                    address: "台北市大安區咖啡路1號",
                    latitude: 25.033,
                    longitude: 121.565,
                    rating: 4.7,
                    priceLevel: 2
                )
            ]
        }
        return []
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        throw GooglePlacesError.noResults
    }
}

final class SocialPlacePipelineTests: XCTestCase {
    func testAgentParserMergesNumberedPlaceEvidence() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/spyglass/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                1. The Spectacular Spyglass Treehouse (@artistree_treehouse)
                📍 Occidental, California

                2. The Sonoma Spyglass (@sonomaspyglass)
                📍 Sebastopol, California
                airbnb.com/h/sweet-sonoma-spyglass
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.placesFound.map(\.displayName), [
            "The Spectacular Spyglass Treehouse",
            "The Sonoma Spyglass"
        ])
        XCTAssertEqual(analysis.placesFound.first?.category, "stay")
        XCTAssertEqual(analysis.placesFound.first?.locationClues.first, "Occidental, California")
        XCTAssertTrue(analysis.placesFound.first?.venueHandles.contains("artistree_treehouse") == true)
        XCTAssertTrue(analysis.placesFound[1].venueHandles.contains("sonomaspyglass"))
        XCTAssertTrue(analysis.placesFound[1].bookingLinks.contains("airbnb.com/h/sweet-sonoma-spyglass"))
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName.contains("@") })
    }

    func testAgentParserRejectsCreatorHandleForJWMarriottStay() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/jw/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                Please follow @elisolanooo for more hidden gems.
                This is the JW Marriott Desert Springs in the Coachella Valley Area.
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.placesFound.count, 1)
        XCTAssertEqual(analysis.placesFound.first?.displayName, "JW Marriott Desert Springs")
        XCTAssertEqual(analysis.placesFound.first?.category, "stay")
        XCTAssertEqual(analysis.placesFound.first?.locationClues.first, "Coachella Valley Area")
        XCTAssertTrue(analysis.discardedCandidates.contains { $0.value == "Elisolanooo" && $0.reason.contains("creator handle") })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "Elisolanooo" })
        XCTAssertFalse(analysis.placesFound.first?.venueHandles.contains("elisolanooo") == true)
        XCTAssertTrue(analysis.placesFound.first?.missingInfo.contains("Confirm coordinates") == true)
    }

    func testCreatorOnlySocialLinkDoesNotBecomePlace() {
        let candidates = SocialPlaceParser().parse(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/creator-only/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                Please follow @travelcreator for daily hidden gems.
                Here are my favorite cozy stays this winter.
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testProfileResolverUsesMetadataDisplayNameBeforeRawHandle() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            新咖啡實驗室 (@newcafe.tw) • Instagram photos and videos
            台北 coffee lab
            @newcafe.tw
            """,
            sourceURL: "https://www.instagram.com/newcafe.tw/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "新咖啡實驗室")
        XCTAssertTrue(candidates.first?.evidence.joined(separator: " ").contains("Resolved public profile metadata") == true)
    }

    func testHandleOnlySocialCandidateStaysReviewOnlyWithoutFakeCoordinates() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            staying at @ulamanbali
            bamboo resort in Bali
            """,
            sourceURL: "https://www.instagram.com/reel/example/"
        )

        let candidate = candidates.first
        XCTAssertEqual(candidate?.candidateName, "Ulaman Bali")
        XCTAssertNil(candidate?.latitude)
        XCTAssertNil(candidate?.longitude)
        XCTAssertEqual(candidate?.hasReliableCoordinates, false)
        XCTAssertTrue(candidate?.missingInfo.contains("Confirm coordinates") == true)
        XCTAssertTrue(candidate?.evidence.joined(separator: " ").contains("Evidence tier: weakCandidate") == true)
    }

    func testPlacesRefineRanksAcceptableMatchInsteadOfFirstResult() async {
        let google = StubGooglePlacesService()
        let service = SocialLinkReviewCandidateService(googlePlacesService: google)
        let candidate = PendingReviewCandidate(
            candidateName: "Known Cafe",
            address: "123 Known Street",
            category: "cafe",
            latitude: nil,
            longitude: nil,
            sourceURL: "https://example.com/known-cafe",
            sourceText: "Known Cafe at 123 Known Street",
            evidence: ["Evidence tier: likely"],
            confidence: 0.6,
            missingInfo: [],
            savedAt: Date()
        )

        let refined = await service.refineCandidate(candidate)

        XCTAssertEqual(refined.candidateName, "Known Cafe")
        XCTAssertEqual(refined.address, "123 Known Street")
        XCTAssertEqual(refined.latitude, 24.2)
        XCTAssertEqual(refined.longitude, 120.7)
        XCTAssertTrue(refined.evidence.contains("Google Places refined match: Known Cafe"))
    }

    func testPlacesRefinementQueriesSkipCreatorHandles() async {
        let google = StubGooglePlacesService()
        let service = SocialLinkReviewCandidateService(googlePlacesService: google)
        let evidence = """
        Please follow @elisolanooo for more hidden gems.
        This is the JW Marriott Desert Springs in the Coachella Valley Area.
        """
        let candidate = PendingReviewCandidate(
            candidateName: "JW Marriott Desert Springs",
            address: "Coachella Valley Area",
            category: "stay",
            latitude: nil,
            longitude: nil,
            sourceURL: "https://www.instagram.com/reel/jw/",
            sourceText: evidence,
            evidence: ["Venue name: JW Marriott Desert Springs", "Creator handle: @elisolanooo"],
            confidence: 0.64,
            missingInfo: ["Confirm coordinates"],
            savedAt: Date()
        )

        _ = await service.refineCandidate(candidate, evidenceText: evidence)

        XCTAssertFalse(google.queries.contains { $0.localizedCaseInsensitiveContains("elisolanooo") })
        XCTAssertFalse(google.queries.contains { $0.localizedCaseInsensitiveContains("Eli Solanooo") })
        XCTAssertTrue(google.queries.contains { $0.localizedCaseInsensitiveContains("JW Marriott Desert Springs") })
    }

    func testOCRFramePairsBrandWithNearbyDescriptor() {
        let result = SocialOCRCandidateHeuristics.candidate(from: [
            "台南爆漿巴斯克",
            "TULA COFFEE",
            "Tula Basque",
            "不要說你吃過巴斯克蛋糕"
        ])

        XCTAssertEqual(result?.name, "TULA COFFEE")
        XCTAssertGreaterThanOrEqual(result?.confidence ?? 0, 0.5)
        XCTAssertTrue(result?.supportingLines.contains("Tula Basque") == true)
    }

    func testOCRFrameFindsCJKHotelVenueFromThumbnailText() {
        let fixtures = [
            (
                expectedName: "高雄洲際酒店",
                expectedSupportingLine: "高雄洲際酒店",
                lines: [
                    "高雄洲際酒店",
                    "早餐吃到下午 2:30",
                    "高空無邊際泳池",
                    "亞灣海景"
                ]
            ),
            (
                expectedName: "箱根ゲストハウス",
                expectedSupportingLine: "箱根ゲストハウス",
                lines: [
                    "箱根ゲストハウス",
                    "温泉まで徒歩5分",
                    "Hakone travel notes"
                ]
            ),
            (
                expectedName: "부산 호텔 라온",
                expectedSupportingLine: "부산 호텔 라온",
                lines: [
                    "부산 호텔 라온",
                    "해운대 근처",
                    "rooftop view"
                ]
            )
        ]

        for fixture in fixtures {
            let result = SocialOCRCandidateHeuristics.candidate(from: fixture.lines)

            XCTAssertEqual(result?.name, fixture.expectedName)
            XCTAssertGreaterThanOrEqual(result?.confidence ?? 0, 0.45)
            XCTAssertTrue(result?.supportingLines.contains(fixture.expectedSupportingLine) == true)
        }
    }

    func testSocialPipelineRegressionCasesStayStable() {
        let service = SocialLinkReviewCandidateService()

        let yakiniku = service.reviewCandidates(
            fromEvidenceText: """
            4foodie Victoria & Ava 還有她們的夥伴們 on Instagram: "📍Tokyo, Japan
            YAKINIKU 37west NY / 吟コース / ¥24000(税込)
            美味程度：🌕🌕🌕🌕🌗
            環境衛生：🌕🌕🌕🌕🌗
            服務態度：🌕🌕🌕🌕🌕
            再訪意願：🌕🌕🌕🌕🌗
            🗺東京都港区新橋2-11-10 HULIC & New Shinbashi 2F
            "
            """,
            sourceURL: "https://www.instagram.com/reel/DYKRzPixTGd/"
        )
        XCTAssertEqual(yakiniku.first?.candidateName, "YAKINIKU 37west NY")
        XCTAssertNotEqual(yakiniku.first?.candidateName, "再訪意願：🌕🌕🌕🌕🌗")

        let ushigoro = service.reviewCandidates(
            fromEvidenceText: """
            #GIRLSTALK美食
            來自東京的頂級燒肉名店「USHIGORO S.」 @ushigoro.s.tw 正式插旗台北‼️💥
            主打少見的「和牛燒肉割烹」形式。
            📍中山區樂群三路299號2樓
            📅 5/8正式開放inline訂位
            """,
            sourceURL: "https://www.instagram.com/reel/DYG2S_4n3_e/"
        )
        XCTAssertEqual(ushigoro.first?.candidateName, "USHIGORO S")
        XCTAssertNotEqual(
            ushigoro.first?.candidateName,
            "來自東京的頂級燒肉名店「USHIGORO S.」 @ushigoro.s.tw 正式插旗台北‼️💥"
        )
        XCTAssertEqual(ushigoro.first?.address, "中山區樂群三路299號2樓")
        XCTAssertEqual(ushigoro.first?.category, "food")

        let addressOnly = service.reviewCandidates(
            fromEvidenceText: """
            11:00-21:30
            營業時間：週一至週日
            🗺台北市大安區信義路三段1號
            """,
            sourceURL: "https://www.instagram.com/reel/address-only/"
        )
        XCTAssertTrue(addressOnly.isEmpty)
    }
}
