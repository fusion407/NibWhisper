-- Nib's own wording for the guide. The steps, their order and their targets stay exactly as the route has them;
-- only the way each instruction is phrased changes, and plain bookkeeping lines (Accept, Turn in, Train, Collect,
-- Pick up, Abandon, Complete) are left as they are. Rewording happens when a chapter is read, never in the saved data.
local A = _G.NibWhisper
if not A then return end
local Voice = {}
A.TrailVoice = Voice

-- Lines that begin with one of these are left alone.
local plain = {Accept=true, Turn=true, Train=true, Collect=true, Pick=true, Abandon=true, Complete=true, Learn=true, Cast=true}

-- Sentence openers and what Nib says instead. A sentence that starts with the text on the left gets one of the
-- phrases on the right, chosen by the sentence itself so a given step always reads the same way.
local openers = {
    {"Talk to ", {"Have a word with ", "Go say hello to ", "Have a chat with ", "Pay a visit to "}},
    {"Speak to ", {"Have a word with ", "Have a chat with "}},
    {"Speak with ", {"Have a word with ", "Have a chat with "}},
    {"Kill him", {"Take him down"}}, {"Kill her", {"Take her down"}}, {"Kill them", {"Take them down"}}, {"Kill it", {"Take it down"}},
    {"Kill ", {"Take down ", "Deal with ", "Defeat ", "Bonk "}},
    {"Finish killing ", {"Finish off "}},
    {"Loot them for ", {"Search them for ", "Check their pockets for "}},
    {"Loot him for ", {"Search him for "}}, {"Loot her for ", {"Search her for "}}, {"Loot it for ", {"Search it for "}},
    {"Loot the ", {"Scoop up the ", "Grab the "}},
    {"Loot ", {"Scoop up ", "Grab "}},
    {"Travel toward ", {"Waddle toward ", "Head toward "}},
    {"Travel to ", {"Paddle over to ", "Make your way to ", "Set your flippers toward ", "Head for "}},
    {"Fly to ", {"Catch a flight to ", "Take wing to "}},
    {"Hearth to ", {"Hearthstone back to ", "Zip home to "}},
    {"Teleport to ", {"Blink over to ", "Teleport over to "}},
    {"Return to ", {"Head back to ", "Swim on back to "}},
    {"Go back to ", {"Head back to "}},
    {"Go to ", {"Waddle over to ", "Head over to "}},
    {"Go ", {"Waddle ", "Head "}},
    {"Head back to ", {"Make your way back to "}},
    {"Head to ", {"Make for ", "Paddle to "}},
    {"Head ", {"Make your way "}},
    {"Run back to ", {"Hurry back to "}},
    {"Run to ", {"Hurry over to ", "Scurry to "}},
    {"Run ", {"Hurry ", "Scurry "}},
    {"Walk to ", {"Stroll over to "}},
    {"Move to ", {"Shuffle over to "}},
    {"Proceed to ", {"Move along to "}},
    {"Swim to ", {"Paddle to "}},
    {"Swim ", {"Paddle "}},
    {"Jump off the ", {"Hop off the ", "Leap from the "}},
    {"Jump down", {"Hop down"}},
    {"Jump ", {"Hop "}},
    {"Enter the ", {"Step into the ", "Duck into the "}},
    {"Enter ", {"Step into "}},
    {"Exit the ", {"Slip out of the ", "Step out of the "}},
    {"Exit ", {"Slip out of "}},
    {"Leave the ", {"Head out of the "}},
    {"Take the boat", {"Hop aboard the boat", "Catch the boat"}},
    {"Take the Zeppelin", {"Hop aboard the Zeppelin"}}, {"Take the zeppelin", {"Hop aboard the zeppelin"}},
    {"Take the tram", {"Ride the tram"}}, {"Take the Tram", {"Ride the Tram"}},
    {"Take the lift", {"Ride the lift"}},
    {"Take the purple portal", {"Hop through the purple portal"}},
    {"Take the portal", {"Hop through the portal"}},
    {"Buy and equip ", {"Purchase and put on "}},
    {"Buy ", {"Purchase ", "Shop for "}},
    {"Restock on ", {"Stock up on "}},
    {"Restock ", {"Stock up on "}},
    {"Sell your junk", {"Sell off your pocket clutter", "Unload your junk"}},
    {"Vendor trash", {"Sell your junk"}}, {"Vendor Trash", {"Sell your junk"}},
    {"Click here ", {"Tap here "}},
    {"CLICK HERE", {"TAP HERE"}}, {"Click HERE", {"Tap HERE"}},
    {"Click on the ", {"Give a poke to the ", "Tap on the "}},
    {"Click on ", {"Tap on "}},
    {"Click the ", {"Poke the ", "Tap the "}},
    {"Click it", {"Give it a poke"}},
    {"Click ", {"Tap "}},
    {"Use it", {"Put it to use"}},
    {"Use the ", {"Make use of the ", "Break out the "}},
    {"Use ", {"Make use of "}},
    {"Open the ", {"Pop open the ", "Crack open the "}},
    {"Get the ", {"Grab the ", "Fetch the "}},
    {"Equip the ", {"Put on the ", "Gear up with the "}},
    {"Equip your ", {"Put on your "}},
    {"Equip ", {"Gear up with "}},
    {"Withdraw the following", {"Fish the following out of the bank"}},
    {"Withdraw ", {"Take out "}},
    {"Deposit the following", {"Stash the following in the bank"}},
    {"Deposit ", {"Stash "}},
    {"Destroy ", {"Toss out "}}, {"Delete ", {"Toss out "}},
    {"Save ", {"Hang on to "}},
    {"Create ", {"Whip up "}},
    {"Set your Hearthstone", {"Bind your Hearthstone"}},
    {"Skip this step", {"Skip this one", "Pass over this step"}},
    {"Grind to level ", {"Fight your way to level ", "Keep battling until level "}},
    {"Grind ", {"Keep fighting "}},
    {"Die and respawn", {"Take the spirit shortcut: die and respawn", "Let them win this once: die and respawn"}},
    {"Wait for ", {"Hold on for "}},
    {"Follow the ", {"Stick to the ", "Trail along the "}},
    {"Continue ", {"Carry on "}},
    {"Avoid ", {"Steer clear of "}},
    {"Be careful as ", {"Watch your flippers, because ", "Careful now, since "}},
    {"Be careful of ", {"Watch out for ", "Keep an eye out for "}},
    {"Be careful! ", {"Careful now! "}},
    {"Be careful ", {"Take care "}},
    {"Make sure to ", {"Be sure to ", "Remember to "}},
    {"Make sure you ", {"Check that you ", "Be sure you "}},
    {"Make sure ", {"Check that "}},
    {"Ensure ", {"Check that "}},
    {"Remember to ", {"Don't forget to "}},
    {"Don't forget to ", {"Remember to "}},
    {"Do not ", {"Don't "}}, {"Do NOT ", {"Do not, repeat NOT, "}},
    {"Try to ", {"Do your best to "}},
    {"You can ", {"You're free to ", "Feel free to "}},
    {"You may ", {"You're welcome to "}},
    {"You need to ", {"You'll have to "}},
    {"You need ", {"You'll want "}},
    {"You will ", {"You'll "}},
    {"You should ", {"It's wise to "}},
    {"This quest is ", {"This one is ", "This quest happens to be "}},
    {"This is a ", {"Here's a ", "This one's a "}},
    {"This will ", {"Doing so will "}},
    {"This has a ", {"There's a "}},
}

