from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
cases={
 'WARRIOR':('Shield Wall',871,900), 'PALADIN':('Divine Protection',498,300),
 'DRUID':('Barkskin',22812,60), 'WARLOCK':('Death Coil',6789,120),
 'HUNTER':('Deterrence',19263,300), 'PRIEST':('Fade',586,30),
 'SHAMAN':("Nature's Swiftness",16188,180), 'MAGE':('Ice Block',11958,300),
 'ROGUE':('Evasion',5277,300),
}
for cls,(name,spell_id,duration) in cases.items():
 lua=lua51.LuaRuntime(unpack_returned_tuples=True)
 lua.execute('MODE_CLASS="WARRIOR";CAST_IDS={}')
 lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
 lua.globals().BUDDYCLASS=cls;lua.globals().CDNAME=name;lua.globals().CDID=spell_id;lua.globals().BASECD=duration
 lua.execute('''
  GROUPED=true;DUNGEON=true;RAID=false;BUDDY="Buddy";LEVEL=60
  C_ChatInfo=nil -- The other player sends no messages and needs no addon.
  function IsInGroup() return GROUPED end
  function IsInRaid() return RAID end
  function GetNumGroupMembers() return 2 end
  function IsInInstance() return true,DUNGEON and "party" or "none" end
  function UnitExists(unit) return unit=="player" or unit=="party1" end
  function UnitFullName(unit) return unit=="player" and "Tank" or BUDDY,"Realm" end
  function UnitClass(unit) local c=unit=="player" and "WARRIOR" or BUDDYCLASS;return c,c end
  function UnitRace(unit) return "Dwarf","Dwarf" end
  function UnitLevel(unit) return LEVEL end
  local getName=C_Spell.GetSpellName
  C_Spell.GetSpellName=function(id) if id==CDID or id==999999 then return CDNAME end return getName(id) end
  local function anchor(unit)
   local f=CreateFrame("Frame");f.unit=unit;f:Show()
   f.IsVisible=function(self) return self._shown==true end;return f
  end
  CompactPartyFrameMember1=anchor("player");CompactPartyFrameMember2=anchor("party1")
  C_UnitAuras.GetUnitAuraInstanceIDs=function() return {} end
  C_UnitAuras.GetAuraDataByAuraInstanceID=function() return nil end
  C_UnitAuras.GetAuraDuration=function() return {} end
 ''')
 for file in ('DBagsAlerts.lua','PartyCooldowns.lua','PartyDefensives.lua'):
  chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts'/file).read_text(encoding='utf-8-sig'))
  lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
 lua.execute('''
  FIRE("PLAYER_LOGIN");FIRE("PLAYER_ENTERING_WORLD");TICK();TICK()
  local state=DBagsAlertsState.partyCooldowns
  local function find()
   for _,e in ipairs(state.get("party1")) do if e.name==CDNAME then return e end end
  end
  assert(find() and find().placeholder and find().status=="U","class placeholder missing or falsely ready")
  MODE.combat=true;MODE.secret=true
  FIRE("UNIT_SPELLCAST_SUCCEEDED","party1",nil,CDID)
  local e=find();assert(e and not e.placeholder and e.estimated and e.status=="C" and e.remaining==BASECD,"observed cast did not start baseline timer")
  ADVANCE(5)
  assert(find().remaining==BASECD-5,"timer did not continue in combat")
  FIRE("GROUP_ROSTER_UPDATE");TICK();TICK()
  assert(find().status=="C","roster refresh lost observed timer")
  ADVANCE(BASECD)
  assert(find().status=="R" and find().estimated,"expired timer did not become estimated ready")
  FIRE("UNIT_SPELLCAST_SUCCEEDED","party1",nil,999999)
  assert(find().status=="C" and find().remaining==BASECD,"higher-rank cast did not restart timer")
  DBagsAlertsDB.partyDefensives.placeholders=false
  assert(#state.get("party1")==1,"hide placeholders removed tracked spell or kept unobserved spells")
  DBagsAlertsDB.partyDefensives.placeholders=true
  BUDDY="Replacement";FIRE("GROUP_ROSTER_UPDATE")
  assert(find().placeholder,"replacement party member inherited previous cooldown")
  LEVEL=1;assert(#state.get("party1")==0,"below-level placeholders shown")
  LEVEL=60;DUNGEON=false;ADVANCE(1);TICK();TICK()
  assert(next(state.observed)==nil,"kept scanning outside dungeon")
  FIRE("UNIT_SPELLCAST_SUCCEEDED","party1",nil,CDID)
  assert(next(state.observed)==nil,"tracked cast outside dungeon")
  for msg in pairs(ERRORS) do error(msg) end
 ''')
 print(cls,'no-addon class placeholders, observed cast/rank, combat, expiry, roster and scope PASS')
