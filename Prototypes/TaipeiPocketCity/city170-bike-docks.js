// One illustrative 2.0 post at a mapped station node. Individual bay positions and availability are unknown.
// The light body, amber foot and solar cap follow https://www.youbike.com.tw/region/taipei/equipment/
export function bikeDockParts({id, properties:p, geometry:g}) {
  if (p.category !== 'bicycle_rental' || p.brand !== 'YouBike 2.0' || g.type !== 'Point' ||
      !id.startsWith('poi/node/') || p.offGround || p.building || Number(p.layer ?? 0) !== 0 ||
      Number(p.level ?? 0) !== 0 || ['indoor','bridge','tunnel'].some(k=>p[k] && p[k] !== 'no') ||
      (p.access && !['yes','public','permissive'].includes(p.access))) return [];
  const [lon,lat] = g.coordinates;
  const east = 111320 * Math.cos(lat * Math.PI / 180);
  const parts = [];
  function slab(name,x,y,width,depth,base,top,color) {
    const w = width / 2, d = depth / 2, bevel = Math.min(.045, d / 3);
    const loop = [[-w+bevel,-d],[w-bevel,-d],[w,-d+bevel],[w,d-bevel],
      [w-bevel,d],[-w+bevel,d],[-w,d-bevel],[-w,-d+bevel],[-w+bevel,-d]];
    parts.push({type:'Feature',id:id+'/'+name,properties:{kind:'bike-dock',base,top,color},
      geometry:{type:'Polygon',coordinates:[loop.map(([u,v])=>[lon+(x+u)/east,lat+(y+v)/110574])]}});
  }
  slab('foot',0,0,.52,.40,0,.07,'#a9a798');
  slab('stripe',0,0,.40,.26,.07,.24,'#e2a352');
  slab('body',0,0,.40,.26,.24,.94,'#eee8d7');
  slab('socket',0,-.137,.21,.035,.57,.67,'#656962');
  slab('cap',0,0,.44,.30,.94,.99,'#b7b8ae');
  slab('solar',-.046,0,.20,.19,.99,1.008,'#454d5a');
  slab('plate',.129,0,.065,.13,.99,1.008,'#f4eddc');
  return parts;
}

export function bikeStationPlace(p) {
  if (p.category !== 'bicycle_rental') return p;
  const label = p.brand === 'YouBike 2.0' ? 'YouBike 2.0 租借站' : '自行車租借站';
  return {...p,categoryLabel:p.categoryLabel && p.categoryLabel !== p.category ? p.categoryLabel : label,
    detail:p.detail === p.category ? label : p.detail};
}
