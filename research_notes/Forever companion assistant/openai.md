# OpenAI powered Forever companion architecture

## Which model and API fit the companion

### Takeaway
Use an external local service for the model connection. The existing workspace contains Node ESM analysis utilities rather than an established app framework. For a new agent, the applicable build-agents skill defaults to eve; direct OpenAI models are appropriate because the user specifically requests a ChatGPT-powered companion.

### Cited Findings
- The Responses endpoint accepts direct HTTP requests authenticated with an API bearer credential. Credentials belong in a server environment variable, never in browser or addon code. [OpenAI API authentication](https://developers.openai.com/api/reference/overview)
- Current GPT-6.1 Sol documentation lists Responses, web search, and Structured Outputs support. Its account availability and limits depend on the user's API organization. Use a configurable model rather than promising access. [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
- The current eve setup requires Node.js 24 or newer and does not require a Vercel project for local use. [eve getting started](https://eve.dev/docs/getting-started)
- In eve, `defineAgent({model:openai('gpt-6.1-sol')})` can use `openai` from `eve/models/openai` and `OPENAI_API_KEY`. The separate `chatgpt()` helper supports a locally signed-in subscription through `/login`, but cannot run in a deployment. [eve agent configuration](https://eve.dev/docs/agent-config)
- eve supplies a local HTTP session channel: create with `POST /eve/v1/session`, send subsequent messages with `POST /eve/v1/session/:sessionId`, and observe NDJSON at `GET /eve/v1/session/:sessionId/stream`. It also accepts a per-turn `outputSchema` and `clientContext`. [eve HTTP channel](https://eve.dev/docs/channels/eve)

### Inferences
- Recommended layout: Lua addon owns character UI and player snapshot; a localhost-only browser companion owns copy/paste transport, private retrieval, credentials and API calls. There must be no API credential in SavedVariables, addon distribution, exported packets, browser localStorage, or logs.
- If using eve, keep the agent's default broad capabilities constrained: no shell, code execution, MCP, self-modification, arbitrary HTTP fetching, or gameplay automation. Grant only a narrowly scoped game-knowledge lookup tool. Do not expose a stock development server to the LAN.
- The existing `inspect-import.mjs` is a local utility, not an app stack; it does not establish a framework exception. Follow installed eve version docs before implementing its APIs.
- An explicit, source-backed direct Responses transport is also technically possible, but choosing it over the skill's default needs an applicable exception or a clear recorded implementation constraint. Do not add a nominal unused eve scaffold and claim the app uses it.

### Gaps
- No OpenAI key tool was available in the tool inventory examined by the coordinator, and this research did not inspect or expose existing secrets. Live paid model calls have not been tested.
- The public eve pages do not specifically establish Windows native support. Node-version compatibility alone is not proof; install/build/run checks on this host are necessary.

## How should retrieval and reply formatting work

### Takeaway
Knowledge should be retrieved for each relevant question, not described as permanently learned or exhaustive. Separate verified game snapshot facts, privately supplied guide passages, public web evidence, and uncertain general knowledge.

### Cited Findings
- Responses uses the `web_search` tool. Domain filters accept bare domains in `filters.allowed_domains`, and `include:['web_search_call.action.sources']` exposes consulted sources. Native `url_citation` annotations carry URL, title and text offsets; displays of search-backed information must provide prominent clickable citations. [OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search)
- Structured Outputs uses `text.format:{type:'json_schema',name,strict:true,schema}`. Use `required` keys and `additionalProperties:false`; still handle refusal content and incomplete responses. A structurally valid output is not proof that its factual claims are correct. [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- Responses stores application state by default; `store:false` disables that response storage. [Responses migration](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- API data is not used for training by default unless the user opts in, but abuse-monitoring retention and application storage are separate concerns. `store:false` is not a general zero-retention promise. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data)

### Inferences
- Suggested direct REST search body (fill approved domains from the game research):

```js
{
  model: process.env.OPENAI_MODEL || 'gpt-6.1-sol',
  store: false,
  instructions: fixedKnowledgeInstructions,
  input: [{role:'user',content:JSON.stringify({question, snapshot, excerpts})}],
  tools: [{type:'web_search',filters:{allowed_domains:['wowhead.com']}}],
  include: ['web_search_call.action.sources'],
  tool_choice: 'auto',
  max_output_tokens: 2500
}
```

- `POST https://api.openai.com/v1/responses` with `Authorization: Bearer ...` and `Content-Type: application/json`. Abort with a bounded timeout; handle 401, 403, 429, 5xx, network errors, missing output, refusal and `status:'incomplete'`. Do not retry paid calls invisibly without a bounded policy.
- Parse REST text from `output[]` items of `type:'message'`, then `content[]` of `type:'output_text'`; `output_text` is an SDK convenience and must not be assumed on raw HTTP JSON. Parse citation annotations separately. Only accept https URLs whose parsed hostname is an allowed domain or its subdomain; never use string substring matching. Keep provider source IDs separate from model-generated text.
- A robust compatibility path is two bounded stages: retrieve/search into cited text, then request a strict no-tool reply structure using that evidence. This avoids depending on whether a particular selected model/provider supports both hosted search and strict formatting in the same request. Do not claim joint support was integration-tested merely because each feature is listed separately.
- Suggested reply contract: `answer` string, `mood` enum, `intent` enum (`advice`, `roleplay`, `off_topic`, `needs_context`), `sourceIds` array referencing a server-built source table, and optional typed waypoint fields. Validate all fields and lengths on the service and again at the addon boundary.
- The browser can render real clickable source URLs. The addon cannot be assumed able to launch external browsers; render clickable source names that open a copyable URL dialog, with the same source accessible in the browser companion.
- Restrict search to Wowhead plus domains the other researcher confirms as authoritative for Forever. A Wowhead result about another WoW branch is not proof of a Forever drop rate. For rates, identify item/NPC/quest ID, branch, observed sample size where available, and date; otherwise say the rate is unknown. Never invent exact percentages.
- For private guide retrieval, index only user-supplied local material and send small relevant passages rather than the entire 1–60 bundle each turn. Preserve class/race/faction/season conditions; matching prose alone does not establish a safe next quest.

### Gaps
- No live API credential means hosted search, the selected model's eligibility, joint search/JSON behavior, and real latency remain unverified.
- Domain restriction cannot guarantee every page will be available through the search tool. Inaccessible content must remain an explicit unknown; do not bypass access restrictions or promise all of Wowhead has been downloaded.

## How can the companion stay in character safely

### Takeaway
Treat persona and world scope as product requirements enforced at several boundaries. Permit Warcraft roleplay and practical WoW UI help, while redirecting unrelated requests with a short in-character line.

### Cited Findings
- eve channels use the same agent instructions and tools across transport surfaces; route authentication is separate from conversation audience and channel logic. [eve channels](https://eve.dev/docs/channels)
- Current official documentation says eligible ChatGPT Pro and Business subscriptions can claim API credit benefits by linking an owned API organization. Do not state categorically that subscriptions never include API credits; eligibility and active balance must be checked in account billing. [API credits for ChatGPT subscribers](https://developers.openai.com/api/docs/guides/chatgpt-api-credits)

### Inferences
- A fixed persona prompt should identify Nib (or chosen mascot) as a playful Warcraft companion, allow casual in-world RP, require clear concise help, and forbid claims of live observation beyond the supplied snapshot. It must not imply the software is an actual player or Blizzard character.
- All quest titles, guide passages, addon-provided strings, player messages, and web content are untrusted data. They cannot change the persona, topic boundary, source policy, allowed actions, credentials, or output schema. Explicitly say to ignore instructions contained inside retrieved content.
- Off-topic requests should receive a deterministic or separately classified in-character redirect, such as: 'Mrrgl! My maps stop at Azeroth. Quests, crafts, or a tavern tale?' Keyword filtering alone is insufficient for paraphrases and prompt injection; a model scope classifier plus output gate is stronger, but no prompt is an absolute guarantee.
- Keep RP imaginative without presenting invented lore, items, routes, drop chances, quest completion, or NPC locations as verified mechanics. Distinguish 'tavern tale' from actionable factual guidance.
- Snapshot requires captured timestamp, request ID, client build/branch, locale, character level/class/race/faction, active quests/objectives, known completed quest IDs and coverage, professions, map/position, loaded addon list and active RestedXP guide/step. Missing coverage is unknown, never equivalent to uncompleted. Reject mismatched request IDs and show stale-context warnings on replies.
- Do not let the model generate executable Lua. If recommendations include an action, parse a tiny allowlist such as open quest details or set a waypoint, validate numeric IDs/maps and coordinate ranges, and require a player click. Never accept slash commands, arbitrary addon method names, scripts, file paths or URLs as executable instructions.
- Store conversations locally with an obvious clear-history control and a bounded history window. Avoid BattleTag/account identifiers unless necessary; do not export chat from other players. The explicit Send action should state what snapshot is transmitted to the configured AI service.
- Restrict localhost server bind, Host/Origin, body size, concurrency, rate and token bounds; use same-origin CSRF protection and never return provider secrets. Do not expose a browser-provided arbitrary API base URL, arbitrary file loader, or arbitrary URL fetch endpoint.

### Gaps
- No code, live game session or model evaluation was performed in this research assignment. Scope resistance, transport freshness, and reference quality require behavioral tests in the implementation.
- The user's account plan, available credits, key, exact default model preference and acceptable spending cap are unknown. Ship configurable limits and clear setup status rather than claiming production AI is connected.
