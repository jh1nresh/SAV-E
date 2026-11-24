// Street-scale glyphs refine existing POIs using declared trades only.
import {shopCategories} from './shop-categories.js';
import {bikeStationPlace} from './city170-bike-docks.js';
import {registerPlaceBadge} from './place-pins.js?v=street-trades-1';

const food = {disc:'#ffb469',ink:'#542805',label:'#954107'};
const craft = {disc:'#84d8c9',ink:'#124b48',label:'#096963'};
const fashion = {disc:'#d7a9e6',ink:'#532c70',label:'#723d88'};
const garden = {disc:'#a4d983',ink:'#2c5229',label:'#386b34'};
const tech = {disc:'#9acbf0',ink:'#264669',label:'#335f87'};
const trade=(categories,name,palette,lines,solid='')=>({categories,name,...palette,lines,solid});
const trades={
  bakery:trade(['bakery','bakery_shop','pastry'],'烘焙店',food,
    'M6 11c-1-3 2-5 6-5s7 2 6 5l-1 5.5H7z M9 8.5l1.5 2 M13 8l1.5 2'),
  drinks:trade(['beverages','bubble_tea'],'飲料店',food,
    'M7.5 9.5h9L15 18h-6z M7 9h10 M12.5 9l1-4h2'),
  icecream:trade(['ice_cream'],'冰淇淋店',food,
    'M7 11a5 5 0 1 1 10 0z','M8 13h8l-4 6z'),
  bar:trade(['bar','pub'],'酒吧',food,
    'M6 7h12l-6 6z M12 13v5 M9 18h6'),
  groceries:trade(['supermarket','convenience','grocery'],'食品雜貨',craft,
    'M5.5 10h13L17 17H7z M8 10l3-4 M16 10l-3-4 M10.5 12.5v2 M13.5 12.5v2'),
  florist:trade(['florist'],'花店',garden,
    'M12 14v5 M12 16q-3 0-4-2 M12 16l4-2',
    'M12 6c1-3 5-2 4 1 4-1 5 3 2 4 1 3-3 5-5 2-2 3-6 2-5-1-4 0-4-4-1-5 0-3 4-3 5-1z'),
  produce:trade(['greengrocer'],'蔬果店',garden,
    'M12 9q-1-3-3-4 M12 8q1-3 4-3',
    'M12 10c4-3 8 0 5 6-1 3-3 3-5 2-2 1-4 1-5-2-3-6 1-9 5-6z'),
  hair:trade(['hairdresser','barber'],'美髮店',fashion,
    'M9.5 15l7-9.5 M10 6l7.5 9 M9.5 16a2 2 0 1 1-4 0 2 2 0 1 1 4 0 M18.5 16a2 2 0 1 1-4 0 2 2 0 1 1 4 0'),
  optics:trade(['optician'],'眼鏡行',tech,
    'M4.8 11h5.7v2a2.85 2.85 0 0 1-5.7 0z M13.5 11h5.7v2a2.85 2.85 0 0 1-5.7 0z M10.5 12h3 M5 11l1.1-3 M19 11l-1.1-3'),
  laundry:trade(['laundry'],'洗衣店',tech,
    'M7 5.8h10v12.4H7z M7 9.3h10 M14.5 13.7a2.5 2.5 0 1 1-5 0 2.5 2.5 0 1 1 5 0'),
  shoes:trade(['shoes'],'鞋店',fashion,
    'M6 9l3 1.5L12 9l2 3.8 4 1.5v2.5H6z M6 14.8h4.5'),
  jewelry:trade(['jewelry'],'珠寶店',fashion,
    'M5.3 9.7l3.2-3.5h7l3.2 3.5L12 18z M5.5 10h13 M10.5 10l1.5 7 1.5-7'),
  phone:trade(['mobile_phone'],'手機行',tech,
    'M8.5 5.5h7v13h-7z M11.2 16h1.6'),
  electronics:trade(['computer','electronics'],'電子商店',tech,
    'M5.8 7.3h12.4v8H5.8z M12 15.3v2.3 M9 18h6'),
  furniture:trade(['furniture'],'家具店',craft,
    'M8 6v7.3h9 M7 14h10 M8 14v4 M16 14v4 M8 7h7v4'),
  hardware:trade(['hardware','doityourself'],'五金建材',craft,
    'M6 17.5l8.5-8.5 M11 6.4l2-2 6.2 6.2-2 2z'),
  gift:trade(['gift'],'禮品店',fashion,
    'M6 10h12v3H6z M7.5 13v4.8h9V13 M12 9v8 M12 9c-7 0-4-7-1-3z M12 9c7 0 4-7 1-3z'),
};
const byCategory=new Map(Object.values(trades).flatMap(item=>item.categories.map(category=>[category,item])));

export function streetShopProperties(properties){
  if(properties.category==='bicycle_rental')return bikeStationPlace(properties);
  const key=properties.category;
  const label=byCategory.get(key)?.name ?? (Object.hasOwn(shopCategories,key) ? shopCategories[key][0] : null);
  if(!label || (properties.categoryLabel && properties.categoryLabel!==key))return properties;
  const localized={...properties,categoryLabel:label};
  if(localized.detail===key)localized.detail=label;
  return localized;
}

export function streetShopPinStyle(map,pin){
  const icons=[],colors=[];
  for(const [key,item] of Object.entries(trades)){
    const id='place-trade-'+key;
    registerPlaceBadge(map,id,item);
    icons.push(item.categories,id);
    colors.push(item.categories,item.label);
  }
  const atStreet=(mapping,fallback)=>['step',['zoom'],fallback,19,
    ['match',['coalesce',['get','category'],''],...mapping,fallback]];
  return {
    layout:{...pin.layout,'icon-image':atStreet(icons,pin.layout['icon-image'])},
    paint:{...pin.paint,'text-color':atStreet(colors,pin.paint['text-color'])},
  };
}
