-- One hardware keypress invokes Blizzard's native FollowUnit. Never resumes itself.
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local state = {status="Choose a buddy", following=false}
DBagsAlertsState.followBuddy = state
_G.BINDING_HEADER_DBAGSALERTS = "DBagsAlerts"
_G["BINDING_NAME_CLICK DBagsAlertsFollowButton:LeftButton"] = "Follow buddy"
local function config()
    DBagsAlertsDB = DBagsAlertsDB or {}
    if type(DBagsAlertsDB.followBuddy) ~= "table" then DBagsAlertsDB.followBuddy = {enabled=false,name=""} end
    local c = DBagsAlertsDB.followBuddy
    if c.enabled == nil then c.enabled = false end
    if c.statusLocked == nil then c.statusLocked = false end
    if type(c.name) ~= "string" then c.name = "" end
    return c
end
local function valid(name)
    if #name>80 or name:find("%c") then return false end
    for _, bad in ipairs({"/",";","[","]"}) do if name:find(bad,1,true) then return false end end
    return true
end
local function normalized(name) return name:lower():gsub("[%s%-]", "") end
local function fullName(unit)
    local name, realm = UnitName(unit); name, realm = plain(name), plain(realm)
    if type(name) ~= "string" then return end
    return name .. (type(realm)=="string" and realm~="" and ("-"..realm) or ""), name
end
local button = CreateFrame("Button", "DBagsAlertsFollowButton", UIParent)
button:SetSize(1,1); button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
button:RegisterForClicks("AnyDown", "AnyUp")
-- Follow is a normal Blizzard interaction, not a secure macro action.
state.button = button
local hud = CreateFrame("Frame", nil, UIParent)
hud:SetSize(300,36); hud:SetPoint("CENTER", UIParent, "CENTER", 0,160); hud:SetFrameStrata("HIGH"); hud:Hide()
hud:SetMovable(true);hud:SetClampedToScreen(true);hud:RegisterForDrag("LeftButton")
hud:SetScript("OnDragStart",function(self) if not config().statusLocked then self:StartMoving() end end)
hud:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing();local p,_,rp,x,y=self:GetPoint();config().hudPoint={p,rp,x,y}
end)
local function placeHud()
    local c=config();local pos=c.hudPoint
    if type(pos)=="table" and type(pos[1])=="string" then
        hud:ClearAllPoints();hud:SetPoint(pos[1],UIParent,pos[2],pos[3],pos[4])
    end
    hud:EnableMouse(not c.statusLocked)
end
placeHud()
hud.title = hud:CreateFontString(nil,"OVERLAY"); hud.title:SetFont("Fonts\\FRIZQT__.TTF",15,"OUTLINE")
hud.title:SetPoint("TOP"); hud.name = hud:CreateFontString(nil,"OVERLAY")
hud.name:SetFont("Fonts\\FRIZQT__.TTF",12,"OUTLINE"); hud.name:SetPoint("TOP",hud.title,"BOTTOM",0,-3)
state.frame = hud
local pendingUntil, noticeUntil
local function show(title, name, r,g,b)
    hud.title:SetText(title); hud.title:SetTextColor(r,g,b); hud.name:SetText(name or "")
    hud:SetScale((DBagsAlertsDB.scale or 1) * (DBagsAlertsState.partScale and DBagsAlertsState.partScale("helpers") or 1));hud:EnableMouse(not config().statusLocked);hud:Show()
