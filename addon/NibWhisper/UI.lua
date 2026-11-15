local addonName, addon = ...
addon = addon or _G.NibWhisper
local P = addon.Protocol
local UI = {}
addon.UI = UI
local textureRoot = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"

local function backdrop(frame, inset)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 16, insets = {left = inset or 5, right = inset or 5, top = inset or 5, bottom = inset or 5} })
    frame:SetBackdropColor(0.035, 0.065, 0.08, 0.97)
    frame:SetBackdropBorderColor(0.35, 0.67, 0.61, 1)
end

local scales = {0.85, 1, 1.15, 1.3}
function UI:GetScale()
    local scale = tonumber(addon.db and addon.db.uiScale)
    return scale and scale >= 0.7 and scale <= 1.5 and scale or 1
end

-- Top-level windows register here so the Options size control reaches windows created later.
function UI:Scaled(frame)
    self.scaledFrames = self.scaledFrames or {}
    self.scaledFrames[#self.scaledFrames + 1] = frame
    frame:SetScale(self:GetScale())
    return frame
end

function UI:CycleScale()
    -- Nib Targets holds secure buttons, which cannot be rescaled during combat.
    if InCombatLockdown and InCombatLockdown() then addon:Notice("Change the window size after combat.", true); return false end
    local current, nextScale = self:GetScale(), scales[1]
    for _, scale in ipairs(scales) do if scale > current + 0.01 then nextScale = scale; break end end
    addon.db.uiScale = nextScale
    for _, frame in ipairs(self.scaledFrames or {}) do
        frame:SetScale(nextScale)
        if frame.positionKey then self:RestorePosition(frame, frame.positionKey) end
    end
    return true
end

-- A short fade makes windows feel less abrupt. Every call is guarded because animation support varies by client.
function UI:FadeOnShow(frame)
    pcall(function()
        if not frame.CreateAnimationGroup or not frame.HookScript then return end
        local group = frame:CreateAnimationGroup()
        local fade = group:CreateAnimation("Alpha")
        if not fade or not fade.SetFromAlpha then return end
        fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.12)
        if fade.SetSmoothing then fade:SetSmoothing("OUT") end
        frame:HookScript("OnShow", function() group:Play() end)
    end)
end

local function panel(name, parent)
    local frame = CreateFrame("Frame", name, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    backdrop(frame)
    frame:SetClampedToScreen(true)
    if name then UI:Scaled(frame); UI:FadeOnShow(frame) end
    return frame
end

local function captionWidth(caption)
    if caption.GetUnboundedStringWidth then return caption:GetUnboundedStringWidth() end
    return caption.GetStringWidth and caption:GetStringWidth() or 0
end

-- Keeps a caption inside its button. Text that is too long ends in an ellipsis instead of spilling over the border.
local function clip(b)
    local caption = b.GetFontString and b:GetFontString()
    if not caption then return end
    if caption.SetWordWrap then caption:SetWordWrap(false) end
    caption:SetWidth(math.max(10, b:GetWidth() - 16))
end
UI.ClipButton = clip

-- Widens a button to its caption. Use where the neighbours are anchored to it and can move.
local function fit(b)
    local caption = b.GetFontString and b:GetFontString()
    if not caption then return end
    caption:SetWidth(0)
    b:SetWidth(math.max(b:GetWidth(), math.ceil(captionWidth(caption)) + 24))
    clip(b)
end

-- Lays the visible buttons out left to right at their caption widths.
-- When the row is too narrow, only the widest captions are shortened.
function UI:Flow(buttons, available, anchor, minWidth)
    local shown, widths, total = {}, {}, 0
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            local caption = b:GetFontString()
            if caption then caption:SetWidth(0) end
            local width = math.max(minWidth or 60, caption and math.ceil(captionWidth(caption)) + 24 or b:GetWidth())
            shown[#shown + 1], widths[#widths + 1] = b, width
            total = total + width
        end
    end
    if #shown == 0 then return end
    local room = available - 5 * (#shown - 1)
    if total > room then
        local fair, remaining, wide = room / #shown, room, 0
        for _, width in ipairs(widths) do
            if width <= fair then remaining = remaining - width else wide = wide + 1 end
        end
        local cap = math.max(40, math.floor(remaining / math.max(1, wide)))
        for i, width in ipairs(widths) do if width > fair then widths[i] = cap end end
    end
    local previous
    for i, b in ipairs(shown) do
        b:SetWidth(widths[i]); clip(b)
        b:ClearAllPoints()
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 5, 0)
        else b:SetPoint(anchor[1], anchor[2], anchor[1], anchor[3], anchor[4]) end
        previous = b
    end
end

local function label(parent, text, point, x, y, font)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    l:SetPoint(point or "TOPLEFT", parent, point or "TOPLEFT", x or 0, y or 0)
    l:SetText(text)
    return l
end

local function button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 110, height or 24)
    b:SetText(text)
    clip(b)
    return b
end

local function movable(frame, handle)
    frame:SetMovable(true)
    handle = handle or frame
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() if frame == UI.chat then UI:RaiseMain(frame) end; frame:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if frame.positionKey then UI:SavePosition(frame, frame.positionKey) end
    end)
