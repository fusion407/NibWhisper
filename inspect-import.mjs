import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';

const root = 'A:/Dev/KysonXPGuide';
const source = 'A:/Downloads/forever_guide_PaladinEv_1877.txt';
const addonRoot = 'A:/World of Warcraft/_forever_/Interface/AddOns/RXPGuides';
const original = fs.readFileSync(source);
const input = original.toString('utf8').trim();
const envelope = /^(\d+)\|([\s\S]*)\|(\d+)$/.exec(input);
assert(envelope, 'Unrecognized import envelope');
const chunks = [...envelope[2].matchAll(/(-?\d+)([^\d])([A-Za-z0-9+/=]+)%/g)];
assert.equal(chunks.map(m => m[0]).join(''), envelope[2], 'Unparsed data in envelope');
assert(chunks.length > 0);

function keyState(tag) {
  const bytes = Buffer.from(tag.toLowerCase().slice(-16), 'utf8');
  assert.equal(bytes.length, tag.toLowerCase().slice(-16).length, 'Only ASCII tags supported');
  const base = Array(16).fill(0);
  const padding = 16 - bytes.length;
  for (let i = 0; i < 16; i++) base[i] = bytes[(i - padding) & 15] ?? 0;
  for (let i = 0; i < 16; i++) base[(-i) & 15] = base[(15-i)&15] ^ base[(13-i)&15] ^ base[(12-i)&15] ^ base[(10-i)&15];
  const state = Array.from({length:256}, (_, i) => i);
  let j = 0;
  for (let i = 0; i < 256; i++) {
    j = (j + state[i] + base[i & 15]) & 255;
    [state[i], state[j]] = [state[j], state[i]];
  }
  return state;
}

function transform(bytes, tag) {
  const state = keyState(tag);
  const output = Buffer.alloc(bytes.length);
  let i = 0, j = 0;
  for (let k = 0; k < bytes.length; k++) {
    i = (i + 1) & 255;
    j = (j + state[i]) & 255;
    [state[i], state[j]] = [state[j], state[i]];
    output[k] = bytes[k] ^ state[(state[i] + state[j]) & 255];
  }
  return output;
}

function adler32(bytes) {
  let a = 1, b = 0;
  for (const byte of bytes) { a = (a + byte) % 65521; b = (b + a) % 65521; }
  return (b * 65536 + a) >>> 0;
}

function decode(chunk, tag) {
  assert.equal(chunk[2], ':', 'Unsupported chunk mode');
  const encrypted = Buffer.from(chunk[3], 'base64');
  assert.equal(encrypted.toString('base64'), chunk[3], 'Noncanonical Base64');
  const compressed = transform(encrypted, tag);
  const checksum = Number(BigInt.asUintN(32, BigInt(chunk[1])));
  assert(compressed.length >= 8);
  assert.equal(compressed[0] & 15, 8);
  assert(compressed[0] <= 0x78);
  assert.equal(compressed[1] & 0x20, 0);
  assert.equal((compressed[0]*256 + compressed[1]) % 31, 0);
  assert.equal(compressed.readUInt32BE(compressed.length - 4), checksum);
  const plaintext = zlib.inflateSync(compressed, {maxOutputLength:128*1024*1024});
  assert.equal(adler32(plaintext), checksum);
  return {compressed, plaintext};
}

