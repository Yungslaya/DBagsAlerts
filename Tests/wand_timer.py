from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
for cls in ("WARLOCK","MAGE","PRIEST"):
 for hidden in (False,True):
  lua=lua51.LuaRuntime(unpack_returned_tuples=True)
  lua.execute('MODE_CLASS="'+cls+'"; CAST_IDS={}')
  lua.execute((root/'Tests/harness.lua').read_text())
  lua.execute('DBagsAlertsState={}; Enum.PlayerSwingType={Ranged=2}; function UnitRangedDamage() return 1.5 end')
  lua.execute((root/'DBagsAlerts/WandTimer.lua').read_text())
  lua.execute('MODE.secret='+str(hidden).lower())
  lua.execute('FIRE("PLAYER_LOGIN"); FIRE("START_AUTOREPEAT_SPELL"); TICK()\n  local s=DBagsAlertsState.wandTimer\n  assert(s.duration==0)\n  FIRE("PLAYER_SWING",MODE.secret and UnitPower() or 1.5,2); ADVANCE(.2); TICK()\n  assert(s.duration==1.5 and s.frame._shown==true)\n  FIRE("PLAYER_SWING",2,0); assert(s.duration==1.5)\n  DBagsAlertsDB.off={swing=true}; TICK(); assert(not s.frame._shown)\n  DBagsAlertsDB.off.swing=nil\n  local started=s.start\n  FIRE("STOP_AUTOREPEAT_SPELL"); ADVANCE(.2); TICK()\n  assert(s.frame._shown==true and s.start==started,"movement erased countdown")\n  FIRE("START_AUTOREPEAT_SPELL"); TICK()\n  assert(s.start==started,"resume restarted countdown")\n  FIRE("STOP_AUTOREPEAT_SPELL"); ADVANCE(2); TICK()\n  assert(s.frame._shown==true and s.text._text=="Wand ready","missing ready cue")\n  ADVANCE(9); TICK(); assert(not s.frame._shown,"stale ready cue")\n  FIRE("PLAYER_SWING",1.5,2); FIRE("PLAYER_REGEN_ENABLED"); TICK()\n  assert(not s.frame._shown and s.duration==0,"combat end retained timer")\n  FIRE("PLAYER_SWING",1.5,2); FIRE("PLAYER_EQUIPMENT_CHANGED",18); TICK()\n  assert(not s.frame._shown and not s.active)\n  for msg in pairs(ERRORS) do error(msg) end')
  print(cls,hidden,"wand PASS")
