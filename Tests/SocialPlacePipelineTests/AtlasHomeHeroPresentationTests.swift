import XCTest
@testable import SAVE

final class AtlasHomeHeroPresentationTests: XCTestCase {
    @MainActor
    func testMainlandChinaCityNamesSelectOwnedScenes() {
        let fixtures: [(String, Double, Double, AtlasHomeHeroPresentation.Scene)] = [
            ("北京市", 0, 0, .beijing),
            ("廣州市", 0, 0, .guangzhou),
            ("深圳市", 0, 0, .shenzhen),
            ("成都市", 0, 0, .chengdu),
            ("重慶市", 0, 0, .chongqing),
            ("天津市", 0, 0, .tianjin),
            ("杭州市", 0, 0, .hangzhou),
            ("南京市", 0, 0, .nanjing),
            ("武漢市", 0, 0, .wuhan),
            ("西安市", 0, 0, .xian),
            ("蘇州市", 0, 0, .suzhou),
            ("青島市", 0, 0, .qingdao),
            ("廈門市", 0, 0, .xiamen),
            ("長沙市", 0, 0, .changsha),
        ]

        for (title, latitude, longitude, expectedScene) in fixtures {
            let hero = AtlasHomeHeroPresentation.currentRegion(
                title: title,
                subtitle: "China",
                countryCode: "CN",
                latitude: latitude,
                longitude: longitude
            )

            XCTAssertEqual(hero.scene, expectedScene)
        }
    }

    @MainActor
    func testMainlandChinaCoordinatesSelectOwnedScenes() {
        let fixtures: [(Double, Double, AtlasHomeHeroPresentation.Scene)] = [
            (39.9042, 116.4074, .beijing),
            (23.1291, 113.2644, .guangzhou),
            (22.5431, 114.0579, .shenzhen),
            (30.5728, 104.0668, .chengdu),
            (29.5630, 106.5516, .chongqing),
            (39.0851, 117.1994, .tianjin),
            (30.2741, 120.1551, .hangzhou),
            (32.0603, 118.7969, .nanjing),
            (30.5928, 114.3055, .wuhan),
            (34.3416, 108.9398, .xian),
            (31.2989, 120.5853, .suzhou),
            (36.0671, 120.3826, .qingdao),
            (24.4798, 118.0894, .xiamen),
            (28.2282, 112.9388, .changsha),
        ]

        for (latitude, longitude, expectedScene) in fixtures {
            let hero = AtlasHomeHeroPresentation.currentRegion(
                title: "Around you",
                subtitle: "China",
                countryCode: "CN",
                latitude: latitude,
                longitude: longitude
            )

            XCTAssertEqual(hero.scene, expectedScene)
        }
    }

    @MainActor
    func testNearbyUnsupportedCitiesKeepRegionalMapFallback() {
        let fixtures: [(String, Double, Double)] = [
            ("Foshan", 23.0215, 113.1214),
            ("Dongguan", 23.0207, 113.7518),
            ("Jinan", 36.6512, 117.1201),
            ("Wuxi", 31.4912, 120.3119),
            ("Ningbo", 29.8683, 121.5440),
            ("Hefei", 31.8206, 117.2272),
            ("Zhengzhou", 34.7466, 113.6254),
        ]

        for (title, latitude, longitude) in fixtures {
            let hero = AtlasHomeHeroPresentation.currentRegion(
                title: title,
                subtitle: "China",
                countryCode: "CN",
                latitude: latitude,
                longitude: longitude
            )

            XCTAssertEqual(hero.scene, .regionalMap)
        }
    }
}
