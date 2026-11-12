// Delivers the helper's replies to WoW inside font files, so no reply-slot addons are needed.
//
// The game cannot read files, but it can measure text. Each byte of a packet becomes one glyph whose advance
// width encodes the value, and the addon recovers the bytes with FontString:GetStringWidth().
// Seven in-game trials on the Forever client established the rules this file follows:
//   - the client only reads font files that existed when it started, so a pool of placeholders is installed;
//   - a file is read from disk the first time it loads, then cached for the session, so each file is used once;
//   - a file the game tried before it was written cannot be relied on afterwards, so the game never retries one.
//     Each request gets a ladder of files; the receipt, and later a "reply ready" note, go to every rung, and the
//     game tries one fresh rung at a time. The reply itself sits after the ladder and is opened only once announced;
//   - data glyphs need a drawn outline (blank glyphs are replaced by the fallback font);
//   - a glyph measured alone reports its drawing, so the addon measures runs and subtracts a known tail.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const DATA_FIRST = 0xE000;        // Private Use Area: one new character per byte
export const DATA_LIMIT = 6400;          // glyphs available in that area
export const WIDTH_UNITS = 120;          // advance = (value + 1) * 120; the widest stays below 32768
export const PART_BYTES = 6000;          // packet bytes carried by one font
export const POOL_SIZE = 8000;           // reply files installed with the addon
export const BLOCK = 32;                 // files reserved per request
export const LADDER = 22;                // rungs at the start of a block that carry the receipt, then the "ready" note
export const MAX_PARTS = BLOCK - LADDER - 1; // reply files after the ladder
export const PLACEHOLDER = 'NIB PLACEHOLDER\n';
const MAGIC = 'NF1';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const BASE_FONT = path.join(root, 'addon', 'NibWhisper_Assistant', 'Fonts', 'Base.ttf');

const u16 = n => { const b = Buffer.alloc(2); b.writeUInt16BE(n & 0xFFFF); return b; };
const u32 = n => { const b = Buffer.alloc(4); b.writeUInt32BE(n >>> 0); return b; };
const pad4 = b => (b.length % 4 ? Buffer.concat([b, Buffer.alloc(4 - b.length % 4)]) : b);
function checksum(buffer) {
  const b = pad4(buffer); let sum = 0;
  for (let i = 0; i < b.length; i += 4) sum = (sum + b.readUInt32BE(i)) >>> 0;
  return sum;
}
function readTables(font) {
  const tables = {};
  for (let i = 0; i < font.readUInt16BE(4); i++) {
    const at = 12 + i * 16, offset = font.readUInt32BE(at + 8);
    tables[font.toString('latin1', at, at + 4)] = font.subarray(offset, offset + font.readUInt32BE(at + 12));
  }
  return tables;
}
function writeTables(tables) {
  const entries = Object.entries(tables).sort(([a], [b]) => (a < b ? -1 : 1));
  const count = entries.length, power = 2 ** Math.floor(Math.log2(count));
  const header = Buffer.concat([u32(0x00010000), u16(count), u16(power * 16), u16(Math.log2(power)), u16(count * 16 - power * 16)]);
  let position = header.length + count * 16, headAt = 0;
  const directory = [], bodies = [];
  for (const [tag, body] of entries) {
    if (tag === 'head') headAt = position;
    directory.push(Buffer.concat([Buffer.from(tag, 'latin1'), u32(checksum(body)), u32(position), u32(body.length)]));
    const padded = pad4(body); bodies.push(padded); position += padded.length;
  }
  const font = Buffer.concat([header, ...directory, ...bodies]);
  font.writeUInt32BE(0, headAt + 8);
  font.writeUInt32BE((0xB1B0AFBA - checksum(font)) >>> 0, headAt + 8);
  return font;
}
function cmapLookup(cmap) {
  let sub = null;
  for (let i = 0; i < cmap.readUInt16BE(2); i++) {
    const record = 4 + i * 8, offset = cmap.readUInt32BE(record + 4);
    if (cmap.readUInt16BE(record) === 3 && cmap.readUInt16BE(record + 2) === 1 && cmap.readUInt16BE(offset) === 4) sub = cmap.subarray(offset);
  }
  if (!sub) throw new Error('The font has no Unicode BMP character map.');
  const segments = sub.readUInt16BE(6) / 2, ends = 14, starts = ends + segments * 2 + 2, deltas = starts + segments * 2, offsets = deltas + segments * 2;
  return code => {
    for (let s = 0; s < segments; s++) {
      const end = sub.readUInt16BE(ends + s * 2), start = sub.readUInt16BE(starts + s * 2);
      if (code > end) continue;
      if (code < start) return 0;
      const rangeOffset = sub.readUInt16BE(offsets + s * 2), delta = sub.readUInt16BE(deltas + s * 2);
      if (rangeOffset === 0) return (code + delta) & 0xFFFF;
      const glyph = sub.readUInt16BE(offsets + s * 2 + rangeOffset + (code - start) * 2);
      return glyph ? (glyph + delta) & 0xFFFF : 0;
    }
    return 0;
  };
}

