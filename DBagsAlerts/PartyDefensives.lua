-- Party readiness from public self-reports, plus native active defensive auras.
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local function readable(t)
    return type(t) == "table" and not secret(t) and not (issecrettable and issecrettable(t))
end
local state = { rows = {}, status = "Outside a five-player dungeon" }
DBagsAlertsState.partyDefensives = state
local function config()
    DBagsAlertsDB = DBagsAlertsDB or {}
    local c = DBagsAlertsDB.partyDefensives
    if type(c) ~= "table" then c = {}; DBagsAlertsDB.partyDefensives = c end
    if c.enabled == nil then c.enabled = true end
    c.size = math.max(20, math.min(44, tonumber(c.size) or 28))
    if c.left == nil then c.left = false end
    if c.groupRange == nil then c.groupRange = true end
    if c.placeholders == nil then c.placeholders = true end
    return c
end
local function eligible(c)
    if not c.enabled or not IsInGroup() or IsInRaid() then return false end
    local count = plain(GetNumGroupMembers())
    if not count or count < 2 or count > 5 then return false end
    local inside, kind = IsInInstance()
    return plain(inside) == true and plain(kind) == "party"
end
local function visible(frame)
    if not frame then return false end
    if frame.IsVisible then return plain(frame:IsVisible()) == true end
    return plain(frame:IsShown()) == true
end
local function frameUnit(frame)
    if not frame then return end
    local unit = plain(frame.unit) or plain(frame.displayedUnit)
    if type(unit) == "string" then return unit end
    if frame.GetAttribute then return plain(frame:GetAttribute("unit")) end
end
local function matches(frame, unit)
    local token = frameUnit(frame)
    if token == unit then return true end
    return type(token) == "string" and UnitIsUnit and plain(UnitIsUnit(token, unit)) == true
end
local function findFrame(unit)
    -- Compact/raid-style party frames first; they include the player and can be role-sorted.
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if visible(frame) and matches(frame, unit) then return frame end
    end
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if visible(frame) and matches(frame, unit) then return frame end
    end
    local container = _G.CompactPartyFrame
    local frames = container and container.memberUnitFrames
    if readable(frames) then
        for _, frame in pairs(frames) do
            if visible(frame) and matches(frame, unit) then return frame end
        end
    end
    local party = _G.PartyFrame
    for i = 1, 4 do
        local frame = party and party["MemberFrame" .. i] or _G["PartyMemberFrame" .. i]
        if visible(frame) and (frameUnit(frame) or ("party" .. i)) == unit then return frame end
    end
    -- Some layouts nest their compact members instead of exporting global names.
    local budget = 80
    local function search(parent, depth)
        if not parent or depth > 3 or budget <= 0 then return end
        budget = budget - 1
        if visible(parent) and matches(parent, unit) then return parent end
        if parent.GetChildren then
            for _, child in ipairs({parent:GetChildren()}) do
                local found = search(child, depth + 1)
                if found then return found end
            end
        end
    end
    for _, name in ipairs({"CompactPartyFrame", "PartyFrame", "CompactRaidFrameContainer"}) do
        local found = search(_G[name], 0)
        if found then return found end
    end
    if unit == "player" and visible(_G.PlayerFrame) then return PlayerFrame end
