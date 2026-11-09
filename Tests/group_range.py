from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
lua=lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('MODE_CLASS="WARRIOR";CAST_IDS={}')
lua.execute((root/'Tests/harness.lua').read_text(encoding="utf-8"))
lua.execute("""
GROUPED=true;RAID=false;FAR={};CHECKED={};DEAD={};ONLINE={};PRESENT={true,true,true,true}
MAPS={player=1440,party1=1440,party2=1440,party3=1440,party4=1440}
C_Map={GetBestMapForUnit=function(u) return MAPS[u] end}
function IsInGroup() return GROUPED end
function IsInRaid() return RAID end
function GetNumGroupMembers() return 5 end
function UnitExists(u) local i=tonumber(u:match("party(%d)"));return i and PRESENT[i] or u=="player" end
function UnitIsConnected(u) return ONLINE[tonumber(u:match("party(%d)"))]~=false end
function UnitIsDeadOrGhost(u) local i=tonumber(u:match("party(%d)"));return i and DEAD[i]==true or false end
function UnitDistanceSquared(u) local i=tonumber(u:match("party(%d)"));return FAR[i] and 2500 or 100,CHECKED[i]~=false end
function UnitInRange() return false,true end -- Deliberately wrong: must never override measured distance.
BINDINGS={};SAVED=0
function GetBindingKey(action) for k,v in pairs(BINDINGS) do if v==action then return k end end end
function GetBindingAction(k) return BINDINGS[k] or "" end
function SetBindingClick(k,b,m) BINDINGS[k]="CLICK "..b..":"..m;return true end
function SetBinding(k,a) BINDINGS[k]=a;return true end
function SaveBindings() SAVED=SAVED+1 end
function GetCurrentBindingSet() return 2 end
""")
for name in ['DBagsAlerts.lua','GroupRange.lua']:
    chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts'/name).read_text(encoding="utf-8"))
    lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
lua.execute("""
DBagsAlertsDB=DBagsAlertsDB or {};DBagsAlertsDB.partyDefensives={groupRange=true};FIRE("PLAYER_LOGIN")
local s=DBagsAlertsState.groupRange
local suppressed
DBagsAlertsState.setHealerRangeProofs=function(p) suppressed=p~=nil and #p==0 end
local function settle() s.update();ADVANCE(2.1);s.update() end
for mask=0,15 do
    local count=0
    for i=1,4 do FAR[i]=math.floor(mask/2^(i-1))%2==1;if FAR[i] then count=count+1 end end
    settle();assert(s.frame:IsShown()==(count>=3),"wrong visible warning for mask "..mask)
    assert(suppressed==(count>=3),"healer suppression mismatch "..mask)
end
FAR={false,true,false,false};PRESENT[4]=false;MAPS.party2=1450;settle()
assert(not s.frame:IsShown() and s.members==2,"nearby friends plus other-zone member triggered alert")
PRESENT[4]=true;MAPS.party2=1440;FAR={true,true,true,false};CHECKED[3]=false;settle()
assert(not s.frame:IsShown(),"unknown distance counted as far")
CHECKED={};s.update();assert(not s.frame:IsShown(),"no two-second confirmation")
ADVANCE(2.1);s.update();assert(s.frame:IsShown(),"confirmed majority missing")
s.muteButton._OnClick(nil,"LeftButton",true);assert(not s.frame:IsShown(),"mute did not hide immediately")
ADVANCE(59);s.update();assert(not s.frame:IsShown(),"mute ended early")
ADVANCE(2);s.update();assert(not s.frame:IsShown(),"resumed without confirmation")
ADVANCE(2.1);s.update();assert(s.frame:IsShown(),"mute never expired")
DBagsAlertsDB.partyDefensives.muteSeconds=120;s.snooze();assert(s.mutedUntil==GetTime()+120,"custom mute duration ignored")
s.mutedUntil=nil
DBagsAlertsState.openGroupRange()
local w=s.settings
w.bind._OnClick();w.bindingCapture._OnKeyDown(nil,"F8")
assert(BINDINGS.F8=="CLICK DBagsAlertsMuteWakeButton:LeftButton" and SAVED==1,"mute key not saved in addon")
w:Hide();RAID=true;settle();assert(not s.frame:IsShown(),"raid warning")
RAID=false;GROUPED=false;settle();assert(not s.frame:IsShown(),"solo warning")
GROUPED=true;RAID=false;FAR={true,true,true,false};CHECKED={};MAPS.player=1440
RESTING=true;function IsResting() return RESTING end
settle();assert(not s.frame:IsShown() and s.status=="Paused in a resting area","rest area warning")
RESTING=false
for city=1453,1458 do
 MAPS.player=city;settle();assert(not s.frame:IsShown() and s.status=="Paused in a capital city","capital warning")
end
MAPS.player=1440;s.update();assert(not s.frame:IsShown(),"leaving town bypassed confirmation")
ADVANCE(2.1);s.update();assert(s.frame:IsShown(),"warning did not resume outside town")
for msg in pairs(ERRORS) do error(msg) end
""")
print('Group range: explicit visibility, 16 majorities, same-map exclusion, unknown distance, debounce, timed mute and key capture PASS')