/** The pieces of the base font every data font reuses. Parsed once per helper run. */
export function prepareBase(base) {
  const t = readTables(base);
  const long = t.head.readInt16BE(50) === 1;
  const start = g => (long ? t.loca.readUInt32BE(g * 4) : t.loca.readUInt16BE(g * 2) * 2);
  const outline = g => t.glyf.subarray(start(g), start(g + 1));
  const metrics = t.hhea.readUInt16BE(34);
  const keep = g => ({ data: outline(g), advance: t.hmtx.readUInt16BE(Math.min(g, metrics - 1) * 4), bearing: g < metrics ? t.hmtx.readInt16BE(g * 4 + 2) : 0 });
  const lookup = cmapLookup(t.cmap), letterA = lookup(65), block = lookup(0x2588);
  if (!letterA || outline(letterA).readInt16BE(0) < 0 || !block || outline(block).readInt16BE(0) < 0) throw new Error('The base font needs plain A and full-block glyphs.');
  const kept = {};
  for (const tag of ['OS/2', 'cvt ', 'fpgm', 'prep', 'gasp', 'name']) if (t[tag]) kept[tag] = t[tag];
  return { tables: t, kept, fixed: [keep(0), keep(letterA)], ink: outline(block) };
}

/** One font carrying up to DATA_LIMIT - 258 bytes: 256 calibration glyphs, a two-byte length, then the bytes. */
export function dataFont(prepared, bytes) {
  const data = Buffer.from(bytes);
  const values = Buffer.concat([Buffer.from(Array.from({ length: 256 }, (_, i) => i)), u16(data.length), data]);
  if (values.length > DATA_LIMIT) throw new Error(`One font carries ${DATA_LIMIT - 258} bytes; got ${data.length}.`);
  const glyphs = [...prepared.fixed, ...Array.from(values, value => ({ data: prepared.ink, advance: (value + 1) * WIDTH_UNITS, bearing: 0 }))];
  const loca = Buffer.alloc((glyphs.length + 1) * 4), hmtx = Buffer.alloc(glyphs.length * 4);
  let offset = 0;
  glyphs.forEach((g, i) => { loca.writeUInt32BE(offset, i * 4); offset += g.data.length; hmtx.writeUInt16BE(g.advance, i * 4); hmtx.writeInt16BE(g.bearing, i * 4 + 2); });
  loca.writeUInt32BE(offset, glyphs.length * 4);
  const t = prepared.tables;
  const head = Buffer.from(t.head); head.writeInt16BE(1, 50);
  const hhea = Buffer.from(t.hhea); hhea.writeUInt16BE(glyphs.length, 34); hhea.writeUInt16BE(Math.max(hhea.readUInt16BE(10), 256 * WIDTH_UNITS), 10);
  const maxp = Buffer.from(t.maxp); maxp.writeUInt16BE(glyphs.length, 4);
  const post = Buffer.from(t.post.subarray(0, 32)); post.writeUInt32BE(0x00030000, 0); post.writeUInt32BE(0, 12);
  // Character map: "A" is glyph 1, the data characters are glyphs 2 onward.
  const last = DATA_FIRST + values.length - 1;
  const sub = Buffer.concat([u16(4), u16(40), u16(0), u16(6), u16(4), u16(1), u16(2),
    u16(65), u16(last), u16(0xFFFF), u16(0), u16(65), u16(DATA_FIRST), u16(0xFFFF), u16(1 - 65), u16(2 - DATA_FIRST), u16(1), u16(0), u16(0), u16(0)]);
  const cmap = Buffer.concat([u16(0), u16(2), u16(0), u16(3), u32(20), u16(3), u16(1), u32(20), sub]);
  return writeTables({ ...prepared.kept, cmap, glyf: Buffer.concat(glyphs.map(g => g.data)), head, hhea, hmtx, loca, maxp, post });
}

/** Reads a data font back the way a text engine would: character map, then advance widths. Used by tests. */
export function readDataFont(font) {
  const t = readTables(font), lookup = cmapLookup(t.cmap);
  const value = index => { const g = lookup(DATA_FIRST + index); if (!g) throw new Error('Missing data glyph.'); return t.hmtx.readUInt16BE(g * 4) / WIDTH_UNITS - 1; };
  for (let i = 0; i < 256; i++) if (value(i) !== i) throw new Error('Calibration glyphs are wrong.');
  const length = value(256) * 256 + value(257);
  return Buffer.from(Array.from({ length }, (_, i) => value(258 + i)));
}

