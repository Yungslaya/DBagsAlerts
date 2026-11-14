-- Read-only Legacy advice. Never buys, refunds, stages or applies talents.
-- UI/API reference: Gethe/wow-ui-source, forever, Blizzard_LegacySystem.
--
-- Builds checked 2026-11-13 against:
--   Method      "The Best Way to Spend Your Legacy Points in WoW Forever"   (leveling, professions, gatherer builds)
--   Icy Veins   "WoW Forever Legacy System Guide"                          (every talent, ranks, what each needs)
--   Mobalytics  "Legacy Points While Leveling"                             (Thrill first; Talented needs Well Rested)
--   Wowhead     WoW Forever Legacy Calculator                              (ranks and point requirements)
-- All four agree: 16 points per character; Thrill of Adventure first for outdoor leveling; Talented
-- needs 5 points in Well Rested and does nothing at level 60.
-- Where they differ: Icy Veins lists Master Chef and Luremaster as needing 10 points in Professions,
-- Wowhead's calculator says 5. The gatherer order below works either way.
local S = { rows = {}, elapsed = 0 }
DBagsAlertsState.legacyGuide = S
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return plain(value) end
end

-- A pick is found in the game by its spell ID when known, otherwise by its name.
local function pick(name, goal, max, why, id) return { name = name, goal = goal, max = max, why = why, id = id } end
local THRILL = pick("Thrill of Adventure", 5, 5, "Health and mana back after outdoor kills. Less eating and drinking.", 1225472)
local RESTED = pick("Well Rested", 5, 5, "Build rested XP faster. Also unlocks Talented.", 1225478)
local TALENTED = pick("Talented", 5, 5, "Get class talents earlier. No extra talents at level 60.", 1225474)

local builds = {
    { key = "outdoor", label = "Outdoor leveling", talented = true,
      footer = "Thrill works outdoors, not in dungeons. Talented stops helping at level 60.",
      picks = { THRILL, RESTED, TALENTED,
          pick("Field Medicine", 1, 2, "Bandage again sooner outdoors. Take one rank with your last point.", 1225475) } },
    { key = "dungeon", label = "Dungeon leveling", talented = true,
      footer = "Thrill does not work in dungeons. This route uses 10 points; save the rest for your needs.",
      picks = { RESTED, TALENTED } },
    { key = "trade", label = "Leveling + professions",
      footer = "No Talented here. The points go to faster skill-ups and cheaper, faster flights.",
      picks = { THRILL,
          pick("Working Overtime", 5, 5, "20% better chance of a skill-up in every profession."),
          pick("Field Guide", 3, 3, "Campsite features come back sooner. Needed for Frequent Flier."),
          pick("Field Medicine", 2, 2, "Bandage again 10 seconds sooner outdoors.", 1225475),
          pick("Frequent Flier", 1, 1, "Flights cost half and fly 20% faster.") } },
    { key = "gather", label = "Gathering and gold",
      footer = "For farming at any level. Master Chef and Luremaster only help if you cook and fish.",
      picks = {
          pick("Bountiful Harvest", 5, 5, "Twice the Scarce materials from mining, herbs and skinning."),
          pick("Bartering", 2, 2, "Vendors charge 10% less. Needed for Dedicated Study."),
          pick("Master Chef", 5, 5, "Half your cooking makes an extra dish."),
          pick("Dedicated Study", 1, 1, "A free skill point in your lowest profession each day."),
          pick("Luremaster", 2, 2, "Half your casts with a lure catch an extra fish."),
          pick("The Quick and the Dead", 1, 2, "Run faster as a ghost. Take one rank with your last point.") } },
}
local MAX_ROWS = 6

local function settings()
    DBagsAlertsDB = DBagsAlertsDB or {}
    DBagsAlertsDB.legacyGuide = DBagsAlertsDB.legacyGuide or {}
    local s = DBagsAlertsDB.legacyGuide
    if s.dungeons then s.mode = "dungeon" end   -- the old two-way switch
    s.dungeons = nil
    return s
end
local function build()
    local mode = settings().mode
    for _, b in ipairs(builds) do if b.key == mode then return b end end
    return builds[1]
