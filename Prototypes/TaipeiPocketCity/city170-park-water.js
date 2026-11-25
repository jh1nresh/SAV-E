import {addStreetFurniture} from './city170-street-furniture.js';

const layerId = 'city170-park-water';
const zoom = 19;
const loadPoints = async () => (await import(new URL('./city170-park-water-points.js', import.meta.url).href)).default;

export function parkWaterParts([id, lonE7, latE7]) {
  const lon = lonE7 / 1e7, lat = latE7 / 1e7;
  const east = 111320 * Math.cos(lat * Math.PI / 180);
  const ring = (x, y, w, d, bevel) => {
    const l = x - w/2, r = x + w/2, b = y - d/2, t = y + d/2;
    return [[l+bevel,b],[r-bevel,b],[r,b+bevel],[r,t-bevel],[r-bevel,t],[l+bevel,t],
      [l,t-bevel],[l,b+bevel],[l+bevel,b]].map(([u,v])=>[lon+u/east, lat+v/110574]);
  };
  const solid = (part, outer, base, height, color, inner) => ({
    type:'Feature', id:id+'/'+part, properties:{base,height,color},
    geometry:{type:'Polygon',coordinates:inner?[outer,inner.toReversed()]:[outer]},
  });
  // Illustrative parks equipment. Take the small basin scale from the 0.67 × 1.1 m
  // Polyfork park-drinking-fountain-b1c25b. The inventory fixes the position only.
  return [
    solid('foot',ring(0,0,.52,.48,.06),0,.07,'#978977'),
    solid('pedestal',ring(0,0,.38,.34,.045),.07,.84,'#5d928a'),
    solid('basin',ring(0,0,.64,.57,.078),.81,.88,'#cdd3c7'),
    solid('rim',ring(0,0,.64,.57,.078),.88,.94,'#e6e2cb',ring(0,0,.51,.44,.063)),
    solid('bowl',ring(0,-.05,.30,.24,.045),.88,.894,'#a0b4ad'),
    solid('drain',ring(0,-.05,.071,.071,.026),.894,.908,'#677d75'),
    solid('tap',ring(0,.15,.14,.15,.039),.88,1.09,'#679994'),
    solid('outlet',ring(0,.097,.091,.153,.022),1.038,1.09,'#d9dfd3'),
  ];
}

export function addParkWater(map, beforeId, load = loadPoints) {
  addStreetFurniture(map, beforeId, layerId, zoom, load, parkWaterParts, .00001);
}
