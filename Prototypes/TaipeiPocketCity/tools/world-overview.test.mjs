import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';

const tiles = new URL('../cities/map-tiles/', import.meta.url);

// Each MVT tile is a sequence of length-delimited layer records (field 3).
function layerNames(bytes) {
  let offset = 0;
  function varint() {
    let value = 0;
    for (let shift = 0; shift <= 28; shift += 7) {
      assert.ok(offset < bytes.length, 'truncated length');
      const byte = bytes[offset++];
      value += (byte & 0x7f) * 2 ** shift;
      if (byte < 128) return value;
    }
    assert.fail('invalid layer length');
  }
  const names = [];
  while (offset < bytes.length) {
    assert.equal(bytes[offset++], 0x1a, 'MVT layer');
    const length = varint();
    const end = offset + length;
    assert.ok(end <= bytes.length);
    assert.equal(bytes[offset++], 0x0a, 'OpenFreeMap layer name');
    const nameLength = varint();
    assert.ok(nameLength > 0 && offset + nameLength < end);
    names.push(bytes.toString('utf8', offset, offset + nameLength));
    offset = end;
  }
  return names;
}

test('every world overview tile is locally available with complete MVT layers', async () => {
  const index = JSON.parse(await readFile(new URL('index.json', tiles)));
  assert.ok(Number.isInteger(index.overviewMaxZoom) && index.overviewMaxZoom >= 2);
  for (let z = 0; z <= index.overviewMaxZoom; z++) {
    for (let x = 0; x < 2 ** z; x++) {
      for (let y = 0; y < 2 ** z; y++) {
        const path = `overview/${z}-${x}-${y}.pbf`;
        const names = layerNames(await readFile(new URL(path, tiles)));
        assert.ok(names.includes('water'), path);
        if (z === 0) assert.ok(names.includes('boundary') && names.includes('place'), path);
      }
    }
  }
});
