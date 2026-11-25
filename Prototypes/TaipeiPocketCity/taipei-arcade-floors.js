import {decodeMapJSON} from './pocket-city-atlas.js?v=taipei-fronts-2';

// Flat map layers keep the paving on the same ground as the surrounding sidewalk.
export function addArcadeFloors(map, before) {
  const id = 'taipei-arcade-floors';
  let pending = false, removed = false;
  async function load() {
    if (pending || removed || map.getSource(id) || map.getZoom() < 18) return;
    const bounds = map.getBounds();
    if (bounds.getEast()<121.44 || bounds.getWest()>121.67 || bounds.getNorth()<24.95 || bounds.getSouth()>25.22) return;
    pending = true;
    try {
      const response = await fetch(new URL('./assets/taipei-arcade-floors.json.gz?v=sections-2', import.meta.url));
      if (!response.ok) throw Error(String(response.status));
      const data = await decodeMapJSON(response);
      if (removed) return;
      map.addSource(id,{type:'geojson',data,maxzoom:21,tolerance:0,
        attribution:'<a href="https://data.gov.tw/dataset/128426">臺北市建管處騎樓整平工程</a>'});
      map.addLayer({id,type:'fill',source:id,minzoom:18,
        filter:['==',['get','kind'],'floor'],
        paint:{'fill-color':'#d4c4aa','fill-opacity':['interpolate',['linear'],['zoom'],18,0,19.4,.98]}},before);
      map.addLayer({id:id+'-joints',type:'line',source:id,minzoom:19,
        filter:['==',['get','kind'],'joints'],
        paint:{'line-color':'#9e8e78','line-opacity':['interpolate',['linear'],['zoom'],19,0,20.3,.62],
          'line-width':['interpolate',['linear'],['zoom'],19,.45,21.6,1.05]}},before);
      map.off('moveend',load);
    } catch(error) {
      if (!removed) console.warn('Taipei arcade paving',error);
    } finally {
      pending = false;
    }
  }
  map.on('moveend',load);
  map.on('remove',()=>{removed=true;});
  load();
}
