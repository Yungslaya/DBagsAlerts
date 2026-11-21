-- Dragbag addon family: one shared look, taken from the approved What's new preview.
--   Window   ornate stone frame with gold corners, slate middle, gold rule under the title
--   Card     steel box (rows, boxes, tabs, quiet buttons)
--   Button   red button with a gold edge; tabs turn into steel tabs with a gold underline
-- Presentation only: never touches settings, saved data, combat HUDs or protected buttons.
-- The art sits OUTSIDE each frame's edges, so the frame's own contents never touch the border.
-- Master copy: CurseForgePublishing\theme\EmporiumTheme.lua (copy_theme.py puts it in every addon).
local addon = ...
local V = 2
local E = _G.DragbagEmporiumTheme
if type(E) == "table" and (tonumber(E.V) or 1) >= V then return end
E = type(E) == "table" and E or {}
_G.DragbagEmporiumTheme = E
E.V = V

local media = "Interface\\AddOns\\" .. (addon or "ProfessionPal") .. "\\Media\\News\\"
E.media = media
local locale = GetLocale and GetLocale() or "enUS"
local fallback = locale == "ruRU" or locale == "zhCN" or locale == "zhTW" or locale == "koKR"
E.fallback = fallback
E.body = fallback and (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF") or media .. "Inter-Regular.ttf"
E.bold = fallback and E.body or media .. "Inter-SemiBold.ttf"
E.title = fallback and E.body or media .. "Cinzel-SemiBold.ttf"

-- preview colors
E.GOLD = { 0.85, 0.71, 0.42 }        -- #D9B66B section titles, selected tab
E.TITLE = { 0.95, 0.81, 0.50 }       -- #F3CF80 window titles
E.WHITE = { 0.94, 0.93, 0.90 }       -- #F0EDE5
E.MUTE = { 0.71, 0.71, 0.74 }        -- #B4B6BD
E.BTN = { 0.96, 0.86, 0.62 }         -- #F4DC9D red-button text

local function own(f, k) return rawget(f, k) end
local function num(v, d) if type(v) == "number" then return v end return d end

-- Inter is wider than the old narrow font, so body text drops about 10% to keep the same layouts.
function E.Size(size, kind)
    size = tonumber(size) or 13
    if fallback or kind == "title" then return size end
    return math.max(9, math.floor(size * 0.9 + 0.5))
end

function E.Font(fs, size, kind, flags)
    if not (fs and fs.SetFont) then return fs end
    local path = kind == "title" and E.title or kind == "bold" and E.bold or E.body
    if fs:SetFont(path, E.Size(size, kind), flags or "") == false then
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 13, flags or "")
    end
    return fs
end

-- Shrink a one-line label until it fits (never below 9).
function E.Fit(fs, maxW)
    if not (fs and fs.GetStringWidth and fs.GetFont and maxW and maxW > 0) then return end
    local font, size, flags = fs:GetFont()
    if not font or not size then return end
    local function width()
        local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        return num(w, 0)
    end
    size = math.floor(size + 0.5)
    while size > 9 and width() > maxW do
        size = size - 1
        fs:SetFont(font, size, flags)
    end
end

