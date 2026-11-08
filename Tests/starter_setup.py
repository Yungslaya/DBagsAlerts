from pathlib import Path
from lupa import lua51
r=Path(__file__).resolve().parents[1]
for existing in (False, True):
 L=lua51.LuaRuntime(unpack_returned_tuples=True)
 L.execute('MODE_CLASS="WARRIOR"; CAST_IDS={}')
 L.execute((r/'Tests/harness.lua').read_text(encoding='utf-8-sig'))
 L.execute('function IsInInstance() return false,"none" end;function IsInGroup() return false end')
 if existing:
  L.execute('DBagsAlertsDB={target=true,cursor=true,hideBlizz=true,customSizes=true,geometry={health={width=420}},healerMana={enabled=true},partyDefensives={enabled=true,groupRange=true},followBuddy={enabled=true,name="Friend"},petPanel={enabled=true}}')
 for name in (r/'DBagsAlerts/DBagsAlerts.toc').read_text().splitlines():
  if name.endswith('.lua'):
   L.eval('function(s,n) return assert(loadstring(s,n)) end')((r/'DBagsAlerts'/name).read_text(encoding='utf-8-sig'),name)('DBagsAlerts',L.table())
 L.execute('FIRE("PLAYER_LOGIN");TICK();TICK();DBagsAlertsState.healerMana.check()')
 if existing:
  L.execute('''local d=DBagsAlertsDB
  assert(d.target and d.cursor and d.hideBlizz and d.customSizes,"update overwrote preferences")
  assert(d.partyDefensives.groupRange and d.healerMana.enabled,"update disabled chosen feature")
  assert(DBagsAlertsState.starterSetup())
  assert(not d.target and not d.cursor and not d.partyDefensives.groupRange and not d.followBuddy.enabled)
  assert(d.geometry.health.width==420 and d.followBuddy.name=="Friend","preset lost custom data")
  assert(DBagsAlertsState.starterSetup()) -- repeating does not overwrite original backup
  assert(DBagsAlertsState.starterSetup(true))
  assert(d.target and d.cursor and d.partyDefensives.groupRange and d.followBuddy.enabled)
  MODE.combat=true;assert(DBagsAlertsState.starterSetup()==false,"preset changed protected layout in combat")
  ''')
 else:
  L.execute('''local d=DBagsAlertsDB
  assert(d.stack and d.buffNag and d.locked,"starter lost core HUD")
  for _,k in ipairs({"target","casts","hideBlizz","cursor","foodNag","stoneNag","stoneNeed","stanceNag","range","sound","customSizes"}) do assert(d[k]==false,k.." not opt-in") end
  assert(d.partyDefensives.groupRange==false and d.partyDefensives.enabled==false)
  assert(d.healerMana.enabled==false and d.followBuddy.enabled==false and d.petPanel.enabled==false)
  assert(not DBagsAlertsState.groupRange.frame:IsShown(),"fresh install flashes group alert")
  assert(not d.debugLog.enabled,"debug enabled by default")
  ''')
 print('DBagsAlerts saved preferences' if existing else 'DBagsAlerts fresh defaults','PASS')
