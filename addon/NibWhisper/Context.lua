local _, addon = ...
addon = addon or _G.NibWhisper
local P = addon.Protocol
local C = {}
addon.Context = C
local unpackValues = unpack or table.unpack

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpackValues(results, 2)
end
C.Call = call

function C.GetRXP()
    if not _G.LibStub then return nil end
    local ok, library = pcall(function() return _G.LibStub("AceAddon-3.0", true) end)
    if not ok or not library or type(library.GetAddon) ~= "function" then return nil end
    return call(library.GetAddon, library, "RXPGuides", true)
end

local function safeNumber(n)
    return P.IsFinite(n) and n or nil
end

function C.Player()
    local className, class = call(UnitClass, "player")
    local raceName, race = call(UnitRace, "player")
    local player = {
        class = P.SanitizeText(class or className or "unknown", 48),
        race = P.SanitizeText(race or raceName or "unknown", 48),
        faction = P.SanitizeText(call(UnitFactionGroup, "player") or "unknown", 48),
        level = safeNumber(call(UnitLevel, "player")),
        xp = safeNumber(call(UnitXP, "player")),
        xpMax = safeNumber(call(UnitXPMax, "player")),
        restedXP = safeNumber(call(GetXPExhaustion)),
        zone = P.SanitizeText(call(GetRealZoneText) or call(GetZoneText) or "", 120),
        subzone = P.SanitizeText(call(GetSubZoneText) or "", 120),
        dead = call(UnitIsDeadOrGhost, "player") == true,
        inCombat = call(InCombatLockdown) == true,
        coordinateUnits = "percent",
    }
    if C_Map then
        player.mapID = safeNumber(call(C_Map.GetBestMapForUnit, "player"))
        local pos = player.mapID and call(C_Map.GetPlayerMapPosition, player.mapID, "player")
        if pos then
            local x, y
            if type(pos.GetXY) == "function" then x, y = call(pos.GetXY, pos)
            else x, y = pos.x, pos.y end
            if P.IsFinite(x) and P.IsFinite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                player.x, player.y = x * 100, y * 100
            end
        end
    end
    return player
end

function C.Client()
    local version, build, date, interface = call(GetBuildInfo)
    return {
        version = P.SanitizeText(version or "unknown", 40),
        build = P.SanitizeText(tostring(build or "unknown"), 40),
        interface = tonumber(interface),
        locale = P.SanitizeText(call(GetLocale) or "unknown", 16),
        projectID = safeNumber(WOW_PROJECT_ID),
        game = WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT and "FOREVER" or "unverified",
    }
end

