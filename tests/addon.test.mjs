import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { encodePage, PAGE_SIZE } from '../tools/optical-protocol.mjs';
import { loadKnowledge, retrieveKnowledge } from '../companion/lib/knowledge.mjs';
import { finalizeReply } from '../companion/lib/assistant.mjs';
import { encodePacket } from '../companion/lib/protocol.mjs';
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const addonsRoot = path.join(root,'addon');
const addonRoot = path.join(addonsRoot,'NibWhisper');

function runLua(state, source, name, module = false) {
  const status = lauxlib.luaL_loadbuffer(state, to_luastring(source), null, to_luastring(name));
  assert.equal(status, lua.LUA_OK, status === lua.LUA_OK ? '' : to_jsstring(lua.lua_tostring(state,-1)));
  if(module){lua.lua_pushstring(state,to_luastring('NibWhisper'));lua.lua_getglobal(state,to_luastring('NibWhisper'));}
  const result = lua.lua_pcall(state,module?2:0,0,0);
  assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(state,-1)));
}

function client(){
  const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
  runLua(state,fs.readFileSync(path.join(addonRoot,'tests','wow-stub.lua'),'utf8'),'@wow-stub.lua');
  for(const name of ['NibWhisper/Protocol.lua','NibWhisper/Context.lua','NibWhisper/UI.lua','NibWhisper/Core.lua','NibWhisper_Assistant/Assistant.lua','NibWhisper_Assistant/Optical.lua']) runLua(state,fs.readFileSync(path.join(addonsRoot,name),'utf8'),'@'+name,true);
  return state;
}

test('Lua addon compiles and constructs its UI; context, UTF-8, strict packets, actions and stale slots behave correctly',()=>{
  const output=execFileSync(process.execPath,[path.join(addonRoot,'tests','run.mjs')],{cwd:root,encoding:'utf8',timeout:20000});
  assert.match(output,/tests passed/);
});

test('Lua optical frames exactly match the external JavaScript wire protocol on every page',()=>{
  const state=client();
  const packet='NIBQ1:'+Buffer.from(JSON.stringify({schema:1,question:'Mrrgl 🐟',context:'q'.repeat(6000)})).toString('base64');
  const requestId='session-utf8-42';
  const count=Math.ceil(Buffer.byteLength(packet)/PAGE_SIZE);
  for(let i=0;i<count;i++){
    lua.lua_getglobal(state,to_luastring('NibWhisper'));lua.lua_getfield(state,-1,to_luastring('Optical'));lua.lua_getfield(state,-1,to_luastring('Header'));
    lua.lua_pushstring(state,to_luastring(packet));lua.lua_pushstring(state,to_luastring(requestId));lua.lua_pushinteger(state,i);
    const status=lua.lua_pcall(state,3,1,0);
    assert.equal(status,lua.LUA_OK,status===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(state,-1)));
    assert.deepEqual(Buffer.from(lua.lua_tolstring(state,-1)),encodePage(packet,requestId,i));
    lua.lua_settop(state,0);
  }
});

test('Lua manual packet encoding is interoperable with native JSON and Base64',()=>{
  const state=client();
  runLua(state,'testPacket = NibWhisper.Protocol.EncodePacket("NIBQ1", {schema=1, requestId="test-1", capturedAt=1794333600, question="Mrrgl 🐟", history=NibWhisper.Protocol.Array(), context={quests={completedIds=NibWhisper.Protocol.Array({7,33})}}})','@interop.lua');
  lua.lua_getglobal(state,to_luastring('testPacket'));
  const packet=to_jsstring(lua.lua_tostring(state,-1));
  assert.ok(packet.startsWith('NIBQ1:'));
  const decoded=JSON.parse(Buffer.from(packet.slice(6),'base64').toString('utf8'));
  assert.equal(decoded.question,'Mrrgl 🐟');assert.deepEqual(decoded.history,[]);assert.deepEqual(decoded.context.quests.completedIds,[7,33]);
});

test('Real local guide retrieval and finalized companion citations import into Lua without a web URL',async()=>{
  const state=client();
  const data=await loadKnowledge(path.join(root,'companion','data'));
  assert.ok(data.guides.length>0,'The real local guide index must exist');
  const guide=data.guides.find(g=>g.steps?.length);
  const capturedAt=Math.floor(Date.now()/1000);
  const request={schema:1,requestId:'cross-language-local',capturedAt,question:'What is my next quest?',history:[],snapshotAgeSeconds:0,context:{player:{faction:guide.faction||'Alliance'},quests:{active:[]},restedXP:{guide:{name:guide.name,group:guide.group},currentStep:1}}};
  const evidence=retrieveKnowledge(data,request);
  const local=evidence.sources.find(s=>s.id.startsWith('rxp:')&&s.url==='');
  assert.ok(local,'Actual retrieval should return a local guide citation');
  const reply=finalizeReply({answer:'Mrrgl! Check the first step of your local route.',mood:'happy',intent:'advice',sourceIds:[local.id],actions:[]},request,evidence,data);
  assert.equal(reply.sources[0].url,'');
  runLua(state,`NibWhisper:Initialize(); NibWhisper.pending={requestId="cross-language-local",capturedAt=${capturedAt}}`,'@pending.lua');
  lua.lua_pushstring(state,to_luastring(encodePacket('NIBR1',reply)));lua.lua_setglobal(state,to_luastring('crossPacket'));
  runLua(state,'local ok, reason = NibWhisper:ImportReply(crossPacket); assert(ok, reason); assert(NibWhisper.UI.lastReply.sources[1].url == ""); assert(NibWhisper.pending == nil)','@cross-language.lua');
});
