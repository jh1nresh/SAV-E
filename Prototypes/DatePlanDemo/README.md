# Savvy · 個人地圖與朋友出遊預覽

主 Savvy 的真實帳號 Debug 預覽與獨立的虛構雙人約會 demo 共存。兩者資料、入口與證據分開；本次只交付主 Savvy，不交付 City Lab。

## 151：店家資訊與朋友地圖

保留正常 SaveApp／登入／帳號驗證，使用同一個 production MapViewModel 的真實收藏。預設個人地圖；朋友出遊明確切換，讀取實際授權共同清單和分享，沒有虛構朋友或票數。

- 原生 Apple Maps 店家點使用 MapFeature → MKMapItemRequest；收藏／候選照片 pin 也可開卡。已有收藏使用實際 saved identity。只有明確按「收藏」才走既有儲存流程。
- 點開 pin 保留彈出、輕晃、回彈；底部地理錨點固定，移動地圖不重播動畫，Reduce Motion 關閉這些動效。
- 地點卡加入 Apple 小地圖、地址和精簡操作。主卡保留 Savvy 配色；顯示可取得的 Apple 店家資訊、電話與網站，完整 Apple 卡收在補充入口。照片優先讀合適的商家照片，其次是同店網站圖片；缺少時明示，不用貼文截圖冒充。note 區改成來源連結，既有人工筆記不刪除。
- 收藏、Passport、搜尋、地點卡和 compact 帳號／編輯／語言／隱私頁對齊圖示的橘、奶油色及深炭色；保留 navbar 發光切換。更深層的舊頁面仍有待處理。
- 朋友 pin 直接顯示真實分享者與「去過／分享」，同店多人分組顯示。收藏、評星和分享不等同明確推薦，現有資料沒有獨立推薦欄位。
- 新連結匯入的 note 只放明確來源 URL，不再放貼文內文；原內容保留在來源 evidence，不進收藏筆記。Unplaced 恢復和手動筆記保留，不批次改寫舊帳號。
- 定位需主動點擊；不做背景定位或朋友定位。共同清單只傳地點資訊，私人筆記／照片不分享。

Guide 使用 MKDirections 真實步行路線與手動進度；每站60分鐘是明示假設。菜單、營業時間、預算與備案尚未查證，沒有遠端 AI／MCP。152 改為在同一帳號的記憶體內保留已完成規劃的順序、出發時間與進度；返回時先重新確認共同清單權限及每站內容，再顯示路線與時間線。清單變更、權限失效或驗證失敗會清除行程。尚在計算的路線仍取消，不提供跨重開／離線行程持久化。

152 的 Guide 加上目前這站、完成狀態與明確的「完成這站」操作，不會更改地點的去過紀錄。完整測試1,985項：1,981通過、4預期略過、0失敗；最終純版面調整後，重新編譯並跑完七項受影響畫面測試，四張明暗 Guide panel圖已檢查。一般主 App／簽署 build與嚴格簽章檢查通過，主 Savvy152已安裝；版本回讀與實機操作另以receipt確認。模擬器Shutdown，未宣稱真實導航返回或全App視覺驗收。下方151為上一輪紀錄。

新方向：使用者已明確要求預設地圖改成大家公開社群貼文的探索地圖。本地程式已接入獨立公開索引與探索／朋友／我的切換，詳見 [PUBLIC-DISCOVERY.md](PUBLIC-DISCOVERY.md)。它不讀私人收藏或追蹤者 feed，未設定索引時顯示不可用。真實 IG／Threads／小紅書取得、授權與覆蓋仍未接通；手機152仍是現有個人／朋友模式，沒有安裝這個缺少即時資料的入口。不能把測試、分享或匿名熱門訊號冒充全網貼文。

本地另已接入「公開貼文 → 和朋友一起安排 → 選共同清單 → 打開 Guide」；只加入地點候選，不會代替使用者收藏或標記去過。未知加入結果只重讀確認。原生完整測試2,009項（2,005通過、4略過）；最終小幅版面與明暗 fixture 修正後重建，九項受影響畫面測試通過，六張最新元件圖已檢查。這些是假資料元件與資料模型證據，完整根畫面跨 sheet 導航、實機操作與真實來源仍未驗證。

完整範圍、狀態和驗證界線見 [BRIEF.md](BRIEF.md)。149 的一般主 App build、簽署 build 及安裝通過；全單元測試1923項／1920通過／3預期略過／0失敗。149 的帳號頁畫面未驗證。150 歷史版本的一般主 App build、測試版 test-build 與簽署 build 已通過；全單元測試1932項／1929通過／3預期略過／0失敗。六張明暗元件圖已檢查，模擬器已關閉。主 Savvy150 已安裝並正常啟動，metadata 確認版本；實機點擊、晃動手感、定位尚未驗證，不能由原始碼或元件圖推定。

Main UI 完整 guard：`DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW`。一般 Debug／Release 不選此預覽；保留既有 com.wanderly.app、extensions 和資料，不解除安裝或重設帳號。

**PR #343 維持 Draft，Actions 停用，required hosted CI 未通過，不是 merge-ready。** 不 merge、不部署 backend/schema、不發佈 App Store/TestFlight。真實帳號證據留在忽略的 Evidence，不提交私人內容。

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
- `PROMPT.md`：原始 mock scaffold prompt，不代表 148 真實資料契約。
- `BRIEF.md`：148 範圍、驗收與交付邊界。

## 148 介面調整

地圖保留一個精簡個人／朋友切換，移除大型裝飾標題；新增明確定位按鈕與權限／重試狀態。遠景用原生書籤／問號 pin 區分收藏與候選，近景才顯示店名卡。收藏加入本地名稱／地址搜尋及想去／標記去過篩選；Passport 使用實際收藏統計。新主介面共用既有 CityMVPStyle 的冷色、自適應日夜 tokens，保留三 tab、左側搜尋和發光切換。搜尋結果會返回地圖，不會停在看不到結果的收藏頁。

這是原生 SwiftUI，ui-sdk／Modern Web Guidance 的 web 元件不適用；未新增 web layer、npm 套件、AI 服務或位置追蹤。整體應用的舊設定／新增收藏相容入口仍需後續逐面驗證，不能把這次調整稱為全 App 已完成。

151 的 native test-build、一般主 App generic build 與簽署真機 build 通過；全 SAVETests 1,967 項／1,963 通過／4 預期略過／0 失敗。八張正常字級明暗元件圖已檢查，模擬器 Shutdown 已確認。來源內文與人工筆記經兩次恢復循環仍各自保留。獨立公開店家查詢沒有取得精確結果，未到圖片呈現步驟，因此真實商家照片覆蓋仍未驗證；不可把測試假圖或缺圖提示當成證明。主 Savvy151 已安裝到授權 iPhone，metadata 回讀版本正確、簽署及 App Group／keychain 身分一致；實機操作與照片覆蓋仍需另外驗證。
