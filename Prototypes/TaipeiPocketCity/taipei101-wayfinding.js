import {mallWayfinding} from './taipei101-wayfinding-data.js';

const id='taipei101-wayfinding';
const empty={type:'FeatureCollection',features:[]};
const textPaint={
  'text-color':['match',['get','role'],'entrance','#7c4d27','#5c4a36'],
  'text-halo-color':'#fffaed','text-halo-width':1.2,
};
const iconColor=['match',['get','role'],'entrance','#bc7644','#8a7463'];

export function addMallWayfinding(map,namesVisible){
  map.addSource(id,{type:'geojson',data:empty,maxzoom:22,tolerance:0});
  const add=(key,type,options)=>map.addLayer({id:id+'-'+key,source:id,type,...options});
  add('blocks','fill',{filter:['==',['get','role'],'block'],
    paint:{'fill-color':'#e7dcc3','fill-outline-color':'#d6c9ad'}});
  add('walk','fill',{filter:['==',['get','role'],'walk'],
    paint:{'fill-color':'#fffaf0','fill-outline-color':'#dccfaf'}});
  add('zones','fill',{filter:['==',['get','role'],'area'],
    paint:{'fill-color':['match',['get','style'],
      'centre','#e5c4a1','east','#b9d4d8','south','#c1d7b1','food','#efd6b2','gifts','#ddd0dc','#eee5cb'],
    'fill-outline-color':'#c9b698'}});
  add('markers','circle',{filter:['in',['get','role'],['literal',['entrance','lift','escalator']]],
    minzoom:17.45,paint:{'circle-color':iconColor,'circle-stroke-color':'#fffaf0','circle-stroke-width':1.4,
      'circle-radius':['match',['get','role'],'entrance',4.5,3]}});
  const text={'text-field':['get','name'],'text-font':['Noto Sans Bold'],
    'text-size':['match',['get','role'],'zone',13,11],'text-padding':3,
    visibility:namesVisible?'visible':'none'};
  add('names','symbol',{minzoom:17.45,filter:['all',['==',['geometry-type'],'Point'],['!=',['get','role'],'entrance']],
    layout:{...text,'text-variable-anchor':['top','bottom','left','right'],'text-radial-offset':.55,
      'symbol-sort-key':['match',['get','role'],'zone',0,1]},paint:textPaint});
  add('entrance-names','symbol',{minzoom:17.45,filter:['==',['get','role'],'entrance'],
    layout:{...text,'text-anchor':['match',['get','style'],'east','right','top'],
      'text-offset':['match',['get','style'],'east',['literal',[-.68,0]],['literal',[0,.7]]]},paint:textPaint});
  return {
    show(floor){
      const plan=mallWayfinding[floor];
      map.getSource(id).setData(plan?.drawing??empty);
      return Boolean(plan);
    },
    setNames(visible){
      for(const key of ['names','entrance-names'])map.setLayoutProperty(id+'-'+key,'visibility',visible?'visible':'none');
    },
  };
}
