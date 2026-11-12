import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createHash, randomUUID} from 'node:crypto';
import {decodePacket, encodePacket, NibError, plainObject} from './protocol.mjs';

const hash=value=>createHash('sha256').update(value).digest('hex').slice(0,16);
const characterPattern=/^Player-\d{1,12}-[a-f0-9]{1,24}$/i;
const validStamp=(r,now)=>plainObject(r)&&Number.isSafeInteger(r.at)&&r.at>0&&r.at<=now+86400000&&typeof r.by==='string'&&/^[a-z0-9_-]{1,80}$/i.test(r.by);
const newer=(a,b)=>!b||a.at>b.at||(a.at===b.at&&a.by>b.by);

export function validateTrailState(state,catalog,now=Date.now()){
 if(!plainObject(state)||state.dataset!==catalog.dataset||!plainObject(state.guides))throw new NibError('Both computers need the same Nib Trail route package.',409,'route_version');
 const out={dataset:catalog.dataset,guides:{}};
 if(state.selected!==undefined){const r=state.selected;if(!validStamp(r,now)||!Object.hasOwn(catalog.chapterLengths,r.id))throw new NibError('Invalid selected route.');out.selected={id:r.id,at:r.at,by:r.by};}
 for(const id of Object.keys(state.guides).sort()){
  const r=state.guides[id],length=Object.hasOwn(catalog.chapterLengths,id)&&catalog.chapterLengths[id];
  if(!length||!validStamp(r,now)||!Number.isInteger(r.step)||r.step<1||r.step>length+1)throw new NibError('Invalid route progress or timestamp.');
  const indices=(value)=>{if(value===undefined)return[];if(!Array.isArray(value)||value.length>length||value.some(i=>!Number.isInteger(i)||i<1||i>length))throw new NibError('Invalid route step list.');return [...new Set(value)].sort((a,b)=>a-b);};
  const marks={};
  if(r.marks!==undefined){
   if(!plainObject(r.marks))throw new NibError('Invalid route objective checks.');
   for(const [step,entries] of Object.entries(r.marks)){
    if(!/^[1-9]\d*$/.test(step)||Number(step)>length||!Array.isArray(entries)||entries.length>128||entries.some(entry=>!Number.isInteger(entry)||entry<1||entry>2048))throw new NibError('Invalid route objective checks.');
    if(entries.length)marks[step]=[...new Set(entries)].sort((a,b)=>a-b);
   }
  }
  out.guides[id]={step:r.step,at:r.at,by:r.by,skipped:indices(r.skipped),sticky:indices(r.sticky),...(Object.keys(marks).length?{marks}:{})};
 }
 return out;
}
export function mergeTrailStates(states,catalog,now=Date.now()){
 const guides=new Map();let selected;
 for(const state of states){const s=validateTrailState(state,catalog,now);if(s.selected&&newer(s.selected,selected))selected=s.selected;for(const [id,r]of Object.entries(s.guides))if(newer(r,guides.get(id)))guides.set(id,r);}
 return {dataset:catalog.dataset,guides:Object.fromEntries([...guides].sort(([a],[b])=>a.localeCompare(b))),...(selected?{selected}:{})};
}
export async function resolveTrailFolder(env=process.env){
 if(env.NIB_SYNC_DIR){if(!path.isAbsolute(env.NIB_SYNC_DIR))throw new NibError('NIB_SYNC_DIR must be an absolute shared folder path.',503,'sync_config');return path.resolve(env.NIB_SYNC_DIR);}
 for(const root of [env.OneDriveConsumer,env.OneDrive,env.OneDriveCommercial])if(root&&path.isAbsolute(root)&&await fs.stat(root).then(s=>s.isDirectory()).catch(()=>false))return path.join(root,'NibTrail');
 return null;
}
export function createTrailSync({dataDir,env=process.env,deviceId=hash(os.hostname()+'\0'+path.resolve(dataDir))}){
 if(!/^[a-f0-9]{16}$/.test(deviceId))throw Error('Invalid sync device identity');
 let tail=Promise.resolve();
 async function sync(packet){
  const request=decodePacket(packet,'NIBS1'),now=Date.now();
  if(!plainObject(request)||request.schema!==1||typeof request.requestId!=='string'||!/^[\w-]{1,100}$/.test(request.requestId)||!Number.isSafeInteger(request.capturedAt)||Math.abs(request.capturedAt*1000-now)>1800000||typeof request.character!=='string'||!characterPattern.test(request.character))throw new NibError('Invalid or stale character sync request.');
  const root=await resolveTrailFolder(env);if(!root)throw new NibError('No shared progress folder. Set NIB_SYNC_DIR in companion/.env on both PCs, or sign into OneDrive.',503,'sync_not_configured');
  let catalog;try{catalog=JSON.parse(await fs.readFile(path.join(dataDir,'trail-catalog.json'),'utf8'));}catch{throw new NibError('The installed companion is missing its route catalog. Update both computers.',503,'catalog_missing');}
  if(!/^[a-f0-9]{16}$/.test(catalog.dataset)||!plainObject(catalog.chapterLengths))throw new NibError('Invalid local route catalog.',503,'catalog_missing');
  const own=validateTrailState(request.state,catalog,now);
  const identity=hash(request.character.toLowerCase());
  const dir=path.join(root,catalog.dataset,identity),states=[own];
  await fs.mkdir(dir,{recursive:true});
  const realRoot=await fs.realpath(root),realDir=await fs.realpath(dir);
  if(path.relative(realRoot,realDir)!==path.join(catalog.dataset,identity))throw new NibError('The shared progress folder contains an unexpected link.',409,'sync_path');
  let replicas=0;
  for(const file of (await fs.readdir(dir)).filter(f=>/^[a-f0-9]{16}\.json$/.test(f)).sort().slice(0,50)){
   const filename=path.join(dir,file),stat=await fs.lstat(filename).catch(()=>null);
   if(!stat?.isFile()||stat.isSymbolicLink()||stat.size>150000)continue;
   try{states.push(validateTrailState(JSON.parse(await fs.readFile(filename,'utf8')),catalog,now));replicas++;}catch{/* A cloud replica may still be downloading or from an obsolete client. */}
  }
  const state=mergeTrailStates(states,catalog,now);
  // Verify reply fits before persisting. These files contain guide progress only.
  const reply=encodePacket('NIBP1',{schema:1,requestId:request.requestId,capturedAt:request.capturedAt,character:request.character,state});
  const target=path.join(dir,deviceId+'.json'),tmp=path.join(dir,randomUUID()+'.tmp');
  const saved=await fs.lstat(target).catch(()=>null);if(saved?.isSymbolicLink())throw new NibError('Unsafe progress file link.',409,'sync_path');
  const body=JSON.stringify(state)+'\n';
  if(!saved||await fs.readFile(target,'utf8').catch(()=>null)!==body){
   try{await fs.writeFile(tmp,body,{flag:'wx',mode:0o600});await fs.rename(tmp,target);}finally{await fs.unlink(tmp).catch(()=>{});}
  }
  return {packet:reply,replicas};
 }
 return {exchange(packet){const next=tail.then(()=>sync(packet));tail=next.catch(()=>{});return next;}};
}
