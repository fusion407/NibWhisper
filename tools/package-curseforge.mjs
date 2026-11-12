// Builds the zip to upload to CurseForge: dist/NibWhisper-<version>.zip, with one folder per addon at the top level.
//
//   node tools/package-curseforge.mjs                 core + AI Assistant
//   node tools/package-curseforge.mjs --with-guide    also the Leveling Guide, including its route data
//
// What is deliberately left out:
//   - tests, the helper, and everything else outside addon/;
//   - the reply-file fonts. They only matter with the local helper, which CurseForge does not distribute;
//   - sound files in the guide's Sounds folder, which are not this project's to redistribute;
//   - the Leveling Guide, unless --with-guide is given. Its route data (TrailData.lua) is built from RestedXP
//     guides. Only pass --with-guide if you have the right to publish that data.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const secret = /AIza[0-9A-Za-z_-]{30,}|AQ\.[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9_-]{30,}|ghp_[A-Za-z0-9]{30,}/;

function filesOf(dir, base = dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? filesOf(full, base) : [path.relative(base, full).split(path.sep).join('/')];
  });
}
const excluded = file => /^tests\//.test(file) || /^Fonts\//.test(file) || /^Sounds\/.*\.(mp3|ogg|wav)$/i.test(file) || /\.(tmp|log)$/i.test(file);

function zip(entries) {
  const parts = [], central = [];
  let offset = 0;
  for (const { name, data } of entries) {
    const nameBytes = Buffer.from(name), packed = zlib.deflateRawSync(data, { level: 9 }), crc = zlib.crc32(data);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0); header.writeUInt16LE(20, 4); header.writeUInt16LE(0x0800, 6); header.writeUInt16LE(8, 8);
    header.writeUInt16LE(0, 10); header.writeUInt16LE(0x21, 12); // fixed timestamp: the same input always gives the same zip
    header.writeUInt32LE(crc, 14); header.writeUInt32LE(packed.length, 18); header.writeUInt32LE(data.length, 22); header.writeUInt16LE(nameBytes.length, 26);
    const record = Buffer.alloc(46);
    record.writeUInt32LE(0x02014b50, 0); record.writeUInt16LE(20, 4); record.writeUInt16LE(20, 6); record.writeUInt16LE(0x0800, 8); record.writeUInt16LE(8, 10);
    record.writeUInt16LE(0, 12); record.writeUInt16LE(0x21, 14);
    record.writeUInt32LE(crc, 16); record.writeUInt32LE(packed.length, 20); record.writeUInt32LE(data.length, 24); record.writeUInt16LE(nameBytes.length, 28);
    record.writeUInt32LE(offset, 42);
    parts.push(header, nameBytes, packed); central.push(record, nameBytes);
    offset += header.length + nameBytes.length + packed.length;
  }
  const directory = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, directory, end]);
}

/** Collects the files for the package and checks them. Returns { version, entries, addons }. */
export function collect({ withGuide = false, addonRoot = path.join(root, 'addon') } = {}) {
  const addons = ['NibWhisper', 'NibWhisper_Assistant', ...(withGuide ? ['NibWhisper_Guide'] : [])];
  const entries = [], versions = new Set();
  for (const addon of addons) {
    const dir = path.join(addonRoot, addon);
    const files = filesOf(dir).filter(file => !excluded(file)).sort();
    const toc = fs.readFileSync(path.join(dir, `${addon}.toc`), 'utf8');
    versions.add(/^## Version:\s*(\S+)/m.exec(toc)?.[1]);
    for (const line of toc.split(/\r?\n/)) {
      const listed = line.trim().replaceAll('\\', '/');
      if (!listed || listed.startsWith('#')) continue;
      if (!files.includes(listed)) {
        throw new Error(listed === 'TrailData.lua'
          ? 'The Leveling Guide has no route data here. Build it with tools/build-trail.mjs before using --with-guide.'
          : `${addon}.toc lists ${listed}, which is not in the package.`);
      }
    }
    for (const file of files) {
      const data = fs.readFileSync(path.join(dir, file));
      if (secret.test(data.toString('latin1'))) throw new Error(`${addon}/${file} looks like it contains an API key. Nothing was packaged.`);
      entries.push({ name: `${addon}/${file}`, data });
    }
  }
  if (versions.size !== 1 || versions.has(undefined)) throw new Error(`The addon manifests disagree on the version: ${[...versions].join(', ')}`);
  return { version: [...versions][0], entries, addons };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const withGuide = process.argv.includes('--with-guide');
  const { version, entries, addons } = collect({ withGuide });
  const out = path.join(root, 'dist', `NibWhisper-${version}.zip`);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, zip(entries));
  console.log(`${path.relative(root, out)}: ${addons.join(', ')} (${entries.length} files, ${Math.round(fs.statSync(out).size / 1024)} KB)`);
  if (!withGuide) console.log('The Leveling Guide is not included. See "Publishing to CurseForge" in README.md.');
}
export { zip };
