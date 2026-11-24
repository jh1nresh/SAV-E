import {readPocketCityAsset} from './pocket-city-atlas.js?v=taipei-fronts-2';

const extent=[121.5494,25.0644,121.5561,25.0662];
const source='city170-airfield';
const detailZoom=15;

export function addCityAirfield(map,beforeId){
  const layers=map.getStyle().layers;
  const before=layers.find(layer=>layer.id===beforeId||
    ['transportation','building'].includes(layer['source-layer']))?.id;
  map.addSource(source,{type:'geojson',data:{type:'FeatureCollection',features:[]},maxzoom:18});
  map.addLayer({id:source+'-pavement',source,type:'fill',minzoom:detailZoom,
    filter:['==',['get','surface'],'apron'],paint:{'fill-color':'#d4cbb8'}},before);
  map.addLayer({id:source+'-paths',source,type:'line',minzoom:detailZoom,
    filter:['==',['get','surface'],'taxiway'],layout:{'line-cap':'round','line-join':'round'},
    paint:{'line-color':'#bcb5a5','line-width':['interpolate',['linear'],['zoom'],15,1.3,20,4]}},before);

  let pending=false,removed=false;
  async function update(){
    if(pending||removed||map.getZoom()<detailZoom)return;
    const bounds=map.getBounds();
    if(bounds.getWest()>extent[2]||bounds.getEast()<extent[0]||
       bounds.getSouth()>extent[3]||bounds.getNorth()<extent[1])return;
    pending=true;
    try{
      const data=await readPocketCityAsset(source);
      if(!removed){
        map.getSource(source).setData(data);
        map.off('moveend',update);
      }
    }catch(error){
      if(!removed)console.warn('Taipei civilian apron',error.message);
    }finally{pending=false;}
  }
  map.on('moveend',update);
  map.on('remove',()=>{removed=true;map.off('moveend',update);});
  void update();
}
