from pathlib import Path
from lupa import lua51
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
xml=ET.parse(root/"DBagsAlerts/Bindings.xml")
assert xml.getroot().find("Binding").attrib["name"]=="CLICK DBagsAlertsFollowButton:LeftButton"
for cls in ("WARRIOR","DRUID","PRIEST"):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="'+cls+'";CAST_IDS={}')
    lua.execute((root/"Tests/harness.lua").read_text(encoding="utf-8"))
    lua.execute("""
      DUPLICATE=false
      FOLLOW_CALLS={}
      function FollowUnit(unit) FOLLOW_CALLS[#FOLLOW_CALLS+1]=unit end
      BINDINGS={};SAVED=0;CTRL=false;ALT=false;SHIFT=false
      function GetBindingKey(action)
          local keys={};for key,value in pairs(BINDINGS) do if value==action then keys[#keys+1]=key end end
          return keys[1],keys[2]
      end
      function GetBindingAction(key) return BINDINGS[key] or "" end
      function SetBindingClick(key,button,mouse) BINDINGS[key]="CLICK "..button..":"..mouse;return true end
      function SetBinding(key,action) BINDINGS[key]=action;return true end
      function GetCurrentBindingSet() return 2 end
      function SaveBindings(set) assert(set==2,"wrong binding profile");SAVED=SAVED+1 end
      function IsControlKeyDown() return CTRL end
      function IsAltKeyDown() return ALT end
      function IsShiftKeyDown() return SHIFT end
      function GetBindingText(value) return value end
      function UnitExists(u) return u=="player" or u=="party1" or (u=="party2" and DUPLICATE) end
      function UnitName(u)
          if u=="party1" then return "Doc","Home" end
          if u=="party2" then return "Doc","Away" end
          return "Player","Home"
      end
      local create=CreateFrame
      function CreateFrame(...)
          local f=create(...);f.attrs={}
          f.SetAttribute=function(self,k,v)
              assert(not MODE.combat,"protected attribute changed in combat")
              self.attrs[k]=v
          end
          return f
      end
    """)
    for file in ("DBagsAlerts.lua","FollowBuddy.lua"):
        chunk=lua.eval("function(s) return assert(loadstring(s)) end")((root/"DBagsAlerts"/file).read_text(encoding="utf-8"))
        lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
    lua.execute("""
      FIRE("PLAYER_LOGIN")
      local s=DBagsAlertsState.followBuddy
      assert(s.target==nil and #FOLLOW_CALLS==0,"unconfigured follow action")
      DBagsAlertsDB.followBuddy.name="Doc";assert(s.apply())
      assert(s.target=="Doc-Home" and s.unit=="party1","wrong resolved follow name")
      ADVANCE(2);TICK();TICK();assert(not s.following,"timer started follow without a keypress")
      s.button._OnClick(nil,"LeftButton",true);assert(s.frame.title._text=="FOLLOW REQUESTED" and not s.following,"unconfirmed follow shown as active")
      assert(FOLLOW_CALLS[1]=="party1","native FollowUnit not invoked for resolved party member")
      local clicks=#FOLLOW_CALLS;s.button._OnClick(nil,"LeftButton",false)
      assert(#FOLLOW_CALLS==clicks,"key release followed twice")
      FIRE("AUTOFOLLOW_BEGIN","Doc-Home")
      assert(s.following and s.frame.title._text=="FOLLOWING","native confirmation ignored")
      s.frame._OnDragStop(s.frame)
      assert(DBagsAlertsDB.followBuddy.hudPoint,"follow status position not saved")
      s.button._OnClick(nil,"LeftButton",true);ADVANCE(3);TICK();TICK();assert(s.frame.title._text=="FOLLOWING","repeat key falsely reported failure")
      FIRE("AUTOFOLLOW_END");assert(not s.following and s.frame.title._text=="FOLLOW STOPPED","stop status missing")
      ADVANCE(5);TICK();TICK();assert(not s.frame:IsShown(),"stopped status never hid")
      s.button._OnClick(nil,"LeftButton",true);ADVANCE(3);TICK();TICK();
      assert(s.frame.title._text=="FOLLOW NOT STARTED" and not s.following,"failed follow reported success")
      local calls=#FOLLOW_CALLS;MODE.combat=true
      DBagsAlertsDB.followBuddy.name="NewBuddy";s.apply()
      assert(#FOLLOW_CALLS==calls,"configuration started follow automatically")
      assert(s.target=="NewBuddy" and s.unit==nil,"nearby-name fallback wrong")
      MODE.combat=false;FIRE("PLAYER_REGEN_ENABLED")
      DUPLICATE=true;DBagsAlertsDB.followBuddy.name="Doc"
      assert(not s.apply() and s.target==nil,"ambiguous name picked wrong player")
      DBagsAlertsDB.followBuddy.name="Doc-Home";assert(s.apply())
      assert(s.target=="Doc-Home","full name resolution failed")
      DBagsAlertsDB.followBuddy.name="Doc\\n/follow Other";assert(not s.apply() and s.target==nil,"invalid name allowed")
      DBagsAlertsDB.followBuddy.name="Doc-Home";DBagsAlertsDB.followBuddy.enabled=false
      s.apply();assert(s.target==nil,"disabled follow action remained")
      DBagsAlertsState.openFollowBuddy()
      local action="CLICK DBagsAlertsFollowButton:LeftButton"
      s.bindingButton._OnClick();SHIFT=true;s.bindingCapture._OnKeyDown(nil,"F");SHIFT=false
      assert(BINDINGS["SHIFT-F"]==action and SAVED==1,"in-addon key capture not saved")
      s.bindingButton._OnClick();s.bindingCapture._OnKeyDown(nil,"ESCAPE")
      assert(BINDINGS["SHIFT-F"]==action,"Escape changed key")
      BINDINGS.G="JUMP";s.bindingButton._OnClick();s.bindingCapture._OnKeyDown(nil,"G")
      assert(BINDINGS.G=="JUMP","conflict silently replaced")
      s.bindingCapture._OnKeyDown(nil,"G")
      assert(BINDINGS.G==action and BINDINGS["SHIFT-F"]==nil,"replacement/old-key cleanup failed")
      MODE.combat=true;s.bindingButton._OnClick();assert(BINDINGS.G==action,"combat changed binding")
      MODE.combat=false;s.clearBinding._OnClick();assert(BINDINGS.G==nil,"clear did not unbind")
      for msg in pairs(ERRORS) do error(msg) end
    """)
    print(cls,"Follow buddy: hardware-triggered native FollowUnit, no release duplication, confirmation, failure/stop and in-addon binding PASS")
