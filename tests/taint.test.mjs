import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = fileURLToPath(new URL('../addon/', import.meta.url));

// In WoW, any global an addon assigns becomes "tainted". If that global belongs to the game, the game's own code
// is tainted when it reads it, and protected actions (raid markers, targeting, casting from macros) are blocked
// and blamed on the addon. Nib may only assign globals that are its own.
const allowed = new Set(['NibWhisperDB', 'NibWhisperCharDB', 'SLASH_NIBWHISPER1', 'SLASH_NIBWHISPER2']);
const files = ['NibWhisper/Protocol.lua', 'NibWhisper/Context.lua', 'NibWhisper/UI.lua', 'NibWhisper/Core.lua',
  'NibWhisper_Assistant/Assistant.lua', 'NibWhisper_Assistant/CharacterData.lua', 'NibWhisper_Assistant/Optical.lua', 'NibWhisper_Assistant/FontSlots.lua',
  'NibWhisper_Guide/TrailData.lua', 'NibWhisper_Guide/QuestLinks.lua', 'NibWhisper_Guide/Trail.lua', 'NibWhisper_Guide/TrailSync.lua']
  .filter(name => fs.existsSync(path.join(root, name)));

test('Nib never assigns a global that belongs to the game', () => {
  const l = lauxlib.luaL_newstate(); lualib.luaL_openlibs(l);
  const run = (source, name) => {
    let status = lauxlib.luaL_loadbuffer(l, to_luastring(source), null, to_luastring(name)); if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(l, -1)));
    status = lua.lua_pcall(l, 0, 0, 0); if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(l, -1)));
  };
  run(fs.readFileSync(path.join(root, 'NibWhisper/tests/wow-stub.lua'), 'utf8'), '@stub');
  run('NibWhisper=nil;nibSources={};nibNames={}', '@setup');
  files.forEach((name, i) => {
    lua.lua_getglobal(l, to_luastring('nibSources'));
    lua.lua_pushstring(l, to_luastring(fs.readFileSync(path.join(root, name), 'utf8'))); lua.lua_rawseti(l, -2, i + 1);
    lua.lua_getglobal(l, to_luastring('nibNames'));
    lua.lua_pushstring(l, to_luastring(name)); lua.lua_rawseti(l, -2, i + 1);
    lua.lua_settop(l, 0);
  });
  run(`
  -- Every global the addon reads comes from the real table; every global it writes is recorded.
  local real=_G
  written={}
  local env=setmetatable({}, {__index=real, __newindex=function(_,k,v) written[k]=true; rawset(real,k,v) end})
  for i, source in ipairs(nibSources) do
    local chunk=assert(load(source,'@'..nibNames[i],'t',env))
    chunk('NibWhisper', real.NibWhisper)
  end
  -- Exercise the code paths that run during play, so writes inside functions are recorded too.
  local A=real.NibWhisper
  A.eventFrame.scripts.OnEvent(nil,'PLAYER_LOGIN')
  A:Ask('What quests am I on?')
  A.UI:ShowOptions()
  if A.Trail then A.Trail:Open(); A.Trail:Tick(true); A.Trail:ShowLibrary(); A.Trail:ShowSync() end
  real.SlashCmdList.NIBWHISPER('help')
  A.eventFrame.scripts.OnUpdate(nil,0.3)
  local names={}
  for k in pairs(written) do names[#names+1]=k end
  table.sort(names)
  writtenNames=table.concat(names,',')
  `, '@exercise');
  lua.lua_getglobal(l, to_luastring('writtenNames'));
  const written = to_jsstring(lua.lua_tostring(l, -1)).split(',').filter(Boolean);
  lua.lua_close(l);
  const foreign = written.filter(name => !allowed.has(name));
  assert.deepEqual(foreign, [], `Nib assigns these globals, which taints them: ${foreign.join(', ')}`);
  assert.ok(written.includes('NibWhisperDB'), 'the check really saw the addon running');
});