end

function UI:RaiseMain(frame)
    local guide = addon.Trail and addon.Trail.frame
    local behind = frame == self.chat and guide or self.chat
    if behind and behind ~= frame then behind:SetFrameStrata("MEDIUM") end
    frame:SetFrameStrata("HIGH")
    self.frontWindow = frame
end

-- Window positions are stored as an offset from the screen centre in screen units, so they survive a window-size change.
function UI:SavePosition(frame, key)
    local x, y = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local scale = frame.GetScale and frame:GetScale() or 1
    if x and y and ux and uy then addon.db[key] = {x = x * scale - ux, y = y * scale - uy} end
end

function UI:RestorePosition(frame, key)
    local saved = addon.db and addon.db[key]
    if type(saved) ~= "table" or not P.IsFinite(saved.x) or not P.IsFinite(saved.y) then return false end
    local scale = frame.GetScale and frame:GetScale() or 1
    if not P.IsFinite(scale) or scale <= 0 then scale = 1 end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", saved.x / scale, saved.y / scale)
    return true
end

function UI:Paint(frame, layer, r, g, b, a)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a or 1)
    return texture
end

function UI:ResizeGrip(frame, settings, minWidth, minHeight, maxWidth, maxHeight)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else frame:SetMinResize(minWidth, minHeight); frame:SetMaxResize(maxWidth, maxHeight) end
    local saved = addon.db[settings]
    if type(saved) == "table" and P.IsFinite(saved.width) and P.IsFinite(saved.height) then
        frame:SetSize(math.max(minWidth, math.min(maxWidth, saved.width)), math.max(minHeight, math.min(maxHeight, saved.height)))
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(20, 20); grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local function stop()
        if not grip.sizing then return end
        grip.sizing = false
        frame:StopMovingOrSizing()
        addon.db[settings] = {width = frame:GetWidth(), height = frame:GetHeight()}
        if frame.afterResize then frame.afterResize() end
    end
    grip:SetScript("OnMouseDown", function(_, key)
        if key ~= "LeftButton" then return end
        -- A window with secure buttons (Nib Targets) cannot change size during combat.
        if frame.lockedInCombat and InCombatLockdown and InCombatLockdown() then addon:Notice("Resize this window after combat.", true); return end
        grip.sizing = true; frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", stop)
    grip:SetScript("OnHide", stop)
    return grip
end

local function makeTextArea(parent, width, height, maxBytes)
    local box = panel(nil, parent)
    box:SetSize(width, height)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 9, -9)
    scroll:SetPoint("BOTTOMRIGHT", -30, 9)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetWidth(width - 48)
    edit:SetHeight(height - 18)
    edit:SetMaxBytes(maxBytes or P.MAX_PACKET)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if edit.SetTextInsets then edit:SetTextInsets(2, 2, 2, 2) end
    edit:SetScript("OnTextChanged", function(self) if self.GetStringHeight then self:SetHeight(math.max(height - 18, self:GetStringHeight() + 10)) end end)
    scroll:SetScrollChild(edit)
    box.edit, box.scroll = edit, scroll
    return box
end

function UI:EnsureTransfer()
    if self.transfer then return end
    local frame = panel("NibWhisperTransfer", UIParent)
    self.transfer = frame
    frame:SetSize(650, 462)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    movable(frame)
    label(frame, "Nib's message satchel", "TOPLEFT", 18, -18, "GameFontNormalLarge")
    label(frame, "Manual bridge: copy the request to the companion, then paste its reply below.", "TOPLEFT", 18, -46)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    label(frame, "1. Request packet - click in the box, then Ctrl+A and Ctrl+C", "TOPLEFT", 18, -76)
    frame.outbox = makeTextArea(frame, 614, 130, P.MAX_PACKET)
    frame.outbox:SetPoint("TOPLEFT", 18, -96)
    label(frame, "2. Paste the companion's NIBR1 reply packet here", "TOPLEFT", 18, -242)
    frame.inbox = makeTextArea(frame, 614, 130, P.MAX_PACKET)
    frame.inbox:SetPoint("TOPLEFT", 18, -262)
    local import = button(frame, "Read reply", 120, 27)
    import:SetPoint("BOTTOMRIGHT", -18, 20)
    import:SetScript("OnClick", function()
        local ok, err = addon:ImportReply(frame.inbox.edit:GetText())
        if ok then frame.inbox.edit:SetText(""); frame.error:SetText(""); frame:Hide()
        else frame.error:SetText(P.SanitizeText(err or "That reply did not fit this satchel.", 180)); UI:SetStatus(err or "That reply did not fit this satchel.", true) end
    end)
    local selectButton = button(frame, "Select request", 130, 27)
    selectButton:SetPoint("BOTTOMLEFT", 18, 20)
    selectButton:SetScript("OnClick", function() frame.outbox.edit:SetFocus(); frame.outbox.edit:HighlightText() end)
    label(frame, "Keys stay in the companion. Do not paste API keys into the game.", "BOTTOMLEFT", 164, 26)
    frame.error = label(frame, "", "BOTTOMLEFT", 164, 52)
    frame.error:SetWidth(450); frame.error:SetJustifyH("LEFT"); frame.error:SetTextColor(1, 0.6, 0.45)
    if UISpecialFrames then table.insert(UISpecialFrames, "NibWhisperTransfer") end
    frame:Hide()
