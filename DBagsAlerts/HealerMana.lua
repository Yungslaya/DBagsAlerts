-- Pre-pull healer mana warning. Uses normal group roles and readable mana only.
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local FONT = "Fonts\\FRIZQT__.TTF"
local state = { status = "Not grouped" }
DBagsAlertsState.healerMana = state
local function config()
    if not DBagsAlertsDB then return end
    local c = DBagsAlertsDB.healerMana
    if type(c) ~= "table" then c = {}; DBagsAlertsDB.healerMana = c end
    if c.enabled == nil then c.enabled = true end
    if c.drinking == nil then c.drinking = true end
    if c.range == nil then c.range = true end
    c.threshold = math.max(5, math.min(90, tonumber(c.threshold) or 30))
    if type(c.name) ~= "string" then c.name = "" end
    return c
end
local function normalize(name)
    return name:match("^%s*(.-)%s*$"):lower():gsub("%s+", "")
end
local function tank()
    local _, cls = UnitClass("player"); cls = plain(cls)
    if cls ~= "WARRIOR" and cls ~= "PALADIN" and cls ~= "DRUID" then return false end
    if cls == "PALADIN" and DBagsAlertsDB.tank == false then return false end
    if UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned("player")) == "TANK" then return true end
    if cls == "DRUID" then
        local id = plain(GetShapeshiftFormID and GetShapeshiftFormID())
        return id == 5 or id == 8
    end
    -- Forever's spec-role result can be a generic DPS role at low levels.
    -- Learned Protection talents are stronger evidence for our Warrior setup.
    if cls == "WARRIOR" and DBagsAlertsState.tankSetup and DBagsAlertsState.tankSetup() then return true end
    local api = C_SpecializationInfo
    if api and api.GetSpecialization and api.GetSpecializationInfo then
        local ok, index = pcall(api.GetSpecialization)
        index = ok and plain(index)
        if index then
            local okI, _, _, _, _, role = pcall(api.GetSpecializationInfo, index)
            role = okI and plain(role)
            if role == "TANK" then return true end
            if role == "HEALER" or role == "DAMAGER" then return false end
        end
    end
    return DBagsAlertsState.tankSetup and DBagsAlertsState.tankSetup() or false
end
local f = CreateFrame("Frame", nil, UIParent)
-- Same 40px icon, gold glow and Friz font as the floating combat helpers.
f:SetSize(260, 44)
f:SetPoint("BOTTOM", DBagsAlertsState.main, "TOP", 0, 50)
f:SetFrameStrata("HIGH"); f:Hide()
f.icon = f:CreateTexture(nil, "ARTWORK")
f.icon:SetSize(40, 40); f.icon:SetPoint("LEFT")
f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
f.icon:SetTexture("Interface\\Icons\\Spell_Holy_Heal")
f.glow = CreateFrame("Frame", nil, f)
f.glow:SetPoint("CENTER", f.icon, "CENTER"); f.glow:SetSize(40 / 0.64, 40 / 0.64)
f.glow.t = f.glow:CreateTexture(nil, "OVERLAY")
f.glow.t:SetAllPoints(); f.glow.t:SetTexture("Interface\\AddOns\\DBagsAlerts\\Media\\ProcGlow.tga")
f.glow.t:SetBlendMode("ADD"); f.glow.t:SetVertexColor(1, 0.82, 0.25)
f.title = f:CreateFontString(nil, "OVERLAY")
f.title:SetFont(FONT, 18, "OUTLINE"); f.title:SetPoint("TOPLEFT", 50, -1)
f.title:SetTextColor(1, 0.82, 0.25); f.title:SetText("LOW MANA")
f.detail = f:CreateFontString(nil, "OVERLAY")
f.detail:SetFont(FONT, 13, "OUTLINE"); f.detail:SetPoint("TOPLEFT", 50, -22)
f.detail:SetWidth(210); f.detail:SetJustifyH("LEFT"); f.detail:SetWordWrap(false)
f.detail:SetTextColor(0.92, 0.92, 0.92)
f.bar = CreateFrame("StatusBar", nil, f)
f.bar:SetPoint("TOPLEFT", 50, -40); f.bar:SetSize(150, 3)
f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
f.bar:SetStatusBarColor(0.2, 0.5, 1); f.bar:SetMinMaxValues(0, 100)
local pulse = f.glow:CreateAnimationGroup(); pulse:SetLooping("BOUNCE")
local alpha = pulse:CreateAnimation("Alpha")
alpha:SetFromAlpha(1); alpha:SetToAlpha(0.35); alpha:SetDuration(0.55)
state.frame = f
-- Independent range badge: its alpha must not inherit the mana threshold.
local rangeFrame = CreateFrame("Frame", nil, UIParent)
rangeFrame:SetSize(210, 36); rangeFrame:SetFrameStrata("HIGH"); rangeFrame:Hide()
local rangeGate = CreateFrame("Frame", nil, rangeFrame); rangeGate:SetAllPoints()
local rangeIcon = rangeGate:CreateTexture(nil, "ARTWORK")
rangeIcon:SetSize(28, 28); rangeIcon:SetPoint("LEFT")
rangeIcon:SetTexture("Interface\\Icons\\Ability_Hunter_Pathfinding")
rangeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local rangeTitle = rangeGate:CreateFontString(nil, "OVERLAY")
rangeTitle:SetFont(FONT, 16, "OUTLINE"); rangeTitle:SetTextColor(1, 0.4, 0.2)
rangeTitle:SetPoint("TOPLEFT", 36, 0); rangeTitle:SetText("TOO FAR")
local rangeName = rangeGate:CreateFontString(nil, "OVERLAY")
rangeName:SetFont(FONT, 12, "OUTLINE"); rangeName:SetTextColor(0.92, 0.92, 0.92)
rangeName:SetPoint("TOPLEFT", 36, -19); rangeName:SetWidth(174)
rangeName:SetJustifyH("LEFT"); rangeName:SetWordWrap(false)
state.rangeFrame, state.rangeGate = rangeFrame, rangeGate
local showing = false
local function hideMain()
    if showing then pulse:Stop(); showing = false end
    f:Hide(); f:SetAlpha(1)