-- Nine pieces of art around (and under) frame f. O pushes the art outside the frame's edges.
local PARTS = { "tl", "t", "tr", "l", "c", "r", "bl", "b", "br" }
local function slices(f, kind, D, O, sub, at, key)
    key = key or ("emArt" .. kind)
    local p = type(key) == "table" and key or own(f, key)
    if not p or not p.tl then
        p = type(key) == "table" and key or {}
        for _, n in ipairs(PARTS) do
            local t = f:CreateTexture(nil, "BACKGROUND", nil, sub or -7)
            t:SetTexture(media .. kind .. "-" .. n .. ".tga")
            p[n] = t
        end
        if type(key) ~= "table" then f[key] = p end
    end
    for _, t in pairs(p) do t:ClearAllPoints(); t:Show() end
    for _, v in ipairs({ { "tl", "TOPLEFT", -O, O }, { "tr", "TOPRIGHT", O, O },
                         { "bl", "BOTTOMLEFT", -O, -O }, { "br", "BOTTOMRIGHT", O, -O } }) do
        p[v[1]]:SetSize(D, D); p[v[1]]:SetPoint(v[2], at or f, v[2], v[3], v[4])
    end
    p.t:SetPoint("TOPLEFT", p.tl, "TOPRIGHT"); p.t:SetPoint("BOTTOMRIGHT", p.tr, "BOTTOMLEFT")
    p.b:SetPoint("TOPLEFT", p.bl, "TOPRIGHT"); p.b:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT")
    p.l:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT"); p.l:SetPoint("BOTTOMRIGHT", p.bl, "TOPRIGHT")
    p.r:SetPoint("TOPLEFT", p.tr, "BOTTOMLEFT"); p.r:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT")
    p.c:SetPoint("TOPLEFT", p.tl, "BOTTOMRIGHT"); p.c:SetPoint("BOTTOMRIGHT", p.br, "TOPLEFT")
    return p
end
local function hideSlices(f, kind)
    local p = own(f, "emArt" .. kind)
    if p then for _, t in pairs(p) do t:Hide() end end
end

local function clearBackdrop(f)
    if f.SetBackdrop then pcall(f.SetBackdrop, f, nil) end
end

-- Opacity of the art only (text stays readable). Used by overlays with an opacity setting.
function E.ArtAlpha(f, a)
    for _, kind in ipairs({ "panel", "steel", "ruby" }) do
        local p = own(f, "emArt" .. kind)
        if p then for _, t in pairs(p) do t:SetAlpha(a) end end
    end
    if own(f, "emRule") then f.emRule:SetAlpha(a) end
end

-- Window title: Cinzel, preview gold.
function E.Title(fs, size)
    if not fs then return end
    local _, cur = fs:GetFont()
    E.Font(fs, size or cur or 18, "title")
    fs:SetTextColor(unpack(E.TITLE))
    fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.9)
end