end
local function apply()
    local c=config();local typed=c.name:match("^%s*(.-)%s*$")
    if not c.enabled or typed=="" or not valid(typed) then
        state.target=nil;state.unit=nil
        state.status=not c.enabled and "Off" or "Enter a character name";return false
    end
    local wanted=normalized(typed);local matches={}
    local raid=IsInRaid();local count=raid and GetNumGroupMembers() or 4
    for i=1,count do
        local unit=(raid and "raid" or "party")..i
        if plain(UnitExists(unit)) and not plain(UnitIsUnit(unit,"player")) then
            local full,short=fullName(unit)
            if full and (normalized(full)==wanted or normalized(short)==wanted) then matches[#matches+1]={name=full,unit=unit} end
        end
    end
    local target
    if #matches>1 then
        state.target=nil;state.unit=nil;state.status="Multiple matches: enter the full name";return false
    elseif #matches==1 then target=matches[1].name
    else target=typed end
    state.unit=#matches==1 and matches[1].unit or nil
    state.target=target;state.status=#matches==1 and ("Buddy found: "..target) or ("Will try nearby player: "..target)
    return true
end
state.apply=apply
button:SetScript("OnClick",function(_, _, down)
    if down == false then return end -- Release must not start another pending request.
    local c=config()
    apply() -- Resolve the name again on this physical keypress; party slots can change.
    if not c.enabled or not state.target then
        show("SET FOLLOW BUDDY","Open /dbafollow",1,0.65,0.2);noticeUntil=GetTime()+4;return
    end
    if state.following and state.followingName and normalized(state.followingName)==normalized(state.target) then
        show("FOLLOWING",state.followingName,0.3,1,0.4);return
    end
    pendingUntil=GetTime()+2;show("FOLLOW REQUESTED",state.target,1,0.82,0.25)
    if FollowUnit then
        -- Same action as Blizzard's /follow. Called only by this hardware click.
        local ok,err=pcall(FollowUnit,state.unit or state.target)
        if not ok then
            pendingUntil=nil;noticeUntil=GetTime()+5;state.status="Follow blocked: "..tostring(err)
            show("FOLLOW FAILED","WoW blocked the follow action",1,0.4,0.2)
        end
    else
        pendingUntil=nil;noticeUntil=GetTime()+5;show("FOLLOW FAILED","Follow unavailable",1,0.4,0.2)
    end
end)
local driver=CreateFrame("Frame")
for _,e in ipairs({"PLAYER_LOGIN","GROUP_ROSTER_UPDATE","PLAYER_REGEN_ENABLED","AUTOFOLLOW_BEGIN","AUTOFOLLOW_END","UI_ERROR_MESSAGE"}) do driver:RegisterEvent(e) end
driver:SetScript("OnEvent",function(_,event,name,message)
    if event=="AUTOFOLLOW_BEGIN" then
        pendingUntil=nil;noticeUntil=nil;state.following=true;state.followingName=plain(name) or state.target or "Buddy"
        state.status="Following "..state.followingName;show("FOLLOWING",state.followingName,0.3,1,0.4)
    elseif event=="AUTOFOLLOW_END" then
        pendingUntil=nil;state.following=false;noticeUntil=GetTime()+4
        state.status="Follow stopped";show("FOLLOW STOPPED",state.followingName or state.target,1,0.55,0.2)
    elseif event=="UI_ERROR_MESSAGE" then
        if pendingUntil and type(plain(message))=="string" then
            pendingUntil=nil;noticeUntil=GetTime()+5;state.status=message
            show("FOLLOW FAILED",message,1,0.4,0.2)
        end
    else apply() end
end)
local elapsed=0
driver:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+dt;if elapsed<0.25 then return end;elapsed=0
    if pendingUntil and GetTime()>=pendingUntil then
        pendingUntil=nil;noticeUntil=GetTime()+4
        state.status="Follow did not start: get closer and press your key again"
        show("FOLLOW NOT STARTED",state.target,1,0.4,0.2)
    elseif noticeUntil and GetTime()>=noticeUntil then noticeUntil=nil;if not state.following then hud:Hide() end end
end)
local window
DBagsAlertsState.openFollowBuddy=function()
    local c=config()
    if not window then
        local w=CreateFrame("Frame","DBagsAlertsFollowSettings",UIParent);window=w
        w:SetSize(370,390);w:SetPoint("CENTER");w:SetFrameStrata("DIALOG")
        DBagsAlertsState.prepareSettingsWindow(w, "follow")
        DBagsAlertsState.settingsBackButton(w, DBagsAlertsState.openPartyDefensives)
        local bg=w:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0.055,0.055,0.065,1)
        local function text(label,x,y,size)
            local t=w:CreateFontString(nil,"OVERLAY");t:SetFont("Fonts\\FRIZQT__.TTF",size or 13,"OUTLINE")
            t:SetText(label);t:SetPoint("TOPLEFT",x,y);return t
        end
        text("Follow buddy",18,-16,21)
        local close=CreateFrame("Button",nil,w,"UIPanelButtonTemplate");close:SetSize(28,24)
        close:SetPoint("TOPRIGHT",-10,-10);close:SetText("X");close:SetScript("OnClick",function() w:Hide() end)
        w.enabled=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");w.enabled:SetPoint("TOPLEFT",12,-48)
        text("Enable follow key",46,-57)
        w.enabled:SetScript("OnClick",function(self)
            if InCombatLockdown() then self:SetChecked(config().enabled);w.status:SetText("Change settings after combat.");return end
            config().enabled=self:GetChecked() and true or false;apply();w.status:SetText(state.status)
        end)
        text("Character name",18,-98)
        w.entry=CreateFrame("EditBox",nil,w,"InputBoxTemplate");w.entry:SetSize(242,24)
        w.entry:SetPoint("TOPLEFT",24,-120);w.entry:SetAutoFocus(false);w.entry:SetMaxLetters(80)
        local function save()
            if InCombatLockdown() then w.status:SetText("Save after combat.");return end
            local name=w.entry:GetText():match("^%s*(.-)%s*$")
            if not valid(name) then w.status:SetText("Use a character name.");return end
            config().name=name;w.entry:ClearFocus();apply();w.status:SetText(state.status)
        end
        w.entry:SetScript("OnEnterPressed",save);w.entry:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        local saveButton=CreateFrame("Button",nil,w,"UIPanelButtonTemplate");saveButton:SetSize(66,26)
        saveButton:SetPoint("TOPLEFT",282,-120);saveButton:SetText("Save");saveButton:SetScript("OnClick",save)
        text("Follow key",18,-164)
        local action="CLICK DBagsAlertsFollowButton:LeftButton"
        w.bind=CreateFrame("Button",nil,w,"UIPanelButtonTemplate")
        w.bind:SetSize(242,28);w.bind:SetPoint("TOPLEFT",24,-184)
        local clear=CreateFrame("Button",nil,w,"UIPanelButtonTemplate")
        clear:SetSize(66,28);clear:SetPoint("TOPLEFT",282,-184);clear:SetText("Clear")
        w.status=text("",18,-236,12);w.status:SetWidth(334)
        local capture=CreateFrame("Frame",nil,w)
        capture:SetAllPoints(w.bind);capture:SetFrameStrata("DIALOG");capture:Hide()
        capture:SetPropagateKeyboardInput(false)
        local pendingKey
        w.refreshBinding=function()
            local key=GetBindingKey and GetBindingKey(action)
            w.bind:SetText(key and ((GetBindingText and GetBindingText(key,"KEY_")) or key) or "Set key")
        end
        local function finish()
            pendingKey=nil;capture:EnableKeyboard(false);capture:Hide();w.refreshBinding()
        end
        local function persist()
            if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
        end
        local function accept(key)
            if InCombatLockdown() then finish();w.status:SetText("Set the key after combat.");return end
            local oldAction=GetBindingAction and GetBindingAction(key)
            if oldAction and oldAction~="" and oldAction~=action and pendingKey~=key then
                pendingKey=key
                local label=(GetBindingText and GetBindingText(oldAction,"BINDING_NAME_")) or oldAction
                w.status:SetText(key.." is "..label..". Press again to replace.");return
            end
            local old1,old2
            if GetBindingKey then old1,old2=GetBindingKey(action) end
            if not SetBindingClick or not SetBindingClick(key,"DBagsAlertsFollowButton","LeftButton") then
                w.status:SetText("That key could not be saved. Try another.");return
            end
            for _,old in pairs({old1,old2}) do
                if old~=key and (not GetBindingAction or GetBindingAction(old)==action) then SetBinding(old) end
            end
            persist();config().key=key;finish();w.status:SetText("Follow key saved: "..key)
        end
        capture:SetScript("OnKeyDown",function(_,key)
            if key=="ESCAPE" then finish();w.status:SetText("Key unchanged.");return end
            if key=="LSHIFT" or key=="RSHIFT" or key=="LCTRL" or key=="RCTRL" or key=="LALT" or key=="RALT" then return end
            local chord=(IsControlKeyDown and IsControlKeyDown() and "CTRL-" or "")
                ..(IsAltKeyDown and IsAltKeyDown() and "ALT-" or "")
                ..(IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or "")..key
            accept(chord)
        end)
        w.bind:SetScript("OnClick",function()
            if InCombatLockdown() then w.status:SetText("Set the key after combat.");return end
            w.entry:ClearFocus();pendingKey=nil;capture:Show();capture:EnableKeyboard(true)
            w.bind:SetText("Press a key...");w.status:SetText("Press your key combination. Escape cancels.")
        end)
        clear:SetScript("OnClick",function()
            if InCombatLockdown() then w.status:SetText("Clear the key after combat.");return end
            if GetBindingKey then
                local a,b=GetBindingKey(action)
                for _,key in pairs({a,b}) do
                    if not GetBindingAction or GetBindingAction(key)==action then SetBinding(key) end
                end
            end
            persist();config().key=nil;finish();w.status:SetText("Follow key cleared.")
        end)
        local lockStatus=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate")
        lockStatus:SetPoint("TOPLEFT",12,-278);text("Lock follow status",46,-287)
        lockStatus:SetScript("OnClick",function(self) config().statusLocked=self:GetChecked() and true or false;placeHud() end)
        w.lockStatus=lockStatus
        local moveStatus=CreateFrame("Button",nil,w,"UIPanelButtonTemplate")
        moveStatus:SetSize(132,26);moveStatus:SetPoint("TOPLEFT",216,-278);moveStatus:SetText("Move status")
        moveStatus:SetScript("OnClick",function()
            config().statusLocked=false;lockStatus:SetChecked(false);placeHud()
            if not state.following then show("FOLLOW STATUS","Drag this text",0.3,1,0.4);noticeUntil=GetTime()+15 end
        end)
        w:SetScript("OnHide",finish)
        capture:RegisterEvent("PLAYER_REGEN_DISABLED")
        capture:SetScript("OnEvent",function() finish() end)
        state.bindingCapture,state.bindingButton,state.clearBinding=capture,w.bind,clear
        table.insert(UISpecialFrames,"DBagsAlertsFollowSettings")
    end
    window.enabled:SetChecked(c.enabled);window.entry:SetText(c.name);window.status:SetText(state.status)
    window.refreshBinding();window.lockStatus:SetChecked(c.statusLocked)
    DBagsAlertsState.showSettingsWindow(window, "follow")
end
SLASH_DBAGSFOLLOW1="/dbafollow"
SlashCmdList.DBAGSFOLLOW=DBagsAlertsState.openFollowBuddy
