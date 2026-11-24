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
];

export const photoPlaces = entries.map(({id, name, point, categoryLabel, detail}) => ({
  placeId:id, name, point, categoryLabel, detail,
  source: 'OpenStreetMap',
  url: `https://www.openstreetmap.org/${id.slice(4)}`,
}));

export function originalPlacePhoto(place) {
  const id = cityPlaceID(place);
  const entry = entries.find(entry => entry.id === id);
  if (!entry) return null;
  return {
    src: new URL(`./assets/place-photos/${entry.file}`, import.meta.url).href,
    alt: entry.alt,
    credit: entry.credit,
    url: `https://commons.wikimedia.org/wiki/File:${encodeURIComponent(entry.commonsFile)}`,
  };
}
