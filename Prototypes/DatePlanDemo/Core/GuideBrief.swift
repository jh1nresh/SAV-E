#if !SAVVY_MAIN_APP || (DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW)
import Foundation

/// Fictional content for evaluating the information layout. No venue research.
struct DemoGuideBrief: Sendable {
    let purpose: String
    let foodOrActivity: String
    let arrival: String
    let timing: String
    let perPersonBudget: ClosedRange<Int>?
    let backup: String

    static func fixture(_ id: String) -> DemoGuideBrief? {
        switch id {
        case "coffee":
            return .init(purpose: "先坐下來，留一段好好聊天的時間。",
                foodOrActivity: "示範點法：一人一杯咖啡，兩人分一份吐司。實際菜單尚未查證。",
                arrival: "這是虛構座標，不是已確認的店門入口；真實抵達方式待查詢。",
                timing: "安排 60 分鐘。營業時間、低消與能否訂位仍待確認。",
                perPersonBudget: 180...280,
                backup: "若候位太久，可一起改選甜點備案，重新確認後再排行程。")
        case "park":
            return .init(purpose: "散步、拍照，中間找地方坐一下。",
                foodOrActivity: "示範玩法：選樹蔭路線慢慢走，保留休息時間，沿途不用每個點都打卡。",
                arrival: "分鐘數由直線距離估算，實際公園出口與步行路線待確認。",
                timing: "安排 70 分鐘。出發前檢查天氣；這裡尚未接入天氣資料。",
                perPersonBudget: 0...0,
                backup: "下雨時改選室內甜點店；候選替換需要你們重新確認。")
        case "dinner":
            return .init(purpose: "坐下吃晚餐，給這半天一個舒服的收尾。",
                foodOrActivity: "示範點法：兩份主餐，加一份共享沙拉。實際招牌、份量與菜單待查證。",
                arrival: "實際入口、是否方便叫車與真實交通時間待確認。",
                timing: "安排 90 分鐘。可訂位時段、最後點餐與服務費待確認。",
                perPersonBudget: 500...700,
                backup: "客滿時，先看你們的其他室內候選，再明確重新安排。")
        case "dessert":
            return .init(purpose: "想提早休息或遇到下雨時，有個室內替代選擇。",
                foodOrActivity: "示範點法：兩人分一份甜點，各點一杯茶。實際供應與價格待查證。",
                arrival: "替換行程後會重算示範步行時間；真實交通尚未查詢。",
                timing: "安排 45 分鐘。營業時間與是否需要候位待確認。",
                perPersonBudget: 200...350,
                backup: "沒有座位時，回到已收藏的候選重新挑選。")
        default: return nil
        }
    }
}

struct DemoBudgetTotals: Equatable, Sendable {
    let minimumPerPerson: Int
    let maximumPerPerson: Int
    let coveredStops: Int
    let totalStops: Int
    var isComplete: Bool { totalStops > 0 && coveredStops == totalStops }
    var minimumForTwo: Int { minimumPerPerson * 2 }
    var maximumForTwo: Int { maximumPerPerson * 2 }

    static func fixtures(for ids: [String]) -> Self {
        var minimum = 0, maximum = 0, covered = 0
        for id in ids {
            guard let range = DemoGuideBrief.fixture(id)?.perPersonBudget else { continue }
            minimum += range.lowerBound; maximum += range.upperBound; covered += 1
        }
        return .init(minimumPerPerson: minimum, maximumPerPerson: maximum,
                     coveredStops: covered, totalStops: ids.count)
    }
}

#endif
