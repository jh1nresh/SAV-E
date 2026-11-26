import catalog from './taipei-open-shop-catalog-data.js';

export const taipeiDoorplateDataset = 'https://data.gov.tw/dataset/155472';
export const isDuplicateShop = id => Object.hasOwn(catalog.aliases,id);
export const canonicalShopId = id => isDuplicateShop(id) ? catalog.aliases[id] : id;

export function withOpenShopAddress(place){
  const id=canonicalShopId(place.placeId??place.id);
  if(!Object.hasOwn(catalog.entries,id))return place;
  return {...place,...catalog.entries[id],openShopAddress:true};
}

export function addressShopFeature(feature){
  const properties=withOpenShopAddress(feature.properties);
  return properties===feature.properties?feature:{...feature,properties};
}

export const addedOpenShops=catalog.added.map(addressShopFeature);

export function doorplatePoint(place){
  return place.verifiedDoor?[place.navLng,place.navLat]:null;
}