export function adler32(buffer) {
  let a = 1, b = 0;
  for (const byte of buffer) { a = (a + byte) % 65521; b = (b + a) % 65521; }
  return b * 65536 + a;
}
/** Splits a packet into parts. Each part is "NF1", its number, the part count, a checksum, then a slice of the packet. */
export function packetParts(packet) {
  const bytes = Buffer.from(packet, 'latin1');
  const count = Math.max(1, Math.ceil(bytes.length / PART_BYTES));
  if (count > MAX_PARTS) throw new Error('The reply is too large for the font transport.');
  return Array.from({ length: count }, (_, i) => {
    const chunk = bytes.subarray(i * PART_BYTES, (i + 1) * PART_BYTES);
    return Buffer.concat([Buffer.from(MAGIC), Buffer.from([i + 1, count]), u32(adler32(chunk)), chunk]);
  });
}

export const slotFile = index => `R${String(index).padStart(4, '0')}.ttf`;
export const validSlot = index => Number.isInteger(index) && index >= 1 && index <= POOL_SIZE - BLOCK + 1;

/** The reply-file folder inside the installed assistant addon, or null when this install has no pool. */
export async function fontPool(addonsRoot) {
  const dir = path.join(path.resolve(addonsRoot), 'NibWhisper_Assistant', 'Fonts');
  const stat = await fs.lstat(path.join(dir, slotFile(1))).catch(() => null);
  if (!stat?.isFile() || stat.isSymbolicLink()) return null;
  const real = await fs.realpath(dir);
  if (path.dirname(path.dirname(real)).toLowerCase() !== (await fs.realpath(path.resolve(addonsRoot))).toLowerCase()) throw new Error('Reply file folder escaped the AddOns directory.');
  return dir;
}

async function replace(dir, index, contents) {
  const target = path.join(dir, slotFile(index));
  const stat = await fs.lstat(target).catch(() => null);
  if (!stat?.isFile() || stat.isSymbolicLink()) throw new Error('A reply file is missing. Run Install-Nib.ps1 and fully restart WoW.');
  // Written in place, exactly as in the trials that proved this transport: the same file the game knew at startup
  // gets new contents. Swapping a renamed copy in was tried and the game stopped reading the files.
  // A write the game happens to catch half way costs one rung of the ladder, nothing more.
  for (let attempt = 0; ; attempt++) {
    try { await fs.writeFile(target, contents); return; }
    catch (error) {
      // Windows can refuse for the instant the game has the file open.
      if (attempt >= 20) throw new Error(`Reply file ${slotFile(index)} stayed busy: ${error.code ?? error.message}`);
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
}

let cachedBase = null;
export async function loadBase(file = BASE_FONT) {
  if (!cachedBase || cachedBase.file !== file) cachedBase = { file, prepared: prepareBase(await fs.readFile(file)) };
  return cachedBase.prepared;
}

/** The "reply ready" note: part number 0, the number of reply files, and the checksum of no data. */
const readyNote = count => Buffer.concat([Buffer.from(MAGIC), Buffer.from([0, count]), u32(adler32(Buffer.alloc(0)))]);

/**
 * Writes a packet into the request's block. Stage 0 is the receipt, copied to every rung of the ladder.
 * Stage 1 is the reply: its parts go after the ladder, and only then is every rung rewritten to say they are ready.
 */
export async function publishFont(dir, slot, stage, packet, prepared) {
  if (!validSlot(slot)) throw new Error('Invalid reply file number.');
  if (stage !== 0 && stage !== 1) throw new Error('Invalid reply stage.');
  if (!/^(?:NIBR1|NIBP1|NIBA1|NIBK1):[A-Za-z0-9+/=]+$/.test(packet)) throw new Error('Invalid data-only reply packet');
  const parts = packetParts(packet);
  prepared ??= await loadBase();
  if (stage === 0) {
    if (parts.length !== 1) throw new Error('A receipt must fit one file.');
    const receipt = dataFont(prepared, parts[0]);
    for (let rung = 0; rung < LADDER; rung++) await replace(dir, slot + rung, receipt);
    return 1;
  }
  for (let i = 0; i < parts.length; i++) await replace(dir, slot + LADDER + i, dataFont(prepared, parts[i]));
  const note = dataFont(prepared, readyNote(parts.length));
  for (let rung = 0; rung < LADDER; rung++) await replace(dir, slot + rung, note);
  return parts.length;
}

/** Puts every used reply file back to a placeholder. Run when the helper starts. */
export async function resetPool(dir) {
  let reset = 0;
  for (const name of await fs.readdir(dir)) {
    if (/^R\d{4}\.ttf\.\d+\.tmp$/.test(name)) { await fs.unlink(path.join(dir, name)).catch(() => {}); continue; } // left by an interrupted write
    if (!/^R\d{4}\.ttf$/.test(name)) continue;
    const file = path.join(dir, name), stat = await fs.lstat(file).catch(() => null);
    if (stat?.isFile() && !stat.isSymbolicLink() && stat.size !== PLACEHOLDER.length) { await fs.writeFile(file, PLACEHOLDER).then(() => reset++, () => {}); }
  }
  return reset;
}
