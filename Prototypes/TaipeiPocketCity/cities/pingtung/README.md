# 鵝鑾鼻燈塔

OSM way 310320724 和 310320728 提供燈塔與圍牆線位。白色圓塔高 21.4 m，燈室、鐵欄、官舍與白牆依照片建模。`refine-scene.py` 保留環塔的開放草地。

190 m 方形場景。OSM 原始擷取時間為 `2026-11-23T18:23:34.824121+00:00`。從原型根目錄執行 `python3 -B tools/city_workflow.py build pingtung --skill-dir "$POCKET_CITY_SKILL"`，可重建 HTML 與主地圖網格。 若重做 `scene.json`，再執行 `python3 -B cities/pingtung/refine-scene.py`。

- [OpenStreetMap contributors · 實地輪廓](https://api.openstreetmap.org/api/0.6/map?bbox=120.8502185,21.8999960,120.8553015,21.9047440)
- [交通部航港局 · 鵝鑾鼻燈塔](https://lighthouse.motcmpb.gov.tw/lighthouse_3_20.html)
- [燈塔、燈室與欄杆照片](https://commons.wikimedia.org/wiki/File:Eluanbi_Lighthouse_20240918-3.jpg)
- [中央氣象署 · 氣候統計](https://www.cwa.gov.tw/V8/C/C/Statistics/monthlydata.html)
