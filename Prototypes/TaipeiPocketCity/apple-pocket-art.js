import {surfaceFeature} from './city170-ground.js';
import {buildFuxingFront} from './fuxing-fronts.js?v=dihua-shops-1';
import {completeFrontagePack} from './taipei-frontage-pack.js?v=survey-store-1';
import {decodeMapJSON} from './pocket-city-atlas.js?v=taipei-fronts-2';

const tileSize = 256;
const minimumZ = 16;
const maximumZ = 22;
const city = [121.445, 24.948, 121.683, 25.223];
const earth = 40075016.686;
const indexGrid = 2 ** 14;
const liftEast = .85;
const liftNorth = .32;
const paintKinds = new Set(['park', 'water', 'pitch', 'building', 'tree']);
const tones = [
  ['#dbb994', '#b89679'], ['#d4af9c', '#a58075'], ['#b4bec3', '#8ea5ae'],
  ['#dfc4a0', '#af9679'], ['#c7b58e', '#a49a7a'], ['#bfd0be', '#91a79b'],
];
const shopColors = {
  cafe: '#4f7f72', restaurant: '#a65e46', fast_food: '#a65e46', books: '#737e9b',
  clothes: '#a06d7c', pharmacy: '#618683', bakery: '#b38953', convenience: '#83794f',
};

function mercator([lon, lat]) {
  return [(lon + 180) / 360, (1 - Math.asinh(Math.tan(lat * Math.PI / 180)) / Math.PI) / 2];
}
function boundsOf([west, south, east, north]) {
  const [left, top] = mercator([west, north]);
  const [right, bottom] = mercator([east, south]);
  return [left, top, right, bottom];
}
function overlaps(a, b) {
  return a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];
}
function expand([l, t, r, b], n) {
  return [l - n, t - n, r + n, b + n];
}
function metresPerUnit(lat) {
  return earth * Math.cos(lat * Math.PI / 180);
}
const metres = metresPerUnit(25.08);
const cityBounds = boundsOf(city);

function gridCells(bounds) {
  const [left, top, right, bottom] = bounds.map(v => Math.floor(v * indexGrid));
  const keys = [];
  for (let y = top; y <= bottom; y++) {
    for (let x = left; x <= right; x++) keys.push(x + '/' + y);
  }
  return keys;
}

function artworkIndex(source) {
  if (!Array.isArray(source?.packs)) throw Error('Invalid Pocket City index');
  const packs = new Map();
  const cells = new Map();
  for (const record of source.packs) {
    if (!/^p\d+_\d+$/.test(record?.id) || !Array.isArray(record.bounds) ||
        record.bounds.length !== 4 || !record.bounds.every(Number.isFinite)) {
      throw Error('Invalid Pocket City index entry');
    }
    const bounds = boundsOf(record.bounds);
    const file = record.url === record.id + '.json' ? record.url : record.id + '.json.gz';
    packs.set(record.id, {id: record.id, file, bounds, deps: record.deps || []});
    for (const key of gridCells(bounds)) {
      if (!cells.has(key)) cells.set(key, []);
      cells.get(key).push(record.id);
    }
  }
  return {packs, cells};
}

function packsNear(index, bounds) {
  const matched = new Set();
  for (const cell of gridCells(bounds)) {
    for (const id of index.cells.get(cell) || []) {
      const pack = index.packs.get(id);
      if (!overlaps(bounds, pack.bounds)) continue;
      matched.add(id);
      for (const dependency of pack.deps) matched.add(dependency);
    }
  }
  return [...matched].sort().map(id => index.packs.get(id)).filter(Boolean);
}

function polygonRings(geometry) {
  if (geometry.type === 'Polygon') return [geometry.coordinates];
  if (geometry.type === 'MultiPolygon') return geometry.coordinates;
  return [];
}

