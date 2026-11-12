local addonName, addon = ...
addon = addon or _G.NibWhisper
local P, UI, C = addon.Protocol, addon.UI, addon.Context
addon.VERSION = "0.7.5"
addon.nextSlot = 1
addon.sequence = 0
addon.observedTurnIns = {}
local moodAllowed = {happy = true, thinking = true, concerned = true, excited = true}
local intentAllowed = {advice = true, roleplay = true, off_topic = true, needs_context = true}

local function now()
    local value = C.Call(GetServerTime) or C.Call(time) or 0
    return P.IsFinite(value) and math.floor(value) or 0
end
local function uptime() return C.Call(GetTime) or 0 end
local function nonempty(value, limit)
    return type(value) == "string" and #value <= limit and value:find("%S") ~= nil
end

function addon:Notice(text, isError)
    UI:SetStatus(text, isError)
    if isError and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff8fe3bfNib:|r " .. P.SanitizeText(text, 300), 1, 0.8, 0.65)
    end
end

local function looksLikeKey(text)
    local key = text:match("sk%-[%w_%-]+")
    local auth = text:match("AQ%.[%w_%-]+")
    return (key and #key >= 20) or (auth and #auth >= 23) or text:match("AIza[%w_%-]+") ~= nil
        or text:find("OPENAI_API_KEY", 1, true) ~= nil or text:find("GEMINI_API_KEY", 1, true) ~= nil
end

function addon:Remember(role, text)
    if not self.charDB or (role ~= "user" and role ~= "assistant" and role ~= "system") then return end
    text = P.SanitizeText(text, 8000)
    if text == "" or looksLikeKey(text) then return end
    local history = self.charDB.history
    history[#history + 1] = {role = role, text = text, at = now()}
    while #history > 80 do table.remove(history, 1) end
    UI:AddMessage(role, text)
end

function addon:ClearOptical()
    if self.Optical and type(self.Optical.ClearPacket) == "function" then pcall(self.Optical.ClearPacket, self.Optical) end
end

function addon:PublishOptical()
    if not self.pending or not self.db or not self.db.opticalEnabled then return false end
    if not self.Optical or type(self.Optical.SetPacket) ~= "function" then
        self:Notice("The automatic bridge isn't available. Use Copy / paste.", true)
        return false
    end
    local ok, result = pcall(self.Optical.SetPacket, self.Optical, self.pending.packet, self.pending.requestId)
    if not ok or result == false then
        self:Notice("I couldn't raise the signal flags. Use Copy / paste.", true)
        return false
    end
    local pending = self.pending
    -- With reply files the receipt is found on the next rung the game tries, so allow a little longer for it.
    pending.signalUntil = uptime() + math.max(10, 5 + math.ceil(#pending.packet / 512) * 0.40) + (pending.font and 15 or 0)
    pending.nextPollAt = uptime() + 1.5
    return true
end

-- Reserves reply files for one automatic request. nil means the helper answers through the older reply slots.
function addon:ReserveReply()
    return self.FontSlots and self.FontSlots:Reserve() or nil
end

function addon:ConnectGemini()
    if C.Call(InCombatLockdown) then return false, "Try connecting after combat." end
    if self.pending and self.pending.kind ~= "trail" and not self.pending.manualOnly then return false, "Wait for the current request or cancel it in chat." end
    if self.pending then self.pending = nil; self:ClearOptical() end
    self.sequence = self.sequence + 1
    local id = self.session .. "-connect-" .. self.sequence
    local capturedAt = now()
    local font = self:ReserveReply()
    local packet = P.EncodePacket("NIBC1", {schema = 1, requestId = id, capturedAt = capturedAt, source = "clipboard", replyFont = font})
    self.db.chatMode = self:GetChatMode()
    self.db.opticalEnabled = true
    self.pending = {kind = "connect", requestId = id, capturedAt = capturedAt, packet = packet, startedAt = uptime(), nextPollAt = uptime(), pollIndex = 1, font = font}
    if self:PublishOptical() then return true end
    self.pending = nil
    return false, "The Windows helper connection could not start."
end

function addon:ReceiveBridgeState(prefix, packet)
    local pending = self.pending
    if not pending then return false end
    local message = P.DecodePacket(prefix, packet)
    if type(message) ~= "table" or message.schema ~= 1 or message.requestId ~= pending.requestId or message.capturedAt ~= pending.capturedAt then return false end
    if prefix == "NIBA1" then
        if pending.received then return false end
        pending.received = true
        pending.signalUntil = nil
        pending.replyUntil = uptime() + (pending.kind == "connect" and 25 or 125)
        self:ClearOptical()
        if pending.kind == "connect" then UI:SetSetupStatus("Checking your key with Gemini…")
        elseif pending.kind ~= "trail" then self:Notice("Gemini is preparing a reply…") end
        return true
    end
    if pending.kind ~= "connect" then return false end
    self.pending = nil
    self:ClearOptical()
    if message.connected == true then
        self.db.geminiLinked = true
        self:SetChatMode("automatic")
        UI:RefreshOptions()
        UI:SetSetupStatus("Gemini connected. You can ask Nib now.")
        self:Notice("Gemini connected. Ask Nib about your adventure.")
    else
        UI:SetSetupStatus(nonempty(message.error, 240) and message.error or "Gemini could not verify that key.", true)
    end
    return true
end

function addon:SetOpticalEnabled(enabled)
    self.db.opticalEnabled = enabled == true
    UI:UpdateBridgeMode()
    if enabled then
        self:Notice("Auto bridge on. Start the companion and keep the signal corner visible.")
        if self.pending then self.pending.manualOnly = false; self:PublishOptical() end
    else
        self:ClearOptical()
        self:Notice("Manual bridge. Copy the request to the companion and paste its reply here.")
    end
end

function addon:GetChatMode()
    return self.db.chatMode or (self.db.opticalEnabled and "automatic" or "localGuide")
end

function addon:SetChatMode(mode)
    self.db.chatMode = mode
    if mode == "automatic" then self:SetOpticalEnabled(true)
    else
        if self.pending and self.pending.kind ~= "trail" then
            self.pending.manualOnly = true
            self:ClearOptical()
        end
        UI:UpdateBridgeMode()
        self:Notice(mode == "manual" and "Copy questions and replies through the companion." or "Guide chat is ready. Try Next objective or Quest log.")
    end
end

function addon:GuideAnswer(question)
    local query = question:lower()
    if query:find("profession", 1, true) or query:find("skill rank", 1, true) then
        local professions = C.Professions()
        local lines = {}
        for _, skill in ipairs(professions) do
            local rank = skill.rank and tostring(skill.rank) or "?"
            if skill.maxRank then rank = rank .. "/" .. skill.maxRank end
            lines[#lines + 1] = skill.name .. "  " .. rank
        end
        return #lines > 0 and "Here are the profession ranks I can see.\n\n" .. table.concat(lines, "\n") or "Your profession ranks aren't visible in my notes right now."
    end
    if query:find("quest", 1, true) and (query:find("log", 1, true) or query:find("am i on", 1, true) or query:find("active", 1, true)) then
        local quests = C.Quests()
        local lines = {}
        for i = 1, math.min(8, #quests.active) do
            local quest = quests.active[i]
            lines[#lines + 1] = quest.title ~= "" and quest.title or ("Quest " .. quest.id)
            for _, objective in ipairs(quest.objectives or {}) do
                if not objective.finished and objective.text ~= "" then lines[#lines + 1] = "  • " .. objective.text end
            end
        end
        if #quests.active > 8 then lines[#lines + 1] = "More quests are listed in your quest log." end
        return #lines > 0 and table.concat(lines, "\n") or "I don't see any active quests in the notes I can read."
    end
    if query:find("drop rate", 1, true) or query:find("chance to drop", 1, true) then
        return "I don't have drop rates in guide chat. Use Gemini setup for more context, or check the Forever item page on Wowhead."
    end
    if query:find("next", 1, true) or query:find("where", 1, true) or query:find("objective", 1, true) or query:find("current", 1, true) or query:find("stuck", 1, true) then
        local trail = self.Trail and self.Trail:Snapshot()
        if not self.Trail then return "The leveling guide is switched off. Enable Nib Whisper: Leveling Guide in your AddOns list and I can read your next objective." end
        if not trail then return "Open /nib trail and choose a chapter under Routes. Then I can read your next objective and waypoint." end
        local step = trail.steps[1]
        if not step then return "Mrrgl! This chapter is complete. Open Nib Trail and choose Next route." end
        local lines = {trail.guide.name .. " · Step " .. trail.currentStep}
        for _, element in ipairs(step.elements) do lines[#lines + 1] = element.text end
        if step.point then
            local info = C.Call(C_Map and C_Map.GetMapInfo, step.point.mapID)
            lines[#lines + 1] = string.format("Waypoint: %s (%.2f, %.2f)", info and info.name or ("map " .. step.point.mapID), step.point.x, step.point.y)
        end
        return table.concat(lines, "\n")
    end
    return "Mrrgl! In guide chat I can read your next objective, quest log, and profession ranks. For other Warcraft questions and tavern talk, click Gemini setup."
end

function addon:Ask(text)
    if not self.Assistant then self:Notice("Enable Nib Whisper: AI Assistant in your AddOns list to chat with Nib.", true); return false end
    local mode = self:GetChatMode()
    if mode ~= "localGuide" then return self:SendQuestion(text, mode) end
    if not nonempty(text, P.MAX_QUESTION) or not P.ValidUTF8(text) then self:Notice("Enter a question of up to 2,000 bytes.", true); return false end
    if looksLikeKey(text) then self:Notice("Open Gemini setup to connect your copied key.", true); return false end
    if self.pending and self.pending.kind ~= "trail" then self:CancelPending() end
    UI:ShowChat()
    self:Remember("user", text)
    local ok, answer = pcall(self.GuideAnswer, self, text)
    answer = ok and answer or "I couldn't read those notes just now. Try another prompt or reopen the guide."
    self:Remember("system", answer)
    UI:SetReply({answer = answer})
    self:Notice("Guide chat · using your current game data")
    return true
end

function addon:GetHistoryForRequest()
    local result, history = P.Array(), self.charDB and self.charDB.history or {}
    for i = math.max(1, #history - 11), #history do
        local entry = history[i]
        if entry.role == "user" or entry.role == "assistant" then result[#result + 1] = {role = entry.role, text = P.TruncateUTF8(entry.text, 1200)} end
    end
    return result
end

function addon:BuildRequest(question, budget, font)
    local context = self:Snapshot(question)
    self.sequence = self.sequence + 1
    local request = {schema = 1, requestId = self.session .. "-" .. tostring(self.sequence), capturedAt = now(), question = question, context = context, history = self:GetHistoryForRequest(), replyFont = font}
    local ok, packet = pcall(P.EncodePacket, "NIBQ1", request)
    local function tooLarge() return not ok or (budget and #packet > budget) end
    -- Context can be large on veterans. Keep coverage honest whenever reducing it.
    while tooLarge() and #request.history > 0 do table.remove(request.history, 1); ok, packet = pcall(P.EncodePacket, "NIBQ1", request) end
    while tooLarge() and #context.quests.completedIds > 100 do
        local target = math.floor(#context.quests.completedIds / 2)
        while #context.quests.completedIds > target do table.remove(context.quests.completedIds) end
        context.quests.completionCoverage = "partial"
        context.quests.completionCoverageReason = "Completed quest history was trimmed for transport."
        ok, packet = pcall(P.EncodePacket, "NIBQ1", request)
    end
    while tooLarge() and #context.restedXP.steps > 1 do
        table.remove(context.restedXP.steps)
        context.restedXP.stepCoverage = "partial"
        ok, packet = pcall(P.EncodePacket, "NIBQ1", request)
    end
    while budget and tooLarge() and #context.quests.active > 10 do
        local target = math.max(10, math.floor(#context.quests.active / 2))
        while #context.quests.active > target do table.remove(context.quests.active) end
        context.quests.activeCoverage = "partial"
        ok, packet = pcall(P.EncodePacket, "NIBQ1", request)
    end
    while tooLarge() and context.inventory and self.CharacterData and self.CharacterData.Trim(context.inventory) do
        ok, packet = pcall(P.EncodePacket, "NIBQ1", request)
    end
    if not ok then return nil, nil, "Your context is too large or couldn't be encoded. Please try again after a UI reload." end
    return request, packet
end

function addon:SendQuestion(text, mode)
    if not self.initialized then return false end
    if self.pending and self.pending.kind=="trail" then self.pending=nil;self:ClearOptical();if self.Trail then self.Trail.nextSync=uptime()+35 end end
    if self.pending and self.pending.manualOnly and mode == "automatic" then self.pending = nil end
    if self.pending then self:Notice("One question is already in the satchel. Wait, or click Cancel first.", true); return false end
    if not nonempty(text, P.MAX_QUESTION) or not P.ValidUTF8(text) then self:Notice("Ask me a question of up to 2,000 bytes.", true); return false end
    if looksLikeKey(text) then self:Notice("Use Gemini setup for API keys.", true); return false end
    text = P.SanitizeText(text, P.MAX_QUESTION):match("^%s*(.-)%s*$")
    if text == "" then return false end
    local manual = mode == "manual" or not self.db.opticalEnabled
    local font = not manual and self:ReserveReply() or nil
    local success, request, packet, err = pcall(self.BuildRequest, self, text, mode == "automatic" and 26000 or nil, font)
    if not success or not request then self:Notice(err or "I couldn't read your game context. Please try again.", true); return false end
    self.pending = {requestId = request.requestId, capturedAt = request.capturedAt, packet = packet, startedAt = uptime(), nextPollAt = uptime() + 5, pollIndex = 1, manualOnly = manual, font = font}
    self:Remember("user", text)
    UI:ShowChat()
    UI:SetReply(nil)
    if not manual and self:PublishOptical() then self:Notice("Sending to the Nib helper…")
    else
        self.pending.manualOnly = true
        self:Notice("Request ready. Copy it to the companion, then paste the reply.")
        UI:ShowTransfer(packet)
    end
    return true, packet
end

local function safeURL(url)
    return type(url) == "string" and #url <= 2048 and url:match("^https://[%w%.%-]+[/:?]?[^%s]*$") ~= nil
        and not url:find("[%z\1-\31\127]") and not url:find("|", 1, true)
end

function P.ValidateResponse(reply, pending)
    if type(reply) ~= "table" or P.IsArray(reply) or reply == P.NULL then return nil, "That isn't a reply object." end
    if not pending then return nil, "No question is waiting. Old or duplicate replies are not imported." end
    if reply.schema ~= 1 then return nil, "That reply uses an unsupported packet version." end
    if type(reply.requestId) ~= "string" or reply.requestId ~= pending.requestId then return nil, "That reply belongs to a different question or character session." end
    if not P.IsFinite(reply.capturedAt) or reply.capturedAt ~= pending.capturedAt then return nil, "That reply doesn't match this question's context snapshot." end
    if not nonempty(reply.answer, 8000) or not P.ValidUTF8(reply.answer) then return nil, "The answer is empty, invalid, or longer than 8,000 bytes." end
    if not moodAllowed[reply.mood] or not intentAllowed[reply.intent] then return nil, "The reply's mood or intent is invalid." end
    local sources, actions = reply.sources, reply.actions
    if sources == nil then sources = P.Array() end
    if actions == nil then actions = P.Array() end
    if not P.IsArray(sources) or #sources > 6 or not P.IsArray(actions) or #actions > 3 then return nil, "The reply contains too many or invalid source/action entries." end
    local out = {schema = 1, requestId = reply.requestId, capturedAt = reply.capturedAt, answer = P.SanitizeText(reply.answer, 8000), mood = reply.mood, intent = reply.intent, sources = P.Array(), actions = P.Array()}
    for _, source in ipairs(sources) do
        if type(source) ~= "table" or not nonempty(source.title, 240) then return nil, "The reply includes an invalid source." end
        local isLocalGuide = source.url == "" and type(source.id) == "string" and source.id:match("^rxp:[0-9a-f]+:%d+$") ~= nil
        if not isLocalGuide and not safeURL(source.url) then return nil, "The reply includes an invalid source URL." end
        if type(source.id) ~= "string" and not P.IsPositiveInteger(source.id) then return nil, "A source identifier is missing." end
        if #tostring(source.id) > 100 then return nil, "A source identifier is too long." end
        out.sources[#out.sources + 1] = {id = tostring(source.id), title = P.SanitizeText(source.title, 240), url = source.url}
    end
    for _, action in ipairs(actions) do
        if type(action) ~= "table" or type(action.title) ~= "string" or #action.title > 160 then return nil, "The reply includes an invalid action." end
        local clean = {type = action.type, title = P.SanitizeText(action.title, 160)}
        if not clean.title:find("%S") then clean.title = action.type == "waypoint" and "Place waypoint" or action.type == "quest" and "Open quest" or "Select guide" end
        if action.type == "waypoint" then
            if not P.IsPositiveInteger(action.mapID) or not P.IsFinite(action.x) or not P.IsFinite(action.y)
                or action.x < 0 or action.x > 100 or action.y < 0 or action.y > 100 then return nil, "Waypoint coordinates must use a map ID and percentages from 0 to 100." end
            clean.mapID, clean.x, clean.y = action.mapID, action.x, action.y
        elseif action.type == "quest" then
            if not P.IsPositiveInteger(action.questID) then return nil, "The quest action has an invalid quest ID." end
            clean.questID = action.questID
        elseif action.type == "guide" or action.type == "trail" then
            if not nonempty(action.group, 200) or not nonempty(action.name, 200) then return nil, "The guide action has an invalid guide identity." end
            clean.group, clean.name = action.group, action.name
        else return nil, "The reply requests an unsupported action." end
        out.actions[#out.actions + 1] = clean
    end
    return out
end

function addon:ImportReply(packet, silent)
    if self.pending and self.pending.kind then return false,"There is no chat reply waiting." end
    local ok, decoded = pcall(P.DecodePacket, "NIBR1", packet)
    if not ok then return false, "I couldn't read that NIBR1 packet. Copy the complete reply from the companion." end
    local pending = self.pending
    if silent and pending and type(decoded) == "table" and decoded.schema == 1 and decoded.requestId == pending.requestId and decoded.capturedAt == pending.capturedAt and nonempty(decoded.error, 240) then
        pending.manualOnly = true
        self:ClearOptical()
        self:Notice(decoded.error, true)
        return true
    end
    local reply, err = P.ValidateResponse(decoded, self.pending)
    if not reply then return false, err end
    self.pending = nil
    self:ClearOptical()
    self:Remember("assistant", reply.answer)
    UI:SetReply(reply)
    self:Notice("AI reply received")
    if UI.chat and not UI.chat:IsShown() then UI:ShowChat() end
    return true, reply
end

-- Slot files contain a constant string argument, never model-authored Lua.
_G.NibWhisper_Receive = function(packet)
    if not addon.initialized or type(packet) ~= "string" then return false end
    local prefix = packet:sub(1,5)
    if prefix == "NIBA1" or prefix == "NIBK1" then
        local ok, accepted = pcall(addon.ReceiveBridgeState, addon, prefix, packet)
        return ok and accepted == true
    end
    if prefix=="NIBP1" and addon.Trail then local ok,accepted=pcall(addon.Trail.ImportSync,addon.Trail,packet);return ok and accepted==true end
    local ok, accepted = pcall(addon.ImportReply, addon, packet, true)
    return ok and accepted == true
end

function addon:CancelPending()
    if not self.pending then self:Notice("The satchel is empty. Ask away!"); return end
    if self.pending.kind == "connect" then UI:SetSetupStatus("Connection cancelled.") end
    self.pending = nil; self:ClearOptical()
    self:Notice("Question cancelled. A late reply will be ignored.")
end

function addon.GetOpticalState()
    return {packet = addon.pending and addon.pending.packet, requestId = addon.pending and addon.pending.requestId,
        session = addon.session, nextSlot = addon.nextSlot, enabled = addon.db and addon.db.opticalEnabled == true}
end

function addon:PollReplySlots()
    local pending = self.pending
    if not pending or not self.db.opticalEnabled or pending.manualOnly then return end
    local elapsed = uptime()
    local function fail(message)
        self:ClearOptical()
        if pending.kind == "connect" then self.pending = nil; UI:SetSetupStatus(message, true)
        elseif pending.kind == "trail" then pending.manualOnly = true
        else pending.manualOnly = true; self:Notice(message, true) end
    end
    local detail = pending.font and self.FontSlots and self.FontSlots:Describe(pending) or ""
    if pending.signalUntil and elapsed > pending.signalUntil then fail("No response from the Nib helper. Start Nib Helper, then try again." .. detail); return end
    if pending.replyUntil and elapsed > pending.replyUntil then fail("The request timed out. Try again." .. detail); return end
    if pending.font and self.FontSlots then
        -- Reply files: waiting on a file costs nothing, so it is checked every tick.
        local ok, problem = pcall(self.FontSlots.Poll, self.FontSlots, pending)
        if self.pending ~= pending then return end
        if not ok then fail("Nib could not read the reply file. Ask again, or use AI copy and paste.")
        elseif problem then fail(problem) end
        if pending.font then return end
    end
    if elapsed < pending.nextPollAt then return end
    if C.Call(InCombatLockdown) then return end
    local a = C_AddOns or {}
    local loader = a.LoadAddOn or LoadAddOn
    if type(loader) ~= "function" then fail("This game client cannot load Nib replies."); return end
    while self.nextSlot <= 200 and C.Call(a.IsAddOnLoaded or IsAddOnLoaded, string.format("NibWhisperReply%03d", self.nextSlot)) do self.nextSlot = self.nextSlot + 1 end
    if self.nextSlot > 200 then
        fail("Nib's reply slots are used. Type /reload and try again.")
        return
    end
    local slot = string.format("NibWhisperReply%03d", self.nextSlot)
    self.nextSlot = self.nextSlot + 1
    _G.NibWhisperReplyData = nil
    local ok, loaded, reason = pcall(loader, slot)
    if self.pending ~= pending then return end
    if not ok or not loaded then
        fail(self.FontSlots and self.FontSlots.spent and "Nib has used all its reply files for this session. Fully restart WoW to refill them."
            or "Nib's reply files aren't ready. Run Install-Nib.ps1, then fully restart WoW.")
        return
    end
    pending.pollIndex = pending.pollIndex + 1
    pending.nextPollAt = elapsed + (pending.received and (elapsed - pending.startedAt > 25 and 6 or 2.5) or 2)
end

function addon:ExecuteAction(action)
    if C.Call(InCombatLockdown) then return false, "Let the battle settle before using a map, quest, or guide action." end
    if type(action) ~= "table" then return false, "No action selected." end
    -- Revalidate at the click boundary. Model output never selects a Lua function.
    local candidate = {schema = 1, requestId = "click", capturedAt = 1, answer = "action", mood = "happy", intent = "advice", sources = P.Array(), actions = P.Array({action})}
    local validated, err = P.ValidateResponse(candidate, {requestId = "click", capturedAt = 1})
    if not validated then return false, err end
    action = validated.actions[1]
    if action.type == "waypoint" then
        if C_Map and C_Map.GetMapInfo and not C.Call(C_Map.GetMapInfo, action.mapID) then return false, "That map ID isn't available in this client." end
        if TomTom and type(TomTom.AddWaypoint) == "function" then
            local ok, uid = pcall(TomTom.AddWaypoint, TomTom, action.mapID, action.x / 100, action.y / 100, {title = action.title, persistent = false, minimap = true, world = true})
            if ok and uid then return true end
        end
        if UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function" and C_Map and C_Map.SetUserWaypoint then
            local point = C.Call(UiMapPoint.CreateFromCoordinates, action.mapID, action.x / 100, action.y / 100)
            if point then
                local ok = pcall(C_Map.SetUserWaypoint, point)
                if ok then return true end
            end
        end
        return false, "A waypoint needs TomTom or the client's native map-pin API."
    elseif action.type == "quest" then
        local opener = QuestMapFrame_OpenToQuestDetails or QuestLogPopupDetailFrame_Show
        if type(opener) ~= "function" then return false, "This client's quest detail window isn't available. Open your quest log instead." end
        local ok = pcall(opener, action.questID)
        return ok, ok and nil or "I couldn't open that quest. It may not be in your log."
    elseif action.type == "trail" then
        local g=self.Trail and self.Trail:Find(action.group,action.name)
        if not g then return false,"This Nib Trail chapter isn't available for your character." end
        if not self.Trail:Select(g) then return false, "Couldn't select this Nib Trail chapter." end
        self.Trail:Open(); return true
    elseif action.type == "guide" then
        local rxp = C.GetRXP()
        if not rxp or type(rxp.GetGuideTable) ~= "function" then return false, "RestedXP's guide adapter isn't available." end
        local guide = C.Call(rxp.GetGuideTable, action.group, action.name)
        if type(guide) ~= "table" or guide.disabled or guide.internal or guide.empty then return false, "That guide isn't installed and available in RestedXP." end
        UI:ShowCopy("Select this chapter in the RestedXP guide menu:\n\n" .. action.name, "RestedXP chapter")
        return true
    end
    return false, "Unsupported action."
end

function addon:LocalChatter()
    local lines = {
        "Mrrgl! I drew a very fine map. Then I spilled pond water on it. We shall call it a coastal survey.",
        "A snack, a safe path, and a well-folded map. That's my adventuring strategy. Mostly the snack.",
        "If a cave looks suspicious, it probably contains either treasure or a very opinionated spider. Bring a friend!",
        "My compass points toward adventure. And sometimes fish. There may be a calibration issue.",
        "Mrrgl-mrrgl! I am ready for quest questions, profession puzzles, and entirely reasonable tavern gossip.",
    }
    UI:ShowChat(); self:Remember("assistant", lines[math.random(1, #lines)])
end

function addon:Initialize()
    if self.initialized then return end
    if type(NibWhisperDB) ~= "table" then NibWhisperDB = {} end
    if type(NibWhisperCharDB) ~= "table" then NibWhisperCharDB = {} end
    self.db, self.charDB = NibWhisperDB, NibWhisperCharDB
    self.db.opticalEnabled = self.db.opticalEnabled == true
    -- 0.6.1 to 0.7.5 could switch a linked player to copy and paste at login. Put automatic mode back once.
    if self.db.geminiLinked == nil and self.Optical then
        if self.db.chatMode == "manual" or self.db.chatMode == "automatic" or self.db.opticalEnabled then
            self.db.geminiLinked, self.db.chatMode, self.db.opticalEnabled = true, "automatic", true
        else self.db.geminiLinked = false end
    end
    if not self.db.mascotPreference then self.db.mascotVisible = false end
    local history = P.Array()
    if type(self.charDB.history) == "table" then
        for i = math.max(1, #self.charDB.history - 79), #self.charDB.history do
            local entry = self.charDB.history[i]
            if type(entry) == "table" and (entry.role == "user" or entry.role == "assistant" or entry.role == "system") and type(entry.text) == "string" and not looksLikeKey(entry.text) then
                history[#history + 1] = {role = entry.role, text = P.SanitizeText(entry.text, 8000), at = entry.at}
            end
        end
    end
    self.charDB.history = history
    self.session = string.format("%x-%06x-%x", now(), math.random(0, 16777215), math.floor(uptime() * 1000) % 16777215)
    self.pending, self.nextSlot, self.sequence = nil, 1, 0
    self.initialized = true
    UI:Create()
    if self.Trail then
        self.Trail:Init()
        -- The guide is on screen at login unless the player switched that off in Options.
        if self.db.trailOpenOnLogin ~= false then self.Trail:Open() end
    end
    if self.Assistant and #history == 0 then self:Remember("assistant", "Mrrgl! Pick a prompt to read your guide, quest log, or profession ranks. Click Gemini setup for open-ended Warcraft questions.") end
    self:Notice(self:GetChatMode() == "automatic" and "Start the local companion to ask AI questions." or "Pick a prompt or type a question.")
end

local function slash(message)
    message = type(message) == "string" and message:match("^%s*(.-)%s*$") or ""
    local command, rest = message:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""
    if command == "show" then addon.db.mascotVisible = true; addon.db.mascotPreference = true; UI:UpdateMascot()
    elseif command == "hide" then addon.db.mascotVisible = false; addon.db.mascotPreference = true; UI:UpdateMascot()
    elseif command == "auto" then
        local enabled = rest ~= "off" and (rest == "on" or not addon.db.opticalEnabled)
        addon.db.chatMode = enabled and "automatic" or "manual"
        addon:SetOpticalEnabled(enabled)
    elseif command == "options" then UI:ShowOptions()
    elseif command == "filelog" then
        -- What the reply-file reader tried for the request that is waiting or has just failed. For troubleshooting.
        local report = addon.pending and addon.pending.font and addon.FontSlots and addon.FontSlots:Report(addon.pending)
        if report then UI:ShowCopy(report, "Nib reply file log") else addon:Notice("No reply file log. It is kept only while a request is waiting or has just failed.") end
    elseif (command == "copy" or command == "paste") and addon.Assistant then UI:ShowTransfer()
    elseif command == "trail" and addon.Trail then
        local option,value=rest:match("^(%S+)%s+(%d+%.?%d*)$");value=tonumber(value)
        if option=="phase" and value and value>=1 and value<=10 and value%1==0 then addon.db.trailPhase=value
        elseif option=="rate" and value and value>=0.1 and value<=10 then addon.db.trailRate=value end
        addon.Trail:Open()
    elseif command == "cancel" then addon:CancelPending()
    elseif command == "clear" then addon:CancelPending(); addon.charDB.history = P.Array(); UI:RefreshHistory(); UI:SetReply(nil); addon:Notice("Our chat notes are cleared.")
    elseif command == "reset" then
        addon.db.position, addon.db.mascotWidth = nil, nil
        if UI.mascot then UI.mascot:ClearAllPoints(); UI.mascot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 180); UI:SetMascotWidth(nil) end
        addon:Notice("Nib is back beside your adventure supplies, at his usual size.")
    elseif command == "help" then UI:ShowCopy("/nib - chat\n/nib trail - leveling guide\n/nib options - settings\n/nib show or hide - mascot\n/nib auto [on/off] - optional screen-reader bridge\n/nib copy or paste - manual transfer\n/nib cancel - cancel pending question\n/nib clear - clear character chat history\n/nib reset - reset mascot position\n\nMinimap left-click opens chat, Shift-click opens the leveling guide, and right-click opens Nib Options. Drag Nib or the minimap button to move them. Replies only place pins, open quests, or select installed guides when you click an action button. Automatic transport needs a separately running local companion and reply-slot addons installed before restarting the game.", "Nib's pocket instructions")
    elseif message == "" then
        if addon.Assistant then UI:ToggleChat() elseif addon.Trail then addon.Trail:Toggle() end
    else addon:Ask(message) end
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    addon.eventFrame = frame
    frame:RegisterEvent("ADDON_LOADED"); frame:RegisterEvent("PLAYER_LOGIN"); frame:RegisterEvent("QUEST_TURNED_IN")
    local inventoryEvents = {BANKFRAME_OPENED=true, BANKFRAME_CLOSED=true, PLAYERBANKSLOTS_CHANGED=true, BAG_UPDATE_DELAYED=true, PLAYER_MONEY=true,
        TRADE_SKILL_SHOW=true, TRADE_SKILL_LIST_UPDATE=true, TRADE_SKILL_DATA_SOURCE_CHANGED=true, TRADE_SKILL_CLOSE=true, SKILL_LINES_CHANGED=true,
        PLAYER_ENTERING_WORLD=true, PLAYER_LOGOUT=true}
    for event in pairs(inventoryEvents) do pcall(frame.RegisterEvent, frame, event) end
    local deathEvents = {PLAYER_DEAD=true, PLAYER_ALIVE=true, PLAYER_UNGHOST=true}
    for event in pairs(deathEvents) do pcall(frame.RegisterEvent, frame, event) end
    for _, event in ipairs({"QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRAINER_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_REGEN_ENABLED"}) do
        pcall(frame.RegisterEvent, frame, event)
    end
    local questWindowEvents = {GOSSIP_SHOW=true, QUEST_GREETING=true, QUEST_DETAIL=true, QUEST_PROGRESS=true, QUEST_COMPLETE=true, QUEST_ACCEPT_CONFIRM=true}
    for event in pairs(questWindowEvents) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, arg1, arg2)
        -- Start at login, once the Leveling Guide and AI Assistant addons have had their chance to load.
        if event == "PLAYER_LOGIN" then addon:Initialize()
        elseif event ~= "ADDON_LOADED" and addon.initialized then
            if addon.CharacterData and inventoryEvents[event] then addon.CharacterData:Event(event) end
            if event == "PLAYER_LOGOUT" and addon.FontSlots then addon.FontSlots:Logout() end
            if addon.Trail then
                if event == "QUEST_TURNED_IN" and P.IsPositiveInteger(arg1) then addon.observedTurnIns[arg1] = true end
                if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then addon.Trail:MerchantEvent(event) end
                if questWindowEvents[event] then pcall(addon.Trail.QuestAutomation, addon.Trail, event, arg1, arg2) end
                if deathEvents[event] or event == "PLAYER_ENTERING_WORLD" then addon.Trail:RestoreAfterDeath() end
                addon.trailUpdatePending = true
            end
        end
    end)
    local accumulator = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        accumulator = accumulator + elapsed
        if accumulator < 0.25 then return end
        accumulator = 0
        if addon.initialized then
            addon:PollReplySlots()
            if addon.CharacterData then addon.CharacterData:Tick() end
            if addon.Trail then addon.Trail:Tick(addon.trailUpdatePending); addon.trailUpdatePending = nil end
        end
    end)
end

SLASH_NIBWHISPER1 = "/nib"
SLASH_NIBWHISPER2 = "/nibwhisper"
SlashCmdList = SlashCmdList or {}
SlashCmdList.NIBWHISPER = function(message) if addon.initialized then slash(message) end end
addon.Test = {Now = now, LooksLikeKey = looksLikeKey, Slash = slash}
