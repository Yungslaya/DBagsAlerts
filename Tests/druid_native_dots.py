from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
lua=lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('MODE_CLASS="DRUID";CAST_IDS={}')
lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
lua.execute('''
FORM_ID=0;PTYPE=0;WHICH="A";MODE.secret=true
-- Hidden fields may still be displayable when aura access is permitted.
-- Permission and field secrecy are separate; the old mock missed this.
C_Secrets.ShouldAurasBeSecret=function() return false end
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
-- Reported failure: enumeration itself is forbidden, even if pcall is used.
local reads=0
local getIDs=C_UnitAuras.GetUnitAuraInstanceIDs
local getData=C_UnitAuras.GetAuraDataByAuraInstanceID
local getDuration=C_UnitAuras.GetAuraDuration
C_UnitAuras.GetUnitAuraInstanceIDs=function() reads=reads+1;error('forbidden aura enumeration') end
C_UnitAuras.GetAuraDataByAuraInstanceID=function() error('forbidden aura data') end
C_UnitAuras.GetAuraDuration=function() error('forbidden aura duration') end
C_Secrets.ShouldAurasBeSecret=function() return true end
WHICH="A";FIRE("PLAYER_TARGET_CHANGED");step()
assert(reads==0,'queried forbidden aura API')
for _,tile in ipairs(tiles) do assert(rawget(tile,'auraID')==nil,'stale native aura ID retained') end
FIRE('UNIT_SPELLCAST_SUCCEEDED','player','cast',63);ADVANCE(0.5);step()
local ownTimer=false
for _,tile in ipairs(tiles) do
 if tile.name=='Rake' and type(tile.num._text)=='string' and tile.num._text:match('^%d+$') then ownTimer=true end
end
assert(ownTimer,'readable own-cast timer lost when aura access blocked')
-- Restriction outlives combat: must still obey it after combat ends.
MODE.combat=false;FIRE('PLAYER_REGEN_ENABLED');step();assert(reads==0)
-- Unknown/secret permission also means no aura access.
MODE.secret=true;C_Secrets.ShouldAurasBeSecret=function() return UnitPower() end
step();assert(reads==0)
C_Secrets.ShouldAurasBeSecret=function() return false end
C_UnitAuras.GetUnitAuraInstanceIDs=getIDs
C_UnitAuras.GetAuraDataByAuraInstanceID=getData
C_UnitAuras.GetAuraDuration=getDuration
UnitCanAttack=function() return true end
FIRE('UNIT_AURA','target');step()
assert(#tiles==2 and tiles[1].auraID==101,'native auras did not recover: count='..#tiles..' id='..tostring(tiles[1] and rawget(tiles[1],'auraID')))
for msg in pairs(ERRORS) do error(msg) end
''',chunk)
print('Restricted Druid auras: native hidden icons/countdowns, target switching, form switching and removal PASS')
