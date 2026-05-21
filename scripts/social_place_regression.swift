import Foundation

struct RegressionCase {
    let name: String
    let sourceURL: String
    let evidence: String
    let expectedName: String
    let rejectedNames: [String]
}

let cases: [RegressionCase] = [
    RegressionCase(
        name: "4foodie menu caption uses explicit venue anchor before address",
        sourceURL: "https://www.instagram.com/reel/DYZqnVMxt_0/",
        evidence: """
        4foodie Victoria & Ava 還有她們的夥伴們 on Instagram: "當熱炒在吃的火鍋店😂😂
        📍Taipei, Taiwan
        牛寓 / 以下餐點及價位
        泡椒辣炒脆牛心 $320
        美味程度：🌕🌕🌕🌕🌕
        💡補充💡我的第一名！不敢吃牛心的人也會愛！點就對了，請先打電話預訂！中辣～
        
        自家醃製酸高麗炒牛肉 $350
        美味程度：🌕🌕🌕🌕🌖
        整體
        環境衛生：🌕🌕🌕🌕🌑
        服務態度：🌕🌕🌕🌕🌑
        再訪意願：🌕🌕🌕🌕🌖
        🗺台北市松山區民權東路三段106巷3弄51號
        "
        """,
        expectedName: "牛寓",
        rejectedNames: ["整體", "再訪意願：🌕🌕🌕🌕🌖", "自家醃製酸高麗炒牛肉 $350"]
    ),
    RegressionCase(
        name: "4foodie rating rows do not become venue title",
        sourceURL: "https://www.instagram.com/reel/DYKRzPixTGd/",
        evidence: """
        4foodie Victoria & Ava 還有她們的夥伴們 on Instagram: "📍Tokyo, Japan
        YAKINIKU 37west NY / 吟コース / ¥24000(税込)
        美味程度：🌕🌕🌕🌕🌗
        環境衛生：🌕🌕🌕🌕🌗
        服務態度：🌕🌕🌕🌕🌕
        再訪意願：🌕🌕🌕🌕🌗
        🗺東京都港区新橋2-11-10 HULIC & New Shinbashi 2F
        "
        """,
        expectedName: "YAKINIKU 37west NY",
        rejectedNames: ["再訪意願：🌕🌕🌕🌕🌗", "吟コース"]
    ),
    RegressionCase(
        name: "handle-only social evidence resolves known profile display name",
        sourceURL: "https://www.instagram.com/p/DX_cUWNmNxH/",
        evidence: """
        @mikantaichung
        #台中美食 #壽喜燒
        勤美附近
        棉花糖壽喜燒
        關西、關東兩種風格
        """,
        expectedName: "蜜柑 關西風壽喜燒",
        rejectedNames: ["Mikantaichung", "勤美附近", "棉花糖壽喜燒"]
    )
]

@main
struct SocialPlaceRegressionRunner {
    static func main() {
        let service = SocialLinkReviewCandidateService.shared
        var failures: [String] = []
        for testCase in cases {
            let candidates = service.reviewCandidates(fromEvidenceText: testCase.evidence, sourceURL: testCase.sourceURL)
            guard let first = candidates.first else {
                failures.append("\(testCase.name): no candidates")
                continue
            }
            if first.candidateName != testCase.expectedName {
                failures.append("\(testCase.name): expected name \(testCase.expectedName), got \(first.candidateName)")
            }
            for rejected in testCase.rejectedNames where first.candidateName == rejected {
                failures.append("\(testCase.name): rejected title selected: \(rejected)")
            }
            if first.evidence.joined(separator: " | ").contains("Analysis pipeline") == false {
                failures.append("\(testCase.name): missing Analysis pipeline evidence marker")
            }
        }

        if failures.isEmpty {
            print("social place regression: PASS (\(cases.count) cases)")
        } else {
            print("social place regression: FAIL")
            failures.forEach { print("- \($0)") }
            exit(1)
        }
    }
}
