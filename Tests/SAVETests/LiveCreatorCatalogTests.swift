#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
@testable import SAVE

@MainActor
final class LiveCreatorCatalogTests: XCTestCase {
    private let screenshotAddress = "中国台湾省台北市文山区116台湾臺北市文山區景華里景美街5巷2号之1号"
    private var entry: LiveCreatorCatalog.Entry {
        .init(cid: "16341536244857936202", name: "十一香牛肉麵（景美店）",
              address: "臺北市文山區景華里景美街5巷2之1號", latitude: 24.993245, longitude: 121.541764,
              placeId: "poi/node/4033359736", lists: ["visited"], aliases: [], matchedPlaces: [],
              posts: [.init(url: "https://www.threads.com/@zeke_6973/post/Dd_T2fQAXTU", text: "", date: "", author: "zeke_6973")])
    }
    private var catalog: LiveCreatorCatalog {
        .init(schemaVersion: 1, scope: "local_creator_preview", creator: "zeke_6973", entries: [entry])
    }
    func testScreenshotAddressIsReadableWithoutChangingStoredAddress() {
        let place = fixture()
        XCTAssertEqual(LivePlaceAddress.display(place.address), "台北市文山區景美街5巷2之1號")
        XCTAssertEqual(place.address, screenshotAddress)
    }
    func testSimplifiedSearchResultMatchesExactJingmeiBranch() {
        XCTAssertEqual(catalog.match(fixture())?.cid, entry.cid)
        XCTAssertEqual(catalog.match(fixture())?.posts.count, 1)
    }
    func testNearbyWrongBranchHouseFloorAndDistrictCannotInheritSources() {
        for address in [
            "中国台湾省台北市文山区116台湾臺北市文山區明义里木栅路二段66号",
            "台北市文山區景美街5巷2之2號", "台北市文山區景美街5巷2之1號2樓",
            "台北市大安區景美街5巷2之1號",
            "台北市大安區116台灣台北市文山區景美街5巷2之1號"
        ] {
            var place = fixture(); place.address = address
            XCTAssertNil(catalog.match(place), address)
        }
    }
    func testUnrelatedNameOrDistantCoordinatesCannotInheritSources() {
        var place = fixture(); place.name = "十一香牛肉面馆"
        XCTAssertNil(catalog.match(place))
        place = fixture(); place.latitude += 0.01
        XCTAssertNil(catalog.match(place))
    }
    func testAmbiguousBranchDoesNotChooseFirstResult() {
        let duplicated = LiveCreatorCatalog(schemaVersion: 1, scope: "local_creator_preview", creator: "zeke_6973", entries: [entry, entry])
        XCTAssertNil(duplicated.match(fixture()))
    }
    func testOtherRegionsAreNotRewritten() {
        for raw in ["東京都新宿区西新宿2-8-1", "中国广东省深圳市南山区", "123 Main St, Springfield"] {
            XCTAssertEqual(LivePlaceAddress.display(raw), raw)
        }
    }
    func testObservedNativeJingmeiResultAttachesThreeOriginalsWithoutMovingPlace() throws {
        let catalog = LiveCreatorCatalog.shared
        XCTAssertTrue(catalog.valid)
        let row = try XCTUnwrap(catalog.entry(placeId: "poi/node/4033359736"))
        let observations = try XCTUnwrap(row.matchedPlaces).filter { $0.provider != nil }
        XCTAssertEqual(observations.count, 2, "Both observed languages must be packaged")
        for observed in observations {
            var place = fixture()
            place.name = observed.name; place.address = observed.address
            place.latitude = observed.latitude; place.longitude = observed.longitude
            place.locationProvider = .appleMaps; place.providerPlaceId = observed.providerPlaceId
            let match = try XCTUnwrap(catalog.match(place))
            XCTAssertEqual(match.cid, row.cid)
            XCTAssertEqual(Set(match.posts.map(\.url)), Set([
                "https://www.threads.com/@zeke_6973/post/Dd_T2fQAXTU",
                "https://www.threads.com/@zeke_6973/post/DfEObM2ID6l",
                "https://www.threads.com/@zeke_6973/post/DfEPZk4IGxq"]))
            XCTAssertEqual(place.latitude, 24.990345)
            XCTAssertEqual(match.latitude, 24.993245)
            var wrong = place; wrong.providerPlaceId = "H2710I3F9ADA23A5F03"
            XCTAssertNil(catalog.match(wrong), "Wrong native identity")
            wrong = place; wrong.providerPlaceId = nil
            XCTAssertNil(catalog.match(wrong), "Identity required for offset observation")
            wrong = place; wrong.address += "2樓"
            XCTAssertNil(catalog.match(wrong), "Wrong floor")
            wrong = place; wrong.latitude += 0.01
            XCTAssertNil(catalog.match(wrong), "Observed location still bounded to 65m")
        }
        var muzha = fixture()
        muzha.name = "十一香牛肉面馆"
        muzha.address = "中国台湾省台北市文山区116台湾台北市文山区明义里木栅路二段66号"
        muzha.latitude = 24.985691; muzha.longitude = 121.563118
        muzha.locationProvider = .appleMaps; muzha.providerPlaceId = "H2710I3F9ADA23A5F03"
        XCTAssertNil(catalog.match(muzha))
    }
    private func fixture() -> Place {
        Place(id: UUID(), name: "十一香牛肉面 (景美店)", address: screenshotAddress,
              latitude: entry.latitude, longitude: entry.longitude,
              googlePlaceId: nil, category: .food, status: .wantToGo, rating: nil, note: nil,
              sourceUrl: nil, sourcePlatform: .other, coordinateSystem: .wgs84,
              sourceImageUrl: nil, businessPhotoUrls: nil, extractedDishes: nil, priceRange: nil,
              recommender: nil, googleRating: nil, googlePriceLevel: nil, openingHours: nil, createdAt: .now)
    }
}
#endif
