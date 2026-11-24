# 台灣山水圖層

山峰、溫泉、瀑布、海岬、島嶼、公園、保護區與水域的位置來自 OpenStreetMap。點地圖上的名稱可查看資料來源。山頂有圖載高程時，地點卡顯示該筆紀錄的數值。線形地物的標示點取線長中點，面狀地物的標示點取面內代表點。地點資料與湖岸、溪流幾何依 [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/) 提供，署名 [OpenStreetMap contributors](https://www.openstreetmap.org/copyright)。

區域圖上的水域輪廓、河道與露天農圳經過簡化，放大至街道尺度時淡出。即時水位、通行狀態及營業資訊未收錄。台灣本島及離島以內政部鄉鎮市區界篩選，海岸地物另保留約一至一點五公里的近岸範圍。[內政部鄉鎮市區界線](https://data.gov.tw/dataset/7441)

## 圖資與重建

使用 Geofabrik 2026-11-23 Taiwan PBF。東沙島和太平島另由 OSM 地圖 API 讀取公開的海岸與水域地理要素，保留產製所需的精簡 PBF。完整下載位置、SHA-256 與記錄數見 [來源清單](sources.json)。[Geofabrik Taiwan extracts](https://download.geofabrik.de/asia/taiwan.html)

在 TaipeiPocketCity 目錄中，以安裝 pyosmium（Python 套件名為 osmium）及 Shapely 2 的 Python 執行。將原始 PBF 與圖層使用的 WGS84 行政區 FeatureCollection 路徑帶入。

```sh
python3 tools/build-taiwan-scenery.py "$TAIWAN_PBF" \
  --source https://download.geofabrik.de/asia/taiwan/taiwan-261123.osm.pbf \
  --mask "$TAIWAN_TOWNSHIPS_GEOJSON"
node --test tools/taiwan-scenery.test.mjs
```

## 景觀筆記

- 玉山主峰的岩坡與海拔參考玉山國家公園管理處的景觀據點介紹與照片。[玉山主峰](https://www.ysnp.gov.tw/Trail/7fa5c242-df1a-4a8e-bcab-32dc55b1f7b6?ID=980ec5de-bc0d-41a5-b479-add518f66181&Tab=2)
- 日月潭地點卡的拉魯島文化說明參考日月潭國家風景區管理處。[拉魯島](https://www.sunmoonlake.gov.tw/zh-tw/Attractions/Attractions?a=20&id=54)
- 清水斷崖的山海關係與岩性參考太魯閣國家公園管理處景點頁。[清水斷崖](https://www.taroko.gov.tw/ch/trailsAttractions/attractions/8)
