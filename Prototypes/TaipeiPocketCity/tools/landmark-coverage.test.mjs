import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdirSync,mkdtempSync,symlinkSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {approved,report} from './landmark-coverage.mjs';

test('a promoted POI and a new museum enter the queue even when both lack a model',()=>{
  const runtime=mkdtempSync(path.join(tmpdir(),'landmark-audit-')),data=path.join(runtime,'data');
  mkdirSync(data);
  writeFileSync(path.join(runtime,'survey-layer.js'),'');
  const feature=(id,name,category)=>({id,geometry:{type:'Point',coordinates:[121.56,25.04]},properties:{name,category,district:'信義區'}});
  writeFileSync(path.join(data,'city-place-index.json.gz'),gzipSync(JSON.stringify({features:[
    feature('poi/way/189788192','國父紀念館','yes'),feature('poi/node/42','新館','museum'),
    feature('poi/node/43','國父紀念館咖啡','cafe')]})));
  const result=report(data,path.join(runtime,'report'));
  const alias=path.join(runtime,'linked-tools');
  symlinkSync(fileURLToPath(new URL('.',import.meta.url)),alias,'dir');
  const cli=spawnSync(process.execPath,[path.join(alias,'landmark-coverage.mjs'),data,path.join(runtime,'cli-report')],{encoding:'utf8'});
  assert.equal(cli.status,1,cli.stderr);
  assert.equal(JSON.parse(cli.stdout).candidates,2);
  const entry=new URL('./landmark-coverage.mjs',import.meta.url).href;
  const stdin=spawnSync(process.execPath,['--input-type=module','-'],{
    input:'import {inventory} from '+JSON.stringify(entry)+'; console.log(typeof inventory);',
    encoding:'utf8'
  });
  assert.equal(stdin.status,0,stdin.stderr);
  assert.equal(stdin.stdout.trim(),'function');
  assert.equal(result.candidates,2);
  assert.equal(result.counts['待核對造型'],2);
  assert.ok(!result.missingPriority.includes('poi/way/189788192'));
  assert.ok(result.missingPriority.includes('poi/way/1159328965'));
});

test('both distinct views must match the actual camera and reviewed renderer revision',()=>{
  const folder=mkdtempSync(path.join(tmpdir(),'landmark-proof-'));
  const cameras={far:'?view=121,25,16.9',near:'?view=121,25,18.05'};
  const receipt={digest:'revision-1',reference:'https://example.org/hall',views:{}};
  const realWebP={'far': 'UklGRh4AAABXRUJQVlA4TBEAAAAvH8AFAAfQu9LVrP+BiOh/AAA=', 'near': 'UklGRh4AAABXRUJQVlA4TBEAAAAvH8AFAAdQz3L2rv+BiOh/AAA='};
  for(const [key,camera] of Object.entries(cameras)){
    const pixels=Buffer.from(realWebP[key],'base64');
    writeFileSync(path.join(folder,key+'.webp'),pixels);
    receipt.views[key]={file:key+'.webp',camera,sha256:createHash('sha256').update(pixels).digest('hex')};
  }
  assert.equal(approved(receipt,'revision-1',cameras,folder),true);
  assert.equal(approved(receipt,'revision-2',cameras,folder),false);
  assert.equal(approved(receipt,'revision-1',{...cameras,near:'different'},folder),false);
  writeFileSync(path.join(folder,'near.webp'),'changed');
  receipt.views.near.sha256=createHash('sha256').update('changed').digest('hex');
  assert.equal(approved(receipt,'revision-1',cameras,folder),false);
});
