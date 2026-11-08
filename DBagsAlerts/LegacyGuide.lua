-- Read-only Legacy advice. Never buys, refunds, stages or applies talents.
-- UI/API reference: Gethe/wow-ui-source, forever, Blizzard_LegacySystem.
-- Leveling order: Method, "The Best Way to Spend Your Legacy Points".
local S = { rows = {}, elapsed = 0 }
DBagsAlertsState.legacyGuide = S
local secret = issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return plain(value) end
end
local picks = {
    {id=1225472, name="Thrill of Adventure", goal=5, why="Health and mana back after outdoor kills. Less eating and drinking."},
    {id=1225478, name="Well Rested", goal=5, why="Build rested XP faster. Also unlocks Talented."},
    {id=1225474, name="Talented", goal=5, why="Get class talents earlier. No extra talents at level 60."},
    {id=1225475, name="Field Medicine", goal=1, max=2, why="Bandage again sooner outdoors. Take one rank with your last point."},
}
local function settings()
    DBagsAlertsDB = DBagsAlertsDB or {}
    DBagsAlertsDB.legacyGuide = DBagsAlertsDB.legacyGuide or {}
    return DBagsAlertsDB.legacyGuide
end
local function plan()
    if settings().dungeons then return {picks[2], picks[3]} end
    return picks
end
local function ranks()
    local api = C_Traits
    local tree = Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_TREE_ADVENTURE_ID
    if not api or not tree then return end
    local config = read(api.GetConfigIDByTreeID, tree)
    if type(config) ~= "number" then return end
    local nodes = read(api.GetTreeNodes, tree)
    if type(nodes) ~= "table" then return end
    local found = {}
    for _, nodeID in ipairs(nodes) do
        local node = read(api.GetNodeInfo, config, nodeID)
        if type(node) == "table" then
            local entries = plain(node.entryIDs)
            if type(entries) == "table" then
                for _, entryID in ipairs(entries) do
                    local entry = read(api.GetEntryInfo, config, entryID)
                    local defID = entry and plain(entry.definitionID)
                    local def = defID and read(api.GetDefinitionInfo, defID)
                    local spell = def and plain(def.spellID)
                    if type(spell) == "number" then
                        local rank = plain(node.currentRank)
                        if type(rank) == "number" then
                            found[spell] = {rank=rank, canBuy=plain(node.canPurchaseRank)}
                        end
                    end
                end
            end
        end
    end
    return found
end
function S.update()
    if not S.frame then return end
    local list, learned = plan(), ranks()
    local level = read(UnitLevel, "player")
    local capped = type(level) == "number" and level >= 60
    local nextPick, complete, allKnown = nil, true, true
    for i, pick in ipairs(list) do
        local row, info = S.rows[i], learned and learned[pick.id]
        local rank = info and info.rank
        if rank == nil then complete = false; allKnown = false end
        if rank and rank < pick.goal and not nextPick then nextPick = pick; S.nextRank = rank + 1 end
        if rank and rank < pick.goal then complete = false end
        row.name:SetText(pick.name)
        row.rank:SetText((rank and tostring(rank) or "?") .. "/" .. (pick.max or pick.goal))
        row.why:SetText(pick.why)
        row.name:SetTextColor(0.85, 0.81, 0.72)
        row.frame:Show()
    end
    for i=#list+1, #S.rows do S.rows[i].frame:Hide() end
    if not allKnown then nextPick = nil end
    S.nextID = nextPick and nextPick.id or nil
    S.mode:SetText(settings().dungeons and "Dungeon leveling" or "Outdoor leveling")
    if capped then
        S.nextID = nil
        S.head:SetText("Leveling finished")
        S.reason:SetText("Talented no longer helps at 60. Choose a gathering, dungeon or PvP build instead.")
    elseif not allKnown then
        S.head:SetText("Your leveling order")
        S.reason:SetText("Waiting for Legacy ranks. Open the Adventure tree; ? means unreadable, not zero.")
    elseif nextPick then
        local info = learned[nextPick.id]
        S.head:SetText("Next: " .. nextPick.name)
        S.reason:SetText("Take rank " .. S.nextRank .. "/" .. (nextPick.max or nextPick.goal) .. ". " .. nextPick.why)
        for i, pick in ipairs(list) do
            if pick == nextPick then S.rows[i].name:SetTextColor(1, 0.82, 0.3) end
        end
        -- A goal is not necessarily purchasable: respect points and prerequisites.
        S.note:SetText(info.canBuy == true and "Adventure tree. Click the talent yourself, then Apply." or "Next goal. You may need more points or its prerequisites.")
    else
        S.head:SetText(complete and "Leveling picks complete" or "Your leveling order")
        S.reason:SetText(complete and "These picks are filled. Keep earning Legacy points as you play." or "Some ranks are unavailable. Follow the order below once they load.")
    end
    if capped or not nextPick then S.note:SetText("Advice only. Your current choices are kept.") end
    S.footer:SetText(settings().dungeons and "Thrill does not work in dungeons. This route uses 10 points; save the rest for your needs." or "Thrill works outdoors, not in dungeons. Talented stops helping at level 60.")
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
    f:SetSize(280, 520)
    f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, -32)
    f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropBorderColor(0.55, 0.47, 0.3)
    local title = label(f, 16, 14, -14, 250)
    title:SetText("DBags  |  Legacy picks"); title:SetTextColor(1, 0.82, 0.3)
    local mode = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mode:SetSize(250, 24); mode:SetPoint("TOPLEFT", 14, -42)
    S.mode = mode
    mode:SetScript("OnClick", function() settings().dungeons = not settings().dungeons; S.update() end)
    S.head = label(f, 14, 14, -80, 250); S.head:SetTextColor(1, 0.82, 0.3)
    S.reason = label(f, 13, 14, -108, 250)
    for i=1,4 do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(250, 65); row:SetPoint("TOPLEFT", 14, -176-(i-1)*65)
        local name = label(row, 14, 0, 0, 205)
        local rank = label(row, 14, 215, 0, 35)
        local why = label(row, 12, 0, -22, 250)
        S.rows[i] = {frame=row, name=name, rank=rank, why=why}
    end
    S.note = label(f, 12, 14, -438, 250)
    S.footer = label(f, 11, 14, -471, 250)
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
