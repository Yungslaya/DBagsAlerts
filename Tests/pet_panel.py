from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
for cls in ("WARLOCK","HUNTER","WARRIOR","PALADIN","DRUID","MAGE","PRIEST"):
 for hidden in (False,True):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="'+cls+'";CAST_IDS={}')
    lua.execute((root/'Tests/harness.lua').read_text(encoding="utf-8"))
    lua.execute("""
      PET_PRESENT=true;PET_DEAD=false;PET_HP=200;OWNER_HP=800;AUTO_CALLS=0;PICKUPS=0;AUTO=true
      function IsInInstance() return true,"party" end
      function UnitExists(u) if u=="pet" then return PET_PRESENT end return true end
      function UnitIsDeadOrGhost(u) return u=="pet" and PET_DEAD or false end
      local oldHealth=UnitHealth
      function UnitHealth(u)
          if MODE.secret then return oldHealth(u) end
          return u=="pet" and PET_HP or OWNER_HP
      end
      function UnitHealthMax(u) if MODE.secret then return oldHealth(u) end return 1000 end
      function UnitPowerType(u) return u=="pet" and 2 or 0 end
      function UnitName(u) return u=="pet" and "Buddy" or "Player" end
      function GetPetActionInfo(i)
          if i==10 then return nil end
          if i==4 then return MODE_CLASS=="WARLOCK" and "Torment" or "Growl",123,false,false,true,AUTO,99 end
          return "Pet action "..i,123,false,i==2,false,false,99
      end
      function GetPetActionCooldown() return 0,0,0 end
      function TogglePetAutocast() error("insecure protected autocast call") end
      for i=1,10 do _G["PetActionButton"..i]={nativeSlot=i} end
      function IsShiftKeyDown() return true end
      function PickupPetAction(slot) PICKUPS=PICKUPS+1 end
      C_PetInfo={GetPetHappiness=function() return 1 end,GetPetLoyalty=function() return "Best Friend" end,
          GetPetTrainingPoints=function() return 10,4 end,GetPetFoodTypes=function() return {"Meat","Fish"} end}
      local book={}
      if MODE_CLASS=="WARLOCK" then book={{"Summon Imp",688},{"Health Funnel",755}} end
      if MODE_CLASS=="HUNTER" then book={{"Call Pet",883},{"Revive Pet",982},{"Mend Pet",136},{"Feed Pet",6991},{"Beast Training",5149},{"Dismiss Pet",2641}} end
      C_SpellBook.GetNumSpellBookSkillLines=function() return 1 end
      C_SpellBook.GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=#book} end
      C_SpellBook.GetSpellBookItemInfo=function(i) return {name=book[i][1],spellID=book[i][2],itemType=1} end
      local create=CreateFrame
      function CreateFrame(...)
          local o=create(...);o.attrs={}
          o.HookScript=function(self,event,fn) self["_hook"..event]=fn end
          o.SetAttribute=function(self,k,v) assert(not MODE.combat,"pet attributes changed in combat");self.attrs[k]=v end
          return o
      end
    """)
    lua.execute('MODE.secret='+str(hidden).lower())
    for name in ('DBagsAlerts.lua','PetPanel.lua'):
        chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts'/name).read_text(encoding="utf-8"))
        lua.execute('local chunk=...;chunk("DBagsAlerts",{})',chunk)
    lua.execute("""
      FIRE("PLAYER_LOGIN")
      local s=DBagsAlertsState.petPanel
      s.update()
      assert(s.frame.attrs.unit=="pet" and s.frame.attrs["*type2"]=="togglemenu","native pet menu missing")
      assert(DRIVER[s.frame]=="[pet] show; hide","native pet visibility missing")
      assert(s.actions[4].attrs.type1=="pet" and s.actions[4].attrs.action1==4,"native action not configured")
      assert(AUTO_CALLS==0 and PICKUPS==0,"pet actions automated by update")
      assert(rawget(s.actions[4],"_OnClick")==nil,"native secure pet action click handler replaced")
      assert(rawget(s.actions[4],"_hookOnClick")==nil,"insecure click hook installed")
      assert(s.actions[4].attrs.type2=="click","right-click not secure delegated")
      assert(s.actions[4].attrs.clickbutton2==PetActionButton4,"wrong native action slot")
      assert(AUTO_CALLS==0,"addon called protected autocast")
      s.actions[4]._OnDragStart(s.actions[4]);assert(PICKUPS==1,"shift-drag action not picked up")
      if MODE_CLASS=="HUNTER" then
          assert(s.utilityCount==6,"Hunter controls missing")
          assert(s.care._text:find("FEED PET") and s.care._text:find("6 TP"),"Hunter care info missing")
      elseif MODE_CLASS=="WARLOCK" then
          assert(s.utilityCount==2,"unknown demon spells displayed")
          if not MODE.secret then
              assert(s.utilities[2].warn._alpha==1,"low-health Funnel cue missing")
              OWNER_HP=200;s.update();assert(s.utilities[2].warn._alpha==0,"Funnel encouraged at low owner health")
          end
      else assert(s.utilityCount==0,"class received unrelated pet summons") end
      DBagsAlertsDB.customSizes=true
      DBagsAlertsDB.geometry=DBagsAlertsDB.geometry or {}
      DBagsAlertsDB.geometry.pet={width=180,height=30,x=100,y=-50}
      s.configure()
      assert(s.health._w==180 and s.health._h==30,"pet dimensions not applied")
      assert(s.frame._w==180 and s.frame._h>100,"narrow pet actions did not wrap")
      MODE.combat=true
      DBagsAlertsDB.geometry.pet.width=240
      s.configure();assert(s.frame._w==180,"protected pet layout changed in combat")
      MODE.combat=false;FIRE("PLAYER_REGEN_ENABLED")
      assert(s.frame._w==240,"deferred pet layout did not apply")
      MODE.combat=true;s.configure();s.update()
      s.actions[4]._OnDragStart(s.actions[4]);assert(PICKUPS==1,"action dragged in combat")
      MODE.combat=false;FIRE("PLAYER_REGEN_ENABLED")
      DBagsAlertsDB.petPanel.locked=false;s.frame._OnDragStop(s.frame)
      assert(DBagsAlertsDB.petPanel.point,"pet position not saved")
      PET_PRESENT=false;s.update()
      if s.utilityCount>0 then assert(s.care._text:find("NO PET"),"missing pet not indicated") end
      DBagsAlertsDB.petPanel.enabled=false;s.configure();assert(DRIVER[s.frame]=="hide","disabled pet frame visible")
      DBagsAlertsState.openPetSettings()
      if MODE_CLASS=="HUNTER" then SlashCmdList.DBAGSALERTS("");assert(DBagsAlertsState.settingsWindows.pet:IsShown(),"Hunter cannot open addon settings") end
      for msg in pairs(ERRORS) do error(msg) end
    """)
    print(cls,"hidden" if hidden else "plain","pet frame, menu, actions, manual autocast, care, combat and settings PASS")
