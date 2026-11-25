// The two mapped rings define the surface. Lane counts, when present, come from
// OSM. The thin painted dividers are an illustration, not surveyed lane lines.
export function runningTrack(feature) {
  const {properties: p, geometry} = feature;
  if (p.kind !== 'pitch' || p.category !== 'track' || geometry.type !== 'Polygon' ||
      geometry.coordinates.length !== 2 || p.offGround || Number(p.layer ?? 0) !== 0 ||
      Number(p.level ?? 0) !== 0 || ['indoor','covered','tunnel','bridge'].some(k => p[k] && p[k] !== 'no')) return;
  const sports = (p.sport ?? '').split(';');
  if (!sports.some(s => ['running','athletics','runing'].includes(s))) return;

  const surface = {...feature, properties: {...p, kind: 'running-track'}};
  const lanes = Number(p.lanes);
  if (!Number.isInteger(lanes) || lanes < 2 || lanes > 10) return [surface];
  const [outside, inside] = geometry.coordinates;
  const [lng, lat] = inside[0];
  const east = 111320 * Math.cos(lat * Math.PI / 180);
  const north = 110775;
  const local = ring => ring.slice(0, -1).map(([x,y]) => [(x-lng)*east, (y-lat)*north]);
  const outer = local(outside), inner = local(inside);
  if (outer.length < 3 || inner.length < 3) return [surface];
  const signedArea = inner.reduce((sum, [x,y], i) => {
    const [u,v] = inner[(i+1) % inner.length];
    return sum + x*v - y*u;
  }, 0);
  // Start from the inner edge so that start/finish aprons on the outer edge
  // don't bend the laps. Cap the spacing at the narrowest mapped clearance.
  const sign = Math.sign(signedArea);
  if (!sign) return [surface];
  const normals = inner.map(([x,y], i) => {
    const next = inner[(i+1) % inner.length], dx = next[0]-x, dy = next[1]-y;
    const len = Math.hypot(dx,dy);
    return [sign*dy/len, -sign*dx/len];
  });
  const miters = normals.map(([x,y], i) => {
    const [u,v] = normals[(i+normals.length-1) % normals.length];
    const divisor = 1+x*u+y*v;
    return [(x+u)/divisor, (y+v)/divisor];
  });
  const maximumMiter = Math.max(...miters.map(([x,y]) => Math.hypot(x,y)));
  if (!Number.isFinite(maximumMiter) || maximumMiter > 2) return [surface];
  function clearance(vertices, boundary) {
    let distance = Infinity;
    for (const [x,y] of vertices) for (let j=0; j<boundary.length; j++) {
      const [a,b] = boundary[j], [c,d] = boundary[(j+1) % boundary.length];
      const dx = c-a, dy = d-b, dot = (x-a)*dx + (y-b)*dy;
      const t = Math.min(1, Math.max(0, dot/(dx*dx+dy*dy || 1)));
      distance = Math.min(distance, Math.hypot(x-a-t*dx, y-b-t*dy));
    }
    return distance;
  }
  const width = Math.min(clearance(inner,outer),clearance(outer,inner));
  const spacing = Math.min(1.22, width / (maximumMiter*lanes));
  if (spacing < .5) return [surface];
  const lines = [];
  for (let lane=1; lane<lanes; lane++) {
    const ring = inner.map(([x,y], i) => {
      const [dx,dy] = miters[i], offset = spacing*lane;
      return [lng+(x+offset*dx)/east, lat+(y+offset*dy)/north];
    });
    lines.push([...ring,ring[0]]);
  }
  return [surface, {type:'Feature', id:'lanes/'+feature.id, properties:{kind:'track-lanes'},
    geometry:{type:'MultiLineString',coordinates:lines}}];
}
