from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
for cls in ('WARRIOR','PALADIN','DRUID','WARLOCK'):
 lua=lua51.LuaRuntime(unpack_returned_tuples=True)
 lua.execute('MODE_CLASS="'+cls+'";CAST_IDS={}')
 lua.execute((root/'Tests/harness.lua').read_text(encoding='utf-8'))
 lua.execute('''
  local create=CreateFrame
  CreateFrame=function(...)
   local f=create(...)
   f.SetScale=function(self,value) self._scale=value end
   f.GetScale=function(self) return rawget(self,"_scale") or 1 end
   f.SetPoint=function(self,point,a,b,x,y)
    if type(a)=="number" then x,y=a,b end
    self._point={point=point,x=x or 0,y=y or 0}
   end
   return f
  end
  HAS_TOT=true
  local exists=UnitExists
  UnitExists=function(unit) if unit=="targettarget" then return HAS_TOT end;return exists(unit) end
  local name=UnitName
  UnitName=function(unit) if unit=="targettarget" then return "Healer" end;return name(unit) end
 ''')
 chunk=lua.eval('function(s) return assert(loadstring(s)) end')((root/'DBagsAlerts/DBagsAlerts.lua').read_text(encoding='utf-8'))
 lua.execute('''
  local chunk=...;chunk("DBagsAlerts",{});FIRE("PLAYER_LOGIN")
  local state=DBagsAlertsState
  local db=DBagsAlertsDB
  assert(db.targetOfTarget==false and db.customSizes==false,"new features not off by default")
  SlashCmdList.DBAGSALERTS("")
  local w=state.settingsFrame
  assert(w._w==760 and w._h==580,"settings not bounded")
  local count=0
  for name,page in pairs(w.pages) do
   count=count+1;w.selectPage(name)
   local visible=0
   for _,p in pairs(w.pages) do if p.scroll:IsShown() then visible=visible+1 end end
   assert(visible==1,"settings pages overlap")
  end
  assert(count==8,"missing category pages")
  w.selectPage("frames")
  local toggle=w.controls.targetOfTarget
  toggle.GetChecked=function() return true end;toggle._OnClick(toggle)
  MODE.target=true;TICK();TICK()
  assert(state.targetFrame.totBar:IsShown(),"enabled target-of-target missing")
  assert(state.targetFrame.tot._text=="> Healer","wrong target-of-target name")
  HAS_TOT=false;FIRE("UNIT_TARGET","target");TICK();TICK()
  assert(not state.targetFrame.totBar:IsShown(),"missing target-of-target left empty bar")
  HAS_TOT=true;MODE.secret=true;FIRE("UNIT_HEALTH","targettarget");TICK();TICK()
  assert(state.targetFrame.totBar:IsShown(),"hidden health values blocked target-of-target")
  MODE.secret=false
  w.selectPage("sizes")
  local enabled=w.controls.customSizes
  enabled.GetChecked=function() return true end;enabled._OnClick(enabled)
  local anchorW,anchorH=state.main._w,state.main._h
  w.controls.size_target._OnValueChanged(w.controls.size_target,1.6)
  assert(state.targetFrame:GetScale()==1.6,"target size slider did not resize target")
  assert(db.scale==1,"target size changed entire HUD")
  w.controls.size_player._OnValueChanged(w.controls.size_player,1.4)
  w.controls.size_dots._OnValueChanged(w.controls.size_dots,2)
  w.controls.size_alerts._OnValueChanged(w.controls.size_alerts,1.25)
  w.controls.size_cooldowns._OnValueChanged(w.controls.size_cooldowns,1.5)
  assert(state.targetFrame:GetScale()==1.6,"other part resize changed target size")
  assert(state.main._w==anchorW and state.main._h==anchorH,"individual size changed shared drag anchor")
  assert(state.casterHUD.dotY>=8+48*1.6,"larger target/ToT overlaps DoTs")
  local first=state.dotTiles[1]
  if first then assert(first:GetScale()==2,"DoT size slider unused") end
  for _,alert in ipairs(state.alerts) do assert(alert.root:GetScale()==1.25,"spell cue size slider unused") end
  enabled.GetChecked=function() return false end;enabled._OnClick(enabled)
  assert(state.targetFrame:GetScale()==1,"disabling custom sizes did not restore default target size")
  assert(db.partSizes.target==1.6,"custom size preference lost when disabled")
  toggle.GetChecked=function() return false end;toggle._OnClick(toggle);TICK();TICK()
  assert(not state.targetFrame.totBar:IsShown(),"target-of-target toggle did not hide bar")
  for msg in pairs(ERRORS) do error(msg) end
 ''',chunk)
 print(cls,'category pages, opt-in ToT, hidden health, separate sizes and spacing PASS')
