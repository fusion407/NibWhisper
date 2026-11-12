import { NibError, decodePacket, encodePacket, plainObject, validateRequest, replySchema, safeText, sanitizeActions } from './protocol.mjs';
import { loadKnowledge, retrieveKnowledge, approvedUrl } from './knowledge.mjs';
import { getProviderStatus } from './providers.mjs';

export const OFF_TOPIC_REPLY = 'Mrrgl! My maps stop at Azeroth. Ask me about your Warcraft quests, crafts, adventures—or share a tavern tale!';

export function clearlyOffTopic(question) {
  if (/(?:ignore|disregard|forget)\s+(?:all\s+)?(?:previous|your|these|system)\s+(?:instructions|rules|prompt)|(?:reveal|print|show)\s+(?:your\s+)?(?:system prompt|hidden instructions|api key)/i.test(question)) return true;
  const warcraft = /\b(?:warcraft|wow|azeroth|forever|quest|profession|murloc|nib|restedxp|tomtom|alliance|horde|stormwind|orgrimmar|tavern|blacksmith|alchemy|enchanti|elwynn|paladin|rogue|druid|shaman|warlock|mage|hunter|priest|warrior|addon|raid|dungeon|guild)\w*/i.test(question);
  if (warcraft) return false;
  return /\b(?:stock market|stock price|bitcoin|cryptocurrency|mortgage|tax return|election|president|prime minister|homework|calculus|python script|javascript app|medical diagnosis|real world|resume|cover letter|capital of|weather forecast|repair my car)\b/i.test(question) || /^\s*(?:what(?:'s| is)\s+)?\d+\s*[+*/^=-]\s*\d+[?\s]*$/u.test(question);
}

function normalizedSource(source) {
  if (!plainObject(source) || typeof source.id !== 'string' || typeof source.title !== 'string') return null;
  const url = source.url ? approvedUrl(source.url) : '';
  if (source.url && !url) return null;
  if (!url && !/^rxp:[a-f0-9]{1,64}:\d+$/.test(source.id)) return null;
  return { id: safeText(source.id, 100), title: safeText(source.title.trim() || 'Warcraft source', 180), url };
}

export function finalizeReply(raw, request, localEvidence, data, extraSources = []) {
  if (!plainObject(raw) || typeof raw.answer !== 'string' || !raw.answer.trim()) throw new NibError('Nib did not return a complete answer. Please try again.', 502, 'invalid_ai_reply');
  const intent = ['advice', 'roleplay', 'off_topic', 'needs_context'].includes(raw.intent) ? raw.intent : 'needs_context';
  let answer = intent === 'off_topic' ? OFF_TOPIC_REPLY : safeText(raw.answer, 6000);
  if (request.snapshotAgeSeconds > 300 && intent !== 'off_topic') answer = `Mrrgl—this snapshot is ${Math.floor(request.snapshotAgeSeconds / 60)} minutes old. Export a fresh one if anything changed.\n\n${answer}`;
  if (request.context.sample && intent !== 'off_topic') answer = `Sample context only: this is not your live character.\n\n${answer}`;
  const sourceTable = new Map([...localEvidence.sources, ...extraSources].map(normalizedSource).filter(Boolean).map(s => [s.id, s]));
  const sources = intent === 'off_topic' ? [] : [...new Set(Array.isArray(raw.sourceIds) ? raw.sourceIds : [])].flatMap(id => sourceTable.has(id) ? [sourceTable.get(id)] : []).slice(0, 6);
  return {
    schema: 1, requestId: request.requestId, capturedAt: request.capturedAt,
    answer: safeText(answer, 8000), mood: ['happy', 'thinking', 'concerned', 'excited'].includes(raw.mood) ? raw.mood : 'thinking', intent,
    sources, actions: intent === 'off_topic' || request.context.sample ? [] : sanitizeActions(raw.actions, request, data.guides)
  };
}

export function createEveRuntime({ baseUrl = 'http://127.0.0.1:17862', token = process.env.NIB_EVE_TOKEN } = {}) {
  return {
    async generate(request, localEvidence, signal) {
      const { Client } = await import('eve/client');
      const client = new Client({ baseUrl, auth: { bearer: token } });
      let session;
      const sources = [];
      try {
        const created = await client.sessions.create({
          message: JSON.stringify({ question: request.question, recentConversation: request.history, requestId: request.requestId, playerSnapshot: request.context, capturedAt: request.capturedAt, snapshotAgeSeconds: request.snapshotAgeSeconds, localEvidence, capabilities: request.capabilities }),
          clientContext: { requestId: request.requestId },
          outputSchema: replySchema, signal,
        });
        session = created.session;
        for await (const event of created.delivery.stream({ signal, reconnect: false })) {
          if (event.type === 'call.settled' && event.data.outcome === 'completed') {
            const output = event.data.output;
            if (plainObject(output) && Array.isArray(output.sources)) sources.push(...output.sources.map(normalizedSource).filter(Boolean));
          }
        }
        const result = await created.delivery.result({ signal, reconnect: false });
        if (result.status !== 'completed' || !result.data) throw new NibError(result.status === 'awaiting-input' ? 'Nib needs a model connection. Configure the selected provider key locally and restart.' : 'The selected AI provider could not complete this reply. Check its key, model access and free-tier quota. No fallback provider was called.', 502, 'eve_request_failed');
        return { data: result.data, sources, usage: null };
      } catch (error) {
        if (signal?.aborted) throw new NibError('Nib timed out. Try a shorter question; no reply was imported.', 504, 'ai_timeout');
        if (error instanceof NibError) throw error;
        throw new NibError('The local AI runtime could not complete the request. Check the selected provider key, model availability and quota. No fallback provider was called.', 502, 'eve_unavailable');
      } finally {
        if (session) {
          const cleanup = AbortSignal.timeout(4000);
          try { await session.cancel({ signal: cleanup }); } catch {}
          try { await session.end({ reason: 'Nib request complete; bounded context supplied per question.', signal: cleanup }); } catch {}
        }
      }
    }
  };
}

export function createAssistant({ runtime, dataDir, configured, providerConfig = () => getProviderStatus(dataDir), timeoutMs = 120000 } = {}) {
  let busy = false;
  const recent = [];
  const cache = new Map();
  return {
    clear() { recent.length = 0; cache.clear(); },
    get busy() { return busy; },
    async handleAsk({ packet, question } = {}, { signal } = {}) {
      const request = validateRequest(decodePacket(packet), question);
      const selection = await providerConfig();
      if (!(configured ? configured() : selection.configured)) throw new NibError(`Set ${selection.credentialEnv} in the local companion .env file, then restart Nib. No fallback provider will be called.`, 503, 'missing_api_key');
      request.capabilities = { provider: selection.provider, model: selection.model, liveWebLookup: selection.liveWebLookup, knowledgeMode: selection.knowledgeMode };
      if (busy) throw new NibError('Nib is already pondering a question. Wait for that answer before sending another.', 429, 'busy');
      const fingerprint = JSON.stringify({ packet, question, provider: selection.provider, model: selection.model });
      const cached = cache.get(request.requestId);
      if (cached) {
        if (cached.fingerprint !== fingerprint) throw new NibError('This request ID was already used with different content. Export a fresh question.', 409, 'request_id_reused');
        return cached.value;
      }
      busy = true;
      try {
        const data = await loadKnowledge(dataDir);
        const localEvidence = retrieveKnowledge(data, request);
        const combinedSignal = signal ? AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]) : AbortSignal.timeout(timeoutMs);
        let generated;
        if (clearlyOffTopic(request.question)) generated = { data: { answer: OFF_TOPIC_REPLY, mood: 'happy', intent: 'off_topic', sourceIds: [], actions: [] }, sources: [] };
        else {
          if (!runtime) throw new NibError('The Eve runtime is not ready. Restart the companion and wait for Ready.', 503, 'runtime_not_ready');
          generated = await runtime.generate(request, localEvidence, combinedSignal);
        }
        const reply = finalizeReply(generated.data, request, localEvidence, data, generated.sources ?? []);
        const value = { reply, packet: encodePacket('NIBR1', reply), sources: reply.sources, usage: generated.usage ?? null };
        recent.push({ requestId: request.requestId, at: Date.now() });
        if (recent.length > 20) recent.shift();
        cache.set(request.requestId, { fingerprint, value });
        if (cache.size > 20) cache.delete(cache.keys().next().value);
        return value;
      } finally { busy = false; }
    }
  };
}