end

function UI:ShowTransfer(packet)
    self:EnsureTransfer()
    local pending = addon.pending
    self.transfer.outbox.edit:SetText(packet or (pending and pending.kind ~= "trail" and pending.packet) or "")
    self.transfer.error:SetText("")
    self.transfer:Show()
    self.transfer.outbox.edit:SetFocus()
    self.transfer.outbox.edit:HighlightText()
end

function UI:ShowCopy(text, title)
    if not self.copy then
        local f = panel("NibWhisperCopy", UIParent)
        f:SetSize(560, 340); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); movable(f)
        f.title = label(f, "Nib's notes", "TOPLEFT", 18, -18, "GameFontNormalLarge")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() f:Hide() end)
        f.box = makeTextArea(f, 524, 250, P.MAX_PACKET); f.box:SetPoint("TOPLEFT", 18, -53)
        label(f, "Ctrl+A, Ctrl+C to copy. Links are shown as plain text.", "BOTTOMLEFT", 18, 15)
        if UISpecialFrames then table.insert(UISpecialFrames, "NibWhisperCopy") end
        self.copy = f
    end
    self.copy.title:SetText(title or "Nib's notes")
    self.copy.box.edit:SetText(P.SanitizeText(text or "", 30000))
    self.copy:Show(); self.copy.box.edit:SetFocus(); self.copy.box.edit:HighlightText()
end

function UI:SetStatus(text, isError)
    if not self.status then return end
    self.status:SetText(P.SanitizeText(text or "", 180))
    self.status:SetTextColor(isError and 1 or 0.62, isError and 0.55 or 0.86, isError and 0.45 or 0.78)
    if self.cancelButton then
        local waiting = addon.pending ~= nil and addon.pending.kind ~= "trail"
        if waiting ~= self.cancelButton:IsShown() then self.cancelButton:SetShown(waiting); self:LayoutChat() end
    end
end

function UI:LayoutChat()
    local frame = self.chat
    if not frame or not self.actions then return end
    local width = frame:GetWidth()
    self:Flow(self.chips, width - 28, {"BOTTOMLEFT", frame, 14, 115}, 96)
    self:Flow(self.footer, width - 52, {"BOTTOMLEFT", frame, 14, 13}, 66)
    self:Flow(self.actions, width - 42, {"BOTTOMLEFT", self.actionArea, 9, 8}, 90)
end

function UI:AddMessage(role, text)
    if not self.log then return end
    local who = role == "user" and "You" or role == "assistant" and "Nib" or "Guide chat"
    local color = role == "assistant" and "|cff8fe3bf" or role == "user" and "|cffffd18c" or "|cff99aeb4"
    self.log:AddMessage(color .. who .. "|r\n" .. P.SanitizeText(text or "", 8000), 0.9, 0.94, 0.94)
    self.log:ScrollToBottom()
end

function UI:RefreshHistory()
    if not self.log then return end
    self.log:Clear()
    for _, message in ipairs(addon.charDB and addon.charDB.history or {}) do self:AddMessage(message.role, message.text) end
end

