import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { generateText } from 'ai';
import { selectNibModel } from '../agent/lib/provider-model.ts';
import { loadProviderSettings, saveProviderSettings, providerStatus, validateProviderSettings } from '../lib/providers.mjs';
import { createAssistant } from '../lib/assistant.mjs';
import { createHttpServer } from '../lib/http.mjs';
import { encodePacket, sampleRequest, validateQuestion } from '../lib/protocol.mjs';
import { searchGameKnowledge } from '../lib/lookup.mjs';

async function temp(t){const dir=await mkdtemp(path.join(os.tmpdir(),'nib-providers-'));t.after(async()=>{assert.equal(path.dirname(path.resolve(dir)),path.resolve(os.tmpdir()));assert(path.basename(dir).startsWith('nib-providers-'));await rm(dir,{recursive:true,force:true});});return dir;}

test('provider defaults, migration and persisted model selection are deterministic',async t=>{
 const dir=await temp(t);
 assert.deepEqual(await loadProviderSettings(dir,{}),{provider:'gemini',model:'gemini-3.5-flash-lite'});
 assert.equal((await loadProviderSettings(dir,{OPENAI_API_KEY:'only-existing-key'})).provider,'openai');
 await saveProviderSettings({provider:'gemini',model:'gemini-3.8-flash'},dir);
 assert.equal((await loadProviderSettings(dir,{OPENAI_API_KEY:'retained-key'})).model,'gemini-3.8-flash');
 const publicValue=providerStatus(await loadProviderSettings(dir),{GEMINI_API_KEY:'private-test-secret'});
 assert.equal(publicValue.configured,true);assert.equal(publicValue.liveWebLookup,false);assert(!JSON.stringify(publicValue).includes('private-test-secret'));
 await assert.rejects(saveProviderSettings({provider:'gemini',model:'gemini-4-carbon'},dir),/free-tier/);
 await assert.rejects(saveProviderSettings({provider:'gemini',model:'gemini-3.8-flash',apiKey:'not-accepted'},dir),/Keys belong/);
 assert.throws(()=>validateProviderSettings({provider:'openai',model:'https://other.test/api'}));
});

test('Gemini free mode never calls OpenAI or live web lookup even if its key exists',async()=>{
 let calls=0;
 const result=await searchGameKnowledge('Forever copper mining',{provider:'gemini',apiKey:'unused-openai-key',fetchImpl:async()=>{calls++;throw Error('Must not fetch');}});
 assert.equal(calls,0);assert.equal(result.kind,'live-search-unavailable');assert.deepEqual(result.sources,[]);
 const assistant=createAssistant({providerConfig:async()=>providerStatus({provider:'gemini',model:'gemini-3.5-flash-lite'},{OPENAI_API_KEY:'available-openai-key'}),runtime:{generate:async()=>{calls++;}}});
 await assert.rejects(assistant.handleAsk({packet:encodePacket('NIBQ1',sampleRequest())}),error=>error.code==='missing_api_key'&&error.message.includes('GEMINI_API_KEY'));
 assert.equal(calls,0);
});

test('official Gemini SDK sends a direct Google request with private header and bounded output',async()=>{
 const calls=[];
 const selection=selectNibModel({provider:'gemini',model:'gemini-3.5-flash-lite'},{GEMINI_API_KEY:'fake-google-key',OPENAI_API_KEY:'never-use-this'},async(url,options)=>{
  calls.push({url:String(url),headers:new Headers(options.headers),body:JSON.parse(options.body)});
  return new Response(JSON.stringify({candidates:[{content:{role:'model',parts:[{text:'Mrrgl! Your map is ready.'}]},finishReason:'STOP'}],usageMetadata:{promptTokenCount:10,candidatesTokenCount:8,totalTokenCount:18}}),{headers:{'content-type':'application/json'}});
 });
 const result=await generateText({model:selection.model,prompt:'Say hello to an adventurer in Azeroth.',maxRetries:0});
 assert.equal(result.text,'Mrrgl! Your map is ready.');assert.equal(calls.length,1);
 assert.equal(new URL(calls[0].url).hostname,'generativelanguage.googleapis.com');
 assert(calls[0].url.includes('gemini-3.5-flash-lite'));assert.equal(calls[0].headers.get('x-goog-api-key'),'fake-google-key');
 assert(!JSON.stringify(calls[0].body).includes('fake-google-key'));assert(!calls[0].url.includes('fake-google-key'));
 assert.equal(calls[0].body.generationConfig.maxOutputTokens,2400);assert(!calls[0].body.tools);
});

test('Google quota exhaustion stays on Gemini without retries or paid fallback',async()=>{
 let calls=0;
 const {model}=selectNibModel({provider:'gemini',model:'gemini-3.5-flash-lite'},{GEMINI_API_KEY:'fake-key'},async url=>{
  calls++;assert.equal(new URL(url).hostname,'generativelanguage.googleapis.com');
  return new Response(JSON.stringify({error:{code:429,message:'Quota exceeded',status:'RESOURCE_EXHAUSTED'}}),{status:429,headers:{'content-type':'application/json'}});
 });
 await assert.rejects(generateText({model,prompt:'Help my WoW character.',maxRetries:0}),/Quota exceeded/);assert.equal(calls,1);
 assert.throws(()=>selectNibModel({provider:'gemini',model:'gemini-3.5-flash-lite'},{OPENAI_API_KEY:'present-but-never-fallback'}),/GEMINI_API_KEY/);
});

test('model settings require same-origin token; only non-secret validated settings persist',async t=>{
 const dir=await temp(t),assistant=createAssistant({configured:()=>false});
 const app=createHttpServer({assistant,port:0,dataDir:dir});await app.listen();t.after(()=>new Promise(resolve=>app.server.close(resolve)));
 const base=`http://127.0.0.1:${app.server.address().port}`,status=await(await fetch(base+'/api/status')).json();
 const body=JSON.stringify({provider:'gemini',model:'gemini-3.5-flash-lite'}),headers={Origin:base,'Content-Type':'application/json','X-Nib-Token':status.csrfToken};
 assert.equal((await fetch(base+'/api/settings',{method:'POST',body,headers:{Origin:base,'Content-Type':'application/json'}})).status,403);
 const response=await fetch(base+'/api/settings',{method:'POST',body,headers});assert.equal(response.status,200);
 assert.equal((await response.json()).settings.credentialEnv,'GEMINI_API_KEY');
 assert.deepEqual(JSON.parse(await readFile(path.join(dir,'provider-settings.json'),'utf8')),{provider:'gemini',model:'gemini-3.5-flash-lite'});
 assert.equal((await fetch(base+'/api/settings',{method:'POST',headers,body:JSON.stringify({provider:'gemini',model:'gemini-3.5-flash-lite',apiKey:'secret'})})).status,400);
 assert.throws(()=>validateQuestion('AIza'+'a'.repeat(35)),/API key/);
});
