// River washes and brush marks use ground coordinates so they stay with each bend as the map rotates.
import {decodeMapJSON} from './pocket-city-atlas.js?v=taipei-fronts-2';

const source = 'taipei-river-art';
const washes = {shore:'#b4d0b5', shallows:'#95c3b2', reach:'#78b4af', channel:'#63a4a7'};
const inks = {ripple:'#c2e1ce', glint:'#e6ebcf', shade:'#408e93'};
const fade = (near, far, opacity) => ['interpolate',['linear'],['zoom'],near,0,far,['*',opacity,['get','alpha']]];

// A repeating transparent block of short reflected wave crests. The broad
// currents below it follow the surveyed river axis. This tile stays in map space.
function waterGrain() {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 256;
  const ctx = canvas.getContext('2d');
  ctx.lineCap = 'round';
  const shoals = [[19,18,15],[87,11,8],[148,29,21],[227,13,11],[50,65,12],
    [112,81,19],[201,57,7],[16,118,21],[78,139,9],[156,112,13],[228,133,18],
    [34,189,10],[115,175,16],[183,192,23],[234,213,9],[82,230,17],[151,245,7]];
  for (const [x,y,span] of shoals) {
    // Wrap motifs across the image edges so the texture tiles without a seam.
    for (const dx of [-256,0,256]) {
      const left = x + dx;
      for (const [offset,rise,length,color,width] of [
        [0,0,1,'rgba(40,111,117,.42)',2.3],
        [-2,-1.8,.74,'rgba(226,241,210,.68)',1.45],
        [span*.55,3,.46,'rgba(206,231,213,.6)',1.15],
      ]) {
        ctx.beginPath();
        ctx.moveTo(left+offset,y+rise);
        ctx.bezierCurveTo(left+offset+span*.25,y+rise-2.1,
          left+offset+span*length*.72,y+rise+1.2,left+offset+span*length,y+rise-1);
        ctx.strokeStyle=color;
        ctx.lineWidth=width;
        ctx.stroke();
      }
    }
  }
  return ctx.getImageData(0, 0, 256, 256);
}

export function addTaipeiRiverArt(map, firstLabel) {
  let pending = false, removed = false;
  async function load() {
    if (pending || removed || map.getSource(source) || map.getZoom() < 12) return;
    const view = map.getBounds();
    if (view.getEast()<121.44 || view.getWest()>121.69 || view.getNorth()<24.95 || view.getSouth()>25.23) return;
    pending = true;
    try {
      const response = await fetch(new URL('./assets/taipei-river-art.json.gz?v=river-detail-3', import.meta.url));
      if (!response.ok) throw Error(String(response.status));
      const data = await decodeMapJSON(response);
      if (removed) return;
      map.addSource(source,{type:'geojson',data,maxzoom:17,tolerance:.35,attribution:'<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a>'});
      const anchor = map.getLayer('landcover_sand') ? 'landcover_sand' : firstLabel;
      for (const [kind,color] of Object.entries(washes)) {
        map.addLayer({id:source+'-'+kind,type:'fill',source,minzoom:12,
          filter:['==',['get','k'],kind],paint:{'fill-color':color,'fill-opacity':fade(12,14,.94)}},anchor);
      }
      map.addLayer({id:source+'-currents',type:'fill',source,minzoom:14,
        filter:['==',['get','k'],'current'],
        paint:{'fill-color':'#438e92','fill-opacity':fade(14,16.5,.37)}},anchor);
      const grain = source+'-wavelets';
      map.addImage(grain,waterGrain(),{pixelRatio:1});
      map.addLayer({id:grain,type:'fill',source,minzoom:16.3,
        filter:['==',['get','k'],'shore'],
        paint:{'fill-pattern':grain,'fill-opacity':fade(16.3,18.1,.83)}},anchor);
      for (const [kind,color] of Object.entries(inks)) {
        map.addLayer({id:source+'-'+kind,type:'line',source,minzoom:14.25,
          filter:['==',['get','k'],kind],layout:{'line-cap':'round','line-join':'round'},
          paint:{'line-color':color,'line-opacity':fade(14.25,16,kind === 'shade' ? .42 : .65),
            'line-width':['interpolate',['linear'],['zoom'],14,.5,16,1.25,18,2.1,21,3.4]}},anchor);
      }
      map.addLayer({id:source+'-deck', type:'fill', source, minzoom:15.5,
        filter:['==',['get','k'],'pier-deck'],
        paint:{'fill-color':'#ceb68d','fill-outline-color':'#87775f','fill-opacity':fade(15.5,17,1)}},anchor);
      map.addLayer({id:source+'-joints',type:'line',source,minzoom:17.7,
        filter:['==',['get','k'],'deck-joint'],
        paint:{'line-color':'#99794f','line-opacity':fade(17.7,19,.66),
          'line-width':['interpolate',['linear'],['zoom'],18,.65,21,1.4]}},anchor);
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
