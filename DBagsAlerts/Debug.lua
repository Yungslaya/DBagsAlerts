-- Opt-in bounded diagnostics. No hidden-value decoding, chat logging or gameplay actions.
local D={guards={},busy=false};DBagsAlertsDebug=D
local secret=issecretvalue or function() return false end
local function safe(v)
 if secret(v) then return "[restricted]" end
 local kind=type(v)
 if kind=="string" then return v:sub(1,12000) end
 if kind=="number" or kind=="boolean" then return tostring(v) end
 return "["..kind.."]"
end
local function config()
 DBagsAlertsDB=DBagsAlertsDB or {}
 if type(DBagsAlertsDB.debugLog)~="table" then DBagsAlertsDB.debugLog={enabled=false,errors={},events={}} end
 local c=DBagsAlertsDB.debugLog;c.errors=c.errors or {};c.events=c.events or {};return c
end
local function context()
 local _,class=UnitClass("player");local inside,kind=IsInInstance()
 local state=DBagsAlertsState or {};local party=state.partyDefensives
 return "class="..safe(class).." combat="..safe(InCombatLockdown()).." instance="..safe(kind).." grouped="..safe(IsInGroup())
  .." party="..safe(party and party.status)
end
function D.record(message,stack,force)
 local c=config();if not c.enabled and not force then return end
 message=safe(message)
 for _,entry in ipairs(c.errors) do
  if entry.message==message then entry.count=entry.count+1;entry.last=GetTime();return end
 end
 if #c.errors>=30 then table.remove(c.errors,1) end
 c.errors[#c.errors+1]={message=message,stack=safe(stack or (debugstack and debugstack(3,12,4)) or "No stack available"),
  count=1,first=GetTime(),last=GetTime(),context=context()}
