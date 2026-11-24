# 玉山與台灣中高山

台灣本島圖版沿用既有的國土測繪中心鄉鎮界海陸遮罩。玉山近景以主峰（東經 120.957274°、北緯 23.469987°）為中心，涵蓋約 13.5 × 11.2 公里。兩張圖版皆使用 Web Mercator，四角座標、輸入與成品的 SHA-256 均見同目錄的 `index.js`。[內政部鄉鎮界](https://data.gov.tw/dataset/7441) · [主峰定位點](https://www.openstreetmap.org/node/3428095932)

山脊、谷地、坡向明暗及細等高線來自 Mapzen Terrarium DEM。台灣本島取 XYZ z10，玉山圖版取 z14，並附主峰周邊 z10–14 的地形瓦片。玉山定位點的 z14 柵格高程為 3,920 公尺，峰頂實地海拔約 3,952 公尺。山頂尖稜在柵格中會被平滑化。原始 z14 瓦片在 121°E 附近有單欄深度異常，兩側山坡約高 2,000–3,000 公尺，欄內降至海平面以下數千公尺。在玉山圖版和本機 DEM 裡，以左右相鄰高程內插這些異常像素，各瓦片修正數記錄在 `voidSamplesRepaired`。[Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) · [Mapzen／各高程圖資署名](https://github.com/tilezen/joerd/blob/master/docs/attribution.md) · [玉山國家公園山岳介紹](https://www.ysnp.gov.tw/StaticPage/Mountain)

針闊葉林冠、冷杉群、草坡與岩面筆觸為原創插畫符號，依高程、日照方向與坡度配置。玉山的鐵杉雲杉林帶約在 2,500–3,100 公尺，冷杉林帶約在 3,100–3,600 公尺，3,600 公尺以上進入高山植群。圖中樹群代表一片林相，沒有逐株或逐坡生態調查。山坡上的岩紋依等高線方向繪製。色面、輪廓線與成簇的樹冠參考 Pocket Nature 的繪製方式。[玉山國家公園植群分帶](https://www.ysnp.gov.tw/StaticPage/Plant) · [Pocket Nature](https://april-zhu.com/pocketnature)

海拔 520 公尺以下與收錄的水域面透明，520 至 1,000 公尺之間漸入，區域圖保留沿海聚落和街道。湖泊與水庫遮罩沿用台灣山水圖層的 OpenStreetMap 水域面。玉山圖版邊緣另做約 875 公尺的透明過渡。[水域來源與授權](../scenery/SOURCES.md)

重建時在 TaipeiPocketCity 目錄執行下列指令，需 Python 3、Pillow、NumPy 及 SciPy。有缺少的 DEM 瓦片時，產生器會向公開的 Terrain Tiles 下載。

```sh
python3 -B tools/build-taiwan-mountains.py --cache /tmp/savvy-tw-relief-dem
python3 -B tools/test_taiwan_mountains.py
```
