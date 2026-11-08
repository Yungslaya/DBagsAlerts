from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
lua=lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('MODE_CLASS="DRUID";CAST_IDS={};FORM_ID=0;PTYPE=0')
lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
lua.execute('FORM_ID=0;PTYPE=0')
chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts/DBagsAlerts.lua').read_text(encoding='utf-8'))
lua.execute('''
local chunk=...;chunk('DBagsAlerts',{});FIRE('PLAYER_LOGIN');TICK()
local hud=DBagsAlertsState.casterHUD
local DBagsAlertsFrame=DBagsAlertsState.main
assert(hud.form=='caster')
local edits=0
for _,name in ipairs({'SetSize','SetScale','ClearAllPoints','SetPoint','EnableMouse','EnableMouseWheel'}) do
 local original=DBagsAlertsFrame[name]
 DBagsAlertsFrame[name]=function(self,...)
  assert(not MODE.combat,'protected HUD mutation in combat: '..name)
  edits=edits+1;return original(self,...)
 end
end
MODE.combat=true
FORM_ID=1;PTYPE=3;FIRE('UPDATE_SHAPESHIFT_FORM');TICK()
FORM_ID=5;PTYPE=1;FIRE('UPDATE_SHAPESHIFT_FORM');TICK()
FORM_ID=0;PTYPE=0;FIRE('UPDATE_SHAPESHIFT_FORM');TICK()
FORM_ID=1;PTYPE=3;FIRE('UPDATE_SHAPESHIFT_FORM');TICK()
assert(edits==0,'layout ran during combat')
assert(DBagsAlertsState.casterHUD==hud,'combat layout changed')
MODE.combat=false;FIRE('PLAYER_REGEN_ENABLED');TICK()
assert(edits>0,'pending layout never applied')
assert(DBagsAlertsState.casterHUD.form=='cat','latest form not applied after combat')
for msg in pairs(ERRORS) do error(msg) end
''',chunk)
print('Druid combat form changes: no protected anchor mutations; latest layout restored after combat PASS')
