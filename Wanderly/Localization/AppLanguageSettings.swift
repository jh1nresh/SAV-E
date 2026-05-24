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
            return "\(count) saved"
        case .traditionalChinese:
            return "已存 \(count) 個"
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
        switch (key, language) {
        case (.appName, _): return "SAV-E"
        case (.opening, .english): return "Opening SAV-E"
        case (.opening, .traditionalChinese): return "正在開啟 SAV-E"
        case (.tripLinkReady, .english): return "Trip Link Ready"
        case (.tripLinkReady, .traditionalChinese): return "行程連結已準備好"
        case (.tripLinkMessage, .english): return "%@ has %d stops. Full trip import is coming next."
        case (.tripLinkMessage, .traditionalChinese): return "%@ 有 %d 個停靠點。完整行程匯入會在下一版補上。"
        case (.ok, .english): return "OK"
        case (.ok, .traditionalChinese): return "好"
        case (.cantSignIn, .english): return "Can't Sign In"
        case (.cantSignIn, .traditionalChinese): return "無法登入"
        case (.googleNotEnabled, .english): return "Google Isn't Enabled"
        case (.googleNotEnabled, .traditionalChinese): return "Google 登入尚未啟用"
        case (.googleNotEnabledMessage, .english): return "Turn on Google in Privy, or use email sign-in for now."
        case (.googleNotEnabledMessage, .traditionalChinese): return "請在 Privy 啟用 Google，或先使用 Email 登入。"
        case (.appNotAllowed, .english): return "App Not Allowed"
        case (.appNotAllowed, .traditionalChinese): return "App 尚未允許"
        case (.appNotAllowedMessage, .english): return "Add com.wanderly.app to the allowed app identifiers in Privy."
        case (.appNotAllowedMessage, .traditionalChinese): return "請把 com.wanderly.app 加到 Privy 允許的 app identifiers。"
        case (.authSetupNeeded, .english): return "Auth Setup Needed"
        case (.authSetupNeeded, .traditionalChinese): return "需要設定登入"
        case (.genericSignInError, .english): return "Something went wrong. Try again in a moment."
        case (.genericSignInError, .traditionalChinese): return "發生錯誤，請稍後再試。"
        case (.continueWithGoogle, .english): return "Continue with Google"
        case (.continueWithGoogle, .traditionalChinese): return "使用 Google 繼續"
        case (.orUseEmail, .english): return "or use email"
        case (.orUseEmail, .traditionalChinese): return "或使用 Email"
        case (.emailAddress, .english): return "Email address"
        case (.emailAddress, .traditionalChinese): return "Email 地址"
        case (.sendCode, .english): return "Send Code"
        case (.sendCode, .traditionalChinese): return "寄送驗證碼"
        case (.verificationCode, .english): return "Verification code"
        case (.verificationCode, .traditionalChinese): return "驗證碼"
        case (.verify, .english): return "Verify"
        case (.verify, .traditionalChinese): return "驗證"
        case (.signInTagline, .english): return "Your personal place memory."
        case (.signInTagline, .traditionalChinese): return "你的個人地點記憶庫。"
        case (.signInDescription, .english): return "Drop in links, posts, screenshots, notes, or maps. Memo helps SAV-E turn them into reviewable place cards."
        case (.signInDescription, .traditionalChinese): return "丟進連結、貼文、截圖、筆記或地圖，Memo 會幫 SAV-E 轉成可確認的地點卡。"
        case (.capture, .english): return "Capture"
        case (.capture, .traditionalChinese): return "捕捉"
        case (.captureSubtitle, .english): return "link or media"
        case (.captureSubtitle, .traditionalChinese): return "連結或媒體"
        case (.review, .english): return "Review"
        case (.review, .traditionalChinese): return "確認"
        case (.reviewSubtitle, .english): return "with evidence"
        case (.reviewSubtitle, .traditionalChinese): return "保留證據"
        case (.save, .english): return "Save"
        case (.save, .traditionalChinese): return "儲存"
        case (.saveSubtitle, .english): return "memory cards"
        case (.saveSubtitle, .traditionalChinese): return "記憶卡片"
        case (.profileTitle, .english): return "SAV-E Passport"
        case (.profileTitle, .traditionalChinese): return "SAV-E 護照"
        case (.edit, .english): return "Edit"
        case (.edit, .traditionalChinese): return "編輯"
        case (.editPassport, .english): return "Edit Passport"
        case (.editPassport, .traditionalChinese): return "編輯護照"
        case (.editPassportDescription, .english): return "This is how SAV-E labels your memory book."
        case (.editPassportDescription, .traditionalChinese): return "這會顯示在你的 SAV-E 記憶本上。"
        case (.saving, .english): return "Saving..."
        case (.saving, .traditionalChinese): return "儲存中..."
        case (.passportName, .english): return "PASSPORT NAME"
        case (.passportName, .traditionalChinese): return "護照名稱"
        case (.name, .english): return "Name"
        case (.name, .traditionalChinese): return "名稱"
        case (.accountManagedByLogin, .english): return "Email and sign-in provider stay managed by your login account."
        case (.accountManagedByLogin, .traditionalChinese): return "Email 與登入方式仍由你的登入帳號管理。"
        case (.localMemoHelper, .english): return "Local Memo helper"
        case (.localMemoHelper, .traditionalChinese): return "本機 Memo 助手"
        case (.memoHelper, .english): return "MEMO HELPER"
        case (.memoHelper, .traditionalChinese): return "MEMO 助手"
        case (.reviewFirst, .english): return "REVIEW FIRST"
        case (.reviewFirst, .traditionalChinese): return "先確認"
        case (.editPassportAccessibility, .english): return "Edit Passport"
        case (.editPassportAccessibility, .traditionalChinese): return "編輯護照"
        case (.passportStamps, .english): return "Passport Stamps"
        case (.passportStamps, .traditionalChinese): return "護照印章"
        case (.memoBook, .english): return "MEMO BOOK"
        case (.memoBook, .traditionalChinese): return "MEMO 本"
        case (.memoryCards, .english): return "Memory cards"
        case (.memoryCards, .traditionalChinese): return "記憶卡"
        case (.verified, .english): return "Verified"
        case (.verified, .traditionalChinese): return "已確認"
        case (.cities, .english): return "Cities"
        case (.cities, .traditionalChinese): return "城市"
        case (.waitingClues, .english): return "Waiting clues"
        case (.waitingClues, .traditionalChinese): return "待確認線索"
        case (.memberSince, .english): return "Member since"
        case (.memberSince, .traditionalChinese): return "加入時間"
        case (.passportControls, .english): return "Passport Controls"
        case (.passportControls, .traditionalChinese): return "護照設定"
        case (.localMemory, .english): return "Local Memory"
        case (.localMemory, .traditionalChinese): return "本機記憶"
        case (.language, .english): return "Language"
        case (.language, .traditionalChinese): return "語言"
        case (.chooseLanguage, .english): return "Choose Language"
        case (.chooseLanguage, .traditionalChinese): return "選擇語言"
        case (.languageDescription, .english): return "SAV-E will use this language inside the app."
        case (.languageDescription, .traditionalChinese): return "SAV-E 會在 app 內使用這個語言。"
        case (.signOut, .english): return "Sign Out"
        case (.signOut, .traditionalChinese): return "登出"
        case (.askPlaceholder, .english): return "Ask about your places..."
        case (.askPlaceholder, .traditionalChinese): return "問問你的地點..."
        case (.openReviewCandidates, .english): return "Open review candidates"
        case (.openReviewCandidates, .traditionalChinese): return "開啟待確認地點"
        case (.memoSorting, .english): return "Memo is sorting the clues..."
        case (.memoSorting, .traditionalChinese): return "Memo 正在整理線索..."
        case (.cancel, .english): return "Cancel"
        case (.cancel, .traditionalChinese): return "取消"
        case (.back, .english): return "Back"
        case (.back, .traditionalChinese): return "返回"
        case (.tryAgain, .english): return "Try again"
        case (.tryAgain, .traditionalChinese): return "再試一次"
        case (.backToCommands, .english): return "Back to commands"
        case (.backToCommands, .traditionalChinese): return "回到指令"
        case (.closeDrawerContent, .english): return "Close drawer content"
        case (.closeDrawerContent, .traditionalChinese): return "關閉抽屜內容"
        case (.thinking, .english): return "Thinking"
        case (.thinking, .traditionalChinese): return "思考中"
        case (.answer, .english): return "Answer"
        case (.answer, .traditionalChinese): return "回答"
        case (.couldntFinish, .english): return "Couldn’t finish"
        case (.couldntFinish, .traditionalChinese): return "尚未完成"
        case (.commands, .english): return "Commands"
        case (.commands, .traditionalChinese): return "指令"
        case (.loadingSubtitle, .english): return "You can cancel and keep using SAV-E."
        case (.loadingSubtitle, .traditionalChinese): return "你可以取消，繼續使用 SAV-E。"
        case (.answerSubtitle, .english): return "Back returns to commands."
        case (.answerSubtitle, .traditionalChinese): return "返回會回到指令。"
        case (.placeDetailSubtitle, .english): return "Back returns to your command drawer."
        case (.placeDetailSubtitle, .traditionalChinese): return "返回會回到指令抽屜。"
        case (.errorSubtitle, .english): return "Try again or return to commands."
        case (.errorSubtitle, .traditionalChinese): return "可以再試一次，或回到指令。"
        default:
            return String(describing: key)
        }
    }
}
