# Forever identity and knowledge sources

## What exactly is World of Warcraft Forever?

### Takeaway
Forever is an official Blizzard version with its own changed world and systems. Treating it as Classic Era or Season of Discovery would produce incorrect advice.

### Cited Findings
- Blizzard describes Forever as a permanent product alongside Modern and Classic, centered on an expanded original Azeroth and level 60 progression. Its announced global launch was November 4, 2026. — [Blizzard announcement](https://news.blizzard.com/en-gb/article/24302093/carve-a-new-path-with-world-of-warcraft-forever)
- The early original-world timeline gains over 1,000 quests and nine new five-player dungeons covering levels 13–60. New combinations include Undead Paladins, Orc Mages, Troll Warlocks, Human Hunters, Dwarf Shamans and Gnome Priests. — [Blizzard launch overview](https://news.blizzard.com/en-us/article/24315643/return-to-azeroth-in-world-of-warcraft-forever)
- Local RXPGuides explicitly selects the FOREVER flavor and checks WOW_PROJECT_CAMELOT. These are addon source observations, not a live-client build capture. — [RXPGuides.lua](<A:/World of Warcraft/_forever_/Interface/AddOns/RXPGuides/RXPGuides.lua:205>)
- The reviewed Wowhead profession overview labels its edition Patch 1.60.1 and update November 7, 2026. — [Wowhead Forever professions](https://www.wowhead.com/forever/guide/professions/overview)

### Inferences
- Select the /forever/ namespace for database lookups and make the live addon report GetBuildInfo() and WOW_PROJECT_ID. The RXPGuides Vanilla TOC interface value 11509 does not establish the installed Forever client's actual build.
- In-character lore should stay within this world's early timeline and avoid presenting later-expansion events as current Forever events.

### Gaps
- No running client was queried during this research. The exact player build, realm ruleset, faction, level and enabled APIs remain to be obtained by the addon.
- The guide data is a separate route source, not proof that a particular route remains optimal after launch hotfixes.

## Which Wowhead and Blizzard resources can support answers?

### Takeaway
There is readable Forever material on Wowhead, but an exhaustive downloaded or trained Wowhead corpus was not established. Small factual seeds plus targeted search and citations are defensible and more maintainable.

### Cited Findings
- The requested [Wowhead homepage](https://www.wowhead.com/) opened, but exposed a JavaScript shell rather than a useful complete text homepage. Direct articles and some guides were readable.
- Wowhead's reviewed launch compendium organizes class, zones, systems, profession and dungeon resources, while noting that some higher-level dungeon coverage was still pending. — [Forever launch guide compendium](https://www.wowhead.com/classic-ptr/news/every-guide-youll-need-for-launch-the-wow-forever-guide-compendium-383727)
- There is a dedicated [Forever database](https://www.wowhead.com/forever/database), [Quest Unstuck tool](https://www.wowhead.com/forever/quest-unstuck), [Character Planner](https://www.wowhead.com/forever/character-planner) and [profession leveling tool](https://www.wowhead.com/forever/profession-leveling-guides). The planner and unstuck tools exposed JavaScript shells, so their interactive results were not observed.
- Blizzard says professions gain more than 600 recipes, adjusted food, and dungeon-boss Blueprints. — [Blizzard deep dive](https://news.blizzard.com/en-us/article/24303313/world-of-warcraft-forever-deep-dive-panel-recap)
- Primary profession slots remain two, with Cooking, Fishing and First Aid available as secondaries. Basic profession camp features start at skill 20; advanced recipes requiring 140 or more are dungeon/raid drops. — [Blizzard Camping guide](https://news.blizzard.com/en-us/article/24301516/gather-around-the-campfire-in-world-of-warcraft-forever)
- The reviewed Wowhead profession overview places healing-potion crafting in First Aid, not Alchemy. This illustrates a concrete conflict with generic Classic advice. — [Wowhead Forever professions](https://www.wowhead.com/forever/guide/professions/overview)
- Wowhead's current robots file explicitly lists GPTBot and several other AI crawlers under Disallow: /. The attempted terms-of-service URL was inaccessible; no public bulk-republishing license or complete public API was established. — [Wowhead robots.txt](https://www.wowhead.com/robots.txt)

### Inferences
- Do not make a bulk scraper, copy entire Wowhead guides, claim access to all its resources, or equate indexed search snippets with having read a page.
- Use official Blizzard pages for systems and changes, Forever Wowhead database entries for entity-specific information, and the player's current quest/profession snapshot for character state. Restrict web searches to known WoW source domains and require Forever qualifiers.
- Ship concise original facts with URLs, edition, checked date and uncertainty. Retrieve only relevant local route excerpts for the question, rather than sending the full guide corpus with every chat turn.
- The assistant can explain the difference between cited game facts and playful RP flavor. Fictional character flourishes must not become fabricated mechanics.

### Gaps
- This research did not read every item, quest or recipe, observe every tool, obtain a Wowhead API contract, or establish permission for full-site ingestion.
- Launch data can be incomplete; cached material should keep an as-of date and new answers should be checked when mechanics or numerical details matter.
- Do not silently mix Retail, Era, SoD, TBC or Mists results merely because searches include the word Forever.

## How should drop rates and quest recommendations be handled?

### Takeaway
Give recommendations from current character state and verified route evidence. Numerical drop rates need a cited, version-correct observation and should remain estimates rather than guarantees.

### Cited Findings
- Wowhead explains that its Client and Looter collect player interactions, loot and locations; aggregate submissions support database drop statistics, which improve with more observations. This is not a publication of an authoritative server loot table. — [Wowhead's own data-collection explanation](https://www.wowhead.com/news/help-contribute-to-the-wowhead-database-wowhead-client-looter-highlight-338456)
- The Client maintains the Looter addon and uploads collected observations, with its documented default background behavior occurring after WoW closes. — [Wowhead Client](https://www.wowhead.com/client)

### Inferences
- A drop percentage should include item and NPC identity, Forever version, source URL, retrieval date and sample count if the source exposes it. If not found, say the exact rate is unverified; never synthesize a plausible percentage from the guide or a few player anecdotes.
- Quest-unavailable does not equal completed. Check known completion IDs, active quest objectives, level/faction/class restrictions, prerequisites and relevant route conditions. Distinguish incomplete telemetry from a known negative.
- Profession leveling should start with the player's skill, cap, learned recipes and available materials; avoid making an exact shopping list from an unverified Era recipe route.
- Don't promise guaranteed loot, XP per hour, quest availability or fastest routing from static material alone.

### Gaps
- No particular Forever item/mob drop rate was verified in this assignment, and no numerical drop-rate seed is shipped.
- No character-specific recommendation can be verified before the player exports current state.