function C.Quests()
    local result = { active = P.Array(), completedIds = P.Array(), completionCoverage = "unknown", activeCoverage = "unknown" }
    local q = C_QuestLog or {}
    local count, total = call(q.GetNumQuestLogEntries or GetNumQuestLogEntries)
    if P.IsFinite(count) and count >= 0 then
        result.activeCoverage = "complete"
        result.reportedQuestCount = safeNumber(total)
        if count > 200 then result.activeCoverage = "partial" end
        for index = 1, math.min(count, 200) do
            local info
            if q.GetInfo then info = call(q.GetInfo, index)
            elseif GetQuestLogTitle then
                local title, level, group, isHeader, isCollapsed, complete, frequency, id = call(GetQuestLogTitle, index)
                if title then info = { title = title, level = level, suggestedGroup = group, isHeader = isHeader, isCollapsed = isCollapsed, isComplete = complete == 1, questID = id } end
            end
            if type(info) ~= "table" then result.activeCoverage = "partial"
            elseif info.isHeader then
                if info.isCollapsed then result.activeCoverage = "partial" end
            elseif P.IsPositiveInteger(info.questID) then
                local entry = { id = info.questID, title = P.SanitizeText(info.title or "", 240), level = safeNumber(info.level), objectives = P.Array() }
                local complete = call(q.ReadyForTurnIn or q.IsComplete or IsQuestComplete, info.questID)
                if complete ~= nil then entry.readyForTurnIn = complete == true or complete == 1
                elseif info.isComplete ~= nil then entry.readyForTurnIn = info.isComplete == true end
                local objectives = call(q.GetQuestObjectives, info.questID)
                if type(objectives) == "table" then
                    for i = 1, math.min(#objectives, 20) do
                        local objective = objectives[i]
                        if type(objective) == "table" then
                            entry.objectives[#entry.objectives + 1] = {
                                text = P.SanitizeText(objective.text or "", 300),
                                type = P.SanitizeText(objective.type or "", 32),
                                finished = objective.finished == true,
                                fulfilled = safeNumber(objective.numFulfilled),
                                required = safeNumber(objective.numRequired),
                            }
                        end
                    end
                else
                    local n = call(GetNumQuestLeaderBoards, index)
                    if P.IsFinite(n) then
                        for i = 1, math.min(n, 20) do
                            local text, kind, finished = call(GetQuestLogLeaderBoard, i, index)
                            if type(text) == "string" then entry.objectives[#entry.objectives + 1] = { text = P.SanitizeText(text, 300), type = P.SanitizeText(kind or "", 32), finished = finished == true or finished == 1 } end
                        end
                    else entry.objectiveCoverage = "unknown" end
                end
                result.active[#result.active + 1] = entry
            else result.activeCoverage = "partial" end
        end
    end
    local completed = call(q.GetAllCompletedQuestIDs)
    local seen = {}
    if type(completed) == "table" then
        result.completionCoverage = "complete"
        for _, id in ipairs(completed) do if P.IsPositiveInteger(id) then seen[id] = true else result.completionCoverage = "partial" end end
    else
        completed = call(GetQuestsCompleted)
        if type(completed) == "table" then
            result.completionCoverage = "partial"
            result.completionCoverageReason = "Legacy completion cache; full server history has not been verified."
            for id, done in pairs(completed) do if done and P.IsPositiveInteger(id) then seen[id] = true end end
        end
    end
    for id in pairs(addon.observedTurnIns or {}) do if P.IsPositiveInteger(id) then seen[id] = true end end
    for id in pairs(seen) do result.completedIds[#result.completedIds + 1] = id end
    table.sort(result.completedIds)
    if #result.completedIds > 8000 then
        while #result.completedIds > 8000 do table.remove(result.completedIds) end
        result.completionCoverage = "partial"
        result.completionCoverageReason = "Completion history capped to keep the request small."
    end
    return result
end

local professionIDs = { [171] = true, [164] = true, [333] = true, [202] = true, [182] = true, [165] = true, [186] = true, [393] = true, [197] = true, [185] = true, [129] = true, [356] = true, [755] = true, [773] = true, [794] = true }
local professionSpells = { 2259, 2018, 7411, 4036, 2366, 2108, 2575, 8613, 3908, 2550, 3273, 7620, 25229, 45357, 78670 }

function C.Professions()
    local result, seen, names = P.Array(), {}, {}
    local coverage = "complete"
    if GetProfessions and GetProfessionInfo then
        local indexes = { call(GetProfessions) }
        for _, index in pairs(indexes) do
            local name, _, rank, maxRank, _, _, id = call(GetProfessionInfo, index)
            if type(name) == "string" and P.IsFinite(rank) then
                result[#result + 1] = { name = P.SanitizeText(name, 96), rank = rank, maxRank = safeNumber(maxRank), skillID = safeNumber(id) }
                seen[name] = true
            end
        end
    end
    for _, id in ipairs(professionSpells) do
        local info = C_Spell and call(C_Spell.GetSpellInfo, id) or call(GetSpellInfo, id)
        local name = type(info) == "table" and info.name or info
        if type(name) == "string" then names[name] = true end
    end
    local s = C_SkillInfo or {}
    local count = call(s.GetNumSkillLines or GetNumSkillLines)
    if P.IsFinite(count) then
        for i = 1, math.min(count, 200) do
            local name, header, collapsed, rank, _, _, maxRank = call(s.GetSkillLineInfo or GetSkillLineInfo, i)
            local id
            if type(name) == "table" then
                local info = name
                name, header, collapsed, rank, maxRank, id = info.name, info.isHeader, info.isCollapsed, info.rank, info.maxRank, info.skillID
            end
            if header and collapsed then coverage = "partial" end
            if type(name) == "string" and not header and not seen[name] and (professionIDs[id] or names[name]) then
                result[#result + 1] = { name = P.SanitizeText(name, 96), rank = safeNumber(rank), maxRank = safeNumber(maxRank), skillID = safeNumber(id) }
                seen[name] = true
            end
        end
    elseif #result == 0 then coverage = "unknown" end
    return result, coverage
end

function C.Addons()
    local result = P.Array()
    local a = C_AddOns or {}
    local count = call(a.GetNumAddOns or GetNumAddOns)
    if not P.IsFinite(count) then return result, "unknown" end
    for i = 1, math.min(count, 250) do
        local name, title = call(a.GetAddOnInfo or GetAddOnInfo, i)
        name = name or call(a.GetAddOnName, i)
        if type(name) == "string" and not name:match("^NibWhisperReply%d%d%d$") then
            result[#result + 1] = {
                name = P.SanitizeText(name, 96),
                title = P.SanitizeText(title or name, 160),
                version = P.SanitizeText(call(a.GetAddOnMetadata or GetAddOnMetadata, name, "Version") or "", 48),
                loaded = call(a.IsAddOnLoaded or IsAddOnLoaded, name) == true,
            }
        end
    end
    return result, count > 250 and "partial" or "complete"
end

function C.RestedXP()
    local rxp = C.GetRXP()
    local saved = type(RXPCData) == "table" and RXPCData or {}
    if not rxp then return { available = false, steps = P.Array(), reason = "RestedXP is not loaded or its adapter is unavailable." } end
    local guide = type(rxp.currentGuide) == "table" and rxp.currentGuide or nil
    local result = { available = true, steps = P.Array(), adapter = "RestedXP v4.11.35 fields" }
    if not guide or guide.empty then result.reason = "No active RestedXP guide."; return result end
    result.guide = { name = P.SanitizeText(guide.name or saved.currentGuideName or "", 200), group = P.SanitizeText(guide.group or saved.currentGuideGroup or "", 200), key = P.SanitizeText(guide.key or "", 400) }
    local progress = type(saved.guideProgress) == "table" and guide.key and saved.guideProgress[guide.key]
    local current = tonumber(type(progress) == "table" and progress.step or saved.currentStep) or 1
    current = math.max(1, math.floor(current))
    result.currentStep = current
    result.currentStepId = type(progress) == "table" and progress.stepId or saved.currentStepId
    if type(result.currentStepId) ~= "string" and type(result.currentStepId) ~= "number" then result.currentStepId = nil end
    local steps = type(guide.steps) == "table" and guide.steps or {}
    result.totalSteps = #steps
    local indexes, selected = {}, {}
    local function selectStep(i) if i >= 1 and i <= #steps and not selected[i] and #indexes < 8 then selected[i] = true; indexes[#indexes + 1] = i end end
    for i = math.max(1, current - 1), math.min(#steps, current + 3) do selectStep(i) end
    for i = 1, math.min(current - 1, #steps) do if type(steps[i]) == "table" and steps[i].active and steps[i].sticky then selectStep(i) end end
    table.sort(indexes)
    for _, i in ipairs(indexes) do
        local step = steps[i]
        if type(step) == "table" then
            local entry = { index = i, active = step.active == true, sticky = step.sticky == true, completed = step.completed == true, elements = P.Array(), questIds = P.Array() }
            local elements = type(step.elements) == "table" and step.elements or {}
            local seenIDs = {}
            for k = 1, math.min(#elements, 12) do
                local element = elements[k]
                if type(element) == "table" then
                    local text = element.text or element.rawtext or element.tooltipText
                    local questID = P.IsPositiveInteger(element.questId) and element.questId or nil
                    if questID and not seenIDs[questID] then seenIDs[questID] = true; entry.questIds[#entry.questIds + 1] = questID end
                    entry.elements[#entry.elements + 1] = { text = P.SanitizeText(text or "", 600), questID = questID, tag = P.SanitizeText(element.tag or "", 48), completed = element.completed == true, skipped = element.skip == true }
                end
            end
            result.steps[#result.steps + 1] = entry
        end
    end
    return result
end

function C.Snapshot(question)
    local professions, professionCoverage = C.Professions()
    local addons, addonCoverage = C.Addons()
    return {
        player = C.Player(), client = C.Client(), quests = C.Quests(), professions = professions,
        professionCoverage = professionCoverage, addons = addons, addonCoverage = addonCoverage,
        restedXP = C.RestedXP(), nibTrail = addon.Trail and addon.Trail:Snapshot(),
        inventory = addon.CharacterData and addon.db and addon.CharacterData:Snapshot(question),
    }
end

function addon:Snapshot(question) return C.Snapshot(question) end