end
local function nextBuild()
    local current = build()
    for i, b in ipairs(builds) do
        if b == current then settings().mode = builds[i % #builds + 1].key return end
    end
end

local function spellName(id)
    local name = C_Spell and read(C_Spell.GetSpellName, id)
    if type(name) == "string" then return name end
    name = read(GetSpellInfo, id)
    if type(name) == "string" then return name end
end

-- Ranks in every Legacy tree the game exposes: found[spellID] and found[talent name].
local function ranks()
    local api, consts = C_Traits, Constants and Constants.LegacyConsts
    if not api or type(consts) ~= "table" then return end
    local found, any = {}, false
    for key, tree in pairs(consts) do
        if type(key) == "string" and key:find("^LEGACY_TREE_") and type(tree) == "number" then
            local config = read(api.GetConfigIDByTreeID, tree)
            local nodes = type(config) == "number" and read(api.GetTreeNodes, tree)
            if type(nodes) == "table" then
                any = true
                for _, nodeID in ipairs(nodes) do
                    local node = read(api.GetNodeInfo, config, nodeID)
                    local entries = type(node) == "table" and plain(node.entryIDs)
                    if type(entries) == "table" then
                        for _, entryID in ipairs(entries) do
                            local entry = read(api.GetEntryInfo, config, entryID)
                            local defID = entry and plain(entry.definitionID)
                            local def = defID and read(api.GetDefinitionInfo, defID)
                            local spell = def and plain(def.spellID)
                            local rank = plain(node.currentRank)
                            if type(spell) == "number" and type(rank) == "number" then
                                local info = { rank = rank, canBuy = plain(node.canPurchaseRank) }
                                found[spell] = info
                                local name = plain(def.overrideName) or spellName(spell)
                                if type(name) == "string" and name ~= "" then found[name] = info end
                            end
                        end
                    end
                end
            end
        end
    end
    if any then return found end
end

function S.update()
    if not S.frame then return end
    local current, learned = build(), ranks()
    local list = current.picks
    local level = read(UnitLevel, "player")
    local capped = current.talented and type(level) == "number" and level >= 60
    -- The next pick is the first one not yet at its goal. A pick whose rank cannot be read stops the
    -- search there (it might be the real next one), but does not hide a next pick found before it.
    local nextPick, complete, allKnown = nil, true, true
    for i, p in ipairs(list) do
        local row = S.rows[i]
        local info = learned and (learned[p.id] or learned[p.name])
        local rank = info and info.rank
        p.info = info
        if rank == nil then
            complete = false
            if not nextPick then allKnown = false end
        end
        if rank and rank < p.goal and not nextPick and allKnown then nextPick = p; S.nextRank = rank + 1 end
        if rank and rank < p.goal then complete = false end
        row.name:SetText(p.name)
        row.rank:SetText((rank and tostring(rank) or "?") .. "/" .. p.max)
        row.why:SetText(p.why)
        row.name:SetTextColor(0.85, 0.81, 0.72)
        row.frame:Show()
    end
    for i = #list + 1, #S.rows do S.rows[i].frame:Hide() end
    if not allKnown then nextPick = nil end
    S.nextID = nextPick and (nextPick.id or nextPick.name) or nil
    S.mode:SetText(current.label .. "  (click to change)")
    if capped then
        S.nextID = nil
        S.head:SetText("Leveling finished")
        S.reason:SetText("Talented does nothing at 60. Click the button above for a build without it, like Gathering and gold.")
    elseif not allKnown then
        S.head:SetText("Your order")
        S.reason:SetText("Waiting for Legacy ranks. Open the Legacy trees; ? means unreadable, not zero. You can still follow the order below.")
    elseif nextPick then
        S.head:SetText("Next: " .. nextPick.name)
        S.reason:SetText("Take rank " .. S.nextRank .. "/" .. nextPick.max .. ". " .. nextPick.why)
        for i, p in ipairs(list) do
            if p == nextPick then S.rows[i].name:SetTextColor(1, 0.82, 0.3) end
        end
        -- A goal is not necessarily purchasable: respect points and prerequisites.
        S.note:SetText(nextPick.info.canBuy == true and "Click the talent yourself, then Apply."
            or "Next goal. You may need more points or its prerequisites.")
    else
        S.head:SetText(complete and "Picks complete" or "Your order")
        S.reason:SetText(complete and "These picks are filled. Keep earning Legacy points as you play."
            or "Some ranks are unavailable. Follow the order below once they load.")
    end
    if capped or not nextPick then S.note:SetText("Advice only. Your current choices are kept.") end
    S.footer:SetText(current.footer)
end

local function label(parent, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    f:SetPoint("TOPLEFT", x, y); f:SetWidth(width)
    f:SetJustifyH("LEFT"); f:SetWordWrap(true)
    f:SetTextColor(0.85, 0.81, 0.72)
    return f
end
local function attach()
    if S.frame then return end
    local owner = LegacySystemFrame
    if not owner or not owner.TreePage then return end
    local f = CreateFrame("Frame", "DBagsLegacyGuide", owner.TreePage, "BackdropTemplate")
    S.frame = f
    f:SetSize(280, 590)
    f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, -32)
    f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropBorderColor(0.55, 0.47, 0.3)
    local title = label(f, 16, 14, -14, 250)
    title:SetText("DBags  |  Legacy picks"); title:SetTextColor(1, 0.82, 0.3)
    local mode = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mode:SetSize(250, 24); mode:SetPoint("TOPLEFT", 14, -42)
    S.mode = mode
    mode:SetScript("OnClick", function() nextBuild(); S.update() end)
    S.head = label(f, 14, 14, -80, 250); S.head:SetTextColor(1, 0.82, 0.3)
    S.reason = label(f, 13, 14, -104, 250)
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(250, 56); row:SetPoint("TOPLEFT", 14, -172 - (i - 1) * 56)
        local name = label(row, 14, 0, 0, 205)
        local rank = label(row, 14, 215, 0, 35)
        local why = label(row, 12, 0, -20, 250)
        S.rows[i] = {frame=row, name=name, rank=rank, why=why}
    end
    S.note = label(f, 12, 14, -512, 250)
    S.footer = label(f, 11, 14, -546, 250)
    f:SetScript("OnShow", S.update)
    -- Only polls while the talent page is visible, including staged purchases/refunds.
    f:SetScript("OnUpdate", function(_, dt)
        S.elapsed = S.elapsed + dt
        if S.elapsed >= 0.35 then S.elapsed = 0; S.update() end
    end)
    S.update()
end
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", attach)
attach()
