import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {addPocketArt} from '../apple-pocket-art.js';

function recordCanvas() {
  let points = [];
  const fills = [];
  const names = [];
  const ctx = {
    beginPath() { points = []; },
    moveTo(...point) { points.push(point); },
    lineTo(...point) { points.push(point); },
    closePath() {},
    fill() { fills.push({color: this.fillStyle, points: [...points]}); },
    fillText(name) { names.push(name); },
    arc() {}, scale() {}, transform() {}, stroke() {}, save() {}, restore() {},
  };
  return {fills, names, getContext: () => ctx};
}

test('MapKit image callback loads Fuxing in its geographic tile and reuses concurrent loads', async t => {
  const previousDocument = globalThis.document;
  globalThis.document = {createElement: recordCanvas};
  t.after(() => { globalThis.document = previousDocument; });
  const requestCounts = new Map();
  const states = [];
  let failFrontage = true;
  t.mock.method(globalThis, 'fetch', async (url, {signal}) => {
    assert.equal(url.protocol, 'file:');
    signal.throwIfAborted();
    requestCounts.set(url.pathname, (requestCounts.get(url.pathname) || 0) + 1);
    if (failFrontage && url.pathname.endsWith('/city170-frontages/p224_2035.json.gz')) {
      failFrontage = false;
      return new Response('invalid gzip');
    }
    return new Response(await readFile(url, {signal}));
  });
  let tile;
  class TileOverlay {
    constructor(callback, options) {
      tile = callback;
      assert.equal(options.minimumZ, 16);
      assert.equal(options.maximumZ, 22);
    }
  }
  const overlays = new Set();
  const art = addPocketArt({
    addTileOverlay: overlay => overlays.add(overlay),
    removeTileOverlay: overlay => overlays.delete(overlay),
  }, {TileOverlay}, state => states.push(state));
  assert.equal(overlays.size, 1);
  assert.equal(tile(0, 0, 22, 2), null);
  assert.equal(tile(0, 0, 15, 2), null);
  assert.equal(requestCounts.size, 0);

  // The survey-aligned bookstore anchor, independent of the painter's projection.
  const lon = 121.54367371, lat = 25.02748876;
  const z = 22, side = 2 ** z;
  const tx = (lon + 180) / 360 * side;
  const ty = (1 - Math.asinh(Math.tan(lat * Math.PI / 180)) / Math.PI) / 2 * side;
  const x = Math.floor(tx), y = Math.floor(ty);
  const first = tile(x, y, z, 2);
  const [incomplete, duplicate] = await Promise.all([first, tile(x, y, z, 2)]);
  assert.equal(incomplete, duplicate);
  assert.equal(incomplete.width, 512);
  assert.ok(incomplete.fills.length > 0, 'building artwork survives an unavailable frontage pack');
  assert.ok(!incomplete.names.includes('信義書局'));
  assert.deepEqual(states, ['degraded']);

  const image = await tile(x, y, z, 2);
  assert.ok(image.names.includes('信義書局'), 'the authored shop is rendered when the frontage pack recovers');
  assert.equal(image, await tile(x, y, z, 2));
  assert.deepEqual(states, ['degraded']);
  const candidate = image.fills.filter(face => face.color === '#b94131');
  const px = (tx - x) * 256, py = (ty - y) * 256;
  assert.ok(candidate.some(({points}) => {
    const xs = points.map(([xx]) => xx), ys = points.map(([, yy]) => yy);
    return Math.min(...xs) > px && Math.max(...xs) < px + 65 &&
      Math.min(...ys) < py && Math.max(...ys) > py;
  }), 'the red fascia projects eastward above the surveyed frontage while crossing its latitude');
  for (const [path, count] of requestCounts) {
    assert.equal(count, path.endsWith('/city170-frontages/p224_2035.json.gz') ? 2 : 1);
  }
  art.dispose();
  art.dispose();
  assert.equal(overlays.size, 0);
  assert.equal(tile(x, y, z, 2), null);
});

test('index fetch failures report once, while genuine empty tiles remain quiet', async t => {
  const previousDocument = globalThis.document;
  globalThis.document = {createElement: recordCanvas};
  t.after(() => { globalThis.document = previousDocument; });
  let failed = true;
  t.mock.method(globalThis, 'fetch', async () => failed
    ? new Response(null, {status: 503})
    : Response.json({packs: []}));
  let tile;
  const mapkit = {TileOverlay: class { constructor(callback) { tile = callback; } }};
  const map = {addTileOverlay() {}, removeTileOverlay() {}};
  const states = [];
  const art = addPocketArt(map, mapkit, state => states.push(state));
  const coordinates = [3513238, 1795819, 22, 2];
  assert.equal((await tile(...coordinates)).fills.length, 0);
  assert.equal((await tile(...coordinates)).fills.length, 0);
  assert.deepEqual(states, ['degraded']);
  art.dispose();

  failed = false;
  const emptyStates = [];
  const empty = addPocketArt(map, mapkit, state => emptyStates.push(state));
  assert.equal((await tile(...coordinates)).fills.length, 0);
  assert.equal((await tile(...coordinates)).fills.length, 0);
  assert.deepEqual(emptyStates, []);
  empty.dispose();
});
