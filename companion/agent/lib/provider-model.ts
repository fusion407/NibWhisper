import { createGoogle } from '@ai-sdk/google';
import { openai } from 'eve/models/openai';
import { wrapLanguageModel } from 'ai';

export function selectNibModel(settings: { provider: string; model: string }, env = process.env, fetchImpl?: typeof fetch) {
  const gemini = settings.provider === 'gemini';
  const apiKey = gemini ? env.GEMINI_API_KEY : env.OPENAI_API_KEY;
  if (!apiKey?.trim()) throw new Error(`Configure ${gemini ? 'GEMINI_API_KEY' : 'OPENAI_API_KEY'} locally. No other provider will be used.`);
  // Direct provider instances: never route Gemini through OpenAI or AI Gateway.
  const native = gemini ? createGoogle({ apiKey, fetch: fetchImpl })(settings.model) : openai(settings.model);
  return {
    model: wrapLanguageModel({ model: native, middleware: { transformParams: async ({ params }) => ({ ...params, maxOutputTokens: 2400 }) } }),
    reasoning: 'low' as const,
    modelContextWindowTokens: 128000,
    modelOptions: gemini ? {} : { providerOptions: { openai: { store: false } } },
  };
}
