local A = _G.NibWhisper
if not A then return end
local C, P = A.Context, A.Protocol
local call = C.Call
local D = {}
A.CharacterData = D

local function now() return call(GetServerTime) or call(time) or 0 end
local function text(value) return P.SanitizeText(value or "", 128) end
local function itemName(id, link)
    local item = C_Item or {}
    local name = call(item.GetItemNameByID, id) or call(item.GetItemInfo or GetItemInfo, id)
        or (A.QuestLinks and A.QuestLinks.items and A.QuestLinks.items[id])
        or (type(link) == "string" and link:match("|h%[(.-)%]|h"))
    return type(name) == "string" and name ~= "" and text(name) or nil
end

local function character()
    local name, realm = call(UnitFullName, "player")
    name = name or call(UnitName, "player")
    realm = realm and realm ~= "" and realm or call(GetRealmName)
    if type(name) ~= "string" or name == "" then return end
    local key = call(UnitGUID, "player") or (name .. "-" .. (realm or ""))
    A.db.characters = A.db.characters or {}
    local record = A.db.characters[key] or {recipes={}}
    A.db.characters[key] = record
    record.name, record.realm = text(name), text(realm)
    return record
end

local function bagIDs(bank)
    local index = Enum and Enum.BagIndex or {}
    if not bank then
        local ids = {index.Backpack or 0}
        for i = 1, (NUM_BAG_SLOTS or 4) do ids[#ids+1] = i end
        if index.ReagentBag and index.ReagentBag > ids[#ids] then ids[#ids+1] = index.ReagentBag end
        return ids
    end
    local bankType = Enum and Enum.BankType and Enum.BankType.Character
    local purchased = bankType and C_Bank and call(C_Bank.FetchPurchasedBankTabIDs, bankType)
    if type(purchased) == "table" and #purchased > 0 then return purchased, true end
    local ids = {index.Bank or BANK_CONTAINER or -1}
    if type(purchased) ~= "table" then
        for i = 1, (NUM_BANKBAGSLOTS or 7) do
            ids[#ids+1] = index["BankBag_" .. i] or ((NUM_BAG_SLOTS or 4) + i)
        end
        if index.Reagentbank then ids[#ids+1] = index.Reagentbank end
    end
    return ids
end

local function scan(bank)
    local container = C_Container or {}
    local getSlots = container.GetContainerNumSlots or GetContainerNumSlots
    local modern = container.GetContainerItemInfo
    if not getSlots or not (modern or GetContainerItemInfo) then return end
    local items, slots, partial, seen = {}, 0, false, {}
    local ids, purchased = bagIDs(bank)
    for _, bag in ipairs(ids) do
        if not seen[bag] then
            seen[bag] = true
            local size = call(getSlots, bag)
            if P.IsFinite(size) and size > 0 then
                slots = slots + size
                for slot = 1, size do
                    local id, count, link
                    if modern then
                        local info = call(modern, bag, slot)
                        if type(info) == "table" then id, count, link = info.itemID, info.stackCount, info.hyperlink end
                    else
                        local _, n, _, _, _, _, value, _, _, itemID = call(GetContainerItemInfo, bag, slot)
                        id, count, link = itemID or call(GetContainerItemID, bag, slot), n, value
                    end
                    if P.IsPositiveInteger(id) and P.IsPositiveInteger(count) then
                        local entry = items[id] or {itemID=id, name=itemName(id,link), count=0}
                        entry.count = entry.count + count
                        items[id] = entry
                    elseif link or count then partial = true end
                end
            elseif purchased then partial = true end
        end
    end
    if slots == 0 then return end
    return {items=items, capturedAt=now(), coverage=partial and "partial" or "complete"}
end

local difficulty = {[0]="orange",[1]="yellow",[2]="green"}

local function visibleRecipes()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList and page.RecipeList.ScrollBox
    local provider = list and call(list.GetDataProvider,list)
    if not provider and list then
        local view = call(list.GetView,list)
        provider = view and call(view.GetDataProvider,view)
    end
    local enumerate = provider and call(provider.EnumerateEntireRange,provider)
    if not enumerate then return end
    local ids, seen = {}, {}
    for _, node in enumerate do
        local data = call(node.GetData,node)
        local id = data and data.recipeInfo and data.recipeInfo.recipeID
        if P.IsPositiveInteger(id) and not seen[id] then ids[#ids+1] = id; seen[id] = true end
    end
    return ids
end

local function modernRecipes(api)
    local base = call(api.GetBaseProfessionInfo)
    local skill = call(api.GetChildProfessionInfo) or base
    if type(base) ~= "table" or type(skill) ~= "table" or type(base.professionName or skill.professionName) ~= "string" then return end
    if call(api.IsTradeSkillLinked) or call(api.IsTradeSkillGuild) or call(api.IsNPCCrafting) then return end
    local ids = call(api.GetAllRecipeIDs)
    local coverage = "complete"
    if type(ids) ~= "table" then ids = call(api.GetFilteredRecipeIDs); coverage = "filtered" end
    if type(ids) ~= "table" or #ids == 0 then ids = visibleRecipes(); coverage = "filtered" end
    if type(ids) ~= "table" or #ids == 0 then return end
    local out = {name=text(base.professionName or skill.professionName), skillID=base.professionID, rank=skill.skillLevel,
        maxRank=skill.maxSkillLevel, capturedAt=now(), coverage=coverage, recipes={}}
    for _, id in ipairs(ids) do
        local info = call(api.GetRecipeInfo, id)
        local color = info and difficulty[info.relativeDifficulty]
        if info and info.learned == true and info.disabled ~= true and color and info.canSkillUp ~= false and type(info.name) == "string" then
            local recipe = {name=text(info.name), color=color, turnsGrayAt=info.maxTrivialLevel, reagents={}, precise=true}
            local schematic = call(api.GetRecipeSchematic, id, false)
            if type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then recipe.precise = false
            else
                local byItem = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics) do
                    if slot.required ~= false then
                        local options = slot.reagents
                        local item = type(options) == "table" and #options == 1 and options[1]
                        if item and P.IsPositiveInteger(item.itemID) and P.IsPositiveInteger(slot.quantityRequired) then
                            local reagent = byItem[item.itemID]
                            if reagent then reagent.count = reagent.count + slot.quantityRequired
                            else
                                reagent = {itemID=item.itemID, name=itemName(item.itemID), count=slot.quantityRequired}
                                byItem[item.itemID] = reagent
                                recipe.reagents[#recipe.reagents+1] = reagent
                            end
                        else recipe.precise = false end
                    end
                end
            end
            local requirements = call(api.GetRecipeRequirements, id)
            if type(requirements) == "table" then
                for _, requirement in ipairs(requirements) do
                    if requirement.met == false then recipe.requirement = text(requirement.name); break end
                end
            end
            out.recipes[#out.recipes+1] = recipe
        end
    end
    return out
end

function D:Capture(readBank, readRecipes)
    local record = character()
    if not record then return end
    self.current = record
    local money = call(GetMoney)
    if P.IsFinite(money) and money >= 0 then record.moneyCopper = money; record.moneyAt = now() end
    local bags, bank = scan(false), readBank and scan(true)
    if bank and bank.coverage == "partial" and record.bank and record.bank.coverage == "complete" then bank = nil end
    self.bagsLive, self.bankLive = bags ~= nil, bank and true or false
    record.bags, record.bank = bags or record.bags, bank or record.bank
    local professions, coverage = C.Professions()
    if coverage ~= "unknown" or not record.professions then
        record.professions, record.professionCoverage = professions, coverage
        record.professionsAt = now()
    end
    if readRecipes then
        local profile = modernRecipes(C_TradeSkillUI or {})
        if profile then record.recipes[profile.name] = profile end
    end
end

local recipeEvents = {TRADE_SKILL_SHOW=true, TRADE_SKILL_LIST_UPDATE=true, TRADE_SKILL_DATA_SOURCE_CHANGED=true}
function D:Event(event)
    if event == "PLAYER_LOGOUT" then self:Capture(self.bankOpen,false); return end
    if event == "BANKFRAME_OPENED" then self.bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then self.bankOpen = false
    elseif recipeEvents[event] then self.professionOpen = true
    elseif event == "TRADE_SKILL_CLOSE" then self.professionOpen = false end
    self.pending = (call(GetTime) or 0) + 0.3
end

function D:Tick()
    if self.pending and (call(GetTime) or 0) >= self.pending then
        self.pending = nil
        self:Capture(self.bankOpen, self.professionOpen)
    end
end

local ignored = {have=true, what=true, where=true, with=true, inventory=true, bank=true, bags=true, character=true, current=true, leveling=true, profession=true, craft=true, recipe=true, need=true, which=true, show=true, materials=true}
local function relevance(name, id, question, tokens)
    name = (name or ""):lower()
    if name ~= "" and question:find(name,1,true) then return 100 end
    if id and question:match("%f[%d]" .. id .. "%f[%D]") then return 100 end
    for _, token in ipairs(tokens) do if name:find(token,1,true) then return 20 end end
    return 0
end

local function location(snapshot, live, question, tokens)
    if not snapshot then return {status="unseen"} end
    local items = {}
    for _, item in pairs(snapshot.items) do
        local name = item.name or itemName(item.itemID)
        items[#items+1] = {itemID=item.itemID, name=name, count=item.count, score=relevance(name,item.itemID,question,tokens)}
    end
    table.sort(items,function(a,b) if a.score~=b.score then return a.score>b.score end; return a.itemID<b.itemID end)
    local out = {status=live and "live" or "last seen", capturedAt=snapshot.capturedAt, coverage=snapshot.coverage, distinctItems=#items, items=P.Array()}
    for i, item in ipairs(items) do
        if i > 8 and item.score == 0 then out.coverage = "partial"; break end
        out.items[#out.items+1] = {itemID=item.itemID, name=item.name, count=item.count}
    end
    return out
end

local function stock(snapshot,id)
    local item = snapshot and snapshot.items[id]
    if item then return item.count end
    if snapshot and snapshot.coverage == "complete" then return 0 end
end

local function candidates(profile, record, limit)
    local rows = {}
    for _, recipe in ipairs(profile.recipes) do
        local reagents, affordable, missing = P.Array(), nil, 0
        local known = recipe.precise
        for _, input in ipairs(recipe.reagents) do
            local bags, bank = stock(record.bags,input.itemID), stock(record.bank,input.itemID)
            if bags then
                local crafts = math.floor(bags / input.count)
                affordable = affordable and math.min(affordable,crafts) or crafts
                missing = missing + math.max(input.count - bags,0)
            else known = false end
            local alts = P.Array()
            for _, alt in pairs(A.db.characters or {}) do
                if alt ~= record and #alts < 4 then
                    local altBags, altBank = stock(alt.bags,input.itemID), stock(alt.bank,input.itemID)
                    if (altBags or 0) > 0 or (altBank or 0) > 0 then
                        alts[#alts+1] = {name=alt.name,realm=alt.realm,bagsLastSeen=altBags,bankLastSeen=altBank}
                    end
                end
            end
            reagents[#reagents+1] = {name=input.name or itemName(input.itemID),itemID=input.itemID,perCraft=input.count,inBags=bags,inBankLastSeen=bank,onAltsLastSeen=alts}
        end
        local row = {name=recipe.name,color=recipe.color,turnsGrayAt=recipe.turnsGrayAt,reagents=reagents,
            materialCountsKnown=known,craftsFromBags=known and affordable or nil,requires=recipe.requirement}
        local weights={orange=30,yellow=20,green=10}
        row.score = (weights[recipe.color] or 0) + ((affordable or 0)>0 and 28 or 0) - math.min(missing,25)
        if not recipe.precise or recipe.requirement then row.score = row.score - 25 end
        rows[#rows+1] = row
    end
    table.sort(rows,function(a,b) if a.score ~= b.score then return a.score > b.score end; return a.name < b.name end)
    local output = P.Array()
    for i = 1, math.min(#rows,limit) do rows[i].score=nil; output[i]=rows[i] end
    return output
end

function D:Snapshot(question)
    self:Capture(self.bankOpen,self.professionOpen)
    question = (question or ""):lower()
    local tokens = {}
    for word in question:gmatch("[%w']+") do if #word > 3 and not ignored[word] then tokens[#tokens+1]=word:gsub("s$","") end end
    local records = {}
    for _, record in pairs(A.db.characters or {}) do records[#records+1] = record end
    table.sort(records,function(a,b)
        if a == self.current or b == self.current then return a == self.current and b ~= self.current end
        local aNamed,bNamed = question:find(a.name:lower(),1,true) ~= nil,question:find(b.name:lower(),1,true) ~= nil
        if aNamed ~= bNamed then return aNamed end
        return (a.moneyAt or a.professionsAt or 0) > (b.moneyAt or b.professionsAt or 0)
    end)
    local out = {characters=P.Array(),knownCharacters=#records,recipeGuidance=P.Array()}
    for i = 1, math.min(#records,16) do
        local record = records[i]
        local current = record == self.current
        out.characters[#out.characters+1] = {name=record.name,realm=record.realm,current=current,moneyCopper=record.moneyCopper,moneyAt=record.moneyAt,
            bags=location(record.bags,current and self.bagsLive,question,tokens),bank=location(record.bank,current and self.bankLive,question,tokens),
            professions=P.Array(record.professions or {}),professionsAt=record.professionsAt,professionCoverage=record.professionCoverage}
    end
    if self.current then
        local all = question:find("profession",1,true) or question:find("craft",1,true) or question:find("recipe",1,true)
        for name, profile in pairs(self.current.recipes) do
            if all or question:find(name:lower(),1,true) then
                local stale = false
                for _, profession in ipairs(self.current.professions or {}) do
                    if profession.name == name and profession.rank and profile.rank and profession.rank ~= profile.rank then stale = true end
                end
                out.recipeGuidance[#out.recipeGuidance+1] = {profession=name,rankAtCapture=profile.rank,maxRank=profile.maxRank,capturedAt=profile.capturedAt,
                    stale=stale,coverage=profile.coverage,options=candidates(profile,self.current,7)}
            end
        end
    end
    return out
end

function D.Trim(inventory)
    local longest
    for _, character in ipairs(inventory.characters) do
        for _, location in ipairs({character.bags,character.bank}) do
            if location.items and #location.items > 0 and (not longest or #location.items > #longest.items) then longest = location end
        end
    end
    if longest then
        local target = math.floor(#longest.items / 2)
        while #longest.items > target do table.remove(longest.items) end
        longest.coverage = "partial"
        return true
    end
    for _, guidance in ipairs(inventory.recipeGuidance) do
        if #guidance.options > 2 then table.remove(guidance.options); guidance.coverage = "partial"; return true end
    end
    if #inventory.characters > 1 then table.remove(inventory.characters); return true end
end