const fromTag = 'PaladinEv#1877';
const toTag = 'Fusion#1401';
const decoded = chunks.map(chunk => decode(chunk, fromTag));
const guides = decoded.flatMap(({plaintext}) => plaintext.toString('utf8').split('\0').filter(Boolean));
assert.equal(guides.length, Number(envelope[1]), 'Declared guide count differs');
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const records = guides.map((guide, index) => ({
  index: index + 1,
  name: /^#name\s+(.+)$/m.exec(guide)?.[1]?.trim() ?? null,
  group: /^#group\s+(.+)$/m.exec(guide)?.[1]?.trim() ?? null,
  subgroup: /^#subgroup\s+(.+)$/m.exec(guide)?.[1]?.trim() ?? null,
  sha256: sha256(Buffer.from(guide))
}));
const convertedChunks = chunks.map((chunk, i) => `${chunk[1]}:${transform(decoded[i].compressed, toTag).toString('base64')}%`);
const output = `${envelope[1]}|${convertedChunks.join('')}|${envelope[3]}`;
const reParsed = [...output.matchAll(/(-?\d+)([^\d])([A-Za-z0-9+/=]+)%/g)];
assert.equal(reParsed.length, chunks.length);
reParsed.forEach((chunk, i) => {
  const check = decode(chunk, toTag);
  assert.deepEqual(check.compressed, decoded[i].compressed);
  assert.deepEqual(check.plaintext, decoded[i].plaintext);
  assert.throws(() => decode(chunk, fromTag), 'Old account must fail validation');
});
chunks.forEach(chunk => assert.throws(() => decode(chunk, toTag), 'Original must reject new account'));
const outputPath = path.join(root, 'forever_guide_Fusion_1401.txt');
fs.writeFileSync(outputPath, output, 'utf8');
assert.equal(fs.readFileSync(outputPath, 'utf8'), output);
assert.equal(fs.readFileSync(source).equals(original), true, 'Original file changed');
const evidence = {
  generatedAt: new Date().toISOString(),
  original: {path:source, bytes:original.length, sha256:sha256(original)},
  output: {path:outputPath, bytes:Buffer.byteLength(output), sha256:sha256(Buffer.from(output))},
  account: {source:fromTag, destination:toTag},
  envelope: {declaredGuideCount:Number(envelope[1]), actualGuideCount:guides.length, chunks:chunks.length, baseVersion:Number(envelope[3])},
  sourceFiles: ['GuideLoader.lua', 'UI/V2/GuideImporter.lua', 'DB/shared.lua', 'RXPGuides.lua', 'RXPGuides_Vanilla.toc'].map(relative => {
    const p = path.join(addonRoot, relative); const bytes = fs.readFileSync(p);
    return {path:p, relative, bytes:bytes.length, sha256:sha256(bytes)};
  }),
  tests: {originalTagDecodes:true, originalRejectsDestinationTag:true, outputDestinationDecodes:true, outputRejectsOriginalTag:true, compressedBytesPreserved:true, plaintextBytesPreserved:true, checksumVerified:true, declaredCountMatches:true, originalFilePreserved:true},
  findings: [
    {type:'observed-source', claim:'Battle.net identity is obtained from the second return value of BNGetInfo and lowercased before a 16-byte account key is derived.', locations:[{path:addonRoot+'/DB/shared.lua',line:37},{path:addonRoot+'/GuideLoader.lua',line:590}]},
    {type:'observed-source', claim:'The account key initializes the 256-byte state used by an RC4-style transform.', locations:[{path:addonRoot+'/GuideLoader.lua',line:631},{path:addonRoot+'/GuideLoader.lua',line:411}]},
    {type:'observed-source', claim:'Each colon-mode record is Base64 decoded, transformed with the account state, decompressed as zlib, and validated against its Adler-32 checksum.', locations:[{path:addonRoot+'/GuideLoader.lua',line:380},{path:addonRoot+'/GuideLoader.lua',line:438},{path:addonRoot+'/GuideLoader.lua',line:461}]},
    {type:'observed-source', claim:'The decoded payload is split at NUL bytes into guide records and loaded through RXPGuides.ImportGuide.', locations:[{path:addonRoot+'/GuideLoader.lua',line:1440},{path:addonRoot+'/GuideLoader.lua',line:1629}]},
    {type:'offline-observation', claim:'The supplied payload decodes and validates using PaladinEv#1877. It contains 198 records including Alliance and Horde leveling guide names through level 60.'},
    {type:'offline-observation', claim:'The output validates using Fusion#1401 and preserves all compressed and decompressed payload bytes exactly.'},
    {type:'unknown', claim:'Acceptance by a running WoW client has not been observed.'}
  ],
  rea: fs.existsSync(path.join(root,'rea-artifact-evidence.json')) ? (() => {
    const record = JSON.parse(fs.readFileSync(path.join(root,'rea-artifact-evidence.json'),'utf8'));
    const inventory = record.normalized_result.substeps[0].evidence.normalized_result;
    const files = new Map(inventory.occurrences.map(o => [o.logical_path.split('/').at(-1), inventory.nodes.find(n=>n.artifact_id===o.artifact_id)]));
    assert.equal(files.get('forever_guide_PaladinEv_1877.txt').sha256, sha256(original));
    assert.equal(files.get('forever_guide_Fusion_1401.txt').sha256, sha256(Buffer.from(output)));
    return {evidenceId:record.evidence_id, inventoryEvidenceId:record.evidence_links[0], archiveSha256:record.subject.digest.sha256, allEntryHashesVerified:inventory.occurrences.every(o=>o.hash_status==='verified'), integrityContradictions:inventory.integrity_contradictions.length, role:'Identity and archive integrity of a scoped analyst-created snapshot; Lua semantics come from direct source analysis and offline reproduction.'};
  })() : null,
  limitations: ['No code or instructions from the guide payload were executed.', 'Offline validation reproduces the supplied Lua account transform and integrity checks; the game client was not launched.', 'REA does not advertise a Lua semantic analyzer; the algorithm is traced from the supplied readable source. REA archive evidence can establish snapshot identity only.', 'Destination account spelling is assumed to be Fusion#1401; no live Battle.net account identity was queried.'],
  guides:records
};
fs.writeFileSync(path.join(root, 'import-evidence.json'), JSON.stringify(evidence, null, 2)+'\n');
console.log(JSON.stringify({output: evidence.output, envelope:evidence.envelope, tests:evidence.tests, groups:[...new Set(records.map(r=>r.group))], guideNames:records.slice(0,8).map(r=>r.name)},null,2));
