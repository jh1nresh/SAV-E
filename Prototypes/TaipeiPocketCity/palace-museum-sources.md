# 國立故宮博物院正館

原版紙模型在地圖上沿東西向放置。新版保留既有 WGS84 錨點 `121.548544, 25.102274`，依正館南側主要立面向東偏北旋轉 25.2°。原始立面端點為 `(121.5482712, 25.1017663)` 和 `(121.5491092, 25.1021239)`，全館東西向展開約 135 m。[OpenStreetMap 正館建物輪廓](https://www.openstreetmap.org/way/203799171)

按正面影像拆出高中央殿、低側翼、上翹的綠釉斜屋面與赭色屋脊。正入口、玻璃下沉區和兩側白欄階梯依正面照片及前廣場平面圖定位。第一段雙階從約 39.4 m 上到 44.7 m，第二段參照現有 14 級 DEM 的廣場坡度。中央殿和兩側翼亭的屋脊依現有建物測量分區放置，最高點約 64.58 m。這些是 3D 地圖採用的近似標高和外觀，屋頂曲線與細節為手工重建。[國立故宮博物院館舍沿革](https://www.npm.gov.tw/Articles.aspx?l=1&sno=03012533) · [故宮正面廣場平面圖](https://south.npm.gov.tw/FileDownLoad/FileUpload/20190501174630359785.pdf) · [臺北市觀光傳播局正館照片](https://www.travel.taipei/ja/fun/tour/details/1322) · [正館與雙階正面照片](https://orientaldaily.on.cc/asset/china_world/20221107/photo/1107-00178-022b1.jpg)

`palace-museum.js` 產生與現行 SurveyLayer 相容的三角形資料。原有圖包中的索引仍提供展館錨點和載入範圍，SurveyLayer 為同一筆展館紀錄使用本模組的模型。既有圖包還原後即可用 `?landmark=palace-museum` 檢視。`node --test tools/palace-museum.test.mjs` 驗證幾何格式、平面位置、高低屋脊及前階與入口位置。
