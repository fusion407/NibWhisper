import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {loadKnowledge,retrieveKnowledge} from '../companion/lib/knowledge.mjs';
import {sanitizeActions} from '../companion/lib/protocol.mjs';
const require=createRequire(import.meta.url);
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=fileURLToPath(new URL('../addon/',import.meta.url));
// Files in the order the game loads them: the core addon first, then each enabled sub-addon.
const core=['NibWhisper/Protocol.lua','NibWhisper/Context.lua','NibWhisper/UI.lua','NibWhisper/Core.lua'];
const assistant=['NibWhisper_Assistant/Assistant.lua','NibWhisper_Assistant/CharacterData.lua','NibWhisper_Assistant/Optical.lua'];
const guide=['NibWhisper_Guide/TrailData.lua','NibWhisper_Guide/QuestLinks.lua','NibWhisper_Guide/Voice.lua','NibWhisper_Guide/Trail.lua','NibWhisper_Guide/TrailSync.lua'];
function client(files){
 const l=lauxlib.luaL_newstate();lualib.luaL_openlibs(l);
 const run=(s,name,module=false)=>{
  let status=lauxlib.luaL_loadbuffer(l,to_luastring(s),null,to_luastring(name));if(status!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(l,-1)));
  if(module){lua.lua_pushstring(l,to_luastring('NibWhisper'));lua.lua_getglobal(l,to_luastring('NibWhisper'));}
  status=lua.lua_pcall(l,module?2:0,0,0);if(status!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(l,-1)));
 };
 run(fs.readFileSync(path.join(root,'NibWhisper/tests/wow-stub.lua'),'utf8'),'@stub');
 for(const name of files)run(fs.readFileSync(path.join(root,name),'utf8'),'@'+name,true);
 return {l,run};
}

