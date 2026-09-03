import Observation
import XCTest
@testable import SAVE

final class AppLanguageSettingsTests: XCTestCase {
    @MainActor
    func testTraditionalChineseSharedLabelsDoNotFallBackToEnglish() {
        XCTAssertEqual(PlaceCategory.cafe.displayName(language: .traditionalChinese), "咖啡")
        XCTAssertEqual(PlaceStatus.wantToGo.memoryCardLabel(language: .traditionalChinese), "地圖章")
        XCTAssertEqual(PlaceVisibility.publicGuide.displayName(language: .traditionalChinese), "分享推薦")
        XCTAssertEqual(SaveSocialLens.trending.title(language: .traditionalChinese), "熱門")
        XCTAssertEqual(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: .traditionalChinese), "尚未保存")
        XCTAssertEqual(SaveSearchUserState.sourceOnly.displayName(language: .traditionalChinese), "還需要線索")
        XCTAssertTrue(AppLanguage.traditionalChinese.serviceOutputInstruction.contains("Map Stamp into natural Traditional Chinese"))
    }

    @MainActor
    func testEnglishSharedLabelsStayStable() {
        XCTAssertEqual(PlaceCategory.cafe.displayName(language: .english), "Cafe")
        XCTAssertEqual(PlaceStatus.wantToGo.memoryCardLabel(language: .english), "Map Stamp")
        XCTAssertEqual(PlaceVisibility.publicGuide.displayName(language: .english), "Share recommendation")
        XCTAssertEqual(SaveSocialLens.trending.title(language: .english), "Trending")
        XCTAssertEqual(SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: .english), "Not saved yet")
        XCTAssertEqual(SaveSearchUserState.sourceOnly.displayName(language: .english), "Needs one more clue")
    }

    @MainActor
    func testCommunityRecommendationUsesPlaceFactsInsteadOfPrivateNote() {
        var place = recommendationPlace()
        place.note = "Private note: surprise birthday dinner"

        XCTAssertEqual(place.originRecommendationSummary, place.address)
    }

    @MainActor
    func testCommunityRecommendationHasSavvyOwnedSignalCopy() {
        let signal = recommendationPlace().socialSignal

        XCTAssertEqual(signal?.kind, .communityRecommendation)
        XCTAssertEqual(signal?.displayText, "Shared by Mina")
        XCTAssertEqual(signal?.kind.pinSystemImage, "person.crop.circle.badge.checkmark")
    }

    @MainActor
    func testMVPDrawerEntryCopyDoesNotPromoteTripPlanning() {
        XCTAssertEqual(
            SaveText.text(.askPlaceholder, language: .english),
            "Paste a link or ask about saved places..."
        )
        XCTAssertEqual(
            SaveText.text(.askPlaceholder, language: .traditionalChinese),
            "貼上連結，或問你收藏的地點..."
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

    @MainActor
    private func recommendationPlace() -> Place {
        Place(
            id: UUID(uuidString: "7B095461-6957-4C5B-9F43-0C6D9A2F459A")!,
            name: "Koffee Mameya",
            address: "Shibuya City, Tokyo",
            latitude: 35.665,
            longitude: 139.710,
            category: .cafe,
            status: .wantToGo,
            note: nil,
            sourceUrl: "https://www.instagram.com/p/example/?utm_source=test",
            sourcePlatform: .instagram,
            priceRange: "$$",
            recommender: "Mina",
            googleRating: 4.6,
            createdAt: Date(timeIntervalSince1970: 1_721_865_600),
            visibility: .publicGuide,
            socialSignal: PlaceSocialSignal(
                kind: .communityRecommendation,
                lens: .forYou,
                friendNames: [],
                friendCount: 0,
                saveCount: 0,
                trendingRank: nil,
                categoryRank: nil,
                sourceLabel: "Mina",
                referrerId: "user-2",
                referralCode: nil
            )
        )
    }
}
