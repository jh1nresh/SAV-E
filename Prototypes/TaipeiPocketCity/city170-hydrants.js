import {addStreetFurniture} from './city170-street-furniture.js';
// Pillar locations and type come from OSM. One schematic silhouette represents a mapped pillar.
// Taipei's source and https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=J0110038 support red paint.
// https://polyfork.dev/asset/fire-hydrant-b68b17 supplied the 0.51 × 0.81 × 0.50 m prop reference.
const layerId = 'city170-hydrants';
const threshold = 19;
const loadPoints = async () => (await import(new URL('./city170-hydrant-points.js', import.meta.url).href)).default;
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

export function addCityHydrants(map, beforeId, load=loadPoints) {
  addStreetFurniture(map,beforeId,layerId,threshold,load,hydrantParts,.00001);
}
