import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { BASE_FONT, BLOCK, LADDER, MAX_PARTS, PART_BYTES, PLACEHOLDER, POOL_SIZE, WIDTH_UNITS, adler32, dataFont, fontPool, loadBase, packetParts, publishFont, readDataFont, resetPool, slotFile, validSlot } from '../tools/font-transport.mjs';
import { deliver } from '../tools/optical-bridge.mjs';
import { encodePacket } from '../companion/lib/protocol.mjs';
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = fileURLToPath(new URL('../addon/', import.meta.url));

async function tempAddOns(t, { pool = 4 * BLOCK, slots = false } = {}) {
  const addons = path.join(await fsp.mkdtemp(path.join(os.tmpdir(), 'nib-font-')), 'AddOns');
  t.after(() => fsp.rm(path.dirname(addons), { recursive: true, force: true }));
  await fsp.mkdir(path.join(addons, 'NibWhisper'), { recursive: true });
  const dir = path.join(addons, 'NibWhisper_Assistant', 'Fonts');
  await fsp.mkdir(dir, { recursive: true });
  for (let i = 1; i <= pool; i++) await fsp.writeFile(path.join(dir, slotFile(i)), PLACEHOLDER);
  if (slots) await fsp.mkdir(path.join(addons, 'NibWhisperReply001'));
  return { addons, dir };
}

test('a data font carries a packet part exactly, and parts are numbered, checksummed and size-limited', async () => {
  const prepared = await loadBase();
  const bytes = Buffer.from(Array.from({ length: 6000 }, (_, i) => (i * 7 + 3) & 255));
  const font = dataFont(prepared, bytes);
  assert.deepEqual(readDataFont(font), bytes);
  assert.ok(font.length < 300000, `one full part is ${font.length} bytes`);
  let sum = 0; for (let i = 0; i < font.length; i += 4) sum = (sum + font.readUInt32BE(i)) >>> 0;
  assert.equal(sum, 0xB1B0AFBA, 'whole-file checksum');
  assert.ok(256 * WIDTH_UNITS < 32768, 'the widest advance stays a positive signed number');
  assert.throws(() => dataFont(prepared, Buffer.alloc(6143)), /carries/);

  const packet = 'NIBR1:' + 'QUJD'.repeat(3500); // 14,006 bytes: three parts
  const parts = packetParts(packet);
  assert.equal(parts.length, 3);
  parts.forEach((part, i) => {
    assert.equal(part.toString('latin1', 0, 3), 'NF1'); assert.equal(part[3], i + 1); assert.equal(part[4], 3);
    assert.equal(part.readUInt32BE(5), adler32(part.subarray(9)));
  });
  assert.equal(Buffer.concat(parts.map(p => p.subarray(9))).toString('latin1'), packet);
  assert.equal(packetParts('NIBA1:QQ==').length, 1);
  assert.equal(MAX_PARTS, 9);
  assert.throws(() => packetParts('NIBR1:' + 'A'.repeat(PART_BYTES * MAX_PARTS)), /too large/);
  assert.ok(validSlot(1) && validSlot(POOL_SIZE - BLOCK + 1) && !validSlot(0) && !validSlot(POOL_SIZE) && !validSlot(1.5) && !validSlot('1'));
  assert.ok(fs.existsSync(BASE_FONT));
});

