import test from 'node:test';
import assert from 'node:assert/strict';
import {CELL_METRES,CELL_ORIGIN,taiwanCellAt,taiwanCellBounds,buildTaiwanCells} from '../taiwan-cell-geometry.js';

const area=[120.501,23.501,120.505,23.505];
const center=[120.503,23.503];
const ring=([w,s,e,n])=>[[w,s],[e,s],[e,n],[w,n],[w,s]];
const poly=(box,properties={},holes=[])=>({geometry:{type:'Polygon',coordinates:[ring(box),...holes.map(ring)]},properties});
const poi=(pt,name)=>({geometry:{type:'Point',coordinates:pt},properties:{class:'restaurant',name}});
const emptyTiles=()=>({woods:[],ways:[],buildings:[],water:[],fields:[],pois:[]});
const make=(tiles,more={})=>buildTaiwanCells({tiles,contains:()=>true,exclude:()=>false,view:area,center,zoom:19,...more});
const inside=(p,[w,s,e,n])=>p[0]>=w&&p[0]<=e&&p[1]>=s&&p[1]<=n;

test('shared grid uses 170 m cells west and east of its origin, independent of the viewport',()=>{
  assert.equal(CELL_METRES,170);
  assert.deepEqual(taiwanCellAt(...CELL_ORIGIN),[0,0]);
  for(const pt of [[118.31,24.41],[121.57,25.04],[119.5,23.56],[116.73,20.7],[114.36,10.38]]){
    const [i,j]=taiwanCellAt(...pt),bounds=taiwanCellBounds(i,j);
    assert.ok(inside(pt,bounds));
    assert.deepEqual(taiwanCellAt(bounds[0],bounds[1]),[i,j]);
    assert.equal(bounds[2],taiwanCellBounds(i+1,j)[0]);
    assert.equal(bounds[3],taiwanCellBounds(i,j+1)[1]);
  }
});

test('forest roots are stable under pan, and skip water, holes, buildings, mapped paths and authored plots',()=>{
  const tiles=emptyTiles(),pond=[120.5014,23.502,120.502,23.504],
    hole=[120.5022,23.501,120.5029,23.505],house=[120.503,23.501,120.5039,23.5022];
  tiles.woods=[poly(area,{class:'wood'},[hole])];tiles.water=[poly(pond)];tiles.buildings=[poly(house)];
  tiles.ways=[{geometry:{type:'LineString',coordinates:[[120.501,23.503],[120.505,23.503]]},properties:{class:'motorway'}}];
  const allowed=(lng,lat)=>lng<120.5048&&lat>23.5013;
  const a=make(tiles,{contains:allowed,exclude:(x,y)=>x>120.504&&y>23.503});
  assert.ok(a.trees.length>20);
  for(const [x,y] of a.trees){
    assert.ok(allowed(x,y)&&!(x>120.504&&y>23.503));
    assert.ok(![pond,hole,house].some(box=>inside([x,y],box)));
    assert.ok(Math.abs(y-23.503)*110574>13);
  }
  const sub=[120.5024,23.5028,120.504,23.5045];
  const b=make(tiles,{view:sub,contains:allowed,exclude:(x,y)=>x>120.504&&y>23.503});
  assert.deepEqual(b.trees.sort(),a.trees.filter(p=>inside(p,sub)).sort());
  tiles.woods=[];
  assert.deepEqual(make(tiles).trees,[]);
});

test('a roof spanning cells stays whole with its courtyard; only a named shop inside gets an awning',()=>{
  const tiles=emptyTiles(),box=[120.5013,23.5021,120.5032,23.5039],courtyard=[120.502,23.5026,120.5026,23.5032];
  const building=poly(box,{render_height:12},[courtyard]);
  tiles.buildings=[building,building];tiles.pois=[poi([120.5022,23.50285],'中庭地點')];
  const without=make(tiles).details,roofs=without.filter(f=>f.properties.kind==='roof');
  assert.equal(roofs.length,1);assert.deepEqual(roofs[0].geometry,building.geometry);
  assert.ok(without.some(f=>f.properties.kind==='window'));
  assert.ok(!without.some(f=>f.properties.kind==='awning'));
  tiles.pois.push(poi([120.5015,23.5025],'街角麵店'));
  assert.ok(make(tiles).details.some(f=>f.properties.kind==='awning'));
  assert.deepEqual(make(tiles,{overlapsAuthored:()=>true}).details,[]);
  assert.deepEqual(make(tiles,{contains:()=>false}).details,[]);
});

test('park planting is sparse, orchard canopies stay shorter, and plain wood remains dense',()=>{
  const tiles=emptyTiles();
  for(const kind of ['park','orchard','wood']){
    tiles.woods=[poly(area,{subclass:kind})];
    const trees=make(tiles).trees;
    assert.ok(trees.length>0);
    if(kind==='park')assert.ok(trees.length<150);
    if(kind==='orchard')assert.ok(trees.every(p=>p[2]<5&&p[3]==='round'));
    if(kind==='wood')assert.ok(trees.length>=250);
  }
});
