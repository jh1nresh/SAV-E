import Combine
import Foundation

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
}

final class AppLanguageSettings: ObservableObject {
    private let storageKey = "save.appLanguage"
    private let userDefaults: UserDefaults

    @Published var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: storageKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedLanguage = userDefaults.string(forKey: storageKey)
        self.language = AppLanguage(rawValue: storedLanguage ?? "") ?? .english
    }

    func text(_ key: SaveTextKey) -> String {
        SaveText.text(key, language: language)
    }

    func memoWaitingText(_ count: Int) -> String {
        switch language {
        case .english:
            return count == 1 ? "Memo has 1 clue waiting" : "Memo has \(count) clues waiting"
        case .traditionalChinese:
            return count == 1 ? "Memo 有 1 個線索待確認" : "Memo 有 \(count) 個線索待確認"
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

    func verifiedCountText(_ count: Int) -> String {
        switch language {
        case .english:
            return "\(count) ready to plan"
        case .traditionalChinese:
            return "\(count) 個可規劃"
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

enum SaveTextKey {
    case appName
    case opening
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
    case verified
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
            return localized(english: "Opening SAV-E", traditionalChinese: "正在開啟 SAV-E", language: language)
        case .tripLinkReady:
            return localized(english: "Trip Link Ready", traditionalChinese: "行程連結已準備好", language: language)
        case .tripLinkMessage:
            return localized(english: "%@ has %d stops. Full trip import is coming next.", traditionalChinese: "%@ 有 %d 個停靠點。完整行程匯入會在下一版補上。", language: language)
        case .ok:
            return localized(english: "OK", traditionalChinese: "好", language: language)
        case .cantSignIn:
            return localized(english: "Can't Sign In", traditionalChinese: "無法登入", language: language)
        case .googleNotEnabled:
            return localized(english: "Google Isn't Enabled", traditionalChinese: "Google 登入尚未啟用", language: language)
        case .googleNotEnabledMessage:
            return localized(english: "Turn on Google in Privy, or use email sign-in for now.", traditionalChinese: "請在 Privy 啟用 Google，或先使用 Email 登入。", language: language)
        case .appNotAllowed:
            return localized(english: "App Not Allowed", traditionalChinese: "App 尚未允許", language: language)
        case .appNotAllowedMessage:
            return localized(english: "Add com.wanderly.app to the allowed app identifiers in Privy.", traditionalChinese: "請把 com.wanderly.app 加到 Privy 允許的 app identifiers。", language: language)
        case .authSetupNeeded:
            return localized(english: "Auth Setup Needed", traditionalChinese: "需要設定登入", language: language)
        case .genericSignInError:
            return localized(english: "Something went wrong. Try again in a moment.", traditionalChinese: "發生錯誤，請稍後再試。", language: language)
        case .continueWithGoogle:
            return localized(english: "Continue with Google", traditionalChinese: "使用 Google 繼續", language: language)
        case .orUseEmail:
            return localized(english: "or use email", traditionalChinese: "或使用 Email", language: language)
        case .emailAddress:
            return localized(english: "Email address", traditionalChinese: "Email 地址", language: language)
        case .sendCode:
            return localized(english: "Send Code", traditionalChinese: "寄送驗證碼", language: language)
        case .verificationCode:
            return localized(english: "Verification code", traditionalChinese: "驗證碼", language: language)
        case .verify:
            return localized(english: "Verify", traditionalChinese: "驗證", language: language)
        case .signInTagline:
            return localized(english: "Your personal place memory.", traditionalChinese: "你的個人地點記憶庫。", language: language)
        case .signInDescription:
            return localized(english: "Drop in links, posts, screenshots, notes, or maps. Memo helps SAV-E turn them into reviewable place cards.", traditionalChinese: "丟進連結、貼文、截圖、筆記或地圖，Memo 會幫 SAV-E 轉成可確認的地點卡。", language: language)
        case .capture:
            return localized(english: "Capture", traditionalChinese: "捕捉", language: language)
        case .captureSubtitle:
            return localized(english: "link or media", traditionalChinese: "連結或媒體", language: language)
        case .review:
            return localized(english: "Review", traditionalChinese: "確認", language: language)
        case .reviewSubtitle:
            return localized(english: "with evidence", traditionalChinese: "保留證據", language: language)
        case .save:
            return localized(english: "Save", traditionalChinese: "儲存", language: language)
        case .saveSubtitle:
            return localized(english: "Map Stamps", traditionalChinese: "地圖章", language: language)
        case .profileTitle:
            return localized(english: "SAV-E Passport", traditionalChinese: "SAV-E 護照", language: language)
        case .edit:
            return localized(english: "Edit", traditionalChinese: "編輯", language: language)
        case .editPassport:
            return localized(english: "Edit Passport", traditionalChinese: "編輯護照", language: language)
        case .editPassportDescription:
            return localized(english: "This is how SAV-E labels your memory book.", traditionalChinese: "這會顯示在你的 SAV-E 記憶本上。", language: language)
        case .saving:
            return localized(english: "Saving...", traditionalChinese: "儲存中...", language: language)
        case .passportName:
            return localized(english: "PASSPORT NAME", traditionalChinese: "護照名稱", language: language)
        case .name:
            return localized(english: "Name", traditionalChinese: "名稱", language: language)
        case .accountManagedByLogin:
            return localized(english: "Email and sign-in provider stay managed by your login account.", traditionalChinese: "Email 與登入方式仍由你的登入帳號管理。", language: language)
        case .localMemoHelper:
            return localized(english: "Local Memo helper", traditionalChinese: "本機 Memo 助手", language: language)
        case .memoHelper:
            return localized(english: "MEMO HELPER", traditionalChinese: "MEMO 助手", language: language)
        case .reviewFirst:
            return localized(english: "REVIEW FIRST", traditionalChinese: "先確認", language: language)
        case .editPassportAccessibility:
            return localized(english: "Edit Passport", traditionalChinese: "編輯護照", language: language)
        case .passportStamps:
            return localized(english: "Passport Stamps", traditionalChinese: "護照印章", language: language)
        case .memoBook:
            return localized(english: "MEMO BOOK", traditionalChinese: "MEMO 本", language: language)
        case .memoryCards:
            return localized(english: "Memory cards", traditionalChinese: "記憶卡", language: language)
        case .verified:
            return localized(english: "Verified", traditionalChinese: "已確認", language: language)
        case .cities:
            return localized(english: "Cities", traditionalChinese: "城市", language: language)
        case .waitingClues:
            return localized(english: "Waiting clues", traditionalChinese: "待確認線索", language: language)
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
            return localized(english: "SAV-E will use this language inside the app.", traditionalChinese: "SAV-E 會在 app 內使用這個語言。", language: language)
        case .signOut:
            return localized(english: "Sign Out", traditionalChinese: "登出", language: language)
        case .askPlaceholder:
            return localized(english: "Ask about your places...", traditionalChinese: "問問你的地點...", language: language)
        case .openReviewCandidates:
            return localized(english: "Open review candidates", traditionalChinese: "開啟待確認地點", language: language)
        case .memoSorting:
            return localized(english: "Memo is sorting the clues...", traditionalChinese: "Memo 正在整理線索...", language: language)
        case .cancel:
            return localized(english: "Cancel", traditionalChinese: "取消", language: language)
        case .back:
            return localized(english: "Back", traditionalChinese: "返回", language: language)
        case .tryAgain:
            return localized(english: "Try again", traditionalChinese: "再試一次", language: language)
        case .backToCommands:
            return localized(english: "Back to commands", traditionalChinese: "回到指令", language: language)
        case .closeDrawerContent:
            return localized(english: "Close drawer content", traditionalChinese: "關閉抽屜內容", language: language)
        case .thinking:
            return localized(english: "Thinking", traditionalChinese: "思考中", language: language)
        case .answer:
            return localized(english: "Answer", traditionalChinese: "回答", language: language)
        case .couldntFinish:
            return localized(english: "Couldn’t finish", traditionalChinese: "尚未完成", language: language)
        case .commands:
            return localized(english: "Commands", traditionalChinese: "指令", language: language)
        case .loadingSubtitle:
            return localized(english: "You can cancel and keep using SAV-E.", traditionalChinese: "你可以取消，繼續使用 SAV-E。", language: language)
        case .answerSubtitle:
            return localized(english: "Back returns to commands.", traditionalChinese: "返回會回到指令。", language: language)
        case .placeDetailSubtitle:
            return localized(english: "Back returns to your command drawer.", traditionalChinese: "返回會回到指令抽屜。", language: language)
        case .errorSubtitle:
            return localized(english: "Try again or return to commands.", traditionalChinese: "可以再試一次，或回到指令。", language: language)
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
