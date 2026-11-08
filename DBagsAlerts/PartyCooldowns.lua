-- Party members report only their own public cooldown data. No guessed talent timers.
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local function data(t) return type(t)=="table" and not secret(t) and not (issecrettable and issecrettable(t)) end
local lists = {
 WARRIOR={"Shield Wall","Last Stand","Retaliation","Shield Block"},
 PALADIN={"Templar's Bulwark","Divine Protection","Divine Shield","Lay on Hands","Blessing of Protection"},
 DRUID={"Barkskin","Frenzied Regeneration","Survival Instincts","Tranquility","Nature's Swiftness"},
 WARLOCK={"Death Coil","Shadow Ward","Sacrifice"},
 HUNTER={"Deterrence","Feign Death"},
 PRIEST={"Pain Suppression","Guardian Spirit","Desperate Prayer","Power Word: Barrier"},
 SHAMAN={"Nature's Swiftness","Shamanistic Rage","Astral Shift","Mana Tide Totem"},
 MAGE={"Ice Block","Ice Barrier","Mana Shield"},
 ROGUE={"Evasion","Cloak of Shadows","Vanish"},
}
local state={peers={},own={},prefix="DBACD1"}
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
 if not entries then return {{id=0,name="DBagsAlerts sync",status="U",reason="No cooldown report. This player needs the current DBagsAlerts."}} end
 local result={}
 for _,e in ipairs(entries) do
  local copy={id=e.id,name=e.name,status=e.status,duration=e.duration,remaining=e.remaining,at=e.at}
  if GetTime()-at>15 then copy.status="U";copy.reason="Cooldown report expired."
  elseif copy.status=="C" then
   copy.remaining=math.max(0,e.remaining-(GetTime()-e.at))
   if copy.remaining<=0 then copy.status="U";copy.reason="Waiting for readiness confirmation." end
  end
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
  local unit=...;if unit~="player" then return end
 end
 if event=="PLAYER_LOGIN" then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(state.prefix) end
 end
 if event=="PLAYER_LOGIN" or event=="SPELLS_CHANGED" or event=="PLAYER_ENTERING_WORLD" then
  state.rebuild=true;state.rebuildAt=event=="SPELLS_CHANGED" and GetTime()+0.5 or 0
 end
 if event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then state.peers={};state.request=true end
 state.force=true
end)
frame:SetScript("OnUpdate",function(_,dt)
 elapsed=elapsed+dt;if elapsed<0.25 then return end;elapsed=0
 if not scope() then
  state.peers={};state.own={};state.wasActive=false;return
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
