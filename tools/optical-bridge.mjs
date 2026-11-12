import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath}from'node:url';
import {execFile,spawn}from'node:child_process';
import {promisify}from'node:util';
import readline from 'node:readline';
import crypto from 'node:crypto';
import {PageAssembler}from'./optical-protocol.mjs';
import {validGeminiKey}from'../companion/lib/gemini.mjs';
import {fontPool,publishFont,resetPool,validSlot}from'./font-transport.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const captureScript=path.join(root,'tools','capture-optical.ps1');
const envelope=(prefix,value)=>prefix+':'+Buffer.from(JSON.stringify(value)).toString('base64');

export async function readCopiedKey(request, readClipboard=async()=>{
 const {stdout}=await promisify(execFile)('powershell.exe',['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',captureScript,'-ReadKey'],{windowsHide:true,timeout:4500,maxBuffer:1024});
 return stdout;
}) {
 if(request.source!=='clipboard')throw Error('Open Gemini setup and choose Use copied key.');
 let key;
 try{key=String(await readClipboard()).trim();}catch{throw Error('The helper could not read the copied key. Copy it again and retry.');}
 if(!validGeminiKey(key))throw Error('Your clipboard does not contain a complete Gemini key. Copy the full key from Google AI Studio and try again.');
 return key;
}

