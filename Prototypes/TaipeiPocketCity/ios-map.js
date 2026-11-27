import {originalPlacePhoto} from './place-photos.js';
import {placeButtonIcon} from './place-pins.js?v=category-badges-1';
import {setPlacePinEmphasis} from './photo-pin-motion.js';

// The bundled page is the only document allowed to talk to the iOS host.
// Keep account pins in memory. In particular, keep names out of tile/font requests.
const wrap = value => ((value % 360) + 360) % 360;
export function visibleRegion(bounds) {
  const west = bounds.getWest(), south = bounds.getSouth(), north = bounds.getNorth();
  const delta = bounds.getEast() - west;
  const width = Math.abs(delta) >= 360 ? 360 : wrap(delta);
  return {
    contains: ([x,y]) => y >= south && y <= north && wrap(x - west) <= width,
    region: [wrap(west + width / 2 + 180) - 180, (south + north) / 2, width, north - south],
  };
}

function validCamera(camera) {
  return Array.isArray(camera) && camera.length === 5 && camera.every(Number.isFinite)
    && Math.abs(camera[0]) <= 180 && Math.abs(camera[1]) <= 90
    && camera[2] >= -2 && camera[2] <= 21.6 && Math.abs(camera[3]) <= 180
    && camera[4] >= 0 && camera[4] <= 65;
}

function renderPin(button, pin, photo, saved, shared) {
  const key = JSON.stringify([pin.name,pin.category,photo,saved,shared]);
  if (button.artKey === key) return;
  button.artKey = key;
  button.classList.add('ios-art-pin');
  const art = document.createElement('span');
  art.className = photo ? 'ios-pin-art' : 'ios-pin-art ios-category-art';
  art.setAttribute('aria-hidden','true');
  const {canvas} = placeButtonIcon(pin.category);
  art.append(canvas);
  if (photo) {
    const image = document.createElement('img');
    image.alt = '';
    image.decoding = 'async';
    image.onerror = () => { image.remove(); art.classList.add('ios-category-art'); };
    image.src = photo;
    art.append(image);
  }
  if (saved) {
    const bookmark = document.createElement('span');
    bookmark.className = 'ios-pin-bookmark';
    art.append(bookmark);
  }
  if (shared) {
    const friend = document.createElement('span');
    friend.className = 'ios-pin-friend';
    art.append(friend);
  }
  const name = document.createElement('span');
  name.className = 'ios-pin-name';
  name.textContent = pin.name;
  button.replaceChildren(art,name);
}