-- Indexed by first word, longest phrase first, so "Click on the " is tried before "Click ".
local byWord = {}
for _, rule in ipairs(openers) do
    local word = rule[1]:match("^[%a']+")
    byWord[word] = byWord[word] or {}
    table.insert(byWord[word], rule)
end
for _, rules in pairs(byWord) do table.sort(rules, function(a, b) return #a[1] > #b[1] end) end

-- A small aside now and then. Nib has opinions, but the map comes first.
local asides = {" Mrrgl!", " Trust the map.", " I checked this bit twice.", " Easy as fish pie.", " Mind your flippers.", " Snack break after, yes?"}
local ASIDE_EVERY = 23

local function hash(value)
    local h = #value
    for i = 1, #value do h = (h * 31 + value:byte(i)) % 2147483647 end
    return h
end

-- Markup that may sit in front of a sentence without being part of it: spacing, an icon, a colour tag, a colour reset.
local function skipMarkup(raw, at)
    while true do
        local _, to = raw:find("^%s+", at)
        if not to then _, to = raw:find("^|cRXP_%u+_", at) end
        if not to then _, to = raw:find("^|[Tt][^|]*|[Tt]", at) end
        if not to then _, to = raw:find("^|r", at) end
        if not to then return at end
        at = to + 1
    end
end

function Voice.Enabled()
    return not (A.db and A.db.trailVoice == false)
end

-- Rewords one description. The raw text still carries the route's colour and icon tags; they pass through unchanged.
function Voice.Say(raw)
    if type(raw) ~= "string" or raw == "" then return raw end
    local first = skipMarkup(raw, 1)
    local word = raw:match("^[%a']+", first)
    if not word or plain[word] then return raw end
    local seed = hash(raw)
    local parts, copied, at, changed = {}, 1, first, false
    while at <= #raw do
        local opener = raw:match("^[%a']+", at)
        local used, length, tight
        for _, rule in ipairs(opener and byWord[opener] or {}) do
            local from = rule[1]
            if from:sub(-1) == " " then
                -- The route sometimes closes a colour right after the phrase ("Talk to|r Name"), with no space before it.
                local stem = from:sub(1, -2)
                if raw:sub(at, at + #stem - 1) == stem then
                    if raw:sub(at + #stem, at + #stem) == " " then used, length = rule, #from; break end
                    if raw:find("^|r", at + #stem) then used, length, tight = rule, #stem, true; break end
                end
            -- A phrase without a trailing space must end at a word boundary: "Click it" must not match "Click items".
            elseif raw:sub(at, at + #from - 1) == from and not raw:find("^%a", at + #from) then
                used, length = rule, #from
                break
            end
        end
        if used then
            local phrase = used[2][(seed + at) % #used[2] + 1]
            parts[#parts + 1] = raw:sub(copied, at - 1)
            parts[#parts + 1] = tight and phrase:sub(1, -2) or phrase
            copied = at + length
            changed = true
        end
        -- On to the next sentence: past the next full stop, exclamation or question mark that is followed by a space.
        local _, stop = raw:find("[%.!%?]%s+", math.max(at, copied))
        if not stop then break end
        at = skipMarkup(raw, stop + 1)
    end
    if not changed then return raw end
    parts[#parts + 1] = raw:sub(copied)
    local said = table.concat(parts)
    -- Longer instructions sometimes earn a remark. The choice depends only on the text, so it never flickers.
    if #said > 60 and seed % ASIDE_EVERY == 0 and not said:find("[:;,]%s*$") then
        -- Finish the instruction's own sentence first if it stopped without punctuation.
        local ending = said:gsub("|r%s*$", ""):match("(%S)%s*$")
        said = said .. ((ending == "." or ending == "!" or ending == "?") and "" or ".") .. asides[seed % #asides + 1]
    end
    return said
end
