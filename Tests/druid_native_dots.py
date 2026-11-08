from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
lua=lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('MODE_CLASS="DRUID";CAST_IDS={}')
lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
lua.execute('''
FORM_ID=0;PTYPE=0;WHICH="A";MODE.secret=true
UnitGUID=function() return nil end
C_UnitAuras.GetUnitAuraInstanceIDs=function(unit,filter,maxCount)
    assert(unit=="target" and filter=="HARMFUL|PLAYER" and maxCount==6)
    return WHICH=="A" and {101,102} or {}
end
C_UnitAuras.GetAuraDataByAuraInstanceID=function(unit,id)
    return {auraInstanceID=id,name=UnitPower(),icon=UnitPower(),duration=UnitPower(),expirationTime=UnitPower()}
end
C_UnitAuras.GetAuraDuration=function(unit,id) return {unit=unit,id=id} end
''')
chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts/DBagsAlerts.lua').read_text(encoding='utf-8'))
lua.execute('''
local chunk=...;chunk("DBagsAlerts",{});FIRE("PLAYER_LOGIN")
MODE.combat=true;MODE.target=true
local function step() TICK();TICK() end
step()
local tiles=DBagsAlertsState.dotTiles
assert(#tiles==2 and tiles[1].auraID==101 and tiles[2].auraID==102,"native current-target DoTs missing")
assert(tiles[1].nativeCD:IsShown() and tiles[1].nativeCD._cdobj==true,"native hidden countdown missing")
WHICH="B";FIRE("PLAYER_TARGET_CHANGED");step()
assert(#tiles==0,"DoTs leaked to undotted target")
WHICH="A";FIRE("PLAYER_TARGET_CHANGED");step()
assert(#tiles==2 and tiles[1]:IsShown() and tiles[2]:IsShown(),"returning-target native DoTs missing")
FORM_ID=1;PTYPE=3;FIRE("UPDATE_SHAPESHIFT_FORM");ADVANCE(0.6);step()
assert(#tiles==2 and tiles[1].auraID==101,"changing form lost existing caster DoTs")
WHICH="B";FIRE("UNIT_AURA","target");step()
assert(#tiles==0,"removed native DoTs not cleared")
for msg in pairs(ERRORS) do error(msg) end
''',chunk)
print('Restricted Druid auras: native hidden icons/countdowns, target switching, form switching and removal PASS')
