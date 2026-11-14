# Savvy · 個人地圖與朋友出遊預覽

這個目錄保留兩套情境：**主 Savvy 的真實帳號預覽（148 候選）**，以及**獨立的虛構雙人約會 demo**。兩者共用部分視覺元件，但資料、入口與驗證證據必須分開。

目前手機已更新到 **147 真實帳號版**，已確認預設個人模式並讀到原有 85 筆收藏。**148 UI 調整版已完成簽署編譯，安裝與新畫面仍待手機解鎖後驗證**。25 項 native tests 已通過；這不代表真人共同出遊或定位權限流程已實測。

## 148：主帳號版

預覽保留正常 `SaveApp` 入口、登入與帳號驗證 gate。驗證後由 `ContentView` 將同一個 production `MapViewModel` 傳入 `LivePlanningMapRoot`，讀取該帳號原有收藏；不是另外開假帳號或 fixture store。

- **預設個人地圖**：顯示自己的真實收藏及來源標籤，保留收藏／地圖／Passport。
- **朋友出遊明確切換**：讀取既有服務端 ACL 允許的共同清單、地點、實際成員與朋友分享 feed。沒資料就呈現空狀態，不補小安、示範好友或預設票數。
- **真實 Apple Maps**：標準原生底圖與 POI，加上真實收藏／候選 annotations；搜尋使用 `MKLocalSearch`。只有合法、非零 WGS84 座標能成為自有 pin，GCJ-02／BD-09 不假裝轉換。無法定位的資料仍保留在原收藏／清單。
- **來源狀態分開**：「已收藏」「搜尋結果候選」「隊伍候選」「朋友已分享」不互相替代。朋友的想去／到訪不等於自己收藏、到訪或推薦票。
- **帳號管理仍可用**：Passport 開啟既有 compact account settings，保留個人資料、登出與確認刪帳號，不顯示舊 Profile 共同清單入口。

朋友模式用綁定目前 owner/session 的 `LiveOutingModel` 直接讀現有授權 API，不依賴 `MapViewModel.collaborativeLists` 或舊全域清單 cache。帳號切換、取消、模式離開或權限撤回時，舊投影／非同步結果需失效；沒有新增帳號系統或伺服器。

## 明確操作與分享邊界

選擇清單、建立清單、輸入邀請碼加入、加入地點、產生及分享邀請，都是分開的使用者操作。編輯及邀請受實際 ACL 角色限制。這些操作透過既有服務寫入共同清單；**看 pin、選路線或切模式不會自動新增個人收藏或到訪**。

`LiveMapPlace.listPayload` 只傳店名、地址、座標、分類與必要的型別化來源識別，清除私人筆記、評分、來源 URL、照片與分享者記憶，不複製完整 saved Place。這不是即時投票、朋友定位、出席狀態或所有成員同意的證明。

## Guide：真實路線，未知資訊照實呈現

朋友模式可選 2–6 個共同清單地點，按選取順序向 `MKDirections` 取得步行路線與預估時間，畫出回傳路線。每站目前明示預留 60 分鐘；這是規劃假設，不是店家營業或停留時間資料。取不到路線會顯示錯誤，不補虛構移動時間。

可設定出發時間，手動開始與推進下一站；不自動記錄到訪，也不是即時導航。地點卡另有 Apple Maps 步行導航入口。菜單、價格、總預算、營業時間、訂位與備案尚未查證，不套用 mock 示範數字，也不把未知價格當免費。沒有接遠端 AI、MCP 或攻略服務。

## 編譯與交付狀態

`Main/` 真實 UI 與新增 native tests 的完整 guard：

```swift
#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
```

只有此主 App Debug 條件會選用新地圖。一般主 App Debug／Release 不選此 UI；獨立 fixture app 不取代主 App 的 `@main`。Release 沒有預期行為變更，仍須以正常主 App build 驗證。

