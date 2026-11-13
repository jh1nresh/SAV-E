import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPPreviewConfigurationTests: XCTestCase {
    func testOrdinaryAndReadOnlyInspectionChooseTheIntegratedPreview() {
        XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments:[],unitTestHost:false),.preview)
        XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments:["app","--inspect-citylab"],unitTestHost:false),.preview)
        XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments:["app","-AppleLanguages","(en)"],unitTestHost:false),.preview)
    }
    func testAllExistingVerificationComparisonsStayExplicit() {
        for flag in ["--verify-xinyi","--verify-native-ground-owner","--verify-context-labels","--verify-solid-reveal-preview"] {
            XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments:["app",flag],unitTestHost:false),.comparison,flag)
        }
        XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments:["app","--citylab-legacy-renderer"],unitTestHost:false),.comparison)
    }
    func testUnitHostDoesNotChangeHistoricalStaticFeatureAssumptions() {
        XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments:[],unitTestHost:true),.comparison)
        XCTAssertEqual(CityMVPPreviewConfiguration.selectedRoute,.comparison)
        XCTAssertFalse(CityMVPPreviewConfiguration.enabled)
        XCTAssertFalse(CitySceneView.usesOpaqueReveal)
        XCTAssertFalse(CityContextBuildings.enabled)
        XCTAssertFalse(CityContextPlace.enabled)
    }
}