function prepareFeatures({features}) {
  if (!Array.isArray(features?.features)) throw Error('Invalid Pocket City feature pack');
  const art = [];
  for (const row of features.features) {
    const {kind} = row.properties;
    if (!paintKinds.has(kind) || (kind==='pitch' && surfaceFeature(row).properties.offGround)) continue;
    if (kind === 'tree' && row.geometry.type === 'Point') {
      const point = mercator(row.geometry.coordinates);
      art.push({id: row.id, kind, point, bounds: [...point, ...point]});
      continue;
    }
    const shapes = polygonRings(row.geometry).map(rings => rings.map(ring => ring.map(mercator)));
    if (!shapes.length) continue;
    const bounds = [Infinity, Infinity, -Infinity, -Infinity];
    for (const rings of shapes) {
      for (const [x, y] of rings[0]) {
        bounds[0] = Math.min(bounds[0], x);
        bounds[1] = Math.min(bounds[1], y);
        bounds[2] = Math.max(bounds[2], x);
        bounds[3] = Math.max(bounds[3], y);
      }
    }
    const height = Number.parseFloat(row.properties.height) ||
      (Number.parseFloat(row.properties['building:levels']) || 2) * 2.8;
    art.push({id: row.id, kind, shapes, bounds, height: Math.max(2.8, Math.min(23, height))});
  }
  return art;
}

function polygon(ctx, rings, fill, stroke) {
  ctx.beginPath();
  for (const ring of rings) {
    if (ring.length < 3) continue;
    ctx.moveTo(...ring[0]);
    for (const point of ring.slice(1)) ctx.lineTo(...point);
    ctx.closePath();
  }
  ctx.fillStyle = fill;
  ctx.fill('evenodd');
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = .52;
    ctx.stroke();
  }
}

function buildingTone(id) {
  let hash = 0;
  for (const c of String(id)) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  return tones[hash % tones.length];
}

function paintBuilding(ctx, feature, project, zoom) {
  const [roof, wall] = buildingTone(feature.id);
  const height = zoom >= 18 ? feature.height : 0;
  for (const rings of feature.shapes) {
    if (height) {
      const outer = rings[0];
      const remains = [];
      for (let i = 1; i < outer.length; i++) {
        const a = outer[i - 1], b = outer[i];
        remains.push({a, b, depth: (a[1] + b[1]) * liftNorth - (a[0] + b[0]) * liftEast});
      }
      remains.sort((a, b) => a.depth - b.depth);
      ctx.globalAlpha = .62;
      for (const {a, b} of remains) {
        polygon(ctx, [[project(a), project(b), project(b, height), project(a, height)]], wall);
      }
    }
    ctx.globalAlpha = zoom >= 18 ? .69 : .47;
    polygon(ctx, rings.map(ring => ring.map(p => project(p, height))), roof, '#9c9386');
  }
}

function paintTree(ctx, point, project) {
  const [x, y] = project(point, 3.5);
  const [baseX, baseY] = project(point);
  const r = Math.max(1, Math.hypot(x - baseX, y - baseY) * .65);
  ctx.globalAlpha = .74;
  polygon(ctx, [[[baseX - r * .18, baseY], [baseX + r * .18, baseY], [x, y]]], '#9a7e60');
  for (const [dx, dy, radius, color] of [
    [-.32, .12, .8, '#749c6f'], [.39, -.10, .75, '#8aab75'], [.04, -.4, .7, '#a6bd81'],
  ]) {
    ctx.beginPath();
    ctx.arc(x + dx * r, y + dy * r, radius * r, 0, 2 * Math.PI);
    ctx.fillStyle = color;
    ctx.fill();
  }
}

function drawName(ctx, [topLeft, topRight, bottomLeft], name, fill) {
  const length = Math.hypot(topRight[0] - topLeft[0], topRight[1] - topLeft[1]);
  const height = Math.hypot(bottomLeft[0] - topLeft[0], bottomLeft[1] - topLeft[1]);
  if (height < 1.2 || length < 4) return;
  ctx.save();
  ctx.transform((topRight[0] - topLeft[0]) / length, (topRight[1] - topLeft[1]) / length,
    (bottomLeft[0] - topLeft[0]) / height, (bottomLeft[1] - topLeft[1]) / height, ...topLeft);
  ctx.fillStyle = fill;
  ctx.font = 'bold ' + Math.max(1, height * .72) + 'px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(name, length / 2, height / 2, length);
  ctx.restore();
}