148 保留既有 `com.wanderly.app`、圖示、extensions、entitlements 和容器。安裝由本次授權的單一 controller 進行，不先解除安裝、不清帳號、不重設資料；沿用 repo 的裝置／快取獨占、10 GiB runtime 空間底線及簽署檢查。

**PR #343 保持 Draft，接在 #342 後面。GitHub Actions 維持停用，required hosted CI 未通過，不是 merge-ready。** 不 merge、不部署 backend／schema、不發佈 App Store 或 TestFlight。

新增 25 個 native test methods 位於 `Tests/SAVETests`：

- `LiveMapPlaceTests`：11 個，檢查真實型別的座標、穩定 ID、來源狀態與分享白名單。
- `LiveOutingModelTests`：14 個，檢查 ACL、session、取消、失效結果及寫入確認／重試邊界。

25 項 native tests 已在 iOS26.5 執行通過（0 failures），模擬器已關閉。148 UI 的簽署編譯已通過；安裝、新版畫面和定位互動仍需分別驗證。測試 fixtures 不證明真實服務覆蓋，也不授權為了收證自動對使用者帳號建立、加入、分享或刪除資料。

Receipts、截圖與影片留在本機忽略的 `Evidence/` 或工作專用證據路徑，不包含在 clone／PR 中；不提交實際帳號內容。source、靜態檢查、native tests、hosted CI、安裝、啟動與畫面證據分開報告。

## 獨立 mock demo

`SavvyDateDemo` 保留四個虛構地點、小安／你、單機投票與共同選擇、示範預算／行前卡及直線距離移動估算。只有獨立情境使用這些 fixtures；不讀正式收藏，沒有真人好友或同步投票。

從本目錄開啟：

```bash
./run-local.sh
# 沒有 Simulator.app 視窗時：
./run-local.sh --headless
```

需要本機 Xcode、XcodeGen 及腳本指定的可用 simulator。也可執行 `xcodegen generate --spec project.yml`，開啟 `SavvyDateDemo.xcodeproj` 的 `SavvyDateDemo` scheme。腳本取得快取／裝置鎖；結束時依提示釋放，避免與 controller 的 build／runtime 衝突。

獨立 host checks 從本目錄執行：

```bash
swiftc -parse-as-library Core/*.swift Checks/ModelChecks.swift -o .host-checks
./.host-checks
```

既有七組 host checks 與兩項獨立 UI tests 是 mock 的驗證工具，不替代主帳號版的驗證。

## 來源結構

- `Main/LivePlanningMapRoot.swift`：個人／朋友模式、真實地圖、搜尋與 Guide UI。
- `Main/LiveMapPlace.swift`：穩定 pin、座標篩選與 venue-only 分享投影。
- `Main/LiveOutingModel.swift`：目前帳號的 ACL 清單、成員、feed 與明確寫入。
- `Main/LiveRoutePlan.swift`：Apple 步行路線、時間線與手動進度。
- `Core/`、`Sources/`、`Checks/`、`UITests/`：獨立 fixture demo 與檢查；部分視覺元件供 Debug 預覽復用。
- `PROMPT.md`：原始 mock scaffold prompt，不代表 147 真實資料契約。
- `BRIEF.md`：147 範圍、驗收與交付邊界。

## 148 介面調整

地圖保留一個精簡個人／朋友切換，移除大型裝飾標題；新增明確定位按鈕與權限／重試狀態。遠景用原生書籤／問號 pin 區分收藏與候選，近景才顯示店名卡。收藏加入本地名稱／地址搜尋及想去／標記去過篩選；Passport 使用實際收藏統計。新主介面共用既有 CityMVPStyle 的冷色、自適應日夜 tokens，保留三 tab、左側搜尋和發光切換。搜尋結果會返回地圖，不會停在看不到結果的收藏頁。

這是原生 SwiftUI，ui-sdk／Modern Web Guidance 的 web 元件不適用；未新增 web layer、npm 套件、AI 服務或位置追蹤。整體應用的舊設定／新增收藏相容入口仍需後續逐面驗證，不能把這次調整稱為全 App 已完成。
