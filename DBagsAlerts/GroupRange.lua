-- Same-map group warning based only on verified, readable distance measurements.
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local state = { variants = {}, status = "Not grouped" }
DBagsAlertsState.groupRange = state
local root = CreateFrame("Frame", nil, UIParent)
root:SetSize(440, 96); root:SetFrameStrata("HIGH")
root:SetPoint("CENTER", UIParent, "CENTER", 0, 60); root:EnableMouse(false); root:Hide()
state.frame = root
local pulse = root:CreateAnimationGroup(); pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1); fade:SetToAlpha(0.6); fade:SetDuration(3)
local playing = false
local function hide()
    root:Hide()
    if DBagsAlertsState.setHealerRangeProofs then DBagsAlertsState.setHealerRangeProofs(nil) end
    if playing then pulse:Stop(); playing = false end
end
local function variant(i)
    if state.variants[i] then return state.variants[i] end
    local v = {}; local parent = root
    v.frame = parent
    -- Actual red gradients: no dependency on an optional fullscreen texture.
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) ~= "number" then width = 1920 end
    if type(height) ~= "number" then height = 1080 end
    local function screenEdge(side, direction, reverse)
        local t = parent:CreateTexture(nil, "BACKGROUND")
        t:SetBlendMode("ADD") -- Red light only: never darken the world or corners.
        t:SetColorTexture(1, 0, 0, 0.48)
        if side == "LEFT" or side == "RIGHT" then
            t:SetPoint("TOP" .. side, UIParent, "TOP" .. side)
            t:SetPoint("BOTTOM" .. side, UIParent, "BOTTOM" .. side); t:SetWidth(width * 0.22)
        else
            t:SetPoint(side .. "LEFT", UIParent, side .. "LEFT")
            t:SetPoint(side .. "RIGHT", UIParent, side .. "RIGHT"); t:SetHeight(height * 0.22)
        end
        if CreateColor and t.SetGradient then
            t:SetColorTexture(1, 1, 1, 1)
            local red, clear = CreateColor(1, 0, 0, 0.65), CreateColor(1, 0, 0, 0)
            t:SetGradient(direction, reverse and clear or red, reverse and red or clear)
        end
        return t
    end
    v.edges = {screenEdge("LEFT", "HORIZONTAL", false), screenEdge("RIGHT", "HORIZONTAL", true),
        screenEdge("TOP", "VERTICAL", true), screenEdge("BOTTOM", "VERTICAL", false)}
    local edge = v.edges[1]
    local title = parent:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 48, "THICKOUTLINE")
    title:SetTextColor(1, 0.3, 0.12); title:SetPoint("TOP", 0, 0); title:SetText("WAKE UP")
    local detail = parent:CreateFontString(nil, "OVERLAY")
    detail:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    detail:SetTextColor(1, 0.9, 0.65); detail:SetPoint("TOP", title, "BOTTOM", 0, -8); detail:SetText("GROUP TOO FAR")
    v.title, v.detail, v.edge = title, detail, edge
    state.variants[i] = v
    return v
end
local candidateSince
local function config()
    DBagsAlertsDB = DBagsAlertsDB or {}
    DBagsAlertsDB.partyDefensives = DBagsAlertsDB.partyDefensives or {}
    local c = DBagsAlertsDB.partyDefensives
    if c.groupRange == nil then c.groupRange = false end
    c.muteSeconds = math.max(10,math.min(300,tonumber(c.muteSeconds) or 60))
    return c
end
local function mapFor(unit)
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, unit)
    id = ok and plain(id)
    if type(id) == "number" and id > 0 then return id end
end
local function measuredRange(unit)
    if UnitDistanceSquared then
        local ok, distance, checked = pcall(UnitDistanceSquared, unit)
        distance, checked = plain(distance), plain(checked)
        if ok and checked == true and type(distance) == "number" and distance >= 0 then
            return distance <= 1600, true, math.sqrt(distance), "distance"
        end
    end
    if UnitPosition then
        local okP, px, py, pz, pm = pcall(UnitPosition, "player")
        local okU, x, y, z, map = pcall(UnitPosition, unit)
        px, py, pz, pm = plain(px), plain(py), plain(pz), plain(pm)
        x, y, z, map = plain(x), plain(y), plain(z), plain(map)
        if okP and okU and type(pm) == "number" and pm == map
            and type(px) == "number" and type(py) == "number" and type(pz) == "number"
            and type(x) == "number" and type(y) == "number" and type(z) == "number" then
            local distance = (x-px)^2 + (y-py)^2 + (z-pz)^2
            return distance <= 1600, true, math.sqrt(distance), "position"
        end
    end
    -- A missing measurement is not evidence that a teammate is far away.
    return nil, false, nil, "unavailable"
