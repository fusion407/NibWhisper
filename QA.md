# Nib Trail 0.7.5 in-game QA

## Desktop: first five minutes

1. Fully exit and reopen WoW: Forever after installing. On the character selection screen, open **AddOns** and enable **Nib Whisper** and **TomTom**. If RestedXP is already directing you somewhere, hide its route arrow for this test so it doesn't compete with Nib's.
2. Log into a fresh Human on Alliance for a known starting point, or use your current character. Click the minimap button, then **Leveling guide** in the chat header. Click the route banner to choose a chapter. A fresh Human should be offered **1–6 Northshire**. For an existing character, choose a chapter for their level and quest history, then use **Steps** to jump to an instruction.
3. In **Nib Options**, check that auto advance and map pins are on. For a fresh Human, look for **A Threat Within**, quest 783. Walk toward the waypoint and check that the TomTom distance decreases. If a step has several locations, click the coordinate row to cycle pins.
4. Drag the bottom-right corner of the tracker and check that the objectives wrap and scroll. On a Warrior in **1–6 Northshire**, try the checkbox for **Train Battle Shout**, then click it again to undo it while the vendor task is still pending. Open and close Brother Danil's vendor window, then train Battle Shout. The next step and TomTom waypoint should update automatically. Click the route banner and try the category dropdown and search.
   - At Northshire step 12, check that **Nibbled-On Book** is named and the raw directive is gone. Press the down arrow to inspect step 13. The tracker should pause on 13 even when its condition makes it inactive. Click **Done** to resume forward progress.
5. Left-click the minimap button and choose **Next objective** in Guide chat. Check that the reply names the active step. Try **Quest log** and **Professions**. This works before the companion starts.
6. Copy your Gemini API key. In Nib chat choose **Gemini setup → Use copied key**. Leave the clipboard alone until you see **Gemini connected**. Ask “Where should I go for this step?” and compare the answer to the guide. Check that the small corner signal disappears when the helper receives the request. [Setup instructions](README.md)
7. Shift-click the minimap button to open the guide. Put chat and the guide partly over each other and open each from its shortcut. Verify the front window covers the other. Click an objective with coordinates and compare the TomTom destination with its tooltip. Try **Targets** outside combat. On a death or release, verify that a guide you left open stays open.
8. Open your bank on two characters and return to the first. Ask Nib how many of a known item are in each character’s bags and bank. Check the counts and which records are described as last seen. Open a crafting profession with filters cleared and ask what to craft for the next few skill points. Compare the recipe, color and quantities with the game.

9. New in 0.5.4. Ask an AI question whose reply offers action buttons and check that every caption sits inside its button. Hover a shortened one to read the full title. Drag the chat and guide to their smallest sizes and check that no caption crosses a button border. In **Nib Options → Display**, click **Window size** through all four sizes and check that chat, the guide, and Options all rescale. The guide banner should show a thin progress bar and a percentage beside the step number. Hover the guide's footer buttons for tooltips.

10. New in 0.5.5. With the guide open on a step that says to accept or turn in a quest, talk to the NPC and check that Nib accepts or turns it in without a click. A quest that is not in the step should be left alone, and a reward with several choices should wait for you. Hold Ctrl while talking to do it by hand, and switch **Auto quests** off in Nib Options to confirm it stops. If RestedXP's own quest automation is on, both addons act on the same window; turn one off if that causes trouble.
11. Find a step with a **Click here for video reference** line (it shows in blue with a `>` marker). Click it and check that the copy window holds the web address. Click a coloured NPC, enemy, or item name in a step and check that an info card opens with **Ask Nib** and **Copy Wowhead link**. Right-click a quest objective for quest details. Shift-click the minimap button with either mouse button and check that the guide opens, and closes on a second click.

12. New in 0.6.0. On the character selection screen open **AddOns** and check that **Nib Whisper: Leveling Guide** and **Nib Whisper: AI Assistant** are listed, and whether the reply slots now fold under Nib Whisper. Log in with only the guide enabled: left-clicking the minimap button should open the guide, with no chat, mascot, or Ask Nib button. Log in with only the assistant enabled: chat should work and no guide buttons should appear. Log in with both and repeat step 7.

13. New in 0.6.1. Log in and check that the guide is already open. Switch **Open at login** off in Nib Options, `/reload`, and check that it stays closed.

14. New in 0.6.5. Link Gemini once with **Gemini setup → Use copied key**, then fully exit and reopen the game. Nib Options should still show **AI automatic** selected, and a question should be answered without linking again. If Google is briefly overloaded the helper retries by itself; a reply can take up to about 15 seconds longer.

