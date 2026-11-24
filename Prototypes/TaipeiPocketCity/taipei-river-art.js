// River washes and brush marks use ground coordinates so they stay with each bend as the map rotates.
import {decodeMapJSON} from './pocket-city-atlas.js?v=taipei-fronts-2';

const source = 'taipei-river-art';
const washes = {shore:'#b4d0b5', shallows:'#95c3b2', reach:'#78b4af', channel:'#63a4a7'};
const inks = {ripple:'#c2e1ce', glint:'#e6ebcf', shade:'#408e93'};
const fade = (near, far, opacity) => ['interpolate',['linear'],['zoom'],near,0,far,['*',opacity,['get','alpha']]];

export function addTaipeiRiverArt(map, firstLabel) {
  let pending = false, removed = false;
  async function load() {
    if (pending || removed || map.getSource(source) || map.getZoom() < 12) return;
    const view = map.getBounds();
    if (view.getEast()<121.44 || view.getWest()>121.69 || view.getNorth()<24.95 || view.getSouth()>25.23) return;
    pending = true;
    try {
      const response = await fetch(new URL('./assets/taipei-river-art.json.gz?v=bank-fade-2', import.meta.url));
      if (!response.ok) throw Error(String(response.status));
      const data = await decodeMapJSON(response);
      if (removed) return;
      map.addSource(source,{type:'geojson',data,maxzoom:17,tolerance:.35,attribution:'<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a>'});
      const anchor = map.getLayer('landcover_sand') ? 'landcover_sand' : firstLabel;
      for (const [kind,color] of Object.entries(washes)) {
        map.addLayer({id:source+'-'+kind,type:'fill',source,minzoom:12,
          filter:['==',['get','k'],kind],paint:{'fill-color':color,'fill-opacity':fade(12,14,.94)}},anchor);
      }
      for (const [kind,color] of Object.entries(inks)) {
        map.addLayer({id:source+'-'+kind,type:'line',source,minzoom:14.25,
          filter:['==',['get','k'],kind],layout:{'line-cap':'round','line-join':'round'},
          paint:{'line-color':color,'line-opacity':fade(14.25,16,kind === 'shade' ? .49 : .78),
            'line-width':['interpolate',['linear'],['zoom'],14,.5,16,1.25,18,2.1,21,3.4]}},anchor);
      }
      map.addLayer({id:source+'-deck', type:'fill', source, minzoom:15.5,
        filter:['==',['get','k'],'pier-deck'],
        paint:{'fill-color':'#ceb68d','fill-outline-color':'#87775f','fill-opacity':fade(15.5,17,1)}},anchor);
      for (const [part, color, width] of [['rail','#8a7964',3.6],['walk','#e0ccaa',2.1]]) {
        map.addLayer({id:source+'-'+part,type:'line',source,minzoom:15.5,
          filter:['==',['get','k'],'pier-walk'],layout:{'line-join':'round','line-cap':'round'},
          paint:{'line-color':color,'line-opacity':fade(15.5,17,1),
            'line-width':['interpolate',['linear'],['zoom'],15,.8,17,width,20,width*2.6]}},anchor);
      }
      map.off('moveend', load);
    } catch (error) {
      if (!removed) console.warn('Taipei river artwork', error);
    } finally {
      pending = false;
    }
  }
  map.on('remove',()=>{removed=true;});
  map.on('moveend',load);
  load();
}
