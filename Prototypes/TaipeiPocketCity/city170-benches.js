// The source fixes each seat's position. Its small Pocket City silhouette is illustrative.
const source = 'city170-benches';
const minZoom = 18.8;
const city = [121.45, 24.95, 121.68, 25.22];
const frame = '#73665b';
const seatColors = {wood:'#bd8059', stone:'#b8ad98', metal:'#6a8c83', other:'#ae9279'};
const collection = features => ({type:'FeatureCollection', features});

function overlaps(a, b) {
  return a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];
}

export function benchParts([id, x, y, direction, material, backrest]) {
  // An untagged direction uses a neutral schematic axis. Only a mapped backrest is drawn.
  const angle = (direction ?? 0) * Math.PI / 180;
  const cos = Math.cos(angle), sin = Math.sin(angle);
  const east = 111320 * Math.cos(y * Math.PI / 180);
  const projected = (across, forward) => [
    x + (across * cos + forward * sin) / east,
    y + (forward * cos - across * sin) / 110574,
  ];
  const parts = [];
  function box(u, v, width, depth, base, height, color) {
    const l = u - width / 2, r = u + width / 2, b = v - depth / 2, t = v + depth / 2;
    parts.push({type:'Feature', id:id * 10 + parts.length, properties:{base, height, color},
      geometry:{type:'Polygon', coordinates:[[projected(l,b), projected(r,b), projected(r,t),
        projected(l,t), projected(l,b)]]}});
  }
  const seat = seatColors[material] ?? seatColors.other;
  for (const side of [-0.56, 0.56]) box(side, 0, 0.18, 0.44, 0, 0.43, frame);
  box(0, 0, 1.72, 0.52, 0.43, 0.55, seat);
  if (backrest) box(0, -0.21, 1.72, 0.10, 0.55, 0.93, seat);
  return parts;
}

function indexCells(groups) {
  return Object.entries(groups).map(([id, rows]) => {
    const bounds = [Infinity, Infinity, -Infinity, -Infinity];
    for (const [, x, y] of rows) {
      bounds[0] = Math.min(bounds[0], x); bounds[2] = Math.max(bounds[2], x);
      bounds[1] = Math.min(bounds[1], y); bounds[3] = Math.max(bounds[3], y);
    }
    return {id, bounds, rows};
  });
}

const loadPoints = async () => (await import(new URL('./city170-bench-points.js', import.meta.url).href)).default;

export function addCityBenches(map, beforeId, load = loadPoints) {
  map.addSource(source, {type:'geojson', data:collection([]), maxzoom:21, tolerance:0});
  map.addLayer({id:source, type:'fill-extrusion', source, minzoom:minZoom,
    paint:{'fill-extrusion-color':['get','color'], 'fill-extrusion-base':['get','base'],
      'fill-extrusion-height':['get','height'], 'fill-extrusion-vertical-gradient':false}}, beforeId);
  let cells, loading = false, removed = false, last = '';
  async function update() {
    if (removed) return;
    const b = map.getBounds();
    // Pad the viewport by a few metres for benches just across a cell or screen edge.
    const view = [b.getWest() - .00003, b.getSouth() - .00003, b.getEast() + .00003, b.getNorth() + .00003];
    if (map.getZoom() < minZoom || !overlaps(view, city)) {
      if (last) { map.getSource(source).setData(collection([])); last = ''; }
      return;
    }
    if (!cells) {
      if (loading) return;
      loading = true;
      try {
        cells = indexCells(await load());
        if (!removed) await update(); // Re-read the camera after the request.
      } catch (error) { if (!removed) console.warn('Taipei benches', error.message); }
      finally { loading = false; }
      return;
    }
    const visible = cells.filter(cell => overlaps(view, cell.bounds));
    const key = visible.map(cell => cell.id).join(',');
    if (key === last) return;
    map.getSource(source).setData(collection(visible.flatMap(cell => cell.rows.flatMap(benchParts))));
    last = key;
  }
  map.on('moveend', update);
  map.on('resize', update);
  map.on('remove', () => {
    removed = true;
    map.off('moveend', update);
    map.off('resize', update);
  });
  void update();
}
