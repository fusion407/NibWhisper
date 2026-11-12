import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,mkdir,rm,readdir} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createTrailSync,mergeTrailStates,resolveTrailFolder} from '../lib/trail-sync.mjs';
import {createHttpServer} from '../lib/http.mjs';
import {encodePacket,decodePacket} from '../lib/protocol.mjs';
const catalog={dataset:'1234567890abcdef',chapterLengths:{'1111111111111111':60,'2222222222222222':50}};
const [first,second]=Object.keys(catalog.chapterLengths),char='Player-42-0000CAFE';
const state=(guides={},selected)=>({dataset:catalog.dataset,guides,...(selected?{selected}:{})});
const record=(step,at,by)=>({step,at,by,skipped:[],sticky:[]});
const ask=(requestId,s,character=char)=>encodePacket('NIBS1',{schema:1,requestId,capturedAt:Math.floor(Date.now()/1000),character,state:s});
async function dirs(t){const root=await mkdtemp(path.join(os.tmpdir(),'nib-trail-'));t.after(async()=>{assert.equal(path.dirname(root),path.resolve(os.tmpdir()));assert(path.basename(root).startsWith('nib-trail-'));await rm(root,{recursive:true,force:true});});const dataDir=path.join(root,'data');await mkdir(dataDir);await writeFile(path.join(dataDir,'trail-catalog.json'),JSON.stringify(catalog));return{root,dataDir};}

test('separate devices pull the latest cursor, retain other chapters and honor intentional rewinds',async t=>{
 const {root,dataDir}=await dirs(t);const env={NIB_SYNC_DIR:path.join(root,'shared')};
 const desktop=createTrailSync({dataDir,env,deviceId:'1111222233334444'}),laptop=createTrailSync({dataDir,env,deviceId:'1111222233335555'});
 const a=state({[first]:record(18,1000,'desktop')},{id:first,at:1000,by:'desktop'});
 await desktop.exchange(ask('first',a));
 const laptopPull=decodePacket((await laptop.exchange(ask('pull',state()))).packet,'NIBP1');
 assert.equal(laptopPull.state.guides[first].step,18);assert.equal(laptopPull.state.selected.id,first);
 const b=state({[first]:record(15,2000,'laptop'),[second]:{...record(7,2100,'laptop'),skipped:[3],sticky:[4]}},{id:second,at:2200,by:'laptop'});
 await laptop.exchange(ask('offline-laptop',b));
 const both=decodePacket((await desktop.exchange(ask('merge',a))).packet,'NIBP1');
 assert.equal(both.state.guides[first].step,15);assert.deepEqual(both.state.guides[second].skipped,[3]);assert.deepEqual(both.state.guides[second].sticky,[4]);assert.equal(both.state.selected.id,second);
 const unrelated=decodePacket((await desktop.exchange(ask('other-char',state(),'Player-42-0000BEEF'))).packet,'NIBP1');
 assert.deepEqual(unrelated.state.guides,{});
 const sub=path.join(env.NIB_SYNC_DIR,catalog.dataset);const files=await readdir(sub);assert.equal(files.length,2);
});

test('invalid snapshots cannot replace data; conflicting replicas merge deterministically',async t=>{
 const {root,dataDir}=await dirs(t),env={NIB_SYNC_DIR:path.join(root,'shared')};const sync=createTrailSync({dataDir,env});
 await assert.rejects(sync.exchange(ask('bad',state({[first]:record(700,1000,'desktop')}))),/Invalid route progress/);
 await assert.rejects(sync.exchange(ask('bad-build',{dataset:'wrong',guides:{}})),{code:'route_version'});
 await assert.rejects(sync.exchange(ask('bad-char',state(),'../secret')),/Invalid or stale/);
 const s1=state({[first]:record(5,500,'desktop')}),s2=state({[first]:record(8,500,'laptop')});
 assert.deepEqual(mergeTrailStates([s1,s2],catalog),mergeTrailStates([s2,s1],catalog));
 assert.equal(mergeTrailStates([s1,s2],catalog).guides[first].step,8);
 assert.equal(await resolveTrailFolder({OneDrive:root}),path.join(root,'NibTrail'));
});

test('sync exchange runs on protected localhost endpoint independently of model availability',async t=>{
 const {root,dataDir}=await dirs(t);const trailSync=createTrailSync({dataDir,env:{NIB_SYNC_DIR:path.join(root,'shared')}});
 let calls=0;const assistant={busy:false,handleAsk(){calls++;throw Error('unexpected AI call');}};
 const app=createHttpServer({assistant,trailSync,dataDir,port:0});const address=await app.listen();t.after(()=>new Promise(resolve=>app.server.close(resolve)));
 const base=`http://127.0.0.1:${address.port}`,status=await(await fetch(base+'/api/status')).json();
 const body=JSON.stringify({packet:ask('http-sync',state({[first]:record(10,1000,'desktop')}))});
 const headers={Origin:base,'Content-Type':'application/json'};
 assert.equal((await fetch(base+'/api/trail-sync',{method:'POST',headers,body})).status,403);
 const response=await fetch(base+'/api/trail-sync',{method:'POST',headers:{...headers,'X-Nib-Token':status.csrfToken},body});
 assert.equal(response.status,200);const result=decodePacket((await response.json()).packet,'NIBP1');assert.equal(result.state.guides[first].step,10);assert.equal(calls,0);
});