export function connectIOSMap(map, Marker, channel, controls, explore, {floorEvents, visiblePin} = {}) {
  const markers = new Map();
  let pins = [], userMarker;
  let hiddenAtlasIDs = '';
  const routeLayer = 'savvy-guide-route';
  let openPlaceId, detailTarget, friendTarget, expiryTimer, showsPublicPins = true;

  if (explore) {
    map.on('pocketplacechange', event => {
      openPlaceId = event.placeId;
      refresh();
    });
    explore.button.addEventListener('click', () => {
      if (detailTarget && detailTarget.expiresAt > Date.now() && detailTarget.placeId === openPlaceId) {
        channel.postMessage({event: 'select', ids: [detailTarget.id]});
      }
    });
    explore.friendButton?.addEventListener('click', () => {
      if (friendTarget && friendTarget.expiresAt > Date.now() && friendTarget.placeId === openPlaceId) {
        channel.postMessage({event:'select',ids:friendTarget.ids});
      }
    });
    map.on('remove', () => clearTimeout(expiryTimer));
  }

  function updateRoutes(routes) {
    const features = routes.map(coordinates => ({
      type: 'Feature', properties: {}, geometry: {type: 'LineString', coordinates},
    }));
    const data = {type: 'FeatureCollection', features};
    const current = map.getSource(routeLayer);
    if (current) {
      current.setData(data);
    } else if (features.length) {
      map.addSource(routeLayer, {type: 'geojson', data});
      map.addLayer({
        id: routeLayer, type: 'line', source: routeLayer,
        layout: {'line-cap': 'round', 'line-join': 'round'},
        paint: {'line-color': '#B33F2B', 'line-width': 5},
      });
    }
  }

  function refresh() {
    const bounds = visibleRegion(map.getBounds());
    const groups = new Map();
    const pointGroups = new Map();
    const publicAnchors = [];
    const now = Date.now();
    let nextExpiry = Infinity;
    detailTarget = undefined;
    friendTarget = undefined;
    const covered = new Set();
    const byEntity = new Map();
    for (const pin of pins) {
      if (pin.kind === 'post' && !showsPublicPins && !pin.isSaved) continue;
      const venueKey = pin.publicVenueID ?? (pin.kind === 'post' ? pin.id : undefined);
      if (visiblePin) {
        const venue = venueKey && explore?.venues.get(venueKey);
        const placeID = venue && venue.expiresAt > now ? venue.placeId : pin.creatorPlaceID ?? pin.id;
        if (!visiblePin(pin.point, placeID)) continue;
      }
      const key = pin.creatorPlaceID || venueKey || pin.id;
      if (!byEntity.has(key)) byEntity.set(key, []);
      byEntity.get(key).push(pin);
    }
    for (const members of byEntity.values()) {
      const pin = members.find(p => p.kind === 'saved' || p.kind === 'visited') ??
        members.find(p => p.kind !== 'post') ?? members[0];
      const publicPin = members.find(p => p.kind === 'post');
      const venueKey = pin.publicVenueID ?? (publicPin && publicPin.id);
      const venue = venueKey && explore?.venues.get(venueKey);
      const reviewed = venue && venue.expiresAt > now ? venue : null;
      const photo = reviewed && originalPlacePhoto({placeId: reviewed.placeId})?.src;
      if (reviewed) {
        if (reviewed.placeId === openPlaceId && (publicPin && showsPublicPins || pin.isSaved)) {
          const ownPin = members.find(p => p.kind === 'saved' || p.kind === 'visited');
          const detail = ownPin ?? publicPin ?? pin;
          detailTarget = {id:detail.id, saved:!!ownPin, expiresAt:reviewed.expiresAt, placeId:reviewed.placeId};
        }
        if (reviewed.placeId === openPlaceId) {
          const friends = members.filter(p => p.kind === 'shared');
          if (friends.length) friendTarget = {ids:friends.map(p => p.id),placeId:reviewed.placeId,expiresAt:reviewed.expiresAt};
        }
        nextExpiry = Math.min(reviewed.expiresAt, nextExpiry);
        if (members.every(p => p.kind === 'post' && !p.isSaved)) continue;
      }
      if (!bounds.contains(pin.point)) continue;
      if (reviewed) covered.add(reviewed.placeId);
      // Creator identity is independent of live-post freshness. A saved/shared
      // native pin covers the same atlas place without promoting creator posts
      // into verified public discovery or changing the native selection route.
      if (pin.creatorPlaceID) covered.add(pin.creatorPlaceID);
      const entry = {...pin, members, photo, reviewedPlaceId: reviewed?.placeId};
      const pointKey = pin.point.join(',');
      let markerKey = pointGroups.get(pointKey) ?? pointKey;
      if (pin.kind === 'post' && !pin.isSaved && !photo && !groups.has(markerKey)) {
        const {x,y} = map.project(pin.point);
        const nearby = publicAnchors.find(anchor => Math.abs(x - anchor.x) < 44 && Math.abs(y - anchor.y) < 44);
        if (nearby) markerKey = nearby.key;
        else publicAnchors.push({key: markerKey,x,y});
      }
      pointGroups.set(pointKey, markerKey);
      if (!groups.has(markerKey)) groups.set(markerKey, []);
      groups.get(markerKey).push(entry);
    }
    if (explore && !showsPublicPins) {
      for (const venue of explore.venues.values()) {
        if (venue.expiresAt > now) covered.add(venue.placeId);
      }
    }
    const ids = [...covered].sort();
    const signature = ids.join('|');
    if (signature !== hiddenAtlasIDs) {
      hiddenAtlasIDs = signature;
      map.savvyAccountPlaceIds = ids;
      map.fire('pocketaccountpins', {placeIds: ids});
    }
    if (explore) {
      explore.button.hidden = !detailTarget;
      if (explore.friendButton) explore.friendButton.hidden = !friendTarget;
      explore.button.textContent = detailTarget?.saved ? '查看我的收藏' : '在探索中查看';
      clearTimeout(expiryTimer);
      if (Number.isFinite(nextExpiry)) expiryTimer = setTimeout(refresh, Math.min(2**31-1, nextExpiry-now));
    }
    for (const [key, marker] of markers) {
      if (!groups.has(key)) {
        marker.remove();
        markers.delete(key);
      }
    }
    for (const [key, group] of groups) {
      let marker = markers.get(key);
      if (!marker) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'ios-place-pin';
        button.addEventListener('click', event => {
          event.stopPropagation();
          if (button.pocketPlace && explore?.open) explore.open(button.pocketPlace,button);
          else {
            if (button.pinIsOpen) {
              setPlacePinEmphasis(button.querySelector?.('.ios-pin-art'), true, {repeat:true});
            }
            channel.postMessage({event: 'select', ids: button.placeIDs});
          }
        });
        marker = new Marker({element: button, anchor: 'bottom'}).setLngLat(group[0].point).addTo(map);
        markers.set(key, marker);
      }
      const button = marker.getElement();
      const all = group.flatMap(p => p.members);
      button.placeIDs = [...new Set(all.map(pin => pin.id))];
      const representative = group.find(pin => pin.selected) ?? group.find(pin => pin.isSaved) ?? group[0];
      const single = group.length === 1;
      button.pocketPlace = single && representative.reviewedPlaceId && (showsPublicPins || representative.isSaved)
        ? {placeId:representative.reviewedPlaceId,name:representative.name,point:representative.point,
          category:representative.category,detail:representative.address,source:'Savvy'} : null;
      button.dataset.kind = single ? representative.kind : 'group';
      const selected = all.some(pin => pin.selected);
      button.classList.toggle('selected', selected);
      const open = selected || (single && !!openPlaceId && openPlaceId === representative.reviewedPlaceId);
      button.classList.toggle('ios-pin-open', open);
      const saved = single && all.some(pin => pin.isSaved || pin.kind === 'saved' || pin.kind === 'visited');
      button.classList.toggle('is-saved', saved);
      const previous = button.querySelector?.('.ios-pin-art');
      if (representative.category || representative.isSaved !== undefined || representative.photo) {
        const pin = single ? representative : {name:group.length+' 個地點',category:'other'};
        renderPin(button, pin, single ? representative.photo : null, saved, single && all.some(p=>p.kind === 'shared'));
      } else button.textContent = representative.name;
      const art = button.querySelector?.('.ios-pin-art');
      if (art && (button.pinIsOpen !== open || art !== previous)) {
        setPlacePinEmphasis(art, open, {animate:art === previous});
      }
      button.pinIsOpen = open;
      button.setAttribute('aria-label', all.map(pin => pin.label).join(', '));
    }
  }

  let viewportSerial;
  function reportViewport() {
    refresh();
    const center = map.getCenter?.();
    const camera = center && [wrap(center.lng + 180) - 180, center.lat, map.getZoom(), map.getBearing(), map.getPitch()];
    const message = {event: 'move', region: visibleRegion(map.getBounds()).region};
    if (validCamera(camera)) message.camera = camera;
    if (viewportSerial !== undefined) message.viewportSerial = viewportSerial;
    channel.postMessage(message);
  }
  map.on('moveend', reportViewport);
  floorEvents?.addEventListener('mall101-floor', refresh);
  if (floorEvents) map.on('remove', () => floorEvents.removeEventListener('mall101-floor', refresh));
  const host = {
    update(state) {
      if (Array.isArray(state.pins)) pins = state.pins;
      if (Array.isArray(state.routes)) updateRoutes(state.routes);
      if ('user' in state) {
        userMarker?.remove();
        userMarker = null;
        if (state.user) {
          const dot = document.createElement('span');
          dot.className = 'ios-user-dot';
          dot.setAttribute('role','img');
          dot.setAttribute('aria-label',state.user.label);
          userMarker = new Marker({element: dot}).setLngLat(state.user.point).addTo(map);
        }
      }
      if (state.presentation) {
        showsPublicPins = state.presentation.showsPublicPins;
        controls?.(state.presentation);
      }
      if (Number.isSafeInteger(state.viewportSerial)) viewportSerial = state.viewportSerial;
      if (validCamera(state.restoreCamera)) {
        const [lng,lat,zoom,bearing,pitch] = state.restoreCamera;
        map.fire('pocketcamerarestore');
        map.jumpTo({center: [lng,lat], zoom, bearing, pitch});
      } else if (state.bounds === null) {
        map.jumpTo({center:[121,24],zoom:5.8,bearing:0,pitch:0});
      } else if (state.bounds) {
        const [w, s, e, n] = state.bounds;
        map.fitBounds([[w,s],[e,n]], {duration: 0, padding: 24, maxZoom: 19});
      }
      refresh();
    },
  };
  return host;
}
