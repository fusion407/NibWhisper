import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { collect, zip } from '../tools/package-curseforge.mjs';

test('the CurseForge package holds only what may be published, and every manifest entry is present', t => {
  const { version, entries, addons } = collect();
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.deepEqual(addons, ['NibWhisper', 'NibWhisper_Assistant'], 'the Leveling Guide is opt-in');
  const names = entries.map(entry => entry.name);
  for (const expected of ['NibWhisper/NibWhisper.toc', 'NibWhisper/Core.lua', 'NibWhisper/Textures/Nib.tga', 'NibWhisper_Assistant/NibWhisper_Assistant.toc', 'NibWhisper_Assistant/FontSlots.lua'])
    assert.ok(names.includes(expected), expected);
  for (const name of names) assert.doesNotMatch(name, /tests\/|Fonts\/|TrailData|\.mp3$|\.ttf$|\.log$|NibWhisperReply|NibWhisper_Guide/, name);

  const archive = zip(entries);
  assert.equal(archive.readUInt32LE(0), 0x04034b50, 'starts with a local file header');
  const end = archive.length - 22;
  assert.equal(archive.readUInt32LE(end), 0x06054b50); assert.equal(archive.readUInt16LE(end + 10), entries.length);
  const nameLength = archive.readUInt16LE(26), packed = archive.readUInt32LE(18);
  assert.equal(archive.toString('utf8', 30, 30 + nameLength), names[0]);
  assert.deepEqual(zlib.inflateRawSync(archive.subarray(30 + nameLength, 30 + nameLength + packed)), entries[0].data, 'the first file unpacks to its original bytes');
  assert.deepEqual(zip(entries), archive, 'the same input gives the same zip');

  const guideData = fileURLToPath(new URL('../addon/NibWhisper_Guide/TrailData.lua', import.meta.url));
  if (!fs.existsSync(guideData)) assert.throws(() => collect({ withGuide: true }), /no route data/, 'the guide cannot be packaged without its data');
  else {
    const withGuide = collect({ withGuide: true }).entries.map(entry => entry.name);
    assert.ok(withGuide.includes('NibWhisper_Guide/TrailData.lua') && withGuide.includes('NibWhisper_Guide/ThirdParty/QuestieDB-LICENSE.md'));
    assert.ok(!withGuide.some(name => /\.mp3$/.test(name)), 'game audio is never packaged');
  }
});
