-- Wand timing uses public shot events only. No combat-log access.
local _, class = UnitClass("player")
if class ~= "WARLOCK" and class ~= "MAGE" and class ~= "PRIEST" then return end
local state = {start=0, duration=0, active=false}
DBagsAlertsState.wandTimer = state
local bar = CreateFrame("StatusBar", "DBagsAlertsWandTimer", UIParent)
state.frame = bar
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.35,0.65,1)
bar:SetSize(280,10)
bar:SetPoint("CENTER",UIParent,"CENTER",0,-180)
local bg=bar:CreateTexture(nil,"BACKGROUND")
bg:SetAllPoints(); bg:SetColorTexture(0.04,0.04,0.06,0.75)
local text=bar:CreateFontString(nil,"OVERLAY")
state.text = text
text:SetFont("Fonts\\FRIZQT__.TTF",11,"OUTLINE"); text:SetPoint("CENTER")
bar:Hide()
local function hidden(v) return issecretvalue and issecretvalue(v) end
local function speed()
    if not UnitRangedDamage then return end
    local value=UnitRangedDamage("player")
    if not hidden(value) and type(value)=="number" and value>0 then return value end
end
local function reset()
    state.start,state.duration=0,0; bar:Hide()
end
local function place()
    if InCombatLockdown() then return end
    local db=DBagsAlertsDB or {}
    bar:ClearAllPoints()
    local parts=DBagsAlertsState.layoutParts
    if class=="WARLOCK" and parts and parts.power then
        local anchor=DBagsAlertsState.casterHUD and parts.swing or parts.power
        bar:SetPoint("TOPLEFT",anchor,"TOPLEFT",0,0)
        bar:SetPoint("TOPRIGHT",anchor,"TOPRIGHT",0,0)
        if anchor==parts.power then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-2)
            bar:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,-2)
        end
    else
        local pos=db.wandPosition or {}
        bar:SetPoint("CENTER",UIParent,"CENTER",pos.x or 0,pos.y or -180)
        bar:SetWidth(280)
    end
end
bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart",function(self)
    if class~="WARLOCK" and not InCombatLockdown() then self:StartMoving() end
end)
bar:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    local x,y=self:GetCenter(); local px,py=UIParent:GetCenter()
    if x and y and px and py then
        DBagsAlertsDB=DBagsAlertsDB or {}; DBagsAlertsDB.wandPosition={x=x-px,y=y-py}
    end
end)
local driver=CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent",function(self,event,a,b)
    if event=="PLAYER_LOGIN" then
        DBagsAlertsDB=DBagsAlertsDB or {}; place()
        for _,e in ipairs({"PLAYER_SWING","START_AUTOREPEAT_SPELL","STOP_AUTOREPEAT_SPELL","PLAYER_EQUIPMENT_CHANGED","PLAYER_REGEN_ENABLED"}) do self:RegisterEvent(e) end
        self:RegisterUnitEvent("UNIT_RANGEDDAMAGE","player")
    elseif event=="START_AUTOREPEAT_SPELL" then
        state.active=true -- Resume Shoot without erasing the last actual shot.
    elseif event=="STOP_AUTOREPEAT_SPELL" then
        state.active=false -- Movement stops firing, not the last shot's countdown.
    elseif event=="PLAYER_EQUIPMENT_CHANGED" and a==18 then state.active=false; reset()
    elseif event=="PLAYER_REGEN_ENABLED" then state.active=false; reset(); place()
    elseif event=="PLAYER_SWING" then
        if hidden(b) then return end
        local ranged=Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged or 2
        if b~=ranged then return end
        local duration=not hidden(a) and type(a)=="number" and a>0 and a or speed()
        if not duration then reset(); return end
        state.active=true; state.start=GetTime(); state.duration=duration
        state.speed=speed(); bar:SetMinMaxValues(0,duration)
    elseif event=="UNIT_RANGEDDAMAGE" and a=="player" then
        local nextSpeed=speed(); local now=GetTime()
        if nextSpeed and state.speed and state.start+state.duration>now then
            state.duration=now-state.start+(state.start+state.duration-now)*nextSpeed/state.speed
            bar:SetMinMaxValues(0,state.duration)
        end
        state.speed=nextSpeed
    end
end)
local textAt=0
driver:SetScript("OnUpdate",function()
    local db=DBagsAlertsDB or {}; local now=GetTime()
    local left=state.start+state.duration-now
    if state.duration<=0 or (db.off and db.off.swing)
        or (not state.active and left < -8) then bar:Hide(); return end
    bar:Show()
    if left<=0 then
        bar:SetValue(state.duration)
        bar:SetStatusBarColor(0.25,0.85,0.4)
        text:SetText("Wand ready")
    else
        bar:SetStatusBarColor(0.35,0.65,1)
        bar:SetValue(now-state.start)
        if now-textAt>=0.05 then textAt=now; text:SetFormattedText("Wand  %.1f",left) end
    end
end)