test('the helper fills the ladder with the receipt, then the reply files, then the ready note', async t => {
  const { addons, dir } = await tempAddOns(t);
  assert.equal(await fontPool(addons), dir);
  const size = async i => (await fsp.stat(path.join(dir, slotFile(i)))).size;
  const part = async i => readDataFont(await fsp.readFile(path.join(dir, slotFile(i))));
  const block = BLOCK + 1; // the second block
  assert.equal(await publishFont(dir, block, 0, 'NIBA1:QQ=='), 1);
  for (const rung of [0, 1, LADDER - 1]) assert.equal((await part(block + rung)).subarray(9).toString('latin1'), 'NIBA1:QQ==', 'every rung holds the receipt');
  assert.equal(await size(block + LADDER), PLACEHOLDER.length, 'nothing after the ladder yet');
  assert.equal(await size(block - 1), PLACEHOLDER.length, 'the block before is untouched');

  assert.equal(await publishFont(dir, block, 1, 'NIBR1:' + 'QUJD'.repeat(2000)), 2);
  assert.equal((await part(block + LADDER))[3], 1); assert.equal((await part(block + LADDER + 1))[3], 2);
  assert.equal(await size(block + LADDER + 2), PLACEHOLDER.length);
  for (const rung of [0, LADDER - 1]) {
    const note = await part(block + rung);
    assert.equal(note.length, 9); assert.equal(note[3], 0, 'part number 0 marks the ready note'); assert.equal(note[4], 2, 'it names two reply files');
    assert.equal(note.readUInt32BE(5), 1, 'checksum of no data');
  }
  assert.equal(await size(block + BLOCK), PLACEHOLDER.length, 'the next block is untouched');
  await assert.rejects(publishFont(dir, block, 1, 'NIBX1:QQ=='), /Invalid data-only/);
  await assert.rejects(publishFont(dir, block, 1, 'NIBR1:QQ==\nprint(1)'), /Invalid data-only/);
  await assert.rejects(publishFont(dir, block, 0, 'NIBA1:' + 'QUJD'.repeat(2000)), /must fit one file/);
  await assert.rejects(publishFont(dir, block, 2, 'NIBA1:QQ=='), /Invalid reply stage/);
  await assert.rejects(publishFont(dir, 0, 0, 'NIBA1:QQ=='), /Invalid reply file/);
  await assert.rejects(publishFont(dir, 4 * BLOCK + 1, 0, 'NIBA1:QQ=='), /missing/, 'a file that was never installed is refused, not created');
  assert.deepEqual((await fsp.readdir(dir)).filter(name => name.endsWith('.tmp')), [], 'no temporary files are left behind');
  await fsp.writeFile(path.join(dir, 'R0005.ttf.123.tmp'), 'left by an interrupted write');
  assert.equal(await resetPool(dir), LADDER + 2);
  assert.ok(!fs.existsSync(path.join(dir, 'R0005.ttf.123.tmp')));
  assert.equal(await size(block), PLACEHOLDER.length);

  assert.match(await deliver(addons, { replyFont: 1 }, 0, 'NIBA1:QQ=='), /1 reply file\(s\) in block 1/);
  await assert.rejects(deliver(addons, {}, 0, 'NIBA1:QQ=='), /reply modules are not installed/, 'no file number and no slots');
  const legacy = await tempAddOns(t, { pool: 0, slots: true });
  assert.equal(await fontPool(legacy.addons), null);
  assert.match(await deliver(legacy.addons, { replyFont: 1 }, 0, 'NIBA1:QQ=='), /1 optional data slots/);
});

