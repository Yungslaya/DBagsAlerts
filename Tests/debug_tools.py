from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
lua=lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute('MODE_CLASS="DRUID";CAST_IDS={}')
lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
lua.execute('''
CVARS.scriptErrors="0";FORWARDED=0
function IsInInstance() return true,"party" end
function SetCVar(key,value) CVARS[key]=value end
function debugstack() return "fake stack: source.lua:123" end
local handler=function(message) FORWARDED=FORWARDED+1 end
function geterrorhandler() return handler end
function seterrorhandler(fn) handler=fn end
local create=CreateFrame
CreateFrame=function(...)
 local f=create(...)
 if select(1,...)=="EditBox" then
  f.GetStringHeight=function() error("EditBox has no GetStringHeight") end
  f.GetText=function(self) return self._text or "" end
  f.GetWidth=function(self) return self._w end
  f.SetText=function(self,value)
   self._text=value
   local callback=rawget(self,"_OnTextChanged")
   if callback then callback(self,false) end
  end
 end
 f.CreateFontString=function(self)
  local text=newObjPublic()
  text.GetStringHeight=function(self) return #(self._text or "")*2 end
  return text
 end
 f.GetScript=function(self,script) return rawget(self,"_"..script) end
 return f
end
''')
for file in ('Debug.lua','DBagsAlerts.lua','PartyCooldowns.lua','PartyDefensives.lua'):
 chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts'/file).read_text(encoding='utf-8-sig'))
 lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
lua.execute('''
FIRE("PLAYER_LOGIN")
assert(not DBagsAlertsDB.debugLog.enabled,"debug recording on by default")
SlashCmdList.DBAGSDEBUG("on")
assert(DBagsAlertsDB.debugLog.enabled,"cannot enable debug")
geterrorhandler()("test addon error")
geterrorhandler()("test addon error")
local c=DBagsAlertsDB.debugLog
assert(#c.errors==1 and c.errors[1].count==2,"repeated errors not grouped")
assert(c.errors[1].stack:find("source.lua",1,true),"missing stack")
assert(FORWARDED==2,"debug handler swallowed normal Lua display")
SlashCmdList.DBAGSDEBUG("errors on");assert(CVARS.scriptErrors=="1","Lua popup toggle on failed")
SlashCmdList.DBAGSDEBUG("errors off");assert(CVARS.scriptErrors=="0","Lua popup toggle off failed")
MODE.combat=true
for i=1,50 do FIRE("PLAYER_REGEN_DISABLED") end
assert(#c.events==40,"event history not bounded")
for i=1,40 do DBagsAlertsDebug.record("error "..i) end
assert(#c.errors==30,"error history not bounded")
local calls=0
local guarded=DBagsAlertsDebug.guard("test guard",function() calls=calls+1;error("intentional guarded failure") end)
for i=1,100 do guarded() end
assert(calls==1,"guard kept erroring each frame")
ADVANCE(2.1);guarded();assert(calls==2,"guard never retried")
assert(DBagsAlertsDebug.report():find("combat=true",1,true),"missing combat context")
SlashCmdList.DBAGSDEBUG("")
assert(DBagsAlertsState.settingsWindows.debug:IsShown(),"report window missing")
assert(DBagsAlertsState.settingsWindows.debug.edit._text:find("Errors:",1,true),"report text missing")
local edit=DBagsAlertsState.settingsWindows.debug.edit
assert(edit._h>300,"long debug report cannot scroll fully")
edit:SetText("short");assert(edit._h==300,"short debug report did not shrink")
DBagsAlertsDebug.open()
assert(edit._h>300 and edit._text:find("Errors:",1,true),"refresh failed to resize long report")
SlashCmdList.DBAGSDEBUG("off")
local before=#c.errors;geterrorhandler()("after disabling")
assert(#c.errors==before,"debug capture did not stop")
for message in pairs(ERRORS) do
 if not message:find("intentional guarded failure",1,true) then error(message) end
end
''')
print('Debug: opt-in capture, stacks, duplicate counts, bounds, combat context, error popup toggles, guards and report UI PASS')
