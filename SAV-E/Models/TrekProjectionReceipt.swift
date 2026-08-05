import Foundation

/// What came back from projecting a trip into TREK.
///
/// Mirrors `TrekPlanningReceipt` in `backend/src/trekPlanningAdapter.ts` plus
/// the two fields the route adds: how many stops could not be projected, and
/// which provider answered. The adapter never throws on a TREK failure — it
/// returns a `failed` receipt naming the tool that broke — so the app always
/// has something concrete to show instead of a generic error.
struct TrekProjectionReceipt: Codable, Equatable {
    enum Status: String, Codable {
        case completed
        case failed
    }

    let requestId: String
    let localTripId: String
    let status: Status
    let remoteTripId: Int?
    let importedMapStampCount: Int
    let shareCreated: Bool
    let retryPolicy: String
    let failedAt: String?
    let errorCode: String?
    /// Stops dropped because their place is not a confirmed Map Stamp with
    /// real coordinates.
    let skippedStopCount: Int
    /// `"stub"` until the live TREK MCP connection is configured.
    let provider: String

    var isStubProvider: Bool { provider == "stub" }

    func summary(language: AppLanguage) -> String {
        switch status {
        case .completed:
            let base = language.localized(
                english: "Projected \(importedMapStampCount) Map Stamps into TREK.",
                traditionalChinese: "已將 \(importedMapStampCount) 個地圖章投影到 TREK。"
            )
            guard skippedStopCount > 0 else { return base }
            return base + " " + language.localized(
                english: "\(skippedStopCount) stops were skipped because they are not confirmed places yet.",
                traditionalChinese: "有 \(skippedStopCount) 個停留點尚未確認成地點，已略過。"
            )
        case .failed:
            let step = failedAt ?? "unknown"
            return language.localized(
                english: "TREK projection stopped at \(step). Nothing partial was left behind on your SAV-E trip.",
                traditionalChinese: "TREK 投影在 \(step) 中止。你的 SAV-E 行程沒有留下任何殘缺資料。"
            )
        }
    }
}