end
function D.note(label)
 local c=config();if not c.enabled then return end
 if #c.events>=40 then table.remove(c.events,1) end
 c.events[#c.events+1]=string.format("%.1f %s %s",GetTime(),safe(label),context())
end
function D.guard(label,fn)
 local failures,blockedUntil,uniqueFailures={},0,0
 return function(...)
  if GetTime()<blockedUntil then return end
  local ok,result=pcall(fn,...)
  if ok then return result end
  blockedUntil=GetTime()+2
  local message=label..": "..safe(result)
  D.guards[label]=message
  if not failures[message] and uniqueFailures<20 then
   failures[message]=true;uniqueFailures=uniqueFailures+1
   if geterrorhandler then geterrorhandler()(message) else D.record(message) end
  else D.record(message) end
 end
end
local previous,handler
local function install(enabled)
 local c=config();c.enabled=enabled and true or false
 if c.enabled and geterrorhandler and seterrorhandler then
  if geterrorhandler()~=handler then
   previous=geterrorhandler();local forward=previous
   handler=function(message)
    if D.busy then return end
    D.busy=true
    pcall(D.record,message,debugstack and debugstack(2,12,4))
    D.busy=false
    if forward then return forward(message) end
   end
   seterrorhandler(handler)
  end
 elseif handler and geterrorhandler and seterrorhandler and geterrorhandler()==handler then seterrorhandler(previous) end
end
D.enable=install
local function version()
 local api=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
 return api and api("DBagsAlerts","Version") or "unknown"
end
function D.report()
 local c=config();local out={"DBagsAlerts "..safe(version()),context(),"Debug recording: "..safe(c.enabled)}
 local cd=DBagsAlertsState and DBagsAlertsState.partyCooldowns
 if cd and cd.summary then out[#out+1]=cd.summary() end
 for label,error in pairs(D.guards) do out[#out+1]="Guard "..label..": "..error end
 out[#out+1]="Recent events (bounded; no chat text):"
 for _,event in ipairs(c.events) do out[#out+1]=event end
 out[#out+1]="Errors: "..#c.errors
 for i,error in ipairs(c.errors) do
  out[#out+1]=string.format("\n#%d x%d: %s\n%s\n%s",i,error.count,error.message,error.context,error.stack)
 end
 return table.concat(out,"\n")
end
local window
local function open()
 if not window then
  local w=CreateFrame("Frame","DBagsAlertsDebugWindow",UIParent);window=w
  w:SetSize(620,480);w:SetPoint("CENTER");w:SetFrameStrata("DIALOG");w:SetClampedToScreen(true)
  if DBagsAlertsState and DBagsAlertsState.prepareSettingsWindow then DBagsAlertsState.prepareSettingsWindow(w,"debug") end
  w:SetMovable(true);w:EnableMouse(true);w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart",function(self) self:StartMoving() end);w:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
  local bg=w:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0.055,0.055,0.065,1)
  local function text(label,x,y,size)
   local f=w:CreateFontString(nil,"OVERLAY");f:SetFont("Fonts\\FRIZQT__.TTF",size or 13,"OUTLINE");f:SetPoint("TOPLEFT",x,y);f:SetText(label);return f
  end
  text("Debug",18,-16,20)
  local function button(label,x,y,width,callback)
   local b=CreateFrame("Button",nil,w,"UIPanelButtonTemplate");b:SetSize(width,26);b:SetPoint("TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",callback);return b
  end
  button("X",574,-10,28,function() w:Hide() end)
  w.enabled=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");w.enabled:SetPoint("TOPLEFT",12,-46);text("Record debug log",46,-55)
  w.enabled:SetScript("OnClick",function(self) install(self:GetChecked()) end)
  w.luaErrors=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");w.luaErrors:SetPoint("TOPLEFT",292,-46);text("Show Lua errors",326,-55)
  w.luaErrors:SetScript("OnClick",function(self) if SetCVar then SetCVar("scriptErrors",self:GetChecked() and "1" or "0") end end)
  local scroll=CreateFrame("ScrollFrame",nil,w,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",18,-98);scroll:SetPoint("BOTTOMRIGHT",-42,56)
  local edit=CreateFrame("EditBox",nil,scroll);w.edit=edit
  edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal);edit:SetWidth(550);edit:SetHeight(300)
  edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  -- EditBox has no GetStringHeight. Measure wrapped text on a FontString
  -- using the same font and width, then size the scroll child to fit it.
  local measure=scroll:CreateFontString(nil,"OVERLAY")
  measure:SetFontObject(ChatFontNormal);measure:SetWidth(550);measure:SetWordWrap(true);measure:Hide()
  edit:SetScript("OnTextChanged",function(self)
   measure:SetWidth(self:GetWidth() or 550);measure:SetText(self:GetText() or "")
   local height=measure:GetStringHeight()
   if type(height)=="number" then self:SetHeight(math.max(300,height+24)) end
  end)
  scroll:SetScrollChild(edit)
  button("Refresh",18,-438,110,function() edit:SetText(D.report());edit:ClearFocus() end)
  button("Select report",138,-438,140,function() edit:SetFocus();edit:HighlightText() end)
  button("Clear log",288,-438,110,function() local c=config();c.errors={};c.events={};D.guards={};edit:SetText(D.report()) end)
  text("Select report, then Ctrl+C.",410,-446,11)
  table.insert(UISpecialFrames,"DBagsAlertsDebugWindow")
 end
 window.enabled:SetChecked(config().enabled)
 window.luaErrors:SetChecked(GetCVar and GetCVar("scriptErrors")=="1")
 window.edit:SetText(D.report())
 if DBagsAlertsState and DBagsAlertsState.showSettingsWindow then DBagsAlertsState.showSettingsWindow(window,"debug") else window:Show() end
end
D.open=open
SLASH_DBAGSDEBUG1="/dbadebug"
SlashCmdList.DBAGSDEBUG=function(message)
 message=(message or ""):lower()
 if message=="on" then install(true);print("DBagsAlerts: debug recording ON. /dbadebug to copy the report.")
 elseif message=="off" then install(false);print("DBagsAlerts: debug recording OFF.")
 elseif message=="errors on" or message=="errors off" then
  if SetCVar then SetCVar("scriptErrors",message=="errors on" and "1" or "0") end
  print("DBagsAlerts: Lua error display "..(message=="errors on" and "ON" or "OFF"))
 else open() end
end
local frame=CreateFrame("Frame");D.driver=frame
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","GROUP_ROSTER_UPDATE","PLAYER_TARGET_CHANGED","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,addon,functionName)
 local blocked=event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN"
 if blocked then
  local ours=not secret(addon) and (addon=="DBagsAlerts" or addon=="ProtAlerts")
  if ours or config().enabled then
   local entry={message=event..": "..safe(addon).." / "..safe(functionName),stack=debugstack and debugstack(2,12,4)}
   if D.loginReady then D.record(entry.message,entry.stack,true)
   else
    -- SavedVariables are not guaranteed to be restored during file loading.
    -- Keep load-time warnings in memory, then merge them after PLAYER_LOGIN.
    D.startupBlocks=D.startupBlocks or {}
    if #D.startupBlocks<20 then D.startupBlocks[#D.startupBlocks+1]=entry end
   end
  end
 end
 if event=="PLAYER_LOGIN" then
  D.loginReady=true
  if DBagsAlertsState then DBagsAlertsState.debug=D end
  install(config().enabled)
  for _,entry in ipairs(D.startupBlocks or {}) do D.record(entry.message,entry.stack,true) end
  D.startupBlocks=nil
 end
 local c=config();if not c.enabled then return end
 if #c.events>=40 then table.remove(c.events,1) end
 c.events[#c.events+1]=string.format("%.1f %s %s",GetTime(),event,context())
end)