test('the leveling guide works with the AI assistant switched off',()=>{
 const {l,run}=client([...core,...guide]);
 run(`
 local A=NibWhisper;local T=A.Trail
 function UnitGUID() return 'Player-123-00A0B0C0' end
 function UnitLevel() return 1 end
 A.eventFrame.scripts.OnEvent(nil,'PLAYER_LOGIN')
 assert(A.initialized and T and not A.Assistant and not A.Optical and not A.CharacterData)
 assert(not A.UI.chat and not A.UI.mascot and A.UI.minimap,'chat and the mascot belong to the assistant')
 assert(T.frame and T.frame:IsShown(),'the guide is open at login by default')
 -- The guide remembers where it was dragged or resized to.
 assert(A.db.trailPosition==nil and not A.UI:RestorePosition(T.frame,'trailPosition'),'a fresh install uses the default spot')
 local placed
 T.frame.GetCenter=function() return 620,310 end
 T.frame.SetPoint=function(_,point,_,_,x,y) placed={point,x,y} end
 T.frame.scripts.OnDragStop()
 assert(A.db.trailPosition.x==120 and A.db.trailPosition.y==-90,'dragging saves the offset from the screen centre')
 T.frame.GetCenter=function() return 700,400 end;T.frame.afterResize();assert(A.db.trailPosition.x==200 and A.db.trailPosition.y==0,'resizing saves it too')
 assert(A.UI:RestorePosition(T.frame,'trailPosition') and placed[1]=='CENTER' and placed[2]==200 and placed[3]==0)
 A.db.trailPosition={x='bad'};assert(not A.UI:RestorePosition(T.frame,'trailPosition'),'a damaged saved position is ignored')
 A.db.trailPosition=nil;T.frame.GetCenter=nil;T.frame.SetPoint=nil
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'LeftButton');assert(not T.frame:IsShown(),'left-click closes the open guide when there is no chat')
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'LeftButton');assert(T.frame:IsShown(),'left-click opens the guide when there is no chat')
 assert(#T.footerButtons==4,'Ask Nib is only offered with the assistant')
 assert(T:Select(T:Suggested(T.Profile(),'Solo route')));T:Tick(true)
 assert(T.stepTag:GetText():find('Step',1,true))
 assert(A:Ask('What next?')==false,'chat requests are refused without the assistant')
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'RightButton')
 local o=A.UI.options;assert(o:IsShown() and o.advance and o.quests and o.scale and not o.modes and not o.mascot)
 assert(o.login:GetText()=='Open at login: on');o.login.scripts.OnClick();assert(A.db.trailOpenOnLogin==false and o.login:GetText()=='Open at login: off')
 A.initialized=false;A.UI.created=true;T.frame:Hide();A:Initialize();assert(not T.frame:IsShown(),'the Options switch keeps the guide closed at login')
 A.db.trailOpenOnLogin=nil;T:Open()
 -- Nib's wording: instructions are rephrased, plain bookkeeping lines and all names and markup are left alone.
 local V=A.TrailVoice
 for _,line in ipairs({'Accept Return to Marshal McBride','Turn in Kill the Kobolds','Train Battle Shout','Collect 8 Boar Tusks','Abandon The Lost Tools','Pick up the crate','','[Mining Pick]'}) do assert(V.Say(line)==line,line) end
 local talk=V.Say('Talk to |cRXP_FRIENDLY_Marshal McBride|r')
 assert(talk~='Talk to |cRXP_FRIENDLY_Marshal McBride|r' and talk:find(' |cRXP_FRIENDLY_Marshal McBride|r',1,true) and not talk:find('Talk to',1,true),talk)
 assert(V.Say('Talk to |cRXP_FRIENDLY_Marshal McBride|r')==talk,'the same step always reads the same way')
 local tight=V.Say("|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to|r |cRXP_FRIENDLY_Ur'kyo|r")
 assert(tight:find('|Tinterface/worldmap/chatbubble_64grey.blp:20|t',1,true)==1 and tight:find("|r |cRXP_FRIENDLY_Ur'kyo|r",1,true) and not tight:find('Talk to',1,true),tight)
 local two=V.Say('Kill |cRXP_ENEMY_Yetis|r. Loot them for their |cRXP_LOOT_Hides|r')
 assert(not two:find('Kill ',1,true) and not two:find('Loot them',1,true) and two:find('|cRXP_ENEMY_Yetis|r. ',1,true) and two:find(' their |cRXP_LOOT_Hides|r',1,true),two)
 assert(V.Say('Click items on the floor')=='Tap items on the floor','a short phrase does not match inside a longer word')
 assert(V.Say('Click it')=='Give it a poke')
 assert(V.Say('He patrols the road to the north')=='He patrols the road to the north','sentences Nib has nothing to add to stay as written')
 local inside=V.Say('|cRXP_WARN_Be careful as |cRXP_ENEMY_Defias Thugs|r hit hard|r')
 assert(inside:sub(1,11)=='|cRXP_WARN_' and not inside:find('Be careful as',1,true) and inside:find('|cRXP_ENEMY_Defias Thugs|r hit hard|r',1,true),inside)
 local worded=T.Parse('step\\n>> Talk to |cRXP_FRIENDLY_Brother Bob|r\\n.accept 7 >> Accept Kobold Camp Cleanup')
 assert(not worded.entries[1].desc:find('Talk to',1,true) and worded.entries[1].desc:find(' Brother Bob',1,true) and worded.entries[1].display:find('|Hnib:FRIENDLY:Brother Bob|h',1,true),worded.entries[1].display)
 assert(worded.entries[2].desc=='Accept Kobold Camp Cleanup')
 A.UI:RefreshOptions();assert(A.UI.options.voice:GetText()=="Nib's wording: on")
 local before=T.parsed
 A.UI.options.voice.scripts.OnClick()
 assert(A.db.trailVoice==false and T.parsed~=before and A.UI.options.voice:GetText()=="Nib's wording: off",'switching it off rereads the chapters')
 assert(T.Parse('step\\n>> Talk to |cRXP_FRIENDLY_Brother Bob|r').entries[1].desc=='Talk to Brother Bob','off shows the route as written')
 A.UI.options.voice.scripts.OnClick();assert(A.db.trailVoice==true)
 A.db.trailVoice=nil
 -- The chapter sound plays once when the player passes the last step, by Done or by auto advance, and never while browsing.
 local played={}
 function PlaySoundFile(file,channel) played[#played+1]=file..'|'..channel end
 local short={id='sound-fixture',title='Sound fixture',mode='Solo route',faction='Alliance',conditions={},steps=2,next={}}
 T.parsed[short.id]={steps={T.Parse('step\\n>> Walk to the abbey'),T.Parse('step\\n.xp 1 >> Reach level 1')},labels={}}
 T.byID[short.id]=short
 local before=T.state.selected;T.state.selected={id=short.id};T:Write(short,1);T.reviewing=false
 T:Move(1);assert(#played==0,'a step in the middle is silent')
 T:Move(1);assert(#played==1 and played[1]=='Interface\\\\AddOns\\\\NibWhisper_Guide\\\\Sounds\\\\jobs_done.mp3|Master',played[1])
 T:Move(1);assert(#played==1,'an already finished chapter is silent')
 T:Browse(2);T:Browse(1);assert(#played==1,'browsing is silent')
 T:Write(short,2);T.reviewing=false;T.arrivedStep=nil;T:Tick(true)
 assert(T.state.guides[short.id].step==3 and #played==2,'auto advance past the last step plays it too')
 A.db.trailFinishSound=false;T:Write(short,2);T:Move(1);assert(#played==2,'the Options switch silences it')
 A.UI:RefreshOptions();assert(A.UI.options.finish:GetText()=='Chapter sound: off')
 A.UI.options.finish.scripts.OnClick();assert(A.db.trailFinishSound==true and #played==3 and A.UI.options.finish:GetText()=='Chapter sound: on','switching it on previews the sound')
 A.db.trailFinishSound=nil
 T.state.selected=before;T.state.guides[short.id]=nil;T.byID[short.id]=nil;T:Tick(true)
 T:ShowSync();A.db.opticalEnabled=true;assert(not T:RequestSync() and T.syncStatus:find('AI Assistant',1,true))
 assert(T:ExportProgress():sub(1,6)=='NIBT1:','manual export still works')
 T:ShowKeyword('nib:ENEMY:Kobold Vermin');assert(T.infoWindow:IsShown() and not T.infoWindow.ask:IsShown())
 A.Test.Slash('');assert(not T.frame:IsShown(),'/nib toggles the guide when there is no chat')
 A.eventFrame.scripts.OnUpdate(nil,.3)
 `,'@guide-only');
 lua.lua_close(l);
});

