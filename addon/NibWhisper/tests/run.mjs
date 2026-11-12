import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
function execute(source, name, module = false) {
  let status = lauxlib.luaL_loadbuffer(state, to_luastring(source), null, to_luastring(name));
  if (status !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  if (module) { lua.lua_pushstring(state, to_luastring('NibWhisper')); lua.lua_getglobal(state, to_luastring('NibWhisper')); }
  status = lua.lua_pcall(state, module ? 2 : 0, 0, 0);
  if (status !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
}
execute(fs.readFileSync(path.join(root,'tests','wow-stub.lua'),'utf8'),'@wow-stub.lua');
for (const module of ['NibWhisper/Protocol.lua','NibWhisper/Context.lua','NibWhisper/UI.lua','NibWhisper/Core.lua','NibWhisper_Assistant/Assistant.lua','NibWhisper_Assistant/CharacterData.lua','NibWhisper_Assistant/Optical.lua']) execute(fs.readFileSync(path.join(root,'..',module),'utf8'),'@'+module,true);
execute(fs.readFileSync(path.join(root,'tests','smoke.lua'),'utf8'),'@smoke.lua');
console.log('Nib Whisper Lua protocol, context, UI construction, reply, actions, and slot tests passed.');