end
local function hide()
    hideMain(); rangeFrame:Hide()
end
local roster, selected, selectedName = {}, nil, nil
local dirty, scanAt, lastName = true, 0, nil
local function resolve(c)
    wipe(roster); selected, selectedName = nil, nil
    local raid = IsInRaid and IsInRaid()
    local n = raid and GetNumGroupMembers() or 4
    local matches, roles = {}, {}
    local wanted = normalize(c.name)
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        if plain(UnitExists(unit)) and not plain(UnitIsUnit(unit, "player")) then
            local name, realm = UnitName(unit)
            name, realm = plain(name), plain(realm)
            if name then
                local full = name .. (realm and realm ~= "" and ("-" .. realm) or "")
                roster[unit] = full
                if wanted ~= "" then
                    local candidate = normalize(wanted:find("-", 1, true) and full or name)
                    if candidate == wanted then matches[#matches + 1] = unit end
                elseif UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned(unit)) == "HEALER" then
                    roles[#roles + 1] = unit
                end
            end
        end
    end
    local candidates = wanted ~= "" and matches or roles
    if #candidates == 1 then
        selected = candidates[1]; selectedName = roster[selected]
        state.status = "Healer: " .. selectedName
    elseif #candidates > 1 then
        state.status = "Multiple matches. Enter Name-Realm."
        if wanted == "" then state.status = "Multiple healers. Enter your healer's name." end
    elseif wanted ~= "" then state.status = "Name not found in your group."
    else state.status = "No healer marked. Enter their name." end
    state.unit, state.name = selected, selectedName
end
-- Group range is not an exact distance or a line-of-sight check.
local function outsideRange(unit)
    if not UnitInRange then return nil, false end
    local ok, inside, checked = pcall(UnitInRange, unit)
    if not ok or (not secret(checked) and checked ~= true) then return nil, false end
    local function alpha(value, yes, no)
        if not secret(value) then
            if value == true then return true, yes end
            if value == false then return true, no end
            return false
        end
        if not C_CurveUtil or not C_CurveUtil.EvaluateColorValueFromBoolean then return false end
        return pcall(C_CurveUtil.EvaluateColorValueFromBoolean, value, yes, no)
    end
    local okOut, outAlpha = alpha(inside, 0, 1)
    local okCheck, checkedAlpha = alpha(checked, 1, 0)
    if not okOut or not okCheck then return nil, false end
    local out
    if not secret(inside) then out = not inside end
    return out, true, outAlpha, checkedAlpha
end
local drinkName
local function drinking(unit)
    local api = C_UnitAuras
    if not api then return nil end
    if not drinkName then
        local ok, name = false, nil
        if C_Spell and C_Spell.GetSpellName then ok, name = pcall(C_Spell.GetSpellName, 430) end
        drinkName = (ok and plain(name)) or "Drink"
    end
    local function readable(aura)
        return type(aura) == "table" and not secret(aura)
            and not (issecrettable and issecrettable(aura))
    end
    if api.GetAuraDataBySpellName then
        local ok, aura = pcall(api.GetAuraDataBySpellName, unit, drinkName, "HELPFUL")
        if not ok or secret(aura) or (aura and issecrettable and issecrettable(aura)) then return nil end
        return readable(aura) and true or false
    end
    if api.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(api.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or secret(aura) then return nil end
            if not aura then return false end
            if not readable(aura) then return nil end
            if plain(aura.name) == drinkName or plain(aura.spellId) == 430 then return true end
        end
    end
    return nil
end
-- Hand the threshold result directly to frame alpha; never inspect hidden mana.
local manaCurves = {}
local function nativeLowMana(unit, threshold)
    if not UnitPowerPercent or not C_CurveUtil or not C_CurveUtil.CreateCurve
        or not Enum or not Enum.LuaCurveType then return false end
    local curve = manaCurves[threshold]
    if not curve then
        curve = C_CurveUtil.CreateCurve(); curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 1); curve:AddPoint(threshold / 100, 0)
        manaCurves[threshold] = curve
    end
    local ok, value = pcall(UnitPowerPercent, unit, 0, false, curve)
    if not ok or (not secret(value) and type(value) ~= "number") then return false end
    return true, value
end
local low = false
local lastScale, lastIcon
local function check()
    local c = config()
    if state.previewUntil and GetTime() < state.previewUntil then
        rangeFrame:Hide()
        f.title:SetText("LOW MANA"); f.detail:SetText("Healer warning preview")
        f.bar:Show(); f.bar:SetValue(20); f:SetAlpha(1); f:Show()
        if not showing then showing = true; pulse:Play() end
        return
    end
    if not c or not c.enabled then state.status = "Off"; low = false; hide(); return end
    -- This is a pull warning, not a combat instruction. Never infer hidden mana.
    if InCombatLockdown() or plain(UnitAffectingCombat("player")) then state.status = "In combat: pre-pull alerts paused"; hide(); return end
    if not IsInGroup() then
        selected, selectedName = nil, nil; state.unit, state.name = nil, nil
        dirty = true; low = false; state.status = "Not grouped"; hide(); return
    end
    if not tank() then state.status = "Tank setups only"; low = false; hide(); return end
    if plain(UnitIsDeadOrGhost("player")) then hide(); return end
    local now = GetTime()
    if dirty or c.name ~= lastName or now >= scanAt then
        local old = selectedName
        resolve(c); dirty = false; lastName = c.name; scanAt = now + 2
        if old ~= selectedName then low = false end
    end
    if not selected then
        rangeFrame:Hide()
        low = false
        -- Missing/ambiguous group roles must not leave a tank silently unprotected.
        f.title:SetText("SET HEALER"); f.detail:SetText("Open /dbahealer")
        f.bar:Hide(); f:SetAlpha(1); f:Show()
        if not showing then showing = true; pulse:Play() end
        return
    end
    if (UnitIsConnected and plain(UnitIsConnected(selected)) ~= true)
        or plain(UnitIsDeadOrGhost(selected)) then
        state.status = "Healer unavailable"; low = false; hide(); return
    end
    local out, rangeValid, outAlpha, checkedAlpha
    if c.range then out, rangeValid, outAlpha, checkedAlpha = outsideRange(selected) end
    local drink = c.drinking and drinking(selected) or nil
    state.outOfRange, state.drinking = out, drink
    local mana, maximum = plain(UnitPower(selected, 0)), plain(UnitPowerMax(selected, 0))
    local pct
    if type(mana) == "number" and type(maximum) == "number" and maximum > 0 then
        pct = math.max(0, math.min(100, mana / maximum * 100))
    end
    state.percent = pct
    low = pct ~= nil and pct < (c.threshold + (low and 5 or 0)) or false
    local native, lowAlpha = false, nil
    if pct == nil then native, lowAlpha = nativeLowMana(selected, c.threshold) end
    local title
    if drink then title = "DRINKING"
    elseif low or native then title = "LOW MANA" end
    local detail = selectedName
    if pct then detail = detail .. string.format("  %.0f%%", pct) end
    state.status = (native and not drink) and ("Watching " .. selectedName .. ": native mana threshold")
        or (title and (title .. ": " .. detail))
        or (pct and string.format("%s: %.0f%% mana", selectedName, pct) or "Healer mana unavailable")
    if rangeValid then
        rangeFrame:ClearAllPoints()
        if title then rangeFrame:SetPoint("TOPLEFT", f, "TOPRIGHT", 12, -4)
        else rangeFrame:SetPoint("BOTTOM", DBagsAlertsState.main, "TOP", 0, 50) end
        rangeFrame:SetScale(DBagsAlertsDB.scale or 1)
        rangeName:SetText(selectedName)
        rangeFrame:SetAlpha(outAlpha); rangeGate:SetAlpha(checkedAlpha); rangeFrame:Show()
        state.status = state.status .. (out and " | TOO FAR" or " | group range monitored")
    else rangeFrame:Hide() end
    if not title then hideMain(); return end
    if native and not drink then f:SetAlpha(lowAlpha) else f:SetAlpha(1) end
    f.title:SetText(title); f.detail:SetText(detail)
    f.bar:SetShown(pct ~= nil)
    if pct then f.bar:SetValue(pct) end
    local scale = DBagsAlertsDB.scale or 1
    if scale ~= lastScale then f:SetScale(scale); lastScale = scale end
    local icon = drink and "Interface\\Icons\\INV_Drink_07" or "Interface\\Icons\\Spell_Holy_Heal"
    if icon ~= lastIcon then f.icon:SetTexture(icon); lastIcon = icon end
    f.glow:SetShown(DBagsAlertsDB.glow ~= false)
    f:Show()
    if not showing then showing = true; pulse:Play() end
end
local function refresh()
    local ok, err = pcall(check)
    if not ok then
        hide(); state.status = "Healer check error: " .. tostring(err)
        if state.lastError ~= state.status then
            state.lastError = state.status
            if geterrorhandler then geterrorhandler()(state.status) end
        end
    end
    if DBagsAlertsDB and DBagsAlertsDB.healerMana then DBagsAlertsDB.healerMana.lastStatus = state.status end
end
state.check = refresh
local driver = CreateFrame("Frame")
driver:RegisterEvent("GROUP_ROSTER_UPDATE"); driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_REGEN_DISABLED"); driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event)
    dirty = true
    if event == "PLAYER_REGEN_DISABLED" then hide() end
end)
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.5 then return end
    elapsed = 0
    refresh()
    if state.statusText then state.statusText:SetText(state.status) end
