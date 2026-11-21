# Savvy 台北 101 收藏地圖原型

這是一個獨立的瀏覽器原型，用台北 101 周邊 250 × 250 公尺的微縮街景展示 Savvy 的收藏印章。印章、到訪狀態和筆記是示範資料，照片是有署名的公開素材。此原型與 Savvy 帳號及原生 App 分開運作。

## 預覽

從 repository 根目錄啟動本機伺服器。

```sh
python3 -m http.server 42101 --bind 127.0.0.1 --directory Prototypes/Taipei101PocketCity
```

在瀏覽器開啟 [本機預覽](http://127.0.0.1:42101/)。

- 拖曳轉動街區，使用右上角的控制項縮放、切換俯瞰或重設視角。鍵盤焦點在地圖時，可使用方向鍵、加減鍵和 Home。
- 點選觀景台、購物中心或信義路街角的印章，確認照片、筆記及選取狀態同步更新。
- 使用右上角的播放控制暫停或繼續播放行人和車流。系統啟用減少動態效果時，街景預設暫停。

## 素材與授權

[index.html](index.html) 內含渲染程式、街景資料和照片，預覽不需要下載外部資源。

- 渲染工具來自 [April Zhu 的 Pocket City](https://april-zhu.com/pocketcity)。MIT 授權全文保留於 HTML 內。
- 嵌入的街景資料源自 [OpenStreetMap contributors](https://www.openstreetmap.org/copyright)，採 [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/)。建築外觀經插畫簡化，塔樓高度經縮放。
- 觀景台照片 [Cathexi，CC BY-SA 2.0](https://commons.wikimedia.org/wiki/File:Sunset_from_Taipei_101_(1280152346).jpg)。
- 購物中心照片 [eugene o，CC BY 2.0](https://commons.wikimedia.org/wiki/File:2017-10-23_Interior_of_Taipei_101_Mall.jpg)。
- 台北 101 街景照片 [Pauloleong2002，CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Taipei_101_in_blue_sky.jpg)。

照片已縮放，並在收藏卡中裁切顯示。頁面附有各照片的來源與授權連結。
