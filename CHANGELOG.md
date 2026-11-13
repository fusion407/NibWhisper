# Changelog

## 0.7.13
- A step you skipped and later finished now shows as Done in the step list, and no longer counts as skipped.

## 0.7.12
- Nib Targets has skull and cross buttons beside each name: one click targets the enemy and places the marker. The window has a new look and can be resized outside combat.
- The step list is redesigned: step numbers, a status for each step (You are here, Done, Skipped, Not for you), a full-text tooltip, mouse-wheel scrolling and a Show my step button.

## 0.7.11
- Fixed: macros and slash commands such as /tm 8 were blocked with an "addon blocked" error blamed on Nib. Nib had reassigned the game's slash-command table, which tainted every slash command.

## 0.7.10
- Nib plays a sound when an answer arrives, from guide chat or the AI. Nib Options has a switch for it.

## 0.7.9
- A "travel to" step now finishes when you arrive, including while you are browsing steps.
- Steps that should be skipped when you are already in an area now recognise the area.
- Nib's rewording of the guide is removed. The guide reads as the route was written again.

## 0.7.8
- The guide no longer waits on a step that is already finished when you reach it.
- Browsing steps pauses the guide only until you finish the step you are looking at, or accept or hand in a quest.
- Flying, hearthing, setting your home, learning a flight path, abandoning a quest, casting a named spell, equipping or destroying an item, dying to respawn, and choosing a dialogue option now tick their steps by themselves.
- A step that tracks one part of a quest also shows where the whole quest stands.
- The step list has a checkbox on each row to skip a step or go back.

## 0.7.7
- Nib words the guide's instructions his own way. The steps, their order and their targets are unchanged, and plain lines such as Accept, Turn in, Train and Collect stay as they are. Nib Options has a switch for it.

## 0.7.6
- Guide text: stray separators no longer show in steps, and colours that were left open or closed twice are tidied.
- Nib speaks in a few of the guide's own messages.
- Simpler setup: drag the folders in, then start the helper, which finds the game and prepares its reply files.

## 0.7.5
- Nib himself can be resized by a grip in his corner.
- The quest details card has a View in quest log button.

## 0.7.0 to 0.7.4
- Automatic replies now reach the game through reply files inside the AI Assistant addon. The 200 reply-slot addons are no longer needed.
- `/nib filelog` shows what the reply-file reader tried for a waiting or failed request.

## 0.6.0 to 0.6.6
- Nib is now three addons: Nib Whisper, Nib Whisper: Leveling Guide and Nib Whisper: AI Assistant. Either part works without the other.
- The guide opens at login, and the guide and chat windows remember where they were left.
- Gemini stays linked between sessions, and the helper retries when the model is briefly overloaded.
- A sound can play when a chapter is finished.

## 0.5.4 to 0.5.5
- Button captions fit their buttons everywhere, and Options has a window size setting.
- The guide accepts and turns in the current step's quests, with an Options switch and Ctrl to skip.
- Guide links can be copied, coloured names open an info card, and quest objectives show quest details.
- Guide progress bar, tooltips, and several fixes.
