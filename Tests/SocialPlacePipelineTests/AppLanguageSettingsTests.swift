import XCTest
@testable import SAVE

final class AppLanguageSettingsTests: XCTestCase {
    func testTraditionalChineseSharedLabelsDoNotFallBackToEnglish() {
        XCTAssertEqual(PlaceCategory.cafe.displayName(language: .traditionalChinese), "咖啡")
        XCTAssertEqual(PlaceStatus.wantToGo.memoryCardLabel(language: .traditionalChinese), "地圖章")
        XCTAssertEqual(PlaceVisibility.publicGuide.displayName(language: .traditionalChinese), "公開指南")
        XCTAssertEqual(SaveSocialLens.trending.title(language: .traditionalChinese), "熱門")
        XCTAssertEqual(PlaceFilter.wantToGo.title(language: .traditionalChinese), "想去")
        XCTAssertEqual(PlaceSort.nearest.title(language: .traditionalChinese), "最近距離")
        XCTAssertEqual(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: .traditionalChinese), "尚未保存")
        XCTAssertEqual(SaveSearchUserState.sourceOnly.displayName(language: .traditionalChinese), "還需要線索")
        XCTAssertTrue(AppLanguage.traditionalChinese.serviceOutputInstruction.contains("Map Stamp into natural Traditional Chinese"))
    }

    func testEnglishSharedLabelsStayStable() {
        XCTAssertEqual(PlaceCategory.cafe.displayName(language: .english), "Cafe")
        XCTAssertEqual(PlaceStatus.wantToGo.memoryCardLabel(language: .english), "Map Stamp")
        XCTAssertEqual(PlaceVisibility.publicGuide.displayName(language: .english), "Public guide")
        XCTAssertEqual(SaveSocialLens.trending.title(language: .english), "Trending")
        XCTAssertEqual(PlaceFilter.wantToGo.title(language: .english), "Want to Go")
        XCTAssertEqual(PlaceSort.nearest.title(language: .english), "Nearest")
        XCTAssertEqual(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: .english), "Not saved yet")
        XCTAssertEqual(SaveSearchUserState.sourceOnly.displayName(language: .english), "Needs one more clue")
    }
}