function UI:ShowSources(sources)
    local lines = {}
    for i, source in ipairs(sources or {}) do
        lines[#lines + 1] = tostring(i) .. ". " .. source.title .. "\n" .. (source.url ~= "" and source.url or "Local RestedXP guide in your installation (no web link).")
    end
    self:ShowCopy(#lines > 0 and table.concat(lines, "\n\n") or "No web sources were supplied for this reply. Live game state and your local route may still have informed it.", "Nib's source notes")
end

function UI:SetReply(reply)
    self.lastReply = reply
    if self.sourceButton then self.sourceButton:SetShown(reply ~= nil and #(reply.sources or {}) > 0) end
    if self.log then self.log:SetPoint("BOTTOMRIGHT", -14, reply and #(reply.actions or {}) > 0 and 36 or 12) end
    for i = 1, 3 do
        local action, b = reply and reply.actions and reply.actions[i], self.actions and self.actions[i]
        if b then
            if action then
                b.fullTitle = P.SanitizeText(action.title or (action.type == "waypoint" and "Place waypoint" or action.type == "quest" and "Open quest" or "Select guide"), 160)
                b:SetText(P.TruncateUTF8(b.fullTitle, 48))
                b:SetScript("OnClick", function()
                    local ok, err = addon:ExecuteAction(action)
                    UI:SetStatus(ok and "Done! One more little mark on the map." or err, not ok)
                end)
                b:Show()
            else b:Hide() end
        end
    end
    self:LayoutChat()
end

function UI:UpdateBridgeMode()
    if not self.mode then return end
    local mode = addon:GetChatMode()
    self.mode:SetText(({localGuide = "Guide chat", automatic = "AI · automatic", manual = "AI · copy and paste"})[mode])
    if self.transferButton then self.transferButton:SetShown(mode ~= "localGuide") end
    self:LayoutChat()
end

function UI:ShowSetup()
    if not self.geminiSetup then
        local f = panel("NibWhisperGeminiSetup", UIParent)
        self.geminiSetup = f
        f:SetSize(410, 190); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); movable(f)
        label(f, "Connect Gemini", "TOPLEFT", 18, -17, "GameFontNormalLarge")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() f:Hide() end)
        local hint = label(f, "Copy your Gemini API key in Google AI Studio. Return to WoW and click Use copied key.", "TOPLEFT", 18, -47)
        hint:SetWidth(368); hint:SetJustifyH("LEFT")
        f.status = label(f, "", "TOPLEFT", 18, -91)
        f.status:SetWidth(372); f.status:SetJustifyH("LEFT")
        f.connect = button(f, "Use copied key", 130, 26)
        f.connect:SetPoint("BOTTOMRIGHT", -16, 14)
        f.connect:SetScript("OnClick", function()
            local ok, err = addon:ConnectGemini()
            UI:SetSetupStatus(ok and "Sending setup request to the Nib helper…" or err, not ok)
        end)
        if UISpecialFrames then table.insert(UISpecialFrames, "NibWhisperGeminiSetup") end
    end
    self.geminiSetup:Show()
end

function UI:SetSetupStatus(text, isError)
    local f = self.geminiSetup
    if not f then return end
    f.status:SetText(P.SanitizeText(text or "", 240))
    f.status:SetTextColor(isError and 1 or 0.64, isError and 0.57 or 0.86, isError and 0.42 or 0.75)
end

function UI:CreateChat()
    local frame = panel("NibWhisperChat", UIParent)
    self.chat = frame
    frame:SetSize(540, 472)
    frame:SetPoint("CENTER", UIParent, "CENTER", 100, 0)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() UI:RaiseMain(frame) end)
    self:Paint(frame, "BACKGROUND", 0.025, 0.046, 0.055)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 7, -7); header:SetPoint("TOPRIGHT", -7, -7); header:SetHeight(65)
    self:Paint(header, "BACKGROUND", 0.075, 0.17, 0.18)
    movable(frame, header)
    local portrait = header:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(56, 56); portrait:SetPoint("TOPLEFT", 8, -3)
    portrait:SetTexture(textureRoot .. "Nib.tga"); portrait:SetTexCoord(0.17, 0.83, 0.08, 0.76)
    label(header, "Nib Whisper", "TOPLEFT", 72, -12, "GameFontNormalLarge")
    self.mode = label(header, "", "TOPLEFT", 73, -38)
    self.mode:SetTextColor(0.55, 0.89, 0.76)
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -1, -1); close:SetScript("OnClick", function() frame:Hide() end)
    local options = button(header, "Options", 78, 25)
    options:SetPoint("RIGHT", close, "LEFT", -4, -1)
    options:SetScript("OnClick", function() UI:ShowOptions() end)
    fit(options)
    if addon.Trail then
        local guide = button(header, "Leveling guide", 114, 25)
        self.guideButton = guide
        fit(guide)
        guide:SetPoint("RIGHT", options, "LEFT", -5, 0)
        guide:SetScript("OnClick", function() UI.input:ClearFocus(); addon.Trail:Open() end)
    end
    local area = panel(nil, frame)
    self.actionArea = area
    area:SetPoint("TOPLEFT", 12, -83); area:SetPoint("BOTTOMRIGHT", -12, 142)
    if area.SetBackdropColor then area:SetBackdropColor(0.018, 0.037, 0.046, 0.98) end
    self.log = CreateFrame("ScrollingMessageFrame", nil, area)
    self.log:SetPoint("TOPLEFT", 14, -12); self.log:SetPoint("BOTTOMRIGHT", -14, 12)
    self.log:SetFontObject(GameFontHighlight)
    self.log:SetJustifyH("LEFT"); self.log:SetFading(false); self.log:SetMaxLines(200)
    if self.log.SetSpacing then self.log:SetSpacing(8) end
    self.log:EnableMouseWheel(true)
    self.log:SetScript("OnMouseWheel", function(log, delta) if delta > 0 then log:ScrollUp() else log:ScrollDown() end end)
    self.log:EnableMouse(true)
    self.log:SetScript("OnMouseUp", function(_, key)
        if key == "RightButton" and UI.lastReply then UI:ShowCopy(UI.lastReply.answer, "Nib's last reply") end
    end)

    local function send()
        if addon:Ask(UI.input:GetText()) then UI.input:SetText(""); UI.input:ClearFocus() end
    end
    local prompts = {{"Next objective", "What should I do next?"}, {"Quest log", "What quests am I on?"}, {"Professions", "What are my profession ranks?"}}
    self.chips = {}
    for _, prompt in ipairs(prompts) do
        local chip = button(frame, prompt[1], 112, 23)
        local question = prompt[2]
        chip:SetScript("OnClick", function() UI.input:SetText(question); send() end)
        self.chips[#self.chips + 1] = chip
    end
    self.status = label(frame, "", "BOTTOMLEFT", 17, 91)
    self.status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 91); self.status:SetJustifyH("LEFT")
    -- Two lines fit between the prompt row and the input box.
    if self.status.SetMaxLines then self.status:SetMaxLines(2) end
    local inputFrame = panel(nil, frame)
    inputFrame:SetPoint("BOTTOMLEFT", 13, 44); inputFrame:SetPoint("BOTTOMRIGHT", -108, 44); inputFrame:SetHeight(37)
    self.input = CreateFrame("EditBox", nil, inputFrame)
    self.input:SetPoint("TOPLEFT", 10, -7); self.input:SetPoint("BOTTOMRIGHT", -10, 7)
    self.input:SetFontObject(GameFontHighlight); self.input:SetAutoFocus(false); self.input:SetMaxBytes(P.MAX_QUESTION)
    local placeholder = label(inputFrame, "Ask about a quest or where to go…", "LEFT", 11, 0)
    placeholder:SetTextColor(0.58, 0.66, 0.68)
    self.input:SetScript("OnTextChanged", function(input) placeholder:SetShown(input:GetText() == "") end)
    self.input:SetScript("OnEscapePressed", function(input) input:ClearFocus() end)
    self.input:SetScript("OnEnterPressed", send)
    local sendButton = button(frame, "Send", 88, 35)
    sendButton:SetPoint("LEFT", inputFrame, "RIGHT", 5, 0); sendButton:SetScript("OnClick", send)
    self.setup = button(frame, "Gemini setup", 103, 23)
    self.setup:SetScript("OnClick", function() UI:ShowSetup() end)
    local transfer = button(frame, "Transfer", 80, 23)
    self.transferButton = transfer
    transfer:SetScript("OnClick", function() UI:ShowTransfer() end)
    local sources = button(frame, "Sources", 75, 23)
    self.sourceButton = sources; sources:Hide()
    sources:SetScript("OnClick", function() UI:ShowSources(UI.lastReply and UI.lastReply.sources) end)
    local cancel = button(frame, "Cancel", 66, 23)
    self.cancelButton = cancel; cancel:Hide()
    cancel:SetScript("OnClick", function() addon:CancelPending() end)
    self.footer = {self.setup, transfer, sources, cancel}
    local actions = {}
    for i = 1, 3 do
        local action = button(area, "", 127, 22)
        action:SetScript("OnEnter", function(b)
            if not b.fullTitle then return end
            GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:AddLine(b.fullTitle, 1, 1, 1, true); GameTooltip:Show()
        end)
        action:SetScript("OnLeave", function() GameTooltip:Hide() end)
        action:Hide(); actions[i] = action
    end
    self.actions = actions
    self.log:SetPoint("BOTTOMRIGHT", -14, 12)
    self:ResizeGrip(frame, "chatSize", 460, 345, 820, 720)
    frame:SetScript("OnSizeChanged", function() UI:LayoutChat() end)
    -- Chat reopens where it was last left, including after a restart.
    frame.positionKey = "chatPosition"
    frame.afterResize = function() UI:SavePosition(frame, frame.positionKey) end
    self:RestorePosition(frame, frame.positionKey)
    self.chatHeader = header
    if UISpecialFrames then table.insert(UISpecialFrames, "NibWhisperChat") end
    self:UpdateBridgeMode(); self:RefreshHistory()
    frame:Hide()
