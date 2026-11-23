// Run from any directory with Node: node --test path/to/tools/apple-map.test.mjs
import assert from 'node:assert/strict';
import {copyFile, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';

// Maps /frame, initialization events, and library names are public SDK contracts.
// https://developer.apple.com/documentation/mapkit/unified-map-urls
// https://developer.apple.com/documentation/mapkitjs/handling-initialization-events
// https://developer.apple.com/documentation/mapkitjs/loading-the-latest-version-of-mapkit-js
const token = 'eyMock.payload.signature';
const libraries = ['full-map', 'geojson'];
const fixtureIds = ['map-status', 'map-state', 'retry-map', 'apple-map', 'map-selection',
  'art-status', 'back-to-pocket', 'open-in-apple'];
const event = (type, fields = {}) => Object.assign(new Event(type), fields);

class Element extends EventTarget {
  hidden = false;
  textContent = '';
  style = {};
  #disabled = false;
  #classes = new Set();
  attributes = new Map();
  classList = {
    contains: name => this.#classes.has(name),
    toggle: (name, force) => force ? this.#classes.add(name) : this.#classes.delete(name),
  };
  get disabled() { return this.#disabled; }
  set disabled(value) {
    this.#disabled = value;
    if (value && document.activeElement === this) document.activeElement = document.body;
  }
  after(element) { this.nextElementSibling = element; }
  focus() { document.activeElement = this; }
  setAttribute(name, value) { this.attributes.set(name, value); }
  remove() {}
}
class Coordinate {
  constructor(latitude, longitude) { Object.assign(this, {latitude, longitude}); }
}
class CoordinateSpan {
  constructor(latitudeDelta, longitudeDelta) { Object.assign(this, {latitudeDelta, longitudeDelta}); }
}
class CoordinateRegion {
  constructor(center, span) { Object.assign(this, {center, span}); }
}
class PlaceSelectionAccessory {
  static Styles = {CompactCallout: 'compactCallout'};
  constructor({style}) { this.style = style; }
}

async function loadPage(t, mode, search = '') {
  const root = await mkdtemp(join(tmpdir(), 'pocket-city-apple-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  await copyFile(new URL('../apple-map.js', import.meta.url), join(root, 'apple-map.js'));
  await writeFile(join(root, 'package.json'), '{"type":"module"}');
  if (mode !== 'missing') {
    await writeFile(join(root, 'apple-config.js'),
      'export const token = ' + JSON.stringify(mode === 'invalid' ? 'invalid' : token));
  }
  await writeFile(join(root, 'apple-pocket-art.js'),
    'export const addPocketArt = (...args) => globalThis.testAddPocketArt(...args);');

  const ui = Object.fromEntries(fixtureIds.map(id => [id, new Element()]));
  ui['apple-map'].hidden = ui['retry-map'].hidden = true;
  const calls = {sdk: 0, init: 0, reload: 0, destroyed: 0, artAttached: 0, artDisposed: 0};
  const artStates = [];
  const kit = new EventTarget();
  let map;
  let authorized = false;
  let librariesReady = false;
  Object.assign(kit, {
    Coordinate, CoordinateRegion, CoordinateSpan, PlaceSelectionAccessory,
    FeatureVisibility: {Adaptive: 'adaptive'},
    MapFeatureType: {PointOfInterest: 'PointOfInterest'},
    Map: class extends EventTarget {
      constructor(element, options) {
        super();
        assert.equal(element, ui['apple-map']);
        assert.equal(element.hidden, false);
        assert(authorized && librariesReady, 'both MapKit gates precede map creation');
        Object.assign(this, {options, center: options.region.center});
        map = this;
      }
      destroy() { calls.destroyed += 1; }
    },
    init(options) {
      calls.init += 1;
      assert.equal(options.language, 'zh-Hant-TW');
      assert.deepEqual(options.libraries, libraries);
      options.authorizationCallback(received => assert.equal(received, token));
      // A refresh is not the initial authorization event and must not create a map.
      kit.dispatchEvent(event('configuration-change', {status: 'Refreshed'}));
      setImmediate(() => {
        if (mode === 'unauthorized') {
          kit.dispatchEvent(event('error', {status: 'Unauthorized'}));
        } else {
          authorized = true;
          kit.dispatchEvent(event('configuration-change', {status: 'Initialized'}));
        }
      });
    },
    async load(requested) {
      assert.deepEqual(requested, libraries);
      if (mode === 'library-error') throw new Error('Mock library failure');
      librariesReady = true;
      return kit;
    },
  });

  t.mock.method(globalThis, 'setTimeout', (callback, milliseconds) => {
    const native = originals.setTimeout;
    return native(callback, Math.min(milliseconds, 350));
  });
  const browser = new EventTarget();
  browser.location = {search, reload() { calls.reload += 1; }};
  globalThis.window = browser;
  globalThis.document = {
    body: new Element(),
    getElementById: id => ui[id],
    createElement: () => new Element(),
    head: {append(script) {
      calls.sdk += 1;
      assert.equal(script.src, 'https://cdn.apple-mapkit.com/mk/6/mapkit.core.js');
      assert.equal(script.crossOrigin, 'anonymous');
      if (mode === 'blocked') {
        script.dispatchEvent(event('error'));
      } else {
        browser.mapkit = kit;
        script.dispatchEvent(event('load'));
      }
    }},
  };
  globalThis.testAddPocketArt = (mapArgument, sdkArgument, onState) => {
    assert.equal(mapArgument, map);
    assert.equal(sdkArgument, kit);
    calls.artAttached += 1;
    artStates.push(onState);
    if (mode === 'art-error' && calls.artAttached === 1) throw new Error('Mock artwork failure');
    return {dispose() { calls.artDisposed += 1; }};
  };
  t.after(() => {
    delete globalThis.window;
    delete globalThis.document;
    delete globalThis.testAddPocketArt;
  });
  await import(pathToFileURL(join(root, 'apple-map.js')));
  return {ui, browser, calls, map, artStates};
}
const originals = {setTimeout};

function checkLinks(ui, longitude, latitude) {
  assert.equal(ui['back-to-pocket'].href, './index.html?view=' + longitude + ',' + latitude + ',18.5');
  const url = new URL(ui['open-in-apple'].href);
  assert.equal(url.origin, 'https://maps.apple.com');
  assert.equal(url.pathname, '/frame');
  assert.equal(url.searchParams.get('center'), latitude + ',' + longitude);
  assert.equal(url.searchParams.get('span'), '0.0035,0.0035');
}

for (const mode of ['missing', 'invalid', 'blocked', 'unauthorized', 'library-error']) {
  test('Apple mode recovers with ' + mode, async (t) => {
    const {ui, calls, map} = await loadPage(t, mode, '?lat=51.50&lng=-0.12');
    assert.equal(map, undefined);
    assert.equal(ui['map-state'].hidden, false);
    assert.equal(ui['apple-map'].hidden, true);
    assert.equal(ui['retry-map'].hidden, false);
    assert.equal(calls.sdk, ['missing', 'invalid'].includes(mode) ? 0 : 1);
    assert.equal(calls.init, ['unauthorized', 'library-error'].includes(mode) ? 1 : 0);
    if (['missing', 'invalid'].includes(mode)) {
      assert.match(ui['map-status'].textContent, /Mac 版 Pocket City/);
      assert.doesNotMatch(ui['map-status'].textContent, /權杖|token/);
    }
    ui['retry-map'].dispatchEvent(event('click'));
    assert.equal(calls.reload, 1);
    checkLinks(ui, '121.543674', '25.027489');
  });
}

test('an authorized Apple map selects native places and keeps its links on the viewport', async (t) => {
  const {ui, browser, calls, map} = await loadPage(t, 'success', '?lat=25.01234&lng=121.543333');
  assert.equal(ui['map-state'].hidden, true);
  assert(map.options.region instanceof CoordinateRegion);
  assert(map.options.cameraBoundary instanceof CoordinateRegion);
  assert.equal(map.options.showsUserLocation, false);
  assert.equal(map.options.tracksUserLocation, false);
  assert.equal(map.options.showsPointsOfInterest, true);
  assert.equal(map.options.pointOfInterestFilter, undefined);
  assert.deepEqual(map.options.selectableMapFeatures, ['PointOfInterest']);
  assert(map.options.selectableMapFeatureSelectionAccessory instanceof PlaceSelectionAccessory);
  assert.equal(map.options.selectableMapFeatureSelectionAccessory.style, 'compactCallout');
  checkLinks(ui, '121.543333', '25.012340');

  const selection = ui['map-selection'];
  map.dispatchEvent(event('select', {annotation: {title: 'Some region', featureType: 'Territory'}}));
  assert.equal(selection.textContent, '');
  const annotation = {title: '信義書局', featureType: 'PointOfInterest'};
  map.dispatchEvent(event('select', {annotation}));
  assert(selection.textContent.includes(annotation.title));
  map.dispatchEvent(event('deselect', {annotation}));
  assert.equal(selection.textContent, '');

  map.center = new Coordinate(25.023456, 121.509876);
  map.dispatchEvent(event('region-change-end'));
  checkLinks(ui, '121.509876', '25.023456');
  browser.dispatchEvent(event('pagehide', {persisted: true}));
  assert.equal(calls.destroyed, 0);
  browser.dispatchEvent(event('pagehide', {persisted: false}));
  assert.equal(calls.artDisposed, 1);
  assert.equal(calls.destroyed, 1);
  browser.dispatchEvent(event('pagehide', {persisted: false}));
  assert.equal(calls.destroyed, 1);
});

test('artwork failure leaves Apple map and fallback links usable', async (t) => {
  const {ui, map, calls} = await loadPage(t, 'art-error');
  assert(map instanceof EventTarget);
  assert.equal(calls.destroyed, 0);
  assert.equal(ui['apple-map'].hidden, false);
  assert.equal(ui['map-state'].hidden, true);
  assert(ui['art-status'].textContent.length > 0);
  checkLinks(ui, '121.543674', '25.027489');
});

test('retrying degraded artwork replaces only the overlay and retains viewport and focus', async t => {
  const {ui, browser, calls, map, artStates} = await loadPage(t, 'success');
  const status = ui['art-status'];
  const retry = status.nextElementSibling;
  assert.equal(retry.hidden, true);
  assert.equal(retry.type, 'button');
  assert.equal(retry.attributes.get('aria-describedby'), 'art-status');
  assert.equal(status.attributes.get('aria-atomic'), 'true');
  assert.equal(status.style.display, 'block');
  assert.equal(status.classList.contains('visually-hidden'), true);

  map.center = new Coordinate(25.057321, 121.513211);
  const center = map.center;
  map.dispatchEvent(event('region-change-end'));
  artStates[0]('degraded');
  assert.match(status.textContent, /Apple 地圖仍可使用/);
  assert.equal(status.classList.contains('visually-hidden'), false);
  assert.equal(retry.hidden, false);
  retry.focus();
  retry.dispatchEvent(event('click'));
  retry.dispatchEvent(event('click'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls.artAttached, 2);
  assert.equal(calls.artDisposed, 1);
  assert.equal(calls.destroyed, 0);
  assert.equal(calls.reload, 0);
  assert.equal(map.center, center);
  checkLinks(ui, '121.513211', '25.057321');
  assert.equal(status.textContent, '');
  assert.equal(retry.hidden, true);
  assert.equal(document.activeElement, ui['apple-map']);

  artStates[0]('degraded');
  assert.equal(retry.hidden, true, 'stale overlay notifications have no effect');
  artStates[1]('degraded');
  assert.equal(retry.hidden, false, 'failure of the replacement allows another retry');
  browser.dispatchEvent(event('pagehide', {persisted: false}));
  retry.dispatchEvent(event('click'));
  assert.equal(calls.artAttached, 2);
  assert.equal(calls.artDisposed, 2);
  assert.equal(calls.destroyed, 1);
  map.center = new Coordinate(25.053, 121.550);
  map.dispatchEvent(event('region-change-end'));
  checkLinks(ui, '121.513211', '25.057321');
});
