import XCTest
import CoreLocation
import ZIPFoundation
@testable import Wanderly

private final class StubPublicSourceSearchService: PublicSourceSearchServiceProtocol {
    var queries: [String] = []

    func search(query: String) async throws -> [PublicSourceSearchResult] {
        queries.append(query)
        if query.contains("DW2ZpyADbZ6") || query.contains("favorite restaurants in LA") {
            return [
                PublicSourceSearchResult(
                    title: "Talia's favorite restaurants in LA - Instagram mirror",
                    url: "https://example.com/ig/DW2ZpyADbZ6",
                    snippet: "Talia says one of my absolutely favorite restaurants in LA is Quarter Sheets Pizza Club. Save this for a slow dinner night."
                )
            ]
        }
        return []
    }
}

private final class StubGooglePlacesService: GooglePlacesServiceProtocol {
    var queries: [String] = []

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        queries.append(query)
        if query.contains("Quarter Sheets Pizza Club") {
            return [
                GooglePlaceMatch(
                    id: "quarter-sheets-pizza-club",
                    name: "Quarter Sheets Pizza Club",
                    address: "1305 Portia St, Los Angeles, CA 90026",
                    latitude: 34.0779,
                    longitude: -118.2543,
                    rating: 4.6,
                    priceLevel: 2
                )
            ]
        }
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

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        nil
    }
}

final class SocialPlacePipelineTests: XCTestCase {
    func testGoogleMapsSavedListExtractsEmbeddedPlaceLinks() {
        let html = """
        <a href=\"https://www.google.com/maps/place/Quarter+Sheets+Pizza+Club/@34.0779,-118.2543,17z\">Quarter Sheets Pizza Club</a>
        <a href=\"/maps/place/Courage+Bagels/@34.105,-118.287,17z\">Courage Bagels</a>
        """

        let candidates = GoogleMapsListPlaceExtractor.extractCandidates(
            sourceURL: "https://www.google.com/maps/placelists/list/CA-Foodie",
            title: "CA Foodie · Jerry Chen",
            text: nil,
            metadataTitle: "CA Foodie · Jerry Chen - Google Maps",
            metadataDescription: nil,
            htmlText: html
        )

        XCTAssertEqual(candidates.map(\.name), ["Quarter Sheets Pizza Club", "Courage Bagels"])
        XCTAssertEqual(candidates.first?.latitude, 34.0779)
        XCTAssertEqual(candidates.first?.longitude, -118.2543)
        XCTAssertFalse(candidates.contains { $0.name == "CA Foodie · Jerry Chen" })
        XCTAssertTrue(GoogleMapsListPlaceExtractor.looksLikeGoogleMapsList(
            sourceURL: "https://www.google.com/maps/placelists/list/CA-Foodie",
            title: "CA Foodie · Jerry Chen",
            text: nil,
            metadataTitle: "CA Foodie · Jerry Chen - Google Maps",
            metadataDescription: nil
        ))
    }

