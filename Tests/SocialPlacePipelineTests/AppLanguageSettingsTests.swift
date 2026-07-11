import Observation
import XCTest
@testable import SAVE

final class AppLanguageSettingsTests: XCTestCase {
    @MainActor
    func testTraditionalChineseSharedLabelsDoNotFallBackToEnglish() {
        XCTAssertEqual(PlaceCategory.cafe.displayName(language: .traditionalChinese), "咖啡")
        XCTAssertEqual(PlaceStatus.wantToGo.memoryCardLabel(language: .traditionalChinese), "地圖章")
        XCTAssertEqual(PlaceVisibility.publicGuide.displayName(language: .traditionalChinese), "公開指南")
        XCTAssertEqual(SaveSocialLens.trending.title(language: .traditionalChinese), "熱門")
        XCTAssertEqual(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: .traditionalChinese), "尚未保存")
        XCTAssertEqual(SaveSearchUserState.sourceOnly.displayName(language: .traditionalChinese), "還需要線索")
        XCTAssertTrue(AppLanguage.traditionalChinese.serviceOutputInstruction.contains("Map Stamp into natural Traditional Chinese"))
    }

    @MainActor
    func testEnglishSharedLabelsStayStable() {
        XCTAssertEqual(PlaceCategory.cafe.displayName(language: .english), "Cafe")
        XCTAssertEqual(PlaceStatus.wantToGo.memoryCardLabel(language: .english), "Map Stamp")
        XCTAssertEqual(PlaceVisibility.publicGuide.displayName(language: .english), "Public guide")
        XCTAssertEqual(SaveSocialLens.trending.title(language: .english), "Trending")
        XCTAssertEqual(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: .english), "Not saved yet")
        XCTAssertEqual(SaveSearchUserState.sourceOnly.displayName(language: .english), "Needs one more clue")
    }

    @MainActor
    func testMVPDrawerEntryCopyDoesNotPromoteTripPlanning() {
        XCTAssertEqual(
            SaveText.text(.askPlaceholder, language: .english),
            "Ask saved places or paste a spot..."
        )
        XCTAssertEqual(
            SaveText.text(.askPlaceholder, language: .traditionalChinese),
            "問你存過的地點，或貼上一個新地點..."
        )

        let englishSuggestions = SaveMVPDrawerEntryCopy.suggestions(language: .english)
        XCTAssertEqual(englishSuggestions, [
            "Paste a place link",
            "Search saved places",
            "Find boba from my saved places",
            "Review clues",
            "Open my map",
            "Share a place"
        ])
        XCTAssertFalse(englishSuggestions.contains { suggestion in
            suggestion.localizedCaseInsensitiveContains("plan") ||
                suggestion.localizedCaseInsensitiveContains("trip") ||
                suggestion.localizedCaseInsensitiveContains("itinerary")
        })

        let chineseSuggestions = SaveMVPDrawerEntryCopy.suggestions(language: .traditionalChinese)
        XCTAssertEqual(chineseSuggestions, [
            "貼上地點連結",
            "搜尋已保存地點",
            "從已保存地點找珍奶",
            "確認線索",
            "打開我的地圖",
            "分享一個地點"
        ])
        XCTAssertFalse(chineseSuggestions.contains { $0.contains("行程") || $0.contains("規劃") })
        XCTAssertTrue(SaveMVPDrawerEntryCopy.focusNote(language: .english).contains("place-memory loop"))
        XCTAssertTrue(SaveMVPDrawerEntryCopy.focusNote(language: .traditionalChinese).contains("地點記憶流程"))
    }

    @MainActor
    func testLanguageSettingsTracksObservationForEnvironmentConsumers() {
        let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let settings = AppLanguageSettings(userDefaults: userDefaults)
        settings.language = .english

        let invalidated = expectation(description: "language settings observation invalidated")
        withObservationTracking {
            _ = settings.text(.language)
        } onChange: {
            invalidated.fulfill()
        }

        settings.language = .traditionalChinese
        wait(for: [invalidated], timeout: 1)
        XCTAssertEqual(settings.text(.language), "語言")
        XCTAssertEqual(userDefaults.string(forKey: "save.appLanguage"), AppLanguage.traditionalChinese.rawValue)
    }
}
