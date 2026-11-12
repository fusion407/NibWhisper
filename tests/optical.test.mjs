import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {adler32,encodePage,parsePage,PageAssembler,PAGE_SIZE}from'../tools/optical-protocol.mjs';
import {publishReply,readCopiedKey}from'../tools/optical-bridge.mjs';
test('Adler32 matches a known standard vector',()=>assert.equal(adler32(Buffer.from('Wikipedia')),0x11e60398));
test('Gemini setup reads the clipboard only on request and reports invalid copies without exposing them',async()=>{
 const key='AQ.test_setup_key_local_fixture';
 const request={requestId:'fixture-setup',source:'clipboard'};
 let read=false;
 await assert.rejects(()=>readCopiedKey({},async()=>{read=true; return key;}),/Use copied key/);
 assert.equal(read,false);
 assert.equal(await readCopiedKey(request,async()=>` ${key}\n`),key);
 await assert.rejects(()=>readCopiedKey(request,async()=>''),/does not contain a complete Gemini key/);
 await assert.rejects(()=>readCopiedKey(request,async()=>{throw Error(key);}),error=>!error.message.includes(key)&&/could not read/.test(error.message));
});
test('Optical pages survive duplication and out-of-order capture',()=>{
 const packet='NIBQ1:'+Buffer.from(JSON.stringify({question:'Mrrgl? 🐟',notes:'map '.repeat(3000)})).toString('base64');
 const count=Math.ceil(packet.length/PAGE_SIZE),assembler=new PageAssembler();let completed;
 for(let i=count-1;i>=0;i--){completed=assembler.accept(encodePage(packet,'adventurer:request1',i));if(i>0)assert.equal(completed,null);}
 assert.equal(completed.packet,packet);assert.equal(assembler.accept(encodePage(packet,'adventurer:request1',0)).packet,packet);
});
test('Corrupt frames, invalid counts, and mixed requests never assemble',()=>{
 const first=encodePage('x'.repeat(3000),'first',0);first[40]^=1;assert.throws(()=>parsePage(first),/checksum/);
 const count=encodePage('x'.repeat(3000),'first',0);count.writeUInt16BE(300,14);assert.throws(()=>parsePage(count),/bounds/);
 const assembler=new PageAssembler();assembler.accept(encodePage('x'.repeat(3000),'first',0));assert.equal(assembler.accept(encodePage('y'.repeat(3000),'second',1)),null);
});
test('Reply slots receive constant data only; injection cannot become Lua',async()=>{
 const base=await fs.mkdtemp(path.join(os.tmpdir(),'nib-slots-')),addons=path.join(base,'Interface','AddOns');
 try{
  await fs.mkdir(path.join(addons,'NibWhisper'),{recursive:true});await fs.mkdir(path.join(addons,'NibWhisperReply001'));
  const packet='NIBR1:'+Buffer.from(JSON.stringify({answer:'|Hfoo|h\n" ) dangerous() --'})).toString('base64');
  assert.equal(await publishReply(addons,packet),1);
  const code=await fs.readFile(path.join(addons,'NibWhisperReply001','Data.lua'),'utf8');
  assert(code.includes('NibWhisper_Receive("NIBR1:'));assert(!code.includes('dangerous()'));
  await assert.rejects(()=>publishReply(addons,'NIBR1:"); evil()'),/Invalid/);
  await assert.rejects(()=>publishReply(base,packet),/AddOns/);
 }finally{assert.equal(path.dirname(path.resolve(base)),path.resolve(os.tmpdir()));assert(path.basename(base).startsWith('nib-slots-'));await fs.rm(base,{recursive:true,force:true});}
});
