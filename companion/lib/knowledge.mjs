import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const DATA_DIR = process.env.NIB_DATA_DIR || fileURLToPath(new URL('../data/', import.meta.url));
const ALLOWED_DOMAINS = ['wowhead.com', 'news.blizzard.com', 'worldofwarcraft.blizzard.com'];
export { ALLOWED_DOMAINS };

export function approvedUrl(value) {
  try { const url = new URL(value); return url.protocol === 'https:' && Buffer.byteLength(url.href) <= 2048 && !url.username && !url.password && ALLOWED_DOMAINS.some(d => url.hostname === d || url.hostname.endsWith(`.${d}`)) ? url.href : null; }
  catch { return null; }
}

export async function loadKnowledge(dataDir = DATA_DIR) {
  const read = async name => {
    try { return JSON.parse(await fs.readFile(path.join(dataDir, name), 'utf8')); }
    catch (error) { if (error.code === 'ENOENT') return null; throw new Error(`Could not read ${name}; rebuild the local knowledge index.`); }
  };
  const [index, knowledge, starters] = await Promise.all([read('guide-index.json'), read('knowledge.json'), read('trail-starters.json')]);
  return { guides: [...(Array.isArray(index?.guides) ? index.guides : []), ...(Array.isArray(starters?.guides) ? starters.guides : [])], source: index?.source ?? null, entries: Array.isArray(knowledge?.entries) ? knowledge.entries : [], edition: index?.edition ?? knowledge?.edition ?? 'forever', asOf: knowledge?.asOf ?? null };
}

const words = value => [...new Set(String(value ?? '').toLowerCase().match(/[a-z][a-z0-9'-]{2,}|\d{2,}/g) ?? [])].filter(w => !['the','and','for','with','what','where','this','that','have','from','which','quest','quests','help','please','about','your'].includes(w));

export function retrieveKnowledge(data, request, maxChars = 12000) {
  const { context } = request;
  const faction = String(context.player?.faction ?? '').toLowerCase();
  const rxp = context.nibTrail ?? context.restedXP ?? {};
  const guideName = String(rxp.guideName ?? rxp.name ?? rxp.guide?.name ?? '');
  const guideGroup = String(rxp.guideGroup ?? rxp.group ?? rxp.guide?.group ?? '');
  const liveSteps = Array.isArray(rxp.steps) ? rxp.steps : [];
  const liveIds = new Set(liveSteps.flatMap(s => Array.isArray(s.questIds) ? s.questIds.filter(Number.isInteger) : []));
  const liveTerms = words(liveSteps.flatMap(s => (s.elements ?? []).map(e => e.text ?? '')).join(' ')).slice(0, 100);
  const active = Array.isArray(context.quests?.active) ? context.quests.active : [];
  const activeIds = new Set(active.flatMap(q => Number.isInteger(q.id ?? q.questID) ? [q.id ?? q.questID] : []));
  const terms = words(request.question);
  const candidates = [];
  for (const guide of data.guides) {
    if (['alliance', 'horde'].includes(String(guide.faction).toLowerCase()) && faction && String(guide.faction).toLowerCase() !== faction) continue;
    const isCurrent = guide.name === guideName && (!guideGroup || guide.group === guideGroup);
    const header = String(guide.header ?? '');
    for (const item of guide.steps ?? []) {
      const body = String(item.text ?? '');
      const title = `${guide.name} step ${item.index}`;
      const haystack = `${title} ${body}`.toLowerCase();
      let score = terms.reduce((sum, term) => sum + (haystack.includes(term) ? 3 : 0), 0);
      if ((item.questIds ?? []).some(id => activeIds.has(id))) score += 12;
      if (isCurrent) {
        score += 12;
        if (context.nibTrail && guide.id === rxp.guide?.id && Math.abs(item.index-rxp.currentStep)<=2) score += 120 - 15*Math.abs(item.index-rxp.currentStep);
        if ((item.questIds ?? []).some(id => liveIds.has(id))) score += 35;
        score += liveTerms.reduce((sum, term) => sum + (haystack.includes(term) ? 6 : 0), 0);
      }
      if (score > 2) candidates.push({ score, type: 'guide', id: `rxp:${guide.id}:${item.index}`, title: `RestedXP local: ${title}`, url: '', text: `${header.slice(0, 1300)}\n${body}`, group: guide.group, name: guide.name, conditions: item.conditions ?? [], step: item.index });
    }
  }
  for (const entry of data.entries) {
    const haystack = `${entry.title} ${(entry.tags ?? []).join(' ')} ${entry.text}`.toLowerCase();
    const score = terms.reduce((sum, term) => sum + (haystack.includes(term) ? 4 : 0), 0);
    if (score > 0) candidates.push({ score, type: 'seed', id: `seed:${entry.id}`, title: String(entry.title), url: approvedUrl(entry.sources?.[0]?.url) ?? '', text: String(entry.text), sources: (entry.sources ?? []).map(s => approvedUrl(s.url)).filter(Boolean) });
  }
  candidates.sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
  let remaining = maxChars;
  const excerpts = [];
  for (const item of candidates.slice(0, 9)) {
    if (remaining < 300) break;
    const text = item.text.slice(0, Math.min(remaining, 2500));
    remaining -= text.length;
    excerpts.push({ ...item, text });
  }
  return { excerpts, sources: excerpts.map(({ id, title, url, type }) => ({ id, title, url, type })), conditionsEvaluated: false, guideCount: data.guides.length, caution: 'Prioritize the current playerSnapshot.nibTrail step and its verified point when present. Nib Trail uses raw chapter indices; RestedXP may filter them. Local excerpts preserve conditions and may include manual instructions. Verify eligibility and completion against the live snapshot.' };
}
