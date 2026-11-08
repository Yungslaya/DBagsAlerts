from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
for cls in ("WARRIOR","PALADIN","DRUID","WARLOCK"):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="'+cls+'"; CAST_IDS={}')
    lua.execute((root/"Tests/harness.lua").read_text(encoding="utf-8"))
    lua.execute("""
      GROUPED=true; RAID=false; ROLE="TANK"; SPEC_ROLE="TANK"; MANA=20; MAX_MANA=100
      CONNECTED=true; HEALER_DEAD=false; MULTI=false; HIDDEN_MANA=false
      MANUAL=false; FORM=5
      HEALER_POWER=0; MANA_READS=0; NATIVE_READS=0
      local oldPowerType=UnitPowerType
      function UnitPowerType(u)
          if u and (u:find("party") or u:find("raid")) then return HEALER_POWER end
          return oldPowerType(u)
      end
      function IsInGroup() return GROUPED end
      function IsInRaid() return RAID end
      function GetNumGroupMembers() return RAID and 3 or 2 end
      function GetShapeshiftFormID() return FORM end
      function UnitExists(u)
          return u=="player" or u=="target" or u=="party1" or (MULTI and u=="party2")
              or (RAID and (u=="raid1" or u=="raid2" or (MULTI and u=="raid3")))
      end
      function UnitIsUnit(a,b) return a==b or (RAID and a=="raid1" and b=="player") end
      function UnitGroupRolesAssigned(u)
          if u=="player" or u=="raid1" then return ROLE end
          if MANUAL then return "NONE" end
          return "HEALER"
      end
      function UnitName(u)
          if u=="party1" or u=="raid2" then return "Doc","Home" end
          if u=="party2" or u=="raid3" then return "Other","Away" end
          return "Player","Home"
      end
      function UnitIsConnected() return CONNECTED end
      function UnitIsDeadOrGhost(u) return u~="player" and HEALER_DEAD end
      DRINK=false; DRINK_HIDDEN=false; RANGE_INSIDE=true; RANGE_CHECKED=true; RANGE_HIDDEN=false
      function UnitInRange()
          if RANGE_HIDDEN then MODE.secret=true; local v=UnitHealth(); MODE.secret=false; return v,v end
          return RANGE_INSIDE,RANGE_CHECKED
      end
      local oldBoolCurve=C_CurveUtil.EvaluateColorValueFromBoolean
      C_CurveUtil.EvaluateColorValueFromBoolean=function(b,t,f)
          if issecretvalue(b) then return b end
          return b and t or f
      end
      local oldName=C_Spell.GetSpellName
      C_Spell.GetSpellName=function(id) if id==430 then return "Drink" end return oldName(id) end
      local oldAura=C_UnitAuras.GetAuraDataBySpellName
      C_UnitAuras.GetAuraDataBySpellName=function(u,n,filter)
          if n=="Drink" then
              if DRINK_HIDDEN then MODE.secret=true; local v=UnitHealth(); MODE.secret=false; return v end
              if DRINK then return {name="Drink",spellId=430} end
              return nil
          end
          return oldAura(u,n,filter)
      end
      local oldPower=UnitPower
      function UnitPower(u,p)
          if u:find("party") or u:find("raid") then
              MANA_READS=MANA_READS+1
              if HIDDEN_MANA then MODE.secret=true; local v=oldPower(); MODE.secret=false; return v end
              return MANA
          end
          return oldPower(u,p)
      end
      function UnitPowerMax() return MAX_MANA end
      NATIVE_SECRET=false
      function UnitPowerPercent(unit, power, predicted, curve)
          NATIVE_READS=NATIVE_READS+1
          assert(power==0 and curve.p[2][1]==0.3 and curve.p[1][2]==1 and curve.p[2][2]==0,"wrong native mana curve")
          if NATIVE_SECRET then MODE.secret=true; local v=oldPower(); MODE.secret=false; return v end
          return MANA/MAX_MANA < curve.p[2][1] and 1 or 0
      end
      C_SpecializationInfo={GetSpecialization=function() return 1 end,
          GetSpecializationInfo=function() return 1,"Spec","",1,SPEC_ROLE end}
    """)
    for name in ("DBagsAlerts.lua","HealerMana.lua"):
        chunk=lua.eval("function(s) return assert(loadstring(s)) end")((root/"DBagsAlerts"/name).read_text(encoding="utf-8"))
        lua.execute('local chunk=...; chunk("DBagsAlerts",{});',chunk)
        if name=="DBagsAlerts.lua": lua.execute('FIRE("PLAYER_LOGIN")')
    lua.execute("""
      local s=DBagsAlertsState.healerMana
      local function check() ADVANCE(3); s.check() end
      local function visible() return s.frame:IsShown() end
      local function rangeVisible() return s.rangeFrame:IsShown() and s.rangeFrame._alpha~=0 and s.rangeGate._alpha~=0 end
      check()
      if MODE_CLASS=="WARLOCK" then assert(not visible(),"non-tank class warned"); return end
      assert(visible() and s.unit=="party1","low healer not detected")
      assert(s.frame.title._text=="LOW MANA","warning wording")
      assert(s.frame.detail._text=="Doc-Home  20%","wrong healer details")
      for _,formPower in ipairs({3,1}) do
          HEALER_POWER=formPower;MANA=0;HIDDEN_MANA=true
          local reads,native=MANA_READS,NATIVE_READS
          check();assert(not visible(),"Cat energy/Bear rage caused LOW MANA")
          assert(reads==MANA_READS and native==NATIVE_READS,"non-mana form queried mana threshold")
          RANGE_INSIDE=false;check();assert(rangeVisible(),"form suppressed healer range")
          DRINK=true;check();assert(visible() and s.frame.title._text=="DRINKING","form suppressed Drink aura")
          DRINK=false;RANGE_INSIDE=true
      end
      HEALER_POWER=0;HIDDEN_MANA=false;MANA=20;check()
      assert(visible() and s.frame.title._text=="LOW MANA","caster mana warning did not return")
      MANA=80;DRINK=true;check()
      assert(visible() and s.frame.title._text=="DRINKING","drinking at high mana not shown")
      RANGE_INSIDE=false;check()
      assert(visible() and s.frame.title._text=="DRINKING" and rangeVisible(),"drinking and range must show together")
      DBagsAlertsState.setHealerRangeProofs({{0,1},{1,0}})
      assert(#s.rangeProofVariants>=2,"suppression variants not created")
      assert(s.rangeProofVariants[1].gates[1]._alpha==0 and s.rangeProofVariants[2].gates[2]._alpha==0,"suppression gates not applied")
      DBagsAlertsState.setHealerRangeProofs({})
      assert(visible() and s.frame.title._text=="DRINKING","WAKE UP hid drinking reminder")
      DBagsAlertsState.setHealerRangeProofs(nil)
      assert(not s.rangeProofVariants[1].gates[1]:IsShown(),"suppression not reset")
      DRINK=false;check();assert(not visible() and rangeVisible(),"independent out-of-range warning")
      HIDDEN_MANA=true;check();assert(s.frame._alpha==0 and rangeVisible(),"range inherited high-mana alpha")
      HIDDEN_MANA=false
      RANGE_CHECKED=false;check();assert(not rangeVisible(),"unchecked range guessed")
      RANGE_CHECKED=true;RANGE_HIDDEN=true;check()
      assert(s.rangeFrame._alpha=="secret" and s.rangeGate._alpha=="secret","hidden range flags not handed to native display")
      RANGE_HIDDEN=false;RANGE_INSIDE=true;DRINK_HIDDEN=true;check();assert(not visible(),"hidden drink guessed")
      DRINK_HIDDEN=false;DRINK=true;DBagsAlertsDB.healerMana.drinking=false;check()
      assert(not visible(),"drinking toggle ignored")
      DRINK=false;RANGE_INSIDE=false;DBagsAlertsDB.healerMana.range=false;check()
      assert(not visible() and not rangeVisible(),"range toggle ignored")
      RANGE_INSIDE=true;DBagsAlertsDB.healerMana.drinking=true;DBagsAlertsDB.healerMana.range=true
      MANA=20;check();assert(visible(),"mana cue did not return")
      MANA=32;check();assert(visible(),"missing recovery margin")
      MANA=35;check();assert(not visible(),"recovered warning")
      MANA=30;check();assert(not visible(),"threshold boundary")
      MANA=29;check();assert(visible(),"low threshold")
      MODE.combat=true;check();assert(not visible() and not s.rangeFrame:IsShown(),"combat warning")
      MODE.combat=false;check();assert(visible(),"post-combat warning")
      HIDDEN_MANA=true;check();assert(visible() and s.frame._alpha==1,"hidden low mana not displayed")
      MANA=80;check();assert(s.frame._alpha==0,"hidden high mana warned")
      NATIVE_SECRET=true;check();assert(s.frame._alpha=="secret","secret threshold not passed to display")
      NATIVE_SECRET=false;MANA=20;DRINK=true;check()
      assert(s.frame._alpha==1 and s.frame.title._text=="DRINKING","drinking suppressed by mana gate")
      DRINK=false
      HIDDEN_MANA=false;CONNECTED=false;check();assert(not visible(),"offline healer warned")
      CONNECTED=true;HEALER_DEAD=true;check();assert(not visible(),"dead healer warned")
      HEALER_DEAD=false;MULTI=true;check();assert(visible() and s.unit==nil and s.frame.title._text=="SET HEALER","missing setup cue")
      DBagsAlertsDB.healerMana.name=" doc-home ";check()
      assert(visible() and s.unit=="party1","manual name override failed")
      MANUAL=true;check();assert(visible(),"manual healer requires role")
      DBagsAlertsDB.healerMana.name="Absent";check();assert(visible() and s.unit==nil and s.frame.title._text=="SET HEALER","missing manual setup cue")
      MULTI=false;MANUAL=false;DBagsAlertsDB.healerMana.name="";RAID=true
      check();assert(visible() and s.unit=="raid2","raid unit resolution")
      GROUPED=false;check();assert(not visible() and not s.rangeFrame:IsShown() and s.unit==nil,"solo warning/stale healer")
      GROUPED=true;RAID=false;DBagsAlertsDB.healerMana.enabled=false;check();assert(not visible(),"toggle ignored")
      DBagsAlertsDB.healerMana.enabled=true;ROLE="DAMAGER";SPEC_ROLE="DAMAGER";FORM=1
      local tankSetup=DBagsAlertsState.tankSetup
      if MODE_CLASS=="WARRIOR" then
          check();assert(visible(),"low-level Prot talents rejected by generic spec role")
      end
      DBagsAlertsState.tankSetup=function() return false end
      check();assert(not visible(),"DPS setup warned")
      DBagsAlertsState.tankSetup=tankSetup
      ROLE="TANK";SPEC_ROLE="TANK";FORM=5
      if MODE_CLASS=="PALADIN" then
          DBagsAlertsDB.tank=false;check();assert(not visible(),"paladin damage mode warned")
          DBagsAlertsDB.tank=true
      end
      DBagsAlertsState.openHealerSettings()
      for msg in pairs(ERRORS) do error(msg) end
    """)
    print(cls,"mana, drinking, range, combined states, unknown values, toggles and tank gating PASS")