end
local function rowFor(unit)
    if state.rows[unit] then return state.rows[unit] end
    -- These are independent, non-secure display frames. Never modify the party frame.
    local row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("HIGH"); row:Hide(); row.icons = {}; row.unit = unit
    for i = 1, 6 do
        local icon = CreateFrame("Frame", nil, row)
        icon.tex = icon:CreateTexture(nil, "ARTWORK"); icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local edge = icon:CreateTexture(nil, "BACKGROUND")
        edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(1, 0.82, 0.25, 0.9)
        icon.edge = edge
        icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.cd:SetAllPoints(); icon.cd:SetDrawEdge(false); icon.cd:SetDrawBling(false)
        icon.cd:SetHideCountdownNumbers(false); icon.cd:SetReverse(true)
        icon.label = icon:CreateFontString(nil, "OVERLAY")
        icon.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        icon.label:SetPoint("BOTTOM", 0, -2)
        icon:SetScript("OnEnter", function(self)
            if self.auraID and GameTooltip.SetUnitAuraByAuraInstanceID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitAuraByAuraInstanceID(row.unit, self.auraID); GameTooltip:Show()
            elseif self.entry then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.entry.name or "Defensive", 1, 0.82, 0.25)
                local status = self.entry.status
                GameTooltip:AddLine(self.entry.placeholder and "Not observed yet" or status == "R" and (self.entry.estimated and "Estimated ready" or "Cooldown ready") or status == "C" and (self.entry.estimated and "Estimated cooldown" or "On cooldown") or "Unknown", 1, 1, 1)
                GameTooltip:AddLine(self.entry.reason or "Readiness is cooldown only. Stance, equipment and resources may still be required.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:EnableMouse(true); icon:Hide(); row.icons[i] = icon
    end
    state.rows[unit] = row
    return row
end
local function hideAll()
    for _, row in pairs(state.rows) do row:Hide() end
end
-- Older Forever spells may not carry the retail BIG_DEFENSIVE category.
-- Only readable identities are matched; hidden fields are never decoded.
local defensiveNames = {}
for _, name in ipairs({"Shield Wall", "Last Stand", "Shield Block", "Retaliation",
    "Barkskin", "Frenzied Regeneration", "Survival Instincts", "Divine Protection",
    "Divine Shield", "Blessing of Protection", "Templar's Bulwark", "Evasion",
    "Cloak of Shadows", "Ice Block", "Ice Barrier", "Mana Shield", "Deterrence",
    "Feign Death", "Dispersion", "Pain Suppression", "Guardian Spirit",
    "Power Word: Shield", "Sacrifice", "Soul Link", "Shadow Ward", "Stoneform",
    "Astral Shift", "Shamanistic Rage"}) do defensiveNames[name] = true end
local defensiveIDs = {[871]=true,[12975]=true,[2565]=true,[22812]=true,[22842]=true,
    [498]=true,[642]=true,[1022]=true,[5277]=true,[45438]=true,[19263]=true,
    [33206]=true,[47585]=true,[47788]=true,[48707]=true,[48792]=true}
local function defensiveAuras(unit, api)
    local result, seen = {}, {}
    local ok, ids = pcall(api.GetUnitAuraInstanceIDs, unit, "HELPFUL|BIG_DEFENSIVE", 3)
    if ok and readable(ids) then
        for _, id in ipairs(ids) do
            if not secret(id) and type(id) == "number" then
                local aura = api.GetAuraDataByAuraInstanceID(unit, id)
                if readable(aura) then result[#result + 1] = {auraInstanceID=id, icon=aura.icon, duration=aura.duration, expirationTime=aura.expirationTime, name=aura.name, spellId=aura.spellId}; seen[id] = true end
            end
        end
    end
    if #result < 3 and api.GetAuraDataByIndex then
        for i = 1, 80 do
            local aura = api.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not readable(aura) then break end
            local id, spellID, name = plain(aura.auraInstanceID), plain(aura.spellId), plain(aura.name)
            if type(id) == "number" and not seen[id] and
                ((type(spellID) == "number" and defensiveIDs[spellID]) or
                 (type(name) == "string" and defensiveNames[name])) then
                result[#result + 1] = aura; seen[id] = true
                if #result >= 3 then break end
            end
        end
    end
    return result
end
local function paint(unit, anchor, c)
    local row = rowFor(unit)
    if row.anchor ~= anchor or row.size ~= c.size or row.left ~= c.left then
        row:ClearAllPoints()
        if c.left then row:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        else row:SetPoint("LEFT", anchor, "RIGHT", 8, 0) end
        row:SetSize(6 * (c.size + 3), c.size)
        for i, icon in ipairs(row.icons) do
            icon:ClearAllPoints(); icon:SetSize(c.size, c.size)
            icon:SetPoint(c.left and "RIGHT" or "LEFT", row, c.left and "RIGHT" or "LEFT", (i - 1) * (c.size + 3) * (c.left and -1 or 1), 0)
        end
        row.anchor, row.size, row.left = anchor, c.size, c.left
    end
    local api = C_UnitAuras
    local auras = {}
    if api and api.GetUnitAuraInstanceIDs and api.GetAuraDataByAuraInstanceID then
        local ok, result = pcall(defensiveAuras, unit, api)
        if ok then auras = result else state.auraStatus = "Active aura read unavailable" end
    end
    local count, consumed = 0, {}
    local sync = DBagsAlertsState.partyCooldowns
    local entries = sync and sync.get(unit) or {}
    local function active(icon, aura)
        icon.auraID = plain(aura.auraInstanceID)
        icon.tex:SetTexture(aura.icon); icon.tex:SetDesaturated(false); icon:SetAlpha(1)
        icon.edge:SetColorTexture(1, 0.82, 0.25, 1); icon.label:SetText("UP")
        icon.label:SetTextColor(1, 0.82, 0.25); icon.cd:SetReverse(true)
        if api.GetAuraDuration and icon.cd.SetCooldownFromDurationObject then
            local ok, duration = pcall(api.GetAuraDuration, unit, icon.auraID)
            if ok and duration then icon.cd:SetCooldownFromDurationObject(duration)
            else icon.cd:Clear() end
        else
            local duration, expires = plain(aura.duration), plain(aura.expirationTime)
            if type(duration)=="number" and type(expires)=="number" and duration>0 then icon.cd:SetCooldown(expires-duration,duration)
            else icon.cd:Clear() end
        end
    end
    -- Missing addon reports do not create empty question-mark tiles.
    local reported = {}
    for _, entry in ipairs(entries) do if entry.id > 0 then reported[#reported + 1] = entry end end
    for _, entry in ipairs(reported) do
        if count >= 6 then break end
        count = count + 1
        local icon = row.icons[count]
        icon.auraID = nil; icon.entry = entry; icon.cd:Clear(); icon.cd:SetReverse(false)
        icon.tex:SetTexture(entry.id > 0 and C_Spell.GetSpellTexture(entry.id) or 134400)
        local ready = entry.status == "R"
        icon.tex:SetDesaturated(not ready); icon:SetAlpha(entry.placeholder and 0.35 or ready and 1 or 0.65)
        icon.edge:SetColorTexture(ready and 0.25 or 0.3, ready and 0.85 or 0.3, 0.3, 1)
        icon.label:SetText(ready and (entry.estimated and "RDY~" or "RDY") or entry.estimated and "~" or "")
        icon.label:SetTextColor(entry.estimated and 1 or ready and 0.4 or 1, entry.estimated and 0.82 or 1, entry.estimated and 0.3 or ready and 0.4 or 1)
        if entry.status == "C" and entry.remaining and entry.duration and entry.duration > 0 then
            icon.cd:SetCooldown(GetTime() + entry.remaining - entry.duration, entry.duration)
        end
        for i, aura in ipairs(auras) do
            local id, name = plain(aura.spellId), plain(aura.name)
            if not consumed[i] and ((type(id)=="number" and id==entry.id) or (type(name)=="string" and name==entry.name)) then
                active(icon,aura); consumed[i] = true; break
            end
        end
        icon:Show()
    end
    for i, aura in ipairs(auras) do
        if count >= 6 then break end
        if not consumed[i] and type(plain(aura.auraInstanceID))=="number" then
            count = count + 1
            local icon = row.icons[count]; icon.entry = nil
            active(icon,aura); icon:Show()
        end
    end
    for i = count + 1, 6 do row.icons[i].auraID = nil; row.icons[i].entry = nil; row.icons[i]:Hide() end
    row:SetShown(count > 0)
    return #auras
end
local function update()
    local c = config()
    if not eligible(c) then hideAll(); state.status = c.enabled and "Five-player dungeons only" or "Off"; return end
    local api = C_UnitAuras
    if not DBagsAlertsState.partyCooldowns and (not api or not api.GetUnitAuraInstanceIDs or not api.GetAuraDataByAuraInstanceID) then
        hideAll(); state.status = "Native defensive-aura API unavailable"; return
    end
    local anchors, active = 0, 0
    for i = 0, 4 do
        local unit = i == 0 and "player" or ("party" .. i)
        local exists = plain(UnitExists(unit))
        local anchor = exists and findFrame(unit)
        if anchor then anchors = anchors + 1; active = active + paint(unit, anchor, c)
        elseif state.rows[unit] then state.rows[unit]:Hide() end
    end
    state.status = anchors == 0 and "No supported party frames found"
        or string.format("%d party frames; %d active defensives", anchors, active)
end
local function refresh()
    local ok, err = pcall(update)
    if not ok then
        hideAll(); state.status = "Party defensives: " .. tostring(err)
        if state.lastError ~= state.status then
            state.lastError = state.status
            if geterrorhandler then geterrorhandler()(state.status) end
        end
    end
end
state.update = refresh
local dirty, elapsed = true, 0
local driver = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_REGEN_ENABLED"}) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_AURA" or (type(unit) == "string" and (unit == "player" or unit:match("^party[1-4]$"))) then dirty = true end
end)
if hooksecurefunc and CompactUnitFrame_SetUnit then hooksecurefunc("CompactUnitFrame_SetUnit", function() dirty = true end) end
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    -- No frame or aura scanning outside a small dungeon party.
    local c = config()
    if not eligible(c) then
        if state.active then hideAll(); state.active = false end
        return
    end
    state.active = true
    if elapsed < 0.15 or (not dirty and elapsed < 1) then return end
    elapsed = 0; dirty = false; refresh()
end)
local window
DBagsAlertsState.openPartyDefensives = function()
    local c = config()
    if not window then
        local w = CreateFrame("Frame", "DBagsAlertsPartyDefensiveSettings", UIParent)
        window = w; w:SetSize(370, 350); w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG")
        DBagsAlertsState.prepareSettingsWindow(w, "party")
        if DBagsAlertsState.alerts then
            DBagsAlertsState.settingsBackButton(w, function() SlashCmdList.DBAGSALERTS("") end)
        end
        local bg = w:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.055, 0.055, 0.065, 1)
        local function text(label, x, y, size)
            local t = w:CreateFontString(nil, "OVERLAY"); t:SetFont("Fonts\\FRIZQT__.TTF", size or 13, "OUTLINE")
            t:SetText(label); t:SetPoint("TOPLEFT", x, y); return t
        end
        text("Party helpers", 18, -16, 20)
        local follow = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        follow:SetSize(105,24); follow:SetPoint("BOTTOMRIGHT",-14,14); follow:SetText("Follow buddy")
        follow:SetScript("OnClick",function() if DBagsAlertsState.openFollowBuddy then DBagsAlertsState.openFollowBuddy() end end)
        local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        close:SetSize(28, 24); close:SetPoint("TOPRIGHT", -10, -10); close:SetText("X"); close:SetScript("OnClick", function() w:Hide() end)
        w.enabled = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        w.enabled:SetPoint("TOPLEFT", 12, -48); text("Party cooldowns (dungeons)", 46, -57, 12)
        w.enabled:SetScript("OnClick", function(self) config().enabled = self:GetChecked() and true or false; refresh() end)
        w.left = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        w.left:SetPoint("TOPLEFT", 12, -80); text("Icons on the left", 46, -89)
        w.left:SetScript("OnClick", function(self) config().left = self:GetChecked() and true or false; refresh() end)
        w.placeholders = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        w.placeholders:SetPoint("TOPLEFT", 174, -80); text("Placeholders", 208, -89, 12)
        w.placeholders:SetScript("OnClick", function(self) config().placeholders = self:GetChecked() and true or false; refresh() end)
        local label = text("", 18, -124)
        w.size = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
        w.size:SetPoint("TOPLEFT", 24, -151); w.size:SetSize(290, 18)
        w.size:SetMinMaxValues(20, 44); w.size:SetValueStep(2); w.size:SetObeyStepOnDrag(true)
        w.size:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / 2 + 0.5) * 2
            config().size = value; label:SetFormattedText("Icon size: %d", value); refresh()
        end)
        w.groupRange = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        w.groupRange:SetPoint("TOPLEFT", 12, -180)
        text("Group distance warning", 46, -189, 12)
        w.groupRange:SetScript("OnClick", function(self)
            config().groupRange = self:GetChecked() and true or false
            if DBagsAlertsState.groupRange then DBagsAlertsState.groupRange.update() end
        end)
        local rangeSettings=CreateFrame("Button",nil,w,"UIPanelButtonTemplate")
        rangeSettings:SetSize(178,26);rangeSettings:SetPoint("TOPLEFT",24,-218);rangeSettings:SetText("WAKE UP settings")
        rangeSettings:SetScript("OnClick",function() if DBagsAlertsState.openGroupRange then DBagsAlertsState.openGroupRange() end end)
        w.status = text("", 18, -264, 12); w.status:SetWidth(324)
        table.insert(UISpecialFrames, "DBagsAlertsPartyDefensiveSettings")
    end
    window.enabled:SetChecked(c.enabled); window.left:SetChecked(c.left); window.size:SetValue(c.size)
    window.groupRange:SetChecked(c.groupRange); window.placeholders:SetChecked(c.placeholders)
    refresh(); window.status:SetText(state.status); DBagsAlertsState.showSettingsWindow(window, "party")
end
SLASH_DBAGSPARTY1 = "/dbaparty"
SlashCmdList.DBAGSPARTY = function(msg)
    if msg and msg:lower():match("^status") then
        refresh()
        print("DBagsAlerts: " .. state.status .. ". RDY = confirmed; RDY~ = estimated; UP = active. Dim = not observed.")
        return
    end
    DBagsAlertsState.openPartyDefensives()
end
