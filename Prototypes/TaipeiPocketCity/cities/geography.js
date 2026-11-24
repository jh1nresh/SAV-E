// Inverse of the local, rotated metre grid in Pocket City's prep.py.
export function geographicPoint(meta,[x,y]){
  const angle=meta.rotation*Math.PI/180;
  const east=x*Math.cos(angle)-y*Math.sin(angle);
  const north=x*Math.sin(angle)+y*Math.cos(angle);
  return [meta.lon+east/(111320*Math.cos(meta.lat*Math.PI/180)),meta.lat+north/110574];
}

export function geographicScene(scene,landmarkIds,sites=[],placeIds={}){
  const featured=new Set(landmarkIds),features=[];
  const project=point=>geographicPoint(scene.meta,point);
  function add(type,coordinates,properties){features.push({type:'Feature',properties,geometry:{type,coordinates}});}
  function polygon(rings,kind){
    const coordinates=rings.filter(r=>r.length>=3).map(r=>{
      const points=r.map(project);
      if(points[0][0]!==points.at(-1)[0]||points[0][1]!==points.at(-1)[1])points.push(points[0]);
      return points;
    });
    if(coordinates.length)add('Polygon',coordinates,{kind});
  }
  for(const lawn of scene.lawns)polygon(lawn.r,'lawn');
  for(const kind of ['sand','water','roads','walk','paths'])for(const rings of scene[kind])polygon(rings,kind);
  for(const way of scene.centerlines)if(way.name&&way.p.length>1)add('LineString',way.p.map(project),{kind:'street',name:way.name});
  for(const b of scene.buildings){
    if(!b.n||!featured.has(b.id))continue;
    const placeId=placeIds[b.id];
    const edge=b.ring.reduce((best,p)=>p[1]<best[1]?p:best,b.ring[0]);
    const labelAt=[(b.obb.c[0]+edge[0])*.5,edge[1]];
    add('Point',project(labelAt),{kind:'pin',name:b.n,category:'museum',categoryLabel:'地標',rank:0,...(placeId&&{placeId})});
  }
  for(const site of sites)add('Point',site.point,{kind:'pin',name:site.name,category:'museum',categoryLabel:'地標',rank:0,placeId:'poi/'+site.osmType+'/'+site.osmId});
  for(const poi of scene.pois){
    if(sites.some(site=>site.name===poi.name))continue;
    if(poi.name)add('Point',project([poi.x,poi.y]),{kind:'pin',category:poi.kind,name:poi.name,categoryLabel:'街區地點',rank:2});
  }
  return features;
}