export async function publishReply(addonsRoot,packet) {
 if(!/^(?:NIBR1|NIBP1|NIBA1|NIBK1):[A-Za-z0-9+/=]+$/.test(packet)||packet.length>180000)throw Error('Invalid data-only reply packet');
 const target=path.resolve(addonsRoot);if(path.basename(target).toLowerCase()!=='addons')throw Error('Expected an explicit Interface/AddOns directory');
 const main=await fs.lstat(path.join(target,'NibWhisper'));
 if(!main.isDirectory()||main.isSymbolicLink())throw Error('NibWhisper must be installed in this AddOns directory');
 const payload=`-- Published locally by Nib. Data only; the model cannot generate this code.\nif NibWhisper_Receive then NibWhisper_Receive("${packet}") end\n`;
 let written=0;
 const realTarget=await fs.realpath(target);
 for(let i=1;i<=200;i++) {
  const dir=path.join(target,'NibWhisperReply'+String(i).padStart(3,'0'));
  const stat=await fs.lstat(dir).catch(()=>null);if(!stat)continue;
  if(!stat.isDirectory()||stat.isSymbolicLink())throw Error('Reply slot path is not an ordinary installed directory');
  const real=await fs.realpath(dir);if(path.dirname(real).toLowerCase()!==realTarget.toLowerCase())throw Error('Reply slot escaped AddOns directory');
  const temporary=path.join(dir,'Data.'+crypto.randomBytes(6).toString('hex')+'.tmp');
  try{await fs.writeFile(temporary,payload,{flag:'wx'});await fs.rename(temporary,path.join(dir,'Data.lua'));written++;}
  finally{await fs.unlink(temporary).catch(()=>{});}
 }
 if(!written)throw Error('Optional Nib reply modules are not installed. Run Install-Nib.ps1 -Optical while WoW is closed.');
 return written;
}
// A request that names a reply file is answered through the font files in the assistant addon.
// Older addons, and installs without the file pool, still use the load-on-demand reply slots.
// Stage 0 is the receipt for the request; stage 1 is the reply or its error.
export async function deliver(addonsRoot,request,stage,packet) {
 const pool=validSlot(request?.replyFont)?await fontPool(addonsRoot):null;
 if(pool)return `${await publishFont(pool,request.replyFont,stage,packet)} reply file(s) in block ${request.replyFont}`;
 return `${await publishReply(addonsRoot,packet)} optional data slots`;
}
export async function runBridge({addonsRoot,base='http://127.0.0.1:17861',input}={}) {
 if(!addonsRoot)throw Error('Specify --addons with your Forever Interface/AddOns folder');
 if(base!=='http://127.0.0.1:17861')throw Error('Only the local Nib companion is supported');
 const assembler=new PageAssembler(),seen=new Set(),shutdown=new AbortController();let inflight=false,stopped=false;
 let capture;
 if(!input){capture=spawn('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',captureScript,'-ParentProcessId',String(process.pid)],{stdio:['ignore','pipe','pipe'],windowsHide:true});input=capture.stdout;capture.stderr.on('data',data=>process.stderr.write(data));}
 const lines=readline.createInterface({input});
 const stop=()=>{if(stopped)return;stopped=true;shutdown.abort();lines.close();capture?.kill();process.stdin.pause();};process.once('SIGINT',stop);process.once('SIGTERM',stop);process.once('exit',()=>capture?.kill());
 if(capture){
  process.stdin.resume();process.stdin.once('end',stop);
  const parent=Number(process.env.NIB_BRIDGE_PARENT_PID);
  if(Number.isSafeInteger(parent)&&parent>0){const timer=setInterval(()=>{try{process.kill(parent,0);}catch{stop();clearInterval(timer);}},2000);timer.unref();}
 }
 // Used reply files go back to placeholders, so a file the game has not read yet never holds an old reply.
 try{const pool=await fontPool(addonsRoot);if(pool){const reset=await resetPool(pool);console.log(`Nib reply files ready${reset?` (${reset} cleared)`:''}.`);}}catch(error){console.error('Reply files:',error.message);}
 console.log('Nib automatic mode: reading the compact game-corner signal while WoW is foreground.');
 for await(const line of lines){
  if(inflight||line.length>4000||!/^[A-Za-z0-9+/=]+$/.test(line))continue;
  let full;try{full=assembler.accept(Buffer.from(line,'base64'));}catch{continue;}if(!full||seen.has(full.packet))continue;
  const type=full.packet.slice(0,6),isTrail=type==='NIBS1:',isSetup=type==='NIBC1:';
  let request;try{if(!isTrail&&!isSetup&&type!=='NIBQ1:')continue;request=JSON.parse(Buffer.from(full.packet.slice(6),'base64').toString('utf8'));if(request.schema!==1||typeof request.requestId!=='string'||!Number.isFinite(request.capturedAt)||Math.abs(Date.now()/1000-request.capturedAt)>(isSetup?30:1800))continue;}catch{continue;}
  seen.add(full.packet);if(seen.size>64)seen.delete(seen.values().next().value);inflight=true;
  const match={schema:1,requestId:request.requestId,capturedAt:request.capturedAt};
  try {
   const heard=Date.now();
   await deliver(addonsRoot,request,0,envelope('NIBA1',match));
   console.log(`${new Date().toTimeString().slice(0,8)} Request read from the screen; receipt written in ${Date.now()-heard} ms.`);
   const status=await fetch(base+'/api/status',{signal:AbortSignal.any([shutdown.signal,AbortSignal.timeout(5000)])}).then(r=>r.json());
   if(!isTrail&&!isSetup&&(!status.configured||!status.ready))throw Error(status.provider==='gemini'?'Open Gemini setup in Nib chat and connect your key.':'The selected AI provider is unavailable.');
   const endpoint=isTrail?'/api/trail-sync':isSetup?'/api/gemini-key':'/api/ask';
   const body=isSetup?{key:await readCopiedKey(request),selectGemini:true}:{packet:full.packet};
   const response=await fetch(base+endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Nib-Token':status.csrfToken,Origin:base},body:JSON.stringify(body),signal:AbortSignal.any([shutdown.signal,AbortSignal.timeout(isTrail||isSetup?25000:125000)])});
   const result=await response.json();if(!response.ok)throw Error(result.error||'The AI connection failed.');
   const reply=isSetup?envelope('NIBK1',{...match,connected:true}):result.packet;
   if(typeof reply!=='string')throw Error('No valid reply packet returned');
   console.log(`${new Date().toTimeString().slice(0,8)} Published a matched reply to ${await deliver(addonsRoot,request,1,reply)}, ${((Date.now()-heard)/1000).toFixed(1)} s after the receipt.`);
  }catch(error){
   if(stopped)break;
   const message=String(error.message).slice(0,200);
   if(isSetup)console.error('Nib: Gemini setup failed. The reason was sent to the game.');
   else console.error('Nib:',message);
   const reply={...match,error:message,...(isTrail?{character:request.character}:{})};
   try{await deliver(addonsRoot,request,1,envelope(isTrail?'NIBP1':isSetup?'NIBK1':'NIBR1',reply));}catch(publishError){console.error('Reply delivery:',publishError.message);}
  }finally{inflight=false;}
 }
 stop();
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const index=process.argv.indexOf('--addons'),addonsRoot=index>=0?process.argv[index+1]:null;
 if(!process.argv.includes('--watch-screen')){console.error('Start with --watch-screen --addons "…/Interface/AddOns" to explicitly enable local screen transport.');process.exitCode=1;}
 else await runBridge({addonsRoot}).catch(error=>{console.error(error.message);process.exitCode=1;});
}
