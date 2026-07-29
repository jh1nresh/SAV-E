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
            ("Tianjin", 39.0851, 117.1994),
            ("Foshan", 23.0215, 113.1214),
            ("Dongguan", 23.0207, 113.7518),
            ("Chongqing", 29.4316, 106.9123),
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
