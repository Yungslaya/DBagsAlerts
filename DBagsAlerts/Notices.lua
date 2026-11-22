--[[ Battle Buddy - update notices

  1. New version check. Addons can't go online or see the CurseForge app, so Battle Buddy tells
     guildmates and group members which version it is (a hidden addon message). If anyone has a
     newer one, you get one message: "Battle Buddy X is out. Update it in the CurseForge app."
     Only version numbers are sent. Nothing is sent in combat.
     Only a real release download sends its version: the release zip's .toc has
     "## X-Release-Build: 1" (added by CurseForgePublishinguild_release_zip.py). A test copy
     without it never tells anyone about a version that isn't on CurseForge yet; it still listens.
  2. Renamed notice: players who used DBagsAlerts before see one popup saying it is now Battle Buddy.
  3. What's new: after an update, one window lists what changed (from CHANGELOG.md). One shared window for all our addons, a tab each. "/bbuddy news" reopens it.

  Generated from CurseForgePublishing\notices\Notices.template.lua - edit the template, not this copy.
]]

local ADDON = "DBagsAlerts"            -- folder name (never changes, so settings carry over)
local NAME = "Battle Buddy"              -- the name players see
local PREFIX = "BattleBuddyVer"          -- addon message prefix (16 characters or less)
local SV = "DBagsAlertsDB"                  -- account-wide saved table that keeps the notice flags
local OLD_SV = nil            -- per-character saved table that also counts as "was installed", or nil
local RENAME = { old = "DBagsAlerts", text = "DBagsAlerts is now called Battle Buddy.\n\nSame addon, same settings. Nothing to set up again.\n\nNew command: /bbuddy  (the old /dba still works)" }            -- { old = "...", text = "..." } or nil

local api = C_AddOns or {}
local getMeta = api.GetAddOnMetadata or GetAddOnMetadata
local chat = C_ChatInfo or {}
local secret = issecretvalue or function() return false end

local function plain(v) if secret(v) then return nil end return v end

-- "1.3.7" or "v1.3.7" -> { 1, 3, 7 }
local function parse(v)
    if type(v) ~= "string" then return nil end
    local out = {}
    for n in v:gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return #out > 0 and out or nil
end

-- true when version a is newer than version b
local function newer(a, b)
    local x, y = parse(a), parse(b)
    if not (x and y) then return false end
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

local mine = getMeta and getMeta(ADDON, "Version") or nil
local released = getMeta and getMeta(ADDON, "X-Release-Build") == "1"
local state = { installedBefore = false, told = {}, lastSent = {}, replied = {}, pending = {} }

local function store()
    local db = _G[SV]
    if type(db) ~= "table" then db = {}; _G[SV] = db end
    db.notices = type(db.notices) == "table" and db.notices or {}
    return db.notices
end

local function inCombat() return (InCombatLockdown and InCombatLockdown()) or false end

-- Popups wait until you are out of combat.
local function popup(key, text)
    if inCombat() then state.pending[key] = text; return end
    local id = "NOTICE_" .. PREFIX .. "_" .. key
    StaticPopupDialogs[id] = { text = text, button1 = OKAY or "Okay", timeout = 0, whileDead = true,
        hideOnEscape = true, preferredIndex = 3 }
    if StaticPopup_Show then StaticPopup_Show(id) end
end

local function say(text)
    print("|cffffd200" .. NAME .. ":|r " .. text)
end

-- ---------- 1. new version check ----------

local function tellNewer(version)
    if state.told[version] then return end
    state.told[version] = true
    local n = store()
    n.newest = version
    say(version .. " is out (you have " .. tostring(mine) .. "). Update it in the CurseForge app.")
    if n.popupFor ~= version then
        n.popupFor = version
        popup("update", NAME .. " " .. version .. " is out.\n\nYou have " .. tostring(mine) ..
            ".\nUpdate it in the CurseForge app.")
    end
end

local function send(channel, target)
    if not (released and mine and chat.SendAddonMessage) or inCombat() then return end
    local key = channel .. (target or "")
    local now = GetTime and GetTime() or 0
    if state.lastSent[key] and now - state.lastSent[key] < 60 then return end
    state.lastSent[key] = now
    pcall(chat.SendAddonMessage, PREFIX, "V:" .. mine, channel, target)