end

function UI:ShowOptions()
    if not self.options then
        local f = panel("NibWhisperOptions", UIParent)
        self.options = f
        f:SetWidth(365); f:SetFrameStrata("DIALOG")
        movable(f)
        label(f, "Nib Options", "TOPLEFT", 19, -18, "GameFontNormalLarge")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() f:Hide() end)
        -- Sections appear only for the parts of Nib that are switched on in the AddOns list.
        local trail, assistant = addon.Trail, addon.Assistant
        local y = -54
        local function control(title, column, onClick, offset)
            local b = button(f, title, column == 1 and 158 or 161, 26)
            b:SetPoint("TOPLEFT", column == 1 and 18 or 185, y - (offset or 0)); b:SetScript("OnClick", onClick)
            return b
        end
        if assistant then control("Open chat", 1, function() f:Hide(); UI:ShowChat() end) end
        if trail then control("Open leveling guide", assistant and 2 or 1, function() f:Hide(); trail:Open() end) end
        if trail or assistant then y = y - 42 end
        if trail then
            label(f, "LEVELING GUIDE", "TOPLEFT", 20, y); y = y - 22
            f.advance = control("", 1, function()
                addon.db.trailAuto = addon.db.trailAuto == false
                trail.reviewing = false; trail:Tick(true); UI:RefreshOptions()
            end)
            f.pins = control("", 2, function()
                addon.db.trailPins = addon.db.trailPins == false
                if not addon.db.trailPins then trail:ClearPin() end
                trail:Refresh(); UI:RefreshOptions()
            end)
            y = y - 33
            f.quests = control("", 1, function()
                addon.db.trailQuestAuto = addon.db.trailQuestAuto == false
                UI:RefreshOptions()
            end)
            f.quests:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:AddLine("Auto quests")
                GameTooltip:AddLine("While the guide is open, Nib accepts and turns in the quests named in your current step. Rewards with a choice are left to you. Hold Ctrl while talking to an NPC to do it by hand.", 0.85, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            f.quests:SetScript("OnLeave", function() GameTooltip:Hide() end)
            control("Progress sync", 2, function() f:Hide(); trail:ShowSync() end)
            y = y - 33
            f.login = control("", 1, function()
                addon.db.trailOpenOnLogin = addon.db.trailOpenOnLogin == false
                UI:RefreshOptions()
            end)
            f.finish = control("", 2, function()
                addon.db.trailFinishSound = addon.db.trailFinishSound == false
                if addon.db.trailFinishSound then trail:ChapterFinished() end
                UI:RefreshOptions()
            end)
            y = y - 44
        end
        if assistant then
            label(f, "CHAT MODE", "TOPLEFT", 20, y); y = y - 20
            f.modes = {}
            for i, entry in ipairs({{"localGuide", "Guide chat"}, {"automatic", "AI automatic"}, {"manual", "AI copy and paste"}}) do
                local mode = entry[1]
                f.modes[mode] = control(entry[2], 1, function() addon:SetChatMode(mode); UI:RefreshOptions() end, (i - 1) * 32)
            end
            f.selected = label(f, "", "TOPLEFT", 195, y - 8)
            f.selected:SetWidth(145); f.selected:SetJustifyH("LEFT")
            control("Connect Gemini", 2, function() UI:ShowSetup() end, 63)
            y = y - 106
        end
        label(f, "DISPLAY", "TOPLEFT", 20, y); y = y - 20
        f.scale = control("", 1, function() UI:CycleScale(); UI:RefreshOptions() end)
        if assistant then
            f.mascot = control("", 2, function() UI:ToggleMascot(); UI:RefreshOptions() end)
            y = y - 33
            f.replySound = control("", 1, function()
                addon.db.replySound = addon.db.replySound == false
                if addon.db.replySound then addon:ReplySound() end
                UI:RefreshOptions()
            end)
        end
        f:SetHeight(43 - y)
        if UISpecialFrames then table.insert(UISpecialFrames, "NibWhisperOptions") end
    elseif self.options:IsShown() then self.options:Hide(); return end
    local f = self.options
    f:ClearAllPoints()
    if self.minimap then f:SetPoint("TOPRIGHT", self.minimap, "BOTTOMLEFT", -5, -3)
    else f:SetPoint("CENTER") end
    self:RefreshOptions(); f:Show()
end

function UI:RefreshOptions()
    local f = self.options
    if not f then return end
    if f.advance then
        f.advance:SetText(addon.db.trailAuto == false and "Auto advance: off" or "Auto advance: on")
        f.pins:SetText(addon.db.trailPins == false and "Map pins: off" or "Map pins: on")
        f.quests:SetText(addon.db.trailQuestAuto == false and "Auto quests: off" or "Auto quests: on")
        f.login:SetText(addon.db.trailOpenOnLogin == false and "Open at login: off" or "Open at login: on")
        f.finish:SetText(addon.db.trailFinishSound == false and "Chapter sound: off" or "Chapter sound: on")
    end
    if f.mascot then f.mascot:SetText(addon.db.mascotVisible == true and "Hide Nib Himself" or "Show Nib Himself") end
    f.scale:SetText(string.format("Window size: %d%%", math.floor(self:GetScale() * 100 + 0.5)))
    if f.replySound then f.replySound:SetText(addon.db.replySound == false and "Reply sound: off" or "Reply sound: on") end
    if f.selected then
        f.selected:SetText(({localGuide = "Selected: Guide chat\nUses the live guide and quest log.", automatic = "Selected: AI automatic\nKeep the companion open.", manual = "Selected: AI copy and paste\nSend through the companion page."})[addon:GetChatMode()])
    end
end

function UI:ShowChat()
    if not self.chat then return end
    self.chat:Show(); self:RaiseMain(self.chat); self.input:SetFocus()
end

function UI:ToggleChat()
    if not self.chat then return end
    if self.chat:IsShown() and self.frontWindow == self.chat then self.chat:Hide() else self:ShowChat() end
end

function UI:UpdateMascot()
    if not self.mascot then return end
    local visible = addon.db and addon.db.mascotVisible == true
    self.mascot:SetShown(visible)
end

function UI:ToggleMascot()
    addon.db.mascotVisible = addon.db.mascotVisible ~= true
    addon.db.mascotPreference = true
    self:UpdateMascot()
end

-- Nib keeps his proportions: the width is chosen and the height follows.
local MASCOT_WIDTH, MASCOT_MIN, MASCOT_MAX, MASCOT_RATIO = 126, 60, 380, 168 / 126

function UI:SetMascotWidth(width, save)
    local mascot = self.mascot
    if not mascot then return end
    width = tonumber(width)
    if not width or not P.IsFinite(width) then width = MASCOT_WIDTH end
    width = math.floor(math.max(MASCOT_MIN, math.min(MASCOT_MAX, width)) + 0.5)
    mascot:SetSize(width, math.floor(width * MASCOT_RATIO + 0.5))
    if save then addon.db.mascotWidth = width end
    return width
end

-- Drag the corner grip to resize him. The mouse wheel is left alone so it still zooms the camera over Nib.
function UI:MascotResizing(mascot)
    self:SetMascotWidth(addon.db.mascotWidth)
    local function savePlace()
        local x, y = mascot:GetCenter(); local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then
            addon.db.position = {x = x - ux, y = y - uy}
            mascot:ClearAllPoints(); mascot:SetPoint("CENTER", UIParent, "CENTER", x - ux, y - uy)
        end
    end
    local grip = CreateFrame("Button", nil, mascot)
    mascot.grip = grip
    grip:SetSize(18, 18); grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local function stop()
        if not grip.from then return end
        grip.from = nil
        grip:SetScript("OnUpdate", nil)
        UI:SetMascotWidth(mascot:GetWidth(), true)
        savePlace()
        mascot.suppressClickUntil = GetTime() + 0.2
    end
    grip:SetScript("OnMouseDown", function(_, key)
        if key ~= "LeftButton" then return end
        local cursor = GetCursorPosition()
        local left, top = mascot.GetLeft and mascot:GetLeft(), mascot.GetTop and mascot:GetTop()
        if not cursor then return end
        -- Pin the top-left corner so the grip follows the cursor.
        if left and top then mascot:ClearAllPoints(); mascot:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
        grip.from = {cursor = cursor, width = mascot:GetWidth()}
        grip:SetScript("OnUpdate", function()
            local x = GetCursorPosition()
            if x and grip.from then UI:SetMascotWidth(grip.from.width + (x - grip.from.cursor) / (mascot:GetEffectiveScale() or 1)) end
        end)
    end)
    grip:SetScript("OnMouseUp", stop)
    grip:SetScript("OnHide", stop)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Drag to resize Nib"); GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:CreateMascot()
    local mascot = CreateFrame("Button", "NibWhisperMascot", UIParent)
    self.mascot = mascot
    mascot:SetSize(126, 168); mascot:SetFrameStrata("MEDIUM"); mascot:SetClampedToScreen(true)
    mascot:SetMovable(true); mascot:EnableMouse(true); mascot:RegisterForDrag("LeftButton")
    mascot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local saved = addon.db.position
    if type(saved) == "table" and P.IsFinite(saved.x) and P.IsFinite(saved.y) then mascot:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else mascot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 180) end
    mascot.art = mascot:CreateTexture(nil, "ARTWORK"); mascot.art:SetAllPoints(); mascot.art:SetTexture(textureRoot .. "Nib.tga"); mascot.art:SetTexCoord(0.125, 0.875, 0, 1)
    local name = label(mascot, "Nib", "BOTTOM", 0, 0, "GameFontNormal"); name:SetTextColor(0.66, 1, 0.82)
    local close = CreateFrame("Button", nil, mascot, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() UI:ToggleMascot(); UI:RefreshOptions() end)
    mascot.close = close
    mascot:SetScript("OnClick", function(self, which)
        if self.suppressClickUntil and GetTime() < self.suppressClickUntil then return end
        if which == "RightButton" then addon:LocalChatter() else UI:ToggleChat() end
    end)
    mascot:SetScript("OnDragStart", function(self) self.dragged = true; self:StartMoving() end)
    mascot:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter(); local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then addon.db.position = {x = x - ux, y = y - uy} end
        self.suppressClickUntil = GetTime() + 0.2
        self.dragged = false
    end)
    mascot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Nib, apprentice cartographer")
        GameTooltip:AddLine("Click: chat  |  Right-click: a little mrrgl\nDrag: move  |  Corner grip: resize\nNib Options: show or hide", 0.85, 0.9, 0.9, true); GameTooltip:Show()
    end)
    mascot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local timer, blink = 0, false
    mascot:SetScript("OnUpdate", function(_, elapsed)
        timer = timer + elapsed
        if not blink and timer > 5.5 then blink = true; timer = 0; mascot.art:SetTexture(textureRoot .. "NibBlink.tga")
        elseif blink and timer > 0.13 then blink = false; timer = 0; mascot.art:SetTexture(textureRoot .. "Nib.tga") end
    end)
    self:MascotResizing(mascot)
    self:UpdateMascot()
