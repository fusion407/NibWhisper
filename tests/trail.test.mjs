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
const guide=['NibWhisper_Guide/TrailData.lua','NibWhisper_Guide/QuestLinks.lua','NibWhisper_Guide/Trail.lua','NibWhisper_Guide/TrailSync.lua'];
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
 assert(T.library:IsShown() and T.library.menu:IsShown() and not T:Current(),'first login offers route categories without selecting a chapter')
 T.library:Hide()
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
 T.frame.close.scripts.OnClick();assert(not T.frame:IsShown())
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
 -- Nib's reply sound plays when an answer arrives, from guide chat or the AI, and not for errors or when switched off.
 local sounds={}
 function PlaySoundFile(file,channel) sounds[#sounds+1]=file..'|'..channel end
 assert(A:Ask('What quests am I on?') and A.UI.lastReply.answer:find('Kobold Camp Cleanup',1,true))
 assert(#sounds==1 and sounds[1]=='Interface\\\\AddOns\\\\NibWhisper_Assistant\\\\Sounds\\\\murloc.mp3|Master',sounds[1])
 local P=A.Protocol
 local function answer(extra) local r={schema=1,requestId='sound-1',capturedAt=1794333600};for k,v in pairs(extra) do r[k]=v end;return P.EncodePacket('NIBR1',r) end
 A.pending={requestId='sound-1',capturedAt=1794333600}
 assert(A:ImportReply(answer({error='Gemini is busy right now.'}),true) and #sounds==1,'an error is silent')
 assert(A:ImportReply(answer({answer='Mrrgl! North it is.',mood='happy',intent='advice',sources=P.Array(),actions=P.Array()})) and #sounds==2,'an AI answer plays it')
 assert(not A:Ask('') and #sounds==2,'a question that was refused is silent')
 A.UI:RefreshOptions();assert(A.UI.options.replySound:GetText()=='Reply sound: on')
 A.UI.options.replySound.scripts.OnClick();assert(A.db.replySound==false and A.UI.options.replySound:GetText()=='Reply sound: off' and #sounds==2)
 assert(A:Ask('What quests am I on?') and #sounds==2,'the Options switch silences it')
 A.UI.options.replySound.scripts.OnClick();assert(A.db.replySound==true and #sounds==3,'switching it back on previews the sound')
 A.db.replySound=nil
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
 assert(A.UI.mascot:IsShown(),'Nib is visible by default')
 A.UI.mascot.close.scripts.OnClick()
 assert(not A.UI.mascot:IsShown() and A.db.mascotPreference and A.db.mascotVisible==false,'closing Nib saves the visibility preference')
 A.UI:ShowChat(); assert(A.UI.chat.strata=='HIGH' and T.frame.strata=='MEDIUM')
 A.UI.guideButton.scripts.OnClick(); assert(A.UI.chat:IsShown() and T.frame.strata=='HIGH' and A.UI.chat.strata=='MEDIUM')
 T.frame:Hide()
 function IsShiftKeyDown() return true end
 A.UI.chat:Hide()
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'LeftButton'); assert(not T.frame:IsShown() and A.UI.chat:IsShown())
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'RightButton'); assert(T.frame:IsShown() and not A.UI.options)
 function IsShiftKeyDown() return false end
 T.frame:Hide()
 A.UI.minimap.scripts.OnClick(A.UI.minimap,'LeftButton'); assert(T.frame:IsShown() and A.UI.frontWindow==T.frame)
 A.eventFrame.scripts.OnEvent(nil,'PLAYER_DEAD'); T.frame:Hide(); T:Tick(true); assert(T.frame:IsShown())
 T.frame.close.scripts.OnClick(); T:Tick(true); assert(not T.frame:IsShown(),'closing the guide manually must survive the death transition')
 T:Open()
 assert(not T:Current(),'opening Trail should not select a chapter before sync')
 local suggested=T:Suggested(T.Profile(),'Solo route'); assert(suggested and T:Select(suggested)); T:Tick(true)
 local originalRace,originalClass=UnitRace,UnitClass
 assert(not T:Suggested(T.Profile(),'Mage AoE'),'Paladins cannot get a Mage route recommendation')
 function UnitClass() return 'Mage','MAGE' end
 local humanMage=T:Suggested(T.Profile(),'Mage AoE')
 assert(humanMage and humanMage.title:find('Elwynn',1,true))
 function UnitRace() return 'Gnome','Gnome' end
 local gnomeMage=T:Suggested(T.Profile(),'Mage AoE')
 assert(gnomeMage and gnomeMage.title:find('Dun Morogh',1,true))
 assert(T:Suggested(T.Profile(),'Solo route').title:find('Coldridge',1,true))
 local profileStep={id='race-class-fixture'}
 T.parsed[profileStep.id]={steps={T.Parse([[step
+Gnome Mage instruction << Gnome Mage
+Human Mage instruction << Human Mage
+Non-Mage instruction << !Mage]])}}
 local function instructions() return table.concat(T:Evaluate(profileStep,1,T.Profile(),T.QuestReader()).lines,' ') end
 assert(instructions()=='Gnome Mage instruction')
 UnitRace=originalRace
 assert(instructions()=='Human Mage instruction')
 UnitClass=originalClass
 assert(instructions()=='Non-Mage instruction')
 local g,s=T:Current(); assert(g.name=='1-6 Northshire',g.name)
 assert(s.step==5,'expected Northshire quest opener, got '..s.step)
 assert(waypoint and waypoint[1]==1429 and math.abs(waypoint[2]-(1136.48/3000))<.001)
 assert(arrow and waypoint[4].persistent==false and waypoint[4].from=='NibTrail')
 local waypointRow
 for _, row in ipairs(T.rows) do if row.point and row.control and row.control.kind=='accept' then waypointRow=row;break end end
 assert(waypointRow and waypointRow.destination:IsShown())
 waypointRow.destination.scripts.OnClick();assert(T.clickedPoint==waypointRow.point or T.clickedPoint.x==waypointRow.point.x)
 T:ShowTargets()
 local tw=T.targetWindow;local first=tw.rows[1]
 assert(first.target.attributes.macrotext=='/targetexact Deputy Willem' and first.target.caption:GetText()=='Deputy Willem')
 -- Skull and cross buttons target the enemy and place the marker.
 assert(first.marks[1].attributes.macrotext=='/targetexact Deputy Willem\\n/tm 8',first.marks[1].attributes.macrotext)
 assert(first.marks[2].attributes.macrotext=='/targetexact Deputy Willem\\n/tm 7')
 assert(first:IsShown() and not tw.rows[2]:IsShown() and not tw.empty:IsShown() and tw.subtitle:GetText():find('Step 5',1,true))
 -- Resizing: the window shows as many names as fit, says how many are hidden, and cannot be resized in combat.
 tw.names={'A1','A2','A3','A4','A5','A6'};tw:SetHeight(180);T:LayoutTargets()
 assert(tw.rows[2]:IsShown() and tw.rows[3]:IsShown() and not tw.rows[4]:IsShown() and tw.more:GetText():find('+3 more',1,true),tw.more:GetText())
 tw:SetHeight(330);T:LayoutTargets();assert(tw.rows[6]:IsShown() and not tw.rows[7]:IsShown() and tw.more:GetText()=='')
 local grip;for _,child in ipairs(tw.children or {}) do grip=child end
 combat=true;tw:SetHeight(150);T:LayoutTargets();assert(tw.rows[6]:IsShown(),'nothing on a window with secure buttons changes during combat');combat=false
 T:ShowTargets();assert(not tw.rows[2]:IsShown(),'reopening lists the step names again')
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
 T:ShowSteps()
 -- The step list: one row per step with its number, its text and where you stand on it.
 local sf=T.stepsFrame;local cur;for _,row in ipairs(sf.rows) do if row.step==7 then cur=row end end
 assert(cur and cur.badge:GetText()=='You are here' and cur.accent:IsShown() and cur.number:GetText()==7,'the current step is marked')
 assert(sf.summary:GetText():find('Step 7 of',1,true) and sf.range:GetText():find('Steps 4',1,true),sf.range:GetText())
 for _,row in ipairs(sf.rows) do
   if row.step and row.step<7 then assert(row.badge:GetText()=='Done' or row.badge:GetText()=='Skipped' or row.badge:GetText()=='Not for you',row.badge:GetText()) end
   if row.step and row.step>7 then assert(row.badge:GetText()=='' or row.badge:GetText()=='Not for you' or row.badge:GetText()=='Skipped') end
   assert(not (row.caption:GetText() or ''):find('^%[',1),'no bracket tags in the list')
 end
 sf.scripts.OnMouseWheel(sf,-1);assert(sf.from==7,'the wheel moves three steps')
 sf.scripts.OnMouseWheel(sf,1);sf.scripts.OnMouseWheel(sf,1);sf.scripts.OnMouseWheel(sf,1);assert(sf.from==1)
 T:ShowLibrary(); T:ShowSync()
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
 assert(opened==1 and closed==1 and messy.entries[2].desc=='Kill Withered Protectors and loot them',messy.entries[2].display)
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
 assert(T.state.guides[sample.id].step==3 and T.skipNotice.first:find('A Threat Within',1,true),'the blocked step is skipped with its reason, and the step that was already done does not hold the guide up')
 T:Advance(p,T.QuestReader())
 assert(T.state.guides[sample.id].step==3,'a step with something left to do is where the guide stops')

 -- Progress the quest log does not report: manual steps tick themselves from what the player does.
 local auto={id='auto-fixture',title='Auto fixture',mode='Solo route',faction='Alliance',conditions={},steps=9,next={}}
 local function fixture(...) local steps={};for i,body in ipairs({...}) do steps[i]=T.Parse(body) end;T.parsed[auto.id]={steps=steps,labels={}} end
 fixture('step\\n.fly Stormwind >> Fly to Stormwind','step\\n.hs >> Hearth to Goldshire','step\\n.home >> Set your Hearthstone to Goldshire',
  'step\\n.fp Sentinel Hill >> Get the Sentinel Hill flight path','step\\n.abandon 783 >> Abandon A Threat Within','step\\n.cast 2575 >> Cast the spell',
  'step\\n.deathskip >> Die and respawn','step\\n.gossipoption 95406 >> Talk to the robot to start the escort','step\\n>> Rest here')
 T.byID[auto.id]=auto;T.state.selected={id=auto.id};T:Write(auto,1);T.reviewing=false;T:Open()
 local function at() return T.state.guides[auto.id].step end
 local fire=A.eventFrame.scripts.OnEvent
 local flying=false;function UnitOnTaxi() return flying end
 T:Tick(true);assert(at()==1)
 flying=true;T:Tick(true);T:Tick(true);assert(at()==2,'taking the flight finishes the fly step: '..at());flying=false
 fire(nil,'UNIT_SPELLCAST_SUCCEEDED','target','cast',8690);T:Tick(true);assert(at()==2,'someone else hearthing is ignored')
 fire(nil,'UNIT_SPELLCAST_SUCCEEDED','player','cast',8690);T:Tick(true);assert(at()==3,'hearthing finishes the hearth step')
 fire(nil,'HEARTHSTONE_BOUND');T:Tick(true);assert(at()==4,'binding finishes the set-home step')
 ERR_NEWTAXIPATH='New flight path discovered!'
 fire(nil,'UI_INFO_MESSAGE',1,'Some other message');T:Tick(true);assert(at()==4)
 fire(nil,'UI_INFO_MESSAGE',1,ERR_NEWTAXIPATH);T:Tick(true);assert(at()==5,'discovering the flight path finishes that step')
 active[783]=true;T:Tick(true);assert(at()==5,'the quest is still in the log')
 active[783]=nil;T:Tick(true);assert(at()==6,'abandoning the quest finishes the abandon step')
 fire(nil,'UNIT_SPELLCAST_SUCCEEDED','player','cast',133);T:Tick(true);assert(at()==6,'a different spell does not count')
 fire(nil,'UNIT_SPELLCAST_SUCCEEDED','player','cast',2575);T:Tick(true);assert(at()==7,'casting the named spell finishes the cast step')
 fire(nil,'PLAYER_UNGHOST');T:Tick(true);assert(at()==8,'coming back to life finishes the die-and-respawn step')
 assert(T:AutoMark({gossipoption=true})==1);T:Tick(true);assert(at()==9,'choosing the dialogue option finishes the talk-to-start step')

 -- Browsing pauses the guide only until the game moves on.
 fixture('step\\n.accept 7 >> Accept Kobold Camp Cleanup','step\\n.turnin 7 >> Turn in Kobold Camp Cleanup','step\\n>> Rest here')
 auto.steps=3;active[7]=true;complete[7]=false;T.state.guides[auto.id].marks=nil;T:Write(auto,2);T.reviewing=false;T:Tick(true);assert(at()==2,'ticks from the earlier steps are cleared for the new fixture')
 T:Browse(1);T:Tick(true);assert(at()==1 and T.reviewing,'looking back at a finished step stays put')
 fire(nil,'QUEST_TURNED_IN',7);complete[7]=true;active[7]=false;T:Tick(true)
 assert(not T.reviewing and at()==3,'handing in a quest resumes the guide: '..at())
 complete[7]=false;active[7]=false;complete[783]=true;A.observedTurnIns[7]=nil;T:Write(auto,1);T.reviewing=false;T:Tick(true);assert(at()==1,'a fresh start for the second browsing case')
 T:Browse(2);T:Tick(true);assert(at()==2 and T.reviewing)
 T:Browse(1);T:Tick(true);assert(at()==1 and T.reviewing,'an unfinished step being browsed stays put')
 active[7]=true;T:Tick(true);assert(not T.reviewing and at()==2,'finishing the browsed step resumes the guide: '..at())

 -- A step that was skipped and later finished is done, not skipped.
 fixture('step\\n.accept 7 >> Accept Kobold Camp Cleanup','step\\n>> Walk east','step\\n>> Rest here')
 auto.steps=3;active[7]=false;complete[7]=false;complete[783]=true;A.observedTurnIns[7]=nil;T.state.guides[auto.id].marks=nil
 T:Write(auto,1,{});T.reviewing=false;T:Tick(true);assert(at()==1)
 T:Move(1,true);assert(at()==2 and T.state.guides[auto.id].skipped[1]==1,'the quest step is skipped')
 T:ShowSteps();local listed;for _,row in ipairs(T.stepsFrame.rows) do if row.step==1 then listed=row end end
 assert(listed.badge:GetText()=='Skipped' and T.stepsFrame.summary:GetText():find('1 skipped',1,true),T.stepsFrame.summary:GetText())
 active[7]=true;T:Tick(true)
 assert(#T.state.guides[auto.id].skipped==0 and at()==2,'finishing it clears the skipped mark: '..#T.state.guides[auto.id].skipped)
 T:ListSteps();assert(listed.badge:GetText()=='Done' and T.stepsFrame.summary:GetText():find('0 skipped',1,true),listed.badge:GetText())
 T.stepsFrame:Hide();active[7]=false
 -- The real 21-23 Ashenvale/Stonetalon dungeon route, steps 19 to 21: hearth, return to Astranaar, hand in at Raene.
 local ashen
 for _,chapter in ipairs(T.data.chapters) do if chapter.title=='21-23 Ashenvale/Stonetalon' and chapter.mode=='Dungeon route' then ashen=chapter end end
 assert(ashen,'the chapter exists')
 local readyQuests={}
 local realReady=C_QuestLog.ReadyForTurnIn
 C_QuestLog.ReadyForTurnIn=function(id) return readyQuests[id]==true end
 active[1023]=true;readyQuests[1023]=true;complete[991]=true
 local pr=T.Profile()
 local hearth=T:Evaluate(ashen,19,pr,T.QuestReader())
 assert(not hearth.skip and table.concat(hearth.lines,'|'):find('Hearth to Astranaar',1,true),'without Wailing Caverns quests the hearth step applies: '..tostring(hearth.skipReason))
 assert(T:DoingDungeon('WC',T.QuestReader())==false,'no Wailing Caverns quests: not running it')
 C_Map.GetAreaInfo=function(id) return id==415 and 'Astranaar' or nil end
 local raene=T:Evaluate(ashen,21,pr,T.QuestReader())
 assert(not raene.skip,'a quest ready to hand in keeps the step even away from Astranaar: '..tostring(raene.skipReason))
 local raeneText=table.concat(raene.lines,'|')
 assert(raeneText:find('Raene',1,true) and not raeneText:find('unavailable',1,true),'the quest handed in by the same step counts as its prerequisite: '..raeneText)
 readyQuests[1023]=nil
 assert(T:Evaluate(ashen,21,pr,T.QuestReader()).skip,'with nothing to hand in, the route\\'s area rule still applies away from Astranaar')
 -- Holding any quest the route ties to Wailing Caverns means you are running it, and the way around it is skipped.
 local wcIds={};for _,chapter in ipairs(T.data.chapters) do for _,body in ipairs(T.data.bodies[chapter.id]) do
   if body:find('%.dungeon WC') then for id in body:gmatch('%.accept (%d+)') do wcIds[#wcIds+1]=tonumber(id) end end
 end end
 assert(#wcIds>0);active[wcIds[1]]=true
 local pr2=T.Profile()
 assert(T:Evaluate(ashen,19,pr2,T.QuestReader()).skip,'with a Wailing Caverns quest the hearth is skipped')
 active[wcIds[1]]=nil;active[1023]=nil;complete[991]=nil
 C_QuestLog.ReadyForTurnIn=realReady;C_Map.GetAreaInfo=nil
 -- The step list has a checkbox on each row: skip the current step, skip past the next one, or go back.
 fixture('step\\n>> Walk north','step\\n>> Walk east','step\\n>> Walk south','step\\n>> Walk west','step\\n>> Rest here')
 auto.steps=5;T.state.guides[auto.id].marks=nil;T:Write(auto,2);T.reviewing=false;T:Tick(true)
 assert(at()==2 and T.preview[1].box:IsShown() and T.preview[2].box:IsShown() and T.preview[3].box:IsShown())
 T.preview[2].box.scripts.OnClick();assert(at()==3 and T.state.guides[auto.id].skipped[1]==2,'ticking the current step skips it')
 T.preview[3].box.scripts.OnClick();assert(at()==5,'ticking the next step skips past it: '..at())
 T.preview[1].box.scripts.OnClick();assert(at()==4 and T.reviewing,'the step before goes back')
 T:Write(auto,1);T.reviewing=false;T:Tick(true);assert(not T.preview[1].box:IsShown(),'no checkbox where there is no step')
 -- A "travel to" instruction written on the waypoint finishes when the player gets there.
 fixture('step\\n.goto 1429,42.00,60.00,100 >> Travel to the old mill\\n.subzoneskip 449','step\\n>> Rest here')
 auto.steps=2;T.state.guides[auto.id].marks=nil;T:Write(auto,1);T.reviewing=false
 local where=0.80
 local realPosition=C_Map.GetPlayerMapPosition
 C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .42,where end} end
 T:Tick(true)
 local travel=T:Evaluate(auto,1,T.Profile(),T.QuestReader())
 assert(at()==1 and travel.checks==1 and not travel.complete and travel.lines[1]=='[ ] Travel to the old mill',travel.lines[1])
 T:Browse(2);T:Browse(1);T:Tick(true);assert(at()==1 and T.reviewing,'still on the way, and being browsed')
 where=0.61;T:Tick(true);assert(at()==2 and not T.reviewing,'arriving finishes the travel step, even while browsing: '..at())
 -- The same step is passed over when the player is already in the named area.
 T:Write(auto,1);where=0.95;T.reviewing=false
 C_Map.GetAreaInfo=function(id) return id==449 and 'Goldshire' or nil end
 T:Tick(true);assert(at()==2,'a numbered subzone is matched by its name: '..at())
 C_Map.GetAreaInfo=function() return 'Somewhere Else' end
 T:Write(auto,1);T:Tick(true);assert(at()==1,'a different area does not skip it')
 C_Map.GetAreaInfo=nil;C_Map.GetPlayerMapPosition=realPosition
 -- A step that tracks one part of a quest also shows where the whole quest stands.
 fixture('step\\n.complete 2098,3 >> Loot the Bottom of the Key','step\\n>> Rest here')
 auto.steps=2;active[2098]=true;T.state.guides[auto.id].marks=nil;T:Write(auto,1)
 local realObjectives=C_QuestLog.GetQuestObjectives
 C_QuestLog.GetQuestObjectives=function(id) if id==2098 then return {{text='Top of the Key: 0/1',numFulfilled=0,numRequired=1,finished=false},{text='Middle of the Key: 1/1',numFulfilled=1,numRequired=1,finished=true},{text='Bottom of the Key: 0/1',numFulfilled=0,numRequired=1,finished=false}} end return realObjectives(id) end
 local parts=T:Evaluate(auto,1,T.Profile(),T.QuestReader())
 assert(table.concat(parts.lines,'|'):find('so far: Top of the Key: 0/1, Middle of the Key: 1/1, Bottom of the Key: 0/1',1,true),table.concat(parts.lines,'|'))
 assert(not parts.complete)
 C_QuestLog.GetQuestObjectives=realObjectives;active[2098]=nil
 T.byID[auto.id]=nil;T.state.guides[auto.id]=nil;T.state.selected={id=sample.id}
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