end

local function announce()
    if IsInGuild and IsInGuild() then send("GUILD") end
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then send("INSTANCE_CHAT")
    elseif IsInRaid and IsInRaid() then send("RAID")
    elseif IsInGroup and IsInGroup() then send("PARTY") end
end

local function heard(prefix, message, channel, sender)
    prefix, message, sender = plain(prefix), plain(message), plain(sender)
    if prefix ~= PREFIX or type(message) ~= "string" then return end
    local version = message:match("^V:(.+)$")
    if not version or not mine then return end
    if newer(version, mine) then
        tellNewer(version)
    elseif newer(mine, version) and type(sender) == "string" and not state.replied[sender] then
        -- they are behind: tell them once, privately, so they get the notice too
        state.replied[sender] = true
        send("WHISPER", sender)
    end
end

-- ---------- 2. renamed notice ----------

local function renameNotice()
    if not RENAME then return end
    local n = store()
    if n.renameSeen then return end
    n.renameSeen = true
    if state.installedBefore then popup("rename", RENAME.text) end
end

-- ---------- 3. What's new window ----------
-- After an update, people who used the addon before see one window with what changed since the
-- version they last saw (the CHANGELOG, baked in by make_notices.py). New installs see nothing.
-- "/bbuddy news" opens it again. Shared ornate news window for the addon family.

local NEWS = {
    { v = "1.3.1", date = "2026-11-21", items = { { "DoT timers stay on", "A DoT tile could go grey while the DoT was still on the mob. It happened when your pet's attack was dodged, parried or missed right after your cast. Fixed." }, { "No reminder on dying mobs", "The big DoT reminder now stays quiet when the mob is too low for the DoT to be worth it, the same as the small spell cues. Bosses, elites, dungeons and raids always get the reminder." } }, notes = {  } },
    { v = "1.3.0", date = "2026-11-21", items = { { "New look", "The settings windows have a stone frame with gold corners, new fonts and red gold-edged buttons. Our other addons now look the same." }, { "Pet bars match", "The pet frame's bars use the same art and the same green as your own bars." }, { "New HUD font", "The HUD uses the same clean font as the windows." }, { "What's new window", "After an update, one window shows what changed, with a tab for each of our addons you have. Type |cffffffff/bbuddy news|r to see it again." }, { "DoT report", "With debug recording on, the debug report lists what the DoT timers saw. It helps us fix timer bugs faster." } }, notes = {  } },
    { v = "1.2.5", date = "2026-11-20", items = { { "Big DoT alert is a reapply reminder", "It only shows for a DoT you already put on that target. A fresh mob shows nothing." }, { "Earlier warning", "Corruption, Immolate and Siphon Life show in their last 30%. Agony shows when it ends. A DoT that falls off shows until you put it back." } }, notes = {  } },
    { v = "1.2.4", date = "2026-11-20", items = { { "Immolate no longer goes missing", "In combat, Immolate's timer could vanish while Immolate was still on the mob, and the big alert asked you to cast it again. Fixed." }, { "Move and size the big DoT alert", "Settings > Sizes > |cffffd100Big DoT alert|r now has sliders for size, left / right, up / down and opacity." }, { "Drag it", "Click |cffffd100Show it (drag to move)|r and drag the icon where you want it. Click again to hide it. |cffffd100Put it back|r resets it." }, { "Settings > Display has a button that takes you...", "Settings > Display has a button that takes you straight there. The old height slider moved to the new page." } }, notes = {  } },
    { v = "1.2.3", date = "2026-11-20", items = { { "Big DoT refresh alert", "In combat, when a DoT is gone or about to run out, a big pulsing icon with its name shows in the middle of your screen, with one sound. It shows one DoT at a time, in rotation order, and moves on when you cast it." }, { "Refresh timing", "Corruption, Immolate and Siphon Life come back in their last 10%. Agony comes back when it drops off. Utility curses stay on the small icons only." }, { "Settings", "Turn it on or off, turn the sound on or off, and move it up or down in Settings > Display." } }, notes = {  } },
    { v = "1.2.2", date = "2026-11-20", items = { { "Warlock DoT timers fixed", "A DoT you cast on the mob under your mouse is now timed on that mob, not your target. Before, your target could show a timer for a DoT that wasn't there, and the real mob showed none." }, { "DoT numbers match the game", "Timers learn each DoT's real length when the game shows it, and round like the game's own numbers, so they no longer run a second behind the nameplates." }, { "Seen DoTs stay lit", "If the game shows your DoT on the target but not its time, the icon stays lit instead of grey." }, { "Mouseover macros", "Type |cffffffff/bbuddy macros|r to update them. Shadow Bolt, Immolate, Searing Pain, Conflagrate, Drain Life, Drain Soul and Agony now hit the mob under your mouse, or your target if there is none. Your pet stays on your target. The Agony macro works whether your game calls it Bane or Curse of Agony." } }, notes = {  } },
}                 -- { { v = "1.2.5", date = "...", items = { "..." }, notes = { "..." } }, ... } newest first
local ICON = "Interface\\Icons\\INV_Shield_06"
local SLASH_KEY, SLASH = "DBAGSALERTS", "/bbuddy"
local WHITE8 = "Interface\\Buttons\\WHITE8X8"

