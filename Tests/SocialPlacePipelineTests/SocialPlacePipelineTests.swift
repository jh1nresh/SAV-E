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
    func testInstagramReelPublicMetadataExtractsVenueInsteadOfSourceOnly() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            Paseo at Downtown Disney District on Instagram: "Dinner spot at Downtown Disney.
            📍 Downtown Disney District, CA"
            """,
            sourceURL: "https://www.instagram.com/reel/DWkTzpIibh0/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "Paseo at Downtown Disney District")
        XCTAssertFalse(candidates.first?.isSourceOnly == true)
        XCTAssertTrue(candidates.first?.missingInfo.contains("Instagram metadata title; verify exact venue and address") == true)
    }

    func testInstagramRestaurantCaptionUsesNamedVenueBeforeAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            瑞塔 Rita wu on Instagram: "台中·餐廳
            「吃得懂」
            元紀·台灣菜
            🏠臺中市西屯區安和東路5號
            """,
            sourceURL: "https://www.instagram.com/reel/DYoDyPWvDkr/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "元紀·台灣菜")
        XCTAssertEqual(candidates.first?.address, "🏠臺中市西屯區安和東路5號")
        XCTAssertFalse(candidates.contains { $0.candidateName == "吃得懂" })
        XCTAssertFalse(candidates.contains { $0.candidateName == "台中·餐廳" })
    }

    func testInstagramPinVenueLineUsesNextLineHighwayAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            Lorna: OC Insider 在 Instagram: "📍 The Porch at The Ranch at Laguna Beach @theranchlb
            31106 Coast Hwy, Laguna Beach
            Tucked inside Aliso Canyon, this open-air patio has live music on weekends, fire tables, and a full menu with wine, cocktails, and coffee. Valet is complimentary.

            Follow @thescenesouthoc for more hidden gems like this!
            #lagunabeach #orangecounty #happyhour"
            """,
            sourceURL: "https://www.instagram.com/reel/DWmzyodgbuv/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "The Porch at The Ranch at Laguna Beach")
        XCTAssertEqual(candidates.first?.address, "31106 Coast Hwy, Laguna Beach")
        XCTAssertFalse(candidates.contains { $0.candidateName == "Lorna" })
        XCTAssertFalse(candidates.contains { $0.candidateName == "OC Insider" })
    }

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

    func testInstagramReelCaptionVenueMarkerBeatsSourceAccountProfile() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            城市記憶 LESTER | TANG, CHIH-CHUN (@citiesmemory) • Instagram reel
            citiesmemory on May 21, 2026: "跑了好幾次才終於吃到了這間法式吐司！
            -
            跑了幾次Jo & Dawson的延南洞店，不是號碼牌發完了就是當天賣完了，這次剛好發現了光化門附近的新分店，早早的跑過去，不用等太久終於可以順利吃到。
            -
            👉🏻Jo & Dawson 光化門店
            🍽️07:30-20:00
            📍首爾特別市 鐘路區 淸進洞 70
            -
            #韓國美食 #首爾美食 #法式吐司 #seoul #seoulfood".
            """,
            sourceURL: "https://www.instagram.com/reel/DYmFHrizV3E/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "Jo & Dawson 光化門店")
        XCTAssertEqual(candidates.first?.address, "首爾特別市 鐘路區 淸進洞 70")
        XCTAssertEqual(candidates.first?.category, "food")
        XCTAssertNotEqual(candidates.first?.candidateName, "TANG, CHIH-CHUN")
        XCTAssertFalse(candidates.contains { $0.evidence.joined(separator: " ").contains("Venue handle: @citiesmemory") })
    }

    func testInstagramReelCaptionWithKoreanAddressCreatesReviewCandidate() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            城市記憶 LESTER | TANG, CHIH-CHUN on Instagram: "吃了四五次以上的超強韓牛！！
            -
            之前朋友說想吃韓牛的時候，我們總是會約在明洞的一片里脊，想不到弘大也有分店而且店內氣氛還更好。
            -
            👉🏻一片里脊 弘大店
            📍首爾特別市 麻浦區 東橋洞 164-23
            🚇弘益大學入口地鐵站
            -
            #韓國美食 #首爾美食 #弘大美食 #韓牛".
            """,
            sourceURL: "https://www.instagram.com/reel/DYJuEzgTy79/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "一片里脊 弘大店")
        XCTAssertEqual(candidates.first?.address, "首爾特別市 麻浦區 東橋洞 164-23")
        XCTAssertEqual(candidates.first?.category, "food")
        XCTAssertNotEqual(candidates.first?.candidateName, "TANG, CHIH-CHUN")
    }

    func testVenueMarkerStripsStoreNamePrefixBeforeScoring() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            店名：Jo & Dawson 光化門店
            📍首爾特別市 鐘路區 淸進洞 70
            """,
            sourceURL: "https://www.instagram.com/reel/DYmFHrizV3E/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "Jo & Dawson 光化門店")
        XCTAssertFalse(candidates.first?.candidateName.contains("店名") == true)
    }

    func testSourceAccountCandidateRejectsInstagramSuffixLookalikeHost() {
        let candidates = SocialPlaceParser().parse(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://notinstagram.com/newcafe.tw/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                新咖啡實驗室 (@newcafe.tw) • Instagram photos and videos
                台北 coffee lab
                @newcafe.tw
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

    func testURLOnlyInstagramReelProducesSourceOnlyEvidenceDebugCandidate() {
        let service = SocialLinkReviewCandidateService()
        let sourceURL = "https://www.instagram.com/reel/DYsourceOnly/"

        let candidates = service.reviewCandidatesOrSourceOnly(fromEvidenceText: "", sourceURL: sourceURL)

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertTrue(candidate.isSourceOnly)
        XCTAssertEqual(candidate.candidateName, "Instagram reel")
        XCTAssertEqual(candidate.sourceURL, sourceURL)
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Source URL: \(sourceURL)") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.attempts.contains("Checked public metadata/caption text for explicit place names") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.attempts.contains("Did not use logged-in Instagram scraping") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.missingFields.contains("Verified place name") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.nextBestClue, "Share a caption, screenshot/OCR frame, map link, or visible venue handle for this Reel.")
        XCTAssertTrue(candidate.missingInfo.contains("Verified place name"))
    }

    func testCaptionVenueWithoutVerifiedAddressStaysReviewCandidateWithoutCoordinates() {
        let service = SocialLinkReviewCandidateService()

        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            New brunch spot: Garden Table Cafe
            Save this cozy patio for next weekend.
            """,
            sourceURL: "https://www.instagram.com/reel/venue-no-address/"
        )

        let candidate = candidates.first
        XCTAssertEqual(candidate?.candidateName, "Garden Table Cafe")
        XCTAssertEqual(candidate?.address, "")
        XCTAssertNil(candidate?.latitude)
        XCTAssertNil(candidate?.longitude)
        XCTAssertEqual(candidate?.isSourceOnly, false)
        XCTAssertTrue(candidate?.missingInfo.contains("Confirm address") == true)
        XCTAssertTrue(candidate?.missingInfo.contains("Confirm coordinates") == true)
        XCTAssertTrue(candidate?.evidenceDiagnostic?.found.contains("Candidate place name: Garden Table Cafe") == true)
        XCTAssertTrue(candidate?.evidenceDiagnostic?.missingFields.contains("Verified address") == true)
    }

    func testSaveMemoryRecordPreservesEvidenceDiagnosticForSourceOnlyClues() throws {
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: ["Source URL: https://www.instagram.com/reel/DYsourceOnly/"],
            attempts: ["Checked public metadata/caption text for explicit place names"],
            missingFields: ["Verified place name", "Verified address", "Verified coordinates"],
            nextBestClue: "Share a caption, screenshot/OCR frame, map link, or visible venue handle for this Reel."
        )
        let record = SaveMemoryRecord(
            state: .sourceOnly,
            sourceURL: "https://www.instagram.com/reel/DYsourceOnly/",
            title: "Instagram reel",
            evidence: diagnostic.found + diagnostic.attempts,
            evidenceDiagnostic: diagnostic
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SaveMemoryRecord.self, from: encoded)

        XCTAssertEqual(decoded.state, .sourceOnly)
        XCTAssertEqual(decoded.evidenceDiagnostic?.found.first, diagnostic.found.first)
        XCTAssertEqual(decoded.evidenceDiagnostic?.missingFields, diagnostic.missingFields)
        XCTAssertEqual(decoded.evidenceDiagnostic?.nextBestClue, diagnostic.nextBestClue)
    }

    func testSaveSourceOnlyCreatesEvidenceDiagnosticInsteadOfBareBookmark() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("save-memory-records.json")
        let service = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let record = try service.saveSourceOnly(
            url: URL(string: "https://www.instagram.com/reel/DYfallback/")!,
            note: "Creator post saved before parser evidence arrived"
        )

        XCTAssertEqual(record.state, .sourceOnly)
        XCTAssertEqual(record.title, "Instagram reel")
        XCTAssertTrue(record.evidenceDiagnostic?.found.contains("Source URL: https://www.instagram.com/reel/DYfallback/") == true)
        XCTAssertTrue(record.evidenceDiagnostic?.found.contains("Shared text/caption was present but did not contain a verified place candidate") == true)
        XCTAssertTrue(record.evidenceDiagnostic?.missingFields.contains("Verified place name") == true)
        XCTAssertEqual(record.evidenceDiagnostic?.nextBestClue, "Share a caption, screenshot/OCR frame, map link, or visible venue handle for this Reel.")
        XCTAssertEqual(record.evidenceDiagnostic?.statusLabel, "Source clue")
        XCTAssertEqual(record.evidenceDiagnostic?.primaryActionLabel, "Add caption / screenshot / map link")
        XCTAssertEqual(record.evidenceDiagnostic?.canSaveAsMapStamp, false)
    }

    func testEvidenceDiagnosticPromotesToMapMatchReadyAfterRefinement() async {
        let google = StubGooglePlacesService()
        let service = SocialLinkReviewCandidateService(googlePlacesService: google)
        let candidate = PendingReviewCandidate(
            candidateName: "Known Cafe",
            address: "",
            category: "cafe",
            sourceURL: "https://example.com/known-cafe",
            sourceText: "Known Cafe",
            evidence: ["Evidence tier: likely"],
            confidence: 0.6,
            missingInfo: [],
            savedAt: Date(),
            evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                found: ["Source URL: https://example.com/known-cafe", "Candidate place name: Known Cafe"],
                attempts: ["Checked public metadata/caption text for explicit place names"],
                missingFields: ["Verified coordinates"],
                nextBestClue: "Confirm coordinates or choose a Google Places match before saving this as a Map Stamp."
            )
        )

        let refined = await service.refineCandidate(candidate)

        XCTAssertEqual(refined.evidenceDiagnostic?.statusLabel, "Map match ready")
        XCTAssertEqual(refined.evidenceDiagnostic?.primaryActionLabel, "Confirm map match")
        XCTAssertEqual(refined.evidenceDiagnostic?.canSaveAsMapStamp, true)
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
            savedAt: Date(),
            evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                found: ["Source URL: https://example.com/known-cafe", "Candidate place name: Known Cafe"],
                attempts: ["Checked public metadata/caption text for explicit place names"],
                missingFields: ["Verified coordinates"],
                nextBestClue: "Confirm coordinates or choose a Google Places match before saving this as a Map Stamp."
            )
        )
        let refined = await service.refineCandidate(candidate)

        XCTAssertEqual(refined.candidateName, "Known Cafe")
        XCTAssertEqual(refined.address, "123 Known Street")
        XCTAssertEqual(refined.latitude, 24.2)
        XCTAssertEqual(refined.longitude, 120.7)
        XCTAssertTrue(refined.evidence.contains("Google Places refined match: Known Cafe"))
        XCTAssertTrue(refined.evidenceDiagnostic?.found.contains("Google Places match: Known Cafe") == true)
        XCTAssertTrue(refined.evidenceDiagnostic?.found.contains("Verified coordinates: 24.2, 120.7") == true)
        XCTAssertFalse(refined.evidenceDiagnostic?.missingFields.contains("Verified coordinates") == true)
        XCTAssertEqual(refined.evidenceDiagnostic?.nextBestClue, "Confirm this Google Places match before saving it as a Map Stamp.")
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
