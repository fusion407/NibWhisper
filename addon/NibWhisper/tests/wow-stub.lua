NibWhisper = {}
unpack = table.unpack
local methods = {}
local function frame()
    return setmetatable({shown = true, width = 200, height = 200, scripts = {}, messages = {}, text = ""}, {__index = methods})
end
function CreateFrame() return frame() end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetCenter() return 500,400 end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 2 end
function methods:CreateTexture() return frame() end
function methods:CreateFontString() return frame() end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(shown) self.shown=shown end
function methods:IsShown() return self.shown end
function methods:SetText(text) self.text=text end
function methods:SetFrameStrata(value) self.strata=value end
function methods:SetAttribute(name,value) self.attributes=self.attributes or {};self.attributes[name]=value end
function methods:GetText() return self.text end
function methods:GetStringHeight() return math.ceil(#self.text/80)*12 end
function methods:GetStringWidth() return #(self.text or "")*6 end
function methods:GetFontString() self.fontString=self.fontString or frame(); self.fontString.text=self.text; return self.fontString end
function methods:SetWordWrap() end
function methods:SetAlpha() end
function methods:SetNormalTexture() self.normal=frame() end
function methods:GetNormalTexture() return self.normal end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return self.checked end
function methods:AddMessage(text) self.messages[#self.messages+1]=text end
function methods:Clear() self.messages={} end
function methods:SetFocus() self.focus=true end
function methods:ClearFocus() self.focus=false end
for _,name in ipairs({'SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetClampedToScreen','SetPoint','ClearAllPoints','SetFrameLevel','SetMovable','EnableMouse','RegisterForDrag','RegisterForClicks','StartMoving','StopMovingOrSizing','SetMultiLine','SetAutoFocus','SetFontObject','SetMaxBytes','SetTextInsets','SetScrollChild','HighlightText','SetTextColor','SetJustifyH','SetFading','SetMaxLines','SetIndentedWordWrap','EnableMouseWheel','ScrollUp','ScrollDown','ScrollToBottom','SetAllPoints','SetTexture','SetTexCoord','SetHighlightTexture','RegisterEvent','SetOwner','AddLine','SetScale','SetColorTexture'}) do methods[name]=function() end end
UIParent=frame(); Minimap=frame(); GameTooltip=frame(); DEFAULT_CHAT_FRAME=frame()
function methods:SetJustifyV() end
function methods:SetVerticalScroll() end
function methods:SetMaxLetters() end
function methods:SetResizable() end
function methods:SetResizeBounds() end
function methods:StartSizing() end
BackdropTemplateMixin={}; GameFontHighlightSmall={}; GameFontHighlight={}; UISpecialFrames={}
clock=100
function GetTime() return clock end
function GetServerTime() return 1794333600 end
function time() return 1794333600 end
function GetBuildInfo() return '1.60.1','69977','Nov 2026',16001 end
function GetLocale() return 'enUS' end
WOW_PROJECT_ID=20; WOW_PROJECT_CAMELOT=20
function UnitClass() return 'Paladin','PALADIN' end
function UnitRace() return 'Human','Human' end
function UnitFactionGroup() return 'Alliance' end
function UnitLevel() return 12 end
function UnitXP() return 1000 end
function UnitXPMax() return 5000 end
function GetXPExhaustion() return 2000 end
function UnitIsDeadOrGhost() return false end
combat=false
function InCombatLockdown() return combat end
function GetRealZoneText() return 'Elwynn Forest' end
function GetSubZoneText() return 'Goldshire' end
C_Map={GetBestMapForUnit=function() return 1429 end, GetPlayerMapPosition=function() return {GetXY=function() return .42,.65 end} end, GetMapInfo=function(id) if id==1429 then return {name='Elwynn Forest'} end end}
C_QuestLog={GetNumQuestLogEntries=function() return 2,1 end,GetInfo=function(i) if i==1 then return {isHeader=true,title='Elwynn Forest',isCollapsed=false} else return {questID=7,title='Kobold Camp Cleanup',level=2} end end,GetQuestObjectives=function() return {{text='Kobolds slain: 3/10',numFulfilled=3,numRequired=10,finished=false,type='monster'}} end,GetAllCompletedQuestIDs=function() return {783, 7, 33} end,ReadyForTurnIn=function() return false end}
C_SkillInfo={GetNumSkillLines=function() return 2 end,GetSkillLineInfo=function(i) if i==1 then return {name='Professions',isHeader=true,isCollapsed=false} else return {name='Alchemy',rank=99,maxRank=150,skillID=171,isHeader=false} end end}
loadedSlots={}; slotLoads={}
C_AddOns={GetNumAddOns=function() return 2 end,GetAddOnInfo=function(i) return i==1 and 'RXPGuides' or 'TomTom','Test addon' end,GetAddOnMetadata=function() return 'v4.11.35' end,IsAddOnLoaded=function(name) return loadedSlots[name] or name=='RXPGuides' or name=='TomTom' end,LoadAddOn=function(name) loadedSlots[name]=true; slotLoads[#slotLoads+1]=name; if slotCallback then slotCallback() end; return true end}
RXPCData={currentGuideName='01-06 Elwynn Forest',currentGuideGroup='RestedXP Forever Guide (A)',currentStep=2,currentStepId=22,guideProgress={}}
rxp={currentGuide={name='01-06 Elwynn Forest',group='RestedXP Forever Guide (A)',key='key',steps={{elements={{text='Accept a quest',questId=7}}},{active=true,elements={{text='|cffff0000Defeat kobolds|r',questId=7,completed=false}}},{elements={{text='Return to the abbey',questId=7}}}}}}
rxp.GetGuideTable=function(group,name) if group=='RestedXP Forever Guide (A)' and name=='01-06 Elwynn Forest' then return rxp.currentGuide end end
rxp.LoadGuideTable=function(self,group,name) selectedGuide={group,name} end
LibStub=function() return {GetAddon=function() return rxp end} end
TomTom={AddWaypoint=function(self,map,x,y,options) waypoint={map,x,y,options}; return 'uid' end}
QuestMapFrame_OpenToQuestDetails=function(id) openedQuest=id end
