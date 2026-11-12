local A, P = NibWhisper, NibWhisper.Protocol
local function fails(fn) local ok=pcall(fn); assert(not ok,'Expected rejection') end
assert(P.EncodeBase64('hello')=='aGVsbG8=')
assert(P.DecodeBase64('aGVsbG8=')=='hello')
assert(P.DecodeBase64('AA==')=='\0')
fails(function() P.DecodeBase64('AB==') end)
fails(function() P.DecodeBase64('AA=A') end)
fails(function() P.DecodeBase64('AA==AAAA') end)
local emoji=P.DecodeJSON('"\\uD83D\\uDC1F"')
assert(P.ValidUTF8(emoji) and #emoji==4)
assert(P.DecodeJSON(P.EncodeJSON({hello=emoji})).hello==emoji)
assert(P.EncodeJSON(P.Array())=='[]')
assert(P.EncodeJSON({})=='{}')
assert(P.DecodeJSON('false')==false)
assert(P.DecodeJSON('null')==P.NULL)
fails(function() P.DecodeJSON('{"a":1,"a":2}') end)
fails(function() P.DecodeJSON('[1,]') end)
fails(function() P.DecodeJSON('01') end)
fails(function() P.DecodeJSON('1e999') end)
fails(function() P.DecodeJSON('"\\ud800"') end)
fails(function() P.DecodeJSON('"\\udc00"') end)
fails(function() P.DecodeJSON('{"x": true} trailing') end)
fails(function() P.DecodeJSON('"'..string.char(192,128)..'"') end)
assert(P.SanitizeText('|Hitem:7|h[Fish]|h |Tbad:9|t |cffff0000hello|r')=='[Fish]  hello')
A:Initialize()
assert(A.initialized and A.UI.chat and A.UI.mascot and A.UI.minimap)
assert(A.db.opticalEnabled==false)
local snapshot=A:Snapshot()
assert(snapshot.player.class=='PALADIN' and snapshot.player.name==nil)
assert(math.abs(snapshot.player.x-42)<.001)
assert(snapshot.client.interface==16001 and snapshot.client.game=='FOREVER')
assert(snapshot.quests.completionCoverage=='complete' and #snapshot.quests.completedIds==3)
assert(snapshot.quests.active[1].id==7 and snapshot.quests.active[1].readyForTurnIn==false)
assert(snapshot.quests.active[1].objectives[1].fulfilled==3)
assert(snapshot.professions[1].rank==99)
assert(snapshot.restedXP.currentStep==2 and snapshot.restedXP.steps[2].elements[1].text=='Defeat kobolds')
assert(#snapshot.addons==2)
local savedCompleted=C_QuestLog.GetAllCompletedQuestIDs; C_QuestLog.GetAllCompletedQuestIDs=nil
assert(A:Snapshot().quests.completionCoverage=='unknown')
C_QuestLog.GetAllCompletedQuestIDs=savedCompleted
local oldStub=LibStub; LibStub=nil
assert(A:Snapshot().restedXP.available==false)
LibStub=oldStub
C_QuestLog.GetAllCompletedQuestIDs=nil
GetQuestsCompleted=function() return {[783]=true,[7]=false} end
local legacy=A:Snapshot().quests
assert(legacy.completionCoverage=='partial' and #legacy.completedIds==1 and legacy.completedIds[1]==783)
GetQuestsCompleted=nil; C_QuestLog.GetAllCompletedQuestIDs=savedCompleted
local oldSkill=C_SkillInfo; C_SkillInfo=nil
GetNumSkillLines=function() return 2 end
GetSkillLineInfo=function(i) if i==1 then return 'Professions',true,false else return 'Alchemy',false,false,55,false,0,75 end end
GetSpellInfo=function(id) if id==2259 then return 'Alchemy' end end
local skillFallback=A:Snapshot().professions
assert(#skillFallback==1 and skillFallback[1].rank==55 and skillFallback[1].maxRank==75)
C_SkillInfo=oldSkill; GetNumSkillLines=nil; GetSkillLineInfo=nil; GetSpellInfo=nil
assert(A:SendQuestion('What should I do next?'))
local pending=A.pending
local request=P.DecodePacket('NIBQ1',pending.packet)
assert(request.question=='What should I do next?' and request.requestId==pending.requestId)
assert(request.capturedAt==pending.capturedAt and request.context.quests.active[1].id==7)
assert(not A:SendQuestion('Second pending request'))
local reply={schema=1,requestId=pending.requestId,capturedAt=pending.capturedAt,answer='Mrrgl! |Hitem:1|h[Fish]|h finish those kobolds.',mood='happy',intent='advice',sources=P.Array({{id='s1',title='Quest',url='https://www.wowhead.com/classic/quest=7'}}),actions=P.Array({{type='waypoint',title='Abbey',mapID=1429,x=48,y=42}})}
local packet=P.EncodePacket('NIBR1',reply)
local stale=P.DecodePacket('NIBR1',packet); stale.requestId='old'
assert(not A:ImportReply(P.EncodePacket('NIBR1',stale)))
assert(A.pending==pending)
local wrongTime=P.DecodePacket('NIBR1',packet); wrongTime.capturedAt=wrongTime.capturedAt+1
assert(not A:ImportReply(P.EncodePacket('NIBR1',wrongTime)))
assert(NibWhisper_Receive(packet))
assert(waypoint==nil and openedQuest==nil and selectedGuide==nil, 'Importing a reply must not execute any game action')
assert(A.pending==nil and A.UI.lastReply.answer=='Mrrgl! [Fish] finish those kobolds.')
assert(not NibWhisper_Receive(packet))
assert(not A:ImportReply(packet))
local invalid=P.DecodePacket('NIBR1',packet); invalid.requestId='check'; invalid.answer=string.rep('x',8001)
assert(not P.ValidateResponse(invalid,{requestId='check',capturedAt=invalid.capturedAt}))
invalid.answer='safe'; invalid.actions[1].x=math.huge
assert(not P.ValidateResponse(invalid,{requestId='check',capturedAt=invalid.capturedAt}))
fails(function() P.EncodePacket('NIBQ1',{value=string.rep('x',P.MAX_PACKET)}) end)
assert(A:ExecuteAction(A.UI.lastReply.actions[1]))
assert(waypoint[1]==1429 and waypoint[2]==.48 and waypoint[3]==.42)
assert(A:ExecuteAction({type='quest',title='Quest',questID=7}) and openedQuest==7)
assert(A:ExecuteAction({type='guide',title='Guide',group='RestedXP Forever Guide (A)',name='01-06 Elwynn Forest'}))
assert(selectedGuide==nil and A.UI.copy.box.edit:GetText():find('01-06 Elwynn Forest',1,true))
assert(not A:ExecuteAction({type='waypoint',title='Invalid',mapID=1429,x=101,y=0}))
assert(not A:ExecuteAction({type='lua',title='Never',name='print("oops")'}))
combat=true; assert(not A:ExecuteAction({type='quest',title='Quest',questID=7})); combat=false
assert(not A:SendQuestion('sk-abcdefghijklmnopqrstuvwxyz123456'))
A:SetOpticalEnabled(true)
assert(A:SendQuestion('Where is my next stop?'))
local state=A.GetOpticalState()
assert(state.packet==A.pending.packet and state.session==A.session and state.nextSlot==1)
clock=106
slotCallback=function() NibWhisper_Receive(packet) end -- stale old reply must not clear pending
A:PollReplySlots()
assert(A.pending and #slotLoads==1 and A.nextSlot==2)
clock=108; combat=true; A:PollReplySlots(); assert(#slotLoads==1); combat=false
local ack={schema=1,requestId=A.pending.requestId,capturedAt=A.pending.capturedAt}
slotCallback=function() NibWhisper_Receive(P.EncodePacket('NIBA1',ack)) end
A:PollReplySlots(); assert(A.pending.received and A.pending.signalUntil==nil and #slotLoads==2)
clock=111
local nextReply={schema=1,requestId=A.pending.requestId,capturedAt=A.pending.capturedAt,answer='Your next stop is the abbey.',mood='thinking',intent='advice',sources=P.Array(),actions=P.Array()}
slotCallback=function() NibWhisper_Receive(P.EncodePacket('NIBR1',nextReply)) end
A:PollReplySlots(); assert(A.pending==nil and #slotLoads==3)
assert(A:SendQuestion('One final route check?'))
A.nextSlot=201; clock=120; A:PollReplySlots(); assert(A.pending.manualOnly)
A:CancelPending(); assert(A.pending==nil)
A.UI:ShowSetup()
A.UI.geminiSetup.connect.scripts.OnClick()
local setup=P.DecodePacket('NIBC1',A.pending.packet)
assert(setup.source=='clipboard' and not setup.key and not setup.fingerprint)
local connected={schema=1,requestId=setup.requestId,capturedAt=setup.capturedAt,connected=true}
assert(NibWhisper_Receive(P.EncodePacket('NIBK1',connected)) and not A.pending and A:GetChatMode()=='automatic')
assert(A:ConnectGemini())
clock=131; A:PollReplySlots()
assert(not A.pending and A.UI.geminiSetup.status:GetText():find('No response',1,true))
assert(#A.charDB.history<=80)

-- Capture bank and bags on one character, then switch to an alt and check the saved records.
local data=A.CharacterData
local toon='Fins'
function UnitFullName() return toon,'Test Realm' end
function UnitGUID() return 'Player-1-'..toon end
function GetMoney() return toon=='Fins' and 120305 or 505010 end
Enum={BagIndex={Backpack=0,ReagentBag=5},BankType={Character=0}}
C_Bank={FetchPurchasedBankTabIDs=function(kind) assert(kind==0);return {12} end}
C_Item={GetItemNameByID=function(id) return id==2447 and 'Peacebloom' or 'Silverleaf' end}
C_Container={GetContainerNumSlots=function(bag) return (bag==0 or bag==12) and 1 or 0 end,
 GetContainerItemInfo=function(bag) return {itemID=2447,stackCount=bag==12 and 10 or (toon=='Fins' and 6 or 2)} end}
data:Event('BANKFRAME_OPENED'); clock=132; data:Tick()
data:Event('BANKFRAME_CLOSED')
toon='Nibble'
C_TradeSkillUI={GetBaseProfessionInfo=function() return {professionName='Alchemy',skillLevel=99,maxSkillLevel=150} end,
 GetRecipeInfo=function() return {name='Minor Healing Potion',learned=true,canSkillUp=true,relativeDifficulty=0,maxTrivialLevel=110} end,
 GetRecipeSchematic=function() return {reagentSlotSchematics={{required=true,quantityRequired=1,reagents={{itemID=2447}}}}} end}
ProfessionsFrame={CraftingPage={RecipeList={ScrollBox={GetDataProvider=function() return {EnumerateEntireRange=function()
 local served=false; return function() if not served then served=true;return 1,{GetData=function() return {recipeInfo={recipeID=2330}} end} end end
end} end}}}}
data:Event('TRADE_SKILL_SHOW')
local req,encoded=A:BuildRequest('Where is Peacebloom and what Alchemy recipe should I craft?',26000)
assert(req and encoded and #encoded<=26000)
local inventory=P.DecodePacket('NIBQ1',encoded).context.inventory
local me,alt=inventory.characters[1],inventory.characters[2]
assert(me.name=='Nibble' and me.moneyCopper==505010 and me.bank.status=='unseen')
assert(me.bags.status=='live' and me.bags.items[1].count==2)
assert(alt.name=='Fins' and alt.bags.status=='last seen' and alt.bank.items[1].count==10 and alt.moneyCopper==120305)
local plan=inventory.recipeGuidance[1]
assert(plan.profession=='Alchemy' and plan.rankAtCapture==99 and plan.coverage=='filtered')
local potion=plan.options[1]
assert(potion.name=='Minor Healing Potion' and potion.craftsFromBags==2 and potion.reagents[1].onAltsLastSeen[1].bankLastSeen==10)
