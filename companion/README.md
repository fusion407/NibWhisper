# Nib companion

The local AI service for Nib, your Warcraft murloc companion. See the [main project instructions](../README.md) for addon installation and [backend notes](BACKEND.md) for the packet API, safeguards, retrieval and verification details.

Requires Node.js 24 or newer. In this folder:

1. Run `npm ci`.
2. Copy `.env.example` to `.env` and set your private `GEMINI_API_KEY` from Google AI Studio. OpenAI is a separate optional provider.
3. Run `npm start`, then open `http://127.0.0.1:17861`.

The server supervises a genuine eve runtime privately on port 17862. Only the authored Warcraft lookup tool is enabled; default shell, file access, broad web tools, delegation and development extensions are disabled. No model request is sent until you ask a question. Without a key, the UI and labeled sample remain available and AI requests show setup instructions.

Use the page's provider/model controls to switch. Gemini free mode uses the local guide and researched notes; live search is disabled and it never falls back to OpenAI or a paid model. Free-tier access depends on Google's current model/project quotas, and Google may use free-tier content to improve products. The key stays local; provider settings contain only the provider name and model ID.

`npm test`, `npm run typecheck` and `npm run build` verify the implementation. `node test/eve-smoke.mjs` performs a bounded runtime health/auth/tool-inventory check without sending any model request. Live AI answers and in-game behavior still require the user's account and client.

Do not share `.env`, `.eve`, or the private `data/guide-index.json` file. The UI supports manual packets; optional screen-code transport is enabled separately in the main project instructions.