test('the AI assistant works with the leveling guide switched off',()=>{
 const {l,run}=client([...core,...assistant]);
 run(`
 local A=NibWhisper
 A.eventFrame.scripts.OnEvent(nil,'ADDON_LOADED','NibWhisper');assert(not A.initialized,'start-up waits for login so sub-addons can load')
 A.eventFrame.scripts.OnEvent(nil,'PLAYER_LOGIN')
 assert(A.initialized and A.Assistant and not A.Trail and A.UI.chat and A.UI.mascot and not A.UI.guideButton)
 -- Nib himself can be resized by his corner grip. He keeps his proportions, stays within limits, and remembers the size.
 local nib,cursor=A.UI.mascot,400
 function GetCursorPosition() return cursor,300 end
 assert(nib:GetWidth()==126 and nib:GetHeight()==168 and nib.grip)
 nib.grip.scripts.OnMouseDown(nib.grip,'RightButton');assert(not nib.grip.scripts.OnUpdate,'only the left button resizes')
 nib.grip.scripts.OnMouseDown(nib.grip,'LeftButton');cursor=463;nib.grip.scripts.OnUpdate()
 assert(nib:GetWidth()==189 and nib:GetHeight()==252,'dragging 63 to the right makes him half as big again')
 cursor=2000;nib.grip.scripts.OnUpdate();assert(nib:GetWidth()==380,'he has a largest size')
 cursor=-2000;nib.grip.scripts.OnUpdate();assert(nib:GetWidth()==60 and nib:GetHeight()==80,'and a smallest')
 cursor=442;nib.grip.scripts.OnUpdate();nib.grip.scripts.OnMouseUp()
 assert(A.db.mascotWidth==168 and nib:GetHeight()==224 and not nib.grip.scripts.OnUpdate and A.db.position,'letting go saves the size and place')
 A.Test.Slash('reset');assert(A.db.mascotWidth==nil and nib:GetWidth()==126 and nib:GetHeight()==168,'/nib reset restores his usual size')
 A.db.mascotWidth=200;A.UI:SetMascotWidth(A.db.mascotWidth);assert(nib:GetWidth()==200 and nib:GetHeight()==267)
 A.UI:SetMascotWidth('bad');assert(nib:GetWidth()==126,'a damaged saved size falls back to the usual one')
 A.db.mascotWidth=nil
 -- Chat remembers where it was dragged or resized to.
 local chat,placed=A.UI.chat
 assert(A.db.chatPosition==nil)
 chat.GetCenter=function() return 380,460 end
 chat.SetPoint=function(_,point,_,_,x,y) placed={point,x,y} end
 A.UI.chatHeader.scripts.OnDragStop();assert(A.db.chatPosition.x==-120 and A.db.chatPosition.y==60,'dragging chat saves its position')
 chat.GetCenter=function() return 500,400 end;chat.afterResize();assert(A.db.chatPosition.x==0 and A.db.chatPosition.y==0,'resizing chat saves it too')
 assert(A.UI:RestorePosition(chat,'chatPosition') and placed[1]=='CENTER' and placed[2]==0)
 A.db.chatPosition=nil;chat.GetCenter=nil;chat.SetPoint=nil
 function IsShiftKeyDown() return true end
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'LeftButton');assert(A.UI.chat:IsShown(),'Shift-click falls back to chat without the guide')
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'RightButton')
 local o=A.UI.options;assert(o:IsShown() and o.modes and o.mascot and o.scale and not o.advance and not o.quests)
 assert(A:Ask('What should I do next?') and A.UI.lastReply.answer:find('Leveling Guide',1,true),A.UI.lastReply.answer)
 assert(A:Ask('What quests am I on?') and A.UI.lastReply.answer:find('Kobold Camp Cleanup',1,true))
 A.Test.Slash('trail');A.eventFrame.scripts.OnEvent(nil,'QUEST_DETAIL');A.eventFrame.scripts.OnUpdate(nil,.3)
 -- Linking Gemini once is remembered at every later login, and a player left on copy and paste by 0.6.1-0.6.4 is put back.
 A.db.chatMode='manual';A.db.opticalEnabled=false;A.db.geminiLinked=nil
 A.initialized=false;A:Initialize()
 assert(A.db.geminiLinked==true and A:GetChatMode()=='automatic' and A.db.opticalEnabled==true,'the earlier fallback is undone once')
 A:SetChatMode('manual');A.initialized=false;A:Initialize()
 assert(A:GetChatMode()=='manual','a later deliberate choice is kept')
 A:SetChatMode('localGuide');A.db.geminiLinked=nil;A.db.chatMode=nil;A.db.opticalEnabled=false
 A.initialized=false;A:Initialize();assert(A.db.geminiLinked==false and A:GetChatMode()=='localGuide','a player who never linked stays on guide chat')
 assert(A:ConnectGemini())
 local setup=A.Protocol.DecodePacket('NIBC1',A.pending.packet)
 assert(NibWhisper_Receive(A.Protocol.EncodePacket('NIBK1',{schema=1,requestId=setup.requestId,capturedAt=setup.capturedAt,connected=true})))
 assert(A.db.geminiLinked==true and A:GetChatMode()=='automatic')
 A.initialized=false;A:Initialize();assert(A:GetChatMode()=='automatic' and A.db.opticalEnabled==true,'the link survives a new login')
 `,'@assistant-only');
 lua.lua_close(l);
});

