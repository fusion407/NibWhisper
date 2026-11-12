local A=_G.NibWhisper
if not A then return end
local T,P,C=A.Trail,A.Protocol,A.Context
if not T then return end
local call=C.Call
local function stamp(r) return type(r)=="table" and P.IsFinite(r.at) and r.at>=1 and r.at%1==0 and r.at<=((call(GetServerTime) or call(time) or 0)*1000.0+86400000) and type(r.by)=="string" and #r.by<=80 and r.by:match("^[%w_-]+$") end
local function newer(a,b)
    if not b then return true end
    return a.at>b.at or a.at==b.at and a.by>b.by
end
function T.ValidateState(value)
    if type(value)~="table" or value.dataset~=T.data.dataset or type(value.guides)~="table" or P.IsArray(value.guides) or value.guides==P.NULL then return nil end
    local out={dataset=T.data.dataset,guides={}}
    if value.selected then
        local r=value.selected;if not stamp(r) or not T.byID[r.id] then return nil end
        out.selected={id=r.id,at=r.at,by=r.by}
    end
    for id,r in pairs(value.guides) do
        local g=T.byID[id]
        if not g or not stamp(r) or not P.IsPositiveInteger(r.step) or r.step>g.steps+1 then return nil end
        local record={step=r.step,at=r.at,by=r.by}
        for _,k in ipairs({"skipped","sticky"}) do
            local list=r[k] or P.Array();if not P.IsArray(list) or #list>g.steps then return nil end
            local seen={};record[k]=P.Array()
            for _,i in ipairs(list) do if not P.IsPositiveInteger(i) or i>g.steps then return nil end;if not seen[i] then seen[i]=true;record[k][#record[k]+1]=i end end
        end
        if r.marks ~= nil then
            if type(r.marks) ~= "table" or P.IsArray(r.marks) or r.marks == P.NULL then return nil end
            record.marks = {}
            for step, entries in pairs(r.marks) do
                local number = tonumber(step)
                if type(step) ~= "string" or not P.IsPositiveInteger(number) or tostring(number) ~= step or number > g.steps or not P.IsArray(entries) or #entries > 128 then return nil end
                local copy, seen = P.Array(), {}
                for _, entry in ipairs(entries) do
                    if not P.IsPositiveInteger(entry) or entry > 2048 then return nil end
                    if not seen[entry] then seen[entry] = true; copy[#copy + 1] = entry end
                end
                if #copy > 0 then record.marks[step] = copy end
            end
        end
        out.guides[id]=record
    end
    return out
end
local function arrayState(state)
    local out={dataset=state.dataset,guides={},selected=state.selected}
    for id,r in pairs(state.guides) do
        local marks
        if r.marks and next(r.marks) then
            marks = {}
            for step, entries in pairs(r.marks) do marks[step] = P.Array(entries) end
        end
        out.guides[id]={step=r.step,at=r.at,by=r.by,skipped=P.Array(r.skipped or {}),sticky=P.Array(r.sticky or {}),marks=marks}
    end
    return out
end
function T:MergeProgress(state)
    state=self.ValidateState(state);if not state then return false end
    local p=self.Profile()
    if state.selected and self:Eligible(self.byID[state.selected.id],p)~=false and newer(state.selected,self.state.selected) then self.state.selected=state.selected;self.clock=math.max(self.clock,state.selected.at) end
    for id,r in pairs(state.guides) do if newer(r,self.state.guides[id]) then self.state.guides[id]=r;self.clock=math.max(self.clock,r.at) end end
    self:Refresh();return true
end
function T:SetSyncStatus(s)
    self.syncStatus=s
    -- The tracker banner shows the message briefly; Refresh restores the route line afterwards.
    self.syncNoticeUntil=(call(GetTime) or 0)+6
    if self.frame and self.frame:IsShown() and self.meta then self.meta:SetText(s) end
    if self.syncWindow then self.syncWindow.status:SetText(s) end
end
function T:RequestSync()
    if not self.state then return false end
    if not A.Optical then self:SetSyncStatus("Cloud sync needs the Nib Whisper: AI Assistant addon. Export and import still work.");return false end
    if not A.db.opticalEnabled then self:SetSyncStatus("Turn on Nib Auto bridge and start the automatic companion first.");return false end
    if A.pending then self:SetSyncStatus("Wait for the pending Nib request before syncing.");return false end
    local character=self:Character();if not character then return false end
    local now=call(GetTime) or 0;local captured=call(GetServerTime) or call(time) or 0
    A.sequence=A.sequence+1;local id=A.session.."-trail-"..A.sequence
    local font=A.ReserveReply and A:ReserveReply() or nil
    local ok,packet=pcall(P.EncodePacket,"NIBS1",{schema=1,requestId=id,capturedAt=captured,character=character,state=arrayState(self.state),replyFont=font})
    if not ok then self:SetSyncStatus("The progress packet is too large to sync.");return false end
    A.pending={kind="trail",requestId=id,capturedAt=captured,packet=packet,startedAt=now,nextPollAt=now+5,pollIndex=1,clock=self.clock,font=font}
    self.nextSync=now+60
    if not A:PublishOptical() then A.pending=nil;return false end
    self:SetSyncStatus("Syncing route progress…")
    return true
end
function T:ImportSync(packet)
    local pending=A.pending;if not pending or pending.kind~="trail" then return false end
    local ok,r=pcall(P.DecodePacket,"NIBP1",packet)
    if not ok or type(r)~="table" or r.schema~=1 or r.requestId~=pending.requestId or r.capturedAt~=pending.capturedAt or r.character~=self:Character() then return false end
    A.pending=nil;A:ClearOptical()
    local now=call(GetTime) or 0
    if r.error then self.nextSync=now+90;self.syncBackoff=self.nextSync;self:SetSyncStatus(P.SanitizeText(r.error,230));return false end
    local changedDuring=self.clock~=pending.clock
    if not self:MergeProgress(r.state) then self.nextSync=now+90;self.syncBackoff=self.nextSync;self:SetSyncStatus("Sync rejected: different route data or invalid progress.");return false end
    self.dirty=changedDuring
    self.syncBackoff=nil
    self.nextSync=now+(changedDuring and 20 or 300)
    self:SetSyncStatus("Route progress synced. Cloud folder delivery depends on your sync app.")
    return true
end
function T:SyncTick(now)
    if A.pending and A.pending.kind=="trail" then
        if now-A.pending.startedAt>35 or A.pending.manualOnly then A.pending=nil;A:ClearOptical();self.nextSync=now+90;self.syncBackoff=self.nextSync;self:SetSyncStatus("Sync timed out. Check the automatic companion or export progress manually.") end
        return
    end
    if not A.db.trailSync or not A.Optical or not A.db.opticalEnabled or A.pending or call(InCombatLockdown) or now<(self.syncBackoff or 0) then return end
    if not self.nextSync then self.nextSync=now+12 end
    local dirtyReady=self.dirty and now-(self.lastChange or 0)>=12 and now-(self.lastSyncAttempt or -60)>=25
    if dirtyReady or now>=self.nextSync then self.lastSyncAttempt=now;self:RequestSync() end
end
function T:ExportProgress()
    local character=self:Character();if not character then return nil end
    local ok,packet=pcall(P.EncodePacket,"NIBT1",{schema=1,character=character,state=arrayState(self.state)})
    return ok and packet or nil
end
function T:ImportProgress(packet)
    local ok,r=pcall(P.DecodePacket,"NIBT1",packet)
    if not ok or type(r)~="table" or r.schema~=1 or not self:Character() or r.character~=self:Character() or not self:MergeProgress(r.state) then return false end
    self.dirty=true;self.lastChange=call(GetTime) or 0;self:SetSyncStatus("Progress merged for this character.");return true
end
function T:ShowSync()
    if not self.syncWindow then
        local f=CreateFrame("Frame","NibTrailSync",UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil);self.syncWindow=f
        f:SetSize(560,325);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true);A.UI:Scaled(f)
        if f.SetBackdrop then f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=15,insets={left=4,right=4,top=4,bottom=4}});f:SetBackdropColor(.025,.065,.065,.98) end
        local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",18,-16);title:SetText("Nib Trail progress sync")
        local explain=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");explain:SetPoint("TOPLEFT",18,-46);explain:SetWidth(515);explain:SetJustifyH("LEFT");explain:SetText("Use the same synced folder on both computers. Auto bridge sends only route progress to your companion. Manual transfer works without a shared folder.")
        local close=CreateFrame("Button",nil,f,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",-4,-4);close:SetScript("OnClick",function()f:Hide()end)
        local function button(text,x,y,w,fn)local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate");b:SetSize(w,24);b:SetPoint("TOPLEFT",x,y);b:SetText(text);b:SetScript("OnClick",fn);A.UI.ClipButton(b);return b end
        f.toggle=button("Cloud sync",18,-88,154,function(b)
            A.db.trailSync=not A.db.trailSync;b:SetText(A.db.trailSync and "Cloud sync: on" or "Cloud sync: off")
            if A.db.trailSync and not A.Optical then
                A.db.trailSync=false;b:SetText("Cloud sync: off");T:RequestSync()
            elseif A.db.trailSync then
                A.db.chatMode = A:GetChatMode()
                A.db.opticalEnabled = true
                T.nextSync=0;T:RequestSync()
            else
                if A.pending and A.pending.kind=="trail" then A.pending=nil;A:ClearOptical() end;T:SetSyncStatus("Automatic sync off. Local progress is still saved.")
            end
        end)
        button("Sync now",182,-88,112,function()T:RequestSync()end)
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",18,-128);scroll:SetSize(493,113)
        f.edit=CreateFrame("EditBox",nil,scroll);f.edit:SetMultiLine(true);f.edit:SetAutoFocus(false);f.edit:SetFontObject(GameFontHighlightSmall);f.edit:SetSize(486,112);f.edit:SetMaxBytes(P.MAX_PACKET);scroll:SetScrollChild(f.edit)
        button("Export / copy",18,-253,140,function()local p=T:ExportProgress();if p then f.edit:SetText(p);f.edit:SetFocus();f.edit:HighlightText();T:SetSyncStatus("Press Ctrl+C, then paste and import on the same character on the other PC.") end end)
        button("Import / merge",166,-253,140,function()if T:ImportProgress(f.edit:GetText()) then f.edit:SetText("") else T:SetSyncStatus("Wrong character, route version, or incomplete progress packet.") end end)
        f.status=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");f.status:SetPoint("TOPLEFT",18,-286);f.status:SetWidth(518);f.status:SetJustifyH("LEFT")
        if UISpecialFrames then table.insert(UISpecialFrames,"NibTrailSync") end
    end
    self.syncWindow.toggle:SetText(A.db.trailSync and "Cloud sync: on" or "Cloud sync: off")
    self.syncWindow.status:SetText(self.syncStatus or "Export copies progress for this character only.");self.syncWindow:Show()
end
