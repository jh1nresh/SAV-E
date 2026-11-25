# Savvy Pocket City

同一個台北街區有兩個入口。「3D 街景」可以拖曳、旋轉和放大到復興南路的招牌。「Apple 地點」在 Apple 地圖上顯示 Pocket City 插畫，沿用 Apple 提供的興趣點與地點卡。這個原型沒有 Savvy 帳號資料。

## 從地球看台灣

在同一張地圖拖曳、旋轉和縮放。從[台灣本島](http://127.0.0.1:42418/index.html?view=120.92,23.68,7.0&bearing=0)可以看到中央山脈、河谷與西部平原。搜尋「日月潭」可以飛到湖岸，搜尋鄉鎮名可以移到當地繼續逛。街口的具名地點沿用 Savvy 的 pin 與地點卡。

- 全國範圍取自國土測繪中心 TOWN_MOI_1120317 鄉鎮界。22 縣市、368 鄉鎮市區的陸域共與 1,283,052 個約 170 公尺網格相交，包含離島。各格共用同一個地理原點。海岸邊的格子只要碰到陸地就計入。[界線來源](https://maps.nlsc.gov.tw/pro/download.jsp)
- 山脊與谷地沿用數值高程。另有 14,940 個具名景觀與公園、13,309 段河溪和露天水道以及 840 個水域與濕地輪廓。搜尋「玉山主峰」可斜看實際山稜、林帶與峰頂裸岩。全島中高山有廣域圖版，玉山群峰另有高解析近景。林冠與岩色依海拔和坡度繪製。景觀名稱可點開看公開來源。[地形來源](https://github.com/tilezen/joerd/blob/master/docs/attribution.md) · [玉山高程與圖版說明](taiwan/mountains/SOURCES.md) · [山水資料與重建方式](taiwan/scenery/SOURCES.md)
- 全台具名公共地點來自 2026-11-23 的 OpenStreetMap 台灣快照，共 245,607 筆，涵蓋所有鄉鎮。此索引與山水資料有交集。除了店家，也包含學校、車站及公共設施。瀏覽地點與建立收藏是不同操作。[Geofabrik 台灣快照](https://download.geofabrik.de/asia/taiwan.html)
- 街口近景按目前視野中的建物、道路、水域和林地生成屋頂、店面細節與林冠。台北以外的 21 縣市按視野讀取隨附的道路與建物分片，離線仍有已收錄的街道與街屋；線上向量圖磚補充周圍底圖。只有能對應到建物外牆的公開店家才繪製店面，其餘具名地點保留 pin。專門繪製的地標優先顯示自己的模型。[地標製作流程](CITY-WORKFLOW.md)

![復興南路同一手機鏡位，關閉店名後的舊版與新版](examples/fuxing-mobile-comparison.jpg)

## Savvy App 地點與貼文接入

[101 周邊的分類 pin 預覽](http://127.0.0.1:42418/index.html?view=121.5657,25.0348,17.65&bearing=-8)。城市、街區和街口依縮放層級顯示地點。下圖為同一鏡位，左為前版、右為本版。

![101 周邊同一鏡位的 pin 對照](examples/xinyi-place-pins.jpg)

- 首次執行下方的 `prepare_data.py` 後，透過 [loadCityPlaces](city-place-index.js) 取得 GeoJSON FeatureCollection。這個快照收錄台北 12 區共 39,664 筆。每筆以 `properties.placeId` 識別，Point 座標順序為經度、緯度。行政區和分類在 `district`、`category` 與 `categoryLabel`，部分地點沒有名稱。如果已有舊版 `data/`，可在本次提交的新工作目錄重新還原。
- App 接入時，請把已確認的 Savvy 分店識別碼和地圖的 `placeId` 建立對應，再帶入該分店的已審核貼文。開啟 pin、瀏覽公開來源或找到同名分店都不會建立使用者收藏。無法確認分店的貼文留待核對。
- [地點卡](place-callout.js) 與 [照片解析](place-photos.js) 是網頁原型的接入位置。目前有九筆附來源且對應到分店識別碼的照片。接入貼文時，有可展示的原圖就顯示圖片及來源，只有原文連結就保留文字卡與連結。請用有圖、無圖、同名不同分店三種情境驗收。

iPhone Debug 預覽以 `SAVVY_DATE_PLAN_PHONE_PREVIEW` 與 `SAVVY_TAIPEI_SOURCE_SNAPSHOT` 啟用本地來源。建置時，`SAVVY_LOCAL_POCKET_CITY_SOURCES` 指向下方轉換出的地圖 JSON，`SAVVY_LOCAL_NATIVE_SOURCES` 指向同一批已審核、仍有效的原生公開貼文快照。兩者皆為本地輸入。分店詳情由 Savvy 的原生面板顯示，地圖保留選中 pin 的動畫。

從 repo 根目錄把已審核的公開索引轉成這個預覽的地點資料。最後一個參數是同一套索引版本的已編譯後端驗證器。

```sh
node Prototypes/TaipeiPocketCity/tools/build-savvy-place-sources.mjs \
  /path/to/active-index.json \
  Prototypes/TaipeiPocketCity/data/city-place-index.json.gz \
  /path/to/localized-addresses.json \
  Prototypes/TaipeiPocketCity/savvy-place-sources.json \
  /path/to/backend/dist/publicDiscovery.js
```

工具依 Savvy 分店 ID 與 Pocket City `placeId` 建立對照。自動比對要求相同店名、行政區、完整門牌與鄰近座標。具名的已審查對照另驗證兩邊的名稱與地址。

同一地點的來源已審核、地圖分店 ID 尚待核對時，用 Savvy 原有的公開地點座標顯示獨立 pin，搜尋也可找到。原文只綁定這個 Savvy 地點 ID。地點仍有有效原文就會顯示在地圖上，最後一篇到期後移除該 Savvy pin。底圖地點沿用自己的識別碼和地點卡。

畫面讀取本機生成的貼文網址、標題、作者及可展示的照片。產出的 `savvy-place-sources.json` 供本機預覽使用，索引更新後可以重建。

## Mac 上看 Apple 地點

在 macOS 15 以上，安裝 Xcode 命令列工具後，從專案根目錄執行以下指令。開啟的視窗從大安區復興南路出發。拖曳可移到附近街口，點選地點標記可看 Apple 提供的詳細資訊。原生版先查詢目前視野內的地點。若附近查詢不提供結果，則查詢視野內的餐廳。可在下方輸入店名、書店或咖啡等類別。原生版直接使用系統 MapKit，無須設定網頁 token。地圖、地點與地點卡需要連線。

```sh
cd Prototypes/TaipeiPocketCity
python3 prepare_data.py
bash native/run.sh
```

## 在瀏覽器開啟 3D 街景

從專案根目錄執行。首次還原需要 Python 3.9 以上。圖資封裝檔約 242 MiB，另預留 650 MiB 還原空間。

```sh
cd Prototypes/TaipeiPocketCity
python3 prepare_data.py
python3 -m http.server 42418 --bind 127.0.0.1
```

- [復興南路書店](http://127.0.0.1:42418/index.html?street=fuxing)可從同一鏡位切換「舊版對照」或隱藏店名。點「看整排」拉遠。搜尋框能跳到其他行政區。
- [Apple 地點](http://127.0.0.1:42418/apple.html)使用 MapKit JS。請在此資料夾建立 Git 忽略的 `apple-config.js`，內容為 `export const token = "YOUR_PUBLIC_MAPKIT_JS_TOKEN";`。請使用允許實際預覽主機的瀏覽器 token。所有 Apple 私鑰都應存放在網頁服務目錄之外。兩種模式的底圖服務需要網路。[MapKit JS 文件](https://developer.apple.com/documentation/mapkitjs)
- Apple 地圖自行選取當前比例下顯示的地點。選取 Apple 地點只開地點資訊。Apple 地點與原型收錄的店家分別由 Apple 和公開圖資提供，兩份資料的收錄範圍可能不同。
- 原始的 [台北 101 收藏印章示範](../Taipei101PocketCity/README.md)可獨立執行。

## Apple 地圖與插畫的資料來源

Mac 版透過 MapKit 即時取得地點。Apple 提供的地點只顯示在 Apple 地圖上，不寫進插畫圖包或 Savvy 收藏。插畫幾何來自獨立公開圖資，兩種底圖都能使用這份插畫。保留 Apple 和供應商標示及 OpenStreetMap 署名。[Apple 地圖服務條款，附件 6](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) · [OSM 授權與署名](https://www.openstreetmap.org/copyright)

## 圖資與來源

台北 12 區按 170 公尺街廓整理。3D 版保留市府建物量體、24,072 筆可定位的來源店家和公共樹籍。7,906 筆可對上臨街外牆。復興南路示範街廓有 19 間店面。信義書局的紅招牌與騎樓參照紀錄照片，書架、入口深度及鄰店外觀為插畫重建。[信義書局紀錄](https://www.dream-land.com.tw/56%E4%BF%A1%E7%BE%A9%E6%9B%B8%E5%B1%80/)

- 道路、建物輪廓與地點採 © OpenStreetMap contributors。OSM 衍生資料以 ODbL 1.0 提供，原始出處與擷取版本隨資料附於 `data/city170/index.json`。地圖署名見圖面。[OpenStreetMap 授權](https://www.openstreetmap.org/copyright)
- 臺北市政府都市發展局提供 2025 年 LOD1 模型。市府商業處、衛生局、市場處、公園處與捷運工程局提供其他圖層，各來源列於圖面及資料摘要。[LOD1 服務](https://historygis.udd.gov.taipei/arcgis/rest/services/Hosted/LOD1_2025/SceneServer) · [都發局資料開放宣告](https://udd.gov.taipei/QA/article/ngork7d) · [公共樹籍](https://data.gov.tw/dataset/128274)
- 3D 街景使用 OpenFreeMap、OpenMapTiles、Mapzen 地形及 MapLibre GL JS。插畫參考 April Zhu 的 Pocket City 與 Pocket Nature。[Pocket City](https://april-zhu.com/pocketcity) · [Pocket Nature](https://april-zhu.com/pocketnature) · [Pocket City 授權](assets/Pocket-City-LICENSE.txt) · [MapLibre 授權](assets/MapLibre-LICENSE.txt)

`prepare_data.py` 會查核每包 SHA-256，還原完成才建立 `data/`。可用 `tools/bundle_data.py <準備好的圖資資料夾> <輸出資料夾>` 重新封裝。封裝與還原會保留每份資料解壓後的內容，gzip 壓縮位元組可能不同。`scripts/` 保留地圖資料與模型的製作工具，各自使用原始來源與額外的製圖相依套件。

## 台北 170 公尺逐格稽核

台北市的 9,686 個格子沿市界裁切，跨格地物共用同一筆幾何。逐格稽核會用封裝後的地圖核對建物、道路、學校、店面、自然地貌及相鄰資料包，輸出各行政區摘要和每格一行的 JSONL。市府 2025 實測建物仍使用原始 200 公尺資料包，稽核依地理位置對回 170 公尺格。

```sh
python tools/audit-taipei-cells.py --data /path/to/PocketCity/data --osm /path/to/taipei.json.gz --output /path/to/audit
```

校園球場的插畫畫線依公開的運動類型、外框與尺寸產生。地面階梯、溪流和溝渠採用原始路線；草地、濕地、農地與果園保留來源邊界。可以在同一張圖查看[育達高中](http://127.0.0.1:42418/index.html?view=121.55419,25.05009,18.55&bearing=-16&pitch=32)和[關渡平原](http://127.0.0.1:42418/index.html?view=121.476947,25.123890,16.85&bearing=-14&pitch=28)。

## 在同一張地圖移到其他縣市

開啟時地球朝向東亞。拖曳可轉到另一個半球，持續放大會在同一張地圖看見街道。城市名稱、地標和店家依比例尺顯示，移到有手繪內容的位置就會自動載入建築、街道、樹木與行人。「回到地球」可隨時拉回球體全景。從網址開啟時也可指定街區，例如 [淡水紅毛城](http://127.0.0.1:42418/index.html?city=tamsui)。每個手繪街區的範圍和來源可查閱 [城市索引](cities/catalog.json)。[街區製作與驗收流程](CITY-WORKFLOW.md)

台北以外的 21 縣市共收錄 521,303 個建物輪廓。圖資有記載時，以各棟的外牆色、屋頂色和材質繪製。其餘街屋沿用台北的窗框、玻璃與線腳，搭配 Pocket City 的暖色牆面、綠色窗框和靛藍遮棚。拉近會看到對應的店面。18 個地標街區也重建了周邊街屋的配色。各縣市的公開欄位及涵蓋數可查閱[建物材質索引](taiwan/materials/index.json)。
