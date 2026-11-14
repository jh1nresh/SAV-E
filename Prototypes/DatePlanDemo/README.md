# Savvy · 兩人半天約會（本地 demo）

SwiftUI / Apple MapKit 的雙人約會預覽。保留獨立模擬器專案，並提供主 Savvy 的明確 Debug 編譯入口；使用者已授權在自己的 iPhone 安裝 build 146。帳號、正式收藏與既有 3D 程式不變，沒有 App Store／TestFlight 或服務發佈。

保留 **收藏、地圖、Passport**，搜尋在左邊，tab 使用滑動發光選取。主流程拿掉自建 3D、雲霧、車流、額外朋友 tab、浮動新增按鈕和評分。參考 Midway 的步驟與卡片編排，改成可操作的雙人流程。

## 開啟

在本目錄執行：

```bash
./run-local.sh
```

需要本機既有 Xcode、XcodeGen、Simulator.app 及 iPhone 14 Pro / iOS 26.5 模擬器。也可先在本目錄執行 `xcodegen generate --spec project.yml`，再打開產生的 `SavvyDateDemo.xcodeproj`，選 `SavvyDateDemo` scheme 使用模擬器執行。

目前這台 Mac 保留了 simctl 和模擬器 runtime，但沒有 Simulator.app 視窗程式；驗證及錄影已用 headless 模擬器完成。`./run-local.sh --headless` 可啟動相同預覽供自動操作，不會開互動視窗。先前完整流程影片是本機驗證留存，不隨 PR 提交；`Evidence/` 不包含在 clone 中。新版手機的安裝／啟動證據另列於 PR。

啟動腳本會取得快取與裝置鎖，保留終端機工作直到你按 Enter；結束時關閉這台模擬器並確認 Shutdown，再釋放鎖。若裝置已被其他操作使用，這次不接管。

## 主 Savvy 的 iPhone 開發預覽

主專案預設仍進入既有 Savvy。只有主 target 同時設定 `DEBUG` 和 `SAVVY_DATE_PLAN_PHONE_PREVIEW` 時，才改用約會 demo 的 App 入口；不會建立 `SaveApp`、啟動帳號／分享生命週期或讀取真實收藏。一般 Debug 和所有 Release 都排除這些示範 Swift 原始碼。預覽使用現有 `com.wanderly.app`、圖示、extensions 與 entitlements，build 146。

先確保有獨占的編譯快取、足夠空間與可用的既有開發簽署設定，再執行：

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj -scheme SAV-E -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${SAVE_DERIVED_DATA:?Set an exclusively owned cache path}" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG SAVVY_CITY_MVP SAVVY_MAIN_APP SAVVY_DATE_PLAN_PHONE_PREVIEW' \
  COMPILER_INDEX_STORE_ENABLE=NO build
```

這個命令從 repo 根目錄執行；使用既有 signing profiles，不開啟自動憑證／裝置註冊。只在使用者明確授權後，才把產物更新安裝到其 Savvy，**不先解除安裝、不清帳號或容器**。手機一般開啟此開發版本就會進入示範情境；要回到既有產品，重新編譯／安裝不帶預覽旗標的版本。真實分享入口、登入與雲端同步不在此 demo 中。

此 PR 接在 #342 後面，保留 Draft。GitHub Actions 維持停用，必要 hosted CI 尚未通過，不能視為 merge-ready；不 merge、不發佈正式版。

## 操作情境

1. 「朋友推薦」可切換全部／小安推薦／我的收藏，加入或移出這次候選。
2. 「一起挑」可切換操作你和小安；只有兩人都選的地點才計入共同選擇。小安一開始已挑三個示範地點。
3. Guide 依共同選擇產生半天時間線，可改開始時間、透過每站的 `…` 往前或往後移。
4. 「開始照行程走」顯示下一站，按下一站手動推進。
5. 可隨時切換收藏／地圖／Passport。投票與排行程不會新增收藏或到訪。
6. 搜尋可開啟地點；只有按收藏並確認，才加入本地示範收藏。

選擇改變後，既有時間線會保留並標明待重新安排。過期提案無法開始或推進；重新安排需要明確操作。
出發後，原本的時間與順序會鎖定，避免下一站被跳過或重複。要修改時，回到一起挑並明確重新安排，進度會重設。

## 示範邊界

- 地圖是真正的 Apple MapKit 基本地圖；店名、座標、人物、推薦文字與交通時間是隔離的示範資料。
- Guide 使用本地規則，沒有接遠端 AI、攻略搜尋、營業資訊或 MCP。
- 朋友投票是單機兩個操作身分，沒有伺服器同步、真人好友或定位分享。
- 虛線表示停靠順序，沒有宣稱為實際步行路線。移動分鐘數是直線距離的示範估算。
- 狀態留在這次 App 執行期間；重開後回到初始情境。
- 此版本以直向、淺色預覽為主。正式 App 的語言、登入、權限、付費與儲存流程未接入。
- Guide 每站可打開吃玩／交通／時間提醒／預算／備案行前卡；總預算隨共同選擇更新。這些是明確標示的示範內容，尚未接入真實菜單、路線、營業資訊或價格。參考頁的外框可讀，內嵌行程回傳 404，因此沒有匯入或推測其中的真實店家。

## 結構與檢查

- `Core/DatePlanModel.swift`：候選、獨立投票、共識快照、時間線與手動進度。
- `Sources/`：地圖、三 tab、挑選卡、Guide、搜尋、收藏與 Passport。
- `Core/GuideBrief.swift`：行前卡示範內容與兩人預算彙總，未知價格不當作免費。
- `Checks/ModelChecks.swift`：七組可在 Mac 執行的狀態檢查。
- `UITests/`：完整約會流程、不同意與過期提案情境。
- `PROMPT.md`：依 Midway 與本次需求改寫的 scaffold prompt。
- `BRIEF.md`：本地範圍、產品狀態與驗收約定。

Host checks：

```bash
swiftc -parse-as-library Core/*.swift Checks/ModelChecks.swift -o .host-checks
./.host-checks
```

獨立專案的驗證不等於主 App 新版、真實手機行為或正式發佈證明；各項證據需分開記錄。

2026-11-14 本地驗證：七組模型檢查、generic simulator build 及兩項 UI 測試通過。UI 涵蓋共同選店、預算與行前卡、改時間／站序、三站進度、搜尋確認收藏與退出返回。iPhone 14 Pro／iOS 26.5、直向淺色；其他尺寸與動態字體尚未驗證。`--headless` 啟動、按 Enter 結束、Shutdown 與鎖釋放均已實際驗證。既有 208 個記錄的來源檔雜湊未變。

## Guide 的資訊結構

每站行前卡說明吃什麼／玩什麼、如何抵達、停留與營業提醒、每人與兩人示範預算，以及下雨／候位備案。時間線保留時間、地點與停留長度，摘要顯示兩人示範預算。未知價格列待確認，不默認為0；交通與服務費尚未計入。這是資訊架構預覽，尚未接入真實餐點、票價或交通資料。
