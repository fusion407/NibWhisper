import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { NibError, plainObject } from './protocol.mjs';

const DATA_DIR = process.env.NIB_DATA_DIR || fileURLToPath(new URL('../data/', import.meta.url));
export const GEMINI_MODELS = [
  { id: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash-Lite · free-tier eligible' },
  { id: 'gemini-3.8-flash', label: 'Gemini 3.8 Flash · free-tier eligible' },
];
export const DEFAULT_GEMINI_MODEL = GEMINI_MODELS[0].id;

export function validateProviderSettings(value) {
  if (!plainObject(value) || Object.keys(value).some(k => !['provider', 'model'].includes(k))) throw new NibError('Choose a provider and model only. Keys belong in the local .env file.');
  const { provider, model } = value;
  if (!['gemini', 'openai'].includes(provider)) throw new NibError('Choose Gemini or OpenAI.');
  if (typeof model !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,99}$/.test(model)) throw new NibError('Enter a valid model ID, without a URL or API key.');
  if (provider === 'gemini' && !GEMINI_MODELS.some(m => m.id === model)) throw new NibError('Choose one of the Gemini free-tier-eligible models. No paid fallback is enabled.');
  if (provider === 'openai' && !/^gpt-[a-zA-Z0-9._:-]+$/.test(model)) throw new NibError('Use an OpenAI GPT model ID, such as the one configured in OPENAI_MODEL.');
  return { provider, model };
}

export async function loadProviderSettings(dataDir = DATA_DIR, env = process.env) {
  let saved;
  try { saved = JSON.parse(await fs.readFile(path.join(dataDir, 'provider-settings.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw new NibError('Provider settings are unreadable. Restore companion/data/provider-settings.json.', 500, 'provider_settings_invalid'); }
  if (saved) return validateProviderSettings(saved);
  const provider = env.NIB_AI_PROVIDER || (env.GEMINI_API_KEY || !env.OPENAI_API_KEY ? 'gemini' : 'openai');
  return validateProviderSettings({ provider, model: provider === 'gemini' ? env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL : env.OPENAI_MODEL || 'gpt-6.1-sol' });
}

export async function saveProviderSettings(value, dataDir = DATA_DIR) {
  const settings = validateProviderSettings(value);
  await fs.mkdir(dataDir, { recursive: true });
  // Only two validated non-secret fields can ever be persisted by the browser.
  const destination = path.join(dataDir, 'provider-settings.json');
  const temporary = destination + '.' + randomUUID() + '.tmp';
  try {
    await fs.writeFile(temporary, JSON.stringify(settings, null, 2) + '\n', { mode: 0o600 });
    await fs.rename(temporary, destination);
  } finally { await fs.unlink(temporary).catch(() => {}); }
  return settings;
}

export function providerStatus(settings, env = process.env) {
  const gemini = settings.provider === 'gemini';
  const credentialEnv = gemini ? 'GEMINI_API_KEY' : 'OPENAI_API_KEY';
  return {
    ...settings, providerLabel: gemini ? 'Google Gemini' : 'OpenAI', credentialEnv,
    configured: Boolean(env[credentialEnv]?.trim()), liveWebLookup: !gemini,
    freeTierEligible: gemini,
    knowledgeMode: gemini ? 'Local RestedXP guide and researched notes; live search disabled in free mode.' : 'Local guide plus on-demand cited Wowhead/Blizzard search.',
    modelChoices: gemini ? GEMINI_MODELS : [{ id: env.OPENAI_MODEL || 'gpt-6.1-sol', label: 'Configured OpenAI model · API billing applies' }],
  };
}

export async function getProviderStatus(dataDir = DATA_DIR, env = process.env) {
  return providerStatus(await loadProviderSettings(dataDir, env), env);
}
