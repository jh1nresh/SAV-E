// Join by feature identity: similarly named campuses can be kilometres apart.
export function campusBounds(features) {
  const byId = new Map();
  for (const {id, properties, geometry} of features) {
    if (properties.kind !== 'school') continue;
    const polygons = geometry.type === 'Polygon' ? [geometry.coordinates] :
      geometry.type === 'MultiPolygon' ? geometry.coordinates : [];
    let west=Infinity, east=-Infinity, south=Infinity, north=-Infinity;
    for (const [shell] of polygons) for (const [x,y] of shell) {
      west=Math.min(west,x); east=Math.max(east,x);
      south=Math.min(south,y); north=Math.max(north,y);
    }
    if (east>west && north>south) byId.set('label/'+id, [[west,south],[east,north]]);
  }
  return byId;
}

export function showSchool(map, {center, bounds}) {
  const bearing = map.getBearing();
  if (bounds) {
    const canvas = map.getCanvas();
    const padding = {left:canvas.clientWidth*.12, right:canvas.clientWidth*.12,
      top:canvas.clientHeight*.18, bottom:canvas.clientHeight*.18};
    const camera = map.cameraForBounds(bounds, {bearing, padding, maxZoom:18.6});
    if (camera) {
      map.jumpTo({center:camera.center,zoom:camera.zoom,bearing,pitch:38});
      return;
    }
  }
  map.jumpTo({center,zoom:17.35,pitch:38});
}
