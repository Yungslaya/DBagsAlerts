from pathlib import Path
from lupa import lua51
root=Path(r'C:\Users\brand\Documents\DBagsAlerts')
for unknown_guid in (False,True):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="DRUID";CAST_IDS={}')
    lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
    lua.execute('''
      FORM_ID=0;PTYPE=0;WHICH="A";AURAS={A={Moonfire={duration=12,expirationTime=GetTime()+10}},B={}}
      local original=C_UnitAuras.GetAuraDataBySpellName
      C_UnitAuras.GetAuraDataBySpellName=function(unit,name,filter)
        if unit=="target" then assert(filter=="HARMFUL|PLAYER");return AURAS[WHICH][name] end
        return original(unit,name,filter)
      end
    ''')
    if unknown_guid: lua.execute('UnitGUID=function() return nil end')
    chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts/DBagsAlerts.lua').read_text(encoding='utf-8'))
    lua.execute('''
      local chunk=...;chunk("DBagsAlerts",{});FIRE("PLAYER_LOGIN")
      MODE.combat=true;MODE.target=true
      local function step() TICK();TICK() end
      local function moon()
        for _,f in ipairs(DBagsAlertsState.dotTiles) do if f.name=="Moonfire" then return f end end
        error("Moonfire tile missing")
      end
      step();assert(moon().num._text=="10","pre-existing target DoT not loaded")
      WHICH="B";FIRE("PLAYER_TARGET_CHANGED");step()
      assert(moon().num._text=="","DoT leaked to different target")
      ADVANCE(3);WHICH="A";FIRE("PLAYER_TARGET_CHANGED");step()
      assert(moon().num._text=="7","returning target DoT countdown not restored")
      AURAS.A.Moonfire=nil;FIRE("UNIT_AURA","target");step()
      assert(moon().num._text=="","removed DoT remained visible")
      AURAS.A.Moonfire={duration=12,expirationTime=GetTime()+12}
      FIRE("UNIT_AURA","target");step()
      assert(moon().num._text=="12","refresh on same target not detected")
      for msg in pairs(ERRORS) do error(msg) end
    ''',chunk)
    print('Druid target switch; GUID '+('hidden' if unknown_guid else 'readable')+' PASS')
