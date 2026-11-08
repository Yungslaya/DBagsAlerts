-- Observe public party casts without requiring other installs. Optional public self-reports improve accuracy.
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local function data(t) return type(t)=="table" and not secret(t) and not (issecrettable and issecrettable(t)) end
-- Forever baselines from Icy Veins spell database (2026-11-07).
-- {name, base spell ID, earliest level, base cooldown seconds, talent/racial note}
-- Talent-dependent cooldowns remain estimates; never label them confirmed ready.
local profiles = {
 WARRIOR={{"Shield Wall",871,28,900},{"Last Stand",12975,20,180,"Talent"},
  {"Retaliation",20230,20,900},{"Shield Block",2565,16,5}},
 PALADIN={{"Divine Protection",498,6,300},{"Divine Shield",642,34,300},
  {"Blessing of Protection",1022,10,300},{"Templar's Bulwark",1311015,40,300,"Talent"}},
 DRUID={{"Barkskin",22812,44,60},{"Frenzied Regeneration",22842,36,180},
  {"Tranquility",740,30,300},{"Nature's Swiftness",17116,30,180,"Talent"}},
 WARLOCK={{"Death Coil",6789,42,120},{"Shadow Ward",6229,32,30}},
 HUNTER={{"Deterrence",19263,20,300,"Talent"},{"Feign Death",5384,30,30}},
 PRIEST={{"Fade",586,8,30},{"Desperate Prayer",13908,10,600,"Dwarf racial"}},
 SHAMAN={{"Nature's Swiftness",16188,30,180,"Talent"}},
 MAGE={{"Ice Block",11958,30,300,"Talent"},{"Ice Barrier",11426,40,30,"Talent"}},
 ROGUE={{"Evasion",5277,8,300},{"Vanish",1856,22,300}},
}
local lists={}
for class, spells in pairs(profiles) do
 lists[class]={};for _,spell in ipairs(spells) do lists[class][#lists[class]+1]=spell[1] end
end
local state={peers={},own={},confirmed={},used={},observed={},prefix="DBACD2",legacyPrefix="DBACD1",stats={casts=0,restricted=0,auras=0,sent=0,received=0}}
DBagsAlertsState.partyCooldowns=state
local function scope()
 local c=DBagsAlertsDB and DBagsAlertsDB.partyDefensives
 if not c then
  DBagsAlertsDB=DBagsAlertsDB or {};DBagsAlertsDB.partyDefensives={};c=DBagsAlertsDB.partyDefensives
 end
 if c.share==nil then c.share=true end
 if not c.enabled and not c.share then return false end
 if not IsInGroup() or IsInRaid() then return false end
 local n=plain(GetNumGroupMembers()); local inside,kind=IsInInstance()
 return n and n>=2 and n<=5 and plain(inside)==true and plain(kind)=="party"
end
local function canonical(s) return not secret(s) and type(s)=="string" and s:lower():gsub("%s","") or nil end
local function identity(unit)
 local name,realm
 if UnitFullName then name,realm=UnitFullName(unit) else name=UnitName(unit) end
 name,realm=plain(name),plain(realm)
 if type(name)~="string" then return end
 if type(realm)~="string" or realm=="" then realm=GetNormalizedRealmName and GetNormalizedRealmName() end
 return canonical(name .. (type(realm)=="string" and realm~="" and ("-"..realm) or "")),canonical(name)
end
local function profileFor(unit)
 local _,class=UnitClass(unit);return profiles[plain(class)] or {}
end
local function observe(unit,castID)
 if not scope() then return end
 if secret(castID) then state.stats.restricted=state.stats.restricted+1;return end
 if type(castID)~="number" or secret(unit) or type(unit)~="string" then return end
 if unit~="player" and not unit:match("^party[1-4]$") then return end
 if plain(UnitExists(unit))~=true then return end
 local key=identity(unit);if not key then return end
 local name=plain(C_Spell.GetSpellName(castID))
 for _,profile in ipairs(profileFor(unit)) do
  if castID==profile[2] or (name and name==profile[1]) then
   state.stats.casts=state.stats.casts+1
   state.observed[key]=state.observed[key] or {}
   state.observed[key][profile[1]]={id=castID,at=GetTime(),duration=profile[4]}
   if DBagsAlertsDebug then DBagsAlertsDebug.note("Observed "..unit.." "..profile[1]) end
   if DBagsAlertsState.partyDefensives then DBagsAlertsState.partyDefensives.update() end
   return
  end
 end
end
local function observeAura(unit,aura)
 if not scope() or not data(aura) then return end
 local id,name,expires,length=plain(aura.spellId),plain(aura.name),plain(aura.expirationTime),plain(aura.duration)
 local key=identity(unit);if not key then return end
 for _,profile in ipairs(profileFor(unit)) do
  if (type(id)=="number" and id==profile[2]) or (type(name)=="string" and name==profile[1]) then
   local token=plain(aura.auraInstanceID)
   state.auraSeen=state.auraSeen or {};state.auraSeen[key]=state.auraSeen[key] or {}
   local marker=type(expires)=="number" and expires>0 and expires or token
   if marker and state.auraSeen[key][profile[1]]==marker then return end
   state.observed[key]=state.observed[key] or {}
   local old=state.observed[key][profile[1]]
   local at=GetTime()
   if type(expires)=="number" and type(length)=="number" and length>0 then at=math.min(at,expires-length) end
   -- No public timestamp: record first sighting once, never restart every scan.
   if not marker and old then return end
   state.auraSeen[key][profile[1]]=marker
   if not old or at>old.at+0.5 then
    state.observed[key][profile[1]]={id=type(id)=="number" and id or profile[2],at=at,duration=profile[4],source="aura"}
    state.stats.auras=state.stats.auras+1
   end
   return
  end
 end
end
state.observeAura=observeAura
state.observe=observe
local function observedEntries(unit)
 local result={};local key=identity(unit);local history=key and state.observed[key] or {}
 local level=plain(UnitLevel(unit))
 for _,profile in ipairs(profileFor(unit)) do
  local seen=history and history[profile[1]]
  local raceAllowed=true
  if profile[5]=="Dwarf racial" then
   local race;if UnitRace then local _,token=UnitRace(unit);race=plain(token) end;raceAllowed=race=="Dwarf"
  end
  local c=DBagsAlertsDB and DBagsAlertsDB.partyDefensives
  if seen or (not (c and c.placeholders==false) and type(level)=="number" and level>=profile[3] and raceAllowed) then
   local remaining=seen and math.max(0,seen.at+seen.duration-GetTime())
   result[#result+1]={id=seen and seen.id or profile[2],name=profile[1],
    status=seen and (remaining>0 and "C" or "R") or "U",remaining=remaining,
    duration=seen and seen.duration or profile[4],at=GetTime(),estimated=seen~=nil,
    placeholder=not seen,castAt=seen and seen.at,reason=seen and "Estimated from an observed cast and the Forever base cooldown. Talents, resets and missed casts can change readiness."
     or "Class ability placeholder. Not observed yet; training or talent is not confirmed."}
  end
 end
 return result
end
local function senderUnit(sender)
 sender=canonical(sender); if not sender then return end
 -- Forever names can be rendered with a space or a hyphen between their parts.
 -- Match complete normalized names only, and reject any ambiguous short name.
 local compact=sender:gsub("%-","")
 local found,foundKey
 for i=0,4 do
  local unit=i==0 and "player" or ("party"..i)
  if plain(UnitExists(unit)) then
   local full,short=identity(unit)
   local display=UnitName and canonical(UnitName(unit))
   local matches=sender==full or sender==short or sender==display
      or (full and compact==full:gsub("%-",""))
      or (short and compact==short:gsub("%-",""))
      or (display and compact==display:gsub("%-",""))
   if matches then
    if found and found~=unit then return end
    found,foundKey=unit,full
   end
  end
 end
 return found,foundKey
end
state.summary=function()
 local peers=0;for _,peer in pairs(state.peers) do if GetTime()-peer.at<=15 then peers=peers+1 end end
 return string.format("CD sync v2: %d peers; %d known; %d sent / %d received; %d casts / %d buffs; %d restricted casts",
  peers,#(state.known or {}),state.stats.sent,state.stats.received,state.stats.casts,state.stats.auras,state.stats.restricted)
  .."; send result="..tostring(state.lastSendResult or "not attempted")
  .."; failures="..tostring(state.sendFailures or 0)
  .."; prefix="..tostring(state.prefixResult or "not registered")
  .."; outgoing restricted="..tostring(state.outgoingRestricted)
  .."; incoming="..tostring(state.incoming or 0).."; unmatched sender="..tostring(state.unmatchedSender or 0)
  ..(state.lastReceiveIssue and ("; "..state.lastReceiveIssue) or "")
end
local function rebuild()
 local _,class=UnitClass("player"); class=plain(class)
 local wanted={}; for _,name in ipairs(lists[class] or {}) do wanted[name]=true end
 local known={}; local api=C_SpellBook
 if api and api.GetNumSpellBookSkillLines and api.GetSpellBookSkillLineInfo and api.GetSpellBookItemInfo then
  local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  for line=1,api.GetNumSpellBookSkillLines() do
   local info=api.GetSpellBookSkillLineInfo(line)
   if data(info) then
    for slot=info.itemIndexOffset+1,info.itemIndexOffset+info.numSpellBookItems do
     local item=api.GetSpellBookItemInfo(slot,bank)
     if data(item) then
      local name,id=plain(item.name),plain(item.spellID)
      if type(name)~="string" and type(id)=="number" then name=plain(C_Spell.GetSpellName(id)) end
      local kinds=Enum and Enum.SpellBookItemType
      local future=kinds and kinds.FutureSpell and plain(item.itemType)==kinds.FutureSpell
      if not future and type(name)=="string" and wanted[name] and type(id)=="number" and plain(item.isOffSpec)~=true then known[name]=id end
     end
    end
   end
  end
 end
 state.known={}
 for _,name in ipairs(lists[class] or {}) do
  if known[name] then state.known[#state.known+1]={id=known[name],name=name} end
 end
end
local function sample()
 local out={};local now=GetTime()
 for _,known in ipairs(state.known or {}) do
  local entry={id=known.id,name=known.name,status="U",at=now}
  local ok,cd=pcall(C_Spell.GetSpellCooldown,known.id)
  if ok and data(cd) then
   local start,duration,rate=plain(cd.startTime),plain(cd.duration),plain(cd.modRate) or 1
   local onGCD,active=plain(cd.isOnGCD),plain(cd.isActive)
   if onGCD==true or active==false then entry.status="R"
   elseif type(start)=="number" and type(duration)=="number" and type(rate)=="number" and rate>0 then
    local remaining=math.max(0,(start+duration-now)/rate)
    if duration==0 or remaining==0 then entry.status="R"
    elseif remaining<=86400 and duration/rate<=86400 then entry.status="C";entry.remaining=remaining;entry.duration=duration/rate end
   end
  end
  -- Retain public cooldown observations across combat restrictions. A readable
  -- own-cast event invalidates readiness immediately; expiry never guesses ready.
  if state.used[known.id] and now-state.used[known.id]<0.5 then entry.status="U" end
  if entry.status~="U" then
   state.confirmed[known.id]={status=entry.status,remaining=entry.remaining,duration=entry.duration,at=now,estimated=entry.estimated}
  else
   local previous=state.confirmed[known.id]
   if previous then
    if previous.status=="R" then entry.status="R";entry.estimated=previous.estimated
    elseif previous.status=="C" then
     local remaining=math.max(0,previous.remaining-(now-previous.at))
     if remaining>0 then entry.status="C";entry.remaining=remaining;entry.duration=previous.duration;entry.estimated=previous.estimated end
    end
   end
  end
  if entry.status=="U" then
   local key=identity("player");local seen=key and state.observed[key] and state.observed[key][known.name]
   if seen then
    entry.remaining=math.max(0,seen.at+seen.duration-now);entry.duration=seen.duration
    entry.status=entry.remaining>0 and "C" or "R";entry.estimated=true
    entry.reason="Estimated from this player's own cast; live timing is restricted."
   end
  end
  out[#out+1]=entry
 end
 state.own=out
 return out
end
local function payload(entries)
 local out={}
 for _,e in ipairs(entries) do
  out[#out+1]=string.format("%d,%s,%d,%d",e.id,e.estimated and (e.status=="C" and "E" or e.status=="R" and "T" or "U") or e.status,math.ceil((e.remaining or 0)*10),math.ceil((e.duration or 0)*10))
 end
 return table.concat(out,";")
end
local function channel()
 return IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
end
local session=tostring(math.floor(GetTime()*1000));local sequence=0
local function transmit(message)
 local c=DBagsAlertsDB and DBagsAlertsDB.partyDefensives
 if not c or c.share==false then return end
 if C_ChatInfo and C_ChatInfo.SendAddonMessage then
  if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
   local ok,restricted=pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
   state.outgoingRestricted=ok and plain(restricted) or nil
   if state.outgoingRestricted==true then state.lastSendResult="Restricted by game";return end
  end
  local ok,result=pcall(C_ChatInfo.SendAddonMessage,state.prefix,message,channel())
  state.lastSendResult=ok and (plain(result) or "no result") or "send failed"
  local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
  if ok and (result==nil or (not secret(result) and (result==true or result==success or result==0))) then
   state.stats.sent=state.stats.sent+1
  else state.sendFailures=(state.sendFailures or 0)+1 end
 end
end
local function readMessage(prefix,message,distribution,sender)
 if prefix~=state.prefix and prefix~=state.legacyPrefix then return end
 state.incoming=(state.incoming or 0)+1
 if not scope() then state.lastReceiveIssue="Report arrived outside tracker scope";return end
 if distribution~="PARTY" and distribution~="INSTANCE_CHAT" then state.lastReceiveIssue="Unsupported report channel";return end
 if secret(message) or type(message)~="string" or #message>250 then return end
 local unit,key=senderUnit(sender)
 if not unit then state.unmatchedSender=(state.unmatchedSender or 0)+1;state.lastReceiveIssue="Sender name did not uniquely match a party member";return end
 if unit=="player" then return end
 if message=="Q" then state.force=true;return end
 local epoch,seq,body=message:match("^S:(%d+):(%d+):(.*)$")
 seq=tonumber(seq);if not epoch or not seq then return end
 local old=state.peers[key]
 if old and old.epoch==epoch and seq<=old.seq then return end
 local entries={};local seen={};local _,class=UnitClass(unit);class=plain(class)
 local allowed={};for _,name in ipairs(lists[class] or {}) do allowed[name]=true end
 for record in body:gmatch("[^;]+") do
  local id,status,remaining,duration=record:match("^(%d+),([RCUET]),(%d+),(%d+)$")
  id,remaining,duration=tonumber(id),tonumber(remaining),tonumber(duration)
  if not id or id<1 or id>10000000 or not remaining or remaining>864000 or duration>864000 or remaining>duration+1 or seen[id] or #entries>=6 then return end
  local name=plain(C_Spell.GetSpellName(id))
  -- Base defensive IDs can be validated without a cached remote spell name.
  if type(name)~="string" then
   for _,profile in ipairs(profiles[class] or {}) do if id==profile[2] then name=profile[1];break end end
  end
  if type(name)~="string" or not allowed[name] then state.lastReceiveIssue="Unknown defensive spell ID "..id;return end
  local estimated=status=="E" or status=="T"
  entries[#entries+1]={id=id,name=name,status=status=="E" and "C" or status=="T" and "R" or status,
   remaining=remaining/10,duration=duration/10,at=GetTime(),estimated=estimated};seen[id]=true
 end
 state.stats.received=state.stats.received+1
 state.peers[key]={epoch=epoch,seq=seq,at=GetTime(),entries=entries}
 if DBagsAlertsState.partyDefensives then DBagsAlertsState.partyDefensives.update() end
end
state.receive=readMessage
state.get=function(unit)
 local entries,at
 if unit=="player" then entries=state.own;at=GetTime()
 else local key=identity(unit);local peer=key and state.peers[key];entries=peer and peer.entries;at=peer and peer.at end
 if not entries or (at and GetTime()-at>15) then return observedEntries(unit) end
 local observations={}
 for _,e in ipairs(observedEntries(unit)) do observations[e.name]=e end
 local result={}
 for _,e in ipairs(entries) do
  local copy={id=e.id,name=e.name,status=e.status,duration=e.duration,remaining=e.remaining,at=e.at,estimated=e.estimated,source="peer"}
  if GetTime()-at>15 then copy.status="U";copy.reason="Cooldown report expired."
  elseif copy.status=="C" then
   copy.remaining=math.max(0,e.remaining-(GetTime()-e.at))
   if copy.remaining<=0 then copy.status=e.estimated and "R" or "U";copy.reason="Waiting for live readiness confirmation." end
  end
  local observation=observations[e.name]
  if observation and not observation.placeholder and
   (copy.status=="U" or (copy.status=="R" and observation.castAt and observation.castAt>=(e.at or 0))) then copy=observation end
  result[#result+1]=copy;observations[e.name]=nil
 end
 for _,e in pairs(observations) do if not e.placeholder then result[#result+1]=e end end
 return result
end
local elapsed,lastSend,lastBody=0,-100,nil
local frame=CreateFrame("Frame");state.driver=frame
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","SPELLS_CHANGED","PLAYER_REGEN_ENABLED","SPELL_UPDATE_COOLDOWN","UNIT_SPELLCAST_SUCCEEDED","CHAT_MSG_ADDON"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,...)
 if event=="CHAT_MSG_ADDON" then readMessage(...);return end
 if event=="UNIT_SPELLCAST_SUCCEEDED" then
  local unit,_,castID=...;observe(unit,castID)
  if unit~="player" then return end
  -- A readable successful own cast confirms the actual trained spell/rank even
  -- when the spellbook snapshot was incomplete at login or after learning it.
  if type(castID)=="number" and not secret(castID) then
   local castName=plain(C_Spell.GetSpellName(castID))
   for _,profile in ipairs(profileFor("player")) do
    if castID==profile[2] or castName==profile[1] then
     state.known=state.known or {};local exists=false
     for _,entry in ipairs(state.known) do if entry.name==profile[1] then entry.id=castID;exists=true;break end end
     if not exists then state.known[#state.known+1]={id=castID,name=profile[1]} end
     break
    end
   end
  end
  if secret(castID) then
   state.confirmed={}
  elseif type(castID)=="number" then
   local name=plain(C_Spell.GetSpellName(castID))
   for _,known in ipairs(state.known or {}) do
    if castID==known.id or (name and name==known.name) then
     state.confirmed[known.id]=nil;state.used[known.id]=GetTime()
    end
   end
  end
 end
 if event=="PLAYER_LOGIN" then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
   state.prefixResult=plain(C_ChatInfo.RegisterAddonMessagePrefix(state.prefix))
   C_ChatInfo.RegisterAddonMessagePrefix(state.legacyPrefix)
  end
 end
 if event=="PLAYER_LOGIN" or event=="SPELLS_CHANGED" or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" then
  state.rebuild=true;state.rebuildAt=event=="SPELLS_CHANGED" and GetTime()+0.5 or 0
 end
 if event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then
  state.peers={};state.request=true
  local present={}
  for i=0,4 do
   local unit=i==0 and "player" or ("party"..i)
   if plain(UnitExists(unit)) then local key=identity(unit);if key then present[key]=true end end
  end
  for key in pairs(state.observed) do if not present[key] then state.observed[key]=nil end end
 end
 state.force=true
end)
frame:SetScript("OnUpdate",function(_,dt)
 elapsed=elapsed+dt;if elapsed<0.25 then return end;elapsed=0
 if not scope() then
  state.peers={};state.own={};state.observed={};state.auraSeen={};state.wasActive=false;return
 end
 if not state.wasActive then state.wasActive=true;state.request=true;state.rebuild=true;state.rebuildAt=0;state.force=true end
 -- Stance changes fire SPELLS_CHANGED during combat. Keep the last readable
 -- spellbook rather than replacing the shared list with a restricted/empty scan.
 if state.rebuild and not InCombatLockdown() and GetTime()>=(state.rebuildAt or 0) then rebuild();state.rebuild=false end
 local now=GetTime();local body=payload(sample())
 if now-lastSend<0.5 then return end
 if state.request then transmit("Q");state.request=false end
 if state.force or body~=lastBody or now-lastSend>=3 then
  sequence=sequence+1;transmit("S:"..session..":"..sequence..":"..body)
  lastSend,lastBody,state.force=now,body,false
 end
end)

if DBagsAlertsDebug then
 for _,script in ipairs({"OnEvent","OnUpdate"}) do
  local callback=frame:GetScript(script)
  if callback then frame:SetScript(script,DBagsAlertsDebug.guard("Party cooldowns "..script,callback)) end
 end
end