15. New in 0.6.3 and 0.6.4. Drag the guide and the chat window somewhere new, fully exit the game, and reopen it. Both should appear where you left them. Repeat after resizing it and after changing **Window size**.

16. New in 0.6.6. Finish the last step of a chapter, by **Done** or by auto advance, and check that the chapter sound plays once. Browsing steps and logging in on a finished chapter should stay silent. Switch **Chapter sound** off and on in Nib Options; switching it on previews the sound.

17. New in 0.7.0. Fully restart WoW after installing, so the game sees the new reply files. With **AI automatic** selected, ask Nib a question and check that the answer arrives as before. Ask one that produces a long answer. In `companion/nib-helper.log` the helper should report `Published a matched reply to N reply file(s)` instead of `optional data slots`. Then run `Install-Nib.ps1 -RemoveSlots`, restart WoW, check that no **Nib reply slot** entries remain in the AddOns list, and ask again.

18. New in 0.7.5. Show Nib himself from Nib Options and drag the grip in his bottom-right corner. He should grow and shrink in proportion, stop at a smallest and largest size, and keep the size after `/reload`. `/nib reset` restores it. In the guide, right-click a quest objective for a quest you are on and click **View in quest log**; the quest log should open on that quest. The button should be absent for a quest you have not picked up.

## Desktop → laptop → desktop

1. Extract the same **NibWhisper-Personal.zip** on the laptop. From the extracted folder, run the command below in PowerShell, replacing the sample game path with the laptop's actual path. Enable Nib and TomTom and fully restart the game after installing. Use Node.js 24+ and run `npm ci` in the extracted `companion` folder before starting the helper.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Nib.ps1 -Optical -Background -AddOnsPath 'C:\Games\World of Warcraft\_forever_\Interface\AddOns'
   ```

2. On both computers, sign into the same OneDrive account and make sure the `NibTrail` folder is available locally. Nib can use the `NibTrail` folder under the local OneDrive folder by default. To use a different shared folder, set `NIB_SYNC_DIR` in each machine's `companion/.env` to the absolute path of that machine's copy of the **same** replicated folder. Start `Start-Nib-Auto.cmd` on both; the terminal should say the sync folder is configured. Sync needs no AI key.
3. On the desktop, log into the character you want to test and choose a route. Turn **Auto advance** off in Nib Options. Make a change with **Done**, **Skip**, or **Back** and write down the chapter and step. Open **Nib Options → Progress sync**, turn **Cloud sync** on, and wait for **Route progress synced**. If needed, click **Sync now**. Wait for your cloud app to finish uploading before leaving the desktop.
4. On the laptop, wait for the cloud app to download the folder. Log into the **same character** and open **Nib Options → Progress sync** before choosing a chapter. Turn **Cloud sync** on or click **Sync now**. Confirm the desktop's chapter, step, and skipped count appear. Switch off **Auto advance** for the comparison if the local quest state could advance the step.
5. Move back one step on the laptop, sync, wait for the cloud upload/download, and pull on the desktop. The newer deliberate rewind should win. Repeat with a different character; that character should not inherit the first one's progress.

Sync merges chapter progress separately. If both devices edit the same chapter before exchanging updates, the newer recorded change wins. Check **Route progress synced** before closing, then let your cloud app finish delivering the files. The status confirms the local exchange; it cannot verify delivery to another PC.

If the bridge or cloud folder is unavailable, use **Sync → Export / copy** on one computer, then paste the full `NIBT1:` string into **Sync → Import / merge** on the other. If the bridge times out, keep WoW in front and its bottom-right corner clear. Check `companion/nib-helper-error.log` and try a full game restart. A `/reload` refreshes the game's reply slots.

## What to record if a check fails

Include the client version, faction/class/race/level, chapter, step, what you expected, and what happened. For navigation, include the displayed map and coordinates and whether TomTom was enabled. For sync, record which device changed the step first, the last sync status on each, and whether the shared folder had finished syncing. To capture Lua errors, use `/console scriptErrors 1` and record the first error.

The route pack contains 282 chapters and 28,541 source steps. It includes faction, class and race filters, linked chapters, progress from supported game events, and side objectives that can stay visible while you travel. Some specialized source directives still require manual confirmation. NPC dialogue, purchases, and travel are player actions. Nib does not claim full RestedXP feature parity. Automated tests cover representative cases; navigation in the live client and delivery between two actual computers still need the checks above.
