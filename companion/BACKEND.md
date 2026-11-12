# Nib local AI companion

Requires Node.js 24 or newer. This is a genuine eve agent with dynamically selected direct Google Gemini or OpenAI providers. The Node server supervises a private eve runtime on `127.0.0.1:17862` and serves the companion UI and packet API on `127.0.0.1:17861`.

Install dependencies with `npm ci`. Copy `.env.example` to `.env`, set `GEMINI_API_KEY` from Google AI Studio, and run `npm start`. The default Gemini model is `gemini-3.5-flash-lite`. Provider/model controls save only non-secret fields to `data/provider-settings.json`; the dynamic model resolver reads these before model calls. An existing OpenAI-only environment stays OpenAI unless a saved selection overrides it. API keys are read at startup, so key changes require a restart. Missing selected-provider credentials return an actionable HTTP 503 without calling another provider.

Gemini models offered by the selector have free-tier input/output access listed in Google's current [pricing](https://ai.google.dev/gemini-api/docs/pricing); availability, project verification, quotas and billing are the account owner's responsibility. Google may use free-tier data to improve products. The app cannot infer billing eligibility from the key. Gemini search grounding is disabled because it is not free on these models; Gemini mode never invokes OpenAI or a paid fallback. Explicit OpenAI selection uses its own API credentials and billing. No Codex or browser-session credentials are reused.

## Local API

- `GET /api/status`: includes `{ok,csrfToken,provider,providerLabel,model,modelChoices,credentialEnv,configured,ready,liveWebLookup,knowledgeMode,freeTierEligible,runtime,guideCount,seedCount,busy,setupMessage,opticalEnabled,opticalError}`. A ready runtime is not proof that a provider call will succeed. No keys are returned.
- `POST /api/settings`: `{provider,model}` with the same CSRF/Origin headers as Ask. Validates a small provider/model allowlist, rejects secret/unknown fields, and rejects switching during a request. It saves the selection atomically and clears the request cache. Model changes do not require reinstalling the addon.
- `GET /api/sample`: `{sample:true,request,packet}`. Explicitly fictional sample character; never presented as live game state.
- `POST /api/ask`: JSON `{packet,question?}`. Include `X-Nib-Token` from status and exact `Origin: http://127.0.0.1:17861`. Returns `{reply,packet,sources,usage}`. Errors return `{error,code}` and a non-success HTTP status.
- `POST /api/clear`: JSON `{}` with the same headers; clears bounded in-process request deduplication. Addon chat history, eve local workflow records, and provider retention are separate.

Requests use `NIBQ1:` plus canonical Base64 UTF-8 JSON. Replies use `NIBR1:`. Both are limited to 128 KiB. A reply preserves the request's `requestId` and `capturedAt`. Questions are at most 2,000 UTF-8 bytes. Only one request is processed at a time; repeated identical IDs are deduplicated in a bounded cache. Reusing an ID with different content is rejected.

The reusable backend is `createAssistant(options).handleAsk({packet,question?},{signal?})` in `lib/assistant.mjs`. The HTTP boundary enforces localhost Host/Origin, a per-boot CSRF token, JSON body limits and a short rate limit. Model generation and source lookup have bounded timeouts. The localhost eve endpoint uses a separate random bearer token that the browser never receives.

## Knowledge and character behavior

`data/guide-index.json` is the private user-supplied RestedXP index; it is excluded from Git. `data/knowledge.json` contains a small original cited research seed, not a Wowhead mirror. Each question retrieves a bounded set of relevant passages, excludes explicit opposite-faction routes when faction is known, and matches actual running guide steps by quest IDs and element text. Unknown/neutral faction entries remain eligible. Raw source step indices are not equated with the running addon's filtered indices. Original headers and conditions remain visible to the model, but no guide DSL is executed and class/race/season prerequisites are not automatically evaluated.

Only `lookup_warcraft` is enabled in the eve agent. Default shell, file, arbitrary web, delegation and self-modification tools are disabled; development extensions are also disabled. In Gemini mode the lookup returns an explicit local-only capability note without any network call. In OpenAI mode it calls Responses web search restricted to `wowhead.com`, `news.blizzard.com`, and `worldofwarcraft.blizzard.com`, at most twice per request. It keeps provider citation metadata and filters URLs by parsed hostname. The final response can cite only actual returned source IDs or retrieved local passages. It cannot invent a new clickable URL.

Nib's authored instructions limit answers to Warcraft help and in-world roleplay, preserve the playful murloc persona, distinguish Forever from other WoW editions, and require uncertainty about unverified mechanics or drop rates. An additional deterministic gate catches common out-of-scope and instruction-override requests. Prompting and these checks are defenses, not a mathematical guarantee of factual accuracy or perfect scope adherence.

Only `waypoint`, `quest`, and `guide` suggestions survive the action validator. Waypoints use percentage coordinates from 0 to 100. Guide suggestions must match a known indexed guide for the player's faction. The game addon requires a player click; no model output is executed as Lua, shell, slash commands, or arbitrary addon calls.

## Optional optical transport

Set `NIB_OPTICAL_ADDONS` to the explicit installed `Interface/AddOns` directory only after installing the optional reply modules and enabling Nib optical mode in game. The supervisor then starts the separate `tools/optical-bridge.mjs` helper. Its screen-region capture and reply-slot lifecycle are documented by the main project. Manual packets remain available if the helper fails. Optical transport currently requires the default public port 17861.

## Verification and limits

`npm test` checks packet validation, Unicode, source domain filtering, retrieval/faction conditions, raw Responses parsing, action filtering, scope redirects, missing-key behavior, deduplication and HTTP CSRF/origin checks. `npm run typecheck` validates authored TypeScript. `npm run build` builds the actual eve runtime. `node test/eve-smoke.mjs` starts an isolated private runtime, verifies health/auth and that only the lookup tool is exposed, then stops it. It sends no model request and needs no API key.

Each dynamic model selection supplies a conservative 128,000-token context limit so builds do not depend on optional Gateway metadata. Middleware caps each primary generation at 2,400 output tokens; OpenAI search requests also have token caps. Only the selected provider's key is used. Quota or access errors do not select a different provider.

Live Google/OpenAI replies and in-game operation require runtime testing with the user's configured account and client. `store:false` applies to OpenAI, not Google's retention terms: [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data). Provider tests use mocked responses and do not establish real key validity or free-tier eligibility. eve can retain local workflow transcripts under `.eve`; the browser and addon may retain their own history. Do not share `.env`, `.eve`, or private guide indexes.
