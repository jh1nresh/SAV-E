# 新竹市 · 新竹車站

220 公尺方形。以瀏覽器開啟 `index.html` 即可離線旋轉和縮放。`map-mesh.bin` 與 `map-mesh.json` 提供同一地標的共用地圖模型。

## 重建

在此目錄執行以下指令。需要 Python、Shapely、Node 和安裝的 Pocket City 技能。

```bash
kit="${POCKET_CITY_SKILL:-$HOME/.codex/skills/pocket-city}/scripts"
python3 "$kit/plot.py" --osm osm-bbox.json --rotate north --keep '新竹火車站' --out plot.json
python3 "$kit/prep.py" --osm osm-bbox.json --plot plot.json --drive right --out scene.json
python3 "$kit/build.py" --scene scene.json --city city.json --landmarks landmarks.js --out index.html
node ../../tools/export-pocket-mesh.mjs index.html
```

`osm-bbox.json` 保存 OpenStreetMap bbox API 的地物與道路、關係成員位置。各地取樣範圍、主地標 OSM ID 與照片／建築文獻列於 `metadata.json`。立面細節與未測量的高度為插畫。
