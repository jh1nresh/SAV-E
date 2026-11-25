import {cityPlaceID} from './savvy-place-sources.js';

const entries = [
  {
    id: 'poi/node/7175344617',
    name: '福州世祖胡椒餅',
    point: [121.5774695, 25.0509974],
    categoryLabel: '夜市小吃',
    detail: '松山區 · 饒河街觀光夜市創始攤',
    file: 'raohe-pepper-bun.jpg',
    alt: '饒河街福州世祖胡椒餅創始攤的招牌與製作胡椒餅的店員',
    credit: '玄史生 · 2018 · CC0 1.0 · 縮圖',
    commonsFile: '福州世祖胡椒餅_饒河夜市創始店_20180714a.jpg',
  },
  {
    id: 'poi/node/2861307508',
    name: '阜杭豆漿',
    point: [121.5247742, 25.0442057],
    categoryLabel: '早餐店',
    detail: '中正區 · 華山市場二樓',
    file: 'fu-hang-soy-milk.jpg',
    alt: '阜杭豆漿的一碗豆漿和油條',
    credit: 'KQuhen · 2010 · CC BY-SA 4.0 · 縮圖',
    commonsFile: 'Doujiang_and_youtiao_Taipei.jpg',
  },
  {
    id: 'poi/node/2572568042',
    name: '阿宗麵線',
    point: [121.5076858, 25.0433177],
    categoryLabel: '小吃店',
    detail: '萬華區 · 峨眉街西門店',
    file: 'ay-chung-ximen.jpg',
    alt: '峨眉街阿宗麵線西門店的招牌與店前人潮',
    credit: 'Tzuhsun Hsu · 2017 · CC BY-SA 2.0 · 縮圖',
    commonsFile: 'Ay-Chung_Flour-Rice_Noodle_20170904a.jpg',
  },
  {
    id: 'poi/node/3007181095',
    name: '美觀園 36 號本舖',
    point: [121.5065422, 25.0434442],
    categoryLabel: '餐廳',
    detail: '萬華區 · 峨眉街 36 號',
    file: 'mei-36.jpg',
    alt: '峨眉街 36 號美觀園的金色招牌與店門',
    credit: '阿道 · 2023 · CC BY-SA 4.0 · 縮圖',
    commonsFile: 'Meiguanyuan-no.36.2023-05-04.jpg',
  },
  {
    id: 'poi/node/3007181096',
    name: '美觀園 47 號店',
    point: [121.5068365, 25.0436012],
    categoryLabel: '餐廳',
    detail: '萬華區 · 峨眉街 47 號',
    file: 'mei-47.jpg',
    alt: '峨眉街 47 號美觀園的黑色直式招牌與入口',
    credit: '阿道 · 2023 · CC BY-SA 4.0 · 縮圖',
    commonsFile: 'Meiguanyuan-no.47.2023-05-04.jpg',
  },
  {
    id: 'poi/node/2426176904',
    name: '鼎泰豐 信義本店',
    point: [121.5301015, 25.0335186],
    categoryLabel: '餐廳',
    detail: '大安區 · 信義路二段 194 號',
    file: 'din-tai-fung-xinyi.jpg',
    alt: '鼎泰豐信義本店面向信義路二段的紅色招牌與騎樓',
    credit: 'Yu tptw · 2023 · CC BY-SA 4.0 · 縮圖',
    commonsFile: 'Din_Tai_Fung_Xinyi_Branch_20230704.jpg',
  },
  {
    id: 'poi/node/4888000022',
    name: '天津蔥抓餅',
    point: [121.5296873, 25.0326521],
    categoryLabel: '小吃店',
    detail: '大安區 · 永康街 6 巷 1 號',
    file: 'tianjin.jpg',
    alt: '永康街口天津蔥抓餅的攤位與排隊人潮',
    credit: 'Ounfs Robmmy 238 · 2024 · CC0 1.0 · 縮圖',
    commonsFile: 'TW_台灣_Taiwan_台北_Taipei_永康街_YongKang_Street_天津蔥抓餅_food_shop_March_2024_R12S_05.jpg',
  },
  {
    id: 'poi/node/3656220731',
    name: '永康牛肉麵',
    point: [121.5280834, 25.0329201],
    categoryLabel: '餐廳',
    detail: '大安區 · 金山南路二段 31 巷 17 號',
    file: 'yong-kang.jpg',
    alt: '永康牛肉麵店面及門口上方的黃色招牌',
    credit: 'Solomon203 · 2022 · CC BY-SA 4.0 · 縮圖',
    commonsFile: 'Yong-Kang_Beef_Noodle_20220918.jpg',
  },
  {
    id: 'poi/way/1131522120',
    name: '富邦美術館',
    point: [121.571232, 25.0392836],
    categoryLabel: '博物館',
    detail: '信義區 · 松高路 79 號',
    file: 'fubon-museum.jpg',
    alt: '松高路富邦美術館入口與館前廣場',
    credit: '阿道 · 2024 · CC BY-SA 4.0 · 縮圖',
    commonsFile: 'Fubon_Art_Museum_20241127.jpg',
  },
];

const photosById = new Map(entries.map(entry => [entry.id, entry]));

export const photoPlaces = entries.map(({id, name, point, categoryLabel, detail}) => ({
  placeId:id, name, point, categoryLabel, detail,
  source: 'OpenStreetMap',
  url: `https://www.openstreetmap.org/${id.slice(4)}`,
}));

export function originalPlacePhoto(place) {
  const id = cityPlaceID(place);
  const entry = photosById.get(id);
  if (!entry) return null;
  return {
    file: entry.file,
    src: new URL(`./assets/place-photos/${entry.file}`, import.meta.url).href,
    alt: entry.alt,
    credit: entry.credit,
    url: `https://commons.wikimedia.org/wiki/File:${encodeURIComponent(entry.commonsFile)}`,
  };
}