test('end to end: a question asked in the game is answered through reply files it never tries twice', async t => {
  const pool = 4 * BLOCK;
  const { addons, dir } = await tempAddOns(t, { pool });
  const l = lauxlib.luaL_newstate(); lualib.luaL_openlibs(l);
  t.after(() => lua.lua_close(l));
  const run = (source, name = '@step', module = false) => {
    let status = lauxlib.luaL_loadbuffer(l, to_luastring(source), null, to_luastring(name)); if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(l, -1)));
    if (module) { lua.lua_pushstring(l, to_luastring('NibWhisper')); lua.lua_getglobal(l, to_luastring('NibWhisper')); }
    status = lua.lua_pcall(l, module ? 2 : 0, 0, 0); if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(l, -1)));
  };
  const read = name => { lua.lua_getglobal(l, to_luastring(name)); const value = to_jsstring(lua.lua_tostring(l, -1)); lua.lua_settop(l, 0); return value; };
  run(fs.readFileSync(path.join(root, 'NibWhisper/tests/wow-stub.lua'), 'utf8'), '@stub');
  for (const name of ['NibWhisper/Protocol.lua', 'NibWhisper/Context.lua', 'NibWhisper/UI.lua', 'NibWhisper/Core.lua', 'NibWhisper_Assistant/Assistant.lua', 'NibWhisper_Assistant/Optical.lua', 'NibWhisper_Assistant/FontSlots.lua'])
    run(fs.readFileSync(path.join(root, name), 'utf8'), '@' + name, true);
  // Copies what is on disk into the pretend game: a real font becomes its glyph widths, a placeholder stays unloadable.
  const sync = async () => {
    const entries = [];
    for (let i = 1; i <= pool; i++) {
      const file = await fsp.readFile(path.join(dir, slotFile(i)));
      if (file.length === PLACEHOLDER.length) continue;
      const bytes = readDataFont(file);
      const values = [...Array.from({ length: 256 }, (_, v) => v), bytes.length >> 8, bytes.length & 255, ...bytes];
      entries.push(`[${i}]={${values.map(v => (v + 1) * WIDTH_UNITS / 32).join(',')}}`);
    }
    run(`diskFiles={${entries.join(',')}}`);
  };
  // Each tick is 0.3 s of game time.
  const pump = (seconds = 3) => run(`for _=1,${Math.ceil(seconds / 0.3)} do clock=clock+0.3;NibWhisper.eventFrame.scripts.OnUpdate(nil,0.3) end`);
  run(`
  diskFiles={};fontTried={};fontCache={}
  local template=getmetatable(CreateFrame()).__index
  -- The pretend game is stricter than the real one is known to be: whatever a file held the first time it was
  -- tried is what it holds for the rest of the session, placeholder or font.
  function template:SetFont(path)
    if fontMissing then error('Invalid font asset ('..path..'): file not found') end
    local index=tonumber(path:match('R(%d%d%d%d)%.ttf$'))
    if not index then return true end -- the base font that shows the folder is installed
    if fontBusy then error('FontString:SetFont(): Invalid font asset ('..path..'): file not found') end
    if not fontTried[index] then fontTried[index]=true;fontCache[index]=diskFiles[index] or false end
    self.font=fontCache[index] or nil
    return self.font~=nil
  end
  -- Measures like the game: a lone character reports its drawing, a run reports the pen, snapped to screen pixels.
  function template:GetStringWidth()
    local s,i,pen,ink=self.text or '',1,0,0
    while i<=#s do
      local a,b,c=s:byte(i,i+2);local code
      if a<0x80 then code=a;i=i+1 elseif a<0xE0 then code=(a-0xC0)*64+(b-0x80);i=i+2 else code=(a-0xE0)*4096+(b-0x80)*64+(c-0x80);i=i+3 end
      ink=pen+36
      pen=pen+(code==65 and 37.5 or (self.font and self.font[code-0xE000+1]) or 45)
    end
    return math.floor(math.max(pen,ink)*0.64+0.5)/0.64
  end
  function tried() local n=0;for _ in pairs(fontTried) do n=n+1 end;return n end
  -- The pretend game also refuses what the trials never covered: a text object that has already been pointed at one
  -- reply file cannot load another.
  local realSetFont=template.SetFont
  function template:SetFont(path)
    local index=path:match('R(%d%d%d%d)%.ttf$')
    if index then if self.boundTo and self.boundTo~=index then return false end;self.boundTo=index end
    return realSetFont(self,path)
  end
  local started=5000
  function debugprofilestop() return started end
  A=NibWhisper;A:Initialize()
  A:SetChatMode('automatic')
  assert(A:Ask('How should I level?'))
  assert(A.pending.font==1 and A.db.fontNext==${BLOCK + 1} and A.db.fontUsed==${BLOCK},'the first request reserves the first block')
  requestPacket=A.pending.packet
  `);
  const request = JSON.parse(Buffer.from(read('requestPacket').slice(6), 'base64').toString('utf8'));
  assert.equal(request.replyFont, 1);
  pump(3);
  run(`assert(tried()==0,'the helper needs a moment, so nothing is tried in the first seconds')`);
  pump(8);
  run(`assert(A.pending and not A.pending.received and not A.pending.manualOnly and tried()>=2 and tried()<=4,'rungs are tried one at a time, a few seconds apart: '..tried())
  assert(#slotLoads==0,'no reply-slot addon is loaded while reply files are in use')
  -- A file error while waiting, as when the helper is replacing a file, must not end the request.
  fontBusy=true`);
  pump(3);
  run(`fontBusy=nil;assert(A.pending and A.pending.font==1 and not A.pending.manualOnly,'a busy file is passed over')`);
  const match = { schema: 1, requestId: request.requestId, capturedAt: request.capturedAt };
  await deliver(addons, request, 0, encodePacket('NIBA1', match));
  await sync(); pump(6);
  run(`assert(A.pending and A.pending.received,'the receipt arrives on a rung the game had not tried before')
  receiptRungs=tried()`);
  const answer = 'Mrrgl! ' + 'Follow the road north past the abbey and mind the kobolds. '.repeat(110);
  const reply = encodePacket('NIBR1', { ...match, answer, mood: 'happy', intent: 'advice', sources: [], actions: [] });
  assert.ok(Buffer.byteLength(reply) > PART_BYTES, 'the reply needs more than one file');
  await deliver(addons, request, 1, reply);
  await sync(); pump(12);
  run(`assert(A.pending==nil,'the reply was imported')
  assert(A.UI.lastReply.answer==${JSON.stringify(answer)},'the answer arrives intact across two files')
  assert(fontTried[${LADDER + 1}] and fontTried[${LADDER + 2}] and not fontTried[${LADDER + 3}],'only the announced reply files are opened')
  assert(tried()<=receiptRungs+5,'few rungs are used once the helper answers')
  -- The next request uses a fresh block, and a damaged file is refused rather than imported.
  assert(A:Ask('And after that?') and A.pending.font==${BLOCK + 1})
  secondPacket=A.pending.packet`);
  const second = JSON.parse(Buffer.from(read('secondPacket').slice(6), 'base64').toString('utf8'));
  assert.equal(second.replyFont, BLOCK + 1);
  const secondMatch = { schema: 1, requestId: second.requestId, capturedAt: second.capturedAt };
  await deliver(addons, second, 0, encodePacket('NIBA1', secondMatch));
  await deliver(addons, second, 1, encodePacket('NIBR1', { ...secondMatch, answer: 'Head to Goldshire.', mood: 'happy', intent: 'advice', sources: [], actions: [] }));
  await sync();
  run(`diskFiles[${BLOCK + 1 + LADDER}][300]=diskFiles[${BLOCK + 1 + LADDER}][300]+3.75`); // one byte off by one: only the checksum can notice
  pump(12);
  run(`assert(A.pending and A.pending.manualOnly and A.UI.status:GetText():find('could not read the reply file',1,true),A.UI.status:GetText())
  A:CancelPending()`);
  // An old receipt left in a block is recognised and refused.
  await deliver(addons, { replyFont: 2 * BLOCK + 1 }, 0, encodePacket('NIBA1', { schema: 1, requestId: 'someone-else', capturedAt: request.capturedAt }));
  await sync();
  run(`assert(A:Ask('Third question?') and A.pending.font==${2 * BLOCK + 1})`);
  pump(8);
  run(`assert(A.pending.manualOnly and A.UI.status:GetText():find('old reply file',1,true),A.UI.status:GetText())
  A:CancelPending()
  -- Reload: the counter carries on. Restart: every file is readable again, and the numbering continues round the pool.
  A.FontSlots:Logout();A.FontSlots.checked=nil
  assert(A.FontSlots:Reserve()==${3 * BLOCK + 1} and A.db.fontUsed==${4 * BLOCK},'after a reload the session count is kept')
  A.FontSlots:Logout();A.FontSlots.checked=nil
  function debugprofilestop() return 12 end
  assert(A.FontSlots:Reserve()==${4 * BLOCK + 1} and A.db.fontUsed==${BLOCK},'after a restart the count starts again')
  A.db.fontNext=${POOL_SIZE - 5};assert(A.FontSlots:Reserve()==1,'numbering wraps to the start of the pool')
  A.db.fontUsed=${POOL_SIZE - 5};assert(A.FontSlots:Reserve()==nil and A.FontSlots.spent,'a spent pool reserves nothing')
  A.db.fontUsed=0;A.db.fontNext=${3 * BLOCK + 1};A.FontSlots.spent=nil
  -- A request that times out says what the reader saw.
  assert(A:Ask('Timeout question?') and A.pending.font==${3 * BLOCK + 1})
  `);
  pump(150);
  run(`assert(A.pending.manualOnly and A.UI.status:GetText():find('No response from the Nib helper',1,true) and A.UI.status:GetText():find(' s from file ${3 * BLOCK + 1}, 0 readable',1,true),A.UI.status:GetText())
  assert(not (A.UI.copy and A.UI.copy:IsShown()),'a failed request no longer opens a window by itself')
  A.Test.Slash('filelog')
  local report=A.UI.copy.box.edit:GetText()
  assert(report:find('Nib reply files, block ${3 * BLOCK + 1}, asked at ',1,true) and report:find('rung file ${3 * BLOCK + 1}: empty (SetFont returned false)',1,true),report)
  A.UI.copy:Hide()
  A:CancelPending()
  -- Without the files installed, decided at login, requests use the reply-slot addons instead.
  A.FontSlots.present=nil;fontMissing=true
  assert(A:Ask('Fallback question?') and A.pending.font==nil and A.FontSlots.present==false)
  requestPacket=A.pending.packet`);
  assert.equal(JSON.parse(Buffer.from(read('requestPacket').slice(6), 'base64').toString('utf8')).replyFont, undefined, 'the helper is not told to use reply files');
  pump(8);
  run(`assert(#slotLoads>=1,'missing reply files fall back to reply slots')`);
});