    func testGoogleTakeoutImportParsesBulkFileFormatsSeparatelyFromSavedListLinks() async throws {
        let json = """
        [
          {
            "name": "Known Cafe",
            "address": "123 Known Street",
            "latitude": 24.2,
            "longitude": 120.7,
            "url": "https://www.google.com/maps/place/Known+Cafe"
          },
          {
            "name": "Review Tea House",
            "address": "No coordinates in export"
          }
        ]
        """
        let geojson = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {
                "name": "Geo Noodles",
                "address": "1 Geo Road",
                "url": "https://www.google.com/maps/place/Geo+Noodles"
              },
              "geometry": {
                "type": "Point",
                "coordinates": [-118.2543, 34.0779]
              }
            }
          ]
        }
        """
        let kml = """
        <kml><Document><Placemark>
          <name>KML Bakery</name>
          <description>1 KML Street https://www.google.com/maps/place/KML+Bakery</description>
          <Point><coordinates>-118.3,34.1,0</coordinates></Point>
        </Placemark></Document></kml>
        """

        let jsonResult = try await parseTakeoutFixture(json, fileExtension: "json")
        let geojsonResult = try await parseTakeoutFixture(geojson, fileExtension: "geojson")
        let kmlResult = try await parseTakeoutFixture(kml, fileExtension: "kml")
        let zipResult = try await parseTakeoutZipFixture(entryName: "Takeout/Maps/Saved Places.json", contents: json)

        XCTAssertEqual(jsonResult.readyDrafts.map(\.name), ["Known Cafe"])
        XCTAssertEqual(jsonResult.reviewDrafts.map(\.name), ["Review Tea House"])
        XCTAssertEqual(geojsonResult.readyDrafts.map(\.name), ["Geo Noodles"])
        XCTAssertEqual(kmlResult.readyDrafts.map(\.name), ["KML Bakery"])
        XCTAssertEqual(zipResult.readyDrafts.map(\.name), ["Known Cafe"])
        XCTAssertFalse(GoogleMapsListPlaceExtractor.looksLikeGoogleMapsList(
            sourceURL: "file:///Takeout/Maps/Saved Places.json",
            title: "Google Takeout export",
            text: json,
            metadataTitle: nil,
            metadataDescription: nil
        ))
    }

    private func parseTakeoutFixture(_ contents: String, fileExtension: String) async throws -> GoogleTakeoutImportResult {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        let data = try XCTUnwrap(contents.data(using: .utf8))
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await GoogleTakeoutImportService().parse(fileAt: url)
    }

    private func parseTakeoutZipFixture(entryName: String, contents: String) async throws -> GoogleTakeoutImportResult {
        let data = try XCTUnwrap(contents.data(using: .utf8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        defer { try? FileManager.default.removeItem(at: url) }

        guard let archive = Archive(url: url, accessMode: .create) else {
            XCTFail("Could not create ZIP archive")
            throw GoogleTakeoutImportError.unreadableFile
        }

        try archive.addEntry(with: entryName, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }

        return try await GoogleTakeoutImportService().parse(fileAt: url)
    }

    private var douyinFoodListFixture: String {
        """
        叫我Wendii 的图文作品：🇺🇸LA必吃美食！都是我的宝藏店！
        P2-P5 Brothers and cousins Taco
        P6-P7 Artisanal Goods 可颂很好吃
        P8-P9 Ruen Pair 泰国菜 在 Thai town
        P10-P11 小食代川菜
        P12-P13 马来西亚菜，Ipoh Kopitiam 怡保茶餐厅
        P14-P15 Läderach 巧克力 推荐草莓味
        P16 Potato Corner 已经开到上海咯
        #美国生活 #加州美食 #洛杉矶 #洛杉矶美食 #留学生
        https://v.douyin.com/buUywZoMiLw/
        """
    }

    func testPlaceBearingSourceRunsPublicSearchAndPlacesMatchWithEvidenceReceipt() async throws {
        let places = StubGooglePlacesService()
        let search = StubPublicSourceSearchService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: places,
            publicSourceSearchService: search
        )

        let candidates = try await service.recoverReviewCandidates(
            fromEvidenceText: """
            Talia on Instagram: "This is one of my absolutely favorite restaurants in LA.
            Save this for a slow dinner night."
            """,
            sourceURL: "https://www.instagram.com/reel/DW2ZpyADbZ6/"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.candidateName, "Quarter Sheets Pizza Club")
        XCTAssertEqual(candidate.address, "1305 Portia St, Los Angeles, CA 90026")
        XCTAssertEqual(candidate.latitude, 34.0779)
        XCTAssertEqual(candidate.longitude, -118.2543)
        XCTAssertEqual(candidate.reviewState, "map_match_ready")
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertTrue(search.queries.contains { $0.contains("DW2ZpyADbZ6") })
        XCTAssertTrue(places.queries.contains { $0.contains("Quarter Sheets Pizza Club") && $0.contains("LA") })
        XCTAssertTrue(candidate.evidence.contains { $0.contains("Public web search result") && $0.contains("Quarter Sheets Pizza Club") })
        XCTAssertTrue(candidate.evidenceDiagnostic?.canSaveAsMapStamp == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains { $0.contains("Recovered venue candidate: Quarter Sheets Pizza Club") } == true)
    }

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

    func testInstagramPinnedVenueLineWithZipAddressBeatsOCRText() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            Teresa | LA & OC Lifestyle • Travel Creator on Instagram: "Mediterranean escape in Los Angeles that feels like a mini trip to Greece 🇬🇷
            Now serving weekend brunch for the summer, it’s the perfect daytime spot to slow down and enjoy the vibe.
            From fresh oysters and warm pita to Greek salad, seared octopus, lamb chops, and lobster orzo, everything is packed with flavor.

            📍 Alisa Wine & Friends @alisa_wine_friends
            1009 Abbot Kinney Blvd, Venice, CA 90291

            #losangeles #thingstodoinla #abbotkinney #restaurant #wheretoeat"
            """,
            sourceURL: "https://www.instagram.com/reel/DYmsoN0hxdv/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "Alisa Wine & Friends")
        XCTAssertEqual(candidates.first?.address, "1009 Abbot Kinney Blvd, Venice, CA 90291")
        XCTAssertFalse(candidates.contains { $0.candidateName == "to slow down and enjoy the vibe" })
        XCTAssertFalse(candidates.contains { $0.candidateName == "MEDITERRANEAN" })
    }

    func testInstagramLocatedHandleBeatsGenericOCRTitle() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DXI_znYBvKV/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: nil,
                metadataTitle: """
                Samantha Jacksich | San Diego Foodie on Instagram: "The most iconic dinner spot by the beach in San Diego✨

                @themarineroom is located in La Jolla and known for their stunning ocean views and waves crashing into the windows.

                Located at 📍 1950 Spindrift Dr if you want to check it out 🤩
                """,
                metadataDescription: nil,
                ocrLines: ["LA JOLLA'S MOST ICONIC RESTAURANT"]
            )
        )

        XCTAssertEqual(analysis.placesFound.first?.displayName, "The Marine Room")
        XCTAssertEqual(analysis.placesFound.first?.locationClues.first, "1950 Spindrift Dr")
        XCTAssertTrue(analysis.placesFound.first?.venueHandles.contains("themarineroom") == true)
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "LA JOLLA'S MOST ICONIC RESTAURANT" })
        XCTAssertFalse(analysis.placesFound.first?.evidenceChips.contains { $0.contains("@https://") } == true)
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

    func testInstagramCoffeeShopListTreatsHandlesAsPlaceCluesNotCaptionLabels() {
        let service = SocialLinkReviewCandidateService()
        let evidenceText = """
        Teresa | LA & OC Lifestyle • Travel Creator on Instagram: "The coffee shops in Los Angeles County I always end up returning to ☕️

        @theboyandthebearco @stereoscopecoffee @musocoffeela
        → best for coffee quality

        @elorea @archives.ofus
        → unique coffee experiences

        @fasttimescoffee @est.today.cafe
        → atmosphere & aesthetic

        @moducafe
        → desserts worth it

        Which one would you go to first?

        #losangeles #hiddengem #coffeeshop #coffeeislife #lacoffee".
        """

        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: evidenceText,
            sourceURL: "https://www.instagram.com/reel/DYsbskQyclc/"
        )

        let names = candidates.map(\.candidateName)
        XCTAssertTrue(names.contains("Fasttimescoffee"))
        XCTAssertTrue(names.contains("Theboyandthebearco"))
        XCTAssertTrue(names.contains("Stereoscopecoffee"))
        XCTAssertTrue(names.contains("Musocoffee La"))
        XCTAssertTrue(names.contains("Elorea"))
        XCTAssertTrue(names.contains("Archives Ofus"))
        XCTAssertTrue(names.contains("Est Today Cafe"))
        XCTAssertTrue(names.contains("Moducafe"))
        XCTAssertFalse(names.contains("unique coffee experiences"))
        XCTAssertFalse(names.contains("MY FAVORITE"))
        XCTAssertFalse(names.contains("Teresa"))
        XCTAssertTrue(candidates.allSatisfy { $0.latitude == nil && $0.longitude == nil })
        XCTAssertTrue(candidates.first { $0.candidateName == "Fasttimescoffee" }?.evidence.joined(separator: " ").contains("Venue handle: @fasttimescoffee") == true)
    }

    func testInstagramCoffeeShopListProducesSourceLevelUnderstanding() {
        let evidenceText = """
        Teresa | LA & OC Lifestyle • Travel Creator on Instagram: "The coffee shops in Los Angeles County I always end up returning to ☕️

        @theboyandthebearco @stereoscopecoffee @musocoffeela
        → best for coffee quality

        @elorea @archives.ofus
        → unique coffee experiences

        @fasttimescoffee @est.today.cafe
        → atmosphere & aesthetic

        @moducafe
        → desserts worth it

        Which one would you go to first?

        #losangeles #hiddengem #coffeeshop #coffeeislife #lacoffee".
        """

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DYsbskQyclc/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: evidenceText,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.sourceType, .multiPlaceList)
        XCTAssertEqual(analysis.sourceIntent, .multiPlaceList)
        XCTAssertTrue(analysis.isPlaceBearing)
        XCTAssertEqual(analysis.topic, "coffee shops in Los Angeles County")
        XCTAssertTrue(analysis.sourceSummary.contains("multi-place list"))
        XCTAssertTrue(analysis.regionClues.contains("Los Angeles County"))
        XCTAssertEqual(analysis.groups.map(\.label), [
            "best for coffee quality",
            "unique coffee experiences",
            "atmosphere & aesthetic",
            "desserts worth it"
        ])
        XCTAssertEqual(analysis.groups[0].venueHandles, ["theboyandthebearco", "stereoscopecoffee", "musocoffeela"])
        XCTAssertEqual(analysis.groups[1].venueHandles, ["elorea", "archives.ofus"])
        XCTAssertEqual(analysis.groups[2].venueHandles, ["fasttimescoffee", "est.today.cafe"])
        XCTAssertEqual(analysis.groups[3].venueHandles, ["moducafe"])
        XCTAssertEqual(analysis.placesFound.count, 8)
        XCTAssertTrue(analysis.placesFound.allSatisfy { $0.locationClues.isEmpty })
        XCTAssertTrue(analysis.placesFound.first { $0.displayName == "Fasttimescoffee" }?.evidenceChips.contains("Category clue: Source group: atmosphere & aesthetic") == true)
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "unique coffee experiences" })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "MY FAVORITE" })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "Teresa" })
        XCTAssertTrue(analysis.nextBestAction.contains("enrich selected venue clues"))
    }

    func testDouyinFoodListProducesMultiPlaceSourceUnderstanding() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://v.douyin.com/buUywZoMiLw/",
                resolvedURL: "https://www.iesdouyin.com/share/video/buUywZoMiLw/",
                sharedTitle: nil,
                sharedText: douyinFoodListFixture,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        let names = analysis.placesFound.map(\.displayName)
        XCTAssertEqual(analysis.sourceType, .multiPlaceList)
        XCTAssertEqual(analysis.sourceIntent, .multiPlaceList)
        XCTAssertTrue(analysis.isPlaceBearing)
        XCTAssertTrue(names.contains("Brothers and Cousins Tacos"))
        XCTAssertTrue(names.contains("Artisanal Goods"))
        XCTAssertTrue(names.contains("Ruen Pair"))
        XCTAssertTrue(names.contains("小食代川菜"))
        XCTAssertTrue(names.contains("Ipoh Kopitiam 怡保茶餐厅"))
        XCTAssertTrue(names.contains("Läderach"))
        XCTAssertTrue(names.contains("Potato Corner"))
        XCTAssertTrue(analysis.regionClues.contains("LA"))
        XCTAssertTrue(analysis.regionClues.contains("洛杉矶"))
        XCTAssertTrue(analysis.regionClues.contains { $0.localizedCaseInsensitiveContains("Thai Town") })
    }

    func testDouyinFoodListCreatesReviewCandidatesWithoutFakeCoordinates() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: douyinFoodListFixture,
            sourceURL: "https://v.douyin.com/buUywZoMiLw/"
        )

        let names = candidates.map(\.candidateName)
        XCTAssertGreaterThan(candidates.count, 1)
        XCTAssertFalse(candidates.contains { $0.isSourceOnly })
        XCTAssertTrue(names.contains("Brothers and Cousins Tacos"))
        XCTAssertTrue(names.contains("Artisanal Goods"))
        XCTAssertTrue(names.contains("Ruen Pair"))
        XCTAssertTrue(names.contains("小食代川菜"))
        XCTAssertTrue(names.contains("Ipoh Kopitiam 怡保茶餐厅"))
        XCTAssertTrue(names.contains("Läderach"))
        XCTAssertTrue(names.contains("Potato Corner"))
        XCTAssertTrue(candidates.allSatisfy { $0.latitude == nil && $0.longitude == nil })
        XCTAssertTrue(candidates.allSatisfy { $0.address.isEmpty })
        XCTAssertTrue(candidates.allSatisfy { !$0.hasReliableCoordinates })
        XCTAssertFalse(names.contains("可颂很好吃"))
        XCTAssertFalse(names.contains("巧克力 推荐草莓味"))
        XCTAssertFalse(names.contains("已经开到上海咯"))
    }

    func testInstagramCarouselWithPMarkersDoesNotTriggerDouyinListParser() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/not-douyin/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                MY FAVORITE LA food carousel
                P1 best for coffee quality
                P2 atmosphere and aesthetic
                P3 desserts worth it
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        let names = analysis.placesFound.map(\.displayName)
        XCTAssertFalse(names.contains("best for coffee quality"))
        XCTAssertFalse(names.contains("atmosphere and aesthetic"))
        XCTAssertFalse(names.contains("desserts worth it"))
        XCTAssertFalse(names.contains("MY FAVORITE LA food carousel"))
    }

    func testDouyinCuisinePrefixKeepsFollowingVenueName() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.iesdouyin.com/share/note/example/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                抖音图文：LA food list
                P2 泰国菜 Palms Thai 在 Thai Town
                P3 可颂很好吃
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        let names = analysis.placesFound.map(\.displayName)
        XCTAssertTrue(names.contains("Palms Thai"))
        XCTAssertFalse(names.contains("泰国菜"))
        XCTAssertFalse(names.contains("可颂很好吃"))
    }

    func testRestaurantRecommendationWithoutVenueBecomesPlaceBearingIntent() {
        let evidenceText = """
        Talia on Instagram: "This is one of my absolutely favorite restaurants in LA.
        Save this for a slow dinner night."
        """

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DW2ZpyADbZ6/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: evidenceText,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.sourceType, .sourceOnly)
        XCTAssertEqual(analysis.sourceIntent, .restaurantRecommendation)
        XCTAssertTrue(analysis.isPlaceBearing)
        XCTAssertTrue(analysis.placesFound.isEmpty)
        XCTAssertEqual(analysis.topic, "restaurants in LA")
        XCTAssertTrue(analysis.regionClues.contains("LA"))
        XCTAssertEqual(analysis.understanding.sourceType, .singlePlaceRecommendation)
        XCTAssertTrue(analysis.recoveryStrategies.contains(.publicSearchRecovery))
        XCTAssertFalse(analysis.recoveryStrategies.contains(.directParse))
        XCTAssertEqual(analysis.resolverDecision.kind, .pendingCandidate)
        XCTAssertTrue(analysis.resolverDecision.shouldRunPublicSearch)
        XCTAssertFalse(analysis.resolverDecision.allowsDirectSave)
        XCTAssertTrue(analysis.resolverDecision.requiredEvidence.contains("Public corroboration"))
        XCTAssertTrue(analysis.nextBestAction.contains("source recovery search"))
    }

    func testMultiHandleListUnderstandingUsesListModeAndHandleResolver() {
        let evidenceText = """
        @theboyandthebearco @stereoscopecoffee @musocoffeela
        → best for coffee quality

        @elorea @archives.ofus
        → unique coffee experiences
        """

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DYsbskQyclc/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: evidenceText,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.understanding.sourceType, .multiPlaceList)
        XCTAssertTrue(analysis.recoveryStrategies.contains(.listMode))
        XCTAssertTrue(analysis.recoveryStrategies.contains(.handleResolver))
        XCTAssertTrue(analysis.recoveryStrategies.contains(.publicSearchRecovery))
        XCTAssertEqual(analysis.resolverDecision.kind, .multiPlaceList)
        XCTAssertTrue(analysis.resolverDecision.shouldRunPublicSearch)
        XCTAssertFalse(analysis.resolverDecision.allowsDirectSave)
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "best for coffee quality" })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "unique coffee experiences" })
    }

    func testVagueLifestyleCaptionAsksForEvidenceAndSourceReceipt() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/vague/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: "slow down and enjoy the vibe",
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.understanding.sourceType, .vagueLifestyleCaption)
        XCTAssertTrue(analysis.recoveryStrategies.contains(.askForMoreEvidence))
        XCTAssertEqual(analysis.understanding.evidenceTier, .sourceOnly)
        XCTAssertEqual(analysis.resolverDecision.kind, .reject)
        XCTAssertFalse(analysis.resolverDecision.shouldRunPublicSearch)
        XCTAssertTrue(analysis.placesFound.isEmpty)
    }

    func testMapShareUnderstandingRoutesToMapResolution() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://maps.app.goo.gl/abc123",
                resolvedURL: nil,
                sharedTitle: "Google Maps",
                sharedText: nil,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.understanding.sourceType, .mapShare)
        XCTAssertEqual(analysis.primaryRecoveryStrategy, .mapLinkResolution)
        XCTAssertEqual(analysis.resolverDecision.kind, .pendingCandidate)
        XCTAssertFalse(analysis.resolverDecision.allowsDirectSave)
        XCTAssertTrue(analysis.resolverDecision.requiredEvidence.contains("Structured map resolution"))
        XCTAssertFalse(analysis.recoveryStrategies.contains(.publicSearchRecovery))
    }

    func testBookingLinkUnderstandingRoutesToBookingResolution() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.opentable.com/r/example-restaurant",
                resolvedURL: nil,
                sharedTitle: "Reserve Example Restaurant",
                sharedText: "Book a table for dinner",
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.understanding.sourceType, .bookingOrReservation)
        XCTAssertTrue(analysis.recoveryStrategies.contains(.bookingLinkResolution))
        XCTAssertEqual(analysis.resolverDecision.kind, .pendingCandidate)
        XCTAssertTrue(analysis.resolverDecision.requiredEvidence.contains("Map/place match"))
        XCTAssertTrue(analysis.recoveryStrategies.contains(.publicSearchRecovery))
    }

    func testCreatorOnlyHandleDoesNotBecomePlaceBearingSource() {
        let evidenceText = "Please follow @travelcreator for daily hidden gems."

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/creator-only/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: evidenceText,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.sourceIntent, .creatorOnly)
        XCTAssertEqual(analysis.understanding.sourceType, .creatorSourceOnly)
        XCTAssertTrue(analysis.recoveryStrategies.contains(.sourceOnlyReceipt))
        XCTAssertFalse(analysis.recoveryStrategies.contains(.handleResolver))
        XCTAssertFalse(analysis.isPlaceBearing)
        XCTAssertEqual(analysis.resolverDecision.kind, .sourceOnly)
        XCTAssertFalse(analysis.resolverDecision.shouldRunPublicSearch)
        XCTAssertTrue(analysis.placesFound.isEmpty)
    }

    func testOCRRejectsGenericCoffeeListLabelsAndFavoriteHeader() {
        let candidates = SocialPlaceParser().parse(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DYsbskQyclc/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: nil,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: ["MY FAVORITE", "unique coffee experiences"]
            )
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testInstagramActivityVenueMarkerWithNextLineAddressCreatesReviewCandidate() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            Bitter Root Pottery on Instagram: "📍Bitter Root Pottery Baroque Location
            7461 Beverly Blvd (Penthouse) LA, CA 90036

            For bookings ➡️ www.bitterrootpottery.com"
            """,
            sourceURL: "https://www.instagram.com/reel/DXxN8ENyfIe/"
        )

        let candidate = candidates.first
        XCTAssertEqual(candidate?.candidateName, "Bitter Root Pottery Baroque Location")
        XCTAssertEqual(candidate?.address, "7461 Beverly Blvd (Penthouse) LA, CA 90036")
        XCTAssertEqual(candidate?.category, "attraction")
        XCTAssertEqual(candidate?.isSourceOnly, false)
        XCTAssertNil(candidate?.latitude)
        XCTAssertNil(candidate?.longitude)
        XCTAssertTrue(candidate?.evidence.joined(separator: " ").contains("Booking link: www.bitterrootpottery.com") == true)
        XCTAssertFalse(candidates.contains { $0.candidateName == "Bitter Root Pottery" })
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
        XCTAssertTrue(candidate.evidenceDiagnostic?.attempts.contains("Prepared public web search fallback queries for source-only recovery") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.missingFields.contains("Verified place name") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.suggestedSearchQueries?.first, "instagram reel DYsourceOnly place")
        XCTAssertTrue(candidate.evidence.contains("Suggested public search: instagram reel DYsourceOnly place"))
        XCTAssertEqual(candidate.evidenceDiagnostic?.nextBestClue, "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.")
        XCTAssertTrue(candidate.missingInfo.contains("Verified place name"))
    }

    func testPlausiblePlaceNameInSearchQueryBecomesUnresolvedCandidate() {
        let service = SocialLinkReviewCandidateService()
        let sourceURL = "https://www.instagram.com/reel/DYtokyoPasta/"

        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "東京家庭義大利麵 士林店 台北 Taipei 士林站",
            sourceURL: sourceURL
        )

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertEqual(candidate.reviewState, "unresolved_place_candidate")
        XCTAssertEqual(candidate.candidateName, "東京家庭義大利麵 士林店")
        XCTAssertEqual(candidate.address, "")
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
        XCTAssertTrue(candidate.missingInfo.contains("Verified address"))
        XCTAssertTrue(candidate.missingInfo.contains("Verified coordinates"))
        XCTAssertFalse(candidate.missingInfo.contains("Verified place name"))
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Candidate place name: 東京家庭義大利麵 士林店") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.statusLabel, "Needs confirmation")
    }

    func testPlaceBearingInstagramMetadataCreatesWeakReviewCandidateInsteadOfSourceOnly() {
        let service = SocialLinkReviewCandidateService()
        let sourceURL = "https://www.instagram.com/reel/DW2ZpyADbZ6/?igsh=tracking"
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            Talia on Instagram: "This is one of my absolutely favorite restaurants in LA.
            Save this for a slow dinner night."
            """,
            sourceURL: sourceURL
        )

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertEqual(candidate.reviewState, "place_bearing_source")
        XCTAssertEqual(candidate.candidateName, "LA restaurant recommendation clue")
        XCTAssertEqual(candidate.category, "food")
        XCTAssertEqual(candidate.confidence, 0.35)
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
        XCTAssertTrue(candidate.missingInfo.contains("Exact restaurant name"))
        XCTAssertTrue(candidate.missingInfo.contains("Verified address"))
        XCTAssertTrue(candidate.missingInfo.contains("Verified coordinates"))
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains(where: { $0.contains("Place-bearing source") }) == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Source intent: restaurantRecommendation") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.statusLabel, "Place clue")
        XCTAssertEqual(candidate.evidenceDiagnostic?.primaryActionLabel, "Run recovery search")
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Resolver decision: pendingCandidate") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.suggestedSearchQueries?.first, "\"DW2ZpyADbZ6\" restaurant LA")
        XCTAssertFalse(candidate.evidenceDiagnostic?.suggestedSearchQueries?.joined(separator: " ").contains("igsh") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.nextBestClue.contains("source recovery search") == true)
    }

    func testURLOnlyInstagramReelSearchPlanRemovesTrackingQuery() {
        let service = SocialLinkReviewCandidateService()
        let sourceURL = "https://www.instagram.com/reel/DWmzyodgbuv/?igsh=tracking"

        let candidate = service.reviewCandidatesOrSourceOnly(fromEvidenceText: "", sourceURL: sourceURL)[0]

        XCTAssertEqual(candidate.evidenceDiagnostic?.suggestedSearchQueries, [
            "instagram reel DWmzyodgbuv place",
            "DWmzyodgbuv restaurant venue",
            "\"https://www.instagram.com/reel/DWmzyodgbuv/\""
        ])
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

    func testEvidenceDiagnosticDecodesOldRecordsWithoutSearchQueries() throws {
        let json = """
        {
          "found": ["Source URL: https://www.instagram.com/reel/old/"],
          "attempts": ["Checked public metadata/caption text for explicit place names"],
          "missingFields": ["Verified place name"],
          "nextBestClue": "Share a caption"
        }
        """.data(using: .utf8)!

        let diagnostic = try JSONDecoder().decode(SocialPlaceEvidenceDiagnostic.self, from: json)

        XCTAssertNil(diagnostic.suggestedSearchQueries)
        XCTAssertEqual(diagnostic.found.first, "Source URL: https://www.instagram.com/reel/old/")
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
        XCTAssertEqual(record.evidenceDiagnostic?.suggestedSearchQueries?.first, "instagram reel DYfallback place")
        XCTAssertEqual(record.evidenceDiagnostic?.nextBestClue, "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.")
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
