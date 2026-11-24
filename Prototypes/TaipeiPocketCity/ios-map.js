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

export function connectIOSMap(map, Marker, channel) {
  const markers = new Map();
  let pins = [], userMarker;

  function refresh() {
    const bounds = visibleRegion(map.getBounds());
    const groups = new Map();
    const pointGroups = new Map();
    const publicAnchors = [];
    for (const pin of pins) {
      if (!bounds.contains(pin.point)) continue;
      const pointKey = pin.point.join(',');
      let key = pointGroups.get(pointKey) ?? pointKey;
      if (pin.kind === 'post' && !groups.has(key)) {
        const {x,y} = map.project(pin.point);
        const nearby = publicAnchors.find(anchor => Math.abs(x - anchor.x) < 44 && Math.abs(y - anchor.y) < 44);
        if (nearby) key = nearby.key;
        else publicAnchors.push({key,x,y});
      }
      pointGroups.set(pointKey, key);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(pin);
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
          channel.postMessage({event: 'select', ids: button.placeIDs});
        });
        marker = new Marker({element: button, anchor: 'bottom'}).setLngLat(group[0].point).addTo(map);
        markers.set(key, marker);
      }
      const button = marker.getElement();
      button.placeIDs = group.map(pin => pin.id);
      const representative = group.find(pin => pin.selected) ?? group[0];
      button.dataset.kind = representative.kind;
      button.classList.toggle('selected', !!representative.selected);
      button.textContent = representative.name;
      button.setAttribute('aria-label', group.map(pin => pin.label).join(', '));
    }
  }

  function reportViewport() {
    refresh();
    channel.postMessage({event: 'move', region: visibleRegion(map.getBounds()).region});
  }
  map.on('moveend', reportViewport);
  const host = {
    update(state) {
      if (Array.isArray(state.pins)) pins = state.pins;
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
      if (state.bounds === null) {
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
