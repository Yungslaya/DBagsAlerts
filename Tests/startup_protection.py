from pathlib import Path
from lupa import lua51
r=Path(__file__).resolve().parents[1]
L=lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute('MODE_CLASS="WARLOCK"; CAST_IDS={}')
L.execute((r/'Tests/harness.lua').read_text(encoding='utf-8-sig'))
L.execute('''BLOCKED_REGISTRATIONS=0
function IsInInstance() return false,"none" end
function IsInGroup() return false end
local create=CreateFrame
CreateFrame=function(...)
 local f=create(...)
 f.RegisterEvent=function(self,event)
  if event=="COMBAT_LOG_EVENT_UNFILTERED" or event=="COMBAT_LOG_EVENT" then
   BLOCKED_REGISTRATIONS=BLOCKED_REGISTRATIONS+1
   error("restricted event registration")
  end
 end
 return f
end
''')
for file in (r/'DBagsAlerts/DBagsAlerts.toc').read_text().splitlines():
 if file.endswith('.lua'):
  L.eval('function(s,n) return assert(loadstring(s,n)) end')((r/'DBagsAlerts'/file).read_text(encoding='utf-8-sig'),file)('DBagsAlerts',L.table())
L.execute('''assert(BLOCKED_REGISTRATIONS==0,"addon attempted forbidden event even under pcall")
FIRE("ADDON_ACTION_FORBIDDEN","DBagsAlerts","Frame:RegisterEvent")
DBagsAlertsDB={} -- simulate SavedVariables becoming available after source files
FIRE("PLAYER_LOGIN");TICK();TICK()
assert(#DBagsAlertsDB.debugLog.errors==1,"startup blocked action lost")
assert(DBagsAlertsDB.debugLog.errors[1].message:find("Frame:RegisterEvent",1,true))
assert(DBagsAlertsDB.debugLog.enabled==false,"diagnostic forced verbose logging on")
FIRE("ADDON_ACTION_BLOCKED","DBagsAlerts","TestProtectedAction")
assert(#DBagsAlertsDB.debugLog.errors==2,"blocked action lost with debug recording off")
assert(BLOCKED_REGISTRATIONS==0)
''')
print('Startup: no restricted event registration; early blocked actions preserved with recording off PASS')
