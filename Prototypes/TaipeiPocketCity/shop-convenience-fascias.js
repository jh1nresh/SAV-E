import {storeBrandGroups} from './taipei-convenience-art.js';

const brands=new Map();
for(const [brand,kind,ids] of storeBrandGroups){
  for(const id of ids.split(' '))brands.set('poi/'+kind+'/'+id,brand);
}

const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
const fascia=(brand,background,ink,bands)=>({brand,background:rgb(background),ink:rgb(ink),bands:bands.map(rgb)});
// Illustrative colour bands. Wide glass and the fascia proportions reference
// Taiwanese shop fronts and Polyfork's convenience-store-c30e1d. The place
// name uses the existing map texture and every band fits the measured bay.
const paper='#faf0d6', dark='#303635';
const palettes={
  seven:fascia('seven',paper,dark,['#dc894b','#478e6b','#b74d47']),
  family:fascia('family','#edf0dc',dark,['#7ab265','#467eaa']),
  hilife:fascia('hilife','#dcefe4',dark,['#8fc8bc','#397f87']),
  ok:fascia('ok','#a63a35',paper,['#d99148']),
  shopee:fascia('shopee','#b04630',paper,['#e8a05b']),
};

export function convenienceFascia(row){
  if(row.category==='convenience')return palettes[brands.get(row.id)];
}