-- the versions to show: newer than `since`, not newer than this copy, at most 3
-- (items are { "short headline", "the full text, shown when you point at the line" })
local function newsSince(since)
    local out = {}
    for _, s in ipairs(NEWS) do
        if #out >= 3 then break end
        if not (mine and newer(s.v, mine)) and (since == nil or newer(s.v, since)) then out[#out + 1] = s end
    end
    return out
end

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\News\\"
local BODY, TITLE, BOLD = MEDIA .. "Inter-Regular.ttf", MEDIA .. "Cinzel-SemiBold.ttf", MEDIA .. "Inter-SemiBold.ttf"
local function text(parent, size, r, g, b, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if fs:SetFont(font or BODY, size, "") == false then fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end
    fs:SetTextColor(r, g, b); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetShadowOffset(0, 0)
    return fs
end
local function label(parent, x, y, w, h, value, size, font, gold)
    local t = text(parent, size, gold and .85 or .94, gold and .71 or .93, gold and .42 or .90, font)
    t:SetPoint("TOPLEFT", x, -y); t:SetSize(w, h); t:SetText(value)
    t:SetWordWrap(false)
    return t
end
local function texture(parent, file, x, y, w, h, u, v, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(MEDIA .. file .. ".tga"); t:SetPoint("TOPLEFT", x, -y); t:SetSize(w, h)
    t:SetTexCoord(0, u or 1, 0, v or 1)
    return t
end
local function button(parent, value, w, fn, red)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 48)
    b.art = texture(b, red and "ruby" or "secondary", 0, 0, w, 48, (red and 245 or 130)/256, 48/64)
    b.label = label(b, 8, 14, w-16, 26, value, 17, BOLD, red)
    -- dead center of the button, whatever the font's own spacing is
    b.label:ClearAllPoints(); b.label:SetPoint("LEFT", 8, 0); b.label:SetPoint("RIGHT", -8, 0); b.label:SetHeight(26)
    b.label:SetJustifyH("CENTER"); b.label:SetJustifyV("MIDDLE")
    b:SetScript("OnEnter", function() b.art:SetVertexColor(1.15,1.15,1.15) end)
    b:SetScript("OnLeave", function() b.art:SetVertexColor(1,1,1) end)
    b:SetScript("OnClick", fn)
    return b
end
local KIT = 5
local HUB = _G.DragbagAddonsNews
if type(HUB) ~= "table" then HUB = { addons = {}, order = {} }; _G.DragbagAddonsNews = HUB end
if (HUB.kit or 0) < KIT then
    HUB.kit = KIT
    local function inFight() return (InCombatLockdown and InCombatLockdown()) or false end
    local function build()
        if HUB.frame then return HUB.frame end
        local f = CreateFrame("Frame", "DragbagWhatsNew", UIParent)
        f:SetSize(900,818); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        local height = tonumber(UIParent:GetHeight()) or 1080
        local width = tonumber(UIParent:GetWidth()) or 1920
        -- Same size as the approved picture: one unit is one screen pixel on screens up to 1440 tall
        -- (bigger screens scale it up), and it always fits on the screen.
        local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        parentScale = type(parentScale)=="number" and parentScale>0 and parentScale or 1
        local _, pixels = 0, nil
        if GetPhysicalScreenSize then _, pixels = GetPhysicalScreenSize() end
        pixels = type(pixels)=="number" and pixels>0 and pixels or 1080
        local one = 768/(pixels*parentScale)*math.max(1,pixels/1440)
        f:SetScale(math.max(.3,math.min(one,(height-24)/818,(width-24)/900)))
        f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        -- the preview's own frame art in three parts, so the window can be shorter or taller
        local top=texture(f,"news-top",5,5,890,240,890/1024,240/256)
        local bot=f:CreateTexture(nil,"BACKGROUND"); bot:SetTexture(MEDIA .. "news-bot.tga")
        bot:SetPoint("BOTTOMLEFT",5,5); bot:SetSize(890,128); bot:SetTexCoord(0,890/1024,0,1)
        local mid=f:CreateTexture(nil,"BACKGROUND"); mid:SetTexture(MEDIA .. "news-mid.tga")
        mid:SetPoint("TOPLEFT",top,"BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT",bot,"TOPRIGHT")
        mid:SetTexCoord(0,890/1024,0,160/256)
        local brand = label(f,170,12,560,26,"DRAGBAG’S EMPORIUM",15,TITLE,true); brand:SetJustifyH("CENTER")
        f.title = label(f,100,52,700,60,"WHAT’S NEW",43,TITLE,true); f.title:SetJustifyH("CENTER")
        f.sub = label(f,90,128,720,28,"",17); f.sub:SetJustifyH("CENTER")
        local close = CreateFrame("Button",nil,f,"BackdropTemplate")
        close:SetSize(28,28); close:SetPoint("TOPLEFT",836,-32)
        close:SetBackdrop({bgFile=WHITE8,edgeFile=WHITE8,edgeSize=1})
        close:SetBackdropColor(.14,.14,.12,1); close:SetBackdropBorderColor(.61,.48,.27,1)
        -- the x is two gold lines, like the picture, so it is always dead center
        for _,turn in ipairs({45,-45}) do
            local bar=close:CreateTexture(nil,"OVERLAY"); bar:SetTexture(WHITE8); bar:SetVertexColor(.85,.71,.42)
            bar:SetSize(15,2); bar:SetPoint("CENTER"); if bar.SetRotation then bar:SetRotation(math.rad(turn)) end
        end
        close:SetScript("OnClick",function() f:Hide() end)
        if UISpecialFrames then table.insert(UISpecialFrames,"DragbagWhatsNew") end
        f.tabs, f.tabPool, f.rows, f.heads = {}, {}, {}, {}
        f.scroll=CreateFrame("ScrollFrame",nil,f)
        f.scroll:SetPoint("TOPLEFT",43,-240); f.scroll:SetSize(814,443)
        f.body=CreateFrame("Frame",nil,f.scroll); f.body:SetSize(814,443); f.scroll:SetScrollChild(f.body)
        f.scroll:EnableMouseWheel(true)
        local function scrollTo(value)
            local limit=math.max(0,(f.bodyHeight or 0)-(f.viewport or 443))
            f.scroll:SetVerticalScroll(math.min(limit,math.max(0,value)))
        end
        f.scroll:SetScript("OnMouseWheel",function(self,delta) scrollTo((self:GetVerticalScroll() or 0)-delta*86) end)
        f.up=CreateFrame("Button",nil,f); f.up:SetSize(24,24); f.up:SetPoint("TOPLEFT",861,-248)
        label(f.up,0,0,24,24,"▲",15,BODY,true); f.up:SetScript("OnClick",function() scrollTo((f.scroll:GetVerticalScroll() or 0)-172) end)
        f.down=CreateFrame("Button",nil,f); f.down:SetSize(24,24); f.down:SetPoint("TOPLEFT",861,-651)
        label(f.down,0,0,24,24,"▼",15,BODY,true); f.down:SetScript("OnClick",function() scrollTo((f.scroll:GetVerticalScroll() or 0)+172) end)
        local line=f:CreateTexture(nil,"ARTWORK"); line:SetTexture(WHITE8); line:SetVertexColor(.25,.25,.27)
        line:SetPoint("BOTTOMLEFT",44,125); line:SetSize(811,1)
        f.foot=label(f,44,738,410,26,"Hover an update for details.",13); f.foot:SetTextColor(.71,.71,.74); f.foot:ClearAllPoints(); f.foot:SetPoint("BOTTOMLEFT",44,54)
        f.ok=button(f,"Got it",130,function() f:Hide() end); f.ok:SetPoint("BOTTOMRIGHT",-45,54)
        f.open=button(f,"Open",245,function()
            local e=f.current and f.current.entry
            f:Hide(); if e and e.open and not inFight() then pcall(e.open) end
        end,true); f.open:SetPoint("RIGHT",f.ok,"LEFT",-12,0)
        f:SetScript("OnHide",function() if GameTooltip then GameTooltip:Hide() end; for _,e in pairs(HUB.addons) do e.pending=nil end end)
        HUB.frame=f
        return f
    end
    local overrides={
        ["Big DoT alert is a reapply reminder"]={"Refresh at the right moment","A clearer reminder for damage-over-time spells you’ve already applied.","flame"},
        ["Earlier warning"]={"Earlier refresh warnings","Corruption, Immolate and Siphon Life: final 30%.","timer"},
        ["Immolate no longer goes missing"]={"Immolate stays tracked","Its timer remains visible while the effect is active.","flame"},
        ["Move and size the big DoT alert"]={"Put your alert where you want it","Move and resize it in Settings → Sizes → Big DoT alert.","tools"},
    }
    local icons={DBagsAlerts="shield",DragsHedgeFund="coin",ProfessionPal="flask",MarketLedger="book"}
    local function selectTab(f,tab)
        f.current=tab
        local e=tab.entry
        f.sub:SetText(e.name .. " · Version " .. tostring(e.version))
        f.open.label:SetText("Open " .. e.name)
        if e.open then f.open:Show() else f.open:Hide() end
        for _,b in ipairs(f.tabs) do
            local on=b.tab==tab
            b.label:SetTextColor(on and .85 or .94,on and .71 or .93,on and .42 or .90)
            b.active:SetShown(on)
        end
        for _,row in ipairs(f.rows) do row:Hide() end
        for _,head in ipairs(f.heads) do head:Hide() end
        local y,n=0,0
        for section,s in ipairs(tab.list) do
            if section>1 then y=y+13 end
            local head=f.heads[section]
            if not head then
                head=CreateFrame("Frame",nil,f.body); head:SetSize(814,56)
                head.title=label(head,1,5,210,30,"",19,TITLE,true)
                head.badge=texture(head,"badge",216,1,62,28,62/64,28/32)
                head.version=label(head,220,6,170,28,"",15,BOLD,true)
                head.version:SetJustifyV("MIDDLE")
                head.rule=head:CreateTexture(nil,"ARTWORK"); head.rule:SetTexture(WHITE8); head.rule:SetVertexColor(.33,.29,.2)
                head.rule:SetPoint("TOPLEFT",294,-17); head.rule:SetSize(518,1)
                head.line=texture(head,"divider",0,36,814,13)
                f.heads[section]=head
            end
            head:ClearAllPoints(); head:SetPoint("TOPLEFT",0,-y); head:Show()
            head.title:SetText(section==1 and "LATEST UPDATE" or "ALSO IMPROVED")
            head.version:ClearAllPoints()
            head.version:SetPoint("TOPLEFT",section==1 and 216 or 230,-1)
            head.version:SetWidth(section==1 and 62 or 170)
            head.version:SetJustifyH(section==1 and "CENTER" or "LEFT")
            head.version:SetText(section==1 and s.v or "· " .. s.v)
            head.badge:SetShown(section==1); head.rule:SetShown(section==1)
            head.line:SetShown(section>1)
            y=y+(section==1 and 43 or 46)
            for _,item in ipairs(s.items or {}) do
                n=n+1
                local row=f.rows[n]
                if not row then
                    row=CreateFrame("Frame",nil,f.body); row:SetSize(814,76); row:EnableMouse(true)
                    texture(row,"row",0,0,814,76,814/1024,76/128)
                    row.icon=texture(row,"shield",12,12,51,51,1,1,"ARTWORK")
                    row.heading=label(row,80,12,718,27,"",20,BOLD)
                    row.detail=label(row,80,42,718,24,"",15); row.detail:SetTextColor(.71,.71,.74)
                    row:SetScript("OnEnter",function(self)
                        self.heading:SetTextColor(.95,.81,.5)
                        if GameTooltip then
                            GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.short,1,.82,.4)
                            GameTooltip:AddLine(self.more or "",.94,.93,.90,true); GameTooltip:Show()
                        end
                    end)
                    row:SetScript("OnLeave",function(self) self.heading:SetTextColor(.94,.93,.90); if GameTooltip then GameTooltip:Hide() end end)
                    f.rows[n]=row
                end
                local short,more=item[1],item[2] or ""
                local override=tab.key=="DBagsAlerts" and overrides[short]
                local detail=override and override[2] or more:match("^[^\n]+") or "Hover for details."
                if #detail>90 then detail=detail:sub(1,87):match("^(.*)%s") or detail:sub(1,87); detail=detail .. "…" end
                row.short,row.more=short,more
                row.heading:SetText(override and override[1] or short); row.heading:SetTextColor(.94,.93,.90)
                row.detail:SetText(detail)
                row.icon:SetTexture(MEDIA .. (override and override[3] or icons[tab.key] or "book") .. "-tile.tga")
                row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y); row:Show(); y=y+86
            end
        end
        f.viewport=math.min(443,math.max(100,y))
        f:SetHeight(240+f.viewport+135); f.scroll:SetHeight(f.viewport)
        f.down:ClearAllPoints(); f.down:SetPoint("TOPLEFT",861,-(240+f.viewport-26))
        f.bodyHeight=y; f.body:SetHeight(math.max(f.viewport,y)); f.scroll:SetVerticalScroll(0)
        f.up:SetShown(y>443); f.down:SetShown(y>443)
        f.foot:SetText(y>443 and "Hover for details. Scroll for more updates." or "Hover an update for details.")
    end
    local order={DBagsAlerts=1,DragsHedgeFund=2,ProfessionPal=3,MarketLedger=4}
    function HUB.Show(mode,pick)
        if inFight() then HUB.want={mode,pick}; return end
        local tabs={}
        for _,key in ipairs(HUB.order) do
            local e=HUB.addons[key]
            local list=e.pending or e.recent()
            if list and #list>0 then tabs[#tabs+1]={entry=e,list=list,key=key} end
        end
        if #tabs==0 then return end
        table.sort(tabs,function(a,b) return (order[a.key] or 99)<(order[b.key] or 99) end)
        for _,t in ipairs(tabs) do if mode=="login" then t.entry.seen() end end
        local f=build()
        for _,b in ipairs(f.tabPool) do b:Hide() end
        f.tabs={}
        for i,tab in ipairs(tabs) do
            local b=f.tabPool[i]
            if not b then
                b=CreateFrame("Button",nil,f); b:SetSize(198,44)
                texture(b,"tab",0,0,198,44,198/256,44/64)
                b.icon=texture(b,"shield",7,6,32,32,1,1,"ARTWORK")
                b.label=label(b,43,13,152,24,"",15,BOLD)
                b.label:ClearAllPoints(); b.label:SetPoint("LEFT",43,0); b.label:SetPoint("RIGHT",-4,0); b.label:SetHeight(24)
                b.label:SetJustifyV("MIDDLE")
                b.icon:ClearAllPoints(); b.icon:SetPoint("LEFT",7,0)
                b.active=b:CreateTexture(nil,"ARTWORK"); b.active:SetTexture(WHITE8); b.active:SetVertexColor(.88,.73,.38)
                b.active:SetPoint("BOTTOMLEFT",7,0); b.active:SetSize(184,2)
                b:SetScript("OnClick",function(self) selectTab(f,self.tab) end)
                f.tabPool[i]=b
            end
            b:ClearAllPoints(); b:SetPoint("TOPLEFT",42+(i-1)*206,-180)
            b.label:SetText(tab.entry.name); b.icon:SetTexture(MEDIA .. (icons[tab.key] or "book") .. ".tga")
            b.tab=tab; b:Show(); f.tabs[i]=b
        end
        local first=tabs[1]
        if mode=="login" then for _,t in ipairs(tabs) do if t.entry.pending then first=t; break end end end
        for _,t in ipairs(tabs) do if t.key==pick then first=t end end
        selectTab(f,first); f:Show()
    end
    function HUB.Flush()
        if HUB.want and not inFight() then local w=HUB.want; HUB.want=nil; HUB.Show(w[1],w[2]) end
    end