function paintShop(ctx, row, project, zoom) {
  const origin = mercator(row.center);
  const localMetres = metresPerUnit(row.center[1]);
  const angle = row.angle * Math.PI / 180;
  const [nx, ny] = [Math.cos(angle), Math.sin(angle)];
  // The tile view is drawn looking toward the northeast, exposing western and southern façades.
  if (nx * -liftEast + ny * -liftNorth <= .02) return;
  const half = Math.min(4.5, row.width / 2);
  const storey = (row.surveyTop ?? Infinity) - Math.max(row.groundZ ?? 0, row.surveyBase ?? 0);
  if (storey < 1.9) return;
  const heightScale = Math.min(1, (storey - .15) / 3.2);
  const top = 3.2;
  const faces = [];
  const point = (s, z, d) => [(-ny * s + nx * (.11 + d)), (nx * s + ny * (.11 + d)), z * heightScale];
  const xy = ([e, n, z]) => project([origin[0] + e / localMetres, origin[1] - n / localMetres], z);
  // Opposite-direction wall and display faces share the same screen pixels.
  // Sort by their distance out from the wall, so a tall back panel cannot hide its own display.
  const depth = ([e, n]) => nx * e + ny * n;
  function quad(points, fill) {
    faces.push({points, fill, depth: points.reduce((sum, p) => sum + depth(p), 0) / points.length});
  }
  function panel(a, b, low, high, d, fill) {
    if (b > a && high > low) {
      quad([point(a, low, d), point(b, low, d), point(b, high, d), point(a, high, d)], fill);
    }
  }
  function sign(a, b, low, high, d, fill) {
    if (zoom < 20 || b <= a || high <= low) return;
    const points = [point(a, high, d), point(b, high, d), point(a, low, d)];
    faces.push({points, fill, name: row.name, depth: points.reduce((sum, p) => sum + depth(p), 0) / 3});
  }
  if (!buildFuxingFront(row, {half, top, point, quad, panel, rgb: color => color, sign})) {
    const name = shopColors[row.category] || '#85775c';
    panel(-half, half, .08, top, .02, '#b8a389');
    panel(-half + .08, half - .08, .19, 2.57, .05, '#566963');
    for (const [a, b] of [[-half + .16, -.56], [.56, half - .16]]) {
      panel(a, b, .32, 2.41, .078, '#93a6a0');
      panel(a, b, .68, .74, .084, '#dfcba3');
    }
    panel(-.49, .49, .21, 2.12, .091, '#788e87');
    panel(-half + .06, half - .06, 2.63, 3.11, .090, name);
    sign(-half + .14, half - .14, 2.71, 3.04, .096, '#fff0cb');
  }
  ctx.globalAlpha = .94;
  for (const face of faces.sort((a, b) => a.depth - b.depth)) {
    const points = face.points.map(xy);
    if (face.name) drawName(ctx, points, face.name, face.fill);
    else polygon(ctx, [points], face.fill);
  }
}

function makeCanvas(scale) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = tileSize * scale;
  return canvas;
}

function drawTile(tile, features, fronts, canvas) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return canvas;
  ctx.scale(tile.scale, tile.scale);
  const world = tileSize * 2 ** tile.z;
  const project = ([x, y], height = 0) => [
    x * world - tile.x * tileSize + height / metres * world * liftEast,
    y * world - tile.y * tileSize - height / metres * world * liftNorth,
  ];
  const parkFill = {park: '#99b879', pitch: '#b7b582', water: '#76a9ab'};
  for (const feature of features) {
    const fill = parkFill[feature.kind];
    if (!fill) continue;
    ctx.globalAlpha = .47;
    for (const rings of feature.shapes) polygon(ctx, rings.map(ring => ring.map(p => project(p))), fill);
  }
  const buildings = features.filter(f => f.kind === 'building').sort((a, b) =>
    (a.bounds[3] - b.bounds[3]) * liftNorth - (a.bounds[0] - b.bounds[0]) * liftEast);
  for (const feature of buildings) paintBuilding(ctx, feature, project, tile.z);
  if (tile.z >= 18) for (const feature of features) {
    if (feature.kind === 'tree') paintTree(ctx, feature.point, project);
  }
  fronts.sort((a, b) => (b.center[1] - a.center[1]) * liftNorth + (b.center[0] - a.center[0]) * liftEast);
  for (const row of fronts) paintShop(ctx, row, project, tile.z);
  return canvas;
}

