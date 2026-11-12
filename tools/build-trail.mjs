import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const rxp=process.argv[2]||'A:/World of Warcraft/_forever_/Interface/AddOns/RXPGuides';
const index=JSON.parse(fs.readFileSync(path.join(root,'companion/data/guide-index.json'),'utf8'));
const hash=s=>crypto.createHash('sha256').update(s).digest('hex').slice(0,16);
const field=(header,key)=>[...header.matchAll(new RegExp('^[ \\t]*#'+key+'(?:[ \\t]+(.*))?[ \\t]*$','gmi'))].map(m=>m[1]?.trim()??'');
const conditional=s=>{const [value,condition]=s.split(/\s*<<\s*/,2);return[value.trim(),condition?.trim()||''];};
const scriptList=fs.readFileSync(path.join(rxp,'Guides/GuideList-forever.xml'),'utf8');
const files=[...scriptList.matchAll(/file="(Guides\/forever\/[^"\r\n]+\.lua)"/g)].map(m=>m[1]);
const starters=[];
for(const file of files){
 const input=fs.readFileSync(path.join(rxp,file),'utf8').replace(/\r\n/g,'\n');
 for(const start of input.matchAll(/\bRegisterGuide\(\s*\[(=*)\[/g)){
  const offset=start.index+start[0].length,end=input.indexOf(']'+start[1]+']',offset);if(end<offset)continue;
  const raw=input.slice(offset,end),bounds=[...raw.matchAll(/^[ \t]*step(?:[ \t].*)?$/gm)];if(!bounds.length)continue;
  const header=raw.slice(0,bounds[0].index);if(!field(header,'forever').length)continue;
  const name=field(header,'name')[0];if(!name)continue;
  const steps=bounds.map((m,i)=>{const text=raw.slice(m.index,bounds[i+1]?.index??raw.length).trim();return{index:i+1,text,questIds:[...new Set([...text.matchAll(/\.(?:accept|turnin|complete)\s+(\d+)/gi)].map(x=>+x[1]))]};});
  for(const value of field(header,'group')){
   const [group,groupCondition]=conditional(value),faction=/\(A\)|Alliance/.test(group)?'Alliance':/\(H\)|Horde/.test(group)?'Horde':'Unknown';
   starters.push({id:hash(raw+'\0'+group),name,group,faction,groupCondition,header,steps,source:file});
  }
 }
}
const seen=new Set(),all=[...index.guides,...starters].filter(g=>{const key=g.group+'\0'+g.name+'\0'+g.header;if(seen.has(key))return false;seen.add(key);return true;});
const dataset=hash(all.map(g=>g.id).sort().join(','));
const catalogue=all.map(g=>{
 const display=field(g.header,'displayname').map(conditional).find(d=>!d[1]||d[1]===g.faction)?.[0]||g.name;
 const level=display.match(/^(\d{1,2})\s*-\s*(\d{1,2})\b/);
 const mode=/Dungeon Quests/.test(g.group)?'Dungeon quests':/Dungeon Guide/.test(g.group)?'Dungeon route':/Mage/.test(g.group)?'Mage AoE':'Solo route';
 const conditions=[...(g.groupCondition?[g.groupCondition]:[]),...g.header.split('\n').flatMap(l=>l.trim().startsWith('<<')?[l.trim().slice(2).trim()]:[])];
 return {id:g.id,name:g.name,title:display,group:g.group,faction:g.faction,mode,min:level?+level[1]:0,max:level?+level[2]:0,race:field(g.header,'defaultfor')[0]||'',conditions,header:g.header,next:field(g.header,'next').map(conditional),steps:g.steps.length};
});
assert.equal(new Set(catalogue.map(g=>g.id)).size,catalogue.length);
for(const f of ['Alliance','Horde'])assert(catalogue.some(g=>g.faction===f&&g.min===1)&&catalogue.some(g=>g.faction===f&&g.max===60));
const map=Object.fromEntries(catalogue.map(g=>[g.id,g.steps]));
const lua=v=>typeof v==='string'?'"'+v.replace(/[\\"\x00-\x1f\x7f]/g,c=>c==='\\'?'\\\\':c==='"'?'\\"':'\\'+c.charCodeAt(0).toString().padStart(3,'0'))+'"':typeof v==='number'?String(v):Array.isArray(v)?'{'+v.map(lua).join(',')+'}':'{'+Object.entries(v).map(([k,x])=>'['+lua(k)+']='+lua(x)).join(',')+'}';
const lines=['-- Generated from the supplied route index and installed starter guide literals. Data only.','local addon = _G.NibWhisper','if not addon then return end','addon.TrailData = {dataset='+lua(dataset)+', chapters='+lua(catalogue)+', bodies={'];
for(const g of all)lines.push('['+lua(g.id)+']='+lua(g.steps.map(s=>s.text))+',');
lines.push('}}');
fs.writeFileSync(path.join(root,'addon/NibWhisper_Guide/TrailData.lua'),lines.join('\n')+'\n');
const stats={dataset,imported:index.guides.length,starter:all.length-index.guides.length,chapters:all.length,steps:all.reduce((n,g)=>n+g.steps.length,0),starterFiles:files};
fs.writeFileSync(path.join(root,'companion/data/trail-catalog.json'),JSON.stringify({schema:1,...stats,chapterLengths:map}));
fs.writeFileSync(path.join(root,'companion/data/trail-starters.json'),JSON.stringify({schema:1,guides:all.filter(g=>g.source)}));
console.log(JSON.stringify({...stats,starterFiles:files.length}));
