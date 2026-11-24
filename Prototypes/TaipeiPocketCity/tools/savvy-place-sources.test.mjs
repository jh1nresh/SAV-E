import assert from 'node:assert/strict';
import {test} from 'node:test';
import {buildSavvyPlaceSources} from './build-savvy-place-sources.mjs';
import {cityPlaceID,validSavvyPosts,verifiedSavvyMapProjection} from '../savvy-place-sources.js';
import {originalPlacePhoto} from '../place-photos.js';

const at='2026-11-23T18:00:00.000Z', expiresAt='2026-11-24T18:00:00.000Z';
const place={provider:'apple_maps',providerPlaceID:'TestA',name:'同名餐廳',
  address:'臺北市大安區仁愛路4段10號2樓',longitude:121.54,latitude:25.04};
const post={place,platform:'instagram',sourceURL:'https://www.instagram.com/p/Fixture/',verifiedAt:at};
const mapPlace=(id, detail, name=place.name)=>({properties:{placeId:id,name,detail,district:'大安區'},
  geometry:{type:'Point',coordinates:[place.longitude,place.latitude]}});
const project=(features,posts=[post],reviewed=[])=>buildSavvyPlaceSources({expiresAt,posts},{features},[],reviewed);

test('exact address binds only one same-name venue even at identical coordinates',()=>{
  const result=project([mapPlace('poi/node/1','仁愛路四段10號2F'),
    mapPlace('poi/node/2','仁愛路四段10號3F'),mapPlace('poi/node/3','仁愛路四段11號2F')]);
  assert.deepEqual(result.venues.map(row=>row.placeId),['poi/node/1']);
  assert.deepEqual(result.verifiedPins,[]);
});

test('a branch without an exact base match keeps its approved source on its own Savvy place ID',()=>{
  const other={...post,place:{...place,providerPlaceID:'Test/Other',address:'臺北市大安區仁愛路四段10號3樓'},
    sourceURL:'https://www.instagram.com/p/OtherBranch/'};
  const result=project([mapPlace('poi/node/1','仁愛路四段10號2F')],[post,other]);
  assert.equal(result.venues.length,1);
  assert.equal(result.venues[0].posts[0].url,post.sourceURL);
  assert.equal(result.verifiedPins.length,1);
  const [pin]=result.verifiedPins;
  assert.equal(pin.placeId,'savvy/apple_maps/Test%2FOther');
  assert.equal(pin.detail,other.place.address);
  assert.equal(pin.posts[0].url,other.sourceURL);
  assert.deepEqual(pin.point,[other.place.longitude,other.place.latitude]);
  assert.equal(result.coverage.additionalOriginals,1);
});

test('a Savvy map pin survives the first source expiry and is removed when the last one expires',()=>{
  const row={placeId:'savvy/apple_maps/TestA',point:[121.54,25.04],name:'分店',detail:'仁愛路四段10號',
    district:'大安區',category:'restaurant',categoryLabel:'餐廳',posts:[
    {platform:'instagram', url:'https://www.instagram.com/p/Before/',expiresAt:'2026-11-24T12:00:00.000Z'},
    {platform:'threads', url:'https://www.threads.com/@example/post/Last',expiresAt},
  ]};
  const snapshotExpiry=Date.parse(expiresAt);
  const invalidText=['detail','district','category','categoryLabel'].map((key,i)=>({...row,placeId:`savvy/bad/${i}`,[key]:123}));
  const projection=verifiedSavvyMapProjection([row,{...row,placeId:'poi/node/4'},{...row,point:[25,121]},...invalidText,null],
    Date.parse('2026-11-24T12:00:00.000Z'),snapshotExpiry);
  assert.deepEqual(projection.featureCollection.features.map(f=>f.id),[row.placeId]);
  assert.equal(projection.featureCollection.features[0].properties.sourcesExpireAt,snapshotExpiry);
  assert.equal(projection.featureCollection.features[0].properties.source,'Savvy');
  assert.equal(projection.nextExpiry,snapshotExpiry);
  assert.deepEqual(verifiedSavvyMapProjection([row],snapshotExpiry,snapshotExpiry).featureCollection.features,[]);
});

test('same door with a different room, stall or unspecified floor cannot borrow a source',()=>{
  for(const [expected,other] of [['2樓A室','2樓B室'],['138攤','137攤'],['2樓','']]){
    const candidate={...post,place:{...place,address:'臺北市大安區仁愛路四段10號'+expected}};
    assert.equal(project([mapPlace('poi/node/1','仁愛路四段10號'+other)],[candidate]).venues.length,0);
  }
});

test('duplicate city identities and multiple venues claiming a pin do not project',()=>{
  const first=mapPlace('poi/node/1','仁愛路四段10號2F');
  const second=mapPlace('poi/node/2','仁愛路四段10號2F');
  assert.equal(project([first,second]).coverage.reasons.multiple_city_matches,1);
  assert.equal(project([first],[post,{...post,place:{...place,providerPlaceID:'TestB'}}]).coverage.reasons.city_identity_conflict,2);
  assert.equal(project([first,mapPlace('poi/node/1','仁愛路四段99號2F','他店')]).coverage.reasons.city_identity_conflict,1);
});

test('inactive reviewed link remains reserved and does not stop other venues',()=>{
  const known={...place,placeId:'poi/node/1',savvyName:place.name,cityName:place.name,
    door:'仁愛路四段10號',district:'大安區',cityUnit:'2樓'};
  const first=mapPlace(known.placeId,'仁愛路四段10號2F');
  const unrelated={...post,place:{...place,providerPlaceID:'ShelfA'}};
  assert.equal(project([first],[unrelated],[known]).coverage.reasons.city_identity_conflict,1);
});

test('a missing or expired cover preserves the original link and rejects foreign URLs',()=>{
  const time=Date.parse(at);
  const url='https://www.threads.com/@example/post/AbcDef';
  const approved={url:'https://media.cdninstagram.com/photo.jpg',permission:'author',expiresAt};
  const item={platform:'threads',url,expiresAt};
  const posts=validSavvyPosts([{...item,cover:approved},{...item,cover:{...approved,expiresAt:at}},
    {...item,url:'https://www.threads.com.evil.test/@example/post/AbcDef'},
    {...item,expiresAt:at},null],time);
  assert.deepEqual(posts.map(post=>post.coverPermission),['author',null]);
  assert.deepEqual(posts.map(({url,cover})=>[url,cover]),[[url,approved.url],[url,null]]);
});

test('equivalent OSM IDs may resolve a photo while a different OSM ID never borrows it',()=>{
  const point=[121.5076858,25.0433177];
  assert.equal(cityPlaceID({id:'osm-node-2572568042'}),'poi/node/2572568042');
  assert.ok(originalPlacePhoto({id:'osm-node-2572568042',name:'阿宗麵線',point}));
  assert.equal(originalPlacePhoto({id:'osm-node-4194681689',name:'阿宗麵線',point}),null);
});
