# Nib Whisper

Nib is a small, goofy murloc cartographer for **World of Warcraft: Forever**. He comes as a 1–60 leveling guide with quest tracking and TomTom waypoints, and as an in-game chat companion that answers Warcraft questions with Google Gemini.

## Install

### 1. Download

For chat, choose **Code → Download ZIP** on GitHub and unzip it. Keep the folder so you can run Nib's helper from it.

For the leveling guide, use a private addon ZIP that includes `NibWhisper_Guide/TrailData.lua`, or build that file from your own installed guides with `node tools/build-trail.mjs`. GitHub's source ZIP does not contain the route data.

### 2. Drag and drop

Fully exit WoW. Open the extracted addon ZIP or the `addon` folder in the source ZIP, then merge the relevant folders into `World of Warcraft\_forever_\Interface\AddOns`:

- `NibWhisper`
- `NibWhisper_Guide` (requires `TrailData.lua`)
- `NibWhisper_Assistant`

Start the game and enable Nib Whisper and the modules you installed on the AddOns list. In game, type `/nib version` to check the loaded version and modules. [TomTom](https://www.curseforge.com/wow/addons/tomtom) is optional and adds the waypoint arrow.

### 3. Set up your Gemini key

This step is only for AI answers.

1. Install [Node.js](https://nodejs.org) 24 or newer, once.
2. Double-click **`Start-Nib-Auto.cmd`** in the folder you unzipped. The first time, it finds your AddOns folder and creates Nib's reply files there. Leave its window open while you play.
3. Fully exit and reopen the game once, so it sees the reply files.
4. Get a free key from [Google AI Studio](https://aistudio.google.com/apikey) and copy it.
5. In the game, right-click Nib's minimap button and choose **Gemini setup → Use copied key**. Keep the key on your clipboard until Nib says **Gemini connected**.

That's it. Nib remembers the link, so from now on you only start `Start-Nib-Auto.cmd` before playing. To have it start by itself when you sign in to Windows, run `Install-Nib.ps1 -Background` once.

### Good to know

- **If the start script can't find the game**, it asks you to paste the path of your AddOns folder.
- **Updating:** merge the updated folders into the existing AddOns folder to retain your locally built route data. Use a full client restart to load the update.
- **Your key stays on your computer**, in `companion/data/gemini-key.local`. It never goes into the game.


## Three addons, two switches

Nib installs as **Nib Whisper** plus two sub-addons. Keep Nib Whisper enabled, then tick either or both in the AddOns list:

- **Nib Whisper: Leveling Guide** is Nib Trail. On its own, the minimap button's left-click opens the guide and Options shows only guide settings. Cloud sync needs the assistant's helper bridge; export and import still work.
- **Nib Whisper: AI Assistant** is chat, the mascot, inventory notes, and the helper bridge. On its own, the guide buttons disappear and guide chat still answers quest log and profession questions.

Automatic replies reach the game through **reply files**: 8,000 small font files inside the AI Assistant addon. The helper writes each reply into one as character widths and Nib measures it back, so nothing extra appears in the AddOns list. Each file can be read once per game session, which allows about 250 automatic requests before WoW needs a full restart. The older 200 **Nib reply slot** addons are no longer needed; `Install-Nib.ps1 -RemoveSlots` uninstalls them. If an automatic request fails, `/nib filelog` shows what the reader tried and when, for comparison with `companion/nib-helper.log`.

## Nib Trail: leveling guide

Type `/nib trail` or click **Leveling trail** in Nib's chat. **Routes** suggests chapters for your character. The pack combines the installed starter routes with your supplied later routes: **282 chapters and 28,541 source steps**, with level 1–60 coverage and solo, dungeon, and Mage routes. Nib tracks supported quest, item, and travel milestones, saves a cursor for each chapter, and uses TomTom for the active step's arrow and pins when installed. **Ask Nib** passes the current guide step and its resolved waypoint to the assistant. The tracker works independently of the companion, AI provider, and RestedXP addon.

Drag the tracker's bottom-right corner to resize it. Progress saves locally per character. **Progress sync** in Nib Options offers automatic sharing through the local companion and a folder shared by both PCs, plus manual export/import. Sync works without an AI key. [In-game QA walkthrough](QA.md)

The tracker arrows and **Steps** let you browse numbered steps and pause automatic advancement. **Done** resumes forward progress. Nib checks the live quest log for acceptance, objectives, and turn-ins. The bundled QuestieDB Forever snapshot lists prerequisites for 1,316 quests in the route pack. A step can be skipped when all its tracked objectives are blocked by confirmed missing prerequisites. Quests already in your log stay eligible, and gaps in the data stay unknown. [QuestieDB source revision](https://github.com/Questie/QuestieDB/tree/e19dfdf8528334ea63da0ecc4e291c134c0fc266/data/Forever)

### Choose an AI provider

The companion's **AI provider** and **Model** controls save a selection locally. The Gemini setup form checks access to the selected Google model and saves the key on this computer without a restart. A saved key takes precedence over `GEMINI_API_KEY` in `companion/.env`. OpenAI key changes require restarting the companion.

The default is **Gemini 3.5 Flash-Lite**, with Gemini 3.8 Flash as another option. Both have free-tier token access listed in Google's current [pricing](https://ai.google.dev/gemini-api/docs/pricing), subject to project eligibility and changing quotas. The companion cannot establish your billing tier from the key. Google may use free-tier content to improve its products. Private guide excerpts and character context are sent to the provider only when you ask.

**Live web search is disabled in Gemini free mode**, because search grounding is not included in the current models' free API tier. The local 1–60 guide, researched notes and live character snapshots still work, with their existing citations. Nib must say when a current drop rate or other missing fact needs a manual Wowhead check. This is a visible capability limit, not a claim that the assistant browsed a page it could not access.

OpenAI remains an optional explicit selection: configure `OPENAI_API_KEY`, choose **OpenAI**, and select a supported model ID. Its API billing and on-demand search apply only to that selected provider.

### Copy and paste mode

The default works without screen capture:

1. Asking in-game opens Nib's message satchel with a selected `NIBQ1:` packet. Copy it.
2. Paste it into **Link your character** on the companion page and choose **Read character notes**, then **Ask Nib**.
3. Choose **Copy reply for the game**. Return to WoW, use **Copy / paste** (or `/nib paste`), paste the `NIBR1:` packet into the reply box, and click **Read reply**.

Each reply matches one pending question and character session. Duplicate, cancelled, and previous-session replies are rejected. Ask new in-game questions to refresh context. Further questions asked only in the browser are marked browser-only and cannot answer an old in-game pending request.

### How automatic mode works

Automatic mode is what the install steps above set up. It uses display and addon-file mechanisms instead of direct HTTP from Lua. No game memory is read and no clicks, keystrokes, or gameplay are automated. No Blizzard endorsement has been established.

1. When you ask a question, a small grayscale signal appears in the bottom-right corner of the game until the helper confirms it has read it. Keep WoW in front with that corner visible.
2. The helper decodes the signal. Screen images stay on your computer and are discarded.
3. The helper writes its reply into Nib's reply files, and Nib reads it back by measuring text. Replies are data only; nothing in them is run as code.
4. The helper reads your clipboard only when you click **Use copied key**. The setup request itself carries no API key.

The helper's screen-reading loop only runs while a process named `Wow…` is in the foreground. Display scaling, HDR/gamma, window layout and client updates can affect it; use copy and paste if it fails. Each reply file can be read once per game session, which allows about 250 automatic requests before WoW needs a full restart.

## What Nib knows about your character

Every in-game question captures a new timestamped snapshot:

- Character level, class, race, faction, zone, map position, XP and available character state.
- Active quest IDs and objectives, known completed IDs, and explicit completion-coverage flags. Unavailable or trimmed history is reported as unknown/partial.
- Live bag counts and carried gold. Personal banks and other characters use timestamped records from this WoW account on this machine. Log into each alt and open its bank once. Open a bank again to refresh its record.
- Profession ranks and caps. Open the crafting profession with its filters cleared to record learned recipes, current skill-up colors and reagent costs. Nib can suggest a batch using materials in your bags, bank and saved alt records. It will identify estimates and stale data.
- Loaded addon names/versions and read-only RestedXP current-guide, nearby processed steps, quest IDs, and progress details.

The export contains no BattleTag, API key, or other players' chat. It is not an inventory of every fact in the game. Missing quest completion or recipe data is never proof that nothing is completed or known.

Nib can recommend a map pin, quest details, or a guide that is available in RestedXP. **Only your click runs an action.** Replies cannot execute arbitrary Lua, slash commands, or addon methods. Reading RXP context does not advance its steps. Loading a suggested guide changes your selected guide only after you click.

## Knowledge and personality

The local private index contains **198 supplied guide records and 19,153 raw steps**. Retrieval selects a small set of relevant excerpts per question, preserving route headers and conditions. Actual live RestedXP step text is the closest context: processed step numbers can differ from raw file step numbers because the addon filters routes.

Nib also uses a small set of original factual summaries with sources. OpenAI mode additionally supports on-demand search restricted to Wowhead and official Blizzard sites; Gemini free mode uses local knowledge only. This is **retrieval**, not training or a complete Wowhead mirror. Some pages may be inaccessible. Forever is distinct from Classic Era/SoD/retail; unknown drop rates, prerequisites and recipe details must remain unknown instead of being invented. Route conditions are included as reference text rather than executed by the AI; speed and applicability still require judgment.

Nib is instructed to stay in Azeroth, permit casual Warcraft roleplay, and redirect unrelated real-world questions in character. Deterministic checks handle obvious unrelated/injection requests, and the model has fixed world-scope instructions and structured output. Persona compliance and factual quality still need live model evaluation; no prompt guarantees perfect behavior. The agent has one scoped knowledge-lookup tool, with general shell/file/computer tools disabled.

## Controls

| Control | Effect |
|---|---|
| Minimap left-click | Open the leveling guide, or chat if only the assistant is enabled |
| Minimap right-click / click Nib / `/nib` | Open Nib chat when the assistant is enabled |
| Minimap Shift-right-click | Open Nib Options (plain right-click when only the guide is enabled) |
| **×** on Nib | Hide the mascot until you show him again in Nib Options |
| Click a blue `>` guide line | Copy its video or web link |
| Click a coloured name in a guide step | Open an info card with Ask Nib and a Wowhead link |
| Right-click a quest objective in the guide | Show quest status, objectives, and prerequisites |
| **Auto quests** in Nib Options | Accept and turn in the current step's quests while the guide is open; hold Ctrl to skip |
| `/nib options` | Open settings for chat, the guide, sync, mascot visibility, and window size |
| Click a guide objective with coordinates | Set its TomTom waypoint |
| **Targets** in the guide header | Open Nib’s target picker outside combat |
| Drag Nib / minimap icon | Move it |
| Drag the grip in Nib's corner | Resize him |
| `/nib show` or `/nib hide` | Set mascot visibility |
| `/nib trail` | Open the leveling guide and progress controls |
| `/nib auto on` or `/nib auto off` | Set automatic bridge mode |
| `/nib copy` / `/nib paste` | Open manual exchange |
| `/nib cancel` | Cancel pending question |
| `/nib clear` | Clear this character's addon chat |
| `/nib reset` | Reset mascot position |
| `/nib filelog` | Show the reply-file reader's log for a waiting or failed request |
| `/nib help` | Show pocket instructions |

## Data and setup

The local service binds to `127.0.0.1` and protects writes with same-origin checks and a session token. The Gemini setup form saves the key as a local credential in `companion/data/gemini-key.local`. Pressing Send in AI mode shares your question, character snapshot, and relevant guide excerpts with the selected provider. Google may use free-tier content to improve its products. Guide chat uses game data directly in WoW.

The browser page works without a key for setup and sample-context previews. It does not fabricate AI replies. The `sample` badge always identifies synthetic character data. Model access, project quota and billing must be checked by the owner. Existing consumer ChatGPT or Gemini app sign-ins do not configure these API credentials.

## Publishing to CurseForge

`npm run package:curseforge` writes `dist/NibWhisper-<version>.zip`, laid out the way CurseForge expects: one folder per addon at the top level. Pushing a tag such as `v0.7.5` runs the same script on GitHub and attaches the zip to a GitHub release.

Before the first upload:

1. **Create the project** on CurseForge under World of Warcraft, then add its number to each `.toc` as `## X-Curse-Project-ID: <number>`.
2. **Choose a licence.** There is no `LICENSE` file yet, which means all rights reserved. If the Leveling Guide is ever published, note that `QuestLinks.lua` comes from QuestieDB under GPL-3.0.
3. **Decide what ships.** The default zip holds the core and the AI Assistant only. On its own that gives chat in Guide chat and copy-and-paste modes. Automatic replies need the local helper from this repository, which CurseForge does not distribute.
4. **The Leveling Guide is not in the default zip.** Its route data, `TrailData.lua`, is built from RestedXP guides and is not in this repository either. Publishing it needs RestedXP's permission. `--with-guide` exists for that case and should not be used without it.
5. **Check CurseForge's rules for the helper bridge.** Automatic mode passes data between the game and a local program through an on-screen signal and font files. Read their addon policy, and Blizzard's, before describing or shipping that feature there.
6. **Upload** the zip from `dist`, pick the game versions matching `## Interface`, and paste the section for that version from `CHANGELOG.md`.

The two sounds are also not in the repository or the zip. Put your own files at `addon/NibWhisper_Guide/Sounds/jobs_done.mp3` (end of a chapter) and `addon/NibWhisper_Assistant/Sounds/murloc.mp3` (Nib replies). Nib stays silent if a file is missing.

## Verification and source map

Run from the project root:

```powershell
npm test
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\capture-optical.ps1 -SelfTest
npm --prefix companion run typecheck
npm --prefix companion run build
```

Tests cover Lua compilation/UI construction with mocked game APIs, modern and legacy snapshots, Unicode/strict packet parsing, stale/duplicate replies, explicit action boundaries, actual local-guide citation interoperability, backend HTTP/source/scope behavior, paged optical transport and synthetic bitmap decoding. Provider tests exercise the official Gemini SDK with mocked Google responses, private-header authentication, quota errors, saved model selections and no OpenAI fallback. A bounded Eve runtime/authentication smoke ran without model calls. **The actual WoW rendering/transport and live provider answers have not been tested.**

- `addon/NibWhisper/`: the shared core (minimap button, Options, events, packet protocol) and original sprite assets.
- `addon/NibWhisper_Guide/`: Nib Trail, its route data and quest links.
- `addon/NibWhisper_Assistant/`: the switch for chat and the mascot, inventory records, and the screen signal. The chat window code itself stays in the core folder and is only built when this addon is enabled.
- `addon/NibWhisper_Assistant/Fonts/` and `tools/font-transport.mjs`: the reply files and the code that writes them.
- `addon/NibWhisperReply001…200/`: the older reply slots, kept as a fallback.
- `companion/`: localhost UI and genuine eve agent; `.env` is private.
- `companion/data/guide-index.json`: private user-supplied guide index; not a public source corpus.
- `tools/`: reproducible asset/index/transport tools.
- `reports/Forever companion assistant.md`: deep research and citations.
- `import-evidence.json`: previous guide-bundle inspection evidence.

This is an independent personal project, not affiliated with Blizzard, Wowhead, or RestedXP. The original addon code, original guide bundle, and current game session are not modified by installing Nib's separate folders.
