from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]

def client(player, other, cls, othercls):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="'+cls+'";CAST_IDS={}')
    lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
    lua.globals().SELF=player;lua.globals().OTHER=other
    lua.globals().SELFCLASS=cls;lua.globals().OTHERCLASS=othercls
    lua.execute('''
      GROUPED=true;DUNGEON=true;RAID=false;OUT={};TESTCD={};HIDDEN=false
      function IsInGroup() return GROUPED end
      function IsInRaid() return RAID end
      function GetNumGroupMembers() return 2 end
      function IsInInstance() return true,DUNGEON and "party" or "none" end
      function UnitExists(u) return u=="player" or u=="party1" end
      function UnitFullName(u) return u=="player" and SELF or OTHER,"TestRealm" end
      function UnitClass(u) local c=u=="player" and SELFCLASS or OTHERCLASS;return c,c end
      C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,
        SendAddonMessage=function(prefix,msg,channel) OUT[#OUT+1]={prefix,msg,channel} end}
      local cd=C_Spell.GetSpellCooldown
      C_Spell.GetSpellCooldown=function(id)
        if HIDDEN then MODE.secret=true;local r=cd(id);MODE.secret=false;return r end
        return TESTCD[id] or cd(id)
      end
      local function anchor(unit)
        local f=CreateFrame("Frame");f.unit=unit;f:Show()
        f.IsVisible=function(self) return self._shown==true end
        return f
      end
      CompactPartyFrameMember1=anchor("player");CompactPartyFrameMember2=anchor("party1")
      C_UnitAuras.GetUnitAuraInstanceIDs=function() return {} end
      C_UnitAuras.GetAuraDataByAuraInstanceID=function() return nil end
      C_UnitAuras.GetAuraDuration=function() return {} end
    ''')
    for name in ('DBagsAlerts.lua','PartyCooldowns.lua','PartyDefensives.lua'):
        chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts'/name).read_text(encoding='utf-8-sig'))
        lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
    lua.execute('DBagsAlertsDB=DBagsAlertsDB or {};DBagsAlertsDB.partyDefensives={enabled=true,placeholders=true};FIRE("PLAYER_LOGIN");FIRE("PLAYER_ENTERING_WORLD");TICK();TICK()')
    return lua

def deliver(source, target, sender):
    packets=source.globals().OUT
    for i in range(1,len(packets)+1):
        packet=packets[i]
        target.globals().DBagsAlertsState.partyCooldowns.receive(packet[1],packet[2],packet[3],sender+'-TestRealm')
    source.execute('OUT={}')

