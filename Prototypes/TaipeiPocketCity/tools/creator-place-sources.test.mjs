import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {validateCreatorCatalog,appendCreatorPlaces,creatorEntry,loadCreatorCatalog} from '../creator-place-sources.js';
const catalog=JSON.parse(await readFile(new URL('../../CreatorLists/lala/CreatorPlaceSources.json',import.meta.url)));

test('full frozen list preserves every resolved branch and excludes pending pins',()=>{
  assert.equal(validateCreatorCatalog(catalog),catalog);
  const city={type:'FeatureCollection',features:[]};
  const result=appendCreatorPlaces(city,catalog);
  assert.equal(result.features.length,catalog.summary.uniquePlaces);
  const twice=appendCreatorPlaces(result,catalog);
  assert.deepEqual(twice,result);
  assert.equal(city.features.length,0);
  assert.ok(!result.features.some(f=>catalog.pending.some(p=>f.id==='creator/lala/'+p.cid)));
});
test('existing IDs and no-bundle path stay unchanged',()=>{
  const row=catalog.entries.find(r=>!r.isNew);
  const city={type:'FeatureCollection',features:[{properties:{placeId:row.placeId},geometry:{coordinates:[row.longitude,row.latitude]}}]};
  assert.equal(appendCreatorPlaces(city,null),city);
  assert.equal(appendCreatorPlaces(city,catalog).features.filter(f=>f.properties.placeId===row.placeId).length,1);
  assert.equal(creatorEntry(catalog,row.placeId),row);
  assert.equal(creatorEntry(catalog,'not-a-place'),null);
});
test('malformed duplicate ID, wrong author and unsafe original fail closed',()=>{
  for(const mutate of [
    c=>c.entries.push(c.entries[0]),
    c=>c.entries[0].latitude=Infinity,
    c=>c.entries[0].isNew='true',
    c=>delete c.entries[0].category,
    c=>c.entries[0].placeId='',
    c=>c.entries.find(r=>r.posts.length).posts[0].url='javascript:alert(1)',
    c=>c.entries.find(r=>r.posts.length).posts[0].author='other',
    c=>c.scope='production',
  ]){const copy=structuredClone(catalog);mutate(copy);assert.equal(validateCreatorCatalog(copy),null);}
});
test('catalog missing in production does not break map loading',async()=>{
  const old=globalThis.fetch;globalThis.fetch=async()=>({ok:false});
  try{assert.equal(await loadCreatorCatalog(),null);}finally{globalThis.fetch=old;}
});

test('native-only known places remain visible without the expiring public snapshot',()=>{
  const row=catalog.entries.find(r=>r.placeId.startsWith('savvy/apple_maps/'));
  assert.ok(row && !row.isNew);
  const result=appendCreatorPlaces({features:[]},catalog);
  assert.equal(result.features.filter(f=>f.id===row.placeId).length,1);
  assert.ok(!result.features.some(f=>f.id==='creator/lala/'+row.cid));
});

test('creator and live public layers share one canonical pin without suppressing unrelated stores',async()=>{
  const {withoutCreatorDuplicates}=await import('../creator-place-sources.js');
  const row=catalog.entries[0];
  const features=[{properties:{placeId:row.placeId}},{properties:{placeId:'unrelated-branch'}}];
  const data={type:'FeatureCollection',features};
  assert.deepEqual(withoutCreatorDuplicates(data,catalog).features,[features[1]]);
  assert.equal(withoutCreatorDuplicates(data,null),data);
  assert.equal(features.length,2);
  const added=appendCreatorPlaces({features:[]},catalog);
  assert.ok(added.features.every(f=>f.properties.creatorSource));
});
