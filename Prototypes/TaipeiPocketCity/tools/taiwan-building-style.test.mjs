import test from 'node:test';
import assert from 'node:assert/strict';
import {buildingStyle, storefrontStyle} from '../taiwan-building-style.js';

const swatches = ['wall','roof','glass','frame','trim','awning','sign','accent'];
const representative = [
  [{building:'house'}, 'residential'],
  [{building:'retail'}, 'retail'],
  [{amenity:'university'}, 'school'],
  [{building:'warehouse'}, 'industrial'],
  [{building:'shrine'}, 'traditional'],
  [{amenity:'place_of_worship', religion:'taoist'}, 'traditional'],
  [{amenity:'place_of_worship', building:'church'}, 'civic'],
  [{height:45}, 'tower'],
];

test('every use has complete, varied, repeatable finish schedules for both zoom levels', () => {
  for (const [tags, expected] of representative) {
    const sets = Array.from({length:100},(_,i)=>buildingStyle('way/'+i,tags));
    assert.ok(new Set(sets.map(p=>p.wall)).size >= 3, expected+' wall variety');
    assert.ok(new Set(sets.map(p=>p.glass)).size >= 2 || expected==='traditional', expected+' glazing');
    for (const [i,plan] of sets.entries()) {
      assert.equal(plan.family,expected);
      for (const channel of swatches) assert.match(plan[channel],/^#[0-9a-f]{6}$/);
      assert.notEqual(plan.glass,plan.frame);
      assert.notEqual(plan.roof,plan.wall);
      assert.deepEqual(buildingStyle('way/'+i,{...tags},{zoom:18}),plan);
    }
  }
});

test('roof and facade evidence are independent; valid explicit paint outranks material', () => {
  const id = 'way/890';
  const p = buildingStyle(id,{'building:colour':'#Cc8833','roof:color':'#26E',
                              'building:material':'stone','roof:material':'steel'});
  assert.equal(p.wall,'#cc8833');
  assert.equal(p.roof,'#2266ee');
  assert.deepEqual(buildingStyle(id,{'roof:material':'steel','roof:colour':'bogus'}).roof,
                   buildingStyle(id,{'roof:material':'metal'}).roof);
  assert.equal(buildingStyle(id,{'building:colour':'not-listed;light blue'}).wall,'#aec8cf');
  for(const [source,ink] of [['olive','#929153'],['白色','#f4efe4'],['藍色','#87a9ba'],['lightsteelblue','#acbdcd'],['綠色、灰色、紅色','#91ae92']]){
    assert.equal(buildingStyle(1072725772,{'building:colour':source,'building:material':'plaster'}).wall,ink);
  }
  assert.equal(buildingStyle(id,{'building:material':'brick'}).roof,buildingStyle(id).roof);
  assert.equal(buildingStyle(id,{'roof:material':'slate'}).wall,buildingStyle(id).wall);
  for (const material of ['glass','bricks','wood','concrete','copper']) {
    const colours = new Set(Array.from({length:35},(_,i)=>buildingStyle(i,{'building:material':material}).wall));
    assert.ok(colours.size >= 2 && colours.size <= 3);
  }
  assert.deepEqual(buildingStyle(id,{'building:colour':'constructor','roof:material':'__proto__'}),buildingStyle(id));
});

test('silhouette fallback identifies a hall, a tall building, or a shop without inferring a temple or school', () => {
  assert.equal(buildingStyle(3,{}, {width:30,depth:46,height:12}).family,'hall');
  assert.equal(buildingStyle(3,{}, {area:2000,height:40}).family,'tower');
  assert.equal(buildingStyle(3,{'building:levels':'18'}).family,'tower');
  assert.equal(buildingStyle(3,{}, {area:90,shop:'restaurant'}).family,'retail');
  assert.equal(buildingStyle(3,{building:'apartments'}, {height:16,shop:'restaurant'}).family,'residential');
  assert.equal(buildingStyle(3,{building:'yes',shop:'no'}).family,'residential');
  assert.equal(buildingStyle(3,{amenity:'school'}, {area:1500,height:12}).family,'school');
});

test('mapped local shop types select recognisable displays and fabric, retaining the frame of the building', () => {
  const base = buildingStyle(345);
  for (const [category,detail] of [['cafe','cafe'],['tea','cafe'],['fast_food','food'],['greengrocer','produce'],
    ['market','produce'],['stationery','books'],['boutique','apparel'],['pharmacy','health'],
    ['florist','flowers'],['bicycle','cycle'],['hardware','display']]) {
    const shop = storefrontStyle(category,840,base);
    assert.equal(shop.detail,detail);
    assert.equal(shop.frame,base.frame);
    assert.equal(shop.glass,base.glass);
    assert.deepEqual(shop,storefrontStyle(category,840,base));
    for (const k of ['awning','sign','accent','trim']) assert.match(shop[k],/^#[0-9a-f]{6}$/);
  }
  const neighbours = Array.from({length:64},(_,i)=>storefrontStyle('restaurant',i,base));
  assert.equal(new Set(neighbours.map(shop=>shop.awning)).size,4);
  assert.equal(storefrontStyle('other',1,base).sign,base.sign);
});