tank=client('Tank','Healer','WARRIOR','PRIEST')
healer=client('Healer','Tank','PRIEST','WARRIOR')
deliver(tank,healer,'Tank')
healer.execute('''
 local entries=DBagsAlertsState.partyCooldowns.get("party1")
 assert(#entries>=3 and entries[1].status=="R","healer did not receive ready tank defensives")
 local row=DBagsAlertsState.partyDefensives.rows.party1
 assert(row:IsShown() and row.icons[1].label._text=="RDY","ready icon missing on healer party frame")
''')
tank.execute('''
 DBagsAlertsDB.partyDefensives.enabled=false -- sender shares with its own display off
 TESTCD[22]={isActive=true,isOnGCD=false,startTime=GetTime(),duration=240}
 ADVANCE(1);TICK();TICK()
''')
deliver(tank,healer,'Tank')
healer.execute('''
 local e=DBagsAlertsState.partyCooldowns.get("party1")[1]
 assert(e.status=="C" and e.remaining>230,"real cooldown not synchronized")
 assert(DBagsAlertsState.partyDefensives.rows.party1.icons[1].label._text=="","cooldown still labeled ready")
''')
# Native active buffs merge into the matching synchronized slot.
healer.execute('''
 C_UnitAuras.GetUnitAuraInstanceIDs=function() return {880} end
 C_UnitAuras.GetAuraDataByAuraInstanceID=function() return {auraInstanceID=880,spellId=22,name="Shield Wall",icon=122} end
 DBagsAlertsState.partyDefensives.update()
 local row=DBagsAlertsState.partyDefensives.rows.party1
 assert(row.icons[1].label._text=="UP" and row.icons[1].auraID==880,"active buff did not replace cooldown slot")
 assert(not row.icons[4]:IsShown(),"active defensive duplicated")
 C_UnitAuras.GetUnitAuraInstanceIDs=function() return {} end
''')
# Never serialize hidden values or carry a previous ready state through restrictions.
tank.execute('MODE.combat=true;HIDDEN=true;ADVANCE(1);TICK();TICK()')
deliver(tank,healer,'Tank')
healer.execute('''
 local entries=DBagsAlertsState.partyCooldowns.get("party1")
 assert(entries[1].status=="C","public cooldown observation lost in combat")
 assert(entries[2].status=="R","confirmed unused ready defensive disappeared in combat")
''')
tank.execute('FIRE("UNIT_SPELLCAST_SUCCEEDED","player",nil,23);ADVANCE(1);TICK();TICK()')
deliver(tank,healer,'Tank')
healer.execute('''
  local used=DBagsAlertsState.partyCooldowns.get("party1")[2]
 assert(used.status=="C" and used.estimated and used.remaining>100,"restricted own cast failed to synchronize a labeled estimate")
 MODE.combat=true
 C_UnitAuras.GetAuraDataByIndex=function() error("aura read blocked") end
 DBagsAlertsState.partyDefensives.update()
 assert(DBagsAlertsState.partyDefensives.rows.party1:IsShown(),"combat aura failure hid cooldown row")
 C_UnitAuras.GetAuraDataByIndex=nil
 for msg in pairs(ERRORS) do if msg:find("aura read blocked",1,true) then ERRORS[msg]=nil end end
''')
# Validate sender, protocol ordering, stale reports and scope.
healer.execute('''
 local s=DBagsAlertsState.partyCooldowns
 local peer=s.peers["tank-testrealm"];local seq=peer.seq
 s.receive(s.prefix,"S:999:999:22,R,0,0","PARTY","Stranger-TestRealm")
 assert(s.peers["tank-testrealm"].seq==seq,"accepted non-party sender")
 s.receive(s.prefix,"S:"..peer.epoch..":"..(seq-1)..":22,R,0,0","PARTY","Tank-TestRealm")
 assert(s.peers["tank-testrealm"].seq==seq,"accepted out-of-order snapshot")
 s.receive(s.prefix,"S:999:999:22,C,999999999,999999999","PARTY","Tank-TestRealm")
 assert(s.peers["tank-testrealm"].seq==seq,"accepted unbounded timer")
 ADVANCE(16)
 assert(s.get("party1")[1].status~="R" or s.get("party1")[1].estimated,"stale data displayed confirmed ready")
 DUNGEON=false;OUT={};ADVANCE(1);TICK();TICK()
 assert(#OUT==0 and next(s.peers)==nil,"scanned/sent outside five-player dungeon")
 DUNGEON=true;ADVANCE(1);TICK();TICK()
 assert(s.get("party1")[1].placeholder and s.get("party1")[1].status=="U","unobserved class spell guessed ready")
 DBagsAlertsState.partyDefensives.update()
 assert(DBagsAlertsState.partyDefensives.rows.party1:IsShown(),"class placeholders missing without peer addon")
''')
# Heartbeat is bounded, and disabling the existing party setting stops it.
tank.execute('''
 HIDDEN=false;OUT={}
 for i=1,100 do ADVANCE(0.05);TICK() end
 assert(#OUT<=11,"message flood")
 DBagsAlertsDB.partyDefensives.enabled=false;DBagsAlertsDB.partyDefensives.share=false;OUT={};ADVANCE(1);TICK();TICK()
 assert(#OUT==0,"disabled module still sends")
 for msg in pairs(ERRORS) do error(msg) end
''')
healer.execute('for msg in pairs(ERRORS) do error(msg) end')
print('Two clients: ready/cooldown/restricted/stale, healer UI, validation, throttling and dungeon scope PASS')
