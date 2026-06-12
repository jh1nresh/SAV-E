import Combine
import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    func localized(english: String, traditionalChinese: String) -> String {
        switch self {
        case .english:
            return english
        case .traditionalChinese:
            return traditionalChinese
        }
    }

    var serviceOutputInstruction: String {
        switch self {
        case .english:
            return "English"
        case .traditionalChinese:
            return "Traditional Chinese (zh-Hant). Use natural Taiwanese Traditional Chinese. Keep the SAV-E brand name unchanged, but translate product concepts such as Map Stamp into natural Traditional Chinese."
        }
    }
}

@Observable
final class AppLanguageSettings: ObservableObject {
    @ObservationIgnored private let storageKey = "save.appLanguage"
    @ObservationIgnored private let userDefaults: UserDefaults

    var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: storageKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedLanguage = userDefaults.string(forKey: storageKey)
        self.language = AppLanguage(rawValue: storedLanguage ?? "") ?? Self.defaultLanguageFromLocale()
    }

    private static func defaultLanguageFromLocale() -> AppLanguage {
        Locale.preferredLanguages.contains { $0.hasPrefix("zh") } ? .traditionalChinese : .english
    }

    func text(_ key: SaveTextKey) -> String {
        SaveText.text(key, language: language)
    }

    func localized(english: String, traditionalChinese: String) -> String {
        language.localized(english: english, traditionalChinese: traditionalChinese)
    }

    func memoWaitingText(_ count: Int) -> String {
        switch language {
        case .english:
            return count == 1 ? "SAV-E has 1 clue waiting" : "SAV-E has \(count) clues waiting"
        case .traditionalChinese:
            return count == 1 ? "SAV-E 有 1 個線索等你確認" : "SAV-E 有 \(count) 個線索等你確認"
        }
    }

    func savedCountText(_ count: Int) -> String {
        switch language {
        case .english:
            return "\(count) Map Stamps"
        case .traditionalChinese:
            return "\(count) 個地圖章"
        }
    }

    func visitedCountText(_ count: Int) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 visited place" : "\(count) visited places"
        case .traditionalChinese:
            return "\(count) 個去過地點"
        }
    }

    func proofBackedCountText(_ count: Int) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 proof-backed place" : "\(count) proof-backed places"
        case .traditionalChinese:
            return "\(count) 個有憑證地點"
        }
    }

    func cityCountText(_ count: Int) -> String {
        switch language {
        case .english:
            return "\(count) city stamps"
        case .traditionalChinese:
            return "\(count) 個城市章"
        }
    }

    func waitingPlaceText(_ count: Int) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 maybe place" : "\(count) maybe places"
        case .traditionalChinese:
            return count == 1 ? "1 個待確認地點" : "\(count) 個待確認地點"
        }
    }
}

private struct AppLanguageSettingsKey: EnvironmentKey {
    static let defaultValue = AppLanguageSettings()
}

extension EnvironmentValues {
    var appLanguageSettings: AppLanguageSettings {
        get { self[AppLanguageSettingsKey.self] }
        set { self[AppLanguageSettingsKey.self] = newValue }
    }
}

enum SaveTextKey {
    case appName
    case opening
    case openingHint
    case tripLinkReady
    case tripLinkMessage
    case ok
    case cantSignIn
    case googleNotEnabled
    case googleNotEnabledMessage
    case appNotAllowed
    case appNotAllowedMessage
    case authSetupNeeded
    case genericSignInError
    case continueWithGoogle
    case orUseEmail
    case emailAddress
    case sendCode
    case verificationCode
    case verify
    case signInTagline
    case signInDescription
    case capture
    case captureSubtitle
    case review
    case reviewSubtitle
    case save
    case saveSubtitle
    case profileTitle
    case edit
    case editPassport
    case editPassportDescription
    case saving
    case passportName
    case name
    case accountManagedByLogin
    case localMemoHelper
    case memoHelper
    case reviewFirst
    case editPassportAccessibility
    case passportStamps
    case memoBook
    case memoryCards
    case visited
    case proofBacked
    case cities
    case waitingClues
    case memberSince
    case passportControls
    case localMemory
    case language
    case chooseLanguage
    case languageDescription
    case signOut
    case askPlaceholder
    case openReviewCandidates
    case memoSorting
    case cancel
    case back
    case tryAgain
    case backToCommands
    case closeDrawerContent
    case thinking
    case answer
    case couldntFinish
    case commands
    case loadingSubtitle
    case answerSubtitle
    case placeDetailSubtitle
    case errorSubtitle
}

