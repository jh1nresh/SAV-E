const city = [121.45,24.95,121.68,25.22];
const features = rows => ({type:'FeatureCollection',features:rows});
const touches = (a,b) => a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];

function indexed(groups) {
  return Object.entries(groups).map(([key,rows]) => {
    const x = rows.map(r=>r[1]/1e7), y = rows.map(r=>r[2]/1e7);
    return {key, rows, extent:[Math.min(...x), Math.min(...y), Math.max(...x), Math.max(...y)]};
  });
}

export function addStreetFurniture(map, beforeId, layerId, threshold, load, parts, padding) {
  map.addSource(layerId,{type:'geojson',data:features([]),maxzoom:21,tolerance:0});
  map.addLayer({id:layerId,type:'fill-extrusion',source:layerId,minzoom:threshold,
    paint:{'fill-extrusion-base':['get','base'],'fill-extrusion-height':['get','height'],
      'fill-extrusion-color':['get','color'],'fill-extrusion-vertical-gradient':false}},beforeId);
  let cells, loading=false, removed=false, last='';
  async function update() {
    if (removed) return;
    const b = map.getBounds();
    const view = [b.getWest()-padding,b.getSouth()-padding,b.getEast()+padding,b.getNorth()+padding];
    if (map.getZoom() < threshold || !touches(view,city)) {
      if (last) map.getSource(layerId).setData(features([]));
      last='';
      return;
    }
    if (!cells) {
      if (loading) return;
      loading=true;
      try {
        cells=indexed(await load());
        if (!removed) await update();
      } catch(error) {
        if (!removed) console.warn(layerId,error.message);
      } finally {loading=false;}
      return;
    }
    const visible = cells.filter(c=>touches(view,c.extent));
    const key = visible.map(c=>c.key).join(',');
    if (last === key) return;
    map.getSource(layerId).setData(features(visible.flatMap(c=>c.rows.flatMap(parts))));
    last=key;
  }
  map.on('moveend',update);
  map.on('resize',update);
  map.on('remove',()=>{
    removed=true;
    map.off('moveend',update);
    map.off('resize',update);
  });
  void update();
}
