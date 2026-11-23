import {addPocketArt} from './apple-pocket-art.js';

const defaultCenter = {latitude: 25.027489, longitude: 121.543674};
const taipei = {south: 24.945, west: 121.44, north: 25.225, east: 121.683};
const spanDegrees = .0035;
const mapkitSource = 'https://cdn.apple-mapkit.com/mk/6/mapkit.core.js';
const libraries = ['full-map', 'geojson'];
const mapkitToken = /^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

function taipeiCenter(latitude, longitude) {
  if (latitude >= taipei.south && latitude <= taipei.north &&
      longitude >= taipei.west && longitude <= taipei.east) {
    return {latitude, longitude};
  }
  return defaultCenter;
}

function initialCenter() {
  const query = new URLSearchParams(window.location.search);
  return taipeiCenter(Number(query.get('lat')), Number(query.get('lng')));
}

function updateLinks({latitude, longitude}) {
  const view = [longitude.toFixed(6), latitude.toFixed(6), '18.5'].join(',');
  document.getElementById('back-to-pocket').href = './index.html?view=' + view;
  const url = new URL('https://maps.apple.com/frame');
  url.searchParams.set('center', [latitude.toFixed(6), longitude.toFixed(6)].join(','));
  url.searchParams.set('span', [spanDegrees, spanDegrees].join(','));
  document.getElementById('open-in-apple').href = url.href;
}

async function readToken() {
  try {
    const config = await import('./apple-config.js');
    const value = typeof config.token === 'string' ? config.token.trim() : '';
    return mapkitToken.test(value) ? value : null;
  } catch {
    return null;
  }
}

// Apple documents manual initialization with a public browser-token callback.
// https://developer.apple.com/documentation/mapkitjs/loading-the-latest-version-of-mapkit-js
function loadCore() {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = mapkitSource;
    script.async = true;
    script.crossOrigin = 'anonymous';
    function finish(error) {
      clearTimeout(timer);
      script.removeEventListener('load', loaded);
      script.removeEventListener('error', failed);
      if (error) {
        script.remove();
        reject(error);
      } else {
        resolve(window.mapkit);
      }
    }
    function loaded() {
      finish(typeof window.mapkit?.init === 'function' ? null : new Error('MapKit JS unavailable'));
    }
    function failed() {
      finish(new Error('MapKit JS script unavailable'));
    }
    const timer = setTimeout(failed, 12_000);
    script.addEventListener('load', loaded);
    script.addEventListener('error', failed);
    document.head.append(script);
  });
}

function initializeMapKit(sdk, token) {
  return new Promise((resolve, reject) => {
    let authenticated = false;
    let loaded = false;
    function finish(error) {
      clearTimeout(timer);
      sdk.removeEventListener('configuration-change', configured);
      sdk.removeEventListener('error', failed);
      if (error) reject(error);
      else resolve();
    }
    function configured(event) {
      if (event.status !== 'Initialized') return;
      authenticated = true;
      if (loaded) finish();
    }
    function failed() {
      finish(new Error('MapKit JS could not initialize'));
    }
    const timer = setTimeout(failed, 15_000);
    sdk.addEventListener('configuration-change', configured);
    sdk.addEventListener('error', failed);
    try {
      sdk.init({
        authorizationCallback: complete => complete(token),
        language: 'zh-Hant-TW',
        libraries,
      });
      sdk.load(libraries).then(() => {
        loaded = true;
        if (authenticated) finish();
      }, failed);
    } catch {
      failed();
    }
  });
}

function region(sdk, center, latitudeDelta, longitudeDelta) {
  return new sdk.CoordinateRegion(
    new sdk.Coordinate(center.latitude, center.longitude),
    new sdk.CoordinateSpan(latitudeDelta, longitudeDelta),
  );
}

function createMap(sdk, container, center) {
  const {south, west, north, east} = taipei;
  return new sdk.Map(container, {
    region: region(sdk, center, spanDegrees, spanDegrees),
    cameraBoundary: region(sdk, {latitude: (south + north) / 2, longitude: (west + east) / 2},
      north - south, east - west),
    showsZoomControl: true,
    showsCompass: sdk.FeatureVisibility.Adaptive,
    showsScale: sdk.FeatureVisibility.Adaptive,
    isRotationEnabled: true,
    showsUserLocation: false,
    showsUserLocationControl: false,
    tracksUserLocation: false,
    showsPointsOfInterest: true,
    // MapKit's default POI filter includes all place categories.
    selectableMapFeatures: [sdk.MapFeatureType.PointOfInterest],
    selectableMapFeatureSelectionAccessory: new sdk.PlaceSelectionAccessory({
      style: sdk.PlaceSelectionAccessory.Styles.CompactCallout,
    }),
  });
}

