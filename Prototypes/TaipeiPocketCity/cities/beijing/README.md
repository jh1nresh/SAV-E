# 北京 · 天壇祈年殿

在 Savvy 主地圖選擇本街區，或從 `../../?city=beijing` 定位。此 240 公尺方形包含祈年殿、祈年門、皇乾殿及東西配殿。

## 重建

在此目錄執行以下指令。需要 Python 3.9+、Shapely 與 Pocket City 技能。

```bash
kit="${POCKET_CITY_SKILL:-$HOME/.codex/skills/pocket-city}/scripts"
python3 "$kit/plot.py" --osm osm-bbox.json --rotate north --keep '祈年殿;祈年门;皇乾殿;东配殿;西配殿' --out plot.json
python3 "$kit/prep.py" --osm osm-bbox.json --plot plot.json --drive right --out scene.json
python3 refine-scene.py
python3 "$kit/build.py" --scene scene.json --city city.json --landmarks landmarks.js --out index.html
```

`osm-bbox.json` 保存官方 OSM bbox API 回傳的有標籤地物，並補入同一份資料中的道路節點與關係成員座標。來源網址記於 `metadata.json`。`refine-scene.py` 依已標記的院牆界線補入石鋪庭院。層高、樹種配置、人物與天候有插畫詮釋。
