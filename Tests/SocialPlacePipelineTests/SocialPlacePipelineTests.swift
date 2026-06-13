import XCTest
import CoreLocation
import ZIPFoundation
@testable import SAVE

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
        if query.contains("DVqC21VkxPv") || query.contains("關西壽喜燒") {
            return [
                PublicSourceSearchResult(
                    title: "士林日本人老闆開業8年的關西壽喜燒 - Instagram mirror",
                    url: "https://example.com/ig/DVqC21VkxPv",
                    snippet: "俊²分享士林日本人老闆開業8年的關西壽喜燒。店名：牛喜壽喜燒，地址：台北市士林區忠誠路二段200號3樓。"
                )
            ]
        }
        if query.contains("賀鴨郎") || query.contains("houyacantoneserestaurant") {
            return [
                PublicSourceSearchResult(
                    title: "賀鴨郎｜粵菜烤鴨中餐廳-承億酒店",
                    url: "https://www.taiurbanresort.com.tw/restaurant-detail/HOU_YA/",
                    snippet: "賀鴨郎 粵菜烤鴨中餐廳｜B1。餐廳地點 高雄市前鎮區林森四路189號B1。電話訂位 07-3333999。"
                )
            ]
        }
        if query.contains("推薦４間冰店") || query.contains("清水茶香") {
            return [
                PublicSourceSearchResult(
                    title: "清水茶香｜台北冰店推薦",
                    url: "https://example.com/taipei-shaved-ice/qingshui",
                    snippet: "清水茶香 台北冰店，地址 台北市大安區復興南路一段100號。推薦黑糖剉冰與手搖茶。"
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
        if query.localizedCaseInsensitiveContains("5712 Via Montellano") || query.localizedCaseInsensitiveContains("Wild Wonders") {
            return [
                GooglePlaceMatch(
                    id: "wild-wonders",
                    name: "Wild Wonders",
                    address: "5712 Via Montellano, Bonsall, CA 92003",
                    latitude: 33.2927,
                    longitude: -117.2089,
                    rating: 4.9,
                    priceLevel: nil
                )
            ]
        }
        if query.contains("牛喜壽喜燒") {
            return [
                GooglePlaceMatch(
                    id: "niu-xi-sukiyaki",
                    name: "牛喜壽喜燒",
                    address: "台北市士林區忠誠路二段200號3樓",
                    latitude: 25.1164,
                    longitude: 121.5319,
                    rating: 4.5,
                    priceLevel: 2
                )
            ]
        }
        if query.localizedCaseInsensitiveContains("A Cheng Goose") {
            return [
                GooglePlaceMatch(
                    id: "a-cheng-goose",
                    name: "A Cheng Goose",
                    address: "No. 105, Jilin Rd, Zhongshan District, Taipei City",
                    latitude: 25.0562,
                    longitude: 121.5301,
                    rating: 4.3,
                    priceLevel: 2
                )
            ]
        }
        if query.contains("清水茶香") {
            return [
                GooglePlaceMatch(
                    id: "qingshui-tea-taipei",
                    name: "清水茶香 台北復興店",
                    address: "台北市大安區復興南路一段100號",
                    latitude: 25.043,
                    longitude: 121.544,
                    rating: 4.4,
                    priceLevel: 1
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

private final class EmptyGooglePlacesService: GooglePlacesServiceProtocol {
    var queries: [String] = []

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        queries.append(query)
        return []
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        throw GooglePlacesError.noResults
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        nil
    }
}

private final class StubPlaceResolverService: PlaceResolverServiceProtocol {
    var queries: [String] = []

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        queries.append(query)
        if query.contains("蟹尊苑") {
            return [
                PlaceProviderMatch(
                    provider: .amap,
                    id: "amap-xiezunyuan",
                    name: "蟹尊苑",
                    address: "上海市黄浦区广东路59号",
                    latitude: 31.2389,
                    longitude: 121.4962,
                    rating: 4.7,
                    reviewCount: nil,
                    priceLevel: nil,
                    types: ["餐饮服务"],
                    coordinateSystem: .gcj02
                )
            ]
        }
        if query.contains("奢海陌野民宿") {
            return [
                PlaceProviderMatch(
                    provider: .amap,
                    id: "amap-shehai-moye",
                    name: "奢海陌野民宿",
                    address: "青岛市崂山区雕龙嘴村",
                    latitude: 36.1689,
                    longitude: 120.6651,
                    rating: 4.8,
                    reviewCount: 42,
                    priceLevel: nil,
                    types: ["住宿服务"],
                    coordinateSystem: .gcj02
                )
            ]
        }
        return []
    }
}

final class SocialPlacePipelineTests: XCTestCase {
    private struct TikTokSourceFixture: Decodable {
        struct Expected: Decodable {
            var sourceIntent: SocialPlaceSourceIntent
            var region: String
            var topic: String
            var placesFound: Int
            var needsRecovery: Bool
            var resolverDecision: SocialPlaceResolverDecisionKind
        }

        var input: TikTokSourceAdapterInput
        var expected: Expected
    }

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

    func testGoogleMapsSavedListExtractsEscapedQueryPlaceLinks() {
        let html = #"""
        <a aria-label="Gem Dining" href="https:\/\/www.google.com\/maps?cid=123456789\u0026query_place_id=ChIJ123">Open</a>
        <a title="Stereoscope Coffee" href="/maps?cid=987654321&amp;ftid=0x80c2">Open</a>
        """#

        let candidates = GoogleMapsListPlaceExtractor.extractCandidates(
            sourceURL: "https://maps.app.goo.gl/saved-list",
            title: "Dinner ideas · Google Maps",
            text: nil,
            metadataTitle: "Dinner ideas - Google Maps",
            metadataDescription: nil,
            htmlText: html
        )

        XCTAssertEqual(candidates.map(\.name), ["Gem Dining", "Stereoscope Coffee"])
    }

    func testGoogleMapsSavedListPrivateShellHasNoInventedCandidates() {
        let html = """
        <title>Private list - Google Maps</title>
        <meta name="description" content="Saved places">
        """

        XCTAssertTrue(GoogleMapsListPlaceExtractor.looksLikeGoogleMapsList(
            sourceURL: "https://maps.app.goo.gl/private-list",
            title: "Private list - Google Maps",
            text: nil,
            metadataTitle: "Private list - Google Maps",
            metadataDescription: "Saved places"
        ))
        XCTAssertTrue(GoogleMapsListPlaceExtractor.extractCandidates(
            sourceURL: "https://maps.app.goo.gl/private-list",
            title: "Private list - Google Maps",
            text: nil,
            metadataTitle: "Private list - Google Maps",
            metadataDescription: "Saved places",
            htmlText: html
        ).isEmpty)
    }

    func testInstagramTaiwanCaptionUsesAngleBracketVenueBeforeHoursLine() {
        let metadata = """
        煦那皮、台北美食、台中美食、國外旅遊 on Instagram: "<Standard Bread>  #新開幕
        *杜拜巧克力吐司 $399
        *香辣奶油香腸義大利麵 $330
        📢5/29正式營運
        ——————————————
        韓國超紅的Standard Bread ，在台北A11開幕了
        ——————————————
        🏠日～四 11:00～21:30 五六 11:00～22:00 5/29正式營運
        🚇捷運台北101站，步行約10分鐘
        📍臺北市信義區松壽路11號B2F
        #信義區美食 #台北美食 #美食 #reels"
        """

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DY1w2qGSiRT/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: nil,
                metadataTitle: metadata,
                metadataDescription: metadata,
                ocrLines: []
            )
        )

        XCTAssertTrue(analysis.placesFound.contains { $0.displayName == "Standard Bread" })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName.contains("11:00") })
        XCTAssertEqual(analysis.placesFound.first?.displayName, "Standard Bread")
        XCTAssertEqual(analysis.placesFound.first?.locationClues.first, "臺北市信義區松壽路11號B2F")
    }

    func testInstagramTaiwanCaptionExtractsChineseAngleBracketVenueAndAddress() {
        let metadata = """
        <阿夢> 📍中正紀念堂
        *煙花女麵 $350
        *蘋果香酥配冰淇淋 $200
        在台北發現一間超怕你餓到，份量很大的深夜咖啡廳，兼小餐館
        大推煙花女麵，海鮮搭配蕃茄吃起來帶點酸，很夠味超好吃
        甜點選了蘋果香酥配冰淇淋，整體環境是暖色調很舒適
        🏠依店家公告 @among_nimbo
        🚇捷運中正紀念堂站，步行約18分鐘
        📍臺北市中正區寧波西街155號
        #台北美食 #中正紀念堂美食 #深夜咖啡廳
        """

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DXzKpnKSfV9/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: metadata,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.placesFound.count, 1)
        XCTAssertEqual(analysis.placesFound.first?.displayName, "阿夢")
        XCTAssertEqual(analysis.placesFound.first?.locationClues.first, "臺北市中正區寧波西街155號")
        XCTAssertTrue(analysis.placesFound.first?.locationClues.contains("中正紀念堂") == true)
        XCTAssertTrue(analysis.placesFound.first?.evidenceChips.contains("Highlight: Recommended item: 煙花女麵 $350") == true)
        XCTAssertTrue(analysis.placesFound.first?.evidenceChips.contains { $0.contains("份量很大的深夜咖啡廳") } == true)
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "Address-only place clue" })

        let candidate = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
            .reviewCandidates(fromEvidenceText: metadata, sourceURL: "https://www.instagram.com/reel/DXzKpnKSfV9/")
            .first
        XCTAssertEqual(candidate?.placeHighlights.first, "在台北發現一間超怕你餓到，份量很大的深夜咖啡廳，兼小餐館")
        XCTAssertEqual(candidate?.recommendedItems.first?.name, "煙花女麵")
        XCTAssertEqual(candidate?.recommendedItems.first?.price, "$350")
        XCTAssertTrue(candidate?.vibeTags.contains("Large portions") == true)
        XCTAssertTrue(candidate?.vibeTags.contains("Cozy") == true)
        XCTAssertEqual(candidate?.accessNotes.first, "🚇捷運中正紀念堂站，步行約18分鐘")
        XCTAssertEqual(candidate?.sourceHandle, "among_nimbo")
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

    private func loadTikTokSourceFixture(_ name: String) throws -> TikTokSourceFixture {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("fixtures/social-source", isDirectory: true)
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TikTokSourceFixture.self, from: data)
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

    func testSocialPlaceEvidenceResolverReturnsMapStampReadyEvidenceBackedCandidate() async throws {
        let places = StubGooglePlacesService()
        let search = StubPublicSourceSearchService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: places,
            publicSourceSearchService: search
        )

        let result = await service.resolveEvidence(SocialPlaceEvidenceResolverInput(
            sourceURL: "https://www.instagram.com/reel/DW2ZpyADbZ6/",
            caption: """
            Talia on Instagram: "This is one of my absolutely favorite restaurants in LA.
            Save this for a slow dinner night."
            """,
            authorHandle: "taliaeats",
            visibleLocationTags: ["LA"],
            categoryClues: ["restaurant"]
        ))

        XCTAssertEqual(result.outcome, .mapStamp)
        XCTAssertEqual(result.rawSource.sourceURL, "https://www.instagram.com/reel/DW2ZpyADbZ6/")
        XCTAssertEqual(result.extracted.caption?.contains("favorite restaurants in LA"), true)
        XCTAssertEqual(result.extracted.authorHandle, "taliaeats")
        XCTAssertTrue(result.extracted.cityClues.contains("LA"))
        XCTAssertTrue(result.searchQueries.contains { $0.contains("DW2ZpyADbZ6") })
        XCTAssertEqual(result.candidate.candidateName, "Quarter Sheets Pizza Club")
        XCTAssertEqual(result.candidate.address, "1305 Portia St, Los Angeles, CA 90026")
        XCTAssertEqual(result.candidate.latitude, 34.0779)
        XCTAssertEqual(result.candidate.longitude, -118.2543)
        XCTAssertTrue(result.evidence.contains { $0.contains("Raw source saved") })
        XCTAssertTrue(result.evidence.contains { $0.contains("Caption captured") })
        XCTAssertTrue(result.evidence.contains { $0.contains("Confidence reason: Places resolver verified") })
    }

    func testSocialPlaceEvidenceResolverKeepsHandleOnlyInstagramAsReviewCandidateWithoutCoordinates() async throws {
        let places = EmptyGooglePlacesService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: places,
            publicSourceSearchService: StubPublicSourceSearchService()
        )

        let result = await service.resolveEvidence(SocialPlaceEvidenceResolverInput(
            sourceURL: "https://www.instagram.com/reel/DXReviewOnly/",
            caption: #"Jess on Instagram: "Trying pastries at @hiddenmooncafe today. #LAcoffee""#,
            authorHandle: "jessfood",
            taggedHandles: ["hiddenmooncafe"],
            cityClues: ["LA"],
            categoryClues: ["cafe"]
        ))

        XCTAssertEqual(result.outcome, .reviewCandidate)
        XCTAssertFalse(result.candidate.isSourceOnly)
        XCTAssertNil(result.candidate.latitude)
        XCTAssertNil(result.candidate.longitude)
        XCTAssertTrue(result.missingFields.contains("Verified address"))
        XCTAssertTrue(result.missingFields.contains("Verified coordinates"))
        XCTAssertTrue(result.extracted.taggedHandles.contains("hiddenmooncafe"))
        XCTAssertTrue(result.evidence.contains { $0.contains("Tagged/venue handle: @hiddenmooncafe") })
        XCTAssertTrue(result.confidenceReason.contains("Review Candidate"))
    }

    func testSocialPlaceEvidenceResolverKeepsBareInstagramURLSourceOnlyWithoutHallucinatingPlace() async throws {
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: EmptyGooglePlacesService(),
            publicSourceSearchService: StubPublicSourceSearchService()
        )

        let result = await service.resolveEvidence(SocialPlaceEvidenceResolverInput(
            sourceURL: "https://www.instagram.com/reel/DBareOnly/"
        ))

        XCTAssertEqual(result.outcome, .sourceOnly)
        XCTAssertTrue(result.candidate.isSourceOnly)
        XCTAssertNil(result.candidate.latitude)
        XCTAssertNil(result.candidate.longitude)
        XCTAssertEqual(result.candidate.address, "")
        XCTAssertTrue(result.searchQueries.contains { $0.contains("DBareOnly") && $0.contains("place") })
        XCTAssertTrue(result.missingFields.contains("Verified place name"))
        XCTAssertTrue(result.evidence.contains { $0.contains("Raw source saved") })
        XCTAssertTrue(result.confidenceReason.contains("no verified place identity"))
    }

    func testInstagramReelThumbnailOCRFeedsPublicRecoveryAndPlacesResolver() async throws {
        let places = StubGooglePlacesService()
        let search = StubPublicSourceSearchService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: places,
            publicSourceSearchService: search
        )

        let result = await service.resolveEvidence(SocialPlaceEvidenceResolverInput(
            sourceURL: "https://www.instagram.com/reel/DHiddenOCR/",
            caption: "Foodie on Instagram: \"save this for later\"",
            authorHandle: "taipei_foodie",
            cityClues: ["台北"],
            categoryClues: ["冰店", "dessert"],
            ocrLines: [
                "推薦４間冰店",
                "台北夏天必吃",
                "清水茶香"
            ]
        ))

        XCTAssertEqual(result.outcome, .mapStamp)
        XCTAssertEqual(result.rawSource.ocrLines, ["推薦４間冰店", "台北夏天必吃", "清水茶香"])
        XCTAssertEqual(result.candidate.candidateName, "清水茶香 台北復興店")
        XCTAssertEqual(result.candidate.address, "台北市大安區復興南路一段100號")
        XCTAssertEqual(result.candidate.reviewState, "map_match_ready")
        XCTAssertTrue(result.searchQueries.contains { $0.contains("推薦４間冰店") || $0.contains("清水茶香") })
        XCTAssertTrue(search.queries.contains { $0.contains("推薦４間冰店") || $0.contains("清水茶香") })
        XCTAssertTrue(places.queries.contains { $0.contains("清水茶香") })
        XCTAssertTrue(result.evidence.contains { $0.contains("清水茶香") })
        XCTAssertTrue(result.candidate.evidenceDiagnostic?.attempts.contains { $0.contains("public metadata/caption/OCR") } == true)
    }

    func testInstagramShilinSukiyakiCaptionStaysRecoveryScopedInsteadOfCreatorOnly() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DVqC21VkxPv/",
                resolvedURL: "https://www.instagram.com/jim.foodie.tw/reel/DVqC21VkxPv/",
                sharedTitle: nil,
                sharedText: """
                俊²的美食日記 📙台北美食 (@jim.foodie.tw) • Instagram Reel
                俊²的美食日記 📙台北美食在 Instagram: "士林📍日本人老闆開業8年的關西壽喜燒
                #台北美食 #台北餐廳 #士林美食 #壽喜燒 #漢堡排"
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.sourceIntent, .restaurantRecommendation)
        XCTAssertTrue(analysis.isPlaceBearing)
        XCTAssertTrue(analysis.placesFound.isEmpty)
        XCTAssertTrue(analysis.regionClues.contains("士林"))
        XCTAssertTrue(analysis.recoveryHints.contains { $0.queryFragment.contains("士林 日本人老闆開業8年的關西壽喜燒") })
        XCTAssertEqual(analysis.resolverDecision.kind, .pendingCandidate)
    }

    func testInstagramShilinSukiyakiCaptionRunsPublicRecoveryAndPlacesMatch() async throws {
        let places = StubGooglePlacesService()
        let search = StubPublicSourceSearchService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: places,
            publicSourceSearchService: search
        )

        let candidates = try await service.recoverReviewCandidates(
            fromEvidenceText: """
            俊²的美食日記 📙台北美食 (@jim.foodie.tw) • Instagram Reel
            俊²的美食日記 📙台北美食在 Instagram: "士林📍日本人老闆開業8年的關西壽喜燒
            #台北美食 #台北餐廳 #士林美食 #壽喜燒 #漢堡排"
            """,
            sourceURL: "https://www.instagram.com/reel/DVqC21VkxPv/?igsh=tracking"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.candidateName, "牛喜壽喜燒")
        XCTAssertEqual(candidate.address, "台北市士林區忠誠路二段200號3樓")
        XCTAssertEqual(candidate.reviewState, "map_match_ready")
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertTrue(search.queries.contains { $0.contains("DVqC21VkxPv") })
        XCTAssertTrue(search.queries.contains { $0.contains("士林") && $0.contains("關西壽喜燒") })
        XCTAssertTrue(places.queries.contains { $0.contains("牛喜壽喜燒") && $0.contains("士林") })
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains { $0.contains("Recovered venue candidate: 牛喜壽喜燒") } == true)
    }

    func testInstagramCityNameHandleCaptionRecoversOfficialAddressAsReviewCandidate() async throws {
        let search = StubPublicSourceSearchService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: EmptyGooglePlacesService(),
            publicSourceSearchService: search
        )

        let candidates = try await service.recoverReviewCandidates(
            fromEvidenceText: """
            KEKE帶我去旅行｜艾琳 on Instagram: "這次讓我念念不忘的
            是高雄的賀鴨郎
            從酥脆鴨皮到多層次的搭配吃法
            每一口都吃得出細節
            難怪很多人吃過一次，
            下次聚餐又默默訂回來🦆✨
            @houyacantoneserestaurant"
            """,
            sourceURL: "https://www.instagram.com/reel/DZSU9JsSkB1/"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.candidateName, "賀鴨郎")
        XCTAssertEqual(candidate.address, "高雄市前鎮區林森四路189號B1")
        XCTAssertEqual(candidate.reviewState, "source_recovered_candidate")
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
        XCTAssertTrue(search.queries.contains { $0.contains("賀鴨郎") && $0.contains("高雄") && $0.contains("地址") })
        XCTAssertTrue(search.queries.contains { $0.contains("houyacantoneserestaurant") && $0.contains("賀鴨郎") })
        XCTAssertTrue(search.queries.contains { $0.contains("賀鴨郎") && $0.contains("官方") && $0.contains("餐廳") })
        XCTAssertTrue(candidate.evidence.contains { $0.contains("Public web search URL: https://www.taiurbanresort.com.tw/restaurant-detail/HOU_YA/") })
        XCTAssertTrue(candidate.evidence.contains { $0.contains("Recovered address evidence: 高雄市前鎮區林森四路189號B1") })
        XCTAssertTrue(candidate.missingInfo.contains("Verified coordinates"))
        XCTAssertTrue(candidate.missingInfo.contains("User confirmation required"))
        XCTAssertTrue(candidate.evidenceDiagnostic?.missingFields.contains("Verified coordinates") == true)
    }

    func testInstagramCityGenericPhraseCreatorHandleWithoutSearchConfirmationStaysSourceOnly() async throws {
        let search = StubPublicSourceSearchService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: EmptyGooglePlacesService(),
            publicSourceSearchService: search
        )

        let candidates = try await service.recoverReviewCandidates(
            fromEvidenceText: """
            旅人日記 on Instagram: "這次讓我念念不忘的是高雄的那間店
            氣氛很好，下次還想再去。
            @keke_travel"
            """,
            sourceURL: "https://www.instagram.com/reel/DGenericCityOnly/"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertTrue(candidate.isSourceOnly)
        XCTAssertEqual(candidate.candidateName, "Instagram reel")
        XCTAssertEqual(candidate.address, "")
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
        XCTAssertFalse(search.queries.contains { $0.contains("那間店") && $0.contains("地址") })
        XCTAssertTrue(candidate.evidenceDiagnostic?.missingFields.contains("Verified place name") == true)
    }

    func testAmapRefinementPromotesChinaRestaurantCandidateToMapReady() async {
        let resolver = StubPlaceResolverService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: StubGooglePlacesService(),
            placeResolverService: resolver
        )
        let candidate = PendingReviewCandidate(
            candidateName: "蟹尊苑",
            address: "上海 黄浦",
            category: "food",
            latitude: nil,
            longitude: nil,
            sourceURL: "https://www.xiaohongshu.com/explore/china-crab",
            sourceText: "上海本帮菜 蟹尊苑 黄浦区",
            evidence: ["Evidence tier: likely"],
            confidence: 0.62,
            missingInfo: ["Confirm coordinates"],
            savedAt: Date()
        )

        let refined = await service.refineCandidate(candidate, evidenceText: "上海本帮菜 蟹尊苑 黄浦区")

        XCTAssertEqual(refined.reviewState, "map_match_ready")
        XCTAssertEqual(refined.candidateName, "蟹尊苑")
        XCTAssertEqual(refined.address, "上海市黄浦区广东路59号")
        XCTAssertEqual(refined.latitude, 31.2389)
        XCTAssertEqual(refined.longitude, 121.4962)
        XCTAssertTrue(resolver.queries.contains { $0.contains("蟹尊苑") && $0.contains("上海") })
        XCTAssertTrue(refined.evidence.contains("Amap refined match: 蟹尊苑"))
        XCTAssertTrue(refined.evidence.contains("Amap coordinates (GCJ-02): 31.2389, 121.4962"))
        XCTAssertEqual(refined.evidenceDiagnostic?.nextBestClue, "Confirm this Amap match before saving it as a Map Stamp.")
    }

    func testBaiduMapDeepLinkPreservesBD09CoordinateProvenance() throws {
        let match = try XCTUnwrap(ChinaMapDeepLinkParser.match(
            from: "https://api.map.baidu.com/marker?location=31.2391,121.4964&title=%E8%9F%B9%E5%B0%8A%E8%8B%91&content=%E4%B8%8A%E6%B5%B7%E5%B8%82%E9%BB%84%E6%B5%A6%E5%8C%BA%E5%B9%BF%E4%B8%9C%E8%B7%AF59%E5%8F%B7&output=html"
        ))

        XCTAssertEqual(match.provider, .baidu)
        XCTAssertEqual(match.name, "蟹尊苑")
        XCTAssertEqual(match.address, "上海市黄浦区广东路59号")
        XCTAssertEqual(match.latitude, 31.2391)
        XCTAssertEqual(match.longitude, 121.4964)
        XCTAssertEqual(match.coordinateSystem, .bd09)
        XCTAssertEqual(match.coordinateEvidenceLabel, "Baidu Maps coordinates (BD-09)")
    }

    func testAmapMapDeepLinkBecomesMapReadyReviewCandidate() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "朋友分享高德地图 https://uri.amap.com/marker?position=121.4962,31.2389&name=%E8%9F%B9%E5%B0%8A%E8%8B%91&src=save",
            sourceURL: "https://uri.amap.com/marker?position=121.4962,31.2389&name=%E8%9F%B9%E5%B0%8A%E8%8B%91&src=save"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.candidateName, "蟹尊苑")
        XCTAssertEqual(candidate.reviewState, "map_match_ready")
        XCTAssertEqual(candidate.latitude, 31.2389)
        XCTAssertEqual(candidate.longitude, 121.4962)
        XCTAssertTrue(candidate.evidence.contains("Amap coordinates (GCJ-02): 31.2389, 121.4962"))
        XCTAssertEqual(candidate.evidenceDiagnostic?.nextBestClue, "Confirm this Amap deep-link match before saving it as a Map Stamp.")
    }

    func testChinaResolverKeepsBaiduFallbackAfterAmapAndProxyMiss() async throws {
        final class EmptyBackend: BackendPlaceResolverServiceProtocol {
            func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] { [] }
        }
        final class EmptyAmap: AmapPlaceSearchServiceProtocol {
            func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] { [] }
        }
        final class BaiduOnly: BaiduPlaceSearchServiceProtocol {
            func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
                [PlaceProviderMatch(
                    provider: .baidu,
                    id: "baidu-xiezunyuan",
                    name: "蟹尊苑",
                    address: "上海市黄浦区广东路59号",
                    latitude: 31.2391,
                    longitude: 121.4964,
                    rating: 4.6,
                    reviewCount: 88,
                    priceLevel: nil,
                    types: ["美食"],
                    coordinateSystem: .bd09
                )]
            }
        }
        final class EmptyGoogle: GooglePlacesServiceProtocol {
            func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] { [] }
            func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails { throw GooglePlacesError.noResults }
            func photoURL(reference: String, maxWidth: Int) -> URL? { nil }
        }

        let resolver = PlaceResolverService(
            googlePlacesService: EmptyGoogle(),
            amapPlaceSearchService: EmptyAmap(),
            baiduPlaceSearchService: BaiduOnly(),
            backendPlaceResolverService: EmptyBackend()
        )

        let matches = try await resolver.searchPlace(query: "上海 蟹尊苑 黄浦", near: nil)

        XCTAssertEqual(matches.first?.provider, .baidu)
        XCTAssertEqual(matches.first?.coordinateSystem, .bd09)
        XCTAssertEqual(matches.first?.coordinateEvidenceLabel, "Baidu Maps coordinates (BD-09)")
    }

    func testXiaohongshuAndDouyinLinksPreparePlatformSpecificRecoveryQueries() {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())

        let xhs = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://www.xiaohongshu.com/explore/65abc123"
        ).first
        let douyin = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://v.douyin.com/buUywZoMiLw/"
        ).first

        XCTAssertEqual(xhs?.candidateName, "Xiaohongshu link")
        XCTAssertEqual(douyin?.candidateName, "Douyin link")
        XCTAssertTrue(xhs?.evidenceDiagnostic?.suggestedSearchQueries?.contains("xiaohongshu 65abc123 place") == true)
        XCTAssertTrue(douyin?.evidenceDiagnostic?.suggestedSearchQueries?.contains("douyin buUywZoMiLw place") == true)
    }

    func testXiaohongshuURLOnlyUsesHermesStyleBlockedLinkAnalysis() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())

        let candidate = try XCTUnwrap(service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "小红书",
            sourceURL: "https://www.xiaohongshu.com/explore/65abc123?xsec_token=abc&utm_source=copy"
        ).first)
        let diagnostic = try XCTUnwrap(candidate.evidenceDiagnostic)

        XCTAssertEqual(candidate.candidateName, "Xiaohongshu link")
        XCTAssertTrue(candidate.isSourceOnly)
        XCTAssertTrue(diagnostic.found.contains("Xiaohongshu note id: 65abc123"))
        XCTAssertTrue(diagnostic.found.contains("Canonical Xiaohongshu URL: https://www.xiaohongshu.com/explore/65abc123"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: classified the shared URL/platform and canonical post id before trusting content"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: inspected readable metadata/caption/OCR for venue anchors, address pins, map links, and social handles"))
        XCTAssertTrue(diagnostic.attempts.contains("Resolved canonical Xiaohongshu URL and extracted the note id"))
        XCTAssertTrue(diagnostic.attempts.contains("Detected blocked or generic Xiaohongshu metadata shell instead of usable caption text"))
        XCTAssertTrue(diagnostic.found.contains("Readable metadata/caption/OCR: present but no verified address/map link"))
        XCTAssertTrue(diagnostic.missingFields.contains("Readable Xiaohongshu caption or screenshot OCR"))
        XCTAssertEqual(diagnostic.nextBestClue, "Share a Xiaohongshu screenshot/OCR frame, copied caption, or map link so SAV-E can turn this source into a Review Candidate.")
        XCTAssertEqual(diagnostic.suggestedSearchQueries?.first, "xiaohongshu 65abc123 place")
        XCTAssertTrue(diagnostic.suggestedSearchQueries?.contains("\"https://www.xiaohongshu.com/explore/65abc123\"") == true)
    }

    func testXiaohongshuShortLinkDoesNotPretendSlugIsNoteID() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())

        let candidate = try XCTUnwrap(service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "http://xhslink.com/o/3zvbJIowbqS"
        ).first)
        let diagnostic = try XCTUnwrap(candidate.evidenceDiagnostic)

        XCTAssertEqual(candidate.candidateName, "Xiaohongshu link")
        XCTAssertTrue(candidate.isSourceOnly)
        XCTAssertTrue(diagnostic.found.contains("Xiaohongshu short link code: 3zvbJIowbqS"))
        XCTAssertTrue(diagnostic.found.contains("Original Xiaohongshu short URL: http://xhslink.com/o/3zvbJIowbqS"))
        XCTAssertFalse(diagnostic.found.contains("Xiaohongshu note id: 3zvbJIowbqS"))
        XCTAssertTrue(diagnostic.attempts.contains("Detected Xiaohongshu short link but public redirect did not expose a canonical note id"))
        XCTAssertTrue(diagnostic.missingFields.contains("Readable Xiaohongshu caption or screenshot OCR"))
        XCTAssertEqual(diagnostic.nextBestClue, "Share a Xiaohongshu screenshot/OCR frame, copied caption, or map link so SAV-E can turn this source into a Review Candidate.")
        XCTAssertEqual(diagnostic.suggestedSearchQueries?.first, "xiaohongshu short link 3zvbJIowbqS place")
        XCTAssertTrue(diagnostic.suggestedSearchQueries?.contains("\"http://xhslink.com/o/3zvbJIowbqS\"") == true)
    }

    func testXiaohongshuBlocked404OriginalURLRecoversCanonicalNoteID() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())

        let candidate = try XCTUnwrap(service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "小红书",
            sourceURL: "https://www.xiaohongshu.com/404/sec_cixRFHQg?source=xhs_sec_server&originalUrl=http%3A%2F%2Fwww.xiaohongshu.com%2Fdiscovery%2Fitem%2F69c3ed88000000001d01c4c3%3Fapp_platform%3Dios%26xsec_source%3Dapp_share"
        ).first)
        let diagnostic = try XCTUnwrap(candidate.evidenceDiagnostic)

        XCTAssertEqual(candidate.candidateName, "Xiaohongshu link")
        XCTAssertTrue(candidate.isSourceOnly)
        XCTAssertTrue(diagnostic.found.contains("Xiaohongshu note id: 69c3ed88000000001d01c4c3"))
        XCTAssertTrue(diagnostic.found.contains("Canonical Xiaohongshu URL: http://www.xiaohongshu.com/discovery/item/69c3ed88000000001d01c4c3"))
        XCTAssertFalse(diagnostic.found.contains("Xiaohongshu note id: sec_cixRFHQg"))
        XCTAssertEqual(diagnostic.suggestedSearchQueries?.first, "xiaohongshu 69c3ed88000000001d01c4c3 place")
        XCTAssertTrue(diagnostic.suggestedSearchQueries?.contains("\"http://www.xiaohongshu.com/discovery/item/69c3ed88000000001d01c4c3\"") == true)
    }

    func testXiaohongshuCaptionMetadataCanBecomeReviewCandidate() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())

        let candidate = try XCTUnwrap(service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            小红书：上海蟹尊苑真的太好吃
            📍蟹尊苑
            上海市黄浦区广东路59号
            """,
            sourceURL: "https://www.xiaohongshu.com/explore/65abc123"
        ).first)

        XCTAssertEqual(candidate.candidateName, "蟹尊苑")
        XCTAssertEqual(candidate.address, "上海市黄浦区广东路59号")
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Xiaohongshu note id: 65abc123") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.attempts.contains("Used readable Xiaohongshu caption/metadata as place evidence") == true)
        XCTAssertTrue(candidate.missingInfo.contains("Confirm coordinates"))
    }

    func testDianpingKeywordsCreateReviewCandidateWithoutFakeCoordinates() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())

        let candidate = try XCTUnwrap(service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            Title: 青岛崂山📍住到了人生酒店！
            Keywords: 奢海陌野民宿
            Description: 青岛崂山旅行住宿推荐，面朝大海的民宿体验。
            """,
            sourceURL: "http://dpurl.cn/IFoOLolz"
        ).first)
        let diagnostic = try XCTUnwrap(candidate.evidenceDiagnostic)

        XCTAssertEqual(candidate.candidateName, "奢海陌野民宿")
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertEqual(candidate.reviewState, "review_candidate")
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
        XCTAssertTrue(candidate.missingInfo.contains("Verified coordinates"))
        XCTAssertTrue(diagnostic.found.contains("Dianping feed id: IFoOLolz"))
        XCTAssertTrue(diagnostic.found.contains("Dianping business clue: 奢海陌野民宿"))
        XCTAssertTrue(diagnostic.attempts.contains("Preferred Dianping keywords/business field over generic feed title"))
    }

    func testDianpingKeywordOutranksGenericTitleAndRefinementKeepsAmapProvenance() async throws {
        let resolver = StubPlaceResolverService()
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: StubGooglePlacesService(),
            placeResolverService: resolver
        )

        let candidates = try await service.recoverReviewCandidates(
            fromEvidenceText: """
            Title: 青岛崂山📍住到了人生酒店！
            Keywords: 奢海陌野民宿
            Description: 青岛崂山旅行住宿推荐，面朝大海的民宿体验。
            """,
            sourceURL: "https://m.dianping.com/feeddetail/466776750"
        )
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidate.candidateName, "奢海陌野民宿")
        XCTAssertNotEqual(candidate.candidateName, "青岛崂山📍住到了人生酒店！")
        XCTAssertEqual(candidate.reviewState, "map_match_ready")
        XCTAssertEqual(candidate.address, "青岛市崂山区雕龙嘴村")
        XCTAssertEqual(candidate.latitude, 36.1689)
        XCTAssertEqual(candidate.longitude, 120.6651)
        XCTAssertTrue(resolver.queries.contains { $0.contains("奢海陌野民宿") })
        XCTAssertTrue(candidate.evidence.contains("Amap coordinates (GCJ-02): 36.1689, 120.6651"))
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Dianping feed id: 466776750") == true)
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

    func testInstagramTraditionalChineseBookTitleVenueBeforePinAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            🌸SaSa. Fingerlicking on Instagram: "🍜天母超浮誇牛肉麵
            厚切半筋半肉的牛肉塊給的份量超多

            《忠誠牛肉麵》
            📍台北市士林區德行東路80號

            #天母美食 #台北美食 #士林美食 #排隊美食 #牛肉麵"
            """,
            sourceURL: "https://www.instagram.com/reel/DXPR6RfAICu/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "忠誠牛肉麵")
        XCTAssertEqual(candidates.first?.address, "台北市士林區德行東路80號")
        XCTAssertFalse(candidates.first?.isSourceOnly == true)
        XCTAssertFalse(candidates.contains { $0.candidateName == "天母超浮誇牛肉麵" })
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("SaSa") })
    }

    func testInstagramFoodEmojiVenueMarkerBeforePinAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            煮惑甜心 • 廚娘在 Instagram: "台北最強的便當店😋
            滷肉飯免費吃到飽，飲料喝到飽！！

            🍴食來運轉
            📍臺北市士林區仁勇里小東街31號
            🕛10：00～14：00、16：00～20：00

            #廚娘 #台北美食 #士林夜市 #吃到飽 #滷肉飯"
            """,
            sourceURL: "https://www.instagram.com/reel/DZM8vmZBuNM/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "食來運轉")
        XCTAssertEqual(candidates.first?.address, "臺北市士林區仁勇里小東街31號")
        XCTAssertFalse(candidates.first?.isSourceOnly == true)
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("煮惑甜心") })
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("台北最強的便當店") })
    }

    func testInstagramGenericEmojiVenueMarkerBeforePinAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            台北新店分享 on Instagram: "這間最近很多人收藏

            🧋春水堂人文茶館
            📍臺北市信義區松壽路9號
            🕛11：00～22：00
            """,
            sourceURL: "https://www.instagram.com/reel/DGenericEmoji/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "春水堂人文茶館")
        XCTAssertEqual(candidates.first?.address, "臺北市信義區松壽路9號")
        XCTAssertFalse(candidates.first?.isSourceOnly == true)
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("台北新店分享") })
    }

    func testInstagramGenericEmojiMarkerRejectsMarketingHeadlineBeforeAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            煮惑甜心 • 廚娘在 Instagram: "
            😋台北最強的便當店
            滷肉飯免費吃到飽，飲料喝到飽！！

            🍴食來運轉
            📍臺北市士林區仁勇里小東街31號
            """,
            sourceURL: "https://www.instagram.com/reel/DZM8vmZBuNM/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "食來運轉")
        XCTAssertEqual(candidates.first?.address, "臺北市士林區仁勇里小東街31號")
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("台北最強的便當店") })
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("滷肉飯免費吃到飽") })
    }

    func testInstagramStandaloneChineseVenueLineBeforePinAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            foodies__eric.sharon on Instagram: "內湖好吃到我連吃兩碗的超濃郁蟹黃麵
            隱身瑞光路上生意超好的麵食館！
            餐點份量很夠，服務也很親切🫶🏻

            常客幾乎都點香麻帶勁的紅油燃麵
            鮮蝦抄手&麵條緊緊扒附醬汁超好吃！
            重頭戲絕對是鮮到不行的蟹黃拌麵🦀
            滿滿蟹肉蟹黃裹滿麵條，鮮味爆擊太銷魂了～～

            墨竹亭 燃麵本家 內湖瑞光店
            📍臺北市內湖區港墘里瑞光路289號
            ⏰ 11:00-15:00 / 17:00-20:30
            """,
            sourceURL: "https://www.instagram.com/reel/DY9UL8JTb5p/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "墨竹亭 燃麵本家 內湖瑞光店")
        XCTAssertEqual(candidates.first?.address, "臺北市內湖區港墘里瑞光路289號")
        XCTAssertFalse(candidates.first?.isSourceOnly == true)
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("foodies__eric") })
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("蟹黃麵") && $0.candidateName != "墨竹亭 燃麵本家 內湖瑞光店" })
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("隱身瑞光路") })
        let diagnostic = try XCTUnwrap(candidates.first?.evidenceDiagnostic)
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: pairs venue-looking lines with nearby strong evidence such as a pinned/street address before creating a Review Candidate"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: accepts explicit venue anchors including labels, quotes/brackets, generic emoji/symbol markers, and standalone CJK/Latin venue lines before an address"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: rejects creator profiles, hashtags, marketing headlines, menu/price items, operating hours, transit/access lines, review metrics, and generic social shells as venue names"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: falls back to source-only when readable metadata is missing/blocked, only a creator handle exists, only OCR/headline text exists, only menu/items exist, multiple list places need selection, or no address/map-provider match is available"))
    }

    func testInstagramStandaloneLowercaseLatinVenueLineBeforePinAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            coffee notes on Instagram: "saved this one for a slow morning

            blue bottle coffee
            📍300 Webster St, Oakland
            """,
            sourceURL: "https://www.instagram.com/reel/DLowercaseVenue/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "blue bottle coffee")
        XCTAssertEqual(candidates.first?.address, "300 Webster St, Oakland")
        XCTAssertFalse(candidates.first?.isSourceOnly == true)
    }

    func testInstagramTraditionalChineseBookTitleDiagnosticExplainsAnalysisMethod() throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidate = try XCTUnwrap(service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            🌸SaSa. Fingerlicking on Instagram: "🍜天母超浮誇牛肉麵
            厚切半筋半肉的牛肉塊給的份量超多

            《忠誠牛肉麵》
            📍台北市士林區德行東路80號

            #天母美食 #台北美食 #士林美食 #排隊美食 #牛肉麵"
            """,
            sourceURL: "https://www.instagram.com/reel/DXPR6RfAICu/"
        ).first)
        let diagnostic = try XCTUnwrap(candidate.evidenceDiagnostic)

        XCTAssertEqual(candidate.candidateName, "忠誠牛肉麵")
        XCTAssertEqual(candidate.address, "台北市士林區德行東路80號")
        XCTAssertTrue(diagnostic.found.contains("Readable metadata/caption/OCR: present with location clues"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: classified the shared URL/platform and canonical post id before trusting content"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: inspected readable metadata/caption/OCR for venue anchors, address pins, map links, and social handles"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: requires a place name plus address or map-provider match before saving directly; otherwise keeps it in Review"))
        XCTAssertTrue(diagnostic.attempts.contains("Analysis method: records unresolved details internally so SAV-E can keep trying instead of guessing"))
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

    func testInstagramMenuItemPinLineDoesNotOutrankVenueNamedBeforeAddress() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            俊²的美食日記 📙台北美食 on Instagram: "大安📍IG很少人介紹過的正統義大利餐廳
            這間位於通化夜市巷弄裡低調的十年老店
            「Divino Taipei」我已經回訪三次了
            不但由待過米其林二星的義大利人老闆掌廚

            用餐餐點：

            📌炙烤牛舌｜甜玉米
            📌豬頰肉｜佩可利諾起司｜水管麵
            📌紅蝦塔塔｜濃蝦醬｜粗直麵

            Divino Taipei
            📍：台北大安區安和路二段71巷15號
            🕒：18:00-21:30 （週日、一公休）
            ☎️：02-2732-2552
            #台北美食 #義式餐廳 #台北餐廳 #義大利麵 #大安區美食"
            """,
            sourceURL: "https://www.instagram.com/reel/DWQp2adE9rB/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "Divino Taipei")
        XCTAssertEqual(candidates.first?.address, "台北大安區安和路二段71巷15號")
        XCTAssertFalse(candidates.contains { $0.candidateName == "炙烤牛舌｜甜玉米" })
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

    func testInstagramWildWondersVenueHandleBeatsGenericOCRHeading() {
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/wildwonders/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: """
                San Diego weekend idea: @wildwonderssd in Bonsall offers wildlife animal encounters and sanctuary tours.
                📍5712 Via Montellano, Bonsall, CA 92003
                """,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: ["Things to know", "animal encounter experience"]
            )
        )

        XCTAssertEqual(analysis.placesFound.first?.displayName, "Wild Wonders")
        XCTAssertEqual(analysis.placesFound.first?.category, "attraction")
        XCTAssertEqual(analysis.placesFound.first?.locationClues.first, "5712 Via Montellano, Bonsall, CA 92003")
        XCTAssertTrue(analysis.placesFound.first?.venueHandles.contains("wildwonderssd") == true)
        XCTAssertTrue(analysis.regionClues.contains("San Diego"))
        XCTAssertTrue(analysis.regionClues.contains("Bonsall"))
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName.localizedCaseInsensitiveContains("Things to know") })
    }

    func testAddressOnlyHighConfidencePlacesMatchOverridesGenericOCRHeading() async throws {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = try await service.recoverReviewCandidates(
            fromEvidenceText: """
            Things to know
            Wildlife animal encounter experience near San Diego.
            📍5712 Via Montellano, Bonsall, CA 92003
            """,
            sourceURL: "https://www.instagram.com/reel/wildwonders-address/"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.candidateName, "Wild Wonders")
        XCTAssertEqual(candidate.address, "5712 Via Montellano, Bonsall, CA 92003")
        XCTAssertEqual(candidate.category, "attraction")
        XCTAssertEqual(candidate.reviewState, "map_match_ready")
        XCTAssertEqual(candidate.hasReliableCoordinates, true)
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("Things to know") })
        XCTAssertTrue(candidate.evidence.contains("Google Places refined match: Wild Wonders"))
    }

    func testTransitExitClueDoesNotBecomeAddressOnlyPlaceCandidate() {
        let evidence = """
        蘆洲美食 on Instagram: "下班後想吃點甜的
        🚇捷運蘆洲站(2號出口)
        #蘆洲美食 #台北甜點 #reels"
        """
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/reel/DY6Kbg6PS3N/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: evidence,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: evidence,
            sourceURL: "https://www.instagram.com/reel/DY6Kbg6PS3N/"
        )

        XCTAssertFalse(SocialPlaceEvidenceScorer.looksLikeAddressLine("🚇捷運蘆洲站(2號出口)"))
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName == "Address-only place clue" })
        XCTAssertFalse(candidates.contains { $0.candidateName == "Address-only place clue" })
        XCTAssertFalse(candidates.contains { $0.address.contains("捷運蘆洲站") })
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

    func testTikTokSourceAdapterTreatsListOcrAsBoundedRecoveryContract() throws {
        let fixture = try loadTikTokSourceFixture("tiktok-tainan-ice-list.json")
        let result = TikTokSourceAdapter().analyze(fixture.input)

        XCTAssertEqual(result.sourceIntent, fixture.expected.sourceIntent)
        XCTAssertEqual(result.region, fixture.expected.region)
        XCTAssertEqual(result.topic, fixture.expected.topic)
        XCTAssertEqual(result.placesFound, fixture.expected.placesFound)
        XCTAssertEqual(result.needsRecovery, fixture.expected.needsRecovery)
        XCTAssertEqual(result.resolverDecision, fixture.expected.resolverDecision)
        XCTAssertTrue(result.recoveryStrategies.contains(.listMode))
        XCTAssertTrue(result.recoveryStrategies.contains(.ocrExtraction))
        XCTAssertTrue(result.recoveryStrategies.contains(.publicSearchRecovery))
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

    func testDouyinNoisyAggregateShareStaysMultiPlaceSourceOnly() {
        let noisyShareText = """
        9.41 复制打开抖音，看看【金贵七七（环游中国版）的作品】五一大家不要放过武汉！三刷武汉后从20+家美食里筛...
        https://v.douyin.com/1GiTQ8dM5U8/
        05/20 JIi:/ f@o.Qk :9pm
        """
        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://v.douyin.com/1GiTQ8dM5U8/",
                resolvedURL: "https://www.iesdouyin.com/share/video/7628919504407399680/",
                sharedTitle: nil,
                sharedText: noisyShareText,
                metadataTitle: "抖音",
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertEqual(analysis.sourceType, .multiPlaceList)
        XCTAssertEqual(analysis.sourceIntent, .multiPlaceList)
        XCTAssertEqual(analysis.resolverDecision.kind, .multiPlaceList)
        XCTAssertTrue(analysis.isPlaceBearing)
        XCTAssertTrue(analysis.placesFound.isEmpty)
        XCTAssertTrue(analysis.recoveryStrategies.contains(.listMode))
        XCTAssertTrue(analysis.regionClues.contains("武汉") || analysis.regionClues.contains("武漢"))
    }

    func testDouyinNoisyAggregateShareDoesNotInventRestaurantCoordinates() {
        let service = SocialLinkReviewCandidateService()
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            9.41 复制打开抖音，看看【金贵七七（环游中国版）的作品】五一大家不要放过武汉！三刷武汉后从20+家美食里筛...
            https://v.douyin.com/1GiTQ8dM5U8/
            05/20 JIi:/ f@o.Qk :9pm
            """,
            sourceURL: "https://v.douyin.com/1GiTQ8dM5U8/"
        )

        let candidate = try! XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidate.reviewState, "unresolved_place_candidate")
        XCTAssertEqual(candidate.latitude, nil)
        XCTAssertEqual(candidate.longitude, nil)
        XCTAssertTrue(candidate.address.isEmpty)
        XCTAssertFalse(candidate.hasReliableCoordinates)
        XCTAssertTrue(candidate.missingInfo.contains("Verified address"))
        XCTAssertTrue(candidate.evidenceDiagnostic?.recoveryPlan?.decision == .multiPlaceList)
        XCTAssertTrue(candidate.evidenceDiagnostic?.recoveryPlan?.requiredEvidence.contains("Map/place match") == true)
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

    func testInstagramShopAndLocationMarkersCreateReviewCandidate() {
        let service = SocialLinkReviewCandidateService()
        let sourceURL = "https://www.instagram.com/reel/DYMZ575zYYQ/"
        let candidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            辰辰🌱卉卉🤤台北｜新北｜ 美食分享🍗Jun Chen Ye (@b.p.food_) • Instagram reel
            b.p.food_ on May 11, 2026: "🔥在台北終於吃到好吃到升天的的雞肉飯了
            🔸雞肉飯$65 都是用整塊的無骨雞下去製作
            鮮嫩又多汁一定要半熟蛋
            🏡店名：上好雞肉
            📮地點：新北市中和區民治街8巷1號
            ⏱️時間：11:00-14:00 16:30-18:30（六日公休）"
            """,
            sourceURL: sourceURL
        )

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertFalse(candidate.isSourceOnly)
        XCTAssertEqual(candidate.candidateName, "上好雞肉")
        XCTAssertEqual(candidate.address, "新北市中和區民治街8巷1號")
        XCTAssertTrue(candidate.evidence.joined(separator: " ").contains("Source URL: \(sourceURL)"))
        XCTAssertNil(candidate.latitude)
        XCTAssertNil(candidate.longitude)
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
        XCTAssertTrue(candidate.evidenceDiagnostic?.attempts.contains("Did not use logged-in social scraping") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.attempts.contains("Prepared public web search fallback queries for source-only recovery") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.missingFields.contains("Verified place name") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.suggestedSearchQueries?.first, "instagram reel DYsourceOnly place")
        XCTAssertTrue(candidate.evidence.contains("Suggested public search: instagram reel DYsourceOnly place"))
        XCTAssertEqual(candidate.evidenceDiagnostic?.nextBestClue, "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.")
        XCTAssertTrue(candidate.missingInfo.contains("Verified place name"))
        XCTAssertEqual(candidate.evidenceDiagnostic?.recoveryPlan?.decision, .sourceOnly)
        XCTAssertEqual(candidate.evidenceDiagnostic?.recoveryPlan?.allowsDirectSave, false)
        XCTAssertTrue(candidate.evidenceDiagnostic?.recoveryPlan?.evidenceAtoms.contains("readable_text: none") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.recoveryPlan?.queriesToTry.contains("instagram reel DYsourceOnly place") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.rejectedEvidence?.contains { $0.reason.contains("not promoted to venue") } == true)
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
        XCTAssertEqual(candidate.evidenceDiagnostic?.statusLabel, "Review candidate")
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
        XCTAssertEqual(candidate.evidenceDiagnostic?.statusLabel, "Possible place")
        XCTAssertEqual(candidate.evidenceDiagnostic?.primaryActionLabel, "Review options")
        XCTAssertTrue(candidate.evidenceDiagnostic?.found.contains("Resolver decision: pendingCandidate") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.suggestedSearchQueries?.first, "\"DW2ZpyADbZ6\" restaurant LA")
        XCTAssertFalse(candidate.evidenceDiagnostic?.suggestedSearchQueries?.joined(separator: " ").contains("igsh") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.nextBestClue.contains("source recovery search") == true)
        XCTAssertEqual(candidate.evidenceDiagnostic?.recoveryPlan?.decision, .pendingCandidate)
        XCTAssertEqual(candidate.evidenceDiagnostic?.recoveryPlan?.allowsDirectSave, false)
        XCTAssertTrue(candidate.evidenceDiagnostic?.recoveryPlan?.requiredEvidence.contains("Public corroboration") == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.recoveryPlan?.blockedResultHints.contains { $0.contains("creator profile") } == true)
        XCTAssertTrue(candidate.evidenceDiagnostic?.rejectedEvidence?.contains { $0.value.contains("tracking") } == true)
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

    func testSaveCardPlaceDecodesOldRecordsWithoutStructuredHighlights() throws {
        let json = """
        {
          "name": "Garden Table Cafe",
          "address": "Taipei",
          "status": "review_candidate",
          "confidence": 0.7,
          "proofLevel": "source_link",
          "evidence": ["Source URL: https://www.instagram.com/reel/old/"],
          "missingInfo": ["Confirm coordinates"]
        }
        """.data(using: .utf8)!

        let place = try JSONDecoder().decode(SaveCardPlace.self, from: json)

        XCTAssertEqual(place.name, "Garden Table Cafe")
        XCTAssertTrue(place.placeHighlights.isEmpty)
        XCTAssertTrue(place.recommendedItems.isEmpty)
        XCTAssertTrue(place.vibeTags.isEmpty)
        XCTAssertTrue(place.accessNotes.isEmpty)
        XCTAssertNil(place.sourceHandle)
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
        XCTAssertNil(diagnostic.recoveryPlan)
        XCTAssertNil(diagnostic.rejectedEvidence)
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
        XCTAssertEqual(record.evidenceDiagnostic?.statusLabel, "Saved for later")
        XCTAssertEqual(record.evidenceDiagnostic?.primaryActionLabel, "Add details")
        XCTAssertEqual(record.evidenceDiagnostic?.canSaveAsMapStamp, false)
        XCTAssertEqual(record.evidenceDiagnostic?.recoveryPlan?.decision, .sourceOnly)
        XCTAssertEqual(record.evidenceDiagnostic?.recoveryPlan?.allowsDirectSave, false)
        XCTAssertTrue(record.evidenceDiagnostic?.recoveryPlan?.evidenceAtoms.contains("shared_note: present") == true)
        XCTAssertTrue(record.evidenceDiagnostic?.rejectedEvidence?.contains { $0.value == "source-only link" } == true)
    }

    func testSaveLocalVaultRestoresConfirmedPlaceWithMapMetadata() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("save-memory-records.json")
        let service = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let place = Place(
            id: UUID(),
            name: "Utopia Euro Caffe",
            address: "2489 Park Ave, Tustin, CA",
            latitude: 33.7032,
            longitude: -117.8271,
            googlePlaceId: nil,
            category: .cafe,
            status: .wantToGo,
            rating: 4.7,
            note: "Saved before backend sync finished.",
            sourceUrl: "https://maps.app.goo.gl/example",
            sourcePlatform: .googleMaps,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        _ = try service.saveConfirmedPlace(place)
        let restored = try service.confirmedPlaces()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.name, "Utopia Euro Caffe")
        XCTAssertEqual(restored.first?.category, .cafe)
        XCTAssertEqual(restored.first?.latitude, 33.7032)
        XCTAssertEqual(restored.first?.longitude, -117.8271)
        XCTAssertEqual(restored.first?.rating, 4.7)
    }

    func testSaveLocalVaultIgnoresLegacyConfirmedRecordsWithoutCoordinates() throws {
        let vaultDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
        let vaultURL = vaultDirectory.appendingPathComponent("save-memory-records.json")
        let legacyJSON = """
        [{
          "id": "00000000-0000-0000-0000-000000000001",
          "state": "confirmed_place",
          "title": "Legacy Cafe",
          "placeName": "Legacy Cafe",
          "address": "123 Main St",
          "evidence": [],
          "placeHighlights": [],
          "recommendedItems": [],
          "vibeTags": [],
          "accessNotes": [],
          "createdAt": "2026-05-31T00:00:00Z"
        }]
        """.data(using: .utf8)!
        try legacyJSON.write(to: vaultURL)
        let service = SaveLocalVaultService(overrideVaultURL: vaultURL)

        XCTAssertEqual(try service.recentRecords().count, 1)
        XCTAssertEqual(try service.confirmedPlaces(), [])
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

        XCTAssertEqual(refined.evidenceDiagnostic?.statusLabel, "Ready to save")
        XCTAssertEqual(refined.evidenceDiagnostic?.primaryActionLabel, "Save place")
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

    func testExactMapCandidateSearchUsesRecoveredPlaceNameAndAddress() async {
        let google = StubGooglePlacesService()
        let service = MapCandidateSearchService(googlePlacesService: google)

        let candidates = await service.searchCandidates(
            matching: "A Cheng Goose No. 105號 Jilin Rd Zhongshan District",
            near: nil,
            span: nil,
            excluding: []
        )

        XCTAssertEqual(google.queries, ["A Cheng Goose No. 105號 Jilin Rd Zhongshan District"])
        let result = candidates.first
        XCTAssertEqual(result?.title, "A Cheng Goose")
        XCTAssertEqual(result?.subtitle, "No. 105, Jilin Rd, Zhongshan District, Taipei City")
        XCTAssertEqual(result?.latitude, 25.0562)
        XCTAssertEqual(result?.longitude, 121.5301)
        XCTAssertNil(result?.distanceMeters)
        XCTAssertTrue(result?.evidence.contains("Google Places result") == true)
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
    func testInstagramReelCaptionKeepsVenueMarkerBeforeAddress() {
        let caption = """
        真蓁 挖寶美食💅 on Instagram: "這是我此生吃過最扯的吃到飽…….
        竟然是帝王蟹吃到飽啊啊啊啊😍～～～～～～
        台北店 $3588
        桃園店／竹北店 $3888
        新竹金山店 $4888
        台中店 $4588
        ‼️每間分店餐點有所不同，反應在價格上，這次在台中吃的

        🏠孫太太。山海。惠中行館
        📍臺中市西屯區惠中六街15號1樓

        #台中美食 #台中吃到飽 #帝王蟹吃到飽 #台中火鍋 #台中必吃"
        """

        let candidates = SocialLinkReviewCandidateService.shared.reviewCandidates(
            fromEvidenceText: caption,
            sourceURL: "https://www.instagram.com/reel/DWiJELtk08-/"
        )

        XCTAssertEqual(candidates.first?.candidateName, "孫太太。山海。惠中行館")
        XCTAssertEqual(candidates.first?.address, "臺中市西屯區惠中六街15號1樓")
        XCTAssertEqual(candidates.first?.category, "food")
        XCTAssertFalse(candidates.contains { $0.candidateName == "Address-only place clue" })
    }

    func testSavedPlaceMemorySummaryFiltersMapDistanceDebugLines() {
        let place = Place(
            id: UUID(),
            name: "Utopia Euro Caffe",
            address: "Selected on map",
            latitude: 33.684,
            longitude: -117.826,
            category: .cafe,
            status: .wantToGo,
            note: "Distance: 852m away",
            sourcePlatform: .googleMaps,
            priceRange: "$$",
            googleRating: 4.6,
            createdAt: Date(),
            visibility: .privateMemory,
            socialSignal: nil
        )

        XCTAssertNil(place.cleanMemoryNote)
        XCTAssertEqual(place.memorySummary(language: .traditionalChinese), "已存成想找時間去的地點。")
    }

    func testOnboardingFirstClueQueuesReviewCandidateWithoutSyntheticSourceURL() throws {
        let candidates = PendingPlaceImportService.onboardingFirstClueCandidates(
            from: "Hidden Moon Cafe near the station, tiny patio, tagged @hidden.moon.cafe"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertNil(candidate.sourceURL)
        XCTAssertEqual(candidate.sourceText, "Hidden Moon Cafe near the station, tiny patio, tagged @hidden.moon.cafe")
        XCTAssertFalse(candidate.evidence.contains { $0.contains("save://onboarding") })
        XCTAssertTrue(candidate.evidence.contains { $0.contains("Onboarding clue: Hidden Moon Cafe") })
        XCTAssertFalse(candidate.candidateName.isEmpty)
    }

    // MARK: - Share-text normalization (messy real-world pastes)

    private struct ShareTextFixture: Decodable {
        struct Expected: Decodable {
            var primaryURLString: String
            var platform: SocialSharePlatform
            var creatorName: String?
            var captionContains: [String]
            var captionExcludes: [String]
        }

        var rawShareText: String
        var expected: Expected
    }

    private func loadShareTextFixture(_ name: String) throws -> ShareTextFixture {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("fixtures/social-source", isDirectory: true)
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ShareTextFixture.self, from: data)
    }

    private func assertShareTextFixtureNormalizes(_ name: String) throws {
        let fixture = try loadShareTextFixture(name)
        let bundle = SocialShareTextNormalizer.normalize(fixture.rawShareText)

        XCTAssertEqual(bundle.primaryURLString, fixture.expected.primaryURLString, name)
        XCTAssertEqual(bundle.platform, fixture.expected.platform, name)
        XCTAssertEqual(bundle.creatorName, fixture.expected.creatorName, name)
        XCTAssertEqual(bundle.rawShareText, fixture.rawShareText, "\(name): raw paste must be preserved")
        for clue in fixture.expected.captionContains {
            XCTAssertTrue(bundle.captionEvidence.contains(clue), "\(name): caption should keep clue \(clue)")
        }
        for noise in fixture.expected.captionExcludes {
            XCTAssertFalse(bundle.captionEvidence.contains(noise), "\(name): caption should strip noise \(noise)")
        }
    }

    func testDouyinNoisyShareTextNormalizesToSourceBundle() throws {
        try assertShareTextFixtureNormalizes("douyin-noisy-share-wuhan.json")
    }

    func testXiaohongshuShareBoilerplateNormalizesToSourceBundle() throws {
        try assertShareTextFixtureNormalizes("xhs-share-boilerplate.json")
    }

    func testShareTextNormalizerPrefersStructuredMapLinkAcrossMultipleURLs() {
        let bundle = SocialShareTextNormalizer.normalize(
            """
            看看這個 https://www.instagram.com/reel/DW2ZpyADbZ6/
            還有地圖 https://maps.app.goo.gl/AbCdEf123
            """
        )

        XCTAssertEqual(bundle.embeddedURLStrings.count, 2)
        XCTAssertEqual(bundle.primaryURLString, "https://maps.app.goo.gl/AbCdEf123")
        XCTAssertEqual(bundle.platform, .googleMaps)
        XCTAssertTrue(bundle.captionEvidence.contains("看看這個"))
    }

    func testShareTextNormalizerKeepsBareShortLinkAndURLLessPastes() {
        let bare = SocialShareTextNormalizer.normalize("http://xhslink.com/o/7FgwQfDuTc4")
        XCTAssertEqual(bare.primaryURLString, "http://xhslink.com/o/7FgwQfDuTc4")
        XCTAssertEqual(bare.platform, .xiaohongshu)
        XCTAssertTrue(bare.captionEvidence.isEmpty)

        let urlless = SocialShareTextNormalizer.normalize("今天天氣很好，沒有連結")
        XCTAssertNil(urlless.primaryURLString)
        XCTAssertFalse(urlless.hasResolvableURL)
        XCTAssertEqual(urlless.captionEvidence, "今天天氣很好，沒有連結")
    }

    func testCreatorWorkBracketTitleNeverBecomesVenueCandidate() {
        XCTAssertTrue(SocialPlaceEvidenceScorer.isRejectedTitle("金贵七七（环游中国版）的作品"))
        XCTAssertTrue(SocialPlaceEvidenceScorer.looksLikeShareBoilerplateText("9.41 复制打开抖音，看看"))
        XCTAssertFalse(SocialPlaceEvidenceScorer.isRejectedTitle("奢海陌野民宿"))

        let analysis = SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://v.douyin.com/abc123XYZ/",
                resolvedURL: nil,
                sharedTitle: nil,
                sharedText: "7.89 复制打开抖音，看看【小张美食日记的作品】这家咖啡店环境太好了 https://v.douyin.com/abc123XYZ/",
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )

        XCTAssertFalse(analysis.placesFound.contains { $0.displayName.hasSuffix("的作品") })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName.contains("复制打开") })
        XCTAssertFalse(analysis.placesFound.contains { $0.displayName.contains("http") })
        XCTAssertFalse(analysis.resolverDecision.allowsDirectSave)
    }

    func testSharedTextEntryWithoutURLNeverHardFails() async throws {
        let service = SocialLinkReviewCandidateService(
            googlePlacesService: EmptyGooglePlacesService(),
            publicSourceSearchService: StubPublicSourceSearchService()
        )

        let clueCandidates = await service.reviewCandidates(
            fromSharedText: """
            店名：牛喜壽喜燒
            地址：台北市士林區忠誠路二段200號3樓
            """
        )
        XCTAssertTrue(clueCandidates.contains { candidate in
            candidate.candidateName == "牛喜壽喜燒" && candidate.address.contains("台北市士林區忠誠路二段200號")
        })
        XCTAssertTrue(clueCandidates.allSatisfy { $0.latitude == nil && $0.longitude == nil })

        let vagueCandidates = await service.reviewCandidates(fromSharedText: "今天天氣很好，沒有連結")
        let vague = try XCTUnwrap(vagueCandidates.first)
        XCTAssertFalse(vague.hasReliableCoordinates)
        XCTAssertNil(vague.latitude)
        XCTAssertFalse(vague.candidateName.isEmpty)
        XCTAssertFalse(vague.evidenceDiagnostic?.nextBestClue.isEmpty ?? true)
    }

    func testGoogleMapsPlaceLinkBecomesMapMatchReadyCandidateWithURLCoordinates() {
        let service = SocialLinkReviewCandidateService(googlePlacesService: EmptyGooglePlacesService())

        let google = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://www.google.com/maps/place/Quarter+Sheets+Pizza+Club/@34.0779,-118.2543,17z/data=!3m1"
        )
        XCTAssertEqual(google.count, 1)
        XCTAssertEqual(google.first?.candidateName, "Quarter Sheets Pizza Club")
        XCTAssertEqual(google.first?.latitude, 34.0779)
        XCTAssertEqual(google.first?.longitude, -118.2543)
        XCTAssertEqual(google.first?.reviewState, "map_match_ready")
        XCTAssertEqual(google.first?.missingInfo, ["User confirmation required"])

        let apple = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://maps.apple.com/?q=Courage%20Bagels&ll=34.105,-118.287"
        )
        XCTAssertEqual(apple.first?.candidateName, "Courage Bagels")
        XCTAssertEqual(apple.first?.latitude, 34.105)
        XCTAssertEqual(apple.first?.longitude, -118.287)
        XCTAssertEqual(apple.first?.reviewState, "map_match_ready")
    }

    func testWesternMapLinkRejectsInvalidCoordinatesAndLookalikeHosts() {
        let service = SocialLinkReviewCandidateService(googlePlacesService: EmptyGooglePlacesService())

        let nanApple = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://maps.apple.com/?q=Fake%20Spot&ll=nan,nan"
        )
        XCTAssertNotEqual(nanApple.first?.reviewState, "map_match_ready")
        XCTAssertNil(nanApple.first?.latitude)

        let outOfRangeApple = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://maps.apple.com/?q=Fake%20Spot&ll=95.0,200.0"
        )
        XCTAssertNotEqual(outOfRangeApple.first?.reviewState, "map_match_ready")
        XCTAssertNil(outOfRangeApple.first?.latitude)

        let outOfRangeGoogle = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://www.google.com/maps/place/Fake+Spot/@999.0779,-118.2543,17z"
        )
        XCTAssertNotEqual(outOfRangeGoogle.first?.reviewState, "map_match_ready")

        let lookalikeHost = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://maps.google.evil.com/maps/place/Fake+Spot/@34.0779,-118.2543,17z"
        )
        XCTAssertNotEqual(lookalikeHost.first?.reviewState, "map_match_ready")
        XCTAssertNil(lookalikeHost.first?.latitude)
    }

    func testTikTokAndInstagramPostVariantsKeepDescriptorBackedSourceReceipts() {
        let service = SocialLinkReviewCandidateService(googlePlacesService: EmptyGooglePlacesService())

        let tiktokVideo = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://www.tiktok.com/@foodie/video/7301234567890123456"
        )
        XCTAssertEqual(tiktokVideo.first?.candidateName, "TikTok link")
        XCTAssertTrue(tiktokVideo.first?.isSourceOnly == true)
        XCTAssertTrue(tiktokVideo.first?.evidenceDiagnostic?.suggestedSearchQueries?.contains { $0.contains("7301234567890123456") } == true)

        let tiktokShort = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://vt.tiktok.com/ZS8abcdEf/"
        )
        XCTAssertEqual(tiktokShort.first?.candidateName, "TikTok link")
        XCTAssertTrue(tiktokShort.first?.isSourceOnly == true)

        let instagramPost = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: "",
            sourceURL: "https://www.instagram.com/p/DW2ZpyADbZ6/"
        )
        XCTAssertEqual(instagramPost.first?.candidateName, "Instagram link")
        XCTAssertTrue(instagramPost.first?.evidenceDiagnostic?.suggestedSearchQueries?.contains { $0.contains("DW2ZpyADbZ6") } == true)
    }

    func testGeminiTransportRetriesTransientUpstreamErrorBeforeFailingLinkParse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGeminiURLProtocol.self]
        StubGeminiURLProtocol.responses = [
            (statusCode: 429, body: "{}"),
            (statusCode: 200, body: #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#)
        ]
        StubGeminiURLProtocol.requestCount = 0

        var transport = SAVEGeminiTransport(
            modelFallbacks: ["gemini-test"],
            session: URLSession(configuration: config),
            accessTokenProvider: nil,
            directAPIKey: "test-key"
        )
        transport.transientRetryDelayNanoseconds = 0

        let json = try await transport.generateContent(body: ["contents": []])
        XCTAssertEqual(StubGeminiURLProtocol.requestCount, 2)
        XCTAssertNotNil(json["candidates"])
    }

}

private final class StubGeminiURLProtocol: URLProtocol {
    static var responses: [(statusCode: Int, body: String)] = []
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = min(Self.requestCount, max(Self.responses.count - 1, 0))
        Self.requestCount += 1
        let stub = Self.responses.indices.contains(index) ? Self.responses[index] : (statusCode: 500, body: "{}")
        let url = request.url ?? URL(string: "https://generativelanguage.googleapis.com")!
        guard let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