end

function UI:CreateMinimap()
    if not Minimap then return end
    local b = CreateFrame("Button", "NibWhisperMinimapButton", Minimap)
    self.minimap = b
    b:SetSize(32, 32); b:SetFrameStrata("MEDIUM"); b:SetMovable(true)
    b:SetNormalTexture("Interface\\Icons\\INV_Misc_Fish_02")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local normal = b:GetNormalTexture(); if normal then normal:SetTexCoord(0.08, 0.92, 0.08, 0.92); normal:SetPoint("TOPLEFT", 4, -4); normal:SetPoint("BOTTOMRIGHT", -4, 4) end
    local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
    local function place()
        local angle = math.rad(tonumber(addon.db.minimapAngle) or 210)
        local radius = math.max(Minimap:GetWidth(), Minimap:GetHeight()) * 0.5 + 9
        b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    b:SetScript("OnClick", function(self, which)
        if self.suppressClickUntil and GetTime() < self.suppressClickUntil then return end
        local shift = IsShiftKeyDown and IsShiftKeyDown()
        if which == "RightButton" and not (shift and addon.Trail) then UI:ShowOptions()
        elseif which == "LeftButton" and shift and addon.Assistant then UI:ShowChat()
        elseif addon.Trail then addon.Trail:Open()
        elseif addon.Assistant then UI:ToggleChat() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition(); local mx, my = Minimap:GetCenter(); local scale = Minimap:GetEffectiveScale()
            if x and y and mx and my then
                local dx, dy = x / scale - mx, y / scale - my
                local atan2 = math.atan2 or _G.atan2
                local angle
                if atan2 then angle = atan2(dy, dx)
                elseif dx > 0 then angle = math.atan(dy / dx)
                elseif dx < 0 then angle = math.atan(dy / dx) + (dy >= 0 and math.pi or -math.pi)
                else angle = dy >= 0 and math.pi / 2 or -math.pi / 2 end
                addon.db.minimapAngle = math.deg(angle); place()
            end
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); self.suppressClickUntil = GetTime() + 0.2; place() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Nib Whisper")
        local lines = {}
        if addon.Trail then lines[#lines + 1] = "Left-click: leveling guide" end
        if addon.Assistant then lines[#lines + 1] = addon.Trail and "Shift-left-click: Nib chat" or "Left-click: Nib chat" end
        if addon.Trail then lines[#lines + 1] = "Shift-right-click: leveling guide" end
        lines[#lines + 1] = "Right-click: Nib Options\nDrag: move around minimap"
        GameTooltip:AddLine(table.concat(lines, "\n"), 0.85, 0.9, 0.9, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
end

function UI:Create()
    if self.created then return end
    self.created = true
    if addon.Assistant then self:CreateChat(); self:CreateMascot() end
    self:CreateMinimap()
end