function memo(cache, key, max, load) {
  if (cache.has(key)) {
    const entry = cache.get(key);
    cache.delete(key);
    cache.set(key, entry);
    return entry.promise;
  }
  const entry = {finished: false};
  entry.promise = load().then(value => {
    entry.finished = true;
    for (const [candidate, record] of cache) {
      if (cache.size <= max) break;
      if (record.finished) cache.delete(candidate);
    }
    return value;
  }, error => {
    if (cache.get(key) === entry) cache.delete(key);
    throw error;
  });
  cache.set(key, entry);
  return entry.promise;
}

export function addPocketArt(map, mapkit, onState = () => {}) {
  const tiles = new Map(), packs = new Map(), frontages = new Map(), blank = new Map();
  const lifetime = new AbortController();
  let degraded = false;
  let index;
  function reportDegraded() {
    if (degraded || lifetime.signal.aborted) return;
    degraded = true;
    onState('degraded');
  }
  async function json(path) {
    const url = new URL('./data/' + path, import.meta.url);
    const response = await fetch(url, {signal: lifetime.signal});
    if (!response.ok) throw Error('Pocket City asset ' + response.status + ' ' + path);
    if (!path.endsWith('.gz')) return response.json();
    return decodeMapJSON(response);
  }
  function empty(scale) {
    if (!blank.has(scale)) blank.set(scale, makeCanvas(scale));
    return blank.get(scale);
  }
  async function artwork(tile, bounds) {
    if (!index) index = json('city170/index.json').then(artworkIndex).catch(error => {
      index = undefined;
      throw error;
    });
    const candidates = packsNear(await index, bounds);
    if (!candidates.length || lifetime.signal.aborted) return empty(tile.scale);
    const data = await Promise.all(candidates.map(async pack => {
      const rows = memo(packs, pack.id, 42, () => json('city170/' + pack.file).then(prepareFeatures));
      const shops = tile.z < 19 ? [] : memo(frontages, pack.id, 46, async () => {
        const items = await json('city170-frontages/' + pack.file);
        return completeFrontagePack(pack.id,items);
      });
      return Promise.allSettled([rows, shops]);
    }));
    if (data.some(parts => parts.some(part => part.status === 'rejected'))) {
      tiles.delete(tile.key);
      reportDegraded();
    }
    const features = new Map(), fronts = new Map();
    // Data completion order must not change which features are painted on top at a tile boundary.
    for (const [rows, shops] of data) {
      if (rows.status === 'fulfilled') {
        for (const row of rows.value) if (overlaps(bounds, row.bounds)) features.set(row.id, row);
      }
      if (shops.status !== 'fulfilled') continue;
      for (const row of shops.value) {
        const xy = mercator(row.center);
        if (overlaps(bounds, [...xy, ...xy])) fronts.set(row.id, row);
      }
    }
    if (lifetime.signal.aborted || (!features.size && !fronts.size)) return empty(tile.scale);
    return drawTile(tile, [...features.values()], [...fronts.values()], makeCanvas(tile.scale));
  }
  const overlay = new mapkit.TileOverlay((x, y, z, scale) => {
    if (lifetime.signal.aborted || ![x, y, z].every(Number.isInteger) || z < minimumZ || z > maximumZ) return null;
    const side = 2 ** z;
    if (x < 0 || y < 0 || x >= side || y >= side) return null;
    const bounds = [x / side, y / side, (x + 1) / side, (y + 1) / side];
    if (!overlaps(bounds, cityBounds)) return null;
    const size = Number.isFinite(scale) ? Math.max(1, Math.min(3, scale)) : 1;
    const key = [z, x, y, size].join('/');
    // Nearby roof relief and canopies must be considered identically on both sides of tile joins.
    return memo(tiles, key, Math.ceil(64 / size ** 2),
      () => artwork({x, y, z, scale: size, key}, expand(bounds, 28 / metres)))
      .catch(() => {
        reportDegraded();
        return empty(size);
      });
  }, {minimumZ, maximumZ, opacity: .88});
  map.addTileOverlay(overlay);
  return {dispose() {
    if (lifetime.signal.aborted) return;
    lifetime.abort();
    map.removeTileOverlay(overlay);
    tiles.clear();
    packs.clear();
    frontages.clear();
    blank.clear();
  }};
}