test('real trail bundle loads, recommends a starter, tracks quests, converts world waypoints and protects sync identity',()=>{
 const {l,run}=client([...core,'NibWhisper_Assistant/Assistant.lua','NibWhisper_Assistant/Optical.lua',...guide]);
 run(`
 local A=NibWhisper;local T=A.Trail
 assert(#T.data.chapters==282)
 function UnitLevel() return 1 end
 function UnitGUID() return 'Player-123-00A0B0C0' end
 function CreateVector2D(x,y) return {x=x,y=y} end
 C_Map.GetWorldPosFromMapPos=function(id,v) if id==1429 and v then return 0,{GetXY=function() return -8000-v.y*3000,1000-v.x*3000 end} end end
 local active,complete={},{}
 C_QuestLog.GetAllCompletedQuestIDs=function()return{}end
 C_QuestLog.IsQuestFlaggedCompleted=function(id)return complete[id]==true end
 C_QuestLog.IsOnQuest=function(id)return active[id]==true end
 TomTom.SetCrazyArrow=function(_,uid,dist,title) arrow={uid,dist,title} end
 TomTom.RemoveWaypoint=function(_,uid) removed=uid end
 TomTom.AddWaypoint=function(_,map,x,y,options) waypoint={map,x,y,options};return {from=options.from} end
 A:Initialize(); T:Open()
 assert(not A.UI.mascot:IsShown())
 A.UI:ShowChat(); assert(A.UI.chat.strata=='HIGH' and T.frame.strata=='MEDIUM')
 A.UI.guideButton.scripts.OnClick(); assert(A.UI.chat:IsShown() and T.frame.strata=='HIGH' and A.UI.chat.strata=='MEDIUM')
 T.frame:Hide()
 function IsShiftKeyDown() return true end
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'LeftButton'); assert(T.frame:IsShown() and A.UI.chat:IsShown())
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'RightButton'); assert(not T.frame:IsShown() and not A.UI.options,'Shift with the right button toggles the guide, not Options')
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'RightButton'); assert(T.frame:IsShown())
 function IsShiftKeyDown() return false end
 A.eventFrame.scripts.OnEvent(nil,'PLAYER_DEAD'); T.frame:Hide(); T:Tick(true); assert(T.frame:IsShown())
 T.frame.close.scripts.OnClick(); T:Tick(true); assert(not T.frame:IsShown(),'closing the guide manually must survive the death transition')
 T:Open()
 assert(not T:Current(),'opening Trail should not select a chapter before sync')
 local suggested=T:Suggested(T.Profile(),'Solo route'); assert(suggested and T:Select(suggested)); T:Tick(true)
 local g,s=T:Current(); assert(g.name=='1-6 Northshire',g.name)
 assert(s.step==5,'expected Northshire quest opener, got '..s.step)
 assert(waypoint and waypoint[1]==1429 and math.abs(waypoint[2]-(1136.48/3000))<.001)
 assert(arrow and waypoint[4].persistent==false and waypoint[4].from=='NibTrail')
 local waypointRow
 for _, row in ipairs(T.rows) do if row.point and row.control and row.control.kind=='accept' then waypointRow=row;break end end
 assert(waypointRow and waypointRow.destination:IsShown())
 waypointRow.destination.scripts.OnClick();assert(T.clickedPoint==waypointRow.point or T.clickedPoint.x==waypointRow.point.x)
 T:ShowTargets(); assert(T.targetWindow.rows[1].attributes.macrotext=='/targetexact Deputy Willem')
 -- Quest automation acts only on the quest the visible step names, and only when switched on.
 local questCalls={}
 C_GossipInfo={GetActiveQuests=function() return {} end,GetAvailableQuests=function() return {{questID=999},{questID=783}} end,SelectAvailableQuest=function(id) questCalls[#questCalls+1]='select '..id end}
 local shownQuest=783
 function GetQuestID() return shownQuest end
 function AcceptQuest() questCalls[#questCalls+1]='accept' end
 function IsQuestCompletable() return true end
 function CompleteQuest() questCalls[#questCalls+1]='complete' end
 function GetNumQuestChoices() return 0 end
 function GetQuestReward(choice) questCalls[#questCalls+1]='reward '..choice end
 local fire=A.eventFrame.scripts.OnEvent
 fire(nil,'GOSSIP_SHOW');fire(nil,'QUEST_DETAIL')
 assert(table.concat(questCalls,',')=='select 783,accept',table.concat(questCalls,','))
 shownQuest=999;fire(nil,'QUEST_DETAIL');fire(nil,'QUEST_PROGRESS');fire(nil,'QUEST_COMPLETE')
 assert(#questCalls==2,'quests outside the current step are left alone')
 shownQuest=783;A.db.trailQuestAuto=false;fire(nil,'QUEST_DETAIL');assert(#questCalls==2,'the Options switch turns automation off')
 A.db.trailQuestAuto=nil
 function IsControlKeyDown() return true end
 fire(nil,'QUEST_DETAIL');assert(#questCalls==2,'holding Ctrl skips automation')
 function IsControlKeyDown() return false end
 T.frame:Hide();fire(nil,'QUEST_DETAIL');assert(#questCalls==2,'a closed guide automates nothing');T:Open()
 local turnin={id='turnin-fixture',title='Turn-in fixture',mode='Solo route',faction='Alliance',conditions={},steps=2}
 T.parsed[turnin.id]={steps={T.Parse('step\\n.turnin 783 >> Turn in A Threat Within\\n.link https://youtu.be/ab--cd >> Click here for video reference\\n.link /run print(1) >> Click here to run\\n>> Talk to |cRXP_FRIENDLY_Marshal McBride|r and loot |cRXP_LOOT_Nibbled-On Book|r'),T.Parse('step\\n>> Rest')},labels={}}
 T.byID[turnin.id]=turnin
 local previous=T.state.selected;T.state.selected={id=turnin.id};T:Write(turnin,1);active[783]=true
 questCalls={};fire(nil,'QUEST_PROGRESS');fire(nil,'QUEST_COMPLETE')
 assert(table.concat(questCalls,',')=='complete,reward 1',table.concat(questCalls,','))
 function GetNumQuestChoices() return 3 end
 fire(nil,'QUEST_COMPLETE');assert(#questCalls==2,'a reward choice is left to the player')
 -- Guide links copy their address; script links stay plain text; coloured names open an info card.
 local fixture=T:Evaluate(turnin,1,T.Profile(),T.QuestReader())
 assert(fixture.links[2]=='https://youtu.be/ab--cd' and fixture.links[3]==nil,'only web links are clickable')
 assert(fixture.display[4]:find('|Hnib:FRIENDLY:Marshal McBride|h',1,true) and fixture.display[4]:find('|Hnib:LOOT:Nibbled-On Book|h',1,true),fixture.display[4])
 assert(not fixture.lines[4]:find('|',1,true),'plain lines carry no markup')
 T.reviewing=true;T:Refresh()
 local linkRow;for _,row in ipairs(T.rows) do if row.link then linkRow=row end end
 linkRow.destination.scripts.OnClick(nil,'LeftButton');assert(A.UI.copy:IsShown() and A.UI.copy.box.edit:GetText()=='https://youtu.be/ab--cd')
 T:ShowKeyword('nib:FRIENDLY:Marshal McBride')
 assert(T.infoWindow:IsShown() and T.infoWindow.title:GetText()=='Marshal McBride' and T.infoWindow.kind:GetText()=='Friendly NPC')
 assert(T.infoWindow.info.url=='https://www.wowhead.com/classic/search?q=Marshal%20McBride')
 T.rows[1].destination.scripts.OnClick(nil,'RightButton')
 assert(T.infoWindow.title:GetText()=='A Threat Within' and T.infoWindow.body:GetText():find('in your quest log',1,true),T.infoWindow.body:GetText())
 assert(T.infoWindow.info.url=='https://www.wowhead.com/classic/quest=783')
 -- A quest in the log can be opened in the game's quest log from the card; other subjects do not offer it.
 assert(T.infoWindow.log:IsShown() and T.infoWindow.info.questID==783 and T.infoWindow.info.inLog)
 local selected,shownPanel
 QuestLogFrame=CreateFrame('Frame');QuestLogFrame:Hide()
 function ShowUIPanel(panel) shownPanel=panel;panel:Show() end
 function QuestLog_SetSelection(index) selected=index end
 function QuestLog_Update() end
 C_QuestLog.GetLogIndexForQuestID=function(id) return id==783 and 4 or 0 end
 T.infoWindow.log.scripts.OnClick()
 assert(shownPanel==QuestLogFrame and selected==4 and not T.infoWindow:IsShown(),'the classic quest log opens on the quest')
 QuestLogFrame=nil;QuestLog_SetSelection=nil;openedQuest=nil
 T:ShowQuestInfo(783);T.infoWindow.log.scripts.OnClick();assert(openedQuest==783,'a map-based quest log is used when that is what the client has')
 combat=true;local opened,why=T:OpenQuestLog(783);assert(not opened and why:find('after combat',1,true));combat=false
 active[783]=nil;T:ShowQuestInfo(783);assert(not T.infoWindow.log:IsShown(),'a quest you are not on has no quest log entry to open')
 local refused,reason=T:OpenQuestLog(783);assert(not refused and reason:find('not in your quest log',1,true))
 active[783]=true
 T:ShowKeyword('nib:FRIENDLY:Marshal McBride');assert(not T.infoWindow.log:IsShown())
 T:ShowQuestInfo(783)
 T:ShowKeyword('nib:EVIL:x');assert(T.infoWindow.title:GetText()=='A Threat Within','unknown link kinds are ignored')
 T.infoWindow:Hide();A.UI.copy:Hide()
 active[783]=nil;T.reviewing=false;T.state.selected=previous;T.state.guides[turnin.id]=nil;T.byID[turnin.id]=nil;T:Tick(true)
 assert(A:Snapshot().nibTrail.currentStep==5)
 assert(T.rows[1] and T.rows[1].text:GetText()~='')
 local wide=T.content:GetWidth();T.frame:SetWidth(253);T.frame.scripts.OnSizeChanged();assert(T.content:GetWidth()<wide)
 assert(T.stepTag:GetText():find('Step 5',1,true) and T.preview[2].index==5)
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'RightButton');assert(A.UI.options:IsShown())
 assert(A:Ask('What is my next Nib Trail objective?') and not A.pending)
 assert(A.UI.lastReply.answer:find('A Threat Within',1,true))
 -- Captions must stay inside their buttons, and each button row inside the chat window.
 local function rowWidth(list) local total,count=0,0;for _,b in ipairs(list) do if b:IsShown() then total=total+b:GetWidth();count=count+1 end end;return total+5*math.max(0,count-1),count end
 A.UI:SetReply({answer='x',actions={{type='quest',title='Loot the Ancient Statuette',questID=7},{type='quest',title='Speak with the extremely talkative quartermaster of Northshire Abbey',questID=7},{type='quest',title='Go',questID=7}}})
 local shortAction,longAction=A.UI.actions[1],A.UI.actions[2]
 assert(shortAction:GetWidth()>=#'Loot the Ancient Statuette'*6+24,'a caption that fits must get a button wide enough for it')
 assert(shortAction:GetFontString():GetWidth()<=shortAction:GetWidth(),'the caption is bounded by its button')
 local used,count=rowWidth(A.UI.actions);assert(count==3 and used<=A.UI.chat:GetWidth()-42,'action buttons overflow the chat window: '..used)
 assert(longAction.fullTitle:find('quartermaster',1,true),'a shortened action keeps its full title for the tooltip')
 A.UI.chat:SetWidth(460);A.UI.chat.scripts.OnSizeChanged()
 for _,list in ipairs({A.UI.actions,A.UI.chips,A.UI.footer}) do assert(rowWidth(list)<=460-28,'a button row overflows the narrowest chat window') end
 A.UI.chat:SetWidth(540);A.UI.chat.scripts.OnSizeChanged();A.UI:SetReply({answer=A.UI.lastReply.answer})
 local footerWidth=0;for _,b in ipairs(T.footerButtons) do footerWidth=footerWidth+b:GetWidth() end
 assert(#T.footerButtons==5 and footerWidth<=T.frame:GetWidth()-16,'guide footer buttons overflow the guide window')
 assert(A.UI:GetScale()==1 and A.UI:CycleScale() and A.db.uiScale==1.15)
 combat=true;assert(not A.UI:CycleScale() and A.db.uiScale==1.15,'window size must not change during combat');combat=false
 A.db.uiScale=nil
 local shared=T.Profile();shared.memo={}
 local first=T:Evaluate(g,s.step,shared,T.QuestReader())
 assert(first and T:Evaluate(g,s.step,shared,T.QuestReader())==first,'one tick reuses a step evaluation')
 assert(T:Evaluate(g,s.step,T.Profile(),T.QuestReader())~=first,'a new tick evaluates again')
 A:SetChatMode('automatic');assert(A:Ask('How should I level?'))
 local transportError={schema=1,requestId=A.pending.requestId,capturedAt=A.pending.capturedAt,error='Connect Gemini on the companion page.'}
 assert(NibWhisper_Receive(A.Protocol.EncodePacket('NIBR1',transportError)) and A.pending.manualOnly)
 assert(A.UI.status:GetText()==transportError.error)
 A:CancelPending()
 active[783]=true;T:Tick(true);g,s=T:Current();assert(s.step==7,'quest did not advance: '..s.step)
 assert(removed and removed.from=='NibTrail')
 T:Move(1,true);g,s=T:Current();assert(s.step==8 and s.skipped[1]==7)
 T:Move(-1,false);T:Tick(true);g,s=T:Current();assert(s.step==7 and T.reviewing)
 T:ShowSteps(); T:ShowLibrary(); T:ShowSync()
 local exported=T:ExportProgress();assert(exported:sub(1,6)=='NIBT1:')
 local d=A.Protocol.DecodePacket('NIBT1',exported);d.character='Player-123-0BAD';assert(not T:ImportProgress(A.Protocol.EncodePacket('NIBT1',d)))
 d.character=T:Character();d.state.guides[g.id].step=10;d.state.guides[g.id].at=s.at+10
 assert(T:ImportProgress(A.Protocol.EncodePacket('NIBT1',d)));local _,current=T:Current();assert(current.step==10)
 A.db.opticalEnabled=true; A.Optical={SetPacket=function(_,packet) signal=packet end,ClearPacket=function()signal=nil end}
 assert(T:RequestSync() and signal:sub(1,6)=='NIBS1:')
 local request=A.Protocol.DecodePacket('NIBS1',signal)
 local reply={schema=1,requestId=request.requestId,capturedAt=request.capturedAt,character=request.character,state=request.state}
 reply.requestId='wrong';assert(not T:ImportSync(A.Protocol.EncodePacket('NIBP1',reply)))
 reply.requestId=request.requestId;assert(T:ImportSync(A.Protocol.EncodePacket('NIBP1',reply)));assert(not A.pending)
 -- Display fixes found by scanning every step: a second ">>" is not shown, and an unclosed colour is closed.
 local messy=T.Parse('step\\n>> Clear a path first. >>This fight is hard\\n>> Kill |cRXP_ENEMY_Withered Protectors and loot them')
 assert(messy.entries[1].desc=='Clear a path first. This fight is hard',messy.entries[1].desc)
 local _,opened=messy.entries[2].display:gsub('|c%x%x%x%x%x%x%x%x','');local _,closed=messy.entries[2].display:gsub('|r','')
 assert(opened==1 and closed==1 and messy.entries[2].desc:find(' Withered Protectors and loot them',1,true),messy.entries[2].display)
 assert(T.Matches('Horde/Alliance Paladin !Mage',T.Profile())==true)
 assert(T.Matches('new_unknown_tag',T.Profile())==nil)
 assert(T.Point('1429,42.5,33.25').x==42.5)
 assert(not T.Point('1429/1,-136.48,-8933.47'))
 assert(T.XPReached('2-1000',{level=1,xp=4000,xpMax=5000})==true)

 local function battleShoutRow()
   for _, row in ipairs(T.rows) do if row:IsShown() and row.control and row.control.kind=='train' and row.text:GetText():find('Battle Shout',1,true) then return row end end
 end
 function UnitClass() return 'Warrior','WARRIOR' end
 local learned=false
 C_Spell={IsPlayerSpell=function() return false end}
 C_SpellBook={IsSpellKnown=function(id) return id==6673 and learned end}
 T.reviewing=false; T:Write(g,6); T:Tick(true)
 local row=battleShoutRow();assert(row and row.toggle:IsShown(),'Battle Shout needs a clickable objective')
 row.toggle.scripts.OnClick()
 row=battleShoutRow();assert(row.control.marked and T.state.guides[g.id].marks['6'][1]==row.control.entry)
 local snapshot=A.Protocol.DecodePacket('NIBT1',T:ExportProgress())
 assert(T.ValidateState(snapshot.state).guides[g.id].marks['6'][1]==row.control.entry)
 row.toggle.scripts.OnClick()
 assert(not battleShoutRow().control.marked,'manual check should toggle off')
 local oldPin=T.pin
 A.eventFrame.scripts.OnEvent(nil,'MERCHANT_SHOW')
 A.eventFrame.scripts.OnEvent(nil,'MERCHANT_CLOSED')
 A.eventFrame.scripts.OnUpdate(nil,.3)
 assert(T.state.guides[g.id].step==6,'selling alone must not complete Battle Shout')
 learned=true
 A.eventFrame.scripts.OnEvent(nil,'SPELLS_CHANGED')
 A.eventFrame.scripts.OnUpdate(nil,.3)
 assert(T.state.guides[g.id].step==7,'training should advance the vendor-and-Battle-Shout step')
 assert(T.pin and T.pin~=oldPin and T.currentPoint,'TomTom should update to the new step')
 T:ShowLibrary(); T.library.modeButton.scripts.OnClick()
 assert(T.library.menu:IsShown() and T.library.mode==1,'category button opens a menu without changing filters')

 T:Browse(12)
 assert(T.preview[3].index==13,'the Next preview must show the adjacent step even if it is inactive')
 T.preview[3].scripts.OnClick(T.preview[3]);T:Tick(true)
 assert(T.state.guides[g.id].step==13 and T.reviewing,'Next must stop at exactly one step')
 active[7]=true
 local book=T:Evaluate(g,12,T.Profile(),T.QuestReader())
 local joined=table.concat(book.lines,'\\n')
 assert(joined:find('Collect Nibbled-On Book',1,true) and not joined:find('247834',1,true) and not joined:find('disablecheckbox',1,true),joined)
 for _, control in pairs(book.controls) do assert(control.kind~='use' and control.kind~='complete','book use and the disabled checkbox are instructions') end
 local p=T.Profile()
 local sample={id='prerequisite-fixture',title='Prerequisite fixture',mode='Solo route'}
 T.parsed[sample.id]={steps={T.Parse('step\\n.accept 7 >> Accept Kobold Camp Cleanup')},labels={}}
 active[7]=false;complete[783]=false
 local blocked=T:Evaluate(sample,1,p,T.QuestReader())
 assert(blocked.skip and blocked.blocked[7]:find('A Threat Within',1,true))
 complete[783]=true
 assert(not T:Evaluate(sample,1,p,T.QuestReader()).skip,'completed prerequisite should unblock the step')
 complete[783]=false;active[7]=true
 assert(not T:Evaluate(sample,1,p,T.QuestReader()).skip,'an active quest wins over prerequisite data')
 local unknown=T:Evaluate(sample,1,p,function(kind,id) if id==7 then return false end end)
 assert(not unknown.skip,'unknown history must not skip the step')

 sample.faction='Alliance';sample.conditions={};sample.steps=3
 T.parsed[sample.id].steps[2]=T.Parse('step\\n.accept 783 >> Accept A Threat Within')
 T.parsed[sample.id].steps[3]=T.Parse('step\\n>> Walk back to the abbey')
 T.byID[sample.id]=sample;active[7]=false;active[783]=true
 T.state.selected={id=sample.id};T:Write(sample,1);T.reviewing=false;T.arrivedStep=nil
 T:Advance(p,T.QuestReader())
 assert(T.state.guides[sample.id].step==2 and T.skipNotice.first:find('A Threat Within',1,true),'automatic skip must show the missing prerequisite')
 T:Advance(p,T.QuestReader())
 assert(T.state.guides[sample.id].step==2,'the already complete destination must stay visible')
 `,'@trail-test');
 lua.lua_close(l);
});

test('the assistant retrieves the exact independent starter step and can suggest its chapter',async()=>{
 const data=await loadKnowledge();const g=data.guides.find(g=>g.name==='1-6 Northshire'&&g.group==='RestedXP Forever Guide (A)');
 assert(g&&data.guides.length===282);
 const request={question:'What should I do now?',context:{player:{faction:'Alliance'},quests:{active:[]},nibTrail:{guide:{id:g.id,name:g.name,group:g.group},currentStep:5,steps:[{questIds:[783],elements:[{text:'Accept A Threat Within'}]}]}}};
 const result=retrieveKnowledge(data,request);
 assert.equal(result.excerpts[0].id,`rxp:${g.id}:5`);
 assert.equal(sanitizeActions([{type:'trail',group:g.group,name:g.name}],request,data.guides)[0].type,'trail');
});
