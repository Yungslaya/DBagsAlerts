from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
lua=lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('MODE_CLASS="WARRIOR"; CAST_IDS={}')
lua.execute((root/'Tests/harness.lua').read_text(encoding="utf-8"))
lua.execute('function IsInInstance() return false,"none" end')
for name in ['DBagsAlerts.lua','HealerMana.lua','PartyDefensives.lua','GroupRange.lua','FollowBuddy.lua']:
    chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts'/name).read_text(encoding="utf-8"))
    lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
lua.execute("""
FIRE("PLAYER_LOGIN")
local function only(key)
    for name,w in pairs(DBagsAlertsState.settingsWindows) do
        assert(w:IsShown()==(name==key),"window stack: "..name.." during "..key)
    end
    local w=DBagsAlertsState.settingsWindows[key]
    assert(rawget(w,"_OnDragStart") and rawget(w,"_OnDragStop"),"window cannot move")
    w._OnDragStop(w);assert(DBagsAlertsDB.windows[key],"window position not saved")
end
SlashCmdList.DBAGSALERTS("");only("main")
assert(DBagsAlertsState.settingsFrame._h<=820,"main settings too tall")
DBagsAlertsState.openPartyDefensives();only("party")
DBagsAlertsState.openFollowBuddy();only("follow")
DBagsAlertsState.openHealerSettings();only("healer")
SlashCmdList.DBAGSALERTS("");only("main")
DBagsAlertsState.groupRange.update()
assert(not DBagsAlertsState.groupRange.frame:IsShown(),"warning flashes over settings")
for msg in pairs(ERRORS) do error(msg) end
""")
print('Single-window navigation, drag/save positions, bounded height and quiet settings PASS')
