-- Independent route reader. Guide commands are data, never executable Lua.
local A = _G.NibWhisper
if not A then return end
local P, C, D = A.Protocol, A.Context, A.TrailData
if not D then return end
local T = {data=D, byID={}, parsed={}, maps={}, pinMode=true}
A.Trail = T
for _, g in ipairs(D.chapters) do T.byID[g.id]=g end
local call = C.Call
local questData = A.QuestLinks or {names={}, requirements={}, items={}}
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function condition(s)
    local first, second = s:match("^(.-)%s*<<%s*(.*)$")
    return trim(first or s), trim(second)
end
local function text(s)
    return P.SanitizeText((s or ""):gsub("|cRXP_[A-Z]+_",""):gsub("::%d+", ""), 1000)
end
local routeColors = {FRIENDLY="ff46ef82", ENEMY="ffff794d", WARN="ffffd86b", BUY="ffffd86b", LOOT="ffffd86b", PICKUP="ffffd86b", PICK="ff9fd8ff", TURNIN="ffffd86b"}
local linkKinds = {FRIENDLY="Friendly NPC", ENEMY="Enemy", LOOT="Item", PICK="World object", BUY="Vendor item"}
local function routeText(raw)
    if not raw then return nil end
    local markup = {}
    local function keep(value)
        markup[#markup + 1] = value
        return "~NIB" .. #markup .. "~"
    end
    -- Named NPCs, enemies, items and objects become links the tracker can open an info card for.
    raw = raw:gsub("|cRXP_([A-Z]+)_([^|]+)|r", function(kind, name)
        local clean = text(name)
        if not linkKinds[kind] or clean == "" or #clean > 80 then return nil end
        return keep("|c" .. (routeColors[kind] or "ffe5e7ff") .. "|Hnib:" .. kind .. ":" .. clean .. "|h") .. name .. keep("|h|r")
    end)
    raw = raw:gsub("|cRXP_([A-Z]+)_", function(kind) return keep("|c" .. (routeColors[kind] or "ffe5e7ff")) end)
    raw = raw:gsub("|r", function() return keep("|r") end)
    raw = raw:gsub("|[Tt]([^|]+)|[Tt]", function(spec)
        local file = spec:match("^([^:]+)")
        if file and file:match("^%d%d%d%d%d%d?%d?%d?%d?$") then return keep("|T" .. file .. ":12:12|t") end
        if file and file:lower():gsub("\\", "/") == "interface/worldmap/chatbubble_64grey.blp" then
            return keep("|TInterface\\WorldMap\\ChatBubble_64Grey.blp:12:12|t")
        end
        return ""
    end)
    return (text(raw):gsub("~NIB(%d+)~", function(index) return markup[tonumber(index)] or "" end))
end
local function split(s, separator)
    local r={}; for x in s:gmatch("[^"..separator.."]+") do r[#r+1]=trim(x) end; return r
end
local known={}
for k in ("alliance horde neutral warrior paladin hunter rogue priest shaman mage warlock druid monk deathknight demonhunter evoker human dwarf gnome nightelf undead scourge orc troll tauren skyborne bloodelf draenei goblin worgen male female era classic forever camelot tbc wotlk cata mop retail sod som ssf hardcore softcore skip"):gmatch("%w+") do known[k]=true end
local function comparison(expr,value)
    local op,n=expr:match("^%s*([<>]?=?)%s*([%d.]+)%s*$");n=tonumber(n)
    if not n or not value then return nil end
    if op=="<" then return value<n elseif op==">" then return value>n elseif op=="<=" then return value<=n elseif op==">=" then return value>=n end
    return value==n
end
function T.Profile()
    local p=C.Player(); p.tags={forever=true,camelot=true,era=true,classic=true}
    for _, tag in ipairs({p.class,p.race,p.faction}) do p.tags[tag:lower():gsub("%s+", "")]=true end
    if p.tags.scourge then p.tags.undead=true elseif p.tags.undead then p.tags.scourge=true end
    local sex=call(UnitSex,"player"); if sex==2 then p.tags.male=true elseif sex==3 then p.tags.female=true end
    p.hardcore=call(C_GameRules and C_GameRules.IsHardcoreActive)==true
    p.tags.hardcore=p.hardcore; p.tags.softcore=not p.hardcore
    p.season=0 -- Forever is not SoD or Season of Mastery.
    p.phase=tonumber(A.db and A.db.trailPhase)
    p.rate=tonumber(A.db and A.db.trailRate) or 1
    p.tags.ssf=call(C_GameRules and C_GameRules.IsSelfFoundAllowed)==true
    return p
end
-- Whitespace is AND, slash is OR. Unknown tokens are displayed for review.
function T.Matches(expr,p)
    if not expr or expr=="" then return true end
    local unknown=false
    for _, branch in ipairs(split(expr,"/")) do
        local valid, unresolved=true,false
        for raw in branch:gmatch("%S+") do
            local neg=raw:sub(1,1)=="!"; local k=(neg and raw:sub(2) or raw):lower()
            local result
            if tonumber(k) and p.level then result=p.level>=tonumber(k)
            elseif p.tags[k]~=nil or known[k] then result=p.tags[k]==true
            else unresolved=true end
            if result~=nil and result==neg then valid=false; break end
        end
        if valid and not unresolved then return true end
        if valid then unknown=true end
    end
    if unknown then return nil end
    return false
end
function T:Eligible(g,p)
    if not g or (g.faction~="Unknown" and g.faction~=p.faction) then return false end
    local unknown=false
    for _, v in ipairs(g.conditions) do local m=self.Matches(v,p); if m==false then return false elseif m==nil then unknown=true end end
    for line in (g.header or ""):gmatch("[^\r\n]+") do
        local tag,value=trim(line):match("^#(season)%s+(.+)$")
        if tag and not (","..value:gsub("%s","")..","):find(","..p.season..",",1,true) then return false end
        local rate=trim(line):match("^#xprate%s+(.+)$")
        if rate and comparison(rate,p.rate)==false then return false end
    end
    if unknown then return nil end
    return true
end
function T.Parse(raw)
    local s={flags={},entries={},collectionQuests={}}
    for line in raw:gmatch("[^\r\n]+") do
        line=trim(line)
        if line:sub(1,2)~="--" and line~="" then
            local body,filter=condition(line)
            if body=="step" then s.condition=filter
            elseif body:sub(1,1)=="#" then
                local k,v=body:match("^#([%w/]+)%s*(.*)$")
                if k then s.flags[#s.flags+1]={kind=k:lower(),value=v,condition=filter} end
            else
                local left,desc=body:match("^(.-)%s*>>%s*(.*)$")
                local tag,args=trim(left or body):match("^%.([%w]+)%s*(.*)$")
                if tag then
                    local kind = tag:lower()
                    local code, annotation
                    -- A link's address may itself contain "--", so it is never split into an annotation.
                    if kind ~= "link" then code, annotation = args:match("^(.-)%s*%-%-%s*(.*)$") end
                    local entry = {kind=kind,args=trim(code or args),annotation=text(annotation),desc=text(desc),display=routeText(desc),condition=filter}
                    if kind == "disablecheckbox" and s.entries[#s.entries] then
                        -- RestedXP applies this to the preceding element. Keep its index for saved objective marks.
                        s.entries[#s.entries].checkboxCondition = filter
                    elseif kind == "collect" then
                        local item, quest = entry.args:match("^(%d+)%s*,%s*%d+%s*,%s*(%d+)")
                        if item and quest then s.collectionQuests[tonumber(item)] = tonumber(quest) end
                    end
                    s.entries[#s.entries+1] = entry
                elseif desc or body:sub(1,1)=="+" then
                    local note = desc or body:sub(2)
                    s.entries[#s.entries+1]={kind="note",desc=text(note),display=routeText(note),condition=filter}
                end
            end
        end
    end
    return s
end
function T:Chapter(g)
    if self.parsed[g.id] then return self.parsed[g.id] end
    local chapter={steps={},labels={}}
    for i, raw in ipairs(D.bodies[g.id]) do
        local step=self.Parse(raw); chapter.steps[i]=step
        for _, f in ipairs(step.flags) do if f.kind=="label" then chapter.labels[f.value]=i end end
    end
    self.parsed[g.id]=chapter
    return chapter
end
function T.MapID(value)
    local id=tonumber(value); if id then return id end
    if T.maps[value] then return T.maps[value] end
    if value=="StormwindClassic" then return 1453 elseif value=="EPLClassic" then return 1423 end
    if not C_Map or not C_Map.GetMapInfo then return nil end
    if not T.mapScan then
        T.mapScan=true
        for i=1400,1480 do local m=call(C_Map.GetMapInfo,i);if m and m.name then T.maps[m.name]=i end end
        local children=call(C_Map.GetMapChildrenInfo,947,nil,true)
        if type(children)=="table" then for _,m in ipairs(children) do if m.name and m.mapID then T.maps[m.name]=T.maps[m.name] or m.mapID end end end
    end
    return T.maps[value]
end
local function world(mapID,x,y)
    local instance, pos = call(C_Map and C_Map.GetWorldPosFromMapPos,mapID,call(CreateVector2D,x,y))
    if pos and pos.GetXY then local wy,wx=call(pos.GetXY,pos);return wx,wy,instance end
end
T.World=world
function T.Point(args)
    local a=split(args,","); if #a<3 then return nil end
    local zone, instance=a[1]:match("^(.+)/(%d+)$"); local id=T.MapID(zone or a[1]); local x,y=tonumber(a[2]),tonumber(a[3]); local radius=tonumber(a[4]);
    if not id or not P.IsFinite(x) or not P.IsFinite(y) then return nil end
    if instance then
        local h=call(function() return LibStub("HereBeDragons-2.0",true) end)
        local nx,ny
        if h then nx,ny=call(h.GetZoneCoordinatesFromWorldInstance,h,x,y,tonumber(instance),id) end
        if not nx or not ny then
            local x0,y0,ins=world(id,0,0); local x1,y1=world(id,0.5,0.5)
            if ins==tonumber(instance) and x0 and x1 and x0~=x1 and y0~=y1 then nx,ny=(x-x0)/(2*(x1-x0)),(y-y0)/(2*(y1-y0)) end
        end
        if not nx or not ny then return nil end
        x,y=nx*100,ny*100
    end
    if not P.IsFinite(x) or not P.IsFinite(y) or x<0 or x>100 or y<0 or y>100 then return nil end
    return {mapID=id,x=x,y=y,radius=radius and radius>0 and radius or nil, hidden=a[5]~=nil and radius~=nil and radius>0}
end
function T.Distance(point,p)
    if not point or not p.mapID or p.x==nil or p.y==nil then return nil end
    local x,y,i=world(p.mapID,p.x/100,p.y/100);local xx,yy,j=world(point.mapID,point.x/100,point.y/100)
    if x and xx and i==j then return math.sqrt((xx-x)^2+(yy-y)^2),xx-x,yy-y end
end
local function quests()
    local log, q = nil,C_QuestLog or {}
    local function fallback(id)
        if not log then
            log={a={},d={}};local data=C.Quests()
            for _,v in ipairs(data.active) do log.a[v.id]=v end
            for _,v in ipairs(data.completedIds) do log.d[v]=true end
            log.coverage, log.doneCoverage = data.activeCoverage, data.completionCoverage
        end
        local done = log.d[id]
        if done == nil and log.doneCoverage == "complete" then done = false end
        return log.a[id],done,log.coverage
    end
    return function(kind,id,index)
        if not id then return nil end
        id = math.abs(id)
        local done=call(q.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted,id)
        if done==nil then local _,d=fallback(id);done=d end
        if (A.observedTurnIns or {})[id] then done=true end
        if kind=="turnin" or kind=="isquestturnedin" or kind=="isquestnotturnedin" then return done end
        local on=call(q.IsOnQuest,id)
        if on==nil then local a,_,coverage=fallback(id); if a then on=true elseif coverage=="complete" then on=false end end
        if kind=="accept" then
            if done == true or on == true then return true end
            if done == false and on == false then return false end
            return nil
        end
        if kind=="isonquest" or kind=="isnotonquest" then return on end
        local ready=call(q.ReadyForTurnIn or q.IsComplete or IsQuestComplete,id)
        if kind=="complete" and done==true then return true end
        if ready==true or ready==1 then return true end
        if index and index>0 then
            local obj=call(q.GetQuestObjectives,id)
            if obj and obj[index] then
                local goal = obj[index]
                return goal.finished == true or goal.finished == 1 or
                    (type(goal.numFulfilled) == "number" and type(goal.numRequired) == "number" and goal.numRequired > 0 and goal.numFulfilled >= goal.numRequired)
            end
            local a=fallback(id); if a and a.objectives[index] then return a.objectives[index].finished==true end
        end
        if ready~=nil then return false end
        if on==false then return false end
    end
end
local function questName(id)
    local name = id and call(C_QuestLog and C_QuestLog.GetTitleForQuestID,id)
    if id and (type(name) ~= "string" or name == "") then name = questData.names[id] end
    return name and name ~= "" and text(name) or nil
end

local function itemName(id, annotation)
    local name = call(C_Item and C_Item.GetItemNameByID, id) or call(GetItemInfo, id)
    if type(name) == "string" and name ~= "" then return text(name) end
    local hint = trim((annotation or ""):gsub("%s*%([xX]?%d+%)%s*$", ""))
    local knownName = questData.items and questData.items[id]
    if knownName then return text(knownName) end
    if hint ~= "" and not hint:match("^[%d%p]+$") then return hint end
end

local function missingPrerequisite(id, q)
    local requirements = id and questData.requirements[id]
    if not requirements or q("accept", id) ~= false then return nil end
    if call(C_QuestLog and C_QuestLog.IsQuestAvailable, id) == true then return nil end
    local function name(quest) return questName(quest) or ("quest " .. quest) end
    for _, quest in ipairs(requirements.all) do
        if q("turnin", quest) == false then return "Turn in " .. name(quest) end
    end
    if #requirements.any > 0 then
        local choices, knownMissing = {}, true
        for _, quest in ipairs(requirements.any) do
            if q("turnin", quest) ~= false then knownMissing = false end
            choices[#choices+1] = name(quest)
        end
        if knownMissing then return "Turn in " .. table.concat(choices, " or ") end
    end
    if requirements.active > 0 and q("isonquest", requirements.active) == false then
        return "Have " .. name(requirements.active) .. " in your quest log"
    end
    if requirements.started > 0 and q("accept", requirements.started) == false then
        return "Start " .. name(requirements.started)
    end
end
local function spellKnown(id)
    local book = C_SpellBook or {}
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    return call(book.IsSpellKnown, id, bank) == true
        or call(book.IsSpellKnown, id) == true
        or call(C_Spell and C_Spell.IsPlayerSpell, id) == true
        or call(IsPlayerSpell, id) == true
        or call(IsSpellKnown, id) == true
end
local gates={isonquest=true,isnotonquest=true,isquestcomplete=true,isquestnotcomplete=true,isquestturnedin=true,isquestnotturnedin=true,isquestavailable=true}
local gatesNeg={isnotonquest=true,isquestnotcomplete=true,isquestnotturnedin=true}
local quiet={target=true,mob=true,unitscan=true,trainer=true,line=true,link=true,timer=true,subzone=true,zone=true,group=true,dungeon=true,
    disablecheckbox=true,itemstat=true,money=true,skill=true,skipgossip=true,skipgossipid=true,cooldown=true,bindlocation=true,
    pin=true,usespell=true,maxlevel=true,solo=true,addquestitem=true,enabledungeon=true,bronzetube=true,showwhiledead=true,
    reputation=true,blastedlands=true,macro=true,aura=true}
local manualNames={fly="Take the flight path",fp="Learn the flight path",hs="Use your Hearthstone",home="Set your Hearthstone",vendor="Visit the vendor",use="Use the quest item",cast="Cast the spell",bankdeposit="Deposit the items at the bank",bankwithdraw="Withdraw the items from the bank",abandon="Review the quest to abandon",destroy="Review the item to discard",gossipoption="Talk to the NPC",equip="Equip the item",stable="Visit the stable master"}
local function xpReached(expr,p)
    local reverse,n,x=expr:match("^(<?)%s*(%d+)([%+%.%-]?%d*)$");n=tonumber(n);x=tonumber(x) or 0
    if not n or not p.level or p.xp==nil or p.xpMax==nil then return nil end
    local ok=p.level>n or (p.level==n and (x<=0 or p.xp>=(x<1 and p.xpMax*x or x))) or (x<0 and p.level==n-1 and p.xp>=p.xpMax+x)
    return ok~=(reverse=="<")
end
T.XPReached=xpReached
-- One tracker tick asks about the same step several times. A profile carrying a memo table shares those results.
function T:Evaluate(g,index,p,q)
    local memo=p.memo
    local cached=memo and memo[g]
    if cached and cached[index]~=nil then return cached[index] or nil end
    local r=self:EvaluateStep(g,index,p,q)
    if memo then cached=cached or {};memo[g]=cached;cached[index]=r or false end
    return r
end
function T:EvaluateStep(g,index,p,q)
    local s=self:Chapter(g).steps[index]; if not s then return nil end
    local r={lines={},display={},controls={},linePoints={},links={},points={},targets={},questIds={},checks=0,all=true,blocked={}}
    local m=self.Matches(s.condition,p);if m==false then r.skip=true;r.skipReason="does not apply to your character";return r elseif m==nil then r.review=true end
    for _, f in ipairs(s.flags) do
        local active=self.Matches(f.condition,p)
        if active==nil then r.review=true elseif active then
            local k,v=f.kind,f.value
            if k=="optional" then r.optional=true elseif k=="completewith" then r.sticky=v elseif k=="sticky" then r.sticky="end"
            elseif k=="requires" then r.requires=v elseif k=="loop" then r.loop=true
            elseif k=="hardcore" or k=="hardcoreserver" or k=="ssf" then if not p.tags[k=="ssf" and "ssf" or "hardcore"] then r.skip=true end
            elseif k=="softcore" or k=="softcoreserver" then if p.hardcore then r.skip=true end
            elseif k=="som" or k=="sod" or k=="wotlk" or k=="tbc" then r.skip=true
            elseif k=="season" then if not (","..v:gsub("%s","")..","):find(","..p.season..",",1,true) then r.skip=true end
            elseif k=="maxlevel" and tonumber(v) and p.level and p.level>tonumber(v) then r.skip=true
            elseif k=="phase" or k=="xprate" then
                local match=comparison(v,k=="phase" and p.phase or (k=="xprate" and p.rate or nil))
                if match==false then r.skip=true elseif match==nil then r.review=true end
            end
        end
    end
    if r.skip then return r end
    local lastPoint,firstPending,seen
    seen={}
    local record = self.state and self.state.guides[g.id]
    local marks = record and record.marks and record.marks[tostring(index)] or {}
    local marked = {}
    for _, entry in ipairs(marks) do marked[entry] = true end
    local function addLine(description, display, prefix, control, point, link)
        prefix = prefix or ""
        local index = #r.lines + 1
        r.links[index] = link
        r.lines[index] = prefix .. description
        r.display[index] = prefix .. (display or description)
        r.controls[index] = control
        r.linePoints[index] = point
    end
    local function check(done,description,id,display,entry,kind,merchant,checkboxCondition)
        if id and not seen[id] then seen[id]=true;r.questIds[#r.questIds+1]=id end
        if checkboxCondition ~= nil and self.Matches(checkboxCondition,p) == true then
            if description ~= "" then addLine(description,display,nil,nil,lastPoint) end
            return
        end
        -- A collection may deliberately be routed before its quest is picked up.
        local missing = kind ~= "collect" and not done and id and missingPrerequisite(math.abs(id), q)
        if missing then
            if not r.blocked[id] then
                r.blocked[id] = missing
                addLine((questName(math.abs(id)) or "Quest") .. " unavailable. " .. missing .. " first.")
            end
            return
        end
        local checked = marked[entry] == true
        r.checks=r.checks+1; r.all=r.all and (done==true or checked)
        if not done and not checked and not r.activeEntry then firstPending=lastPoint; r.activeEntry=entry end
        if description~="" then
            addLine(description,display,checked and "[Marked] " or done==true and "[Done] " or "[ ] ",
                {step=index, entry=entry, automatic=done==true, marked=checked, kind=kind, merchant=merchant, quest=id and math.abs(id) or nil},lastPoint)
        end
    end
    for entry, e in ipairs(s.entries) do
        local active=self.Matches(e.condition,p)
        if active==nil then r.review=true end
        if active~=false then
            local k,args=e.kind,e.args or ""; local a=split(args,",");local id=tonumber(a[1]);local description=e.desc
            if k=="goto" or k=="waypoint" then
                local point=self.Point(args)
                if point then point.title=description~="" and description or g.title;lastPoint=point;if not point.hidden then r.points[#r.points+1]=point end end
                if description~="" then addLine(description,e.display,nil,nil,point) end
            elseif k=="target" or k=="mob" or k=="unitscan" then
                local name = trim(args:gsub("^[+%-]", ""))
                if name ~= "" and #name <= 80 and not name:find("[%c|%[%];,]") then r.targets[#r.targets+1] = name end
            elseif k=="accept" or k=="turnin" or k=="complete" then
                local title=questName(id and math.abs(id))
                local objectiveIndex = tonumber(a[2])
                local instruction = description ~= "" and description or ((k=="turnin" and "Turn in" or k=="accept" and "Accept" or "Complete").." "..(title or "the quest"))
                local styled = description ~= "" and e.display or instruction
                if k == "complete" and id and objectiveIndex then
                    local objectives = call(C_QuestLog and C_QuestLog.GetQuestObjectives, math.abs(id))
                    local objective = type(objectives) == "table" and objectives[objectiveIndex]
                    if description == "" then
                        if objective and type(objective.text) == "string" and objective.text ~= "" then instruction = text(objective.text)
                        elseif e.annotation ~= "" then instruction = e.annotation
                        elseif title then instruction = title .. " — objective " .. objectiveIndex end
                        styled = instruction
                    end
                    if objective and type(objective.numFulfilled) == "number" and type(objective.numRequired) == "number" and objective.numRequired > 0 and not instruction:find("%d+%s*/%s*%d+") then
                        local count = string.format("  (%d/%d)", objective.numFulfilled, objective.numRequired)
                        instruction = instruction .. count
                        styled = styled .. count
                    end
                end
                check(q(k,id,objectiveIndex),instruction,id,styled,entry,k,nil,e.checkboxCondition)
            elseif k=="collect" then
                local count=call(C_Item and C_Item.GetItemCount or GetItemCount,id)
                local needed, quest = tonumber(a[2]) or 1, tonumber(a[3])
                local name = itemName(id,e.annotation) or "the required item"
                local progress = count and string.format(" (%d/%d)", math.min(count,needed),needed) or (needed > 1 and (" ×" .. needed) or "")
                local collected = (count and count >= needed) or q("turnin",quest) or (a[4] == "1" and q("accept",quest))
                check(collected,description~="" and description or ("Collect "..name..progress),quest,e.display,entry,k,nil,e.checkboxCondition)
            elseif k=="train" and id then
                local flags = tonumber(a[2]) or 0
                local learned = spellKnown(id) ~= (math.floor(flags / 2) % 2 == 1)
                if flags % 2 == 1 then
                    if learned then r.skip = true end
                    if description ~= "" then addLine(description, e.display) end
                else
                    local spell = call(C_Spell and C_Spell.GetSpellName,id) or call(GetSpellInfo,id)
                    check(learned,description~="" and description or ("Train "..(spell or "the ability")),nil,e.display,entry,k,nil,e.checkboxCondition)
                end
            elseif k=="xp" then
                local done=xpReached(a[1] or "",p)
                if a[2] then if done==true then r.skip=true; r.jump=a[3] end
                else check(done,description~="" and description or ("Reach level "..((a[1] or ""):match("%d+") or "target")),nil,e.display,entry,k,nil,e.checkboxCondition) end
            elseif k=="link" then
                -- Only web addresses are offered. Guide lines that carry script commands stay plain text.
                local url = #args <= 300 and args:match("^https?://[%w%-%._~:/%?#@!%$&'%(%)%*%+,;=%%]+$")
                if description~="" then addLine(description,e.display,nil,nil,nil,url or nil) end
            elseif gates[k] then
                local status,unknown=false,false
                for _, v in ipairs(a) do local n=tonumber(v); if n then
                    local done
                    if k=="isquestavailable" then done=call(C_QuestLog and C_QuestLog.IsQuestAvailable,n) else done=q(k,n) end
                    if done==true then status=true elseif done==nil then unknown=true end
                elseif v=="account" then unknown=true end end
                if unknown and not status then r.review=true
                elseif status==(gatesNeg[k]==true) then r.skip=true; r.skipReason="quest condition not met" end
                if description~="" then addLine(description,e.display,nil,nil,lastPoint) end
            elseif k=="zoneskip" or k=="subzoneskip" then
                local pass
                if k=="subzoneskip" then if p.subzone~="" then pass=p.subzone==a[1] end
                elseif p.mapID then for _, z in ipairs(split(a[1] or "","/+") ) do if self.MapID(z) then pass=(pass==true or self.MapID(z)==p.mapID) end end end
                if pass~=nil and pass~=((tonumber(a[2]) or 0)%2==1) then r.skip=true end
            elseif k=="itemcount" then
                local count,knownCount=0,false
                for item in (a[1] or ""):gmatch("%d+") do local amount=call(C_Item and C_Item.GetItemCount or GetItemCount,tonumber(item),a[3]~=nil);if amount~=nil then knownCount=true;count=count+amount end end
                local need=a[2] or "";if need:match("^%d+$") then need=">="..need end
                local matches=knownCount and comparison(need,count)
                if not knownCount or matches==nil then r.review=true elseif not matches then r.skip=true end
            elseif k=="dungeon" and g.mode~="Dungeon quests" then
                local dungeonMode=g.mode=="Dungeon route"; if (args:sub(1,1)=="!" and dungeonMode) or (args:sub(1,1)~="!" and not dungeonMode) then r.skip=true end
            elseif k=="note" then
                if description~="" then addLine(description,e.display) end
            elseif k=="use" and (description=="" or s.collectionQuests[id]) then
                if description~="" then addLine(description,e.display) end
            elseif not quiet[k] and (description~="" or manualNames[k]) then
                check(false,description~="" and description or manualNames[k],nil,e.display,entry,k,id,e.checkboxCondition)
            elseif description~="" then addLine(description,e.display) end
        end
    end
    r.point=(firstPending and not firstPending.hidden and firstPending) or r.points[1]
    if r.checks == 0 and next(r.blocked) then r.skip=true; r.skipReason="missing quest prerequisite" end
    if r.loop then local dist;for _, point in ipairs(r.points) do local n=self.Distance(point,p);if n and (not dist or n<dist) then dist=n;r.point=point end end end
    if r.checks==0 and r.point and r.point.radius and #r.lines==0 and #r.points==1 then local n=self.Distance(r.point,p);r.checks=1;r.all=n~=nil and n<=r.point.radius end
    if #r.lines==0 and r.point then r.lines[1]=string.format("Travel to map %d at %.2f, %.2f",r.point.mapID,r.point.x,r.point.y) end
    if r.review then r.lines[#r.lines+1]="Some route conditions need review; use Done or Skip after checking them." end
    r.complete=r.checks>0 and r.all and not r.review
    if r.skip then r.point=nil; r.points={}; r.linePoints={}; r.links={}; r.targets={} end
    return r
end

function T:Character()
    local id=call(UnitGUID,"player")
    if type(id)=="string" and id:match("^Player%-%d+%-%x+$") then return id end
end
function T:Stamp()
    local now=(call(GetServerTime) or call(time) or 0)*1000.0
    self.clock=math.max(now,(self.clock or 0)+1)
    return self.clock
end
function T:Init()
    local db=A.charDB
    if type(A.db.trailDevice)~="string" then A.db.trailDevice=A.session end
    if type(db.trail)~="table" or db.trail.dataset~=D.dataset then
        db.trailArchive=type(db.trailArchive)=="table" and db.trailArchive or {}
        if type(db.trail)=="table" and type(db.trail.dataset)=="string" then db.trailArchive[db.trail.dataset]=db.trail end
        db.trail=db.trailArchive[D.dataset] or {dataset=D.dataset,guides={}}
        db.trailArchive[D.dataset]=nil
    end
    self.state=db.trail;self.state.guides=self.state.guides or {};self.dirty=false
    self.clock=self.state.selected and self.state.selected.at or 0
    for _, g in pairs(self.state.guides) do self.clock=math.max(self.clock,g.at or 0) end
end
function T:Write(g,step,skipped,sticky,marks)
    local previous = self.state.guides[g.id]
    self.state.guides[g.id]={step=step,at=self:Stamp(),by=A.db.trailDevice,skipped=skipped or P.Array(),sticky=sticky or P.Array(),marks=marks or (previous and previous.marks)}
    self.dirty=true;self.lastChange=call(GetTime) or 0
end
function T:ApplyMarks(g, changes)
    local s = self.state.guides[g.id]
    local marks = s.marks or {}
    for _, change in ipairs(changes) do
        local step = tostring(change.step)
        local entries = P.Array()
        for _, entry in ipairs(marks[step] or {}) do
            if entry ~= change.entry then entries[#entries + 1] = entry end
        end
        if change.checked then entries[#entries + 1] = change.entry end
        marks[step] = #entries > 0 and entries or nil
    end
    self:Write(g, s.step, s.skipped, s.sticky, marks)
end

function T:ToggleObjective(control)
    local g, s = self:Current()
    if not g or not s or not control or (control.automatic and not control.marked) then return end
    self:ApplyMarks(g, {{step=control.step, entry=control.entry, checked=not control.marked}})
    self.reviewing = false
    self:Tick(true)
end

function T:MerchantEvent(event)
    if event == "MERCHANT_CLOSED" then
        local visit = self.merchantVisit
        self.merchantVisit = nil
        if visit and self:Current() == visit.guide and #visit.changes > 0 then self:ApplyMarks(visit.guide, visit.changes) end
        return
    end
    local g, s = self:Current()
    if not g or not s or self.reviewing then return end
    local guid = call(UnitGUID, "npc")
    local id = guid and tonumber(guid:match("^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
    local changes, p, q = {}, self.Profile(), quests()
    local function track(step)
        local result = self:Evaluate(g, step, p, q)
        if not result or result.skip or result.review then return end
        for _, control in pairs(result.controls) do
            if control.kind == "vendor" and not control.marked and (not control.merchant or control.merchant == id) then
                changes[#changes + 1] = {step=step, entry=control.entry, checked=true}
            end
        end
    end
    track(s.step)
    for _, step in ipairs(s.sticky or {}) do if step ~= s.step then track(step) end end
    self.merchantVisit = {guide=g, changes=changes}
end
function T:Current()
    local g=self.state and self.state.selected and self.byID[self.state.selected.id]
    return g,g and self.state.guides[g.id]
end
function T:Select(g)
    if not self.state or self:Eligible(g,self.Profile())==false then return false end
    self.state.selected={id=g.id,at=self:Stamp(),by=A.db.trailDevice}
    if not self.state.guides[g.id] then self:Write(g,1) end
    self.dirty=true;self.lastChange=call(GetTime) or 0;self:ClearPin();self.reviewing=false
    self.arrivedStep, self.skipNotice = nil, nil
    self:Refresh();return true
end
function T:Find(group,name)
    local p=self.Profile();for _, g in ipairs(D.chapters) do if g.group==group and g.name==name and self:Eligible(g,p)~=false then return g end end
end
function T:Suggested(p,mode)
    local best,score
    for _,g in ipairs(D.chapters) do if g.mode==mode and g.min>0 and self:Eligible(g,p)==true then
        local rank=(p.level and (g.min<=p.level and p.level<=g.max) and 100 or 0) - math.abs((p.level or 1)-g.min)*3
        if g.race~="" and g.race~="None" then if self.Matches(g.race,p)==true then rank=rank+35 else rank=rank-70 end end
        if not score or rank>score then best,score=g,rank end
    end end
    return best
end
function T:NextChapter(g)
    local p=self.Profile()
    for _, n in ipairs(g.next) do if self.Matches(n[2],p)==true then
        local group,name=n[1]:match("^(.-)\\(.*)$");local nextGuide=self:Find(group or g.group,name or n[1]);if nextGuide and nextGuide.id~=g.id then return nextGuide end
    end end
end
function T:Move(delta,skip)
    local g,s=self:Current();if not g or not s then return end
    local n=math.max(1,math.min(g.steps+1,s.step+delta))
    local skipped,sticky=P.Array(),P.Array()
    for _,i in ipairs(s.skipped or {}) do if i~=s.step then skipped[#skipped+1]=i end end
    for _,i in ipairs(s.sticky or {}) do sticky[#sticky+1]=i end
    if skip and s.step<=g.steps then skipped[#skipped+1]=s.step end
    self.reviewing=delta<0
    self.arrivedStep = delta > 0 and (g.id .. ":" .. n) or nil
    self.skipNotice = nil
    self:Write(g,n,skipped,sticky)
    if s.step<=g.steps and n>g.steps then self:ChapterFinished() end
    self:Refresh()
end
-- Plays when the player moves past a chapter's last step. Browsing, sync and logging in already finished stay silent.
T.finishSound = "Interface\\AddOns\\NibWhisper_Guide\\Sounds\\jobs_done.mp3"
function T:ChapterFinished()
    if A.db.trailFinishSound == false then return end
    call(PlaySoundFile, self.finishSound, "Master")
end
function T:Browse(index)
    local g, s = self:Current()
    if not g or not s or index < 1 or index > g.steps or index == s.step then return end
    self.reviewing = true
    self.arrivedStep, self.skipNotice = nil, nil
    self:Write(g,index,s.skipped,s.sticky)
    self:Refresh()
end
function T:Advance(p,q)
    local g,s=self:Current();if not g or not s or self:Eligible(g,p)==false then return end
    local chapter=self:Chapter(g);local i=s.step;local sticky=P.Array();local skippedSet={};local mutated=false
    local reasons = {}
    for _,idx in ipairs(s.skipped or {}) do skippedSet[idx]=true end
    local function keep(idx,r)
        if not r or r.skip or r.complete or skippedSet[idx] then return end
        local untilIndex=r.sticky=="next" and idx+1 or chapter.labels[r.sticky or ""]
        if not untilIndex or untilIndex>=i then sticky[#sticky+1]=idx end
    end
    for _,idx in ipairs(s.sticky or {}) do keep(idx,self:Evaluate(g,idx,p,q)) end
    for _=1,40 do
        local r=self:Evaluate(g,i,p,q);if not r then break end
        local blocked=r.requires and chapter.labels[r.requires]
        if blocked and (blocked>=i or skippedSet[blocked]) then break end
        if r.skip and not r.review then
            local why = r.skipReason or "route condition does not apply"
            local _, detail = next(r.blocked)
            reasons[#reasons+1] = "Step " .. i .. " skipped: " .. (detail and (detail .. " first") or why) .. "."
            i=(r.jump and chapter.labels[r.jump] and chapter.labels[r.jump]>i) and chapter.labels[r.jump] or i+1
        elseif r.sticky and not r.review then keep(i,r);i=i+1
        elseif not r.review and r.checks == 0 and #r.lines == 0 and not r.point then i=i+1
        elseif r.complete and not p.dead and A.db.trailAuto~=false then
            local key = g.id .. ":" .. i
            if i ~= s.step or self.arrivedStep == key then break end
            i=i+1
        else
            if self.arrivedStep == g.id .. ":" .. i then self.arrivedStep = nil end
            break
        end
    end
    if i~=s.step then
        -- Leave an already-complete destination visible. Advance automatically once this step has been seen incomplete.
        local destination = self:Evaluate(g,i,p,q)
        self.arrivedStep = destination and destination.complete and (g.id .. ":" .. i) or nil
        self.skipNotice = #reasons>0 and {key=g.id .. ":" .. i, first=reasons[1], count=#reasons} or nil
    end
    if i~=s.step or #sticky~=#(s.sticky or {}) then self:Write(g,i,s.skipped,sticky);mutated=true end
    if s.step<=g.steps and i>g.steps then self:ChapterFinished() end
    return mutated
end
function T:Snapshot()
    local g,s=self:Current();if not g or not s then return nil end
    local p,q=self.Profile(),quests();local r=self:Evaluate(g,s.step,p,q);local out={guide={id=g.id,name=g.name,group=g.group},currentStep=s.step,totalSteps=g.steps,steps=P.Array(),dataset=D.dataset}
    for i=s.step,math.min(g.steps,s.step+2) do
        local v=i==s.step and r or self:Evaluate(g,i,p,q)
        if v then local elements=P.Array();for j=1,math.min(8,#v.lines) do elements[#elements+1]={text=P.TruncateUTF8(v.lines[j],450)} end
            out.steps[#out.steps+1]={index=i,questIds=P.Array(v.questIds),elements=elements,point=v.point,review=v.review==true} end
    end
    return out
end
T.QuestReader=quests

function T:ClearPin()
    if call(InCombatLockdown) then self.clearAfterCombat = true; return end
    self.clearAfterCombat = nil
    if self.pin and TomTom and (type(self.pin)~="table" or self.pin.from=="NibTrail") then call(TomTom.RemoveWaypoint,TomTom,self.pin) end
    self.pin=nil;self.lastPin=nil
    if self.nativePin and C_Map and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint then
        local current=call(C_Map.GetUserWaypoint);local expected=self.nativePin
        if current and current.uiMapID==expected.mapID and current.position and current.position.GetXY then
            local x,y=call(current.position.GetXY,current.position)
            if x and y and math.abs(x-expected.x/100)<0.00001 and math.abs(y-expected.y/100)<0.00001 then call(C_Map.ClearUserWaypoint) end
        end
    end
    self.nativePin=nil
end
function T:Pin(point,force)
    if call(InCombatLockdown) then return end
    if not point then if self.lastPin then self:ClearPin() end;return end
    local key=string.format("%d:%.4f:%.4f",point.mapID,point.x,point.y)
    if self.lastPin==key and not force then return end
    self:ClearPin()
    if TomTom and TomTom.AddWaypoint then
        self.pin=call(TomTom.AddWaypoint,TomTom,point.mapID,point.x/100,point.y/100,{title="Nib Trail: "..point.title,persistent=false,minimap=true,world=true,cleardistance=0,arrivaldistance=point.radius or 15,crazy=true,from="NibTrail",silent=true})
        if self.pin then call(TomTom.SetCrazyArrow,TomTom,self.pin,point.radius or 15,"Nib Trail");self.lastPin=key;return end
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local pin=call(UiMapPoint.CreateFromCoordinates,point.mapID,point.x/100,point.y/100)
        if pin and pcall(C_Map.SetUserWaypoint,pin) then self.nativePin=point end
    end
    self.lastPin=key
end

local function label(frame,font,x,y,width)
    local l=frame:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT",x,y);if width then l:SetWidth(width) end;l:SetJustifyH("LEFT");l:SetJustifyV("TOP");return l
end
local function button(frame,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");b:SetSize(width,24);b:SetPoint("TOPLEFT",x,y);b:SetText(text);b:SetScript("OnClick",fn)
    A.UI.ClipButton(b);return b
end
local function window(name,width,height,x,escapeCloses)
    local f=CreateFrame("Frame",name,UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
    A.UI:Scaled(f)
    f:SetSize(width,height);f:SetPoint("CENTER",UIParent,"CENTER",x,0);f:SetFrameStrata("HIGH");f:SetClampedToScreen(true)
    if f.SetBackdrop then f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=15,insets={left=4,right=4,top=4,bottom=4}});f:SetBackdropColor(0.025,0.065,0.065,0.97);f:SetBackdropBorderColor(0.49,0.71,0.61,1) end
    f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton");f:SetScript("OnDragStart",function(self) self:StartMoving() end);f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    local close=CreateFrame("Button",nil,f,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",-4,-4);close:SetScript("OnClick",function()f:Hide()end);f.close=close
    if UISpecialFrames and escapeCloses ~= false then table.insert(UISpecialFrames,name) end
    f:Hide();return f
end
local function trackerPanel(parent, r, g, b)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        local pixel = "Interface\\Buttons\\WHITE8X8"
        f:SetBackdrop({bgFile = pixel, edgeFile = pixel, edgeSize = 1})
        f:SetBackdropColor(r, g, b, 0.96)
        f:SetBackdropBorderColor(0.28, 0.32, 0.51, 0.94)
    end
    return f
end

local function trackerButton(parent, title, width, callback, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 18)
    local l = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetAllPoints()
    l:SetTextColor(0.82, 0.85, 1)
    -- One line only: a caption wider than its button ends in an ellipsis instead of wrapping outside it.
    if l.SetWordWrap then l:SetWordWrap(false) end
    b.caption = l
    l:SetText(title)
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(); highlight:SetColorTexture(0.36, 0.42, 0.67, 0.35)
    b:SetScript("OnClick", callback)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

function T:Build()
    if self.frame then return end
    local f = window("NibTrailWindow", 294, 284, -205, false)
    self.frame = f
    f:ClearAllPoints(); f:SetPoint("LEFT", UIParent, "LEFT", 36, 10)
    if f.SetBackdropColor then f:SetBackdropColor(0.025,0.035,0.065,1); f:SetBackdropBorderColor(0.22,0.29,0.40,1) end
    A.UI:Paint(f, "BACKGROUND", 0.025, 0.035, 0.065)
    A.UI:FadeOnShow(f)
    f:SetScript("OnMouseDown", function() A.UI:RaiseMain(f) end)
    f:SetScript("OnDragStart", function() A.UI:RaiseMain(f); f:StartMoving() end)
    -- The guide reopens where it was last left, including after a restart.
    f.positionKey = "trailPosition"
    local function remember() A.UI:SavePosition(f, f.positionKey) end
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); remember() end)
    f.afterResize = remember
    A.UI:RestorePosition(f, f.positionKey)
    f.close:SetScript("OnClick", function() T.keepVisible = false; f:Hide() end)

    local active = trackerPanel(f, 0.043, 0.043, 0.087)
    active:SetPoint("TOPLEFT", 8, -8); active:SetPoint("BOTTOMRIGHT", -8, 141)
    self.stepTag = label(active, "GameFontHighlightSmall", 10, -7)
    self.stepTag:SetTextColor(0.83, 0.86, 1)
    f.close:SetFrameLevel(active:GetFrameLevel() + 2)
    f.close:ClearAllPoints(); f.close:SetPoint("TOPRIGHT", active, "TOPRIGHT", 0, 0)
    local scroll = CreateFrame("ScrollFrame", nil, active, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 9, -27); scroll:SetPoint("BOTTOMRIGHT", -24, 9)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(265, 1); scroll:SetScrollChild(content); self.content = content
    self.rows = {}

    local tracker = trackerPanel(f, 0.053, 0.056, 0.106)
    tracker:SetPoint("BOTTOMLEFT", 8, 8); tracker:SetPoint("BOTTOMRIGHT", -8, 8); tracker:SetHeight(125)
    local header = trackerPanel(tracker, 0.083, 0.16, 0.23)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(32)
    local routes = trackerButton(header, "", 33, function() T:ShowLibrary() end, "Choose a route")
    routes:SetPoint("TOPLEFT"); routes:SetHeight(30)
    local icon = routes:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24); icon:SetPoint("CENTER"); icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    -- Thin bar along the banner: how far through the chapter this character is.
    self.progress = header:CreateTexture(nil, "OVERLAY")
    self.progress:SetColorTexture(0.33, 0.78, 0.62, 0.9)
    self.progress:SetPoint("BOTTOMLEFT", 1, 1); self.progress:SetHeight(2); self.progress:SetWidth(1)
    self.progress:Hide()
    local titleButton = trackerButton(header, "", 1, function() T:ShowLibrary() end, "Choose a route")
    titleButton:SetPoint("TOPLEFT", 34, -1); titleButton:SetPoint("BOTTOMRIGHT", -4, 3)
    self.title = titleButton.caption
    self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", 0, -3); self.title:SetPoint("TOPRIGHT", 0, -3)
    self.title:SetTextColor(0.97, 0.98, 1)
    if self.title.SetMaxLines then self.title:SetMaxLines(1) end
    self.meta = label(titleButton, nil, 0, -16)
    self.meta:ClearAllPoints(); self.meta:SetPoint("TOPLEFT", 0, -16); self.meta:SetPoint("TOPRIGHT", 0, -16)
    self.meta:SetJustifyH("CENTER"); self.meta:SetTextColor(0.70, 0.78, 0.90)
    if self.meta.SetWordWrap then self.meta:SetWordWrap(false) end

    self.preview = {}
    for i = 1, 3 do
        local row = trackerButton(tracker, "", 1, function(b)
            if not b.index then return end
            local g, s = T:Current()
            if g and s and b.index ~= s.step then T:Browse(b.index) end
        end)
        row:SetPoint("TOPLEFT", 5, -34 - (i - 1) * 15)
        row:SetPoint("TOPRIGHT", -28, -34 - (i - 1) * 15)
        row:SetHeight(15)
        row.caption:SetJustifyH("LEFT")
        if row.caption.SetMaxLines then row.caption:SetMaxLines(1) end
        row.bg = A.UI:Paint(row, "BACKGROUND", 0.10, 0.12, 0.22)
        row.bg:SetShown(i == 2)
        self.preview[i] = row
    end
    local up = trackerButton(tracker, "^", 23, function()
        local _, state = T:Current()
        if state and T.preview[1].index then T:Browse(state.step - 1) end
    end, "Look at the previous step. Automatic advancing pauses until you click Done.")
    up:SetPoint("TOPRIGHT", -3, -33)
    local down = trackerButton(tracker, "v", 23, function()
        local _, state = T:Current()
        if state and T.preview[3].index then T:Browse(state.step + 1) end
    end, "Look at the next step. Automatic advancing pauses until you click Done.")
    down:SetPoint("TOPRIGHT", -3, -60)

    local pin = trackerButton(tracker, "", 1, function(_, mouseButton)
        if mouseButton ~= "RightButton" and #T.routePoints > 1 then
            T.clickedPoint = nil
            T.pinIndex = ((T.pinIndex or 1) % #T.routePoints) + 1
            T:Refresh()
        end
        if T.currentPoint then T:Pin(T.currentPoint, true) end
    end, "Click to set this waypoint again. When a step has several pins, a left-click moves to the next one.")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetPoint("TOPLEFT", 5, -80); pin:SetPoint("TOPRIGHT", -5, -80)
    pin.caption:SetTextColor(0.67, 0.83, 0.94)
    self.nav = pin.caption
    if self.nav.SetMaxLines then self.nav:SetMaxLines(1) end

    local footer = trackerPanel(tracker, 0.085, 0.145, 0.22)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT"); footer:SetHeight(24)
    self.footer, self.footerButtons = footer, {}
    self.measure = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.measure:Hide()
    local function control(title, callback, tip)
        local b = trackerButton(footer, title, 40, callback, tip)
        self.footerButtons[#self.footerButtons + 1] = b
        return b
    end
    control("Options", function() A.UI:ShowOptions() end, "Auto advance, map pins, progress sync, and window size")
    control("Steps", function() T:ShowSteps() end, "Browse every step in this chapter")
    control("Skip", function() T:Move(1,true) end, "Skip this step and move on")
    self.nextButton = control("Done", function()
        local g, s = T:Current()
        if g and s and s.step > g.steps then
            local nextGuide = T:NextChapter(g)
            if nextGuide then T:Select(nextGuide) else T:ShowLibrary() end
        else T:Move(1) end
    end, "Mark this step finished and continue")
    -- Only offered when the AI Assistant addon is enabled.
    if A.Assistant then control("Ask Nib", function() A:Ask("What is my next Nib Trail objective?") end, "Ask Nib about this step in chat") end
    local targets = trackerButton(header, "Targets", 45, function() T:ShowTargets() end, "Pick this step's named targets outside combat")
    targets:SetPoint("TOPRIGHT", -2, -6)
    self.measure:SetText("Targets")
    local targetsWidth = math.max(45, math.ceil(self.measure:GetStringWidth()) + 8)
    targets:SetWidth(targetsWidth)
    titleButton:SetPoint("BOTTOMRIGHT", -(targetsWidth + 4), 3)
    A.UI:ResizeGrip(f, "trailCompactSize", 252, 225, 760, 820)
    self:LayoutFooter()
    f:SetScript("OnSizeChanged", function() T:LayoutFooter(); if f:IsShown() then T:Refresh() end end)
    f:SetScript("OnHide", function() T:ClearPin() end)
end

-- Footer buttons share the bar in proportion to their captions, so they fit at any window size and font.
function T:LayoutFooter()
    local buttons = self.footerButtons
    if not buttons then return end
    local available = math.max(120, self.frame:GetWidth() - 16 - 24) -- the resize grip owns the right corner
    local natural, total = {}, 0
    for i, b in ipairs(buttons) do
        self.measure:SetText(b.caption:GetText() or "")
        natural[i] = (self.measure:GetStringWidth() or 30) + 8
        total = total + natural[i]
    end
    local x = 2
    for i, b in ipairs(buttons) do
        local width = math.floor(available * natural[i] / total)
        b:ClearAllPoints(); b:SetPoint("LEFT", self.footer, "LEFT", x, 0); b:SetWidth(width)
        x = x + width
    end
end

function T:RefreshPreview(g, s, p, q, current)
    for offset = -1, 1 do
        local row = self.preview[offset + 2]
        local index = s and s.step + offset
        local evaluated = offset == 0 and current or nil
        if g and index and offset ~= 0 and index >= 1 and index <= g.steps then evaluated = self:Evaluate(g,index,p,q) end
        row.index = evaluated and index or nil
        if evaluated then
            local line = evaluated.display[1] or evaluated.lines[1] or evaluated.skipReason or "Route marker"
            line = line:gsub("^%[Done%] ", ""):gsub("^%[Marked%] ", ""):gsub("^%[ %] ", "")
            if offset ~= 0 then line = text(line) end
            row.caption:SetText(string.format("%02d  %s", index, line))
            local v = offset == 0 and 0.94 or 0.56
            row.caption:SetTextColor(v,v,offset == 0 and 1 or 0.66)
        else
            row.caption:SetText(offset == 0 and (g and "Chapter complete" or "Click the banner to choose a route") or "")
        end
    end
end

function T:RenderRows(lines, controls, points, links)
    local width = math.max(170, self.frame:GetWidth() - 51)
    local signature = width .. "\n" .. table.concat(lines, "\n")
    for i, row in ipairs(self.rows) do
        row.control = controls and controls[i]
        row.point = points and points[i]
        row.link = links and links[i]
    end
    if self.rowSignature == signature then return end
    self.rowSignature = signature
    local offset = 0
    self.content:SetWidth(width)
    for i, line in ipairs(lines) do
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, self.content)
            row.icon = label(row, "GameFontNormalSmall", 3, -2)
            local toggle = CreateFrame("Button", nil, row)
            toggle:SetPoint("TOPLEFT", 0, 1); toggle:SetSize(19, 19)
            toggle:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
            toggle:SetScript("OnClick", function() T:ToggleObjective(row.control) end)
            toggle:SetScript("OnEnter", function(button)
                if not row.control then return end
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:AddLine(row.control.marked and "Undo objective check" or row.control.automatic and "Completed in game" or "Check off this objective")
                GameTooltip:Show()
            end)
            toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.toggle = toggle
            row.check = toggle:CreateTexture(nil, "ARTWORK"); row.check:SetAllPoints()
            -- The text belongs to this button so the client can report clicks on its keyword links.
            local destination = CreateFrame("Button", nil, row)
            destination:SetPoint("TOPLEFT", 22, 0); destination:SetPoint("BOTTOMRIGHT", 0, 0)
            destination:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row.text = label(destination, "GameFontHighlightSmall", 2, -1)
            A.UI:Paint(destination, "HIGHLIGHT", 0.36, 0.46, 0.63, 0.24)
            if destination.SetHyperlinksEnabled then
                destination:SetHyperlinksEnabled(true)
                destination:SetScript("OnHyperlinkClick", function(_, link)
                    T.keywordClickAt = call(GetTime) or 0
                    T:ShowKeyword(link)
                end)
            end
            destination:SetScript("OnClick", function(_, mouseButton)
                -- A keyword click may also arrive here as an ordinary click. It has been handled already.
                if T.keywordClickAt and math.abs((call(GetTime) or 0) - T.keywordClickAt) < 0.05 then return end
                if mouseButton == "RightButton" then
                    if row.control and row.control.quest then T:ShowQuestInfo(row.control.quest) end
                elseif row.link then A.UI:ShowCopy(row.link, "Guide link")
                elseif row.point then T.clickedPoint = row.point; T.pinIndex = nil; T:Refresh() end
            end)
            destination:SetScript("OnEnter", function(button)
                local quest = row.control and row.control.quest
                if not row.point and not row.link and not quest then return end
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                if row.link then
                    GameTooltip:AddLine("Click to copy this link")
                    GameTooltip:AddLine("WoW cannot open a browser. Copy the address and paste it into yours.", 0.85, 0.9, 0.9, true)
                elseif row.point then
                    GameTooltip:AddLine("Click to set the waypoint")
                    GameTooltip:AddLine(string.format("%.2f, %.2f", row.point.x, row.point.y), 0.85, 0.9, 0.9)
                end
                if quest then GameTooltip:AddLine("Right-click for quest details", 0.85, 0.9, 0.9) end
                GameTooltip:Show()
            end)
            destination:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.destination = destination
            self.rows[i] = row
        end
        row.control = controls and controls[i]
        row.point = points and points[i]
        row.link = links and links[i]
        local marked = line:sub(1, 9) == "[Marked] "
        local done = line:sub(1, 7) == "[Done] " or marked
        local pending = line:sub(1, 4) == "[ ] "
        local side = line:sub(1, 1) == "\n"
        local copy = marked and line:sub(10) or done and line:sub(8) or pending and line:sub(5) or side and line:sub(2) or line
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -offset); row:SetWidth(width)
        row.icon:SetText((done or pending) and "" or side and "+" or row.link and ">" or "-")
        row.icon:SetTextColor(0.86, 0.73, 0.48)
        row.toggle:SetShown(row.control ~= nil)
        if done then row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        elseif pending then row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Up") end
        row.text:SetWidth(width - 28); row.text:SetText(copy)
        if done then row.text:SetTextColor(0.56, 0.60, 0.69)
        elseif row.link then row.text:SetTextColor(0.55, 0.82, 1)
        elseif side then row.text:SetTextColor(0.96, 0.78, 0.46)
        else row.text:SetTextColor(0.95, 0.95, 1) end
        local height = math.max(18, row.text:GetStringHeight() + 4)
        row:SetHeight(height); row:Show()
        offset = offset + height + 2
    end
    for i = #lines + 1, #self.rows do self.rows[i]:Hide() end
    self.content:SetHeight(math.max(1, offset))
    if self.scroll.GetVerticalScrollRange and self.scroll.GetVerticalScroll then
        self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(), self.scroll:GetVerticalScrollRange()))
    end
end

function T:Refresh(p, q)
    if not self.frame or not self.frame:IsShown() then return end
    p, q = p or self.Profile(), q or quests()
    local g, s = self:Current()
    if not g or not s then
        self.title:SetText("Choose a route"); self.meta:SetText("Solo, dungeon, and Mage routes")
        self.stepTag:SetText("Nib Trail"); self.nav:SetText(""); self.currentPoint = nil; self.routePoints = {}; self:Pin(nil)
        self.progress:Hide()
        self:RefreshPreview()
        self:RenderRows({"Click the map or route banner to choose a chapter."})
        return
    end
    self.title:SetText(text(g.title))
    local r = self:Evaluate(g, s.step, p, q)
    local lines, controls, points, links, point = {}, {}, {}, {}, r and r.point
    local stepKey = g.id .. ":" .. s.step
    local notice = self.skipNotice
    if notice and notice.key == stepKey then
        lines[#lines+1] = "\n" .. notice.first .. (notice.count > 1 and (" +" .. (notice.count - 1) .. " route checks") or "")
    end
    local syncNotice = self.syncNoticeUntil and (call(GetTime) or 0) < self.syncNoticeUntil and self.syncStatus
    self.meta:SetText(syncNotice or (g.mode .. (self.reviewing and " · Review paused" or A.db.trailAuto == false and " · Auto off" or "")))
    local fraction = math.max(0, math.min(1, (s.step - 1) / math.max(1, g.steps)))
    self.stepTag:SetText(r and string.format("Step %d / %d  ·  %d%%", s.step, g.steps, math.floor(fraction * 100)) or "Chapter complete")
    self.progress:SetWidth(math.max(1, (self.frame:GetWidth() - 18) * fraction)); self.progress:Show()
    self:RefreshPreview(g, s, p, q, r)
    if r then
        if r.optional then lines[#lines + 1] = "Optional step" end
        if r.requires then
            local requiredStep = self:Chapter(g).labels[r.requires]
            if requiredStep and requiredStep >= s.step then lines[#lines + 1] = "Complete the route checkpoint at step " .. requiredStep .. " first." end
        end
        if r.skip and not next(r.blocked) then lines[#lines + 1] = "This step is inactive: " .. (r.skipReason or "route condition does not apply") .. "." end
        for i, line in ipairs(r.lines) do
            lines[#lines + 1] = r.display[i] or line
            controls[#lines] = r.controls[i]
            points[#lines] = r.linePoints[i]
            links[#lines] = r.links[i]
        end
        if #lines == 0 then lines[1] = "Route marker. There is no player action here. Click Done to continue." end
    else
        local nextGuide = self:NextChapter(g)
        lines[1] = nextGuide and ("Chapter complete. Next: " .. text(nextGuide.title)) or "Chapter complete. Choose another chapter from Routes."
    end
    for _, i in ipairs(s.sticky or {}) do
        if i < s.step then
            local side = self:Evaluate(g, i, p, q)
            if side and not side.complete and not side.skip then
                lines[#lines + 1] = "\nWhile you travel · step " .. i
                for j = 1, #side.lines do
                    lines[#lines + 1] = side.display[j] or side.lines[j]
                    controls[#lines] = side.controls[j]
                    points[#lines] = side.linePoints[j]
                    links[#lines] = side.links[j]
                end
                if not point and not side.review then point = side.point end
            end
        end
    end
    local nextLabel = r and "Done" or "Next route"
    if self.nextButton.caption:GetText() ~= nextLabel then self.nextButton.caption:SetText(nextLabel); self:LayoutFooter() end
    local key = stepKey
    if key ~= self.renderKey then
        self.scroll:SetVerticalScroll(0); self.suppressPin = false; self.pinIndex = nil; self.renderKey = key
    end
    local objectiveKey = key .. ":" .. tostring(r and r.activeEntry)
    if objectiveKey ~= self.objectiveKey then self.pinIndex = nil; self.clickedPoint = nil; self.objectiveKey = objectiveKey end
    if self.clickedPoint then
        local selected = self.clickedPoint
        local available = false
        for _, candidate in pairs(points) do
            if candidate.mapID == selected.mapID and candidate.x == selected.x and candidate.y == selected.y then available = true; break end
        end
        if not available then self.clickedPoint = nil end
    end
    self:RenderRows(lines, controls, points, links)
    self.routePoints = r and r.points or {}
    if self.pinIndex and self.routePoints[self.pinIndex] then point = self.routePoints[self.pinIndex] end
    if self.clickedPoint then point = self.clickedPoint end
    self.currentPoint = point
    if point then
        local info = call(C_Map and C_Map.GetMapInfo, point.mapID)
        local dist, dx, dy = self.Distance(point, p)
        local direction = dist and string.format("%.0f yd", dist) or ""
        local facing = call(GetPlayerFacing)
        if dx and dy and facing and math.atan2 then
            local degrees = (math.deg(math.atan2(dx, dy) - facing) + 540) % 360 - 180
            direction = direction .. (math.abs(degrees) < 12 and " · ahead" or string.format(" · %d° %s", math.floor(math.abs(degrees)), degrees > 0 and "left" or "right"))
        end
        local waypoint = string.format("%.2f, %.2f", point.x, point.y)
        if #self.routePoints > 1 then waypoint = waypoint .. string.format("  ·  Pin %d/%d", self.pinIndex or 1, #self.routePoints) end
        self.nav:SetText(waypoint .. (direction ~= "" and ("  ·  " .. direction) or "  ·  " .. text(info and info.name or ("Map " .. point.mapID))))
        if self.clickedPoint or (A.db.trailPins ~= false and not self.suppressPin and not (r and r.review)) then self:Pin(point)
        elseif r and r.review then self:Pin(nil) end
    else
        self.nav:SetText("No waypoint for this step")
        self:Pin(nil)
    end
end
function T:Open()
    self:Build(); self.keepVisible = true; self.frame:Show(); A.UI:RaiseMain(self.frame)
    self:Tick(true)
end
function T:Toggle()
    if self.frame and self.frame:IsShown() and A.UI.frontWindow == self.frame then self.keepVisible = false; self.frame:Hide()
    else self:Open() end
end

-- Quests the current step, and any side steps still open, ask the player to accept or turn in.
function T:QuestTargets()
    local targets = {accept={}, turnin={}, acceptTitles={}, turninTitles={}}
    local g, s = self:Current()
    if not g or not s then return targets end
    local p, q = self.Profile(), quests()
    local function collect(step)
        local result = self:Evaluate(g, step, p, q)
        if not result or result.skip then return end
        for _, control in pairs(result.controls) do
            local list = control.quest and not control.automatic and not control.marked and targets[control.kind]
            if list then
                list[control.quest] = true
                local title = questName(control.quest)
                if title then targets[control.kind .. "Titles"][title] = true end
            end
        end
    end
    collect(s.step)
    for _, step in ipairs(s.sticky or {}) do if step ~= s.step then collect(step) end end
    return targets
end

-- Accepts and turns in only the quests the visible guide step names. Reward choices are left to the player.
function T:QuestAutomation(event, _, title)
    if A.db.trailQuestAuto == false or not self.frame or not self.frame:IsShown() then return end
    if call(IsControlKeyDown) then return end
    local targets = self:QuestTargets()
    if not next(targets.accept) and not next(targets.turnin) then return end
    if event == "GOSSIP_SHOW" then
        local gossip = C_GossipInfo or {}
        for _, quest in ipairs(call(gossip.GetActiveQuests) or {}) do
            if targets.turnin[quest.questID] and quest.isComplete then return call(gossip.SelectActiveQuest, quest.questID) end
        end
        for _, quest in ipairs(call(gossip.GetAvailableQuests) or {}) do
            if targets.accept[quest.questID] then return call(gossip.SelectAvailableQuest, quest.questID) end
        end
    elseif event == "QUEST_GREETING" then
        for i = 1, call(GetNumActiveQuests) or 0 do
            local name, complete = call(GetActiveTitle, i)
            if name and complete and targets.turninTitles[name] then return call(SelectActiveQuest, i) end
        end
        for i = 1, call(GetNumAvailableQuests) or 0 do
            local name = call(GetAvailableTitle, i)
            if name and targets.acceptTitles[name] then return call(SelectAvailableQuest, i) end
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if title and targets.acceptTitles[title] then call(ConfirmAcceptQuest) end
    else
        local id = call(GetQuestID)
        if not id then return end
        if event == "QUEST_DETAIL" then
            if targets.accept[id] then call(AcceptQuest) end
        elseif event == "QUEST_PROGRESS" then
            if targets.turnin[id] and call(IsQuestCompletable) then call(CompleteQuest) end
        elseif event == "QUEST_COMPLETE" and targets.turnin[id] then
            local choices = call(GetNumQuestChoices) or 0
            if choices <= 1 then call(GetQuestReward, 1)
            else A:Notice("Choose your reward. Nib leaves that one to you.") end
        end
    end
end

local reverseNames
local function namedIDs(name)
    if not reverseNames then
        reverseNames = {quests={}, items={}}
        for id, value in pairs(questData.names) do reverseNames.quests[value:lower()] = id end
        for id, value in pairs(questData.items or {}) do reverseNames.items[value:lower()] = id end
    end
    return reverseNames.quests[name:lower()], reverseNames.items[name:lower()]
end
local function questLines(id, q)
    local lines = {}
    if q("turnin", id) == true then lines[1] = "Status: turned in"
    elseif q("isonquest", id) == true then
        lines[1] = "Status: in your quest log"
        for _, objective in ipairs(call(C_QuestLog and C_QuestLog.GetQuestObjectives, id) or {}) do
            if type(objective.text) == "string" and objective.text ~= "" then
                lines[#lines+1] = (objective.finished and "Done: " or "To do: ") .. text(objective.text)
            end
        end
    else
        lines[1] = "Status: not started"
        local missing = missingPrerequisite(id, q)
        if missing then lines[#lines+1] = "Needs: " .. missing end
    end
    return lines
end
local function encodeURL(value)
    return (value:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- What Nib can say about a quest or a highlighted name using only local data.
function T:Describe(kind, name, questID)
    local q = quests()
    local info = {name=name, kind=linkKinds[kind] or "Quest", lines={}}
    local itemID
    if questID then info.name = questName(questID) or ("Quest " .. questID)
    else questID, itemID = namedIDs(name) end
    if kind == "FRIENDLY" or kind == "ENEMY" then questID, itemID = nil, nil end
    if itemID then
        local count = call(C_Item and C_Item.GetItemCount or GetItemCount, itemID)
        if count then info.lines[#info.lines+1] = "In your bags: " .. count end
        info.url = "https://www.wowhead.com/classic/item=" .. itemID
    elseif questID then
        info.kind = "Quest"
        info.questID = questID
        info.inLog = q("isonquest", questID) == true
        for _, line in ipairs(questLines(questID, q)) do info.lines[#info.lines+1] = line end
        info.url = "https://www.wowhead.com/classic/quest=" .. questID
    else
        info.url = "https://www.wowhead.com/classic/search?q=" .. encodeURL(info.name)
    end
    if kind == "FRIENDLY" or kind == "ENEMY" then info.lines[#info.lines+1] = "Use Targets in the guide header to select it." end
    if #info.lines == 0 then info.lines[1] = "The guide has no local notes on this. Copy the Wowhead link to look it up." end
    return info
end

-- Opens the game's own quest log on a quest. Returns false and the reason when it cannot.
function T:OpenQuestLog(id)
    if call(InCombatLockdown) then return false, "Open the quest log after combat." end
    local log = C_QuestLog or {}
    if call(log.IsOnQuest, id) == false then return false, "That quest is not in your quest log." end
    -- This client has the classic quest log: select the quest's row and show the window.
    local index = call(log.GetLogIndexForQuestID, id)
    if not index or index == 0 then index = call(GetQuestLogIndexByID, id) end
    if QuestLogFrame and type(QuestLog_SetSelection) == "function" and index and index > 0 then
        if not QuestLogFrame:IsShown() then call(ShowUIPanel, QuestLogFrame) end
        call(QuestLog_SetSelection, index)
        call(QuestLog_Update)
        return true
    end
    -- Clients with the map-based quest log.
    if type(QuestMapFrame_OpenToQuestDetails) == "function" and pcall(QuestMapFrame_OpenToQuestDetails, id) then return true end
    if type(QuestLogPopupDetailFrame_Show) == "function" and index and index > 0 and pcall(QuestLogPopupDetailFrame_Show, index) then return true end
    return false, "This client's quest log could not be opened from here. Press L to open it."
end

function T:ShowInfo(info)
    local f = self.infoWindow
    if not f then
        f = window("NibTrailInfo", 330, 240, 0)
        f:SetFrameStrata("DIALOG")
        self.infoWindow = f
        f.title = label(f, "GameFontNormalLarge", 16, -15, 280)
        f.kind = label(f, nil, 17, -38, 290); f.kind:SetTextColor(0.67, 0.83, 0.94)
        f.body = label(f, "GameFontHighlight", 17, -60, 296)
        f.log = button(f, "View in quest log", 16, -176, 298, function()
            local opened, problem = T:OpenQuestLog(f.info.questID)
            if opened then f:Hide() else A:Notice(problem, true) end
        end)
        f.ask = button(f, "Ask Nib", 16, -204, 140, function()
            f:Hide(); A:Ask("Tell me about " .. f.info.name .. " for my current Nib Trail step.")
        end)
        f.lookup = button(f, "Copy Wowhead link", 172, -204, 142, function() A.UI:ShowCopy(f.info.url, "Wowhead link") end)
    end
    f.info = info
    f.ask:SetShown(A.Assistant ~= nil)
    -- Offered for a quest you are on; the quest log has nothing to show for one you have not picked up.
    f.log:SetShown(info.questID ~= nil and info.inLog == true)
    f.title:SetText(info.name); f.kind:SetText(info.kind); f.body:SetText(table.concat(info.lines, "\n"))
    f:Show()
end
function T:ShowKeyword(link)
    local kind, name = tostring(link):match("^nib:(%u+):(.+)$")
    if kind and linkKinds[kind] then self:ShowInfo(self:Describe(kind, name)) end
end
function T:ShowQuestInfo(id) self:ShowInfo(self:Describe(nil, nil, id)) end

function T:RestoreAfterDeath()
    if self.keepVisible then self.restoreUntil = (call(GetTime) or 0) + 5 end
end

function T:ShowTargets()
    if call(InCombatLockdown) then A:Notice("Open Nib Targets after combat.", true); return end
    local names, seen = {}, {}
    local g, s = self:Current()
    if g and s then
        local profile, readQuest = self.Profile(), quests()
        local function append(step)
            local result = self:Evaluate(g, step, profile, readQuest)
            for _, name in ipairs(result and result.targets or {}) do
                if not seen[name] and #names < 10 then names[#names+1] = name; seen[name] = true end
            end
        end
        append(s.step)
        for _, step in ipairs(s.sticky or {}) do if step < s.step then append(step) end end
    end
    local f = self.targetWindow
    if not f then
        f = window("NibTrailTargets", 285, 275, 130, false)
        f:SetFrameStrata("DIALOG")
        f.close:SetScript("OnClick", function() if not call(InCombatLockdown) then f:Hide() end end)
        f:SetScript("OnDragStart", function() if not call(InCombatLockdown) then f:StartMoving() end end)
        self.targetWindow = f
        label(f,"GameFontNormalLarge",15,-14):SetText("Nib Targets")
        f.empty = label(f,nil,16,-44,249)
        f.empty:SetText("This step has no named targets.")
        f.rows = {}
        for i = 1, 10 do
            local target = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
            target:SetSize(252,20); target:SetPoint("TOPLEFT",16,-42-(i-1)*21)
            target:RegisterForClicks("AnyUp", "AnyDown")
            target:SetAttribute("type", "macro")
            target.caption = label(target,nil,5,-3,240)
            A.UI:Paint(target,"HIGHLIGHT",0.33,0.41,0.58,0.45)
            f.rows[i] = target
        end
    end
    f.empty:SetShown(#names == 0)
    for i, target in ipairs(f.rows) do
        local name = names[i]
        target:SetAttribute("macrotext", name and ("/targetexact " .. name) or nil)
        target.caption:SetText(name or "")
        target:SetShown(name ~= nil)
    end
    f:Show()
end
function T:Tick(force)
    if not self.state then return end
    local now=call(GetTime) or 0
    if self.clearAfterCombat and not call(InCombatLockdown) then self:ClearPin() end
    if self.keepVisible and self.restoreUntil and now <= self.restoreUntil and self.frame and not self.frame:IsShown() then self.frame:Show() end
    if self.SyncTick then self:SyncTick(now) end
    if not self.frame or not self.frame:IsShown() or (not force and now-(self.lastTick or -10)<0.45) then return end
    self.lastTick=now
    local p,q=self.Profile(),quests()
    p.memo={}
    if not self.reviewing and A.db.trailAuto~=false and not p.dead then self:Advance(p,q) end
    self:Refresh(p,q)
end
local libraryModes = {
    {name="Solo route", subtitle="Questing by zone"},
    {name="Dungeon route", subtitle="Leveling with dungeon runs"},
    {name="Mage AoE", subtitle="Mage area damage routes"},
    {name="Dungeon quests", subtitle="Quests for a specific dungeon"},
}

function T:ShowLibrary()
    if not self.library then
        local f = window("NibTrailLibrary", 570, 545, 175)
        self.library = f
        f.page, f.mode, f.rows = 1, 1, {}
        f:SetFrameStrata("DIALOG")
        if f.SetBackdropColor then f:SetBackdropColor(0.036, 0.043, 0.079, 0.98); f:SetBackdropBorderColor(0.34, 0.41, 0.61, 1) end
        local header = trackerPanel(f, 0.079, 0.13, 0.21)
        header:SetPoint("TOPLEFT", 10, -10); header:SetPoint("TOPRIGHT", -10, -10); header:SetHeight(55)
        f.close:SetFrameLevel(header:GetFrameLevel() + 2)
        label(header, "GameFontNormalLarge", 13, -9):SetText("Nib Trail Route Library")
        local detail = label(header, "GameFontHighlightSmall", 14, -32)
        detail:SetText("Choose a chapter for your character")
        detail:SetTextColor(0.67, 0.75, 0.87)

        f.filter = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.filter:SetSize(307, 28); f.filter:SetPoint("TOPLEFT", 23, -79)
        f.filter:SetAutoFocus(false); f.filter:SetMaxLetters(100)
        local searchHint = label(f, nil, 30, -87)
        searchHint:SetText("Search chapter or zone"); searchHint:SetTextColor(0.62, 0.67, 0.79)
        f.filter:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
        f.filter:SetScript("OnEditFocusLost", function(box) searchHint:SetShown(box:GetText() == "") end)
        f.filter:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        f.filter:SetScript("OnTextChanged", function(box)
            searchHint:SetShown(box:GetText() == "" and not (box.HasFocus and box:HasFocus()))
            f.page = 1; T:List()
        end)

        local selector = trackerPanel(f, 0.13, 0.18, 0.28)
        selector:SetPoint("TOPRIGHT", -19, -78); selector:SetSize(201, 29)
        f.modeButton = trackerButton(selector, "", 201, function() f.menu:SetShown(not f.menu:IsShown()) end)
        f.modeButton:SetAllPoints()
        local arrow = selector:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -6, 0)
        local menu = trackerPanel(f, 0.083, 0.105, 0.17)
        f.menu = menu
        menu:SetPoint("TOPRIGHT", selector, "BOTTOMRIGHT", 0, -4)
        menu:SetSize(221, #libraryModes * 36 + 8)
        menu:SetFrameLevel(f:GetFrameLevel() + 16)
        menu:EnableMouse(true)
        for i, option in ipairs(libraryModes) do
            local index = i
            local choice = trackerButton(menu, option.name, 211, function()
                f.mode, f.page = index, 1
                menu:Hide()
                T:List()
            end)
            choice:SetPoint("TOPLEFT", 5, -4 - (i - 1) * 36); choice:SetHeight(35)
            choice.caption:ClearAllPoints(); choice.caption:SetPoint("TOPLEFT", 8, -4)
            local description = label(choice, nil, 8, -18)
            description:SetText(option.subtitle); description:SetTextColor(0.62, 0.70, 0.83)
        end
        menu:Hide()

        f.result = label(f, nil, 21, -119, 520); f.result:SetTextColor(0.68, 0.76, 0.87)
        f.empty = label(f, "GameFontHighlight", 22, -167, 500)
        f.empty:SetText("No routes match this category and search.")
        for i = 1, 8 do
            local row = trackerButton(f, "", 528, function(b)
                if not b.guide then return end
                if T:Select(b.guide) then T:Open(); f:Hide() end
            end)
            row:SetPoint("TOPLEFT", 21, -140 - (i - 1) * 41); row:SetHeight(38)
            row.bg = A.UI:Paint(row, "BACKGROUND", 0.084, 0.108, 0.16)
            row.caption:ClearAllPoints(); row.caption:SetPoint("TOPLEFT", 12, -5); row.caption:SetWidth(359)
            row.caption:SetJustifyH("LEFT")
            if row.caption.SetMaxLines then row.caption:SetMaxLines(1) end
            row.detail = label(row, nil, 12, -20, 355)
            row.detail:SetTextColor(0.65, 0.73, 0.84)
            row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.badge:SetPoint("RIGHT", -12, 0); row.badge:SetTextColor(0.91, 0.78, 0.49)
            f.rows[i] = row
        end
        local prev = trackerButton(f, "<  Previous", 107, function() f.page = math.max(1, f.page - 1); T:List() end)
        local next = trackerButton(f, "Next  >", 107, function() f.page = f.page + 1; T:List() end)
        prev:SetPoint("BOTTOMLEFT", 22, 23); next:SetPoint("BOTTOMRIGHT", -22, 23)
        f.pages = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.pages:SetPoint("BOTTOM", 0, 25)
        f:SetScript("OnHide", function() f.filter:ClearFocus(); menu:Hide() end)
    end
    self.library:Show()
    self:List()
end

function T:List()
    local f, p = self.library, self.Profile()
    local mode = libraryModes[f.mode].name
    f.modeButton.caption:SetText(mode)
    local query, found = trim(f.filter:GetText()):lower(), {}
    local suggested = self:Suggested(p, mode)
    for _, g in ipairs(D.chapters) do
        if g.mode == mode and self:Eligible(g, p) ~= false and (query == "" or g.title:lower():find(query, 1, true)) then found[#found + 1] = g end
    end
    table.sort(found, function(a,b)
        if a == suggested or b == suggested then return a == suggested and b ~= suggested end
        if a.min ~= b.min then return a.min < b.min end
        return a.title < b.title
    end)
    local perPage = #f.rows
    local pages = math.max(1, math.ceil(#found / perPage))
    f.page = math.min(f.page, pages)
    f.result:SetText(string.format("%d %s", #found, #found == 1 and "route" or "routes"))
    f.pages:SetText(string.format("%d / %d", f.page, pages))
    f.empty:SetShown(#found == 0)
    for i, row in ipairs(f.rows) do
        local g = found[(f.page - 1) * perPage + i]
        row.guide = g
        row:SetShown(g ~= nil)
        if g then
            local saved = self.state.guides[g.id]
            row.caption:SetText(text(g.title))
            row.detail:SetText(g.min > 0 and string.format("Levels %d–%d   ·   %d steps",g.min,g.max,g.steps) or (g.steps .. " steps"))
            row.badge:SetText(saved and (saved.step > g.steps and "Complete" or "Resume · " .. saved.step) or g == suggested and "Suggested" or "")
            if g == suggested then row.bg:SetColorTexture(0.11, 0.19, 0.24, 1)
            else row.bg:SetColorTexture(0.084, 0.108, 0.16, 1) end
        end
    end
end

function T:ShowSteps()
    local g,s=self:Current();if not g then return end
    if not self.stepsFrame then
        local f=window("NibTrailSteps",500,456,180);self.stepsFrame=f;f.rows={}
        f.title=label(f,"GameFontNormalLarge",18,-18,450)
        for i=1,11 do f.rows[i]=button(f,"",18,-49-(i-1)*31,459,function(b)
            if b.step then T:Browse(b.step);f:Hide() end
        end) end
        button(f,"Previous",18,-402,110,function()f.from=math.max(1,f.from-11);T:ListSteps()end)
        button(f,"Next",367,-402,110,function()local chapter=T:Current();if chapter and f.from+11<=chapter.steps then f.from=f.from+11;T:ListSteps() end end)
        f.range=label(f,nil,148,-407,205)
    end
    self.stepsFrame.from=math.max(1,math.min(s.step,g.steps)-3);self.stepsFrame:Show();self:ListSteps()
end
function T:ListSteps()
    local g,s=self:Current();local f=self.stepsFrame;if not g or not f then return end
    f.from=math.min(f.from,g.steps);f.title:SetText(text(g.title));f.range:SetText(f.from.."-"..math.min(g.steps,f.from+10).." of "..g.steps)
    local p,q=self.Profile(),quests();local skip={};for _, i in ipairs(s.skipped or {}) do skip[i]=true end
    for i,b in ipairs(f.rows) do
        local n=f.from+i-1;local r=self:Evaluate(g,n,p,q);b.step=n
        if r then b:SetText(P.TruncateUTF8((n==s.step and "> " or "")..n..". "..(skip[n] and "[Skipped] " or r.skip and "[Inactive] " or n<s.step and "[Past] " or "")..(r.lines[1] or r.skipReason or "Route marker"),77));b:Show()else b:Hide()end
    end
end
