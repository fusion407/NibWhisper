import fs from 'node:fs';import path from 'node:path';import {fileURLToPath}from'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','addon');
for(let i=1;i<=200;i++){
 const name='NibWhisperReply'+String(i).padStart(3,'0'),dir=path.join(root,name);fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(path.join(dir,name+'.toc'),`## Interface: 16001, 11509\n## Title: Nib reply slot ${i}\n## Notes: Optional data-only reply transport for NibWhisper\n## LoadOnDemand: 1\n## Dependencies: NibWhisper\n## Group: NibWhisper\n## Version: 0.1.0\nData.lua\n`);
 fs.writeFileSync(path.join(dir,'Data.lua'),'-- Empty until the local Nib companion publishes a reply.\n');
}
console.log('Prepared 200 optional load-on-demand reply modules.');
