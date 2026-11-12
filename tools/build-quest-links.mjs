import fs from 'node:fs';
import assert from 'node:assert/strict';

const [sourcePath, revision, itemPath] = process.argv.slice(2);
assert(sourcePath && /^[a-f0-9]{40}$/.test(revision || ''), 'Pass a QuestieDB Forever source file and its pinned commit.');
const source = fs.readFileSync(sourcePath, 'utf8');
const routeFiles = ['companion/data/guide-index.json', 'companion/data/trail-starters.json'];
const used = new Set();
const itemIDs = new Set();
for (const file of routeFiles) {
  for (const {steps} of JSON.parse(fs.readFileSync(file, 'utf8')).guides) {
    for (const {text} of steps) {
      for (const match of text.matchAll(/^\s*\.(?:accept|turnin|complete)\s+-?(\d+)/gmi)) used.add(Number(match[1]));
      for (const match of text.matchAll(/^\s*\.collect\s+\d+\s*,\s*\d+\s*,\s*(\d+)/gmi)) used.add(Number(match[1]));
      for (const match of text.matchAll(/^\s*\.(?:collect|use|destroy)\s+(\d+)/gmi)) itemIDs.add(Number(match[1]));
    }
  }
}

// Split the literal columns without evaluating any code from the downloaded file.
function fields(row) {
  const result = [];
  let start = 0, depth = 0, quote = '';
  for (let i = 0; i < row.length; i++) {
    const c = row[i];
    if (quote) {
      if (c === '\\') i++;
      else if (c === quote) quote = '';
    } else if (c === '"' || c === "'") quote = c;
    else if (c === '{') depth++;
    else if (c === '}') depth--;
    else if (c === ',' && depth === 0) { result.push(row.slice(start, i).trim()); start = i + 1; }
  }
  assert.equal(depth, 0, 'Unbalanced quest row');
  assert(!quote, 'Unterminated quest text');
  return [...result, row.slice(start).trim()];
}

function ids(value) {
  if (!value || value === 'nil') return [];
  if (!/^\{\s*\d+(?:\s*,\s*\d+)*\s*,?\s*\}$/.test(value)) return null;
  return [...value.matchAll(/\d+/g)].map(m => Number(m[0])).filter(Boolean);
}

const names = new Map();
const links = new Map();
const luaString = s => '"' + s.replace(/[\x00-\x1f\\"]/g, c => c === '"' || c === '\\' ? '\\' + c : '\\' + String(c.charCodeAt(0)).padStart(3, '0')) + '"';
const rows = source.matchAll(/^\[(\d+)\]\s*=\s*\{(.*)\},?\r?$/gm);
for (const [, key, row] of rows) {
  const id = Number(key);
  const data = fields(row);
  try { if (data[0]?.startsWith('"')) names.set(id, JSON.parse(data[0])); } catch {}
  if (!used.has(id)) continue;
  const all = ids(data[11]), any = ids(data[12]);
  const active = /^\d+$/.test(data[24]) ? Number(data[24]) : 0;
  const started = /^\d+$/.test(data[33]) ? Number(data[33]) : 0;
  if (all && any && (all.length || any.length || active || started)) links.set(id, { all, any, active, started });
}
assert.deepEqual(links.get(7)?.any, [783], 'Northshire prerequisite check');
const nameIDs = new Set([...used].filter(id => names.has(id)));
for (const {all, any, active, started} of links.values()) for (const id of [...all, ...any, active, started]) if (names.has(id)) nameIDs.add(id);
const items = new Map();
if (itemPath) {
  for (const [, idText, single, double] of fs.readFileSync(itemPath,'utf8').matchAll(/^\[(\d+)\]\s*=\s*\{(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"),/gm)) {
    const id = Number(idText);
    if (!itemIDs.has(id)) continue;
    items.set(id,(single ?? double).replace(/\\(['"\\])/g,'$1'));
  }
}
const data = [
  '-- Generated from QuestieDB Forever data, GPL-3.0. See ThirdParty/QuestieDB-LICENSE.md.',
  '-- Source revision: ' + revision,
  'local addon = _G.NibWhisper', 'if not addon then return end', 'addon.QuestLinks = {', 'names = {',
  ...[...nameIDs].sort((a,b) => a-b).map(id => `[${id}]=${luaString(names.get(id))},`),
  '}, items = {',
  ...[...items].map(([id, name]) => `[${id}]=${luaString(name)},`),
  '}, requirements = {',
  ...[...links].map(([id, r]) => `[${id}]={all={${r.all}},any={${r.any}},active=${r.active},started=${r.started}},`),
  '}}', '',
];
fs.writeFileSync('addon/NibWhisper_Guide/QuestLinks.lua', data.join('\n'));
console.log(`${links.size} quests with prerequisites, ${nameIDs.size} quest names, ${items.size} item names`);