-- Close button: the preview's small square with a gold x.
function E.Close(b, size)
    if not b or own(b, "emClose") then return end
    b.emClose = true
    size = size or 24
    b:SetSize(size, size)
    if b.SetNormalTexture then b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetHighlightTexture(""); b:SetDisabledTexture("") end
    for _, r in ipairs({ b:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    if b.GetFontString and b:GetFontString() then b:GetFontString():SetText("") end
    if b.SetText then b:SetText("") end
    local bg = b:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints(); bg:SetColorTexture(0.145, 0.137, 0.125, 1)
    local edges = {}
    for _, v in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local e = b:CreateTexture(nil, "BORDER")
        e:SetColorTexture(0.62, 0.48, 0.27, 1)
        e:SetPoint(v[1]); e:SetPoint(v[2])
        if v[3] == 1 then e:SetWidth(1) else e:SetHeight(1) end
        edges[#edges + 1] = e
    end
    -- the x is two gold lines (always dead center, whatever the font does)
    local bars = {}
    for _, turn in ipairs({ 45, -45 }) do
        local bar = b:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(1, 1, 1, 1); bar:SetVertexColor(unpack(E.GOLD))
        bar:SetSize(math.floor(size * 0.55), 2); bar:SetPoint("CENTER")
        if bar.SetRotation then bar:SetRotation(math.rad(turn)) end
        bars[#bars + 1] = bar
    end
    b:HookScript("OnEnter", function() for _, t in ipairs(bars) do t:SetVertexColor(1, 0.9, 0.6) end end)
    b:HookScript("OnLeave", function() for _, t in ipairs(bars) do t:SetVertexColor(unpack(E.GOLD)) end end)
end

-- A window (or, with compact, a small overlay). band = height of the title area.
function E.Window(f, band, o)
    o = o or {}
    clearBackdrop(f)
    local compact = o.compact
    f.emCompact = compact
    slices(f, "panel", compact and 26 or 48, compact and 8 or 14, -8)
    if own(f, "band") then f.band:Hide() end
    if own(f, "bandLine") then f.bandLine:Hide() end
    if band and band > 0 then
        local r = own(f, "emRule")
        if not r then
            r = f:CreateTexture(nil, "BORDER", nil, 1)
            r:SetTexture(media .. "rule.tga")
            f.emRule = r
        end
        r:ClearAllPoints()
        local h = compact and 10 or 16
        r:SetPoint("TOPLEFT", f, "TOPLEFT", compact and 0 or 4, -band + h / 2)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", compact and 0 or -4, -band + h / 2)
        r:SetHeight(h)
        r:Show()
    end
    if o.title then E.Title(o.title, o.titleSize) end
    if o.close then E.Close(o.close) end
end

-- Steel card (rows, boxes, panels inside a window).
function E.Card(f)
    clearBackdrop(f)
    local h = num(f.GetHeight and f:GetHeight(), 30)
    slices(f, "steel", math.max(3, math.min(7, math.floor(h / 3))), 0, -6)
end

-- Steel card drawn behind a plain texture of `owner` (the texture keeps deciding place and shown/hidden).
function E.CardOn(owner, region, D)
    if not (owner and region) or own(region, "emCard") then return end
    local p = slices(owner, "steel", D or 7, 0, -5, region, {})
    region.emCard = p
    region:SetAlpha(0)
    local function sync() local on = region:IsShown(); for _, t in pairs(p) do t:SetShown(on) end end
    if hooksecurefunc then
        hooksecurefunc(region, "Show", sync); hooksecurefunc(region, "Hide", sync)
        if region.SetShown then hooksecurefunc(region, "SetShown", sync) end
    end
    sync()
end

-- Section label ("NEXT STEP", "TRAINER"): the preview's small gold Cinzel caps.
function E.Section(fs, size)
    if not fs then return end
    local _, cur = fs:GetFont()
    E.Font(fs, size or cur or 15, "title")
    fs:SetTextColor(unpack(E.GOLD))
end

local function hideTemplate(b)
    if b.SetNormalTexture then b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetHighlightTexture(""); b:SetDisabledTexture("") end
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        local t = own(b, k); if t and t.Hide then t:Hide(); t:SetAlpha(0) end
    end
end

local function paintButton(b)
    local kind = b.emKind
    local h = num(b:GetHeight(), 24)
    hideSlices(b, kind == "ruby" and "steel" or "ruby")
    if kind == "ruby" then
        slices(b, "ruby", math.max(5, math.min(10, math.floor(h * 0.22 + 0.5))), 0, -6)
    else
        slices(b, "steel", math.max(3, math.min(7, math.floor(h / 3))), 0, -6)
    end
    local fs = b.GetFontString and b:GetFontString()
    if fs then
        local c = b.emOn and E.GOLD or (kind == "ruby" and E.BTN or E.WHITE)
        if b.IsEnabled and not b:IsEnabled() then c = { 0.45, 0.45, 0.48 } end
        fs:SetTextColor(unpack(c))
        fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.8)
    end
    if own(b, "emLine") then b.emLine:SetShown(b.emOn and true or false) end
end

-- Fit the label of a themed button on one line.
function E.FitButton(b)
    local fs = b.GetFontString and b:GetFontString()
    if not fs then return end
    local size = own(b, "emSize")   -- already the final size: no second 10% cut
    if size and fs:SetFont(E.bold, size, "") == false then fs:SetFont(E.body, size, "") end
    E.Fit(fs, num(b:GetWidth(), 60) - 8)
end

-- A red button (kind "ruby", default) or a quiet steel one (kind "steel"). Call after the label is set.
function E.Button(b, kind, size)
    if not b then return end
    local first = not own(b, "emKind")
    b.emKind = own(b, "emKind") == "tab" and "tab" or (kind or "ruby")
    if first then
        clearBackdrop(b)
        hideTemplate(b)
        local fs = b.GetFontString and b:GetFontString()
        if fs then
            local _, cur = fs:GetFont()
            b.emSize = size and E.Size(size, "bold") or math.max(13, math.floor((cur or 14) + 0.5))
        end
        b:HookScript("OnEnter", function(self)
            if self.IsEnabled and not self:IsEnabled() then return end
            for _, k in ipairs({ "ruby", "steel" }) do
                local p = own(self, "emArt" .. k)
                if p then for _, t in pairs(p) do t:SetVertexColor(1.18, 1.12, 1.05) end end
            end
        end)
        b:HookScript("OnLeave", function(self)
            for _, k in ipairs({ "ruby", "steel" }) do
                local p = own(self, "emArt" .. k)
                if p then for _, t in pairs(p) do t:SetVertexColor(1, 1, 1) end end
            end
        end)
        b:HookScript("OnEnable", paintButton)
        b:HookScript("OnDisable", paintButton)
        b:HookScript("OnSizeChanged", function(self) paintButton(self); E.FitButton(self) end)
        if type(b.SetText) == "function" and hooksecurefunc then
            hooksecurefunc(b, "SetText", function(self) E.FitButton(self) end)
        end
    end
    paintButton(b)
    E.FitButton(b)
end

-- Tabs: steel, gold label and a gold underline on the selected one (like the preview's tabs).
function E.Select(b, on)
    if not b then return end
    if not own(b, "emKind") then E.Button(b, "tab") end
    b.emKind = "tab"
    b.emOn = on and true or false
    if not own(b, "emLine") then
        local l = b:CreateTexture(nil, "ARTWORK", nil, 2)
        l:SetColorTexture(0.88, 0.73, 0.38, 1)
        l:SetPoint("BOTTOMLEFT", 6, 1); l:SetPoint("BOTTOMRIGHT", -6, 1); l:SetHeight(2)
        b.emLine = l
    end
    paintButton(b)
end

-- Battle Buddy settings windows (built with plain WoW parts). Restyles fonts, buttons, title
-- and close button. Safe to call again; it only touches regions it has not seen yet.
local function isTemplateButton(c)
    return c.IsObjectType and c:IsObjectType("Button") and not c:IsObjectType("CheckButton")
        and (own(c, "Left") or own(c, "Middle")) and c.GetFontString and c:GetFontString()
end
function E.Settings(f, o)
    if not f then return end
    o = o or {}
    if own(f, "dbaChrome") then f.dbaChrome:Hide() end
    -- the plain dark backgrounds these windows paint themselves
    for _, r in ipairs({ f:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and r:GetDrawLayer() == "BACKGROUND" and not own(r, "emSeen") then
            local mine = false
            for _, kind in ipairs({ "panel" }) do
                local p = own(f, "emArt" .. kind)
                if p then for _, t in pairs(p) do if t == r then mine = true end end end
            end
            if not mine then r:Hide() end
        end
    end
    E.Window(f, o.band or 50, { title = o.title, close = o.close })
    local function walk(parent, depth)
        if depth > 8 then return end
        for _, r in ipairs({ parent:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("FontString") and not own(r, "emSeen") and r ~= o.title then
                r.emSeen = true
                local _, size = r:GetFont()
                size = size or 13
                if depth == 0 and size >= 19 and not o.title then
                    E.Title(r, size)
                else
                    E.Font(r, size, size >= 16 and "bold" or "body")
                    r:SetShadowOffset(1, -1); r:SetShadowColor(0, 0, 0, 0.8)
                end
            end
        end
        for _, c in ipairs({ parent:GetChildren() }) do
            if isTemplateButton(c) and not own(c, "emKind") then
                local fs = c:GetFontString()
                local label = fs and fs:GetText()
                if label == "X" or label == "x" then
                    E.Close(c, 24)
                elseif label and label ~= "" then
                    E.Button(c, "ruby")
                end
            elseif c.IsObjectType and c:IsObjectType("CheckButton") and own(c, "text") and c.text.SetJustifyH then
                c.text:SetJustifyH("LEFT")
            end
            walk(c, depth + 1)
        end
    end
    walk(f, 0)
end