end


-- this addon's place in the shared window
local entry = HUB.addons[ADDON]
if not entry then
    entry = {}
    HUB.addons[ADDON] = entry
    HUB.order[#HUB.order + 1] = ADDON
end
entry.name, entry.icon, entry.slash, entry.version = NAME, ICON, SLASH, mine
entry.recent = function() return newsSince(nil) end   -- the last 3 versions
entry.seen = function() store().newsSeen = mine end
entry.open = nil

-- after login: only for people who had the addon before, once per new version
local function newsAtLogin()
    if not mine or #NEWS == 0 then return end
    local n = store()
    local seen = n.newsSeen
    if seen == nil then
        if not state.installedBefore then n.newsSeen = mine; return end
        entry.pending = newsSince(NEWS[2] and NEWS[2].v or nil)   -- updated from an unknown version: the newest only
    elseif newer(mine, seen) then
        entry.pending = newsSince(seen)
    end
    -- every addon's timer runs at the same moment; each call shows all the tabs collected so far
    if entry.pending and #entry.pending > 0 then HUB.Show("login") end
end

-- "/bbuddy news" opens it again (this addon's tab first); everything else goes to the addon as before
local function hookSlash()
    if not SlashCmdList then return end
    local orig = SlashCmdList[SLASH_KEY]
    if type(orig) ~= "function" or SlashCmdList[SLASH_KEY .. "_NEWSORIG"] then return end
    SlashCmdList[SLASH_KEY .. "_NEWSORIG"] = orig
    entry.open = function() orig("") end
    SlashCmdList[SLASH_KEY] = function(msg, ...)
        if type(msg) == "string" and msg:lower():match("^%s*news%s*$") then
            HUB.Show("all", ADDON)
            return
        end
        return orig(msg, ...)
    end
end

-- ---------- events ----------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "ADDON_LOADED" and a == ADDON then
        -- saved settings from before this version mean you already used the addon
        local function used(t) return type(t) == "table" and next(t) ~= nil end
        state.installedBefore = used(_G[SV]) or (OLD_SV and used(_G[OLD_SV])) or false
        if chat.RegisterAddonMessagePrefix then pcall(chat.RegisterAddonMessagePrefix, PREFIX) end
    elseif event == "PLAYER_LOGIN" then
        local n = store()
        if n.newest and newer(n.newest, mine) then
            if C_Timer then C_Timer.After(12, function() tellNewer(n.newest) end) end
        else
            n.newest = nil
        end
        if C_Timer then
            C_Timer.After(1, hookSlash)
            C_Timer.After(6, newsAtLogin)
            C_Timer.After(8, renameNotice)
            C_Timer.After(20, announce)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if C_Timer then C_Timer.After(5, announce) end
    elseif event == "CHAT_MSG_ADDON" then
        heard(a, b, c, d)
    elseif event == "PLAYER_REGEN_ENABLED" then
        for key, text in pairs(state.pending) do
            state.pending[key] = nil
            popup(key, text)
        end
        HUB.Flush()
    end
end)

-- for tests
_G["DBagsAlertsNotices"] = { newer = newer, heard = heard, announce = announce, state = state, renameNotice = renameNotice,
    news = NEWS, newsSince = newsSince, newsAtLogin = newsAtLogin, hookSlash = hookSlash, hub = HUB }
