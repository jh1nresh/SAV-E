// Pillar locations and type come from OSM. One schematic silhouette represents a mapped pillar.
// Taipei's source and https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=J0110038 support red paint.
// https://polyfork.dev/asset/fire-hydrant-b68b17 supplied the 0.51 × 0.81 × 0.50 m prop reference.
const layerId = 'city170-hydrants';
const threshold = 19;
const city = [121.45,24.95,121.68,25.22];
const features = rows => ({type:'FeatureCollection',features:rows});
const loadPoints = async () => (await import(new URL('./city170-hydrant-points.js', import.meta.url).href)).default;
const touches = (a,b) => a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];

export function hydrantParts([id,lonE7,latE7]) {
  const x = lonE7 / 1e7, y = latE7 / 1e7;
  const east = 111320 * Math.cos(y * Math.PI / 180);
  const polygon = (part, centerX, centerY, rx, ry, base, height, color, sides=8) => {
    const points = [];
    for (let i = 0; i < sides; i++) {
      const angle = (i + .5) * 2 * Math.PI / sides;
      points.push([x + (centerX + rx * Math.cos(angle)) / east,
                   y + (centerY + ry * Math.sin(angle)) / 110574]);
    }
    points.push(points[0]);
    return {type:'Feature',id:id * 10 + part,properties:{base,height,color},
      geometry:{type:'Polygon',coordinates:[points]}};
  };
  // A low cast foot, painted barrel, nozzle, overlapping bonnet and top nut; orientation is illustrative.
  return [
    polygon(0,0,0,.194,.194,0,.085,'#7c483e'),
    polygon(1,0,0,.151,.151,.085,.57,'#bd5145'),
    polygon(2,.136,0,.111,.080,.34,.47,'#a3453d'),
    polygon(3,.221,0,.041,.083,.335,.48,'#763e38'),
    polygon(4,0,0,.168,.168,.57,.637,'#843d34'),
    polygon(5,0,0,.147,.147,.637,.713,'#c75f4c'),
    polygon(6,0,0,.103,.103,.713,.762,'#d67b60'),
    polygon(7,0,0,.048,.048,.762,.81,'#924b3e',6),
  ];
}

function indexed(groups) {
  return Object.entries(groups).map(([key,rows]) => {
    const x = rows.map(r=>r[1]/1e7), y = rows.map(r=>r[2]/1e7);
    return {key, rows, extent:[Math.min(...x), Math.min(...y), Math.max(...x), Math.max(...y)]};
  });
}

export function addCityHydrants(map, beforeId, load=loadPoints) {
  map.addSource(layerId,{type:'geojson',data:features([]),maxzoom:21,tolerance:0});
  map.addLayer({id:layerId,type:'fill-extrusion',source:layerId,minzoom:threshold,
    paint:{'fill-extrusion-base':['get','base'],'fill-extrusion-height':['get','height'],
      'fill-extrusion-color':['get','color'],'fill-extrusion-vertical-gradient':false}},beforeId);
  let cells, loading=false, removed=false, last='';
  async function update() {
    if (removed) return;
    const b = map.getBounds();
    const view = [b.getWest()-.00001,b.getSouth()-.00001,b.getEast()+.00001,b.getNorth()+.00001];
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
        if (!removed) console.warn('Taipei hydrants',error.message);
      } finally {loading=false;}
      return;
    }
    const visible = cells.filter(c=>touches(view,c.extent));
    const key = visible.map(c=>c.key).join(',');
    if (last === key) return;
    map.getSource(layerId).setData(features(visible.flatMap(c=>c.rows.flatMap(hydrantParts))));
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
