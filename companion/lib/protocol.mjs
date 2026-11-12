import { TextDecoder } from 'node:util';

export const MAX_PACKET_BYTES = 128 * 1024;
export const MAX_QUESTION = 2000;
const decoder = new TextDecoder('utf-8', { fatal: true });

export class NibError extends Error {
  constructor(message, status = 400, code = 'invalid_request') {
    super(message);
    this.name = 'NibError'; this.status = status; this.code = code;
  }
}

export function encodePacket(prefix, value) {
  const packet = `${prefix}:${Buffer.from(JSON.stringify(value), 'utf8').toString('base64')}`;
  if (Buffer.byteLength(packet) > MAX_PACKET_BYTES) throw new NibError('Packet exceeds 128 KiB.', 413, 'packet_too_large');
  return packet;
}

export function decodePacket(packet, expectedPrefix = 'NIBQ1') {
  if (typeof packet !== 'string') throw new NibError('Paste a NIBQ1 request exported from Nib.');
  packet = packet.trim();
  if (Buffer.byteLength(packet) > MAX_PACKET_BYTES) throw new NibError('Packet exceeds 128 KiB.', 413, 'packet_too_large');
  const match = new RegExp(`^${expectedPrefix}:([A-Za-z0-9+/]+={0,2})$`).exec(packet);
  if (!match || match[1].length % 4 !== 0) throw new NibError(`Invalid ${expectedPrefix} packet. Copy the complete packet.`);
  const bytes = Buffer.from(match[1], 'base64');
  if (bytes.toString('base64') !== match[1]) throw new NibError('Packet Base64 is damaged. Copy it again.');
  try { return JSON.parse(decoder.decode(bytes)); }
  catch { throw new NibError('Packet contains invalid UTF-8 or JSON. Export a fresh snapshot.'); }
}

export function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function validateQuestion(question) {
  if (typeof question !== 'string' || !question.trim()) throw new NibError('Ask Nib a Warcraft question or share an in-world tale.');
  if (/AIza[\w-]{25,}|sk-[\w-]{20,}/.test(question)) throw new NibError('That looks like an API key. Keep keys in companion/.env, never in a chat message.');
  if (Buffer.byteLength(question, 'utf8') > MAX_QUESTION) throw new NibError('Please keep your question under 2,000 UTF-8 bytes.');
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/u.test(question)) throw new NibError('Question contains unsupported control characters.');
  return question.trim();
}

export function validateRequest(value, overrideQuestion) {
  if (!plainObject(value) || value.schema !== 1) throw new NibError('Unsupported request schema. Update the Nib addon.');
  if (typeof value.requestId !== 'string' || !/^[A-Za-z0-9_.:-]{1,100}$/.test(value.requestId)) throw new NibError('Missing or invalid request ID. Export a fresh request.');
  const capturedAt = value.capturedAt;
  const epoch = typeof capturedAt === 'number' ? capturedAt * 1000 : (typeof capturedAt === 'string' ? Date.parse(capturedAt) : NaN);
  if (!Number.isFinite(epoch) || epoch < Date.UTC(2020, 0, 1) || epoch > Date.now() + 300000) throw new NibError('Snapshot timestamp is invalid. Check your clock and export again.');
  if (!plainObject(value.context)) throw new NibError('The request has no player context. Export it from the addon.');
  const history = Array.isArray(value.history) ? value.history.slice(-10).filter(m => plainObject(m) && ['user', 'assistant'].includes(m.role) && typeof m.text === 'string').map(m => ({ role: m.role, text: m.text.slice(0, 2000) })) : [];
  return { schema: 1, requestId: value.requestId, capturedAt, question: validateQuestion(overrideQuestion ?? value.question), context: value.context, history, snapshotAgeSeconds: Math.max(0, Math.floor((Date.now() - epoch) / 1000)) };
}

export const replySchema = {
  type: 'object', additionalProperties: false,
  properties: {
    answer: { type: 'string', maxLength: 6000 },
    mood: { type: 'string', enum: ['happy', 'thinking', 'concerned', 'excited'] },
    intent: { type: 'string', enum: ['advice', 'roleplay', 'off_topic', 'needs_context'] },
    sourceIds: { type: 'array', maxItems: 6, items: { type: 'string', maxLength: 200 } },
    actions: { type: 'array', maxItems: 3, items: {
      type: 'object', additionalProperties: false,
      properties: {
        type: { type: 'string', enum: ['waypoint', 'quest', 'guide', 'trail'] },
        mapID: { type: ['integer', 'null'] }, x: { type: ['number', 'null'] }, y: { type: ['number', 'null'] },
        title: { type: 'string', minLength: 1, maxLength: 100 }, questID: { type: ['integer', 'null'] },
        group: { type: ['string', 'null'], maxLength: 160 }, name: { type: ['string', 'null'], maxLength: 160 }
      }, required: ['type', 'mapID', 'x', 'y', 'title', 'questID', 'group', 'name']
    } }
  }, required: ['answer', 'mood', 'intent', 'sourceIds', 'actions']
};

export function safeText(text, limit = 6000) {
  const cleaned = String(text ?? '').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/gu, '');
  if (Buffer.byteLength(cleaned, 'utf8') <= limit) return cleaned;
  let bytes = 0, output = '';
  for (const point of cleaned) {
    const size = Buffer.byteLength(point, 'utf8');
    if (bytes + size > limit) break;
    output += point; bytes += size;
  }
  return output;
}

export function sanitizeActions(actions, request, guides = []) {
  if (!Array.isArray(actions)) return [];
  const faction = request.context.player?.faction;
  return actions.slice(0, 3).flatMap(action => {
    if (!plainObject(action)) return [];
    const defaultTitle = action.type === 'quest' ? `Open quest ${action.questID}` : action.type === 'waypoint' ? 'Place waypoint' : 'Select guide';
    const title = safeText(typeof action.title === 'string' && action.title.trim() ? action.title.trim() : defaultTitle, 100);
    if (action.type === 'waypoint' && Number.isInteger(action.mapID) && action.mapID > 0 && action.mapID <= 10000 && Number.isFinite(action.x) && action.x >= 0 && action.x <= 100 && Number.isFinite(action.y) && action.y >= 0 && action.y <= 100) {
      return [{ type: 'waypoint', mapID: action.mapID, x: action.x, y: action.y, title }];
    }
    if (action.type === 'quest' && Number.isInteger(action.questID) && action.questID > 0 && action.questID <= 10000000) return [{ type: 'quest', questID: action.questID, title }];
    if (['guide','trail'].includes(action.type) && typeof action.group === 'string' && typeof action.name === 'string' && Buffer.byteLength(action.group) <= 160 && Buffer.byteLength(action.name) <= 160 && guides.some(g => g.group === action.group && g.name === action.name && (!['alliance', 'horde'].includes(String(g.faction).toLowerCase()) || !faction || String(g.faction).toLowerCase() === String(faction).toLowerCase()))) return [{ type: action.type, group: action.group, name: action.name, title }];
    return [];
  });
}

export const sampleRequest = () => ({
  schema: 1, requestId: `sample-${Date.now()}`, capturedAt: Math.floor(Date.now() / 1000), question: 'Mrrgl! What can you help me with?',
  context: { sample: true, client: { edition: 'forever', build: 'sample — not live game state' }, player: { name: 'Sample adventurer', level: 12, class: 'WARRIOR', faction: 'Alliance', zone: 'Elwynn Forest' }, quests: { active: [], completedIds: [], completionCoverage: 'unknown — sample only' }, professions: [], addons: [], restedXP: { available: false } }, history: []
});
