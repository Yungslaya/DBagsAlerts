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
local state={peers={},own={},confirmed={},used={},observed={},prefix="DBACD1"}
DBagsAlertsState.partyCooldowns=state
local function scope()
 local c=DBagsAlertsDB and DBagsAlertsDB.partyDefensives
 if c and c.enabled==false then return false end
 if not IsInGroup() or IsInRaid() then return false end
 local n=plain(GetNumGroupMembers()); local inside,kind=IsInInstance()
 return n and n>=2 and n<=5 and plain(inside)==true and plain(kind)=="party"
end
local function canonical(s) return type(s)=="string" and s:lower():gsub("%s","") or nil end
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
 if not scope() or secret(castID) or type(castID)~="number" or type(unit)~="string" then return end
 if unit~="player" and not unit:match("^party[1-4]$") then return end
 if plain(UnitExists(unit))~=true then return end
 local key=identity(unit);if not key then return end
 local name=plain(C_Spell.GetSpellName(castID))
 for _,profile in ipairs(profileFor(unit)) do
  if castID==profile[2] or (name and name==profile[1]) then
   state.observed[key]=state.observed[key] or {}
   state.observed[key][profile[1]]={id=castID,at=GetTime(),duration=profile[4]}
   if DBagsAlertsDebug then DBagsAlertsDebug.note("Observed "..unit.." "..profile[1]) end
   if DBagsAlertsState.partyDefensives then DBagsAlertsState.partyDefensives.update() end
   return
  end
 end
end
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
 local found
 for i=0,4 do
  local unit=i==0 and "player" or ("party"..i)
  if plain(UnitExists(unit)) then
   local full,short=identity(unit)
   if sender==full then return unit,full end
   if sender==short then if found then return end; found=unit end
  end
 end
 if found then return found,identity(found) end
end
local function rebuild()
 local _,class=UnitClass("player"); class=plain(class)
 local wanted={}; for _,name in ipairs(lists[class] or {}) do wanted[name]=true end
 local known={}; local api=C_SpellBook
 if api and api.GetNumSpellBookSkillLines and api.GetSpellBookItemInfo then
  local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  for line=1,api.GetNumSpellBookSkillLines() do
   local info=api.GetSpellBookSkillLineInfo(line)
   if data(info) then
    for slot=info.itemIndexOffset+1,info.itemIndexOffset+info.numSpellBookItems do
     local item=api.GetSpellBookItemInfo(slot,bank)
     if data(item) then
      local name,id=plain(item.name),plain(item.spellID)
      if type(name)=="string" and wanted[name] and type(id)=="number" then known[name]=id end
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
   state.confirmed[known.id]={status=entry.status,remaining=entry.remaining,duration=entry.duration,at=now}
  else
   local previous=state.confirmed[known.id]
   if previous then
    if previous.status=="R" then entry.status="R"
    elseif previous.status=="C" then
     local remaining=math.max(0,previous.remaining-(now-previous.at))
     if remaining>0 then entry.status="C";entry.remaining=remaining;entry.duration=previous.duration end
    end
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
  out[#out+1]=string.format("%d,%s,%d,%d",e.id,e.status,math.ceil((e.remaining or 0)*10),math.ceil((e.duration or 0)*10))
 end
 return table.concat(out,";")
end
local function channel()
 return IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
end
local session=tostring(math.floor(GetTime()*1000));local sequence=0
local function transmit(message)
 if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(state.prefix,message,channel()) end
end
local function readMessage(prefix,message,distribution,sender)
 if prefix~=state.prefix or not scope() or (distribution~="PARTY" and distribution~="INSTANCE_CHAT") then return end
 if secret(message) or type(message)~="string" or #message>250 then return end
 local unit,key=senderUnit(sender)
 if not unit or unit=="player" then return end
 if message=="Q" then state.force=true;return end
 local epoch,seq,body=message:match("^S:(%d+):(%d+):(.*)$")
 seq=tonumber(seq);if not epoch or not seq then return end
 local old=state.peers[key]
 if old and old.epoch==epoch and seq<=old.seq then return end
 local entries={};local seen={};local _,class=UnitClass(unit);class=plain(class)
 local allowed={};for _,name in ipairs(lists[class] or {}) do allowed[name]=true end
 for record in body:gmatch("[^;]+") do
  local id,status,remaining,duration=record:match("^(%d+),([RCU]),(%d+),(%d+)$")
  id,remaining,duration=tonumber(id),tonumber(remaining),tonumber(duration)
  if not id or id<1 or id>10000000 or not remaining or remaining>864000 or duration>864000 or remaining>duration+1 or seen[id] or #entries>=6 then return end
  local name=plain(C_Spell.GetSpellName(id))
  if type(name)~="string" or not allowed[name] then return end
  entries[#entries+1]={id=id,name=name,status=status,remaining=remaining/10,duration=duration/10,at=GetTime()};seen[id]=true
 end
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
  local copy={id=e.id,name=e.name,status=e.status,duration=e.duration,remaining=e.remaining,at=e.at}
  if GetTime()-at>15 then copy.status="U";copy.reason="Cooldown report expired."
  elseif copy.status=="C" then
   copy.remaining=math.max(0,e.remaining-(GetTime()-e.at))
   if copy.remaining<=0 then copy.status="U";copy.reason="Waiting for readiness confirmation." end
  end
  local observation=observations[e.name]
  if observation and not observation.placeholder and
   (copy.status=="U" or (copy.status=="R" and observation.castAt and observation.castAt>=(e.at or 0))) then copy=observation end
  result[#result+1]=copy
 end
 return result
end
local elapsed,lastSend,lastBody=0,-100,nil
local frame=CreateFrame("Frame");state.driver=frame
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","SPELLS_CHANGED","SPELL_UPDATE_COOLDOWN","UNIT_SPELLCAST_SUCCEEDED","CHAT_MSG_ADDON"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,...)
 if event=="CHAT_MSG_ADDON" then readMessage(...);return end
 if event=="UNIT_SPELLCAST_SUCCEEDED" then
  local unit,_,castID=...;observe(unit,castID)
  if unit~="player" then return end
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
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(state.prefix) end
 end
 if event=="PLAYER_LOGIN" or event=="SPELLS_CHANGED" or event=="PLAYER_ENTERING_WORLD" then
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
  state.peers={};state.own={};state.observed={};state.wasActive=false;return
 end
 if not state.wasActive then state.wasActive=true;state.request=true;state.rebuild=true;state.rebuildAt=0;state.force=true end
 if state.rebuild and GetTime()>=(state.rebuildAt or 0) then rebuild();state.rebuild=false end
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
