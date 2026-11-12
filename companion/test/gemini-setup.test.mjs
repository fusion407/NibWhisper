import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, unlink, rmdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createGeminiRuntime, getGeminiKey } from '../lib/gemini.mjs';
import { createAssistant } from '../lib/assistant.mjs';
import { createHttpServer } from '../lib/http.mjs';
import { getProviderStatus } from '../lib/providers.mjs';
import { decodePacket, encodePacket, sampleRequest } from '../lib/protocol.mjs';

test('Gemini setup checks the key, protects it, and unlocks a matched AI reply without restarting', async t => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'nib-key-test-'));
  const storedKey = path.join(dataDir, 'gemini-key.local');
  t.after(async () => { await unlink(storedKey).catch(() => {}); await rmdir(dataDir); });
  const key = 'AQ.test_GeminiKey_for_mock_only';
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    if (options.headers['x-goog-api-key'] !== key) return Response.json({}, { status: 403 });
    if (!options.body) return Response.json({ name: 'models/gemini-3.5-flash-lite' });
    return Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify({
      answer: 'Mrrgl! Check the next objective in your quest log.',
      mood: 'happy', intent: 'advice', sourceIds: [], actions: [],
    }) }] } }] });
  };
  const env = {};
  const gemini = createGeminiRuntime({ dataDir, env, fetchImpl });
  const providerConfig = async () => ({ ...await getProviderStatus(dataDir, env), configured: Boolean(await getGeminiKey(dataDir, env)) });
  const assistant = createAssistant({ runtime: gemini, providerConfig });
  const app = createHttpServer({ assistant, gemini, port: 0, status: providerConfig });
  const { port } = await app.listen();
  t.after(() => app.server.close());
  const base = `http://127.0.0.1:${port}`;
  const status = async () => (await fetch(`${base}/api/status`)).json();
  const post = (endpoint, body, headers = {}) => fetch(`${base}${endpoint}`, {
    method: 'POST', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json', ...headers },
  });
  const initial = await status();
  assert.equal(initial.configured, false);
  assert.equal((await post('/api/gemini-key', { key }, { Origin: base })).status, 403);
  const authorized = { Origin: base, 'X-Nib-Token': initial.csrfToken };
  assert.equal((await post('/api/gemini-key', { key: 'invalid_credential_for_mock' }, authorized)).status, 502);
  assert.equal(await getGeminiKey(dataDir, env), '');
  const saved = await post('/api/gemini-key', { key }, authorized);
  assert.deepEqual(await saved.json(), { ok: true });
  assert.equal((await readFile(storedKey, 'utf8')).trim(), key);
  const connected = await status();
  assert.equal(connected.configured, true);
  assert(!JSON.stringify(connected).includes(key));
  const request = sampleRequest();
  const response = await post('/api/ask', { packet: encodePacket('NIBQ1', request) }, authorized);
  const result = await response.json();
  assert.equal(response.status, 200, JSON.stringify(result));
  assert.equal(decodePacket(result.packet, 'NIBR1').requestId, request.requestId);
  assert.match(result.reply.answer, /Check the next objective/);
  assert.equal(calls.length, 3);
  const generated = calls[2];
  assert.match(generated.url, /^https:\/\/generativelanguage.googleapis.com\/v1beta\/models\/.+:generateContent$/);
  assert.equal(JSON.parse(generated.options.body).generationConfig.responseMimeType, 'application/json');
  assert(!generated.options.body.includes(key));
});