end)
local window
local function text(parent, label, size, x, y)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size, "OUTLINE"); t:SetText(label); t:SetPoint("TOPLEFT", x, y)
    return t
end
DBagsAlertsState.openHealerSettings = function()
    local c = config(); if not c then return end
    if not window then
        local w = CreateFrame("Frame", "DBagsAlertsHealerSettings", UIParent)
        window = w; w:SetSize(370, 356); w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG")
        local bg = w:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.07, 0.11, 0.98)
        text(w, "Healer checks", 21, 18, -16)
        local function button(label, x, y, width, action)
            local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
            b:SetSize(width, 26); b:SetPoint("TOPLEFT", x, y); b:SetText(label); b:SetScript("OnClick", action)
            return b
        end
        button("X", 326, -10, 30, function() w:Hide() end)
        button("Test", 254, -10, 64, function() state.previewUntil = GetTime() + 5; refresh() end)
        local enabled = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        enabled:SetPoint("TOPLEFT", 14, -49); text(w, "Warn before pulling (tanks only)", 13, 48, -58)
        enabled:SetScript("OnClick", function(self) config().enabled = self:GetChecked() and true or false; check() end)
        w.enabled = enabled
        text(w, "Healer name (blank = automatic)", 14, 18, -98)
        local entry = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
        entry:SetSize(244, 25); entry:SetPoint("TOPLEFT", 24, -121)
        entry:SetAutoFocus(false); entry:SetMaxLetters(80)
        local function save() config().name = entry:GetText():match("^%s*(.-)%s*$"); dirty = true; entry:ClearFocus(); check() end
        entry:SetScript("OnEnterPressed", save); entry:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        button("Save", 282, -121, 66, save); w.entry = entry
        local label = text(w, "", 14, 18, -162)
        local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 24, -192); slider:SetSize(310, 18)
        slider:SetMinMaxValues(5, 90); slider:SetValueStep(5); slider:SetObeyStepOnDrag(true)
        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / 5 + 0.5) * 5
            config().threshold = value; low = false
            label:SetFormattedText("Warn below %d%% mana", value); check()
        end)
        w.slider = slider
        local function toggle(label, key, y)
            local b = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
            b:SetPoint("TOPLEFT", 14, y); text(w, label, 13, 48, y - 9)
            b:SetScript("OnClick", function(self) config()[key] = self:GetChecked() and true or false; check() end)
            return b
        end
        w.drinking = toggle("Warn while healer drinks", "drinking", -217)
        w.range = toggle("Warn if healer is out of group range", "range", -248)
        local status = text(w, "", 12, 18, -287); status:SetWidth(332)
        state.statusText = status
        text(w, "Pre-pull only. Range does not check line of sight.", 11, 18, -329)
        table.insert(UISpecialFrames, "DBagsAlertsHealerSettings")
    end
    window.enabled:SetChecked(c.enabled); window.entry:SetText(c.name)
    window.drinking:SetChecked(c.drinking); window.range:SetChecked(c.range)
    window.slider:SetValue(c.threshold); check()
    state.statusText:SetText(state.status); window:Show()
end
SLASH_DBAGSHEALER1 = "/dbahealer"
SlashCmdList.DBAGSHEALER = function(msg)
    if type(msg) == "string" and msg:lower():match("^%s*status%s*$") then
        refresh(); print("DBagsAlerts healer: " .. state.status)
    else DBagsAlertsState.openHealerSettings() end
end
