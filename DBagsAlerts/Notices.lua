--[[ Battle Buddy - update notices

  1. New version check. Addons can't go online or see the CurseForge app, so Battle Buddy tells
     guildmates and group members which version it is (a hidden addon message). If anyone has a
     newer one, you get one message: "Battle Buddy X is out. Update it in the CurseForge app."
     Only version numbers are sent. Nothing is sent in combat.
     Only a real release download sends its version: the release zip's .toc has
     "## X-Release-Build: 1" (added by CurseForgePublishinguild_release_zip.py). A test copy
     without it never tells anyone about a version that isn't on CurseForge yet; it still listens.
  2. Renamed notice: players who used DBagsAlerts before see one popup saying it is now Battle Buddy.

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
    end
end)

-- for tests
_G["DBagsAlertsNotices"] = { newer = newer, heard = heard, announce = announce, state = state, renameNotice = renameNotice }
