import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'forever_guide_Fusion_1401.txt');
const input = fs.readFileSync(source);
const raw = input.toString('utf8').trim();
const match = /^(\d+)\|([\s\S]*)\|(\d+)$/.exec(raw);
assert(match, 'Guide bundle header not recognized');
const parts = [...match[2].matchAll(/(-?\d+):([A-Za-z0-9+/=]+)%/g)];
assert.equal(parts.map(p=>p[0]).join(''),match[2]);

function decode(bytes, tag) {
  const key = Buffer.from(tag.toLowerCase().slice(-16));
  const base = Array(16).fill(0), padding=16-key.length;
  for(let i=0;i<16;i++) base[i]=key[(i-padding)&15]??0;
  for(let i=0;i<16;i++) base[-i&15]=base[(15-i)&15]^base[(13-i)&15]^base[(12-i)&15]^base[(10-i)&15];
  const state=Array.from({length:256},(_,i)=>i);
  let j=0;
  for(let i=0;i<256;i++){j=(j+state[i]+base[i&15])&255;[state[i],state[j]]=[state[j],state[i]];}
  const output=Buffer.alloc(bytes.length); let i=0;j=0;
  for(let k=0;k<bytes.length;k++){i=(i+1)&255;j=(j+state[i])&255;[state[i],state[j]]=[state[j],state[i]];output[k]=bytes[k]^state[(state[i]+state[j])&255];}
  return output;
}
function adler(bytes){let a=1,b=0;for(const v of bytes){a=(a+v)%65521;b=(b+a)%65521;}return(b*65536+a)>>>0;}
const hash = value=>crypto.createHash('sha256').update(value).digest('hex');
const guideTexts=parts.flatMap(p=>{
  const compressed=decode(Buffer.from(p[2],'base64'),'Fusion#1401');
  const plain=zlib.inflateSync(compressed,{maxOutputLength:128*1024*1024});
  assert.equal(adler(plain),Number(BigInt.asUintN(32,BigInt(p[1]))));
  return plain.toString('utf8').split('\0').filter(Boolean);
});
assert.equal(guideTexts.length,Number(match[1]));
const field=(s,name)=>new RegExp('^#'+name+'\\s+(.+)$','m').exec(s)?.[1]?.trim()??'';
const guides=guideTexts.map(text=>{
  const boundaries=[...text.matchAll(/^\s*step\b[^\r\n]*$/gm)];
  const header=text.slice(0,boundaries[0]?.index??text.length);
  const group=field(text,'group');
  return {
    id:hash(text).slice(0,16),name:field(text,'name'),group,subgroup:field(text,'subgroup'),
    faction:/\(A\)|Alliance/.test(group)?'Alliance':/\(H\)|Horde/.test(group)?'Horde':'Unknown',
    header,
    steps:boundaries.map((b,i)=>{
      const step=text.slice(b.index,boundaries[i+1]?.index??text.length).trim();
      const ids=[...step.matchAll(/\.(?:accept|turnin|complete|isOnQuest|isQuestComplete|isQuestTurnedIn|abandon|questcount)\s+(\d+)/gi)].map(m=>Number(m[1]));
      return {index:i+1,text:step,questIds:[...new Set(ids)],conditions:step.split(/\r?\n/).filter(l=>/<<|^\s*#(?:requires|completewith|label|sticky|optional)/.test(l))};
    })
  };
});
const index={schema:1,edition:'forever',source:{title:'User-supplied RestedXP Forever 1–60 guide bundle',sha256:hash(input),guideCount:guides.length,baseVersion:Number(match[3]),note:'Private local source. Conditions and prerequisites are preserved as data, not executed or independently validated.'},guides};
const dataDir=path.join(root,'companion','data');fs.mkdirSync(dataDir,{recursive:true});
fs.writeFileSync(path.join(dataDir,'guide-index.json'),JSON.stringify(index));
fs.copyFileSync(path.join(root,'research_notes','Forever companion assistant','forever-seeds.json'),path.join(dataDir,'knowledge.json'));
console.log(JSON.stringify({guideCount:guides.length,stepCount:guides.reduce((n,g)=>n+g.steps.length,0),bytes:fs.statSync(path.join(dataDir,'guide-index.json')).size,edition:index.edition}));
