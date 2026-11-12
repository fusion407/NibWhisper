import test from 'node:test';
import assert from 'node:assert/strict';
import { createGeminiRuntime } from '../lib/gemini.mjs';

const request = { question: 'Where next?', history: [], context: {}, snapshotAgeSeconds: 0, capabilities: { model: 'gemini-3.5-flash-lite' } };
const reply = { answer: 'Mrrgl! Onward.', mood: 'happy', intent: 'advice', sourceIds: [], actions: [] };
const good = () => Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify(reply) }] } }] });
const env = { GEMINI_API_KEY: 'AQ.test_GeminiKey_for_mock_only' };

test('a briefly overloaded Gemini model is retried and the reply still arrives', async () => {
  let calls = 0;
  const fetchImpl = async () => (++calls < 3 ? Response.json({ error: { status: 'UNAVAILABLE' } }, { status: 503 }) : good());
  const gemini = createGeminiRuntime({ dataDir: 'missing-nib-test-dir', env, fetchImpl, retryDelays: [1, 1, 1] });
  const result = await gemini.generate(request, { excerpts: [], sources: [] });
  assert.equal(calls, 3);
  assert.equal(result.data.answer, reply.answer);
});

test('Gemini gives up after its retries, names the HTTP status, and never retries a rejected key or quota', async () => {
  let calls = 0;
  const busy = createGeminiRuntime({ dataDir: 'missing-nib-test-dir', env, retryDelays: [1, 1], fetchImpl: async () => { calls++; return Response.json({}, { status: 503 }); } });
  await assert.rejects(busy.generate(request, {}), error => error.code === 'gemini_unavailable' && /HTTP 503/.test(error.message));
  assert.equal(calls, 3);
  for (const [status, code] of [[403, 'gemini_access'], [429, 'gemini_quota'], [404, 'gemini_model']]) {
    calls = 0;
    const runtime = createGeminiRuntime({ dataDir: 'missing-nib-test-dir', env, retryDelays: [1, 1], fetchImpl: async () => { calls++; return Response.json({}, { status }); } });
    await assert.rejects(runtime.generate(request, {}), error => error.code === code);
    assert.equal(calls, 1, `HTTP ${status} must not be retried`);
  }
});
