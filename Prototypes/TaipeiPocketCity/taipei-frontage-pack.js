import {recoveredFronts} from './taipei-shopfront-recoveries.js';
import {groundFronts} from './taipei-ground-frontages.js';

import {addressFronts} from './taipei-address-frontages.js';
import {surveyFronts} from './taipei-survey-frontages.js';
import {dihuaNorthFronts} from './dihua-north-frontages.js';
import {compactFronts} from './taipei-compact-frontages.js';
import {edgeFronts} from './taipei-edge-frontages.js';
import {registeredFronts} from './taipei-registered-frontages.js';
import {friendlyFronts} from './taipei-friendly-frontages.js';

export const supplements=[...recoveredFronts,...dihuaNorthFronts,...groundFronts,...addressFronts,
  ...surveyFronts,...compactFronts,...edgeFronts,...registeredFronts,...friendlyFronts];
const recoveredByID=new Map(supplements.map(row=>[row.id,row]));

export function frontageSearchRow(row){
  const recovered=row[5]===null&&recoveredByID.get(row[6]);
  return recovered?[row[0],row[1],recovered.street,...recovered.center,recovered.angle,row[6]]:row.slice(0,7);
}

export function completeFrontagePack(pack,rows){
  if(!Array.isArray(rows))throw Error('Invalid Pocket City frontage pack');
  const additions=supplements.filter(r=>r.pack===pack&&!rows.some(primary=>primary.id===r.id));
  return additions.length?rows.concat(additions):rows;
}

const shopFacts=new Map(dihuaNorthFronts.map(row=>[row.id,row]));
export function withShopFacts(feature){
  const row=shopFacts.get(feature.properties.placeId??feature.id);
  if(!row)return feature;
  const {category,categoryLabel,source,url}=row;
  return {...feature,properties:{...feature.properties,category:category==='food'?'shop':category,categoryLabel,source,url}};
}