function wireMap(sdk, map, center) {
  const selected = document.getElementById('map-selection');
  const placeType = sdk.MapFeatureType.PointOfInterest;
  const recenterLinks = () => {
    const camera = map.center;
    updateLinks(camera ? taipeiCenter(camera.latitude, camera.longitude) : center);
  };
  const selectPlace = ({annotation}) => {
    if (annotation?.featureType !== placeType) return;
    selected.textContent = annotation.title ? '已選取 ' + annotation.title + '。' : '已選取 Apple 地圖地點。';
  };
  const deselectPlace = ({annotation}) => {
    if (annotation?.featureType === placeType) selected.textContent = '';
  };
  map.addEventListener('region-change-end', recenterLinks);
  map.addEventListener('select', selectPlace);
  map.addEventListener('deselect', deselectPlace);
  recenterLinks();
  return () => {
    map.removeEventListener('region-change-end', recenterLinks);
    map.removeEventListener('select', selectPlace);
    map.removeEventListener('deselect', deselectPlace);
  };
}

function startArtwork(map, sdk, container, unwireMap) {
  const status = document.getElementById('art-status');
  // Keep the status region available to assistive technology before any tile fails.
  status.style.display = 'block';
  status.setAttribute('aria-atomic', 'true');
  function setStatus(message) {
    status.classList.toggle('visually-hidden', !message);
    status.textContent = message;
  }
  setStatus('');
  const retry = document.createElement('button');
  retry.id = 'retry-artwork';
  retry.type = 'button';
  retry.className = 'map-action';
  retry.textContent = '重新載入插畫';
  retry.setAttribute('aria-describedby', 'art-status');
  retry.hidden = true;
  status.after(retry);

  let art, attempt = 0, disposed = false;
  async function attach() {
    if (disposed || retry.disabled) return;
    const current = ++attempt;
    const hadFocus = document.activeElement === retry;
    let failed = false;
    function degraded() {
      if (disposed || attempt !== current) return;
      failed = true;
      setStatus('插畫圖層暫時無法完整載入。Apple 地圖仍可使用。');
      retry.hidden = false;
    }
    if (!retry.hidden) setStatus('正在重新載入插畫…');
    retry.disabled = true;
    try {
      art?.dispose();
      art = undefined;
      const layer = await addPocketArt(map, sdk, state => {
        if (state === 'degraded') degraded();
      });
      if (disposed) {
        layer.dispose();
        return;
      }
      art = layer;
      if (!failed) {
        setStatus('');
        retry.hidden = true;
      }
    } catch {
      degraded();
    } finally {
      retry.disabled = false;
      if (!disposed && hadFocus && (document.activeElement === retry || document.activeElement === document.body)) {
        if (retry.hidden) {
          container.tabIndex = -1;
          container.focus({preventScroll: true});
        } else {
          retry.focus({preventScroll: true});
        }
      }
    }
  }
  function pagehide(event) {
    if (event.persisted) return;
    disposed = true;
    window.removeEventListener('pagehide', pagehide);
    retry.removeEventListener('click', attach);
    unwireMap();
    art?.dispose();
    map.destroy();
  }
  retry.addEventListener('click', attach);
  window.addEventListener('pagehide', pagehide);
  return attach();
}

async function start() {
  const center = initialCenter();
  const status = document.getElementById('map-status');
  const state = document.getElementById('map-state');
  const retry = document.getElementById('retry-map');
  const container = document.getElementById('apple-map');
  let map;
  function unavailable(message) {
    map?.destroy();
    container.hidden = true;
    status.textContent = message;
    retry.hidden = false;
    retry.addEventListener('click', () => window.location.reload());
  }

  updateLinks(center);
  const token = await readToken();
  if (!token) {
    unavailable('網頁版尚未連接 Apple 地圖。你可以直接使用 Mac 版 Pocket City，或從上方在 Apple 地圖查看這個街區。');
    return;
  }

  let sdk;
  try {
    sdk = await loadCore();
  } catch {
    unavailable('Apple 地圖元件暫時無法載入。請確認網路後重試，或開啟 Apple 地圖。');
    return;
  }

  let unwireMap;
  try {
    await initializeMapKit(sdk, token);
    container.hidden = false;
    map = createMap(sdk, container, center);
    unwireMap = wireMap(sdk, map, center);
    state.hidden = true;
  } catch {
    unavailable('Apple 地圖無法啟動。請確認權杖允許目前的網站網域，再重新整理。');
    return;
  }

  await startArtwork(map, sdk, container, unwireMap);
}

await start();
