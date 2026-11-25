import assert from 'node:assert/strict';
import test from 'node:test';
import {buildShop} from '../city-shopfronts.js';
import {surveyedShopCamera} from '../city-shop-search.js';
import {friendlyFronts} from '../taipei-friendly-frontages.js';
import * as views from '../taipei-frontage-cameras.js';
import {completeFrontagePack,frontageSearchRow,supplements} from '../taipei-frontage-pack.js';

test('the city-sourced bays join both street rendering and existing-name search',()=>{
  assert.equal(friendlyFronts.length,4);
  assert.equal(new Set(supplements.map(row=>row.id)).size,supplements.length);
  for(const row of friendlyFronts){
    const {id,name,center,angle,pack,district,street}=row;
    assert.equal(completeFrontagePack(pack,[]).find(front=>front.id===id),row);
    assert.equal(completeFrontagePack(pack,[row]).filter(front=>front.id===id).length,1);
    assert.deepEqual(frontageSearchRow([name,district,'',121,25,null,id]),[name,district,street,...center,angle,id]);
    for(const key of ['detail','addressNode','address','phone','registration']){
      assert.ok(!Object.hasOwn(row,key),key);
    }
  }
});

test('rendered storefronts and their hit planes fit measured wall heights',()=>{
  for(const row of friendlyFronts){
    const ground=Math.max(row.groundZ,row.surveyBase);
    const scale=Math.min(1,(row.surveyTop-ground-.13)/3.25);
    const vertices=[];
    const object=buildShop(vertices,row,[0,0,ground],scale,{write:()=>[0,0,1,1]},true);
    assert.ok(object.count>0);
    for(const z of [...vertices.filter((_,i)=>i%13===2),...object.hit.map(p=>p[2])]){
      assert.ok(z>=ground&&z<=row.surveyTop-.12,row.name);
    }
  }
});

test('search chooses checked sightlines for each recovered shop',()=>{
  for(const row of friendlyFronts){
    const entry=frontageSearchRow([row.name,row.district,'',121,25,null,row.id]);
    const heights=views.frontageViewHeights;
    for(const [clientWidth,anchorHeights] of [[390,heights.mobile],[980,heights.desktop]]){
      for(const clientHeight of anchorHeights){
        const pose=surveyedShopCamera(entry,views,{clientWidth,clientHeight});
        assert.equal(pose?.verifiedFrontage,true,row.name);
      }
    }
  }
});