enum SaveText {
    static func text(_ key: SaveTextKey, language: AppLanguage) -> String {
        switch key {
        case .appName:
            return "SAV-E"
        case .opening:
            return localized(english: "Opening SAV-E", traditionalChinese: "正在打開 SAV-E", language: language)
        case .openingHint:
            return localized(english: "Waking up your place memory", traditionalChinese: "整理你的地點記憶", language: language)
        case .tripLinkReady:
            return localized(english: "Trip Preview Parked", traditionalChinese: "行程預覽暫不開放", language: language)
        case .tripLinkMessage:
            return localized(english: "%@ has %d stops. Full trip import is outside this public test; save individual places as Map Stamps for now.", traditionalChinese: "「%@」有 %d 個地點。完整行程匯入不在這次 public test 內；目前請先把單一地點保存成地圖章。", language: language)
        case .ok:
            return localized(english: "OK", traditionalChinese: "好", language: language)
        case .cantSignIn:
            return localized(english: "Can't Sign In", traditionalChinese: "無法登入", language: language)
        case .googleNotEnabled:
            return localized(english: "Google Isn't Enabled", traditionalChinese: "Google 登入尚未啟用", language: language)
        case .googleNotEnabledMessage:
            return localized(english: "Turn on Google in Privy, or use email sign-in for now.", traditionalChinese: "請在 Privy 啟用 Google，或先用電子信箱登入。", language: language)
        case .appNotAllowed:
            return localized(english: "App Not Allowed", traditionalChinese: "App 尚未允許", language: language)
        case .appNotAllowedMessage:
            return localized(english: "Add com.wanderly.app to the allowed app identifiers in Privy.", traditionalChinese: "請把 com.wanderly.app 加到 Privy 允許的 app identifiers。", language: language)
        case .authSetupNeeded:
            return localized(english: "Auth Setup Needed", traditionalChinese: "需要設定登入", language: language)
        case .genericSignInError:
            return localized(english: "Something went wrong. Try again in a moment.", traditionalChinese: "剛剛沒成功，請稍後再試一次。", language: language)
        case .continueWithGoogle:
            return localized(english: "Continue with Google", traditionalChinese: "使用 Google 繼續", language: language)
        case .orUseEmail:
            return localized(english: "or use email", traditionalChinese: "或用電子信箱", language: language)
        case .emailAddress:
            return localized(english: "Email address", traditionalChinese: "電子信箱", language: language)
        case .sendCode:
            return localized(english: "Send Code", traditionalChinese: "寄出驗證碼", language: language)
        case .verificationCode:
            return localized(english: "Verification code", traditionalChinese: "驗證碼", language: language)
        case .verify:
            return localized(english: "Verify", traditionalChinese: "驗證", language: language)
        case .signInTagline:
            return localized(english: "Your private place memory.", traditionalChinese: "你的私人地點記憶。", language: language)
        case .signInDescription:
            return localized(english: "Drop in a place clue. SAV-E keeps the source, asks before saving, then helps you decide later.", traditionalChinese: "丟進一個地點線索。SAV-E 會保留來源、先讓你確認，之後再幫你做決定。", language: language)
        case .capture:
            return localized(english: "Capture", traditionalChinese: "收進來", language: language)
        case .captureSubtitle:
            return localized(english: "link or media", traditionalChinese: "連結、貼文、截圖", language: language)
        case .review:
            return localized(english: "Review", traditionalChinese: "確認", language: language)
        case .reviewSubtitle:
            return localized(english: "with evidence", traditionalChinese: "看證據再存", language: language)
        case .save:
            return localized(english: "Save", traditionalChinese: "存下", language: language)
        case .saveSubtitle:
            return localized(english: "Map Stamps", traditionalChinese: "變成地圖章", language: language)
        case .profileTitle:
            return localized(english: "SAV-E Passport", traditionalChinese: "SAV-E 護照", language: language)
        case .edit:
            return localized(english: "Edit", traditionalChinese: "編輯", language: language)
        case .editPassport:
            return localized(english: "Edit Passport", traditionalChinese: "編輯護照", language: language)
        case .editPassportDescription:
            return localized(english: "This is how SAV-E labels your memory book.", traditionalChinese: "這個名稱會顯示在你的 SAV-E 記憶本上。", language: language)
        case .saving:
            return localized(english: "Saving...", traditionalChinese: "儲存中...", language: language)
        case .passportName:
            return localized(english: "PASSPORT NAME", traditionalChinese: "護照名稱", language: language)
        case .name:
            return localized(english: "Name", traditionalChinese: "名稱", language: language)
        case .accountManagedByLogin:
            return localized(english: "Email and sign-in provider stay managed by your login account.", traditionalChinese: "電子信箱與登入方式仍由你的登入帳號管理。", language: language)
        case .localMemoHelper:
            return localized(english: "Local Memo helper", traditionalChinese: "本機 Memo 小助手", language: language)
        case .memoHelper:
            return localized(english: "MEMO HELPER", traditionalChinese: "MEMO 助手", language: language)
        case .reviewFirst:
            return localized(english: "REVIEW FIRST", traditionalChinese: "先確認", language: language)
        case .editPassportAccessibility:
            return localized(english: "Edit Passport", traditionalChinese: "編輯護照", language: language)
        case .passportStamps:
            return localized(english: "Passport Stamps", traditionalChinese: "護照印章", language: language)
        case .memoBook:
            return localized(english: "MEMO BOOK", traditionalChinese: "MEMO 記憶本", language: language)
        case .memoryCards:
            return localized(english: "Memory cards", traditionalChinese: "地點記憶", language: language)
        case .visited:
            return localized(english: "Visited", traditionalChinese: "去過", language: language)
        case .proofBacked:
            return localized(english: "Proof-backed", traditionalChinese: "有憑證", language: language)
        case .cities:
            return localized(english: "Cities", traditionalChinese: "城市", language: language)
        case .waitingClues:
            return localized(english: "Waiting clues", traditionalChinese: "等你確認", language: language)
        case .memberSince:
            return localized(english: "Member since", traditionalChinese: "加入時間", language: language)
        case .passportControls:
            return localized(english: "Passport Controls", traditionalChinese: "護照設定", language: language)
        case .localMemory:
            return localized(english: "Local Memory", traditionalChinese: "本機記憶", language: language)
        case .language:
            return localized(english: "Language", traditionalChinese: "語言", language: language)
        case .chooseLanguage:
            return localized(english: "Choose Language", traditionalChinese: "選擇語言", language: language)
        case .languageDescription:
            return localized(english: "SAV-E will use this language inside the app.", traditionalChinese: "SAV-E 會在 app 內使用你選的語言。", language: language)
        case .signOut:
            return localized(english: "Sign Out", traditionalChinese: "登出", language: language)
        case .askPlaceholder:
            return localized(english: "Ask saved places or paste a spot...", traditionalChinese: "問你存過的地點，或貼上一個新地點...", language: language)
        case .openReviewCandidates:
            return localized(english: "Open review candidates", traditionalChinese: "查看待確認地點", language: language)
        case .memoSorting:
            return localized(english: "SAV-E is sorting the clues...", traditionalChinese: "SAV-E 正在整理線索...", language: language)
        case .cancel:
            return localized(english: "Cancel", traditionalChinese: "取消", language: language)
        case .back:
            return localized(english: "Back", traditionalChinese: "返回", language: language)
        case .tryAgain:
            return localized(english: "Try again", traditionalChinese: "再試一次", language: language)
        case .backToCommands:
            return localized(english: "Back to commands", traditionalChinese: "回到指令", language: language)
        case .closeDrawerContent:
            return localized(english: "Close drawer content", traditionalChinese: "關閉抽屜", language: language)
        case .thinking:
            return localized(english: "Thinking", traditionalChinese: "思考中", language: language)
        case .answer:
            return localized(english: "Answer", traditionalChinese: "回答", language: language)
        case .couldntFinish:
            return localized(english: "Couldn’t finish", traditionalChinese: "剛剛沒完成", language: language)
        case .commands:
            return localized(english: "Commands", traditionalChinese: "指令", language: language)
        case .loadingSubtitle:
            return localized(english: "You can cancel and keep using SAV-E.", traditionalChinese: "你可以取消，繼續使用 SAV-E。", language: language)
        case .answerSubtitle:
            return localized(english: "Back returns to commands.", traditionalChinese: "返回會回到指令列表。", language: language)
        case .placeDetailSubtitle:
            return localized(english: "Back returns to your command drawer.", traditionalChinese: "返回會回到 SAV-E 抽屜。", language: language)
        case .errorSubtitle:
            return localized(english: "Try again or return to commands.", traditionalChinese: "你可以再試一次，或回到指令列表。", language: language)
        }
    }

    private static func localized(english: String, traditionalChinese: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            return english
        case .traditionalChinese:
            return traditionalChinese
        }
    }
}

enum SaveMVPDrawerEntryCopy {
    static func suggestions(language: AppLanguage) -> [String] {
        switch language {
        case .english:
            return [
                "Paste a place link",
                "Search saved places",
                "Find boba from my saved places",
                "Review clues",
                "Open my map",
                "Share a place"
            ]
        case .traditionalChinese:
            return [
                "貼上地點連結",
                "搜尋已保存地點",
                "從已保存地點找珍奶",
                "確認線索",
                "打開我的地圖",
                "分享一個地點"
            ]
        }
    }

    static func focusNote(language: AppLanguage) -> String {
        language.localized(
            english: "MVP focus: capture place clues, review evidence, save Map Stamps, then search, recommend, open, or share from your saved memory. Full itinerary planning stays in the background until the place-memory loop is reliable.",
            traditionalChinese: "MVP 主線：收進地點線索、檢查證據、保存成地圖章，再從已保存記憶搜尋、推薦、開地圖或分享。完整行程規劃先退到背景，等地點記憶流程穩定後再推。"
        )
    }
}
