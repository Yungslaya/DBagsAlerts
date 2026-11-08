from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
for cls in ("WARRIOR","PALADIN","DRUID","WARLOCK","PRIEST","SHAMAN","MAGE","ROGUE","HUNTER"):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="'+cls+'"; CAST_IDS={}')
    lua.execute((root/"Tests/harness.lua").read_text(encoding="utf-8"))
    lua.execute("""
      GROUPED=true;RAID=false;DUNGEON=true;MEMBERS=3;AURA_READS=0
      function IsInGroup() return GROUPED end
      function IsInRaid() return RAID end
      function GetNumGroupMembers() return MEMBERS end
      function IsInInstance() return true,DUNGEON and "party" or "none" end
      function UnitExists(u) return u=="player" or u=="party1" or u=="party2" end
      local function frame(unit)
          local f=CreateFrame("Frame");f.unit=unit;f:Show()
          f.IsVisible=function(self) return self._shown==true end
          return f
      end
      CompactPartyFrameMember1=frame("party2")
      CompactPartyFrameMember2=frame("player")
      CompactPartyFrameMember3=frame("party1")
      DEFENSIVES={player={101},party1={201,202},party2={}}
      C_UnitAuras.GetUnitAuraInstanceIDs=function(unit,filter,maxCount)
          assert(filter=="HELPFUL|BIG_DEFENSIVE" and maxCount==3,"wrong native filter")
          AURA_READS=AURA_READS+1;return DEFENSIVES[unit] or {}
      end
      C_UnitAuras.GetAuraDataByAuraInstanceID=function(unit,id)
          return {icon=UnitPower(),duration=UnitPower(),expirationTime=UnitPower(),spellId=UnitPower()}
      end
      C_UnitAuras.GetAuraDuration=function(unit,id) return {unit=unit,id=id} end
    """)
    for file in ("DBagsAlerts.lua","PartyDefensives.lua"):
        chunk=lua.eval("function(s) return assert(loadstring(s)) end")((root/"DBagsAlerts"/file).read_text(encoding="utf-8"))
        lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
    lua.execute("""
      FIRE("PLAYER_LOGIN")
      local s=DBagsAlertsState.partyDefensives
      s.update()
      assert(s.rows.player.anchor==CompactPartyFrameMember2,"sorted player frame mismatch")
      assert(s.rows.party1.anchor==CompactPartyFrameMember3,"sorted party frame mismatch")
      assert(s.rows.player:IsShown() and s.rows.party1:IsShown(),"active defensives hidden")
      assert(not s.rows.party2:IsShown(),"empty slots shown")
      assert(s.rows.party1.icons[1].auraID==201 and s.rows.party1.icons[2].auraID==202,"wrong defensive IDs")
      assert(s.rows.party1.icons[1].cd._cdobj==true,"missing native duration")
      MODE.secret=true;s.update()
      assert(s.rows.party1:IsShown(),"hidden aura fields blocked display")
      MODE.secret=false
      DEFENSIVES.party1={};s.update();assert(not s.rows.party1:IsShown(),"expired defensive stayed visible")
      DEFENSIVES.party1={203};s.update()
      DBagsAlertsDB.partyDefensives.left=true;DBagsAlertsDB.partyDefensives.size=40;s.update()
      assert(s.rows.party1.left and s.rows.party1.icons[1]._w==40,"side/size controls")
      CompactPartyFrameMember3:Hide();s.update();assert(not s.rows.party1:IsShown(),"hidden frame kept overlay")
      CompactPartyFrameMember3:Show()
      for _,mode in ipairs({"raid","outdoors","solo","six","disabled"}) do
          RAID=mode=="raid";DUNGEON=mode~="outdoors";GROUPED=mode~="solo"
          MEMBERS=mode=="six" and 6 or 3;DBagsAlertsDB.partyDefensives.enabled=mode~="disabled"
          local before=AURA_READS;s.update()
          assert(AURA_READS==before,"scanned outside eligible dungeon")
          for _,row in pairs(s.rows) do assert(not row:IsShown(),"overlay outside eligible dungeon") end
      end
      DBagsAlertsState.openPartyDefensives()
      for msg in pairs(ERRORS) do error(msg) end
    """)
    print(cls,"party defensives: sorted frames, native durations, hidden data, cleanup, scope and settings PASS")