end
local function update()
    local c=config()
    local function quiet(reason)
        candidateSince=nil;state.status=reason;hide()
    end
    if state.mutedUntil and GetTime()<state.mutedUntil then
        quiet(string.format("Paused for %ds",math.ceil(state.mutedUntil-GetTime())));return
    end
    if DBagsAlertsState.isSettingsOpen and DBagsAlertsState.isSettingsOpen() then quiet("Paused while settings are open");return end
    if not c.groupRange or not IsInGroup() or IsInRaid() then quiet(c.groupRange and "Small parties only" or "Off");return end
    -- Rest areas cover capitals, inns and resting parts of towns. No distance
    -- scans or screen pulse while the player is taking a break there.
    if IsResting and plain(IsResting())==true then quiet("Paused in a resting area");return end
    local count=plain(GetNumGroupMembers())
    if not count or count<2 or count>5 or plain(UnitIsDeadOrGhost("player")) then quiet("Not eligible");return end
    local playerMap=mapFor("player");state.mapID=playerMap
    if not playerMap then quiet("Current map unavailable");return end
    if playerMap>=1453 and playerMap<=1458 then quiet("Paused in a capital city");return end
    local total,far,unknown=0,0,0
    state.snapshot={}
    for i=1,4 do
        local unit="party"..i
        if plain(UnitExists(unit)) then
            local name=plain(UnitName(unit));local map=mapFor(unit)
            local e={unit=unit,name=name or unit,mapID=map,included=false};state.snapshot[#state.snapshot+1]=e
            local connected=UnitIsConnected and plain(UnitIsConnected(unit));local dead=plain(UnitIsDeadOrGhost(unit))
            if map==playerMap and connected~=false and dead~=true then
                total=total+1;e.included=true
                local inside,checked,distance,source=measuredRange(unit)
                e.distance,e.checked,e.source=distance,checked,source
                if connected==true and dead==false and checked==true then
                    e.far=inside==false
                    if e.far then far=far+1 end
                else unknown=unknown+1 end
            end
        end
    end
    state.members,state.required,state.far,state.unknown=total,math.floor(total/2)+1,far,unknown
    if total==0 then quiet("No same-map teammates");return end
    local wants=far>=state.required
    state.status=string.format("%d/%d same-map teammates beyond 40 yd; %d unknown",far,total,unknown)
    -- Unknown measurements cannot activate the warning. Hide the entire frame,
    -- rather than relying on a chain of transparent child frames.
    if not wants then quiet(state.status);return end
    candidateSince=candidateSince or GetTime()
    if GetTime()-candidateSince<2 then hide();return end
    variant(1)
    root:SetScale(1);root:Show()
    if DBagsAlertsState.setHealerRangeProofs then DBagsAlertsState.setHealerRangeProofs({}) end
    if not playing then pulse:Play();playing=true end
end
local function refresh()
    local ok, err = pcall(update)
    if not ok then
        hide(); state.status = "Group range: " .. tostring(err)
        if state.lastError ~= state.status then
            state.lastError = state.status
            if geterrorhandler then geterrorhandler()(state.status) end
        end
    end
end
state.update = refresh
state.snooze=function(seconds)
    local duration=math.max(10,math.min(300,tonumber(seconds) or config().muteSeconds))
    state.mutedUntil=GetTime()+duration;candidateSince=nil;hide()
    state.status=string.format("WAKE UP paused for %ds",duration)
    print("DBagsAlerts: "..state.status)
end
local muteButton=CreateFrame("Button","DBagsAlertsMuteWakeButton",UIParent)
muteButton:SetSize(1,1);muteButton:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",-24,-24)
muteButton:RegisterForClicks("AnyDown","AnyUp")
muteButton:SetScript("OnClick",function(_,_,down) if down~=false then state.snooze() end end)
state.muteButton=muteButton
_G["BINDING_NAME_CLICK DBagsAlertsMuteWakeButton:LeftButton"]="Pause WAKE UP"

DBagsAlertsState.openGroupRange=function()
    local c=config()
    local w=state.settings
    if not w then
        w=CreateFrame("Frame","DBagsAlertsGroupRangeSettings",UIParent);state.settings=w
        w:SetSize(370,330);w:SetPoint("CENTER");w:SetFrameStrata("DIALOG")
        DBagsAlertsState.prepareSettingsWindow(w,"group")
        DBagsAlertsState.settingsBackButton(w,DBagsAlertsState.openPartyDefensives)
        local bg=w:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0.055,0.055,0.065,1)
        local function text(label,x,y,size)
            local t=w:CreateFontString(nil,"OVERLAY");t:SetFont("Fonts\\FRIZQT__.TTF",size or 13,"OUTLINE")
            t:SetText(label);t:SetPoint("TOPLEFT",x,y);return t
        end
        local function button(label,x,y,width,fn)
            local b=CreateFrame("Button",nil,w,"UIPanelButtonTemplate");b:SetSize(width,26)
            b:SetPoint("TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",fn);return b
        end
        text("Group distance",18,-16,21)
        button("X",326,-10,30,function() w:Hide() end)
        w.enabled=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");w.enabled:SetPoint("TOPLEFT",12,-48)
        text("Enable WAKE UP",46,-57)
        w.enabled:SetScript("OnClick",function(self) config().groupRange=self:GetChecked() and true or false;refresh() end)
        local duration=text("",18,-98)
        w.duration=CreateFrame("Slider",nil,w,"OptionsSliderTemplate")
        w.duration:SetPoint("TOPLEFT",24,-125);w.duration:SetSize(310,18)
        w.duration:SetMinMaxValues(10,300);w.duration:SetValueStep(10);w.duration:SetObeyStepOnDrag(true)
        w.duration:SetScript("OnValueChanged",function(_,v)
            v=math.floor(v/10+0.5)*10;config().muteSeconds=v;duration:SetFormattedText("Pause for %d seconds",v)
        end)
        text("Pause key",18,-163)
        local action="CLICK DBagsAlertsMuteWakeButton:LeftButton"
        w.bind=button("Set key",24,-184,242,function() end)
        w.status=text("",18,-235,12);w.status:SetWidth(334)
        local capture=CreateFrame("Frame",nil,w);capture:SetAllPoints(w.bind);capture:Hide()
        capture:SetPropagateKeyboardInput(false)
        local pending
        local function label()
            local key=GetBindingKey and GetBindingKey(action);w.bind:SetText(key or "Set key")
        end
        local function finish() capture:EnableKeyboard(false);capture:Hide();pending=nil;label() end
        local function saveBindings()
            if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
        end
        capture:SetScript("OnKeyDown",function(_,key)
            if key=="ESCAPE" then finish();w.status:SetText("Key unchanged.");return end
            if key=="LSHIFT" or key=="RSHIFT" or key=="LCTRL" or key=="RCTRL" or key=="LALT" or key=="RALT" then return end
            if InCombatLockdown() then finish();w.status:SetText("Set key after combat.");return end
            key=(IsControlKeyDown and IsControlKeyDown() and "CTRL-" or "")
                ..(IsAltKeyDown and IsAltKeyDown() and "ALT-" or "")..(IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or "")..key
            local oldAction=GetBindingAction and GetBindingAction(key)
            if oldAction and oldAction~="" and oldAction~=action and pending~=key then
                pending=key;w.status:SetText(key.." is already bound. Press again to replace.");return
            end
            local old1,old2;if GetBindingKey then old1,old2=GetBindingKey(action) end
            if not SetBindingClick or not SetBindingClick(key,"DBagsAlertsMuteWakeButton","LeftButton") then w.status:SetText("Could not save key.");return end
            for _,old in pairs({old1,old2}) do if old~=key and GetBindingAction(old)==action then SetBinding(old) end end
            saveBindings();finish();w.status:SetText("Pause key saved: "..key)
        end)
        w.bind:SetScript("OnClick",function()
            if InCombatLockdown() then w.status:SetText("Set key after combat.");return end
            pending=nil;capture:Show();capture:EnableKeyboard(true)
            w.bind:SetText("Press a key...");w.status:SetText("Press a key combination. Escape cancels.")
        end)
        button("Clear",282,-184,66,function()
            if InCombatLockdown() then w.status:SetText("Clear key after combat.");return end
            if GetBindingKey then local a,b=GetBindingKey(action)
                for _,key in pairs({a,b}) do if GetBindingAction(key)==action then SetBinding(key) end end
            end
            saveBindings();finish();w.status:SetText("Pause key cleared.")
        end)
        w:SetScript("OnHide",finish)
        capture:RegisterEvent("PLAYER_REGEN_DISABLED");capture:SetScript("OnEvent",finish)
        w.bindingCapture=capture;w.refreshBinding=label
        local resume=button("Resume now",246,-290,102,function()
            state.mutedUntil=nil;candidateSince=nil;refresh();w.status:SetText("WAKE UP resumed")
        end)
        table.insert(UISpecialFrames,"DBagsAlertsGroupRangeSettings")
    end
    w.enabled:SetChecked(c.groupRange);w.duration:SetValue(c.muteSeconds);w.refreshBinding()
    w.status:SetText(state.status);DBagsAlertsState.showSettingsWindow(w,"group")
end
SLASH_DBAGSGROUP1 = "/dbagroup"
SlashCmdList.DBAGSGROUP = function(msg)
    if type(msg)~="string" or not msg:lower():match("^%s*status%s*$") then DBagsAlertsState.openGroupRange();return end
    refresh(); print("DBagsAlerts: " .. state.status)
    for _, e in ipairs(state.snapshot or {}) do
        print(string.format("%s: map %s, %s, %s", e.name, tostring(e.mapID or "unknown"),
            e.included and "counted" or "excluded", e.distance and string.format("%.1f yd", e.distance) or "distance unknown"))
    end
end
local elapsed = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.5 then return end
    elapsed = 0; refresh()
end)
