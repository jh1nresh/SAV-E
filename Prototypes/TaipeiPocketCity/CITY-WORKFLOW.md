# 在 Savvy 地圖加入 Pocket City 街區

使用者可以從台北拖曳至新北，在紅毛城的實際位置看見主堡、領事官邸和南門。選擇其他縣市或海外城市時也共用同一張地圖。點選位置只開啟地點卡。使用者確認收藏後才建立 Map Stamp。

## 決定畫哪一塊

選一個具有辨識度的地標和鄰近街道，以 170 公尺見方為起點。若園區或相關建物會被切斷，依照實際長度放大。記下主要的屋頂、入口朝向和隔壁建物的相對位置，對照地標管理單位的照片或平面圖。從多個方向檢查外觀。故宮的測試保留了原先主殿軸線和量體的回歸案例。[故宮建模依據](palace-museum-sources.md)

以 WGS84 經緯度對齊 OpenStreetMap 和 MapLibre。地標位置若來自只有點位的官方資料或 OSM 節點，保留點位來源。在 metadata 指明以實測輪廓或地點作為定位依據。立面細節與沒有測量依據的尺度需要標成插畫。底圖、實際街區模型、以及尚待確認的店家資料各保留其來源。

## 產生一個可接入的街區

1. 在 `cities/<id>/` 保存資料來源、日期、範圍和 OSM 幾何。用 Pocket City 的 `scripts/plot.py` 保護地標，再用 `scripts/prep.py` 產生 metre grid 與街區資料。對只有周邊水域的方格，可使用 `tools/prepare_city_scene.py SKILL_DIR cities/<id>` 處理空的示意船範圍。
2. 填入 `city.json`、`metadata.json` 和 `landmarks.js`。沿真實外牆的局部軸線畫門窗，保留屋脊、廊道與天井。把主要地標的 OSM 輪廓 ID 放入 `landmarkIds`。對只有地點或院區範圍的地標使用 `landmarkSites` 記錄類型、識別碼和座標。
3. 在 `tools/city_catalog.py` 設定地區順序。使用下列命令以同一個 kit 產生插畫與主地圖要讀取的三角網格。地面和路名由同一組局部座標換回經緯度。地標的建築部件共用地面錨點，獨立建物分別取樣地形。
4. 從主地圖實際拉近、旋轉、離開再回來，確認屋頂方向、地形接合、街道與選點。要看不同地區，用頁首選單移動現有鏡頭。以同一台裝置、經緯度、方位與倍率留存修改前後的畫面，再更新 PR。

在原型目錄執行，將環境變數指向已安裝的 Pocket City skill。

```sh
python3 -B tools/city_workflow.py build tamsui --skill-dir "$POCKET_CITY_SKILL"
python3 -B tools/city_catalog.py
python3 -B tools/city_workflow.py verify
node --test tools/*.test.mjs
```

`catalog.json` 只索引有場景、網格和出處的街區。一般街段使用地圖服務提供的道路與建物輪廓。公開圖資的店家或建物缺口會保留。Savvy 的貼文照片及個人筆記沿用地點資料介面，有原圖才顯示。每個縣市的手繪地標範圍由索引中的 `bounds` 和 `sizeMeters` 表示。

每個地標周邊的少量 OpenFreeMap 向量圖磚與 Terrarium 地形圖磚會隨原型提供。重新整理索引後，執行 `python3 -B tools/cache_landmark_tiles.py`，再執行測試。地標外的長距離拖曳仍需連線取得圖磚。圖磚快照來源與署名保存在 `cities/map-tiles/index.json`。
