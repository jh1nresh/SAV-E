import {test} from 'node:test';
import assert from 'node:assert/strict';
import {connectIOSMap, visibleRegion} from '../ios-map.js';

test('native pin selections track the current visible IDs without moving the camera on refresh', t => {
  const buttons = [], messages = [], commands = [];
  const dom = globalThis.document;
  globalThis.document = {createElement: () => ({
    dataset:{}, classList:{toggle() {}},
    addEventListener(type, handler) { this[type] = handler; },
    setAttribute(name, value) { this[name] = value; },
  })};
  t.after(() => { if (dom === undefined) delete globalThis.document; else globalThis.document = dom; });
  class Marker {
    constructor({element}) { this.button = element; buttons.push(element); }
    getElement() { return this.button; }
    setLngLat() { return this; }
    addTo() { return this; }
    remove() { this.button.removed = true; }
  }
  let east = 122;
  const bounds = {getEast: () => east, getWest: () => 120, getNorth: () => 26, getSouth: () => 24};
  const map = {on(event, fn) { this[event] = fn; }, getBounds: () => bounds,
    fitBounds(...args) { commands.push(args); }};
  const bridge = connectIOSMap(map, Marker, {postMessage: value => messages.push(value)});
  const a = {id:'first',name:'Tea',kind:'saved',label:'Tea, saved',point:[121,25]};
  const b = {...a,id:'second',name:'Bookshop',kind:'visited',label:'Bookshop, visited'};
  bridge.update({pins:[a,b],bounds:[120,24,122,26]});
  assert.equal(buttons.length,1);
  assert.equal(buttons[0]['aria-label'],'Tea, saved, Bookshop, visited');
  buttons[0].click({stopPropagation() {}});
  assert.deepEqual(messages.pop(), {event:'select', ids:['first','second']});
  bridge.update({pins:[b]});
  assert.equal(buttons[0].textContent,'Bookshop');
  buttons[0].click({stopPropagation() {}});
  assert.deepEqual(messages.pop(), {event:'select', ids:['second']});
  assert.equal(buttons[0].dataset.kind, 'visited');
  east = 120.5;
  map.moveend();
  assert.deepEqual(messages.pop(), {event:'move',region:[120.25,25,0.5,2]});
  assert.equal(buttons[0].removed,true);
  assert.equal(commands.length,1);
});

test('wraps both representations of a viewport crossing the date line', () => {
  for (const east of [183,-177]) {
    const box = visibleRegion({getWest:()=>177,getEast:()=>east,getSouth:()=>4,getNorth:()=>8});
    assert.deepEqual(box.region,[-180,6,6,4]);
    for (const lon of [-179,179]) assert.ok(box.contains([lon,6]));
    assert.equal(box.contains([0,6]), false);
  }
});
