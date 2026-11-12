'use strict';
const $=id=>document.getElementById(id);
let status={}, current=null, sample=false, gameEligible=false, replyPacket='', busy=false, usedRequest=false;
const conversation=[];
const formatCount=value=>new Intl.NumberFormat().format(Number(value)||0);
function text(node,value){node.textContent=String(value??'');}
function encodePacket(kind,value){const bytes=new TextEncoder().encode(JSON.stringify(value));let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));return kind+':'+btoa(binary);}
function decodePacket(raw){const value=raw.trim();if(!value.startsWith('NIBQ1:')||value.length>180000)throw Error('That does not look like a Nib character packet. Copy the complete NIBQ1: text from the game.');const binary=atob(value.slice(6));if(binary.length>131072)throw Error('These notes are too large. Export a fresh packet in-game.');const result=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(binary,c=>c.charCodeAt(0))));if(result.schema!==1||!result.requestId||!result.context||!Number.isFinite(result.capturedAt))throw Error('These character notes are incomplete or from a different version.');return result;}
function escapeGameText(value){return String(value??'').replace(/\|[cC][0-9a-fA-F]{8}/g,'').replace(/\|r/g,'').replace(/\|[Tt][\s\S]*?\|[Tt]/g,'').replace(/\|H[^|]*\|h([^|]*)\|h/g,'$1');}
function addMessage(speaker,body,{error=false,sources=[],actions=[]}={}){
 const item=document.createElement('article');item.className='message '+(speaker==='You'?'user':'nib')+(error?' error':'');
 const label=document.createElement('span');label.className='speaker';text(label,speaker.toUpperCase());
 const bubble=document.createElement('div');bubble.className='bubble';text(bubble,escapeGameText(body));item.append(label,bubble);
 if(sources.length){const list=document.createElement('div');list.className='source-list';for(const [i,source]of sources.entries()){if(!source.url&&/^rxp:[a-f0-9]+:\d+$/.test(source.id)){const chip=document.createElement('span');chip.className='local-source';text(chip,`[${i+1}] ${source.title} · local guide`);list.append(chip);continue;}const link=document.createElement('a');try{const url=new URL(source.url);if(url.protocol!=='https:')continue;link.href=url.href;}catch{continue;}link.target='_blank';link.rel='noopener noreferrer';text(link,`[${i+1}] ${source.title||new URL(source.url).hostname}`);list.append(link);}item.append(list);}
 if(actions.length){const note=document.createElement('div');note.className='action-note';text(note,'Suggested in-game actions: '+actions.map(a=>a.title||a.name||a.type).join(' · ')+'. Nib will wait for your click in the game.');item.append(note);}
 $('messages').append(item);$('messages').scrollTop=$('messages').scrollHeight;return item;
}
function capturedAge(){if(!current)return'';const seconds=Math.max(0,Math.round(Date.now()/1000-current.capturedAt));return seconds<60?'just now':seconds<3600?Math.floor(seconds/60)+' min ago':Math.floor(seconds/3600)+' hr ago';}
function renderContext(){
 const c=current.context,p=c.player||{},q=c.quests||{},r=c.nibTrail||c.restedXP||{},guide=r.guide||{};
 $('emptyCharacter').hidden=true;$('characterDetails').hidden=false;$('sampleBadge').hidden=!sample;
 text($('characterName'),p.name||'Your adventurer');text($('characterClass'),[p.level?`Level ${p.level}`:'',p.race,p.className||p.class,p.faction].filter(Boolean).join(' · '));
 text($('characterLocation'),[p.zone,p.subzone].filter(Boolean).join(' / ')||'Location not reported');
 text($('activeCount'),formatCount(q.active?.length));text($('completedCount'),Array.isArray(q.completedIds)?formatCount(q.completedIds.length):'Unknown');
 text($('guideLabel'),c.nibTrail?'NIB TRAIL':'RESTEDXP ROUTE');text($('guideName'),guide.name||r.guideName||'No active guide reported');text($('guideStep'),r.currentStep?`Step ${r.currentStep}`:'');
 text($('snapshotAge'),(sample?'Sample notes · ':`Captured ${capturedAge()} · `)+'Refresh in-game when your quest state changes.');
 text($('chatSubtitle'),sample?'Previewing sample notes. AI answers still require a connection.':`${p.name||'Your adventurer'} · ${p.zone||'Azeroth'} · notes from ${capturedAge()}`);
 const addons=Array.isArray(c.addons)?c.addons:[];const names=addons.map(a=>typeof a==='string'?a:a.title||a.name).filter(Boolean);
 const professions=(c.professions||[]).map(p=>`${p.name||p.skillName||'Skill'} ${p.rank??p.skillLevel??'?'} / ${p.maxRank??p.maxSkillLevel??'?'}`);
 text($('contextSummary'),`Completed quest coverage: ${q.completionCoverage||'unknown'}. Professions: ${professions.join(', ')||'not reported'}. Loaded addons: ${names.join(', ')||'none reported'}. Client: ${c.client?.version||c.client?.build||'unknown'}. No other players' chat or account secrets.`);
}
function renderButton(){const canAsk=!!current&&!!status.configured&&!!status.ready&&!busy;$('askButton').disabled=!canAsk;$('askButton').textContent=busy?'Nib is checking his maps…':'Ask Nib ↗';}
const geminiModels=[['gemini-3.5-flash-lite','Gemini 3.5 Flash-Lite'],['gemini-3.8-flash','Gemini 3.8 Flash']];
function providerOptions(provider,model){const gemini=provider==='gemini';$('modelSelect').replaceChildren();for(const [id,label]of(gemini?geminiModels:[[status.provider==='openai'?status.model:'gpt-6.1-sol','OpenAI model (edit below)']])){const option=document.createElement('option');option.value=id;text(option,label);$('modelSelect').append(option);}$('modelSelect').value=model||$('modelSelect').options[0]?.value;$('customModel').hidden=gemini;$('customModelLabel').hidden=gemini;if(!gemini)$('customModel').value=model||'gpt-6.1-sol';}
async function checkStatus() {
 try {
  const res = await fetch('/api/status', {cache: 'no-store'});
  if (!res.ok) throw Error('Companion service is unavailable');
  status = await res.json();
  const google = status.provider === 'gemini';
  text($('connectionState'), status.ready ? 'Ready to ask' : status.configured ? 'Starting AI connection…' : 'Connect your AI provider');
  $('connectionState').className = 'connection-status ' + (status.ready ? 'ready' : '');
  text($('connectionDetail'), status.setupMessage || status.providerLabel);
  $('providerSelect').value = status.provider || 'gemini';
  providerOptions(status.provider, status.model);
  text($('knowledgeMode'), status.knowledgeMode);
  $('geminiSetup').hidden = !google;
  $('keyLink').hidden = !google;
  text($('keyInstructions'), google
   ? 'Paste a key from Google AI Studio. Nib checks model access and saves it on this computer.'
   : 'Set OPENAI_API_KEY in companion/.env, then restart the companion.');
  text($('providerTerms'), google ? 'Use a Google project with free-tier quota to avoid API charges.' : 'OpenAI API billing depends on your account.');
  text($('privacyNote'), 'When you ask, Nib sends your question, character notes, and relevant guide excerpts to ' + status.providerLabel + '.');
  $('setupDetails').open = !status.configured;
 } catch (e) {
  status = {};
  text($('connectionState'), 'Companion unavailable');
  $('connectionState').className = 'connection-status error';
  text($('connectionDetail'), e.message);
 }
 renderButton();
}
async function post(url,body){const res=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','X-Nib-Token':status.csrfToken||''},body:JSON.stringify(body)});let value;try{value=await res.json();}catch{throw Error('The companion returned an unreadable response.');}if(!res.ok)throw Error(value.error||`Request failed (${res.status})`);return value;}
function loadPacket(packet,isSample=false){current=typeof packet==='string'?decodePacket(packet):packet;sample=isSample||current.context.sample===true;gameEligible=!sample;usedRequest=false;replyPacket='';$('replyCard').hidden=true;$('packetError').textContent='';text($('question'),current.question||'');$('question').value=current.question||'';renderContext();renderButton();text($('sendHint'),sample?'Sample context — this is not your live character.':'Your character notes are ready. Ask when you are.');}
$('geminiSetup').addEventListener('submit', async event => {
 event.preventDefault();
 const input = $('geminiKey');
 const key = input.value.trim();
 input.value = '';
 $('saveGeminiKey').disabled = true;
 text($('keyResult'), 'Checking Gemini model access…');
 try {
  await post('/api/gemini-key', {key});
  await checkStatus();
  $('setupDetails').open = true;
  text($('keyResult'), 'Gemini connected. In WoW, select AI automatic under Nib Options.');
 } catch (error) { text($('keyResult'), error.message); }
 finally { $('saveGeminiKey').disabled = false; }
});
$('sendPacket').addEventListener('click', () => {
 if (busy) return;
 if (!status.ready) { text($('packetError'), 'Connect your AI provider first.'); return; }
 try {
  loadPacket($('packetInput').value);
  $('askForm').requestSubmit();
 } catch (error) { text($('packetError'), error.message); }
});
$('readPacket').addEventListener('click',()=>{try{loadPacket($('packetInput').value);$('question').focus();}catch(e){text($('packetError'),e.message);}});
$('sampleButton').addEventListener('click',async()=>{try{const res=await fetch('/api/sample');if(!res.ok)throw Error('Sample notes are unavailable.');const data=await res.json();const packet=data.packet||data.request||data;loadPacket(packet,true);$('question').value='What should I consider before choosing my next quest?';}catch(e){text($('packetError'),e.message);}});
document.querySelectorAll('[data-question]').forEach(button=>button.addEventListener('click',()=>{$('question').value=button.dataset.question;$('question').focus();}));
$('askForm').addEventListener('submit',async event=>{
 event.preventDefault();const question=$('question').value.trim();if(!current||!question||busy||!status.ready)return;
 if(usedRequest){current={...current,requestId:'browser-'+crypto.randomUUID(),history:conversation.slice(-8)};gameEligible=false;}
 const packet=encodePacket('NIBQ1',current);addMessage('You',question);busy=true;renderButton();const thinking=addMessage('Nib','Mrrgl… a moment while I untangle my maps.');
 try{const result=await post('/api/ask',{packet,question});thinking.remove();const reply=result.reply||result.response;if(!reply?.answer)throw Error('Nib could not produce a complete answer. Please try again.');
 addMessage('Nib',reply.answer,{sources:reply.sources||result.sources||[],actions:reply.actions||[]});conversation.push({role:'user',text:question},{role:'assistant',text:reply.answer});while(conversation.length>12)conversation.shift();replyPacket=result.packet||encodePacket('NIBR1',reply);$('replyPacket').value=replyPacket;$('replyCard').hidden=false;text($('copyStatus'),!gameEligible?'Sample or browser-only reply. To display a reply in-game, start with a fresh question from the addon.':'Ready for your latest in-game question.');$('copyReply').disabled=!gameEligible;usedRequest=true;$('question').value='';text($('sendHint'),'Ask another question here, or send fresh notes from the game.');
 }catch(e){thinking.remove();addMessage('Nib',e.message,{error:true});}finally{busy=false;renderButton();}
});
$('copyReply').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(replyPacket);text($('copyStatus'),'Copied. Return to Nib in-game and choose Paste reply.');}catch{$('replyPacket').closest('details').open=true;$('replyPacket').focus();$('replyPacket').select();text($('copyStatus'),'Press Ctrl+C to copy the selected reply.');}});
$('clearChat').addEventListener('click',async()=>{if(busy)return;try{await post('/api/clear',{});}catch{}conversation.length=0;if(current)current={...current,history:[]};$('messages').replaceChildren();addMessage('Nib','Fresh parchment! I still have your linked character notes, but our tavern tales are cleared.');replyPacket='';$('replyCard').hidden=true;});
$('refreshStatus').addEventListener('click',checkStatus);
$('providerSelect').addEventListener('change',()=>providerOptions($('providerSelect').value));
$('saveProvider').addEventListener('click',async()=>{if(busy)return;const provider=$('providerSelect').value,model=provider==='gemini'?$('modelSelect').value:$('customModel').value.trim();$('saveProvider').disabled=true;try{await post('/api/settings',{provider,model});text($('providerResult'),'Selection saved. Add the selected provider key locally if needed.');await checkStatus();}catch(e){text($('providerResult'),e.message);}finally{$('saveProvider').disabled=false;}});
$('question').addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();$('askForm').requestSubmit();}});
setInterval(()=>{if(current)renderContext();},30000);
checkStatus();
