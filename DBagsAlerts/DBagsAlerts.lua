-- DBagsAlerts: Protection Warrior alerts for WoW Forever.
--
-- DISPLAY ONLY. This addon never casts, targets or presses anything. It lights
-- an icon when something important is ready or needed; you press the button.
--
-- WHY it looks the way it does: Forever runs the retail "secret values" system.
-- In combat many numbers (rage, health, cooldown times, auras) become secret:
-- an addon may SHOW them but not compare or do math with them. So:
--   * Plain values (readable) are checked normally in Lua.
--   * Secret values are never compared. A secret yes/no or a secret percent is
--     turned into a frame alpha by Blizzard's own curve helpers, and frames are
--     nested so the icon only shows when every condition is true (alphas
--     multiply). That is the intended, allowed way to display secret data.
--   * Our own casts stay readable in combat, so buff/debuff timers come from
--     "I cast it at time X, it lasts Y" (Y learned out of combat or from the
--     tooltip).
-- Every possibly-secret read is wrapped so a locked value never throws errors.

local ADDON = ...
local secret = issecretvalue or function() return false end
local function sectable(t) return issecrettable and issecrettable(t) or false end
local function plain(v, default) if secret(v) then return default end return v end
-- Forever moved IsCurrentSpell into C_Spell; the old global is nil there.
local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell or function() return false end

local RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local POWER = RAGE        -- rage (warrior), mana (paladin), druid: follows your form
local CLASS               -- "WARRIOR", "PALADIN", "DRUID" or "WARLOCK"
-- Druid bits live in one table (Lua allows only 200 top-level locals)
local DRU = {
    ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3,
    COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4,
    dotAt = {},          -- dot name -> target key -> time we cast it
    anyRange = false,    -- caster form: count mobs at any range, not only melee
    DOTS = { ["Moonfire"] = true, ["Insect Swarm"] = true, ["Rake"] = true, ["Rip"] = true,
             ["Faerie Fire"] = true, ["Faerie Fire (Feral)"] = true,
             -- warlock (Forever calls Curse of Agony "Bane of Agony")
             ["Corruption"] = true, ["Bane of Agony"] = true, ["Curse of Agony"] = true, ["Immolate"] = true,
             ["Siphon Life"] = true, ["Curse of the Elements"] = true, ["Curse of Weakness"] = true },
    passive = {},        -- passive spells / talents in the spellbook (name -> true)
    icons = {},          -- non-spell icons for alerts (bag items like Healthstone)
    -- GetShapeshiftFormID -> what we call it (moonkin / tree count as caster)
    FORM = { [1] = "cat", [5] = "bear", [8] = "bear", [3] = "travel", [4] = "travel",
             [27] = "travel", [29] = "travel", [2] = "caster", [31] = "caster", [36] = "caster" },
}
local ALERTS, CD_SPELLS   -- picked at login from the class tables below
local spendLine           -- function, defined with the advice code below
local tankingHard         -- function, defined with the advice code below
local DB
local function say(fmt, ...) print("|cffff7d0aDBags|r|cffc79c6eAlerts|r: " .. string.format(fmt, ...)) end

local DEFAULTS = {
    point = { "CENTER", "CENTER", 0, -170 },
    scale = 1,
    locked = true,
    off = {},            -- alert key -> true when turned off
    sunderGoal = 2,      -- Sunder stacks wanted on normal mobs (elites/bosses always 5)
    dumpAt = 70,         -- rage % to start telling you to Heroic Strike / Cleave
    lowHp = 35,          -- health % for the LOW HP warning
    sound = false,       -- raid-warning sound on danger alerts (only when not secret)
    durations = {},      -- learned buff/debuff lengths, by spell name
    tank = true,         -- paladin: tanking setup (Righteous Fury, Seal of Fury, Sanctuary)
    stack = true,        -- big-icon mode (one "press this" icon) instead of a row of icons
    names = false,       -- spell names under the big icon
    advice = false,      -- rage tip line under the rage bar
    target = true,       -- our target frame (name, health, who it's hitting)
    casts = true,        -- our cast bars (yours + your target's)
    hideBlizz = true,    -- hide Blizzard's player frame, target frame and cast bar
    style = "classic",   -- "classic" = WoW gold frames + glossy bars, "clean" = thin black lines
    cursor = true,       -- ring around the mouse cursor
    cursorSize = 48,
    cursorCombat = false,
    buffNag = true,      -- missing Battle Shout reminder, also out of combat
    stanceNag = true,    -- flashing "DEFENSIVE" in combat when you are in another stance
    foodNag = true,      -- "EAT" button when Well Fed (+5% XP in Forever) is missing and you carry food
    stoneNag = true,     -- weapon stone button when your main hand has no stone on it
    stoneNeed = true,    -- ...and a grey "no stone" icon when you have none
    range = true,        -- melee range ring around the big icon
    lowMana = 20,        -- paladin: mana % for the LOW MANA warning
    dumpTank = 90,       -- warrior: spend line while you are getting hit a lot
    shardGoal = 5,       -- warlock: Soul Shards to keep (Drain Soul alert below this)
}

-- Fallback lengths when neither the aura nor the tooltip tells us.
local DEFAULT_DURATION = {
    ["Shield Block"] = 5, ["Battle Shout"] = 120, ["Demoralizing Shout"] = 30,
    ["Thunder Clap"] = 10, ["Sunder Armor"] = 30, ["Rend"] = 21,     -- Icy Veins: Rend lasts 21 sec
    ["Righteous Fury"] = 1800, ["Holy Shield"] = 10, ["Consecration"] = 8,
}
for _, s in ipairs({ "Seal of Fury", "Seal of Righteousness", "Seal of Command", "Seal of the Crusader",
    "Seal of Wisdom", "Seal of Light", "Seal of Justice" }) do DEFAULT_DURATION[s] = 30 end
for _, b in ipairs({ "Blessing of Sanctuary", "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom" }) do
    DEFAULT_DURATION[b] = 300; DEFAULT_DURATION["Greater " .. b] = 900
end

for k, v in pairs({ ["Moonfire"] = 12, ["Insect Swarm"] = 12, ["Rake"] = 9, ["Rip"] = 12,
    ["Faerie Fire"] = 40, ["Faerie Fire (Feral)"] = 40, ["Demoralizing Roar"] = 30, ["Thorns"] = 600,
    ["Mark of the Wild"] = 1800, ["Gift of the Wild"] = 3600, ["Rejuvenation"] = 12 }) do
    DEFAULT_DURATION[k] = v
end
for k, v in pairs({ ["Corruption"] = 18, ["Bane of Agony"] = 24, ["Curse of Agony"] = 24, ["Immolate"] = 15,
    ["Siphon Life"] = 30, ["Curse of the Elements"] = 300, ["Curse of Weakness"] = 120, ["Demon Skin"] = 1800,
    ["Demon Armor"] = 1800, ["Demonic Sacrifice"] = 7200, ["Searing Pain"] = 10 }) do
    DEFAULT_DURATION[k] = v
end

-- Buffs we follow by our own casts. A group means "any one of these counts"
-- (one seal at a time, one blessing on you, one aura).
local GROUPS = {
    ["Shield Block"] = { "Shield Block" },
    ["Battle Shout"] = { "Battle Shout" },
    ["Demoralizing Shout"] = { "Demoralizing Shout" },
    ["Thunder Clap"] = { "Thunder Clap" },
    ["Righteous Fury"] = { "Righteous Fury" },
    ["Holy Shield"] = { "Holy Shield" },
    ["Consecration"] = { "Consecration" },
    MOTW = { "Mark of the Wild", "Gift of the Wild" },
    ["Thorns"] = { "Thorns" },
    ["Rejuvenation"] = { "Rejuvenation" },
    ["Demoralizing Roar"] = { "Demoralizing Roar" },
    ARMOR = { "Demon Armor", "Demon Skin", "Fel Armor" },
    -- Demonic Sacrifice buffs (Imp / Voidwalker / Succubus / Felhunter), or our own cast of it
    SACRIFICE = { "Demonic Sacrifice", "Touch of Shadow", "Fel Stamina", "Burning Wish", "Fel Energy" },
    SOULLINK = { "Soul Link" },
    BRAND = { "Searing Pain" },        -- Demonic Brand: Searing Pain brands the target for 10 sec
    SEAL = { "Seal of Fury", "Seal of Righteousness", "Seal of Command", "Seal of the Crusader",
             "Seal of Wisdom", "Seal of Light", "Seal of Justice" },
    BLESSING = { "Blessing of Sanctuary", "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom",
                 "Greater Blessing of Sanctuary", "Greater Blessing of Kings", "Greater Blessing of Might",
                 "Greater Blessing of Wisdom" },
    AURA = { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Crusader Aura",
             "Fire Resistance Aura", "Frost Resistance Aura", "Shadow Resistance Aura" },
}
local GROUP_OF = {}
for key, names in pairs(GROUPS) do for _, n in ipairs(names) do GROUP_OF[n] = key end end
local PERMANENT = { AURA = true, SOULLINK = true }       -- auras last until changed
-- Which groups to re-read from real aura data whenever it is readable.
local READ = {
    WARRIOR = { "Battle Shout", "Shield Block" },
    PALADIN = { "Righteous Fury", "SEAL", "BLESSING", "AURA", "Holy Shield" },
    DRUID = { "MOTW", "Thorns", "Rejuvenation" },
    WARLOCK = { "ARMOR", "SACRIFICE", "SOULLINK" },
}

---------------------------------------------------------------------------
-- Spellbook: name -> highest learned rank's spellID
---------------------------------------------------------------------------
local spell = {}
local function rankOf(id)
    local sub = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if type(sub) ~= "string" or secret(sub) then return 0 end
    return tonumber(sub:match("%d+")) or 0
end

local function buildSpells()
    wipe(spell)
    wipe(DRU.passive)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local best = {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if item and item.spellID and not item.isPassive and type(item.name) == "string"
                    and not secret(item.name) and (SPELL == nil or item.itemType == SPELL) then
                    local r = rankOf(item.spellID)
                    if not best[item.name] or r >= best[item.name] then
                        best[item.name] = r
                        spell[item.name] = item.spellID
                    end
                elseif item and item.isPassive and type(item.name) == "string" and not secret(item.name) then
                    DRU.passive[item.name] = true      -- talents like Shadow and Flame
                end
            end
        end
    end
end

local durCache = {}       -- tooltip-parsed lengths; reading tooltips every tick is slow
local function durationOf(name)
    if DB.durations[name] then return DB.durations[name] end
    if durCache[name] then return durCache[name] end
    local id = spell[name]
    local d = id and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id)
    local n
    if type(d) == "string" and not secret(d) then
        n = tonumber(d:match("for (%d+) sec") or d:match("over (%d+) sec") or d:match("[Ll]asts (%d+) sec"))
    end
    n = n or DEFAULT_DURATION[name] or 10
    durCache[name] = n
    return n
end

---------------------------------------------------------------------------
-- Readers that never throw. They return a plain boolean, or a secret one.
---------------------------------------------------------------------------
local function ready(name)
    local id = spell[name]
    if not id then return false end
    local ok, c = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(c) ~= "table" or sectable(c) then return true end
    if not secret(c.isOnGCD) and c.isOnGCD == true then return true end
    if secret(c.isActive) then return { secretInv = true, v = c.isActive } end -- secret: "ready" = not active
    if c.isActive ~= nil then return not c.isActive end
    if secret(c.duration) then return true end
    return (c.duration or 0) <= 1.5
end

local function usable(name)
    local id = spell[name]
    if not id then return false end
    local ok, u = pcall(C_Spell.IsSpellUsable, id)
    if not ok then return true end
    return u
end

---------------------------------------------------------------------------
-- Condition gates. A state collects plain checks (all must be true) and
-- secret alphas (handed to nested frames, never inspected).
---------------------------------------------------------------------------
local function need(st, v, invert)
    if not st.ok then return end
    if type(v) == "table" and not sectable(v) and rawget(v, "secretInv") == true then -- wrapped secret from ready()
        v, invert = v.v, not invert
    end
    if secret(v) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local ok, a = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, v, invert and 0 or 1, invert and 1 or 0)
            if ok then st.n = st.n + 1; st[st.n] = a end
        end
        return
    end
    local b = v and true or false
    if invert then b = not b end
    if not b then st.ok = false end
end

local function needAlpha(st, a)
    if not st.ok then return end
    if not a then return end
    if secret(a) then st.n = st.n + 1; st[st.n] = a return end
    if a < 0.5 then st.ok = false end
end

local curves = {}
local function stepCurve(key, below, frac)
    if curves[key] ~= nil then return curves[key] or nil end
    local ok, c = pcall(function()
        local cv = C_CurveUtil.CreateCurve()
        cv:SetType(Enum.LuaCurveType.Step)
        if below then cv:AddPoint(0, 1); cv:AddPoint(frac, 0)
        else cv:AddPoint(0, 0); cv:AddPoint(frac, 1) end
        return cv
    end)
    curves[key] = ok and c or false
    return ok and c or nil
end

-- power (rage or mana) >= pct%  (below=false)  or  < pct%  (below=true)
local function needRage(st, pct, below)
    if not st.ok then return end
    local r, m = UnitPower("player", POWER), UnitPowerMax("player", POWER)
    if not secret(r) and not secret(m) then
        local frac = (m and m > 0) and r / m or 0
        if below then need(st, frac < pct / 100) else need(st, frac >= pct / 100) end
        return
    end
    local cv = UnitPowerPercent and stepCurve("rage" .. pct .. tostring(below), below, pct / 100)
    if not cv then return end
    local ok, a = pcall(UnitPowerPercent, "player", POWER, false, cv)
    if ok then needAlpha(st, a) end
end

local function needLowHealth(st, pct)
    if not st.ok then return end
    local h, m = UnitHealth("player"), UnitHealthMax("player")
    if not secret(h) and not secret(m) then
        need(st, m and m > 0 and h / m < pct / 100)
        return
    end
    local cv = UnitHealthPercent and stepCurve("hp" .. pct, true, pct / 100)
    if not cv then st.ok = false return end
    local ok, a = pcall(UnitHealthPercent, "player", false, cv)
    if ok then needAlpha(st, a) else st.ok = false end
end

-- Target health above pct% (Icy Veins: don't Sunder/Rend a mob that's about to die).
-- If it can't be read at all, don't block the alert.
local function needTargetAbove(st, pct)
    if not st.ok then return end
    local h, m = UnitHealth("target"), UnitHealthMax("target")
    if not secret(h) and not secret(m) then
        if m and m > 0 then need(st, h / m >= pct / 100) end
        return
    end
    local cv = UnitHealthPercent and stepCurve("thp" .. pct, false, pct / 100)
    if not cv then return end
    local ok, a = pcall(UnitHealthPercent, "target", false, cv)
    if ok then needAlpha(st, a) end
end

---------------------------------------------------------------------------
-- Our own casts -> timers (readable in combat)
---------------------------------------------------------------------------
local expires = {}       -- buff/aoe debuff name -> GetTime() it runs out
local sunder = {}        -- target key -> { n = stacks, last = time }
local rendAt = {}        -- target key -> time cast

local lastDebuff             -- { name, at, key } of our last Rend / Sunder cast
local function targetKey()
    local g = UnitGUID("target")
    if g == nil or secret(g) then return "?" end
    return g
end

local function onCast(spellID)
    if spellID == nil or secret(spellID) then return end
    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if type(name) ~= "string" or secret(name) then return end
    local now = GetTime()
    local group = GROUP_OF[name]
    if group then
        expires[group] = PERMANENT[group] and math.huge or now + durationOf(name)
    end
    if name == "Sunder Armor" then
        local k = targetKey()
        local s = sunder[k]
        if not s or now - s.last > durationOf("Sunder Armor") then s = { n = 0 } end
        s.n, s.last = math.min(5, s.n + 1), now
        sunder[k] = s
        lastDebuff = { name = name, at = now, key = k }
    elseif name == "Rend" then
        local k = targetKey()
        rendAt[k] = now
        lastDebuff = { name = name, at = now, key = k }
    elseif DRU.DOTS[name] then
        local k = targetKey()
        DRU.dotAt[name] = DRU.dotAt[name] or {}
        DRU.dotAt[name][k] = now
        lastDebuff = { name = name, at = now, key = k }
    end
end

-- The game counts a dodged / parried / missed Rend or Sunder as "cast". If the
-- target dodges, parries or is immune right after our cast, take it back so the
-- alert comes back instead of waiting out a timer for a debuff that isn't there.
local MISSED = { DODGE = true, PARRY = true, MISS = true, IMMUNE = true, EVADE = true, RESIST = true, DEFLECT = true }
local function onTargetCombat(action)
    local ld = lastDebuff
    if not ld or secret(action) or not MISSED[action] then return end
    if GetTime() - ld.at > 0.35 then lastDebuff = nil return end
    if ld.name == "Rend" then
        rendAt[ld.key] = nil
    elseif ld.name == "Sunder Armor" and sunder[ld.key] then
        sunder[ld.key].n = math.max(0, sunder[ld.key].n - 1)
    elseif DRU.dotAt[ld.name] then
        DRU.dotAt[ld.name][ld.key] = nil
    end
    lastDebuff = nil
end

local function timeLeft(name) return (expires[name] or 0) - GetTime() end

-- Is OUR debuff really on the target? "on" (+ aura data), "off", or nil when the
-- game won't say (combat lock). When it does say, it beats our timers.
local function targetDebuff(name)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local okR, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        if not okR or secret(restricted) then return nil end
        if restricted then
            local id = spell[name]
            local okS, s = false, nil
            if id and C_Secrets.ShouldSpellAuraBeSecret then okS, s = pcall(C_Secrets.ShouldSpellAuraBeSecret, id) end
            if not (okS and not secret(s) and s == false) then return nil end
        end
    end
    local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HARMFUL|PLAYER")
    if not ok or secret(a) or sectable(a) then return nil end
    if a then return "on", a end
    return "off"
end

-- Out of combat the buff itself is readable: correct our timers and learn lengths.
local function readBuff(key)
    if InCombatLockdown() or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return end
    for _, name in ipairs(GROUPS[key] or { key }) do
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if not ok or secret(a) or sectable(a) then return end   -- unreadable: keep our cast timer
        if a then
            if secret(a.expirationTime) or secret(a.duration) then return end
            if (a.duration or 0) > 0 then
                expires[key] = a.expirationTime
                DB.durations[name] = a.duration
            else
                expires[key] = math.huge
            end
            return
        end
    end
    expires[key] = 0   -- readable, and none of them is on you
end

local function readAll()
    for _, key in ipairs(READ[CLASS] or {}) do readBuff(key) end
end

-- any power type >= pct% (or < pct% with below); secret values go through a curve
function DRU.needPower(st, ptype, pct, below)
    if not st.ok then return end
    local r, m = UnitPower("player", ptype), UnitPowerMax("player", ptype)
    if not secret(r) and not secret(m) then
        local frac = (m and m > 0) and r / m or 0
        if below then need(st, frac < pct / 100) else need(st, frac >= pct / 100) end
        return
    end
    local cv = UnitPowerPercent and stepCurve("pw" .. ptype .. "_" .. pct .. tostring(below), below, pct / 100)
    if not cv then return end
    local ok, a = pcall(UnitPowerPercent, "player", ptype, false, cv)
    if ok then needAlpha(st, a) end
end
-- at least n combo points (cat form)
function DRU.needCP(st, n)
    if not st.ok then return end
    local c = UnitPower("player", DRU.COMBO)
    if not secret(c) then need(st, (c or 0) >= n) return end
    DRU.needPower(st, DRU.COMBO, n / 5 * 100 - 1, false)
end
-- our dot needs (re)applying: the real debuff when the game shares it, else our cast
-- timer. refresh = part of the duration left when it's worth refreshing (0 = let it end).
function DRU.dotGone(name, refresh)     -- plain true/false
    local t = DRU.dotAt[name]
    local at = t and t[targetKey()]
    local real, aura = targetDebuff(name)
    local d = durationOf(name)
    local now = GetTime()
    if real == "on" then
        local exp = aura and plain(aura.expirationTime, nil)
        return (exp and exp > 0 and exp - now <= d * refresh) and true or false
    elseif real == "off" then return not at or now - at > 1   -- 1s: it lands just after the cast
    end
    return not at or now - at > d * (1 - refresh)
end
function DRU.needDot(st, name, refresh)
    if not st.ok then return end
    need(st, DRU.dotGone(name, refresh))
end
-- unit health above pct% (below=false) or under pct% (below=true); unreadable = no block
function DRU.needUnitHP(st, unit, pct, below)
    if not st.ok then return end
    local h, m = UnitHealth(unit), UnitHealthMax(unit)
    if not secret(h) and not secret(m) then
        if m and m > 0 then
            if below then need(st, h / m < pct / 100) else need(st, h / m >= pct / 100) end
        end
        return
    end
    local cv = UnitHealthPercent and stepCurve("uhp" .. unit .. pct .. tostring(below), below, pct / 100)
    if not cv then return end
    local ok, a = pcall(UnitHealthPercent, unit, false, cv)
    if ok then needAlpha(st, a) end
end

---------------------------------------------------------------------------
-- Rage gain per hit (only while rage is readable)
---------------------------------------------------------------------------
local lastRage, gains = nil, {}
local function onRage()
    local r = UnitPower("player", RAGE)
    if secret(r) then lastRage = nil return end
    if lastRage and r > lastRage then
        table.insert(gains, r - lastRage)
        if #gains > 8 then table.remove(gains, 1) end
    end
    lastRage = r
end
local function avgGain()
    if #gains == 0 then return nil end
    local s = 0
    for _, g in ipairs(gains) do s = s + g end
    return s / #gains
end

---------------------------------------------------------------------------
-- Enemy count + loose mobs from nameplates (turn enemy nameplates on: V)
---------------------------------------------------------------------------
local scanAt, scanN, scanLoose = 0, nil, nil
local scanMates = {}        -- reused list of group unit tokens
local scanEnemiesNow
local function scanEnemies()   -- counting nameplates 3x a second is plenty
    local now = GetTime()
    if now - scanAt >= 0.3 then scanAt = now; scanN, scanLoose = scanEnemiesNow() end
    return scanN, scanLoose
end
scanEnemiesNow = function()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil, nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" or sectable(plates) then return nil, nil end
    local melee = spell["Sunder Armor"] or spell["Heroic Strike"] or spell["Holy Strike"] or spell["Crusader Strike"]
        or spell["Claw"] or spell["Maul"]
    if DRU.anyRange then melee = nil end
    local grouped = IsInGroup()
    -- your group, without you (for "is this mob hitting a friend?")
    local mates = scanMates
    wipe(mates)
    if grouped then
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local m = "raid" .. i
                if not plain(UnitIsUnit(m, "player"), false) then mates[#mates + 1] = m end
            end
        else
            for i = 1, 4 do mates[#mates + 1] = "party" .. i end
        end
    end
    local n, loose, unknown = 0, 0, false
    for _, p in ipairs(plates) do
        local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
        if u and not secret(u) then
            local atk, dead = UnitCanAttack("player", u), UnitIsDead(u)
            if secret(atk) or secret(dead) then
                unknown = true
            elseif atk and not dead then
                -- Only mobs fighting YOU: you're on their threat list (you hit them or
                -- they're hitting you). Mobs fighting other players don't count.
                local s = UnitThreatSituation("player", u)
                local mine
                if secret(s) then
                    local cmb = UnitAffectingCombat(u)      -- locked: best guess
                    if secret(cmb) then unknown = true; mine = false else mine = cmb and true or false end
                else
                    mine = s ~= nil
                end
                if mine then
                    local inRange = true
                    if melee and C_Spell.IsSpellInRange then
                        local okR, r = pcall(C_Spell.IsSpellInRange, melee, u)
                        if okR and not secret(r) and r == false then inRange = false end
                    end
                    if inRange then n = n + 1 end
                end
                -- Loose = attacking someone in your group (they have its aggro), not you.
                if grouped then
                    for _, m in ipairs(mates) do
                        local ms = UnitThreatSituation(m, u)
                        if not secret(ms) and ms and ms >= 2 then loose = loose + 1; break end
                    end
                end
            end
        end
    end
    if unknown and n == 0 then return nil, nil end
    return n, grouped and loose or 0
end

---------------------------------------------------------------------------
-- Alerts. Order inside a row = priority (left = most important).
---------------------------------------------------------------------------
local ctx = {}
DBagsAlertsState = { ctx = ctx }   -- read-only peek for /pa debug and testing

local WARRIOR_ALERTS = {
    -- DANGER ROW
    { key = "lowhp", row = 1, label = "LOW HP", danger = true, icon = "Shield Wall",
      test = function(st)
          need(st, ctx.combat)
          -- Icy Veins: Shield Wall BEFORE the big hits, so warn earlier (50%) while getting hit a lot
          needLowHealth(st, (tankingHard and tankingHard()) and math.max(DB.lowHp, 50) or DB.lowHp)
          if st.ok then
              local r = ready("Shield Wall")
              if spell["Shield Wall"] and r == true then return "Shield Wall", "SHIELD WALL" end
              r = ready("Last Stand")
              if spell["Last Stand"] and r == true then return "Last Stand", "LAST STAND" end
          end
      end },
    { key = "taunt", row = 1, label = "TAUNT", danger = true, icon = "Taunt",
      test = function(st)
          need(st, ctx.combat and ctx.group and ctx.hostile)
          need(st, ready("Taunt")); need(st, usable("Taunt"))
          if not st.ok then return end
          local isTanking = UnitDetailedThreatSituation("player", "target")
          need(st, isTanking, true)
      end },
    { key = "kick", row = 1, label = "INTERRUPT", danger = true, icon = "Shield Bash",
      test = function(st)
          local k = spell["Shield Bash"] and "Shield Bash" or (spell["Pummel"] and "Pummel")
          need(st, k and ctx.combat and ctx.hostile)
          if not st.ok then return end
          need(st, ready(k)); need(st, usable(k))
          if not st.ok then return end
          local cname, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
          if not cname then cname, _, _, _, _, _, notInt = UnitChannelInfo("target") end
          need(st, cname and true or false)
          need(st, notInt, true)
          return k
      end },
    { key = "loose", row = 1, label = "LOOSE", danger = true, icon = "Taunt",
      test = function(st)
          need(st, ctx.combat and ctx.group and (ctx.loose or 0) > 0)
          if st.ok then return nil, "LOOSE MOBS " .. ctx.loose end
      end },

    -- ACTION ROW
    { key = "block", row = 2, label = "SHIELD BLOCK", icon = "Shield Block",
      test = function(st)
          -- Icy Veins: on cooldown against melee (it's off the global cooldown)
          need(st, ctx.combat and ctx.hostile)
          need(st, ready("Shield Block")); need(st, usable("Shield Block"))
      end },
    { key = "revenge", row = 2, label = "REVENGE", icon = "Revenge",
      test = function(st)
          need(st, ctx.combat); need(st, ready("Revenge")); need(st, usable("Revenge"))
      end },
    { key = "slam", row = 2, label = "SHIELD SLAM", icon = "Shield Slam",
      test = function(st)
          need(st, ctx.combat and ctx.hostile); need(st, ready("Shield Slam")); need(st, usable("Shield Slam"))
      end },
    { key = "vrush", row = 2, label = "VICTORY RUSH", icon = "Victory Rush",
      test = function(st)
          need(st, ctx.hostile); need(st, ready("Victory Rush")); need(st, usable("Victory Rush"))
      end },
    { key = "clap", row = 2, label = "THUNDER CLAP", icon = "Thunder Clap",
      test = function(st)
          -- Icy Veins tank page: "Use it when ready" - one mob or a pack
          need(st, ctx.combat and ctx.hostile)
          need(st, ready("Thunder Clap")); need(st, usable("Thunder Clap"))
      end },
    { key = "demo", row = 2, label = "DEMO SHOUT", icon = "Demoralizing Shout",
      test = function(st)
          -- Icy Veins (Forever prot leveling): "Use Demoralizing Shout early in the fight
          -- to reduce damage taken" - single mob AND packs. Less damage = less eating.
          -- Skipped when the mob is almost dead (wasted rage).
          need(st, ctx.combat and ctx.hostile and timeLeft("Demoralizing Shout") <= durationOf("Demoralizing Shout") * 0.3)   -- pandemic: refresh at 30% left
          need(st, usable("Demoralizing Shout"))
          if (ctx.enemies or 0) < 2 and not ctx.elite then needTargetAbove(st, 40) end
      end },
    { key = "execute", row = 2, label = "EXECUTE", icon = "Execute",
      test = function(st)
          need(st, ctx.combat and ctx.hostile); need(st, ready("Execute")); need(st, usable("Execute"))
      end },
    { key = "dump", row = 2, label = "SPEND RAGE", icon = "Heroic Strike",
      test = function(st)
          local cleave = (ctx.enemies or 0) >= 2 and spell["Cleave"]
          local name = cleave and "Cleave" or "Heroic Strike"
          need(st, ctx.combat and ctx.hostile and spell[name])
          if not st.ok then return end
          local queued = IsCurrentSpell(spell[name])
          need(st, queued, true)          -- already queued? then stay quiet
          needRage(st, spendLine and spendLine() or DB.dumpAt, false)
          return name, cleave and "CLEAVE" or "HEROIC STRIKE"
      end },
    { key = "sunder", row = 2, label = "SUNDER", icon = "Sunder Armor",
      test = function(st)
          need(st, ctx.combat and ctx.hostile)
          if not st.ok then return end
          local s = sunder[targetKey()]
          local stacks = (s and GetTime() - s.last < durationOf("Sunder Armor")) and s.n or 0
          local real, aura = targetDebuff("Sunder Armor")          -- real stacks when readable
          if real == "off" then stacks = 0
          elseif real == "on" then stacks = plain(aura.applications, stacks) or stacks end
          local goal = ctx.elite and 5 or DB.sunderGoal
          need(st, stacks < goal)
          need(st, usable("Sunder Armor"))
          needTargetAbove(st, 30)
          if st.ok then return nil, "SUNDER " .. stacks .. "/" .. goal end
      end },
    { key = "rend", row = 2, label = "REND", icon = "Rend",
      test = function(st)
          need(st, ctx.combat and ctx.hostile and not ctx.bleedImmune)
          if not st.ok then return end
          local at = rendAt[targetKey()]
          local real, aura = targetDebuff("Rend")                 -- the truth, when the game shares it
          local d = durationOf("Rend")
          if real == "on" then                                     -- refresh in the pandemic window (30% left)
              local exp = aura and plain(aura.expirationTime, nil)
              need(st, exp and exp > 0 and exp - GetTime() <= d * 0.3)
          elseif real == "off" then need(st, not at or GetTime() - at > 1)   -- 1s: it lands just after the cast
          else need(st, not at or GetTime() - at > d * 0.7) end
          need(st, usable("Rend"))
          needTargetAbove(st, 40)        -- not on a mob that is about to die
      end },
    { key = "shout", row = 2, label = "BATTLE SHOUT", icon = "Battle Shout",
      test = function(st)
          need(st, DB.buffNag == false)   -- the buff reminder icon shows it instead (no doubles)
          need(st, spell["Battle Shout"] and timeLeft("Battle Shout") <= 10 and not IsMounted())
          need(st, usable("Battle Shout"))
      end },
    { key = "bloodrage", row = 2, label = "BLOODRAGE", icon = "Bloodrage",
      test = function(st)
          need(st, ready("Bloodrage")); need(st, usable("Bloodrage"))
          if not st.ok then return end
          if ctx.combat then needRage(st, 20, true) else need(st, ctx.hostile) end
      end },
}

-- First spell in the list that you know (and, if wanted, that is ready right now).
local function firstKnown(list, mustBeReady)
    for _, n in ipairs(list) do
        if spell[n] and (not mustBeReady or ready(n) == true) then return n end
    end
end

local SEAL_TANK = { "Seal of Fury", "Seal of Righteousness" }
local SEAL_DPS = { "Seal of Righteousness", "Seal of Command", "Seal of Fury" }
local BLESS_TANK = { "Blessing of Sanctuary", "Blessing of Kings", "Blessing of Might" }
local BLESS_DPS = { "Blessing of Might", "Blessing of Kings", "Blessing of Sanctuary" }
local AURAS = { "Devotion Aura", "Retribution Aura" }
local PALLY_SAVES = { "Templar's Bulwark", "Divine Protection", "Divine Shield", "Lay on Hands" }
local PALLY_TAUNTS = { "Hand of Reckoning", "Righteous Defense" }
local PALLY_KICKS = { "Rebuke", "Hammer of Justice" }

local PALADIN_ALERTS = {
    -- DANGER ROW
    { key = "lowhp", row = 1, label = "LOW HP", danger = true, icon = "Templar's Bulwark",
      test = function(st)
          need(st, ctx.combat)
          needLowHealth(st, DB.lowHp)
          if st.ok then
              local n = firstKnown(PALLY_SAVES, true)
              if n then return n, n:upper() end
          end
      end },
    { key = "taunt", row = 1, label = "TAUNT", danger = true, icon = "Judgement",
      test = function(st)
          -- Righteous Defense / Hand of Reckoning if you have them, else Judgement (taunts with Seal of Fury).
          local t = firstKnown(PALLY_TAUNTS)
          local judge = not t
          t = t or "Judgement"
          -- Icy Veins: Swift Judgement is the backup taunt while Judgement is on cooldown
          if judge and ready("Judgement") ~= true and spell["Swift Judgement"] and ready("Swift Judgement") == true then
              t = "Swift Judgement"
          end
          need(st, ctx.combat and ctx.group and ctx.hostile and spell[t])
          if judge then need(st, timeLeft("SEAL") > 0) end
          need(st, ready(t)); need(st, usable(t))
          if not st.ok then return end
          local isTanking = UnitDetailedThreatSituation("player", "target")
          need(st, isTanking, true)
          return t, judge and "TAUNT (JUDGE)" or "TAUNT"
      end },
    { key = "kick", row = 1, label = "STUN IT", danger = true, icon = "Hammer of Justice",
      test = function(st)
          local k = firstKnown(PALLY_KICKS)
          need(st, k and ctx.combat and ctx.hostile)
          if not st.ok then return end
          need(st, ready(k)); need(st, usable(k))
          if not st.ok then return end
          local cname, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
          if not cname then cname, _, _, _, _, _, notInt = UnitChannelInfo("target") end
          need(st, cname and true or false)
          need(st, notInt, true)
          return k, k == "Rebuke" and "INTERRUPT" or "STUN IT"
      end },
    { key = "loose", row = 1, label = "LOOSE", danger = true, icon = "Judgement",
      test = function(st)
          need(st, ctx.combat and ctx.group and (ctx.loose or 0) > 0)
          if st.ok then return nil, "LOOSE MOBS " .. ctx.loose end
      end },

    -- ACTION ROW
    { key = "rfury", row = 2, label = "RIGHTEOUS FURY", icon = "Righteous Fury",
      test = function(st)
          need(st, DB.tank and spell["Righteous Fury"] and timeLeft("Righteous Fury") <= 10 and not IsMounted())
          need(st, usable("Righteous Fury"))
      end },
    { key = "seal", row = 2, label = "SEAL", icon = "Seal of Righteousness",
      test = function(st)
          local s = firstKnown(DB.tank and SEAL_TANK or SEAL_DPS)
          need(st, s and timeLeft("SEAL") <= 2 and (ctx.combat or ctx.hostile))
          if not st.ok then return end
          need(st, usable(s))
          return s, s == "Seal of Fury" and "SEAL (FURY)" or "SEAL"
      end },
    { key = "holyshield", row = 2, label = "HOLY SHIELD", icon = "Holy Shield",
      test = function(st)
          need(st, ctx.combat and ctx.hostile and timeLeft("Holy Shield") <= 0.5)
          need(st, ready("Holy Shield")); need(st, usable("Holy Shield"))
      end },
    { key = "swift", row = 2, label = "SWIFT JUDGE", icon = "Swift Judgement",
      test = function(st)
          need(st, ctx.combat and ctx.hostile); need(st, ready("Swift Judgement")); need(st, usable("Swift Judgement"))
      end },
    { key = "judge", row = 2, label = "JUDGE", icon = "Judgement",
      test = function(st)
          need(st, ctx.combat and ctx.hostile and timeLeft("SEAL") > 0)
          need(st, ready("Judgement")); need(st, usable("Judgement"))
      end },
    { key = "consecrate", row = 2, label = "CONSECRATE", icon = "Consecration",
      test = function(st)
          -- Icy Veins: as much as mana allows. Packs: from 25% mana. One mob: from 50%.
          need(st, ctx.combat and ctx.hostile and timeLeft("Consecration") <= 0)
          need(st, ready("Consecration")); need(st, usable("Consecration"))
          needRage(st, ((ctx.enemies or 0) >= 2 or ctx.elite) and 25 or 50, false)
      end },
    { key = "holystrike", row = 2, label = "HOLY STRIKE", icon = "Holy Strike",
      test = function(st)
          need(st, ctx.combat and ctx.hostile); need(st, ready("Holy Strike")); need(st, usable("Holy Strike"))
      end },
    { key = "exorcism", row = 2, label = "EXORCISM", icon = "Exorcism",
      test = function(st)
          need(st, ctx.combat and ctx.hostile and (ctx.ctype == "Undead" or ctx.ctype == "Demon"))
          need(st, ready("Exorcism")); need(st, usable("Exorcism"))
      end },
    { key = "wrath", row = 2, label = "HAMMER OF WRATH", icon = "Hammer of Wrath",
      test = function(st)
          -- has a cast time: Icy Veins says only when you're not tanking
          need(st, ctx.combat and ctx.hostile and not DB.tank)
          need(st, ready("Hammer of Wrath")); need(st, usable("Hammer of Wrath"))
      end },
    { key = "lowmana", row = 2, label = "LOW MANA", icon = "Seal of Wisdom",
      test = function(st)
          need(st, ctx.combat)
          needRage(st, DB.lowMana, true)
      end },
    { key = "bless", row = 2, label = "BLESSING", icon = "Blessing of Might",
      test = function(st)
          local b = firstKnown(DB.tank and BLESS_TANK or BLESS_DPS)
          need(st, b and timeLeft("BLESSING") <= 10 and not IsMounted())
          if not st.ok then return end
          need(st, usable(b))
          return b
      end },
    { key = "aura", row = 2, label = "AURA", icon = "Devotion Aura",
      test = function(st)
          local a = firstKnown(AURAS)
          need(st, a and timeLeft("AURA") <= 0)
          return a
      end },
}

-- Druid: every alert checks your form, so Bear / Cat / caster each get their own
-- rotation. Order and rules: Icy Veins WoW Forever Feral, Balance and Restoration
-- leveling guides (Nov 2026).
local function inForm(f) return ctx.form == f end
local function castingTarget(st)
    local cname, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
    if not cname then cname, _, _, _, _, _, notInt = UnitChannelInfo("target") end
    need(st, cname and true or false)
    need(st, notInt, true)
end
local DRUID_ALERTS = {
    -- DANGER ROW
    { key = "lowhp", row = 1, label = "LOW HP", danger = true, icon = "Barkskin",
      test = function(st)
          need(st, ctx.combat)
          needLowHealth(st, (inForm("bear") and tankingHard and tankingHard()) and math.max(DB.lowHp, 50) or DB.lowHp)
          if st.ok then
              local list = inForm("bear") and { "Frenzied Regeneration", "Barkskin" }
                  or inForm("cat") and { "Barkskin" } or { "Barkskin", "Regrowth" }
              local n = firstKnown(list, true)
              if n then return n, n:upper() end
          end
      end },
    { key = "kick", row = 1, label = "STOP CAST", danger = true, icon = "Bash",
      test = function(st)
          local k = firstKnown({ "Bash", "Feral Charge" }, true)
          need(st, inForm("bear") and k and ctx.combat and ctx.hostile)
          if not st.ok then return end
          need(st, usable(k))
          castingTarget(st)
          return k, "STOP CAST"
      end },
    { key = "taunt", row = 1, label = "GROWL", danger = true, icon = "Growl",
      test = function(st)
          need(st, inForm("bear") and ctx.combat and ctx.group and ctx.hostile and spell["Growl"])
          need(st, ready("Growl")); need(st, usable("Growl"))
          if not st.ok then return end
          local isTanking = UnitDetailedThreatSituation("player", "target")
          need(st, isTanking, true)
      end },
    { key = "loose", row = 1, label = "LOOSE", danger = true, icon = "Growl",
      test = function(st)
          need(st, inForm("bear") and ctx.combat and ctx.group and (ctx.loose or 0) > 0)
          if st.ok then return nil, "LOOSE MOBS " .. ctx.loose end
      end },

    -- CAT: open from Prowl, Rip at 4+ points, keep Rake up, Claw (Shred when behind)
    { key = "copen", row = 2, label = "OPENER", icon = "Ravage",
      test = function(st)
          local n = firstKnown({ "Ravage", "Shred" })
          need(st, inForm("cat") and ctx.stealth and ctx.hostile and n)
          if not st.ok then return end
          need(st, usable(n))
          return n, n:upper()
      end },
    { key = "rip", row = 2, label = "RIP", icon = "Rip",
      test = function(st)
          need(st, inForm("cat") and ctx.combat and ctx.hostile and spell["Rip"] and not ctx.bleedImmune)
          DRU.needCP(st, 4)
          DRU.needDot(st, "Rip", 0)
          need(st, usable("Rip"))
          if not ctx.elite then needTargetAbove(st, 40) end    -- only if the mob will live a while
      end },
    { key = "rake", row = 2, label = "RAKE", icon = "Rake",
      test = function(st)
          need(st, inForm("cat") and ctx.combat and ctx.hostile and spell["Rake"] and not ctx.bleedImmune)
          DRU.needDot(st, "Rake", 0)                           -- don't refresh it early
          need(st, usable("Rake"))
          if not ctx.elite then needTargetAbove(st, 30) end
      end },
    { key = "fbite", row = 2, label = "BITE", icon = "Ferocious Bite",
      test = function(st)
          -- 5 points and Rip is already on: spend them so they aren't wasted
          need(st, inForm("cat") and ctx.combat and ctx.hostile and spell["Ferocious Bite"])
          DRU.needCP(st, 5)
          need(st, usable("Ferocious Bite"))
      end },
    { key = "cfill", row = 2, label = "CLAW", icon = "Claw",
      test = function(st)
          -- Shred needs you behind the mob: only when someone else tanks (in a group)
          local n = (ctx.group and spell["Shred"]) and "Shred" or (spell["Claw"] and "Claw") or nil
          need(st, inForm("cat") and ctx.combat and ctx.hostile and n)
          if not st.ok then return end
          need(st, usable(n))
          return n, n:upper()
      end },
    { key = "shift", row = 2, label = "SHIFTING POWER", icon = "Shifting Power",
      test = function(st)
          need(st, inForm("cat") and ctx.combat and spell["Shifting Power"])
          need(st, ready("Shifting Power")); need(st, usable("Shifting Power"))
          DRU.needPower(st, DRU.ENERGY, 50, true)              -- on cooldown below 50 energy
      end },

    -- BEAR: Primal Bite on cooldown, Lacerate (one mob) / Swipe (packs), Maul for extra rage
    { key = "primal", row = 2, label = "PRIMAL BITE", icon = "Primal Bite",
      test = function(st)
          need(st, inForm("bear") and ctx.combat and ctx.hostile and spell["Primal Bite"])
          need(st, ready("Primal Bite")); need(st, usable("Primal Bite"))
      end },
    { key = "bfill", row = 2, label = "SWIPE", icon = "Swipe",
      test = function(st)
          local many = (ctx.enemies or 0) >= 2
          local n = (not many and spell["Lacerate"]) and "Lacerate" or (spell["Swipe"] and "Swipe") or nil
          need(st, inForm("bear") and ctx.combat and ctx.hostile and n)
          if not st.ok then return end
          need(st, ready(n)); need(st, usable(n))
          return n, n:upper()
      end },
    { key = "maul", row = 2, label = "MAUL", icon = "Maul",
      test = function(st)
          need(st, inForm("bear") and ctx.combat and ctx.hostile and spell["Maul"])
          if not st.ok then return end
          need(st, IsCurrentSpell(spell["Maul"]), true)        -- not already queued
          need(st, usable("Maul"))
          needRage(st, spendLine(), false)                     -- only extra rage
      end },
    { key = "enrage", row = 2, label = "ENRAGE", icon = "Enrage",
      test = function(st)
          need(st, inForm("bear") and spell["Enrage"] and (ctx.combat or ctx.hostile))
          need(st, ready("Enrage")); need(st, usable("Enrage"))
          if st.ok and ctx.combat then needRage(st, 30, true) end
      end },
    { key = "roar", row = 2, label = "DEMO ROAR", icon = "Demoralizing Roar",
      test = function(st)
          need(st, inForm("bear") and ctx.combat and ctx.hostile and ((ctx.enemies or 0) >= 2 or ctx.elite))
          need(st, spell["Demoralizing Roar"] and timeLeft("Demoralizing Roar") <= durationOf("Demoralizing Roar") * 0.3)
          need(st, usable("Demoralizing Roar"))
      end },
    { key = "ffire", row = 2, label = "FAERIE FIRE", icon = "Faerie Fire",
      test = function(st)
          local n = spell["Faerie Fire (Feral)"] and "Faerie Fire (Feral)" or "Faerie Fire"
          need(st, (inForm("bear") or inForm("cat")) and ctx.combat and ctx.hostile and spell[n] and not ctx.stealth)
          DRU.needDot(st, n, 0.1)
          need(st, ready(n)); need(st, usable(n))
          needTargetAbove(st, 30)
          return n, "FAERIE FIRE"
      end },

    -- CASTER (Balance / Restoration while leveling): Moonfire + Insect Swarm, Wrath filler
    { key = "hurricane", row = 2, label = "HURRICANE", icon = "Hurricane",
      test = function(st)
          need(st, inForm("caster") and ctx.combat and ctx.hostile and (ctx.enemies or 0) >= 3 and spell["Hurricane"])
          need(st, ready("Hurricane")); need(st, usable("Hurricane"))
      end },
    { key = "moonfire", row = 2, label = "MOONFIRE", icon = "Moonfire",
      test = function(st)
          need(st, inForm("caster") and ctx.combat and ctx.hostile and spell["Moonfire"])
          DRU.needDot(st, "Moonfire", 0.3)
          need(st, usable("Moonfire"))
          needTargetAbove(st, 25)
      end },
    { key = "insect", row = 2, label = "INSECT SWARM", icon = "Insect Swarm",
      test = function(st)
          need(st, inForm("caster") and ctx.combat and ctx.hostile and spell["Insect Swarm"])
          DRU.needDot(st, "Insect Swarm", 0.3)
          need(st, ready("Insect Swarm")); need(st, usable("Insect Swarm"))
          needTargetAbove(st, 25)
      end },
    { key = "wrath", row = 2, label = "WRATH", icon = "Wrath",
      test = function(st)
          need(st, inForm("caster") and ctx.combat and ctx.hostile and spell["Wrath"])
          need(st, usable("Wrath"))
      end },

    -- UPKEEP: Mark of the Wild + Thorns always, Rejuvenation on yourself before a pull
    { key = "rejuv", row = 2, label = "REJUV", icon = "Rejuvenation",
      test = function(st)
          need(st, inForm("caster") and not ctx.combat and ctx.hostile and spell["Rejuvenation"])
          need(st, timeLeft("Rejuvenation") <= 0)
          need(st, usable("Rejuvenation"))
      end },
    { key = "motw", row = 2, label = "MARK", icon = "Mark of the Wild",
      test = function(st)
          need(st, spell["Mark of the Wild"] and timeLeft("MOTW") <= 60 and not IsMounted())
          if ctx.combat then need(st, usable("Mark of the Wild")) end
      end },
    { key = "thorns", row = 2, label = "THORNS", icon = "Thorns",
      test = function(st)
          need(st, spell["Thorns"] and timeLeft("Thorns") <= 30 and not IsMounted())
          if ctx.combat then need(st, usable("Thorns")) end
      end },

    -- EXTRA (caster)
    { key = "innervate", row = 2, label = "INNERVATE", icon = "Innervate",
      test = function(st)
          need(st, inForm("caster") and ctx.combat and spell["Innervate"])
          need(st, ready("Innervate")); need(st, usable("Innervate"))
          needRage(st, 40, true)                               -- mana in caster form
      end },
    { key = "grasp", row = 2, label = "NATURE'S GRASP", icon = "Nature's Grasp",
      test = function(st)
          need(st, inForm("caster") and ctx.combat and (ctx.enemies or 0) >= 2 and spell["Nature's Grasp"])
          need(st, ready("Nature's Grasp")); need(st, usable("Nature's Grasp"))
      end },
    { key = "lowmana", row = 2, label = "LOW MANA", icon = "Innervate",
      test = function(st)
          need(st, inForm("caster") and ctx.combat)
          needRage(st, DB.lowMana, true)
      end },
}

-- Warlock: Icy Veins WoW Forever Affliction, Demonology and Destruction leveling
-- guides (Nov 2026). DoTs only on mobs that will live, Life Tap when health is
-- fine, Drain Soul for shards, pet out unless Demonic Sacrifice is on you.
do
    -- bags: Soul Shards + your Healthstone (read at most once a second)
    DRU.SHARD = 6265
    DRU.HS_IDS = { [5512] = true, [19004] = true, [19005] = true, [5511] = true, [19006] = true, [19007] = true,
        [5509] = true, [19008] = true, [19009] = true, [5510] = true, [19010] = true, [19011] = true,
        [9421] = true, [19012] = true, [19013] = true }
    DRU.icons.Healthstone = "Interface\\Icons\\INV_Stone_04"
    local bagAt, shards, hsID = -10, 0, nil
    local function nameOf(info, id)
        local n = info.itemName
        if type(n) ~= "string" or secret(n) then
            local ok, n2 = pcall(C_Item.GetItemInfo, id)
            n = ok and n2 or nil
        end
        if type(n) == "string" and not secret(n) then return n end
    end
    function DRU.bags()
        local now = GetTime()
        if now - bagAt < 1 then return shards, hsID end
        bagAt = now
        local s, hs, icon = 0, nil, nil
        if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
            for bag = 0, 5 do              -- 5 = reagent bag slot (soul shard bag)
                local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
                n = okN and plain(n, 0) or 0
                for slot = 1, (type(n) == "number" and n or 0) do
                    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                    if ok and type(info) == "table" and not sectable(info) and info.itemID and not secret(info.itemID) then
                        local id = info.itemID
                        local nm = nameOf(info, id)
                        if id == DRU.SHARD or nm == "Soul Shard" then
                            s = s + (plain(info.stackCount, 1) or 1)
                        elseif DRU.HS_IDS[id] or (nm and nm:find("Healthstone")) then
                            hs, icon = id, plain(info.iconFileID, nil)
                        end
                    end
                end
            end
        end
        shards, hsID = s, hs
        if icon then DRU.icons.Healthstone = icon end
        return shards, hsID
    end
    local function hsReady()
        local _, id = DRU.bags()
        if not id then return false end
        local getCD = C_Container and C_Container.GetItemCooldown
        if getCD then
            local ok, _, d = pcall(getCD, id)
            if ok and not secret(d) and d and d > 1.5 then return false end
        end
        return true
    end
    function DRU.havePet()
        local e = UnitExists("pet")
        if secret(e) then return true end
        if not e then return false end
        local d = UnitIsDead("pet")
        if secret(d) then return true end
        return not d
    end
    local function trivial()
        local ok, t = pcall(UnitIsTrivial or function() return false end, "target")
        return ok and plain(t, false) == true
    end
    local function demo() return spell["Soul Link"] or DRU.passive["Demonic Brand"] end
    local function sAndF() return DRU.passive["Shadow and Flame"] end
    local function bane() return spell["Bane of Agony"] and "Bane of Agony" or (spell["Curse of Agony"] and "Curse of Agony") end
    local function lives(st, pct) if not ctx.elite then needTargetAbove(st, pct) end end   -- will it live a while?
    local function fight(st) need(st, ctx.combat and ctx.hostile) end

    -- Nightfall's free Shadow Bolt ("Shadow Trance"): the aura when readable, else
    -- the game's own button glow on Shadow Bolt.
    local tranceAt
    function DRU.tranceUp()
        local hidden = true
        if C_Secrets and C_Secrets.ShouldAurasBeSecret then
            local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
            hidden = not ok or secret(r) or r == true
        end
        if not hidden and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
            for _, n in ipairs({ "Shadow Trance", "Nightfall" }) do
                local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", n, "HELPFUL")
                if not ok or secret(a) or sectable(a) then hidden = true break end
                if a then return true end
            end
            if not hidden then return false end
        end
        return tranceAt ~= nil and GetTime() - tranceAt < 10
    end
    local wf = CreateFrame("Frame")
    pcall(wf.RegisterEvent, wf, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    pcall(wf.RegisterEvent, wf, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    pcall(wf.RegisterUnitEvent, wf, "UNIT_SPELLCAST_SUCCEEDED", "player")
    pcall(wf.RegisterUnitEvent, wf, "UNIT_PET", "player")
    wf:SetScript("OnEvent", function(_, event, a1, a2, a3)
        if CLASS ~= "WARLOCK" then return end
        if event == "UNIT_PET" then expires.SOULLINK = 0 return end     -- new pet: Soul Link again
        local id = event == "UNIT_SPELLCAST_SUCCEEDED" and a3 or a1
        if id == nil or secret(id) then return end
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if not ok or type(name) ~= "string" or secret(name) then return end
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
            if name == "Shadow Bolt" then tranceAt = GetTime() end
        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            if name == "Shadow Bolt" then tranceAt = nil end
        elseif name == "Shadow Bolt" then
            tranceAt = nil
        elseif name == "Conflagrate" and not sAndF() and DRU.dotAt.Immolate then
            DRU.dotAt.Immolate[targetKey()] = nil                        -- it ate your Immolate
        end
    end)

    DRU.WARLOCK_ALERTS = {
        -- DANGER ROW
        { key = "lowhp", row = 1, label = "LOW HP", danger = true, icon = "Death Coil",
          test = function(st)
              need(st, ctx.combat)
              needLowHealth(st, DB.lowHp)
              if not st.ok then return end
              if hsReady() then return "Healthstone", "HEALTHSTONE" end
              local n = firstKnown({ "Death Coil" }, true)
              if n then return n, "DEATH COIL" end
              if spell["Drain Life"] then return "Drain Life", "DRAIN LIFE" end
          end },
        { key = "fear", row = 1, label = "FEAR ONE", danger = true, icon = "Fear",
          test = function(st)
              -- solo, 2+ mobs on you and getting low: Fear one so you fight one at a time
              need(st, ctx.combat and ctx.hostile and not ctx.group and (ctx.enemies or 0) >= 2 and spell["Fear"])
              need(st, usable("Fear"))
              DRU.needUnitHP(st, "player", 60, true)
              if not st.ok then return end
              if (ctx.enemies or 0) >= 3 and spell["Howl of Terror"] and ready("Howl of Terror") == true then
                  return "Howl of Terror", "HOWL"
              end
          end },

        -- NEXT: procs and finishers first, then DoTs, then the filler
        { key = "trance", row = 2, label = "FREE BOLT", icon = "Shadow Bolt",
          test = function(st)
              fight(st); need(st, spell["Shadow Bolt"] and DRU.tranceUp())
          end },
        { key = "drainlife", row = 2, label = "DRAIN LIFE", icon = "Drain Life",
          test = function(st)
              fight(st); need(st, spell["Drain Life"]); need(st, usable("Drain Life"))
              DRU.needUnitHP(st, "player", 50, true)
          end },
        { key = "drainsoul", row = 2, label = "SOUL SHARD", icon = "Drain Soul",
          test = function(st)
              -- dying mob + not enough shards: channel Drain Soul as it dies
              fight(st); need(st, spell["Drain Soul"] and not trivial())
              if not st.ok then return end
              need(st, (DRU.bags()) < (DB.shardGoal or 5))
              need(st, usable("Drain Soul"))
              DRU.needUnitHP(st, "target", 25, true)
              if st.ok then return nil, "SHARD " .. (DRU.bags()) .. "/" .. (DB.shardGoal or 5) end
          end },
        { key = "sburn", row = 2, label = "SHADOWBURN", icon = "Shadowburn",
          test = function(st)
              fight(st); need(st, spell["Shadowburn"]); need(st, ready("Shadowburn")); need(st, usable("Shadowburn"))
              -- after Shadow and Flame the shard always comes back: on cooldown vs tough mobs
              if not (sAndF() and ctx.elite) then DRU.needUnitHP(st, "target", 20, true) end
          end },
        { key = "conflag", row = 2, label = "CONFLAGRATE", icon = "Conflagrate",
          test = function(st)
              fight(st); need(st, spell["Conflagrate"] and not DRU.dotGone("Immolate", 0))
              need(st, ready("Conflagrate")); need(st, usable("Conflagrate"))
              if not st.ok or sAndF() then return end
              -- before Shadow and Flame it eats Immolate: only near its end or to finish
              if not DRU.dotGone("Immolate", 0.3) then DRU.needUnitHP(st, "target", 25, true) end
          end },
        { key = "brand", row = 2, label = "BRAND", icon = "Searing Pain",
          test = function(st)
              -- Demonology: Searing Pain brands your pet's target (10 sec)
              fight(st); need(st, demo() and spell["Searing Pain"] and DRU.havePet() and timeLeft("BRAND") <= 0)
              need(st, usable("Searing Pain"))
              lives(st, 25)
          end },
        { key = "corrupt", row = 2, label = "CORRUPTION", icon = "Corruption",
          test = function(st)
              fight(st); need(st, spell["Corruption"])
              DRU.needDot(st, "Corruption", 0.1)
              need(st, usable("Corruption"))
              lives(st, 35)
          end },
        { key = "bane", row = 2, label = "AGONY", icon = "Bane of Agony",
          test = function(st)
              local n = bane()
              fight(st); need(st, n)
              if not st.ok then return end
              DRU.needDot(st, n, 0)                -- strongest ticks at the end: never refresh early
              need(st, usable(n))
              lives(st, 50)
              return n, "AGONY"
          end },
        { key = "immolate", row = 2, label = "IMMOLATE", icon = "Immolate",
          test = function(st)
              fight(st); need(st, spell["Immolate"])
              DRU.needDot(st, "Immolate", 0.1)
              need(st, usable("Immolate"))
              lives(st, 40)
          end },
        { key = "siphon", row = 2, label = "SIPHON LIFE", icon = "Siphon Life",
          test = function(st)
              fight(st); need(st, spell["Siphon Life"])
              DRU.needDot(st, "Siphon Life", 0.1)
              need(st, usable("Siphon Life"))
              lives(st, 60)                         -- 30 sec dot: long fights only
          end },
        { key = "filler", row = 2, label = "SHADOW BOLT", icon = "Shadow Bolt",
          test = function(st)
              -- Incinerate (Destruction 40+), else wand when you have one, else Shadow Bolt
              local okW, wand = pcall(HasWandEquipped or function() return false end)
              wand = okW and plain(wand, false) == true
              local n = spell["Incinerate"] and "Incinerate" or (wand and spell["Shoot"] and "Shoot") or "Shadow Bolt"
              fight(st); need(st, spell[n])
              if not st.ok then return end
              if n == "Shoot" then need(st, IsCurrentSpell(spell.Shoot), true) else need(st, usable(n)) end
              return n, n == "Shoot" and "WAND" or n:upper()
          end },

        -- BUFF: upkeep
        { key = "armor", row = 2, label = "ARMOR", icon = "Demon Skin",
          test = function(st)
              local n = firstKnown({ "Fel Armor", "Demon Armor", "Demon Skin" })
              need(st, n and timeLeft("ARMOR") <= 60 and not IsMounted())
              if not st.ok then return end
              if ctx.combat then need(st, usable(n)) end
              return n, "ARMOR"
          end },
        { key = "pet", row = 2, label = "SUMMON PET", icon = "Summon Imp",
          test = function(st)
              need(st, spell["Summon Imp"] and not IsMounted() and not DRU.havePet())
              need(st, timeLeft("SACRIFICE") <= 0)  -- sacrificed on purpose: no nagging
              if not st.ok then return end
              -- Voidwalker tanks for you (Icy Veins solo pick); Imp needs no shard
              local n = ((DRU.bags()) > 0 and spell["Summon Voidwalker"]) and "Summon Voidwalker" or "Summon Imp"
              return n, "PET"
          end },
        { key = "soullink", row = 2, label = "SOUL LINK", icon = "Soul Link",
          test = function(st)
              need(st, spell["Soul Link"] and DRU.havePet() and timeLeft("SOULLINK") <= 0 and not IsMounted())
              need(st, usable("Soul Link"))
          end },
        { key = "curse", row = 2, label = "CURSE", icon = "Curse of the Elements",
          test = function(st)
              -- elites / bosses: Elements (more magic damage), or Weakness if that's all you have
              local n = firstKnown({ "Curse of the Elements", "Curse of Weakness" })
              fight(st); need(st, n and ctx.elite)
              if not st.ok then return end
              need(st, DRU.dotGone("Curse of the Elements", 0.1) and DRU.dotGone("Curse of Weakness", 0.1))
              need(st, usable(n))
              return n, "CURSE"
          end },
        { key = "mkstone", row = 2, label = "HEALTHSTONE", icon = "Create Healthstone",
          test = function(st)
              need(st, not ctx.combat and spell["Create Healthstone"] and not IsMounted())
              if not st.ok then return end
              local s, hs = DRU.bags()
              need(st, s > 0 and not hs)
              return nil, "MAKE STONE"
          end },

        -- EXTRA
        { key = "lifetap", row = 2, label = "LIFE TAP", icon = "Life Tap",
          test = function(st)
              need(st, spell["Life Tap"] and (ctx.combat or ctx.hostile) and not IsMounted())
              need(st, usable("Life Tap"))
              needRage(st, 40, true)                        -- mana under 40%
              DRU.needUnitHP(st, "player", 60, false)       -- ...and health is fine
          end },
        { key = "funnel", row = 2, label = "HEAL PET", icon = "Health Funnel",
          test = function(st)
              need(st, ctx.combat and spell["Health Funnel"] and DRU.havePet())
              need(st, usable("Health Funnel"))
              DRU.needUnitHP(st, "pet", 30, true)
          end },
        { key = "rof", row = 2, label = "RAIN OF FIRE", icon = "Rain of Fire",
          test = function(st)
              fight(st); need(st, ctx.group and (ctx.enemies or 0) >= 3 and spell["Rain of Fire"])
              need(st, usable("Rain of Fire"))
          end },
        { key = "lowmana", row = 2, label = "LOW MANA", icon = "Life Tap",
          test = function(st)
              need(st, ctx.combat)
              needRage(st, DB.lowMana, true)
          end },
    }
end

local CLASS_ALERTS = { WARRIOR = WARRIOR_ALERTS, PALADIN = PALADIN_ALERTS, DRUID = DRUID_ALERTS,
    WARLOCK = DRU.WARLOCK_ALERTS }

-- Big-icon mode: every alert of a spot sits in one place, stacked. First in the list
-- is on top, so you only ever see the most important lit one. Order: Icy Veins
-- Forever Prot Warrior / Prot Paladin leveling + tank rotation pages (Nov 2026).
local SPOT = {
    WARRIOR = {
        danger = { "lowhp", "kick", "taunt", "loose" },
        next   = { "slam", "revenge", "vrush", "clap", "sunder", "execute" },
        buff   = { "demo", "rend", "shout" },               -- upkeep: never buried under the rotation
        extra  = { "block", "dump", "bloodrage" },   -- off the global cooldown: press any time
    },
    PALADIN = {
        danger = { "lowhp", "kick", "taunt", "loose" },
        next   = { "consecrate", "holyshield", "holystrike", "exorcism", "wrath" },
        buff   = { "rfury", "seal", "bless", "aura" },
        extra  = { "judge", "lowmana" },             -- Judgement is off the global cooldown
    },
    DRUID = {   -- each key only lights in its own form, so one list covers all three specs
        danger = { "lowhp", "kick", "taunt", "loose" },
        next   = { "copen", "rip", "rake", "fbite", "cfill", "primal", "bfill",
                   "hurricane", "moonfire", "insect", "wrath" },
        buff   = { "rejuv", "motw", "thorns", "ffire", "roar" },
        extra  = { "shift", "enrage", "maul", "innervate", "grasp", "lowmana" },
    },
    WARLOCK = {   -- spells you don't know yet never light, so one list covers all three specs
        danger = { "lowhp", "fear" },
        next   = { "trance", "drainlife", "drainsoul", "sburn", "conflag", "brand",
                   "corrupt", "bane", "immolate", "siphon", "filler" },
        buff   = { "armor", "pet", "soullink", "curse", "mkstone" },
        extra  = { "lifetap", "funnel", "rof", "lowmana" },
    },
}
local SPOT_SIZE = { danger = 64, next = 64, buff = 44, extra = 64 }   -- big, easy to see

-- Racials (Wowhead WoW Forever race pages, Nov 2026). Every class gets them; an alert
-- or a cooldown icon only shows when your character really has that racial.
do
    -- Damage racials: worth it on tough fights (elite, 2+ mobs, or getting hit hard).
    local BURST = { "Elune's Light", "Blood Fury", "Berserking" }
    local racial = { key = "racial", row = 2, label = "RACIAL", icon = "Berserking",
      test = function(st)
          local n = firstKnown(BURST)
          local tough = ctx.elite or (ctx.enemies or 0) >= 2 or (tankingHard and tankingHard())
          need(st, n and ctx.combat and ctx.hostile and tough)
          if not st.ok then return end
          need(st, ready(n)); need(st, usable(n))
          return n, n:upper()
      end }
    -- Tauren: War Stomp stops a cast when your normal interrupt isn't ready.
    local stomp = { key = "stomp", row = 1, label = "WAR STOMP", danger = true, icon = "War Stomp",
      test = function(st)
          need(st, spell["War Stomp"] and ctx.combat and ctx.hostile and (ctx.enemies or 0) >= 1)
          if not st.ok then return end
          need(st, ready("War Stomp")); need(st, usable("War Stomp"))
          castingTarget(st)
      end }
    for _, list in pairs(CLASS_ALERTS) do list[#list + 1] = racial; list[#list + 1] = stomp end
    for _, sp in pairs(SPOT) do
        table.insert(sp.danger, "stomp")       -- under the class interrupt
        table.insert(sp.extra, 1, "racial")    -- off the global cooldown: first in its spot
    end
    -- cooldown row: every combat racial (only the ones you know get an icon)
    DRU.RACIAL_CDS = { "Elune's Light", "Shadowmeld", "Blood Fury", "Berserking", "Stoneform", "War Stomp",
        "Will of the Forsaken", "Will to Survive", "Escape Artist", "Shatter Curse" }
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local main = CreateFrame("Frame", "DBagsAlertsFrame", UIParent)
main:SetSize(10, 10)
main:SetMovable(true)
main:SetClampedToScreen(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB.point = { p, rp, x, y }
    if DBagsAlertsState.placeClickers then DBagsAlertsState.placeClickers() end
end)
main.bg = main:CreateTexture(nil, "BACKGROUND")
main.bg:SetAllPoints()
main.bg:SetColorTexture(0.2, 0.6, 1, 0.25)
-- Unlocked: drag to move, mouse wheel to resize.
main:SetScript("OnMouseWheel", function(self, delta)
    if DB.locked then return end
    DB.scale = math.max(0.5, math.min(2.5, (DB.scale or 1) + delta * 0.05))
    self:SetScale(DB.scale)
end)

-- Look: flat dark bars, thin black borders, outlined text.
-- Look inspired by EllesmereUI / Naowh: smooth flat bars,
-- 1px black pixel borders, icons packed edge to edge, no boxes or glows.
local MEDIA = "Interface\\AddOns\\DBagsAlerts\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local BAR_TEX = MEDIA .. "Smooth.tga"
local FONT = "Fonts\\FRIZQT__.TTF"          -- WoW's own font: familiar, easy to read
local FALLBACK_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local function styleText(fs, size, r, g, b)
    if not fs:SetFont(FONT, size, "OUTLINE") then fs:SetFont(FALLBACK_FONT, size, "OUTLINE") end
    fs:SetShadowOffset(0, 0)
    if r then fs:SetTextColor(r, g, b) end
end
local function setText(fs, s)          -- skip the work when the text didn't change
    if fs._t ~= s then fs._t = s; fs:SetText(s) end
end
local function addBorder(f, r, g, b, a, px)
    px = px or 1
    local t = {}
    for i = 1, 4 do
        local e = f:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetColorTexture(r, g, b, a or 1)
        t[i] = e
    end
    t[1]:SetPoint("TOPLEFT", -px, px); t[1]:SetPoint("TOPRIGHT", px, px); t[1]:SetHeight(px)
    t[2]:SetPoint("BOTTOMLEFT", -px, -px); t[2]:SetPoint("BOTTOMRIGHT", px, -px); t[2]:SetHeight(px)
    t[3]:SetPoint("TOPLEFT", -px, px); t[3]:SetPoint("BOTTOMLEFT", -px, -px); t[3]:SetWidth(px)
    t[4]:SetPoint("TOPRIGHT", px, px); t[4]:SetPoint("BOTTOMRIGHT", px, -px); t[4]:SetWidth(px)
    return t
end
local function colorBorder(t, r, g, b, a) for _, e in ipairs(t) do e:SetColorTexture(r, g, b, a or 1) end end

-- Icons that always exist, for alerts whose spell you don't have (yet).
local FALLBACK_ICON = {
    lowhp = "Interface\\Icons\\Spell_Holy_SealOfProtection",
    loose = "Interface\\Icons\\Ability_Warrior_Challange",
    taunt = "Interface\\Icons\\Ability_Warrior_Challange",
    lowmana = "Interface\\Icons\\INV_Drink_07",
    kick = "Interface\\Icons\\Ability_Kick",
}
local DEFAULT_ICON = "Interface\\Icons\\Ability_Warrior_DefensiveStance"

local SIZE = { 46, 38 }
local GAP = 8
local BAR_W = 240

local function makeSlot(a)
    local size = SIZE[a.row]
    local root = CreateFrame("Frame", nil, main)
    root:SetSize(size, size)
    local parent, gates = root, {}
    for i = 1, 4 do
        local g = CreateFrame("Frame", nil, parent)
        g:SetAllPoints(root)
        gates[i], parent = g, g
    end
    local c = CreateFrame("Frame", nil, parent)
    c:SetAllPoints(root)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)     -- zoomed, no Blizzard bevel
    addBorder(c, 0, 0, 0, 1, 1)                    -- 1px black pixel border
    local edge = CreateFrame("Frame", nil, c)
    edge:SetPoint("TOPLEFT", 1, -1); edge:SetPoint("BOTTOMRIGHT", -1, 1)
    c.edge = addBorder(edge, 1, 0.15, 0.15, 1, 2)   -- thick red edge: danger is obvious
    if not a.danger then colorBorder(c.edge, 0, 0, 0, 0) end   -- only danger gets a red edge
    c.edgeFrame = edge
    -- solid name plate: when icons are stacked, the top one's plate hides the names below
    c.plate = c:CreateTexture(nil, "BACKGROUND")
    c.plate:SetColorTexture(0.04, 0.04, 0.05, 0.9)
    c.plate:SetPoint("TOP", root, "BOTTOM", 0, -2)
    c.plate:SetSize(size + 20, 22)
    c.text = c:CreateFontString(nil, "OVERLAY")
    styleText(c.text, a.row == 1 and 11 or 9, 1, 0.85, 0.25)
    c.text:SetPoint("CENTER", c.plate, "CENTER", 0, 0)
    c.text:SetWidth(size + 18)          -- long names wrap onto two lines
    c.text:SetWordWrap(true)
    c.text:SetJustifyH("CENTER")
    if a.danger then c.text:SetTextColor(1, 0.35, 0.35) end
    if a.danger then   -- the red border pulses; the icon itself stays solid
        local ag = edge:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1); fade:SetToAlpha(0.35); fade:SetDuration(0.45)
        ag:Play()
    end
    a.root, a.gates, a.c = root, gates, c
    a.iconName = nil
end

-- Put an alert's frames on their own layer (L .. L+6), so stacks draw in order.
local function setLevels(a, L)
    a.root:SetFrameLevel(L)
    for i = 1, 4 do a.gates[i]:SetFrameLevel(L + i) end
    a.c:SetFrameLevel(L + 5)
    a.c.edgeFrame:SetFrameLevel(L + 6)
end

-- Range: like Blizzard's action bars - the big icon itself is colored red when
-- you're out of melee, amber a few steps out. No extra shapes.
local ring = CreateFrame("Frame", nil, main)    -- holds the mob count on the big icon
-- mob count, bottom-right of the big icon (orange = heavy hits)
ring.count = ring:CreateFontString(nil, "OVERLAY")
styleText(ring.count, 20, 1, 1, 1)
ring.count:SetPoint("BOTTOMRIGHT", -2, 2)

-- A bar: flat fill, dark back, black outline, label on the left, value on the right,
-- and a bright spark riding the end of the fill (anchored, so no math on secrets).
-- "Classic WoW" style: Blizzard's own rounded gold-edged frame (the tooltip border)
-- around every bar and icon spot, and WoW's classic glossy bar texture.
local CLASSIC_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local EDGE = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
               insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local GOLD = { 0.86, 0.72, 0.42 }
local function classic() return not DB or DB.style ~= "clean" end
local function goldFrame(parent, pad)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetPoint("TOPLEFT", -pad, pad); f:SetPoint("BOTTOMRIGHT", pad, -pad)
    if f.SetBackdrop then
        f:SetBackdrop(EDGE)
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    f:Hide()
    return f
end
local BARS = {}

local function makeBar(r, g, b, h, label, parent)
    local bar = CreateFrame("StatusBar", nil, parent or main)
    bar:SetSize(BAR_W, h)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetStatusBarColor(r, g, b)
    bar.col = { r, g, b }
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(); bar.bg:SetTexture(BAR_TEX); bar.bg:SetVertexColor(0.06, 0.06, 0.07, 0.85)
    bar.px = addBorder(bar, 0, 0, 0, 1, 1)
    bar.frame = goldFrame(bar, 4)
    BARS[#BARS + 1] = bar
    bar.left = bar:CreateFontString(nil, "OVERLAY")
    styleText(bar.left, math.max(9, h - 6), 0.9, 0.9, 0.9)
    bar.left:SetPoint("LEFT", 4, 0)
    bar.left:SetText(label or "")
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    styleText(bar.text, math.max(10, h - 6), 1, 1, 1)
    bar.text:SetPoint("RIGHT", -4, 0)
    return bar
end

-- No box behind the bars (an invisible anchor only)
local panel = CreateFrame("Frame", nil, main)
panel.bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
panel.bg:SetAllPoints(); panel.bg:SetColorTexture(0, 0, 0, 0)

local healthBar = makeBar(0.1, 0.8, 0.1, 28, "")       -- classic WoW green
local rageBar = makeBar(0.85, 0.15, 0.15, 18, "")
local threatBar = makeBar(0.15, 0.75, 0.3, 10, "")
local swingBar = makeBar(0.8, 0.8, 0.85, 10, "")
threatBar.text:Hide(); swingBar.text:Hide()
styleText(healthBar.text, 18, 1, 1, 1); styleText(rageBar.text, 14, 1, 1, 1)
healthBar.text:ClearAllPoints(); healthBar.text:SetPoint("CENTER")    -- numbers in the middle, big
rageBar.text:ClearAllPoints(); rageBar.text:SetPoint("CENTER")
panel.accent = panel:CreateTexture(nil, "ARTWORK")
panel.accent:SetColorTexture(0, 0, 0, 0)

-- "Spend here" marker on the rage bar (where the gold starts).
rageBar.tick = rageBar:CreateTexture(nil, "OVERLAY", nil, 6)
rageBar.tick:SetColorTexture(1, 1, 1, 0.8); rageBar.tick:SetSize(2, 13)

-- Advice line: one plain sentence under the power bar. Three sentences sit on top of
-- each other; rage (maybe secret) picks which one is visible through curve alphas.
local advice = CreateFrame("Frame", nil, main)
advice:SetSize(BAR_W, 16)
local function adviceLine(r, g, b)
    local fs = advice:CreateFontString(nil, "OVERLAY")
    styleText(fs, 13, r, g, b); fs:SetPoint("CENTER")
    return fs
end
advice.low = adviceLine(0.75, 0.75, 0.8)
advice.mid = adviceLine(0.85, 0.85, 0.88)
advice.highGate = CreateFrame("Frame", nil, advice)   -- holds the alpha; the text inside pulses
advice.highGate:SetAllPoints()
advice.high = advice.highGate:CreateFontString(nil, "OVERLAY")
styleText(advice.high, 13, 1, 0.82, 0.15); advice.high:SetPoint("CENTER")
do  -- the "too much rage" sentence pulses so you notice it
    local ag = advice.high:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0.6); a:SetDuration(0.6)
    advice.highAnim = ag
end

local info = main:CreateFontString(nil, "OVERLAY")
styleText(info, 9, 0.7, 0.7, 0.75)

-- Health color: green -> yellow -> orange -> red as you drop.
-- Two copies of the health bar (yellow, red) sit on top of the green one and fade in
-- as health falls. Their fade comes from UnitHealthPercent + a curve, so it keeps
-- working when health is secret in combat (we only hand the value to SetAlpha).
local updateHealthColor, styleHealthColor
do
    local text = CreateFrame("Frame", nil, healthBar)    -- keeps the % above the color layers
    text:SetAllPoints()
    healthBar.text:SetParent(text)
    local function layer(r, g, b)
        local s = CreateFrame("StatusBar", nil, healthBar)
        s:SetAllPoints(); s:SetStatusBarTexture(BAR_TEX); s:SetStatusBarColor(r, g, b)
        s:SetMinMaxValues(0, 1); s:SetValue(0); s:SetAlpha(0)
        return s
    end
    local yellow = layer(1, 0.82, 0.1)
    local red = layer(0.9, 0.1, 0.08)
    -- fade in: yellow from 75% down to 45%, red from 45% down to 15% (yellow+red = orange)
    local function fadeCurve(full, none)
        local ok, cv = pcall(function()
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Linear)
            c:AddPoint(0, 1); c:AddPoint(full, 1); c:AddPoint(none, 0); c:AddPoint(1, 0)
            return c
        end)
        return ok and cv or nil
    end
    local yC = C_CurveUtil and fadeCurve(0.45, 0.75)
    local rC = C_CurveUtil and fadeCurve(0.15, 0.45)
    local function plainFade(frac, full, none)
        if frac <= full then return 1 elseif frac >= none then return 0 end
        return (none - frac) / (none - full)
    end
    local function fade(s, cv, full, none, h, m)
        if not secret(h) and not secret(m) then
            s:SetAlpha((m and m > 0) and plainFade(h / m, full, none) or 0)
        elseif cv and UnitHealthPercent then
            local ok, a = pcall(UnitHealthPercent, "player", false, cv)
            if ok and not pcall(s.SetAlpha, s, a) then s:SetAlpha(0) end
        end
    end
    -- setValue = the same smooth setter the green bar uses, so the layers move together
    updateHealthColor = function(h, m, setValue)
        for _, s in ipairs({ yellow, red }) do
            pcall(s.SetMinMaxValues, s, 0, m)
            setValue(s, h)
        end
        fade(yellow, yC, 0.45, 0.75, h, m)
        fade(red, rC, 0.15, 0.45, h, m)
    end
    styleHealthColor = function(tex)
        yellow:SetStatusBarTexture(tex); yellow:SetStatusBarColor(1, 0.82, 0.1)
        red:SetStatusBarTexture(tex); red:SetStatusBarColor(0.9, 0.1, 0.08)
        local L = healthBar:GetFrameLevel() or 1
        yellow:SetFrameLevel(L + 1); red:SetFrameLevel(L + 2); text:SetFrameLevel(L + 3)
    end
end

-- Swing timer. Forever fires PLAYER_SWING the moment your auto-attack lands
-- (technique from AKForeverCombatTimers, MIT). If its length is secret in combat
-- we use your weapon speed, read whenever it is readable.
local swing = { start = 0, dur = 0, speed = nil }
local QUEUED_SPELLS = { "Heroic Strike", "Cleave" }
local function readSpeed()
    local ok, mh = pcall(UnitAttackSpeed, "player")
    if ok and mh and not secret(mh) and mh > 0 then swing.speed = mh end
end
local function onSwing(duration, swingType)
    local MH = Enum and Enum.SwingType and Enum.SwingType.MainHand
    if MH ~= nil and swingType ~= nil and not secret(swingType) and swingType ~= MH then return end
    readSpeed()
    local d = (duration and not secret(duration) and duration > 0) and duration or swing.speed
    if not d then return end
    swing.start, swing.dur = GetTime(), d
end
local function onAttackSpeed()
    local old = swing.speed
    readSpeed()
    local now = GetTime()
    if old and swing.speed and old ~= swing.speed and now < swing.start + swing.dur then
        -- haste/slow mid-swing: stretch what is left
        local left = (swing.start + swing.dur - now) * swing.speed / old
        swing.dur = (now - swing.start) + left
    end
end
-- Runs every frame, so it does as little as possible: one SetValue, and the
-- text / colour only a few times a second.
local swingTextAt, swingQAt, swingShown, swingQueued, swingMax = 0, 0, nil, nil, nil
local function updateSwing()
    local now = GetTime()
    local left = swing.start + swing.dur - now
    local show = (not DB.off.swing and not DRU.caster and (left > 0 or (ctx.combat and ctx.hostile))) and true or false
    if show ~= swingShown then swingShown = show; swingBar:SetShown(show) end
    if not show then return end
    if left > 0 and swing.dur > 0 then
        if swingMax ~= swing.dur then swingMax = swing.dur; swingBar:SetMinMaxValues(0, swing.dur) end
        swingBar:SetValue(now - swing.start)
        if now - swingTextAt >= 0.05 then swingTextAt = now; swingBar.text:SetFormattedText("%.1f", left) end
    elseif swingMax ~= -1 then
        swingMax = -1
        swingBar:SetMinMaxValues(0, 1); swingBar:SetValue(1)
        swingBar.text:SetText("")
    end
    -- Warrior: bar turns gold while Heroic Strike / Cleave is queued on the next swing.
    if now - swingQAt >= 0.1 then
        swingQAt = now
        local queued = false
        for _, n in ipairs(QUEUED_SPELLS) do
            if spell[n] then
                local q = IsCurrentSpell(spell[n])
                if not secret(q) and q then queued = true end
            end
        end
        if queued ~= swingQueued then
            swingQueued = queued
            if queued then swingBar:SetStatusBarColor(1, 0.78, 0.1) else swingBar:SetStatusBarColor(0.8, 0.8, 0.88) end
        end
    end
end
threatBar:SetMinMaxValues(0, 100)
-- Threat: a green bar (you have it) with a red bar on top (you don't). Their alpha
-- comes from isTanking, which may be secret, so one of them shows.
threatBar.red = CreateFrame("StatusBar", nil, threatBar)
threatBar.red:SetAllPoints(); threatBar.red:SetStatusBarTexture(FLAT)
threatBar.red:SetStatusBarColor(0.9, 0.15, 0.15); threatBar.red:SetMinMaxValues(0, 100)
threatBar.red:SetFrameLevel(threatBar:GetFrameLevel() + 1)
threatBar.top = CreateFrame("Frame", nil, threatBar)
threatBar.top:SetAllPoints(); threatBar.top:SetFrameLevel(threatBar:GetFrameLevel() + 2)
threatBar.ok = threatBar.top:CreateFontString(nil, "OVERLAY")
styleText(threatBar.ok, 9, 0.55, 1, 0.6); threatBar.ok:SetPoint("LEFT", threatBar, "LEFT", 4, 0)
threatBar.ok:SetText("TANKING")
threatBar.bad = threatBar.top:CreateFontString(nil, "OVERLAY")
styleText(threatBar.bad, 9, 1, 0.85, 0.85); threatBar.bad:SetPoint("LEFT", threatBar, "LEFT", 4, 0)
threatBar.bad:SetText("NO AGGRO")
threatBar.text:SetParent(threatBar.top)
threatBar.left:SetText("")
threatBar.ok:Hide(); threatBar.bad:Hide()   -- color says it: green = tanking, red = not

-- Cooldown row: real cooldown spirals + countdown numbers, even when the times are secret.
local CLASS_CDS = {
    -- Rotation buttons are left out: the big icons already tell you when to press them.
    -- This row is for emergency + utility cooldowns you want to know are ready in advance.
    WARRIOR = { "Shield Wall", "Last Stand", "Challenging Shout", "Concussion Blow",
        "Intimidating Shout", "Berserker Rage" },
    PALADIN = { "Templar's Bulwark", "Divine Protection", "Divine Shield", "Lay on Hands",
        "Blessing of Protection", "Blessing of Freedom" },
    DRUID = { "Barkskin", "Frenzied Regeneration", "Innervate", "Tranquility", "Challenging Roar", "Dash" },
    WARLOCK = { "Death Coil", "Howl of Terror", "Shadow Ward", "Amplify Curse", "Fel Domination", "Soulshatter" },
}
for _, list in pairs(CLASS_CDS) do
    for _, n in ipairs(DRU.RACIAL_CDS or {}) do list[#list + 1] = n end
end
local CD_SIZE = 40
local cdIcons = {}
local function makeCD(name)
    local f = CreateFrame("Frame", nil, main)
    f:SetSize(CD_SIZE, CD_SIZE)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addBorder(f, 0, 0, 0, 1, 1)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetCountdownFont then pcall(f.cd.SetCountdownFont, f.cd, "GameFontHighlightLarge") end   -- big timer numbers
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(false) end
    pcall(f.cd.SetDrawEdge, f.cd, false)                 -- clean dark sweep, no bright edge line
    pcall(f.cd.SetDrawBling, f.cd, false)                -- we do our own "ready" pop instead
    pcall(f.cd.SetSwipeColor, f.cd, 0, 0, 0, 0.7)
    -- not enough rage/mana: blue tint, like Blizzard's action bars
    f.dim = f:CreateTexture(nil, "OVERLAY")
    f.dim:SetAllPoints(); f.dim:SetColorTexture(0.1, 0.25, 0.8, 0.55); f.dim:SetAlpha(0)
    -- quick "pop" the moment it comes off cooldown
    f.pop = f:CreateAnimationGroup()
    local s = f.pop:CreateAnimation("Scale")
    s:SetScaleFrom(1.3, 1.3); s:SetScaleTo(1, 1); s:SetDuration(0.2)
    if s.SetSmoothing then s:SetSmoothing("OUT") end
    -- Blizzard-style proc glow: shows when this button is what the alerts say to press.
    -- Its own little gate chain, so it can follow secret (locked) conditions too.
    f.glowGates = {}
    local gp = f
    for i = 1, 4 do
        local g = CreateFrame("Frame", nil, gp)
        g:SetAllPoints(f)
        f.glowGates[i], gp = g, g
    end
    f.glowGates[1]:SetAlpha(0)
    f.glow = gp:CreateTexture(nil, "OVERLAY", nil, 7)
    f.glow:SetTexture(MEDIA .. "ProcGlow.tga")        -- our own glow art (icon = middle 64%)
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(1, 0.82, 0.25)
    f.glow:SetPoint("CENTER")
    local ga = f.glow:CreateAnimationGroup()
    ga:SetLooping("BOUNCE")
    local gfade = ga:CreateAnimation("Alpha")
    gfade:SetFromAlpha(1); gfade:SetToAlpha(0.45); gfade:SetDuration(0.5)
    ga:Play()
    f.alphaT = 1                                         -- target alpha; faded smoothly each frame
    f.name = name
    return f
end

-- Big-icon mode: [danger] [ NEXT ] [buff / extra], each a stack of alerts.
-- Empty-slot backgrounds, so the block keeps its shape when nothing is lit.
local slotBG = {}
local function slotBack(key, x, y, s)
    local f = slotBG[key]
    if not f then
        f = CreateFrame("Frame", nil, main)
        f.t = f:CreateTexture(nil, "BACKGROUND")
        f.t:SetAllPoints(); f.t:SetColorTexture(0, 0, 0, 0.35)
        f.px = addBorder(f, 0, 0, 0, 0.8, 1)
        f.frame = goldFrame(f, 4)
        slotBG[key] = f
    end
    f:SetSize(s, s); f:ClearAllPoints()
    f:SetPoint("TOPLEFT", main, "TOPLEFT", x, y)
    f:SetFrameLevel(main:GetFrameLevel() + 1)
    f.frame:SetShown(classic())
    f.t:SetColorTexture(0, 0, 0, classic() and 0.55 or 0.35)
    f:Show()
end

-- Switch every bar between the two styles.
local function applyStyle()
    local c = classic()
    for _, bar in ipairs(BARS) do
        local tex = c and CLASSIC_TEX or BAR_TEX
        bar:SetStatusBarTexture(tex)
        bar:SetStatusBarColor(bar.col[1], bar.col[2], bar.col[3])
        bar.bg:SetTexture(tex)
        bar.bg:SetVertexColor(0.06, 0.06, 0.07, c and 0.9 or 0.85)
        bar.frame:SetShown(c)
        bar.frame:SetFrameLevel(bar:GetFrameLevel() + 4)
        colorBorder(bar.px, 0, 0, 0, c and 0 or 1)
    end
    styleHealthColor(c and CLASSIC_TEX or BAR_TEX)
end

local blockW = BAR_W
local layoutExtras          -- target frame + cast bars; defined further down
-- Big-icon block (EllesmereUI style): a small buff icon on top, then
-- [danger][ NEXT ][extra] packed edge to edge, bars the same width right under.
local function layoutStack()
    local byKey = {}
    for _, a in ipairs(ALERTS) do byKey[a.key] = a; a.root:Hide(); a.inSpot = false end
    local sp = SPOT[CLASS]
    local M, B = SPOT_SIZE.next, SPOT_SIZE.buff
    -- clean style: icons share 1px lines. Classic style: gold frames need a little room.
    local g = classic() and 10 or 1
    local pad = classic() and 5 or 0
    local W = M * 3 + 2 * g + 2 * pad
    local rowY = -(pad + B + g)
    local pos = {
        buff   = { pad, -pad, B },
        danger = { pad, rowY, M },
        next   = { pad + M + g, rowY, M },
        extra  = { pad + 2 * (M + g), rowY, M },
    }
    -- no empty background boxes: a frame only shows around an icon that is lit
    local base = main:GetFrameLevel() + 5
    for spot, keys in pairs(sp) do
        local p = pos[spot]
        for i, key in ipairs(keys) do
            local a = byKey[key]
            if a then
                a.inSpot = true
                a.root:SetSize(p[3], p[3])
                a.root:ClearAllPoints()
                a.root:SetPoint("TOPLEFT", main, "TOPLEFT", p[1], p[2])
                setLevels(a, base + (#keys - i + 1) * 8)     -- first in the list = on top
                local named = DB.names and spot ~= "buff"
                a.c.text:SetShown(named); a.c.plate:SetShown(named)
                a.c.plate:SetSize(p[3] + 2, 16); a.c.text:SetWidth(p[3])
                -- Classic style: the gold frame belongs to the icon, so it hides with it
                if not rawget(a.c, "gold") then a.c.gold = goldFrame(a.c, 4) end
                a.c.gold:SetShown(classic())
                a.c.gold:SetFrameLevel(a.c:GetFrameLevel() + 2)
                -- proc glow on the big icon itself: lit = press it. It lives inside the
                -- icon's gates, so it shows and hides exactly with the alert.
                local gl = rawget(a.c, "glowF")
                if not gl then
                    gl = CreateFrame("Frame", nil, a.c)
                    gl:SetPoint("CENTER")
                    gl.t = gl:CreateTexture(nil, "OVERLAY", nil, 7)
                    gl.t:SetAllPoints(); gl.t:SetTexture(MEDIA .. "ProcGlow.tga"); gl.t:SetBlendMode("ADD")
                    if a.danger then gl.t:SetVertexColor(1, 0.25, 0.2) else gl.t:SetVertexColor(1, 0.82, 0.25) end
                    local ga = gl:CreateAnimationGroup()
                    ga:SetLooping("BOUNCE")
                    local f = ga:CreateAnimation("Alpha")
                    f:SetFromAlpha(1); f:SetToAlpha(0.4); f:SetDuration(0.5)
                    ga:Play()
                    a.c.glowF = gl
                end
                gl:SetSize(p[3] / 0.64, p[3] / 0.64)        -- the icon fills the middle 64% of the art
                gl:SetFrameLevel(a.c:GetFrameLevel() + 3)
                gl:SetShown(DB.glow ~= false)
                if not DB.off[key] then a.root:Show() end
            end
        end
    end
    -- range tint + mob count sit on top of the big icon
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", main, "TOPLEFT", pos.next[1], pos.next[2])
    ring:SetSize(M, M)
    ring:SetFrameLevel(base + 200)
    ring:Show()
    return W, pad + B + g + M + pad + (DB.names and 18 or 0)
end

local function layout()
    local width = BAR_W + 12
    local y = 0
    for _, a in ipairs(ALERTS) do if not a.root then makeSlot(a) end end
    ring:Hide()
    for _, f in pairs(slotBG) do f:Hide() end
    if DB.stack ~= false and SPOT[CLASS] then
        width, y = layoutStack()
    else
        -- row mode: every alert gets its own spot
        local rows = { {}, {} }
        for _, a in ipairs(ALERTS) do
            a.inSpot = true
            a.root:SetSize(SIZE[a.row], SIZE[a.row])
            a.c.text:Show(); a.c.plate:Hide()
            if DB.off[a.key] then a.root:Hide() else a.root:Show(); table.insert(rows[a.row], a) end
        end
        for r = 1, 2 do width = math.max(width, #rows[r] * (SIZE[r] + GAP) - GAP) end
        for r = 1, 2 do
            local list = rows[r]
            local rowW = #list * (SIZE[r] + GAP) - GAP
            for i, a in ipairs(list) do
                a.root:ClearAllPoints()
                a.root:SetPoint("TOPLEFT", main, "TOPLEFT", (width - rowW) / 2 + (i - 1) * (SIZE[r] + GAP), -y)
            end
            if #list > 0 then y = y + SIZE[r] + 26 end
        end
    end
    -- bars: same width as the icon block, stacked tight under it (shared 1px lines)
    applyStyle()
    local gb = classic() and 9 or 1            -- gap between bars (gold frames need room)
    local bp = classic() and 5 or 0            -- bars sit this far inside the block edges
    blockW = ((DB.stack ~= false and SPOT[CLASS]) and width or BAR_W) - 2 * bp
    local x = (width - blockW) / 2
    local top = y
    y = y + (classic() and 6 or 1)
    for _, b in ipairs({ healthBar, rageBar, threatBar, swingBar }) do b:SetWidth(blockW) end
    advice:SetWidth(blockW)
    healthBar:ClearAllPoints(); healthBar:SetPoint("TOPLEFT", main, "TOPLEFT", x, -y)
    rageBar:ClearAllPoints(); rageBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -gb)
    advice:ClearAllPoints(); advice:SetPoint("TOP", rageBar, "BOTTOM", 0, -2)
    advice:SetShown(DB.advice and true or false)
    local spendAt = POWER == MANA and DB.lowMana or DB.dumpAt
    rageBar.tick:SetSize(2, 18)
    rageBar.tick:ClearAllPoints(); rageBar.tick:SetPoint("CENTER", rageBar, "LEFT", blockW * spendAt / 100, 0)
    rageBar.tick:SetShown(POWER == MANA or (POWER == RAGE and CLASS ~= "DRUID") or (CLASS == "DRUID" and POWER == RAGE))
    if POWER == MANA then
        setText(advice.low, "Low mana")
        setText(advice.mid, ""); setText(advice.high, "")
    else
        setText(advice.low, "Building rage")
        setText(advice.mid, "Keep 10 for Shield Block")
    end
    if CLASS then
        local cc = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(CLASS))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS])
        -- health stays classic green (easy to read), not class color
    end
    y = y + 28 + gb + 18 + (DB.advice and 18 or 0)
    -- Caster look (warlock): cast bar right under mana, then one row of DoT timers +
    -- cooldowns. No threat / swing bars (the aggro dots on nameplates cover threat).
    DRU.caster = CLASS == "WARLOCK"
    local known = {}
    if DRU.casterLayout then y = DRU.casterLayout(x, y, gb) end
    -- Important buttons: one centered row right under health + rage (only ones you know)
    for _, f in pairs(cdIcons) do f:Hide() end
    if not DB.off.cooldowns then
        for _, name in ipairs(CD_SPELLS) do
            if spell[name] then
                cdIcons[name] = cdIcons[name] or makeCD(name)
                cdIcons[name].icon:SetTexture(C_Spell.GetSpellTexture(spell[name]) or DEFAULT_ICON)
                table.insert(known, cdIcons[name])
            end
        end
    end
    if #known > 0 then
        local n, cg = #known, 2
        local cs = math.min(44, math.floor((blockW - (n - 1) * cg) / n))
        local cx = (width - (n * cs + (n - 1) * cg)) / 2
        y = y + (classic() and 7 or 3)
        for i, f in ipairs(known) do
            f:SetSize(cs, cs)
            f.glow:SetSize(cs / 0.64, cs / 0.64)          -- the icon fills the middle 64% of the glow art
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", main, "TOPLEFT", cx + (i - 1) * (cs + cg), -y)
            f:Show()
        end
        y = y + cs
    end
    -- threat + swing go under the buttons: when they hide, nothing empty is left in the middle
    threatBar:ClearAllPoints(); threatBar:SetPoint("TOPLEFT", main, "TOPLEFT", x, -(y + gb))
    swingBar:ClearAllPoints(); swingBar:SetPoint("TOPLEFT", threatBar, "BOTTOMLEFT", 0, -gb)
    if DRU.caster then
        threatBar:Hide(); swingBar:Hide()
        y = y + (classic() and 8 or 3)
    else
        threatBar:Show()
        y = y + gb + 10 + gb + 10 + (classic() and 8 or 3)
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", main, "TOPLEFT", x, -top)
    panel:SetSize(blockW, y - top)
    if layoutExtras then y = layoutExtras(width, x, y) end   -- your cast bar + target frame
    info:Hide()
    main:SetSize(width, y + 2)
    main:SetScale(DB.scale)
    main:ClearAllPoints()
    main:SetPoint(DB.point[1], UIParent, DB.point[2], DB.point[3], DB.point[4])
    main:EnableMouse(not DB.locked)
    main:EnableMouseWheel(not DB.locked)
    main.bg:SetShown(not DB.locked)
    if DBagsAlertsState.placeClickers then DBagsAlertsState.placeClickers() end   -- right-click menus follow
end

local function setIcon(a, name, label)
    name = name or a.icon
    if a.iconName ~= name then
        a.iconName = name
        local id = spell[name]
        local tex = id and C_Spell.GetSpellTexture(id) or DRU.icons[name]
        a.c.icon:SetTexture(tex or FALLBACK_ICON[a.key] or DEFAULT_ICON)
    end
    setText(a.c.text, label or a.label)
end

local function safeAlpha(f, v)
    if not pcall(f.SetAlpha, f, v) then f:SetAlpha(1) end
end

local testUntil, soundAt, lit = 0, 0, {}

-- alpha from a yes/no that may be secret (never inspected when secret)
local function boolAlpha(f, v, yes, no)
    if secret(v) then
        local ok, a = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, v, yes, no)
        if ok then safeAlpha(f, a) else f:SetAlpha(yes) end
    else
        f:SetAlpha(v and yes or no)
    end
end

local function updateCD(f)
    local id = spell[f.name]
    if not id then return end
    local ok, c = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(c) == "table" and not sectable(c) then
        if secret(c.startTime) or secret(c.duration) then
            local okD, d = pcall(C_Spell.GetSpellCooldownDuration, id)
            if okD and d and f.cd.SetCooldownFromDurationObject then
                pcall(f.cd.SetCooldownFromDurationObject, f.cd, d)
            end
        elseif (c.duration or 0) > 1.5 then
            f.cd:SetCooldown(c.startTime, c.duration, plain(c.modRate, 1) or 1)
        else
            f.cd:Clear()
        end
    end
    -- ready = full color; on cooldown = gray + faded; coming off cooldown = pop
    local r = ready(f.name)
    if r == true then
        if f.state == "cd" then pcall(f.pop.Play, f.pop) end
        if f.state ~= "ready" then f.state = "ready"; f.icon:SetDesaturated(false); f.alphaT = 1 end
    elseif r == false then
        if f.state ~= "cd" then f.state = "cd"; f.icon:SetDesaturated(true); f.alphaT = 0.5 end
    else
        f.alphaT = 1                                     -- locked: the sweep still shows the cooldown
    end
    local okU, u = pcall(C_Spell.IsSpellUsable, id)
    if okU then boolAlpha(f.dim, u, 0, 1) end
end

-- Fade the button row toward its target alpha (called every frame; 7 icons, cheap).
local function fadeCDs(dt)
    local k = math.min(1, (dt or 0.016) * 10)
    for _, f in pairs(cdIcons) do
        if f:IsShown() then
            local a, t = f:GetAlpha() or 1, f.alphaT or 1
            if math.abs(t - a) > 0.01 then f:SetAlpha(a + (t - a) * k) end
        end
    end
end

-- Show region f only while your power % is in [lo, hi). Works when power is secret
-- (a Step curve turns the percent into 0 or 1 and that becomes the alpha).
local function bandAlpha(f, lo, hi)
    local r, m = UnitPower("player", POWER), UnitPowerMax("player", POWER)
    if not secret(r) and not secret(m) then
        local p = (m and m > 0) and r / m * 100 or 0
        f:SetAlpha((p >= lo and p < hi) and 1 or 0)
        return
    end
    if not UnitPowerPercent then f:SetAlpha(0) return end
    local key = "band" .. lo .. "_" .. hi
    local cv = curves[key]
    if cv == nil then
        local ok, c = pcall(function()
            local x = C_CurveUtil.CreateCurve()
            x:SetType(Enum.LuaCurveType.Step)
            x:AddPoint(0, lo <= 0 and 1 or 0)
            if lo > 0 then x:AddPoint(lo / 100, 1) end
            if hi <= 100 then x:AddPoint(hi / 100, 0) end
            return x
        end)
        cv = ok and c or false
        curves[key] = cv
    end
    if not cv then f:SetAlpha(0) return end
    local ok, a = pcall(UnitPowerPercent, "player", POWER, false, cv)
    if ok then safeAlpha(f, a) else f:SetAlpha(0) end
end

-- "Am I tanking hard right now?" Counts the hits you took (UNIT_COMBAT on you
-- stays readable in combat), plus how many mobs are on you and whether it's an elite.
local hitTimes = {}
local function onUnitCombat(unit, action)
    if unit ~= "player" then return end
    if not secret(action) and (action == "HEAL" or action == "ENERGIZE") then return end
    table.insert(hitTimes, GetTime())
    if #hitTimes > 40 then table.remove(hitTimes, 1) end
end
local function hitsIn(sec)
    local n, now = 0, GetTime()
    for i = #hitTimes, 1, -1 do
        if now - hitTimes[i] <= sec then n = n + 1 else break end
    end
    return n
end
tankingHard = function()
    if not ctx.combat then return false end
    local h = hitsIn(4)
    return h >= 4 or (ctx.enemies or 0) >= 3 or (ctx.elite and h >= 2) or false
end

-- Where the "spend rage" line is right now: higher while you're tanking hard.
spendLine = function()
    if tankingHard() then return math.max(DB.dumpAt, DB.dumpTank or 90) end
    return DB.dumpAt
end

local function updateAdvice()
    local show = ctx.combat or GetTime() < testUntil
    advice:SetAlpha(show and 1 or 0)
    if not show then return end
    if POWER ~= RAGE and POWER ~= MANA or (CLASS == "DRUID" and POWER == RAGE) then
        advice:SetAlpha(0) return                     -- rage tips are warrior words
    end
    if POWER == MANA then
        bandAlpha(advice.low, 0, DB.lowMana)
        return
    end
    local hard = tankingHard()
    local line = spendLine()
    local cleave = (ctx.enemies or 0) >= 2 and spell["Cleave"]
    local many = (ctx.enemies or 0) >= 3

    -- Pick the plain sentence for the middle zone. Only readable facts decide the words;
    -- the rage amount (maybe secret) only decides which zone's sentence you see.
    local mid = "Keep 10 for Shield Block"
    if hard then
        local blockNow = spell["Shield Block"] and ready("Shield Block") == true and timeLeft("Shield Block") <= 0.3
        local clapNow = many and spell["Thunder Clap"] and ready("Thunder Clap") == true and timeLeft("Thunder Clap") <= 1
        local demoNow = (many or ctx.elite) and spell["Demoralizing Shout"] and timeLeft("Demoralizing Shout") <= durationOf("Demoralizing Shout") * 0.3
        if blockNow then mid = "Shield Block now"
        elseif clapNow then mid = "Thunder Clap the pack"
        elseif demoNow then mid = "Demo Shout now"
        else mid = "Save rage for Shield Block" end
        setText(advice.low, "Building rage")
        setText(advice.high, cleave and "Spend: Cleave" or "Spend: Heroic Strike")
    else
        setText(advice.low, "Building rage")
        setText(advice.high, cleave and "Spend: Cleave" or "Spend: Heroic Strike")
    end
    setText(advice.mid, mid)
    if hard then advice.mid:SetTextColor(1, 0.62, 0.3) else advice.mid:SetTextColor(0.85, 0.85, 0.88) end
    bandAlpha(advice.low, 0, 10)
    bandAlpha(advice.mid, 10, line)
    bandAlpha(advice.highGate, line, 1000)
    if not advice.highAnim:IsPlaying() then advice.highAnim:Play() end
    rageBar.tick:ClearAllPoints()
    rageBar.tick:SetPoint("CENTER", rageBar, "LEFT", blockW * line / 100, 0)
end

-- Rage bar: red normally, gold once you are past the "spend" line.
local function colorRage()
    if POWER == MANA then rageBar:SetStatusBarColor(0.2, 0.45, 1) return end
    if POWER == DRU.ENERGY then rageBar:SetStatusBarColor(1, 0.85, 0.1) return end   -- energy: yellow
    local line = spendLine()
    local r, m = UnitPower("player", RAGE), UnitPowerMax("player", RAGE)
    if not secret(r) and not secret(m) then
        if m and m > 0 and r / m * 100 >= line then rageBar:SetStatusBarColor(1, 0.72, 0.1)
        else rageBar:SetStatusBarColor(0.85, 0.12, 0.12) end
        return
    end
    if not UnitPowerPercent then return end
    local key = "rc" .. line
    local set = curves[key]
    if set == nil then
        local ok, c = pcall(function()
            local function ch(lowV, highV)
                local x = C_CurveUtil.CreateCurve()
                x:SetType(Enum.LuaCurveType.Step)
                x:AddPoint(0, lowV); x:AddPoint(line / 100, highV)
                return x
            end
            return { ch(0.85, 1), ch(0.12, 0.72), ch(0.12, 0.1) }
        end)
        set = ok and c or false
        curves[key] = set
    end
    if not set then return end
    local okR, rr = pcall(UnitPowerPercent, "player", RAGE, false, set[1])
    local okG, gg = pcall(UnitPowerPercent, "player", RAGE, false, set[2])
    local okB, bb = pcall(UnitPowerPercent, "player", RAGE, false, set[3])
    if okR and okG and okB then pcall(rageBar.SetStatusBarColor, rageBar, rr, gg, bb) end
end

-- Smooth bars: the game animates between values itself (same as MiniResourceDisplay /
-- Better Personal Resource Display). Bars update only when the game says the value changed.
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local function setBar(bar, v)
    if SMOOTH then
        if not pcall(bar.SetValue, bar, v, SMOOTH) then pcall(bar.SetValue, bar, v) end
    else
        pcall(bar.SetValue, bar, v)
    end
end

local cdAt = 0
local function updateHealth()
    -- Health: bar + percent text. Widgets accept secret numbers; we never compare them.
    pcall(healthBar.SetMinMaxValues, healthBar, 0, UnitHealthMax("player"))
    setBar(healthBar, UnitHealth("player"))
    local h, m = UnitHealth("player"), UnitHealthMax("player")
    if not secret(h) and not secret(m) and m and m > 0 then
        healthBar.text:SetFormattedText("%d%%", h / m * 100 + 0.5)
    elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local okP, pct = pcall(UnitHealthPercent, "player", false, CurveConstants.ScaleTo100)
        if okP then pcall(healthBar.text.SetFormattedText, healthBar.text, "%.0f%%", pct) end
    end
    updateHealthColor(h, m, setBar)
end

local function updatePower()
    -- Rage (warrior) or mana (paladin)
    pcall(rageBar.SetMinMaxValues, rageBar, 0, UnitPowerMax("player", POWER))
    setBar(rageBar, UnitPower("player", POWER))
    if POWER == DRU.ENERGY then      -- cat: energy and combo points
        pcall(rageBar.text.SetFormattedText, rageBar.text, "%d    %d CP", UnitPower("player", POWER), UnitPower("player", DRU.COMBO))
    else
        pcall(rageBar.text.SetFormattedText, rageBar.text, "%d", UnitPower("player", POWER))
    end
    colorRage()
    updateAdvice()
end

local function updateThreat()
    -- Threat on your target. Always shown so the panel never jumps; dim without a target.
    threatBar:SetAlpha((ctx.hostile and not DRU.caster) and 1 or 0)   -- no enemy target: nothing to show
    if ctx.hostile then
        local isTanking, _, scaled = UnitDetailedThreatSituation("player", "target")
        if scaled then
            setBar(threatBar, scaled)
            setBar(threatBar.red, scaled)
            pcall(threatBar.text.SetFormattedText, threatBar.text, "%.0f%%", scaled)
        else
            threatBar:SetValue(0); threatBar.red:SetValue(0); threatBar.text:SetText("")
        end
        if not secret(isTanking) and isTanking == nil then
            threatBar.red:SetAlpha(1)
            threatBar.ok:SetAlpha(0); threatBar.bad:SetAlpha(ctx.combat and 1 or 0)
            if not ctx.combat then threatBar.ok:SetAlpha(0) end
        else
            boolAlpha(threatBar.red, isTanking, 0, 1)   -- red layer hides while you tank
            boolAlpha(threatBar.ok, isTanking, 1, 0)
            boolAlpha(threatBar.bad, isTanking, 0, 1)
        end
    else
        threatBar:SetValue(0); threatBar.red:SetValue(0); threatBar.red:SetAlpha(1)
        threatBar.text:SetText(""); threatBar.ok:SetAlpha(0); threatBar.bad:SetAlpha(0)
    end
end

-- Pieces the slow tick still refreshes (timers that have no event of their own).
local function updateBars()
    local now = GetTime()
    if now - cdAt >= 0.25 then      -- cooldown icons: 4x a second is plenty
        cdAt = now
        for _, f in pairs(cdIcons) do if f:IsShown() then updateCD(f) end end
    end
    colorRage()       -- the spend line moves when heavy hits start/stop
    updateAdvice()
end

-- Which bars need a refresh, set by events and handled once per frame at most.
local barsDirty = { health = true, power = true, threat = true }

-- (range code in its own block: Lua allows only 200 top-level locals)
local updateRange, findNearSpell
do
-- Range ring. Melee = a known melee spell in range. "A few steps away" = a known
-- harmful spell with about 10 yd range (Judgement, Hammer of Justice, Intimidating
-- Shout...), found from the spellbook's own range numbers.
local MELEE = { WARRIOR = { "Sunder Armor", "Heroic Strike", "Hamstring", "Rend" },
                PALADIN = { "Holy Strike", "Crusader Strike" } }
local nearSpell
findNearSpell = function()
    nearSpell = nil
    if not (C_Spell.GetSpellInfo and C_Spell.IsSpellHarmful) then return end
    local best
    for name, id in pairs(spell) do
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and not sectable(info) then
            local mn, mx = plain(info.minRange, 99), plain(info.maxRange, 0)
            local okH, harm = pcall(C_Spell.IsSpellHarmful, id)
            if okH and plain(harm, false) and mn == 0 and mx >= 8 and mx <= 15 and (not best or mx < best) then
                best, nearSpell = mx, name
            end
        end
    end
end
-- Three checks, because one alone lied in game (green at 30+ yards):
--  bar  = your action button for that spell (the same red tint Blizzard's bars use)
--  book = C_Spell.IsSpellInRange
--  near = CheckInteractDistance 3 (about 10 yd; only works out of combat)
local function show(v)
    if v == nil then return "nil" end
    if secret(v) then return "secret" end
    return tostring(v)
end
local function barRange(id)
    local AB = C_ActionBar
    if not (AB and AB.FindSpellActionButtons) then return nil end
    local ok, slots = pcall(AB.FindSpellActionButtons, id)
    if not ok or type(slots) ~= "table" or sectable(slots) then return nil end
    local fn = AB.IsActionInRange or _G.IsActionInRange
    if not fn then return nil end
    for _, slot in ipairs(slots) do
        local okR, r = pcall(fn, slot, "target")
        if okR and r ~= nil then return r end
    end
    return nil
end
local function closeCheck()
    if InCombatLockdown() or not CheckInteractDistance then return nil end
    local ok, r = pcall(CheckInteractDistance, "target", 3)
    if ok and not secret(r) then return r and true or false end
    return nil
end
local dbgAt = 0
local function rangeOf(name, isMelee)
    local id = name and spell[name]
    if not id then return nil end
    local okB, book = pcall(C_Spell.IsSpellInRange, id, "target")
    if not okB then book = nil end
    local bar = barRange(id)
    local close
    if isMelee then close = closeCheck() end
    if isMelee and GetTime() - dbgAt > 1 then      -- for "check logs": what each check said
        dbgAt = GetTime()
        DB.rangeDebug = { spell = name, id = id, book = show(book), bar = show(bar), close = show(close) }
    end
    local r = bar
    if r == nil then r = book end
    -- out of combat the 10 yd check is plain and trustworthy: farther than 10 yd is never melee
    if close == false and (r == nil or secret(r) or r == true) then r = false end
    return r
end
local ringState
-- Color every icon in the big-icon stack (only one is ever visible).
local function tintNext(g, b)
    local keys = SPOT[CLASS] and SPOT[CLASS].next
    if not keys then return end
    for _, a in ipairs(ALERTS) do
        for _, k in ipairs(keys) do
            if a.key == k and a.c then pcall(a.c.icon.SetVertexColor, a.c.icon, 1, g, b) end
        end
    end
end
local function setRing(state)     -- "in", "near", "far"
    if ringState == state then return end
    ringState = state
    if state == "far" then tintNext(0.25, 0.25)
    elseif state == "near" then tintNext(0.75, 0.4)
    else tintNext(1, 1) end
end
-- AGGRO dots: one over EVERY enemy nameplate that is in a fight, plus one on our
-- target frame when your target has no nameplate. Threat status on that mob:
--   3 = it's on you, solid  -> green
--   2 = it's on you, but someone is about to take it -> yellow
--   0/1 or not on its list while it fights -> red (it's NOT hitting you)
-- If the game locks the status number in combat, step curves turn it into alphas
-- without reading it; if even that isn't allowed, it falls back to green/red.
local function newDot()
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetSize(24, 24)
    d:SetFrameStrata("HIGH")
    d:Hide()
    local function tex(r, g, b)
        local t = d:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints(); t:SetTexture(MEDIA .. "Dot.tga"); t:SetAlpha(0)   -- our own dot art
        t:SetVertexColor(r, g, b)
        return t
    end
    d.g = tex(0.2, 1, 0.2)
    d.o = tex(1, 0.85, 0.1)       -- yellow: about to lose aggro
    d.r = tex(1, 0.15, 0.15)
    return d
end
local dot = newDot()              -- the target-frame dot (target without a nameplate)
DBagsAlertsState.dot = dot

local threatCurves
local function statusCurves()
    if threatCurves ~= nil then return threatCurves or nil end
    local ok, c = pcall(function()
        local function step(a0, a1, a2, a3)
            local cv = C_CurveUtil.CreateCurve()
            cv:SetType(Enum.LuaCurveType.Step)
            cv:AddPoint(0, a0); cv:AddPoint(1, a1); cv:AddPoint(2, a2); cv:AddPoint(3, a3)
            return cv
        end
        return { g = step(0, 0, 0, 1), o = step(0, 0, 1, 0), r = step(1, 1, 0, 0) }
    end)
    threatCurves = ok and c or false
    return ok and c or nil
end
local function setState(d, state)
    if state == d.state then return end
    d.state = state
    d.g:SetAlpha(state == "g" and 1 or 0)
    d.o:SetAlpha(state == "o" and 1 or 0)
    d.r:SetAlpha(state == "r" and 1 or 0)
end
-- Color dot d for unit. Returns false when that mob isn't fighting (no dot).
-- trustCombat: the mob's own "in combat" flag may be guessed from ours when locked
-- (only for your target - for every plate that would light up random mobs).
local function colorDot(d, unit, trustCombat)
    local s = UnitThreatSituation("player", unit)
    if not secret(s) then
        if s == nil then
            local tc = UnitAffectingCombat(unit)
            local fighting
            if secret(tc) then fighting = trustCombat and ctx.combat else fighting = tc end
            if not fighting then return false end
            setState(d, "r")
        elseif s >= 3 then setState(d, "g")
        elseif s == 2 then setState(d, "o")
        else setState(d, "r") end
        return true
    end
    d.state = nil                               -- locked number: never compared
    local cv = statusCurves()
    if cv and cv.g.Evaluate then
        local ok1, ag = pcall(cv.g.Evaluate, cv.g, s)
        local ok2, ao = pcall(cv.o.Evaluate, cv.o, s)
        local ok3, ar = pcall(cv.r.Evaluate, cv.r, s)
        if ok1 and ok2 and ok3 and pcall(d.g.SetAlpha, d.g, ag)
           and pcall(d.o.SetAlpha, d.o, ao) and pcall(d.r.SetAlpha, d.r, ar) then
            return true
        end
    end
    local isTanking = UnitDetailedThreatSituation("player", unit)   -- green / red only
    boolAlpha(d.g, isTanking, 1, 0); boolAlpha(d.r, isTanking, 0, 1); d.o:SetAlpha(0)
    return true
end
local function pin(d, anchor, onPlate)
    if d.anchor ~= anchor then
        d.anchor = anchor
        d:ClearAllPoints()
        local ok
        if onPlate then ok = pcall(d.SetPoint, d, "BOTTOM", anchor, "TOP", 0, 4)
        else ok = pcall(d.SetPoint, d, "CENTER", anchor, "TOPRIGHT", -12, -12) end
        if not ok then d.anchor = nil return false end
    end
    d:Show()
    return true
end
local function plateOK(plate)
    return plate and not (plate.IsForbidden and plate:IsForbidden())
       and not (plate.IsVisible and not plate:IsVisible())
end

local pool, used = {}, {}       -- plate frame -> dot
DBagsAlertsState.dotPool = pool
local function plateUnit(p)
    return p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
end
local allOff = false
updateRange = function()
    -- only while YOU are in combat: out of combat nothing is read at all
    local on = DB.range ~= false and ctx.combat
    if not on then
        if not allOff then
            allOff = true
            for _, d in pairs(pool) do d:Hide() end
            dot:Hide()
        end
        return
    end
    allOff = false
    wipe(used)
    -- every enemy nameplate that is fighting
    if on and C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" and not sectable(plates) then
            for _, p in ipairs(plates) do
                local u = plateOK(p) and plateUnit(p)
                if u and not secret(u) then
                    local okA, atk = pcall(UnitCanAttack, "player", u)
                    local dead = UnitIsDead(u)
                    if okA and plain(atk, true) and not plain(dead, false) then
                        local d = pool[p]
                        if not d then d = newDot(); pool[p] = d end
                        if colorDot(d, u, UnitIsUnit(u, "target") == true) and pin(d, p, true) then
                            used[p] = true
                        end
                    end
                end
            end
        end
    end
    for p, d in pairs(pool) do if not used[p] then d:Hide() end end
    -- your target without a nameplate: the dot sits on our target frame
    local tplate
    if on and ctx.hostile then
        local okT, tp = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if okT and plateOK(tp) then tplate = tp end
    end
    local tfr = DBagsAlertsState.targetFrame
    if on and ctx.hostile and not tplate and tfr and tfr:IsShown()
       and colorDot(dot, "target", true) and pin(dot, tfr, false) then
        return
    end
    dot:Hide()
end

end   -- range block

local function updateContext()
    ctx.combat = InCombatLockdown() or plain(UnitAffectingCombat("player"), false)
    ctx.group = IsInGroup()
    local exists = plain(UnitExists("target"), false)
    -- If these are ever locked, assume a target you have in combat is a live enemy.
    local atk = plain(UnitCanAttack("player", "target"), ctx.combat)
    local dead = plain(UnitIsDead("target"), false)
    ctx.hostile = exists and atk and not dead
    local cls = plain(UnitClassification("target"), "normal")
    local lvl = plain(UnitLevel("target"), 0)
    ctx.elite = ctx.hostile and (cls == "elite" or cls == "rareelite" or cls == "worldboss" or lvl == -1) or false
    local ctype = plain(UnitCreatureType("target"), nil)
    ctx.bleedImmune = ctype == "Elemental" or ctype == "Mechanical"
    ctx.ctype = ctype
    if CLASS == "DRUID" then
        local okF, id = pcall(GetShapeshiftFormID or function() return nil end)
        id = okF and plain(id, nil) or nil
        ctx.form = DRU.FORM[id or 0] or "caster"
        ctx.stealth = plain(IsStealthed and IsStealthed(), false) and true or false
        DRU.anyRange = ctx.form ~= "bear" and ctx.form ~= "cat"
    elseif CLASS == "WARLOCK" then
        DRU.anyRange = true           -- caster: count every mob fighting you, at any range
    end
    ctx.enemies, ctx.loose = scanEnemies()
end

local function update()
    if not DB then return end
    updateContext()
    local testing = GetTime() < testUntil
    local glowSet = ctx.glowSet or {}       -- button-row icons that should glow this tick
    ctx.glowSet = glowSet
    wipe(glowSet)
    for _, a in ipairs(ALERTS) do
        if a.root and not DB.off[a.key] and a.inSpot ~= false then
            if testing then
                setIcon(a); a.root:SetAlpha(1); a.rootA = 1
                a.gA = a.gA or {}
                for i = 1, 4 do a.gates[i]:SetAlpha(1); a.gA[i] = 1 end
            else
                -- reuse one table per alert (no garbage every tick)
                local st = a.st
                if not st then st = {}; a.st = st end
                st.ok, st.n = true, 0
                st[1], st[2], st[3], st[4] = nil, nil, nil, nil
                local okT, name, label = pcall(a.test, st)
                if not okT then st.ok = false end
                -- only touch a frame's alpha when it actually changes (secret ones always)
                a.gA = a.gA or {}
                if st.ok then
                    setIcon(a, name, label)
                    if a.rootA ~= 1 then a.rootA = 1; a.root:SetAlpha(1) end
                    for i = 1, 4 do
                        if st[i] then safeAlpha(a.gates[i], st[i]); a.gA[i] = nil
                        elseif a.gA[i] ~= 1 then a.gA[i] = 1; a.gates[i]:SetAlpha(1) end
                    end
                elseif a.rootA ~= 0 then
                    a.rootA = 0; a.root:SetAlpha(0)
                end
                -- Sound only for danger alerts we KNOW are lit (no secret gates).
                local known = st.ok and st.n == 0
                if DB.sound and a.danger and known and not lit[a.key] and GetTime() > soundAt then
                    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
                    soundAt = GetTime() + 3
                end
                lit[a.key] = known
            end
        end
    end
    -- Glow: the button that each big icon is telling you to press (one per spot, in
    -- priority order), with the same conditions - so a glow always means "this one, now".
    local byKey = ctx.byKey
    if not byKey or ctx.byKeyFor ~= ALERTS then
        byKey = {}; for _, a in ipairs(ALERTS) do byKey[a.key] = a end
        ctx.byKey, ctx.byKeyFor = byKey, ALERTS
    end
    local sp = (DB.stack ~= false) and SPOT[CLASS]
    if sp and not testing then
        for _, keys in pairs(sp) do
            for _, key in ipairs(keys) do
                local a = byKey[key]
                local st = a and a.st
                if a and st and st.ok and not DB.off[key] and a.inSpot ~= false then
                    local cdf = cdIcons[a.iconName or a.icon]
                    if cdf and cdf:IsShown() and not glowSet[cdf] then
                        glowSet[cdf] = true
                        cdf.glowGates[1]:SetAlpha(1)
                        for i = 1, 4 do
                            if st[i] then safeAlpha(cdf.glowGates[i], st[i]) elseif i > 1 then cdf.glowGates[i]:SetAlpha(1) end
                        end
                    end
                    break                          -- only the top one in this spot
                end
            end
        end
    end
    if testing then                                -- preview: every button glows
        for _, f in pairs(cdIcons) do
            glowSet[f] = true
            for i = 1, 4 do f.glowGates[i]:SetAlpha(1) end
        end
    end
    for _, f in pairs(cdIcons) do                  -- everything else: no glow
        if not glowSet[f] then f.glowGates[1]:SetAlpha(0) end
    end

    updateBars()
    barsDirty.threat = true        -- threat follows the alert rate, smoothed by the game
    -- small status line: only rebuilt when something in it changed
    local e = ctx.enemies
    local hard = POWER == RAGE and tankingHard()
    local s = ctx.hostile and sunder[targetKey()]
    local stacks = (s and GetTime() - s.last < durationOf("Sunder Armor")) and s.n or 0
    local key = tostring(e) .. (hard and "h" or "") .. stacks
    if key ~= info.key then      -- just a number on the big icon: mobs on you (orange = heavy hits)
        info.key = key
        ring.count:SetText((e and e >= 2) and tostring(e) or "")
        if hard then ring.count:SetTextColor(1, 0.6, 0.25) else ring.count:SetTextColor(1, 1, 1) end
    end
    main:SetAlpha((ctx.combat or ctx.hostile or testing or not DB.locked) and 1 or 0.45)
end

---------------------------------------------------------------------------
-- Target frame + cast bars, so Blizzard's can be hidden. Cast bars use the game's
-- own timer (UnitCastingDuration + SetTimerDuration, the Threat Plates way): WoW
-- animates them itself, smooth, and it works while combat values are locked.
---------------------------------------------------------------------------
local TIMER_NOW = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local DIR_UP = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local DIR_DOWN = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local TARGET_W = 230

local function makeCastBar(parent, h)
    local cb = makeBar(1, 0.7, 0.1, h, "", parent)
    cb.lock = CreateFrame("StatusBar", nil, cb)        -- gray layer: can't be interrupted
    cb.lock:SetAllPoints(); cb.lock:SetStatusBarTexture(BAR_TEX)
    cb.lock:SetStatusBarColor(0.55, 0.55, 0.6); cb.lock:SetMinMaxValues(0, 1)
    cb.lock:SetFrameLevel(cb:GetFrameLevel() + 1); cb.lock:SetAlpha(0)
    cb.top = CreateFrame("Frame", nil, cb)
    cb.top:SetAllPoints(); cb.top:SetFrameLevel(cb:GetFrameLevel() + 2)
    cb.name = cb.top:CreateFontString(nil, "OVERLAY")
    styleText(cb.name, 14, 1, 1, 1)
    cb.name:SetPoint("LEFT", 5, 0); cb.name:SetPoint("RIGHT", -5, 0)
    cb.name:SetJustifyH("LEFT"); cb.name:SetWordWrap(false)
    cb.icon = cb.top:CreateTexture(nil, "OVERLAY")
    cb.icon:SetSize(h, h); cb.icon:SetPoint("RIGHT", cb, "LEFT", -1, 0)
    cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cb.text:Hide(); cb:Hide()
    return cb
end

local castPlayer = makeCastBar(main, 22)

local tf = CreateFrame("Frame", nil, main)              -- target frame
DBagsAlertsState.targetFrame = tf
tf:SetSize(TARGET_W, 90)
tf.name = tf:CreateFontString(nil, "OVERLAY")
styleText(tf.name, 15, 1, 1, 1)
tf.name:SetJustifyH("LEFT"); tf.name:SetWordWrap(false)
tf.level = tf:CreateFontString(nil, "OVERLAY")
styleText(tf.level, 15, 1, 0.82, 0.2)
tf.hp = makeBar(0.8, 0.1, 0.1, 28, "", tf)
styleText(tf.hp.text, 18, 1, 1, 1); tf.hp.text:ClearAllPoints(); tf.hp.text:SetPoint("CENTER")
tf.pw = makeBar(0.2, 0.45, 1, 8, "", tf); tf.pw.text:Hide()
tf.cast = makeCastBar(tf, 22)
tf.tot = tf:CreateFontString(nil, "OVERLAY")              -- who your target is hitting
styleText(tf.tot, 14, 1, 1, 1)
tf.tot:SetJustifyH("RIGHT"); tf.tot:SetWordWrap(false)
tf:Hide()

local tDirty = { all = true }

local function refreshCast(cb, unit, isTarget)
    if not DB.casts then cb:Hide() return end
    local name, _, tex, _, _, _, _, notInt = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, tex, _, _, _, notInt = UnitChannelInfo(unit)
        channel = name and true or false
    end
    if not name then cb:Hide() return end
    local dur
    if channel then dur = UnitChannelDuration and UnitChannelDuration(unit)
    else dur = UnitCastingDuration and UnitCastingDuration(unit) end
    local dir = channel and DIR_DOWN or DIR_UP
    if not (dur and cb.SetTimerDuration and pcall(cb.SetTimerDuration, cb, dur, TIMER_NOW, dir)) then cb:Hide() return end
    pcall(cb.lock.SetTimerDuration, cb.lock, dur, TIMER_NOW, dir)
    pcall(cb.name.SetText, cb.name, name)
    pcall(cb.icon.SetTexture, cb.icon, tex)
    if isTarget then boolAlpha(cb.lock, notInt, 1, 0) else cb.lock:SetAlpha(0) end
    cb:Show()
    if not isTarget and DRU.slideStart then DRU.slideStart(channel) end
end

do   -- slidecast line on your own cast bar (own block: Lua's 200 top-level locals limit)
    -- WoW lets you press your next spell a little before this cast ends (the spell
    -- queue window, 400 ms by default). The white line marks that point; once the
    -- cast passes it the bar turns green: you can start the next one (or move).
    local cb = castPlayer
    -- slidecast zone: the last part of the bar, shaded red (like Quartz' latency box),
    -- with a bright edge where it starts
    cb.zone = cb.top:CreateTexture(nil, "ARTWORK")
    cb.zone:SetColorTexture(0.95, 0.15, 0.15, 0.4)
    cb.zone:Hide()
    cb.slide = cb.top:CreateTexture(nil, "OVERLAY", nil, 6)
    cb.slide:SetColorTexture(1, 1, 1, 0.9)
    cb.slide:SetWidth(2)
    cb.slide:Hide()
    -- spark riding the front of the fill (follows the game's own timer: no math needed)
    cb.spark = cb.top:CreateTexture(nil, "OVERLAY", nil, 7)
    cb.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    cb.spark:SetBlendMode("ADD")
    cb.spark:SetSize(20, 44)
    local fill = cb.GetStatusBarTexture and cb:GetStatusBarTexture()
    if fill then cb.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0) else cb.spark:Hide() end
    cb.left = cb.top:CreateFontString(nil, "OVERLAY")        -- seconds left, right side
    styleText(cb.left, 14, 1, 1, 1)
    cb.left:SetPoint("RIGHT", -5, 0)
    cb.name:SetPoint("RIGHT", -40, 0)
    local function baseColor() local c = cb.col; cb:SetStatusBarColor(c[1], c[2], c[3]) end
    local endAt, slideAt, green           -- plain GetTime() values for this cast, or nil
    local function window()
        local ok, v = pcall(GetCVar or function() end, "SpellQueueWindow")
        v = ok and tonumber(plain(v, nil)) or 400
        return math.max(0, math.min(400, v)) / 1000       -- the game caps it at 400 ms
    end
    -- cast length in seconds: the cast's own times when readable, else the spell's cast time
    local fresh, keepEnd, startID = true, nil, nil   -- fresh = a new cast started (not a pushback update)
    local function castTimes()
        local _, _, _, s, e, _, _, _, id = UnitCastingInfo("player")
        s, e = plain(s, nil), plain(e, nil)
        if type(s) == "number" and type(e) == "number" and e > s then return e / 1000, (e - s) / 1000 end
        id = plain(id, nil) or startID     -- locked: the spell from our own cast-start event
        if id and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            local ct = ok and type(info) == "table" and not sectable(info) and plain(info.castTime, nil)
            if type(ct) == "number" and ct > 0 then
                if keepEnd then return keepEnd, ct / 1000 end    -- pushback, times locked: keep what we had
                return GetTime() + ct / 1000, ct / 1000
            end
        end
    end
    DRU.slideStart = function(channel)
        keepEnd = (not fresh) and endAt or nil
        fresh = false
        endAt, slideAt, green = nil, nil, nil
        baseColor()
        cb.slide:Hide(); cb.zone:Hide(); cb.left:SetText("")
        if channel or DB.slide == false then return end
        local e, len = castTimes()
        if not e then return end
        local w = math.min(window(), len)
        endAt, slideAt = e, e - w
        local width = cb:GetWidth()
        if type(width) == "number" and not secret(width) and width > 0 then
            local x = width * (1 - w / len)
            cb.slide:ClearAllPoints()
            cb.slide:SetPoint("TOP", cb, "TOPLEFT", x, 0); cb.slide:SetPoint("BOTTOM", cb, "BOTTOMLEFT", x, 0)
            cb.zone:ClearAllPoints()
            cb.zone:SetPoint("TOPLEFT", cb, "TOPLEFT", x, 0); cb.zone:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
            cb.slide:Show(); cb.zone:Show()
        end
    end
    local drv = CreateFrame("Frame")
    pcall(drv.RegisterUnitEvent, drv, "UNIT_SPELLCAST_START", "player")
    drv:SetScript("OnEvent", function(_, _, _, _, id)
        fresh = true
        startID = (id ~= nil and not secret(id)) and id or nil
    end)
    drv:SetScript("OnUpdate", function()
        if not endAt then return end
        if not cb:IsShown() then endAt = nil; cb.slide:Hide(); cb.zone:Hide() return end
        local now = GetTime()
        local left = endAt - now
        cb.left:SetFormattedText("%.1f", left > 0 and left or 0)
        local g = now >= slideAt
        if g ~= green then
            green = g
            if g then cb:SetStatusBarColor(0.2, 0.9, 0.3) else baseColor() end
        end
    end)
    DBagsAlertsState.castPlayer = cb
end

do   -- caster look (warlock): cast bar under your mana + a row of DoT timers
    -- Like a caster WeakAura: one tile per DoT you know. Bright with a big countdown
    -- and a draining bar while it's on your target; dark and faded when it's missing;
    -- red numbers in the last 3 seconds. Times come from your own casts (and the real
    -- debuff when the game shares it), so they work in combat.
    local SHADOW = { 0.62, 0.32, 1 }            -- warlock purple
    local TILE_H = 6                            -- timer bar under each tile
    local idle = makeBar(0.1, 0.1, 0.1, 24, "")  -- empty slot when you're not casting
    idle.text:Hide(); idle:SetMinMaxValues(0, 1); idle:SetValue(0); idle:Hide()
    local tiles, used = {}, {}
    local function tile(i)
        if tiles[i] then return tiles[i] end
        local f = CreateFrame("Frame", nil, main)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetPoint("TOPLEFT"); f.icon:SetPoint("TOPRIGHT")
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.shade = f:CreateTexture(nil, "ARTWORK", nil, 2)     -- darkens the icon while missing
        f.shade:SetAllPoints(f.icon); f.shade:SetColorTexture(0, 0, 0, 0.6)
        f.bar = CreateFrame("StatusBar", nil, f)
        f.bar:SetPoint("BOTTOMLEFT"); f.bar:SetPoint("BOTTOMRIGHT"); f.bar:SetHeight(TILE_H)
        f.bar:SetStatusBarTexture(BAR_TEX); f.bar:SetStatusBarColor(SHADOW[1], SHADOW[2], SHADOW[3])
        f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(0)
        f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND")
        f.bar.bg:SetAllPoints(); f.bar.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
        f.top = CreateFrame("Frame", nil, f)
        f.top:SetAllPoints(f.icon); f.top:SetFrameLevel(f:GetFrameLevel() + 3)
        f.num = f.top:CreateFontString(nil, "OVERLAY")
        f.num:SetFont(FONT, 20, "THICKOUTLINE"); f.num:SetPoint("CENTER", 0, 0)
        addBorder(f, 0, 0, 0, 1, 1)
        f.gold = goldFrame(f, 4)
        tiles[i] = f
        return f
    end
    -- which DoTs you know, in rotation order
    local function dotList()
        local list = {}
        for _, n in ipairs({ "Corruption", "Bane of Agony", "Curse of Agony", "Immolate", "Siphon Life" }) do
            if spell[n] and not (n == "Curse of Agony" and spell["Bane of Agony"]) then list[#list + 1] = n end
        end
        local curse = spell["Curse of the Elements"] and "Curse of the Elements" or (spell["Curse of Weakness"] and "Curse of Weakness")
        if curse then list[#list + 1] = curse end
        return list
    end
    -- seconds left on your DoT on the target (nil = not on it / unknown)
    local function left(name)
        local real, aura = targetDebuff(name)
        local now = GetTime()
        if real == "on" then
            local exp = aura and plain(aura.expirationTime, nil)
            if exp and exp > 0 then return exp - now, plain(aura.duration, nil) or durationOf(name) end
        elseif real == "off" then
            local t = DRU.dotAt[name]; local at = t and t[targetKey()]
            if not (at and now - at <= 1) then return nil end        -- just cast: still landing
        end
        local t = DRU.dotAt[name]
        local at = t and t[targetKey()]
        local d = durationOf(name)
        if at and now - at < d then return d - (now - at), d end
    end
    local shown = false
    DRU.casterLayout = function(x, y, gb)
        local cb = castPlayer
        for _, f in ipairs(tiles) do f:Hide() end
        wipe(used)
        if not DRU.caster then
            idle:Hide(); shown = false
            cb.col = { 1, 0.7, 0.1 }
            cb:SetHeight(22); cb.icon:SetSize(22, 22)
            return y
        end
        -- 1) cast bar: full width under your mana, purple, icon on the left
        local h, ih = 24, 24
        cb.col = { SHADOW[1], SHADOW[2], SHADOW[3] }
        cb:SetStatusBarColor(SHADOW[1], SHADOW[2], SHADOW[3])
        cb:SetHeight(h); cb.icon:SetSize(ih, ih)
        y = y + gb + 2
        cb:ClearAllPoints(); cb:SetWidth(blockW - ih - 1)
        cb:SetPoint("TOPLEFT", main, "TOPLEFT", x + ih + 1, -y)
        idle:ClearAllPoints(); idle:SetWidth(blockW - ih - 1)
        idle:SetPoint("TOPLEFT", main, "TOPLEFT", x + ih + 1, -y)
        idle:SetFrameLevel(math.max(0, cb:GetFrameLevel() - 2))
        idle.frame:SetShown(classic()); idle:SetShown(DB.casts and true or false)
        y = y + h + gb + 4
        -- 2) DoT tiles, one row, centered, as big as fits (max 44)
        local list = dotList()
        local n, g = #list, classic() and 8 or 3
        if n > 0 then
            local s = math.min(44, math.floor((blockW - (n - 1) * g) / n))
            local cx = x + (blockW - (n * s + (n - 1) * g)) / 2
            y = y + (classic() and 3 or 0)
            for i, name in ipairs(list) do
                local f = tile(i)
                f.name = name
                f:SetSize(s, s + TILE_H + 1)
                f.icon:SetHeight(s)
                f.icon:SetTexture(C_Spell.GetSpellTexture(spell[name]) or DEFAULT_ICON)
                f.gold:SetShown(classic())
                f:ClearAllPoints(); f:SetPoint("TOPLEFT", main, "TOPLEFT", cx + (i - 1) * (s + g), -y)
                f:Show()
                used[#used + 1] = f
            end
            y = y + s + TILE_H + 1 + (classic() and 6 or 2)
        end
        shown = true
        return y
    end
    -- update the tiles 10x a second
    local t = 0
    local drv = CreateFrame("Frame")
    drv:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 0.1 or not shown then return end
        t = 0
        pcall(function()
            local fight = ctx.hostile
            for _, f in ipairs(used) do
                local l, d
                if fight then
                    l, d = left(f.name)
                    -- a curse tile counts either of your curses
                    if not l and f.name == "Curse of the Elements" then l, d = left("Curse of Weakness") end
                end
                if l and l > 0 then
                    f.shade:SetAlpha(0); f.icon:SetDesaturated(false); f:SetAlpha(1)
                    f.bar:SetValue(d and d > 0 and l / d or 0)
                    f.num:SetFormattedText(l >= 10 and "%d" or "%.1f", l)
                    if l <= 3 then f.num:SetTextColor(1, 0.25, 0.25); f.bar:SetStatusBarColor(1, 0.25, 0.25)
                    else f.num:SetTextColor(1, 1, 1); f.bar:SetStatusBarColor(SHADOW[1], SHADOW[2], SHADOW[3]) end
                else
                    f.shade:SetAlpha(1); f.icon:SetDesaturated(true); f:SetAlpha(fight and 1 or 0.5)
                    f.bar:SetValue(0); f.num:SetText("")
                end
            end
        end)
    end)
    DBagsAlertsState.dotTiles = used
end

local REACTION = { [1] = { 0.85, 0.1, 0.1 }, [2] = { 0.85, 0.1, 0.1 }, [3] = { 0.85, 0.35, 0.1 },
                   [4] = { 0.9, 0.8, 0.1 }, [5] = { 0.1, 0.8, 0.1 }, [6] = { 0.1, 0.8, 0.1 },
                   [7] = { 0.1, 0.8, 0.1 }, [8] = { 0.1, 0.8, 0.1 } }
local POWER_COLOR = { [0] = { 0.2, 0.45, 1 }, [1] = { 0.85, 0.15, 0.15 }, [2] = { 1, 0.5, 0.25 },
                      [3] = { 1, 0.85, 0.1 }, [6] = { 0, 0.8, 1 } }

local function updateTargetHealth()
    pcall(tf.hp.SetMinMaxValues, tf.hp, 0, UnitHealthMax("target"))
    setBar(tf.hp, UnitHealth("target"))
    local h, m = UnitHealth("target"), UnitHealthMax("target")
    if not secret(h) and not secret(m) and m and m > 0 then
        tf.hp.text:SetFormattedText("%d%%", h / m * 100 + 0.5)
    elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitHealthPercent, "target", false, CurveConstants.ScaleTo100)
        if ok then pcall(tf.hp.text.SetFormattedText, tf.hp.text, "%.0f%%", pct) end
    end
end

local function updateTargetPower()
    local pt = plain(UnitPowerType("target"), 0)
    local c = POWER_COLOR[pt] or POWER_COLOR[0]
    tf.pw:SetStatusBarColor(c[1], c[2], c[3])
    pcall(tf.pw.SetMinMaxValues, tf.pw, 0, UnitPowerMax("target", pt))
    setBar(tf.pw, UnitPower("target", pt))
end

local function updateToT()
    local exists = plain(UnitExists("targettarget"), false)
    if not exists then tf.tot:SetText("") return end
    pcall(tf.tot.SetFormattedText, tf.tot, ">> %s", UnitName("targettarget"))
    local me = UnitIsUnit("targettarget", "player")
    if secret(me) then tf.tot:SetTextColor(1, 1, 1)
    elseif me then tf.tot:SetTextColor(0.3, 1, 0.3)            -- hitting you: good
    else tf.tot:SetTextColor(1, 0.3, 0.3) end                    -- hitting someone else: taunt?
end

local function updateTarget()
    if not DB.target or not plain(UnitExists("target"), false) then tf:Hide() return end
    tf:Show()
    if DBagsAlertsState.placeClickers then DBagsAlertsState.placeClickers() end   -- keep the right-click area on it
    pcall(tf.name.SetText, tf.name, UnitName("target"))
    local lvl = UnitLevel("target")
    local cls = plain(UnitClassification("target"), "normal")
    local elite = (cls == "elite" or cls == "rareelite" or cls == "worldboss") and "+" or ""
    if secret(lvl) then tf.level:SetText(elite)
    else tf.level:SetText((lvl == -1 and "??" or tostring(lvl)) .. elite) end
    local r, g, b = 0.85, 0.1, 0.1
    if plain(UnitIsPlayer("target"), false) then
        local _, c = UnitClass("target")
        c = plain(c, nil)
        local cc = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
        if cc then r, g, b = cc.r, cc.g, cc.b end
    else
        local re = plain(UnitReaction("target", "player"), nil)
        if re and REACTION[re] then r, g, b = REACTION[re][1], REACTION[re][2], REACTION[re][3] end
    end
    if plain(UnitIsTapDenied("target"), false) then r, g, b = 0.5, 0.5, 0.5 end   -- someone else's mob
    tf.hp:SetStatusBarColor(r, g, b)
    updateTargetHealth(); updateTargetPower(); updateToT()
    refreshCast(tf.cast, "target", true)
end

-- Place your cast bar under the bars, and the target frame to the right of the block.
layoutExtras = function(width, x, y)
    local gb = classic() and 9 or 1           -- room for the gold frames in Classic style
    if not DRU.caster then                    -- caster look: the cast bar sits under your mana instead
        castPlayer:ClearAllPoints()
        castPlayer:SetWidth(blockW - 23)
        castPlayer:SetPoint("TOPLEFT", main, "TOPLEFT", x + 23, -(y + gb + 2))
        y = y + 22 + gb + 6
    end
    local rowTop = (DB.stack ~= false and SPOT[CLASS]) and (SPOT_SIZE.buff + (classic() and 15 or 2)) or 0
    tf:ClearAllPoints()
    tf:SetPoint("TOPLEFT", main, "TOPLEFT", width + 22, -rowTop)
    tf.name:ClearAllPoints(); tf.name:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, 0); tf.name:SetWidth(TARGET_W - 40)
    tf.level:ClearAllPoints(); tf.level:SetPoint("TOPRIGHT", tf, "TOPRIGHT", 0, 0)
    tf.hp:SetWidth(TARGET_W); tf.hp:ClearAllPoints(); tf.hp:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, -(18 + gb))
    tf.pw:SetWidth(TARGET_W); tf.pw:ClearAllPoints(); tf.pw:SetPoint("TOPLEFT", tf.hp, "BOTTOMLEFT", 0, -gb)
    tf.cast:SetWidth(TARGET_W - 23); tf.cast:ClearAllPoints(); tf.cast:SetPoint("TOPLEFT", tf.pw, "BOTTOMLEFT", 23, -(gb + 2))
    tf.tot:ClearAllPoints(); tf.tot:SetPoint("TOPRIGHT", tf.cast, "BOTTOMRIGHT", 0, -4); tf.tot:SetWidth(TARGET_W)
    tDirty.all = true
    return y
end

-- Hide Blizzard's own frames (out of combat only; /reload brings them back).
local blizzHider = CreateFrame("Frame"); blizzHider:Hide()
local function hideBlizzard()
    if not DB.hideBlizz or InCombatLockdown() then return end
    for _, f in ipairs({ PlayerFrame, TargetFrame, PlayerCastingBarFrame or CastingBarFrame }) do
        if f then pcall(function() f:UnregisterAllEvents(); f:SetParent(blizzHider) end) end
    end
end

do   -- missing buff reminder (own block: Lua's 200 top-level locals limit)
    -- Battle Shout fell off? A gold-glowing icon sits left of the block, in or out of
    -- combat. Out of combat with too little rage it shows Bloodrage first (free rage),
    -- then Battle Shout. Hidden in towns/inns, on a mount, and when dead.
    local NAG = { WARRIOR = { buff = "Battle Shout", helper = "Bloodrage" } }
    do      -- class is only known after login, so the frame is always made and checks it live
        local cfg
        local f = CreateFrame("Frame", nil, main)
        f:SetSize(44, 44)
        f:SetPoint("TOPRIGHT", main, "TOPLEFT", -10, 0)
        f:Hide()
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints(); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        addBorder(f, 0, 0, 0, 1, 1)
        f.gold = goldFrame(f, 4)
        f.glow = f:CreateTexture(nil, "OVERLAY", nil, 7)
        f.glow:SetTexture(MEDIA .. "ProcGlow.tga"); f.glow:SetBlendMode("ADD")
        f.glow:SetVertexColor(1, 0.82, 0.25); f.glow:SetPoint("CENTER")
        f.glow:SetSize(44 / 0.64, 44 / 0.64)
        local ga = f:CreateAnimationGroup()
        ga:SetLooping("BOUNCE")
        local fa = ga:CreateAnimation("Alpha")
        fa:SetFromAlpha(1); fa:SetToAlpha(0.55); fa:SetDuration(0.6)
        ga:Play()
        f.text = f:CreateFontString(nil, "OVERLAY")
        styleText(f.text, 13, 1, 0.82, 0.2)
        f.text:SetPoint("TOP", f, "BOTTOM", 0, -3)
        DBagsAlertsState.buffNag = f

        -- seconds of buff left: the real aura when the game shows it, else our cast timer
        -- In combat WoW hides auras from addons: then "no aura" does NOT mean "no buff".
        -- So: read the aura only when the game isn't hiding them, remember the end time
        -- we last saw, and in combat use that (or our own cast timer, whichever is later).
        local seenEnd                   -- plain expiration time from the last real read
        local seenNone                  -- last real read said: not on you
        local function aurasHidden()
            if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
            local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
            return not ok or secret(r) or r == true
        end
        local function buffLeft()   -- (cfg set by check)
            local now = GetTime()
            if not aurasHidden() and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
                local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", cfg.buff, "HELPFUL")
                if ok and not secret(a) and not sectable(a) then
                    if not a then seenEnd = nil; seenNone = true; return 0 end
                    seenNone = false
                    local e = a.expirationTime
                    if not secret(e) then
                        if not e or e == 0 then seenEnd = math.huge; return 999 end
                        seenEnd = e
                        return e - now
                    end
                end
            end
            local mine = timeLeft(cfg.buff)
            local seen = seenEnd and (seenEnd - now) or 0
            -- never seen it either way and no cast of ours: don't guess "missing"
            if not seenEnd and not seenNone and mine <= 0 then return 999 end
            return math.max(mine, seen)
        end
        local function plainYes(v) return v == true end    -- secret or table -> no
        local shownKey
        local function check()
            cfg = CLASS and NAG[CLASS]
            if not cfg or not DB or DB.buffNag == false or not spell[cfg.buff] or UnitIsDeadOrGhost("player") or IsMounted()
               or (IsResting() and not ctx.combat) then
                f:Hide(); shownKey = nil return
            end
            if buffLeft() > 10 then f:Hide(); shownKey = nil return end
            -- out of combat, rage too low to shout: Bloodrage first
            local show = cfg.buff
            if not ctx.combat and not plainYes(usable(cfg.buff)) and spell[cfg.helper] and plainYes(ready(cfg.helper)) then
                show = cfg.helper
            end
            if show ~= shownKey then
                shownKey = show
                f.icon:SetTexture(C_Spell.GetSpellTexture(spell[show]) or DEFAULT_ICON)
                f.text:SetText(show == cfg.helper and "BLOODRAGE" or "SHOUT")
            end
            f.gold:SetShown(classic())
            f:Show()
        end
        local t = 0
        local drv = CreateFrame("Frame")
        drv:SetScript("OnUpdate", function(_, e)
            t = t + e
            if t < 0.25 then return end
            t = 0
            pcall(check)
        end)
    end
end

do   -- stance reminder (own block: Lua's 200 top-level locals limit)
    -- Icy Veins (Forever prot leveling): "Open with Charge when possible, then swap to
    -- Defensive Stance" - Revenge and your main tank tools need it. So: in a fight with
    -- an enemy, out of Defensive for more than 2 seconds (time to Charge / Overpower /
    -- Intercept), a big DEFENSIVE icon flashes a bit above the middle of the screen.
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(64, 64)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
    f:SetFrameStrata("HIGH")
    f:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addBorder(f, 0, 0, 0, 1, 1)
    f.gold = goldFrame(f, 4)
    f.glow = f:CreateTexture(nil, "OVERLAY", nil, 7)
    f.glow:SetTexture(MEDIA .. "ProcGlow.tga"); f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(1, 0.3, 0.2); f.glow:SetPoint("CENTER")
    f.glow:SetSize(64 / 0.64, 64 / 0.64)
    f.text = f:CreateFontString(nil, "OVERLAY")
    styleText(f.text, 22, 1, 0.3, 0.25)
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)
    f.text:SetText("DEFENSIVE")
    local ga = f:CreateAnimationGroup()          -- flashing
    ga:SetLooping("BOUNCE")
    local fa = ga:CreateAnimation("Alpha")
    fa:SetFromAlpha(1); fa:SetToAlpha(0.25); fa:SetDuration(0.4)
    DBagsAlertsState.stanceNag = f

    -- is Defensive Stance the active stance? true / false, or nil when we can't tell
    local function inDefensive()
        local id = spell["Defensive Stance"]
        if not id or not GetNumShapeshiftForms or not GetShapeshiftFormInfo then return nil end
        local okN, n = pcall(GetNumShapeshiftForms)
        if not okN or secret(n) or not n then return nil end
        for i = 1, n do
            local ok, _, active, _, sid = pcall(GetShapeshiftFormInfo, i)
            if ok and not secret(sid) and not secret(active) then
                local okName, nm = pcall(C_Spell.GetSpellName, sid)
                if sid == id or (okName and nm == "Defensive Stance") then return active and true or false end
            end
        end
        return nil
    end
    DBagsAlertsState.inDefensive = inDefensive

    local offSince
    local t = 0
    local drv = CreateFrame("Frame")
    drv:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 0.2 then return end
        t = 0
        pcall(function()
            local want = DB and DB.stanceNag ~= false and CLASS == "WARRIOR" and ctx.combat and ctx.hostile
                         and not UnitIsDeadOrGhost("player")
            local def = want and inDefensive()
            if want and def == false then
                offSince = offSince or GetTime()
                if GetTime() - offSince >= 2 then
                    if not f:IsShown() then
                        f.icon:SetTexture(C_Spell.GetSpellTexture(spell["Defensive Stance"]) or DEFAULT_ICON)
                        f.gold:SetShown(classic())
                        f:Show(); ga:Play()
                    end
                    return
                end
            else
                offSince = nil
            end
            if f:IsShown() then ga:Stop(); f:Hide() end
        end)
    end)
end

do   -- eat-food reminder (own block: Lua's 200 top-level locals limit)
    -- Forever: every cooked food gives Well Fed + "Well Fed XP Boost" (+5% XP from
    -- kills, Wowhead spell 1243969, a hidden aura). Out of combat, when you have no
    -- Well Fed and a food in your bags says "well fed", an EAT button shows. Click it
    -- to eat (one click = one use, like an action button). Hidden in combat, on a
    -- mount, when dead, at max level, and while you're already eating.
    local XP_AURA = 1243969
    local b = CreateFrame("Button", "DBagsAlertsEatButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(44, 44)
    b:SetPoint("TOPRIGHT", main, "TOPLEFT", -10, -72)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addBorder(b, 0, 0, 0, 1, 1)
    b.gold = goldFrame(b, 4)
    b.glow = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.glow:SetTexture(MEDIA .. "ProcGlow.tga"); b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(0.4, 1, 0.4); b.glow:SetPoint("CENTER")
    b.glow:SetSize(44 / 0.64, 44 / 0.64)
    local ga = b:CreateAnimationGroup()
    ga:SetLooping("BOUNCE")
    local fa = ga:CreateAnimation("Alpha")
    fa:SetFromAlpha(1); fa:SetToAlpha(0.6); fa:SetDuration(0.7)
    ga:Play()
    b.text = b:CreateFontString(nil, "OVERLAY")
    styleText(b.text, 13, 0.45, 1, 0.45)
    b.text:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.text:SetText("EAT")
    b:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
        GameTooltip:AddLine("Click to eat: +5% XP (Well Fed).", 0.45, 1, 0.45)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    DBagsAlertsState.eatButton = b

    -- true = fed (or eating), false = not, nil = the game hides auras right now
    local function hasAura(name)
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if not ok or secret(a) or sectable(a) then return nil end
        return a ~= nil
    end
    -- Out of combat buffs are readable; the "secret" flag is only trusted in combat
    -- (this only runs out of combat anyway). Second value = which buff, for /pa food.
    local function fed()
        if not C_UnitAuras then return nil, "no aura API" end
        if InCombatLockdown() and C_Secrets and C_Secrets.ShouldAurasBeSecret then
            local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
            if not ok or secret(r) or r == true then return nil, "buffs hidden" end
        end
        local wf, food, fd = hasAura("Well Fed"), hasAura("Food"), hasAura("Food & Drink")
        if wf == nil then return nil, "buffs hidden" end
        if wf then return true, "Well Fed" end
        if food or fd then return true, "eating" end
        return false, "not fed"
    end

    -- Does this item's tooltip promise Well Fed? Cached per item (nil = not loaded yet).
    local isFood = {}
    local function wellFedFood(id)
        if isFood[id] ~= nil then return isFood[id] end
        if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
        local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
        if not ok or type(data) ~= "table" or sectable(data) or type(data.lines) ~= "table" then return nil end
        local yes, hasUse = false, false
        for _, line in ipairs(data.lines) do
            local t = line.leftText
            if type(t) == "string" and not secret(t) then
                local low = t:lower()
                if low:find("well fed", 1, true) then yes = true break end
                if low:find("use:", 1, true) or low:find("sell price", 1, true) or low:find("max stack", 1, true) then hasUse = true end
            end
        end
        -- a half-loaded tooltip (item not cached yet) has only a line or two: ask again later
        if not yes and not hasUse and #data.lines < 4 then return nil end
        isFood[id] = yes
        return yes
    end
    local function minLevel(id)
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if not getInfo then return 0 end
        local ok, _, _, _, _, lvl = pcall(getInfo, id)
        if ok and type(lvl) == "number" then return lvl end
        return 0
    end
    -- the best well-fed food you can eat now: highest required level wins
    local function findFood()
        if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return nil end
        local myLevel = plain(UnitLevel("player"), 1) or 1
        local best, bestLvl, bestIcon
        local seen, done = {}, {}         -- what we looked at, for /pa food
        for bag = 0, 4 do
            local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
            for slot = 1, (okN and type(n) == "number" and n or 0) do
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not sectable(info) and info.itemID then
                    local id = info.itemID
                    local wf = wellFedFood(id)
                    local lvl = minLevel(id)
                    if not done[id] and #seen < 12 then
                        done[id] = true
                        seen[#seen + 1] = id .. "=" .. (wf == nil and "?" or (wf and "food" or "no")) .. "/lv" .. lvl
                    end
                    if wf and lvl <= myLevel and (not bestLvl or lvl > bestLvl) then
                        best, bestLvl, bestIcon = id, lvl, info.iconFileID
                    end
                end
            end
        end
        return best, bestIcon, table.concat(seen, " ")
    end

    local driven = false
    local function hide()
        if driven and UnregisterStateDriver then UnregisterStateDriver(b, "visibility") end
        driven = false
        b:Hide()
    end
    -- why the button is hidden, for "/pa food" and "check logs" (saved in DBagsAlertsDB)
    local function note(why, extra)
        if DB then DB.foodDebug = { why = why, extra = extra, at = date and date("%H:%M:%S") or "" } end
    end
    local function update()
        if InCombatLockdown() then return end          -- secure button: only change it out of combat
        local okM, maxLvl = pcall(GetMaxPlayerLevel or function() return 60 end)
        if not okM or type(maxLvl) ~= "number" or secret(maxLvl) or maxLvl < 10 then maxLvl = 60 end
        if not DB or DB.foodNag == false then hide() note("turned off") return end
        if UnitIsDeadOrGhost("player") then hide() note("dead") return end
        local lvl = plain(UnitLevel("player"), 1) or 1
        if lvl >= maxLvl then hide() note("max level", maxLvl) return end
        local f, which = fed()
        if f ~= false then hide() note(f == nil and "can't read buffs" or "already fed / eating", which) return end
        local id, icon, seen = findFood()
        if not id then hide() note("no well-fed food found", seen) return end
        note("showing", id)
        if b.itemID ~= id then
            b.itemID = id
            b:SetAttribute("item", "item:" .. id)
            b.icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or DEFAULT_ICON)
        end
        b.gold:SetShown(classic())
        if not driven and RegisterStateDriver then
            RegisterStateDriver(b, "visibility", "[combat][mounted][dead] hide; show")
            driven = true
        elseif not RegisterStateDriver then
            b:Show()
        end
    end
    DBagsAlertsState.foodUpdate = update

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
    local due = 0
    ev:SetScript("OnEvent", function() due = 0 end)   -- check again on the next tick
    ev:SetScript("OnUpdate", function(_, e)
        due = due - e
        if due > 0 then return end
        due = 2                                          -- also every 2 s (buff running out)
        pcall(update)
    end)
end

do   -- weapon stone reminder (own block: Lua's 200 top-level locals limit)
    -- Main hand has no stone on it (sharpening stone for blades, weightstone for
    -- blunt)? Out of combat a button shows: click = use the stone on your main hand
    -- (a normal 2-line macro: /use stone, /use 16). No stone in your bags: a grey
    -- "NO STONE" icon instead (can be turned off). Hidden in combat, mounted, dead.
    local SHARP = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [9] = true, [15] = true, [13] = true }
    local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }
    local b = CreateFrame("Button", "DBagsAlertsStoneButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(44, 44)
    b:SetPoint("TOPRIGHT", main, "TOPLEFT", -10, -144)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addBorder(b, 0, 0, 0, 1, 1)
    b.gold = goldFrame(b, 4)
    b.glow = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.glow:SetTexture(MEDIA .. "ProcGlow.tga"); b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(0.55, 0.8, 1); b.glow:SetPoint("CENTER")
    b.glow:SetSize(44 / 0.64, 44 / 0.64)
    local ga = b:CreateAnimationGroup()
    ga:SetLooping("BOUNCE")
    local fa = ga:CreateAnimation("Alpha")
    fa:SetFromAlpha(1); fa:SetToAlpha(0.6); fa:SetDuration(0.7)
    ga:Play()
    b.text = b:CreateFontString(nil, "OVERLAY")
    styleText(b.text, 13, 0.6, 0.85, 1)
    b.text:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
            GameTooltip:AddLine("Click: put it on your main hand weapon.", 0.6, 0.85, 1)
        else
            GameTooltip:SetText(self.need or "Weapon stone", 1, 0.82, 0.2)
            GameTooltip:AddLine("No stone in your bags. Blacksmiths make them; trade goods vendors and the Auction House sell them.", 1, 1, 1, true)
            GameTooltip:AddLine("Turn this off: /pa > Show if I have none.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    DBagsAlertsState.stoneButton = b

    -- "sharp", "blunt" or nil for your main hand weapon
    local function weaponKind()
        local okI, id = pcall(GetInventoryItemID, "player", 16)
        if not okI or not id or secret(id) then return nil end
        local getI = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        if not getI then return nil end
        local ok, _, _, _, _, _, classID, subID = pcall(getI, id)
        if not ok or classID ~= 2 then return nil end      -- 2 = weapon
        if SHARP[subID] and BLUNT[subID] then return "both" end
        if SHARP[subID] then return "sharp" end
        if BLUNT[subID] then return "blunt" end
        return nil
    end
    -- stone on the main hand? true / false / nil (can't tell)
    local function stoned()
        if not GetWeaponEnchantInfo then return nil end
        local ok, has, ms = pcall(GetWeaponEnchantInfo)
        if not ok or secret(has) then return nil end
        if not has then return false end
        if not secret(ms) and type(ms) == "number" and ms < 60000 then return false end   -- under a minute left
        return true
    end
    local function stoneKind(name)
        if type(name) ~= "string" or secret(name) then return nil end
        if name:find("Sharpening Stone", 1, true) then return "sharp" end
        if name:find("Weightstone", 1, true) then return "blunt" end
        return nil
    end
    local function itemName(id)
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if not getInfo then return nil end
        local ok, name, _, _, _, lvl = pcall(getInfo, id)
        if ok then return name, (type(lvl) == "number" and lvl or 0) end
    end
    -- best stone for this weapon in your bags (highest required level you can use)
    local function findStone(kind)
        if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return nil end
        local myLevel = plain(UnitLevel("player"), 1) or 1
        local best, bestLvl, bestIcon
        for bag = 0, 4 do
            local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
            for slot = 1, (okN and type(n) == "number" and n or 0) do
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not sectable(info) and info.itemID then
                    local name, lvl = itemName(info.itemID)
                    local k = stoneKind(name or info.itemName)
                    if k and (kind == "both" or k == kind) and (lvl or 0) <= myLevel
                       and (not bestLvl or lvl > bestLvl) then
                        best, bestLvl, bestIcon = info.itemID, lvl, info.iconFileID
                    end
                end
            end
        end
        return best, bestIcon
    end

    local driven = false
    local function hide()
        if driven and UnregisterStateDriver then UnregisterStateDriver(b, "visibility") end
        driven = false
        b:Hide()
    end
    local function show()
        b.gold:SetShown(classic())
        if not driven and RegisterStateDriver then
            RegisterStateDriver(b, "visibility", "[combat][mounted][dead] hide; show")
            driven = true
        elseif not RegisterStateDriver then
            b:Show()
        end
    end
    local function update()
        if InCombatLockdown() then return end          -- secure button: only change it out of combat
        if not DB or DB.stoneNag == false or CLASS == "DRUID" or CLASS == "WARLOCK" or UnitIsDeadOrGhost("player") then hide() return end
        local kind = weaponKind()
        if not kind or stoned() ~= false then hide() return end
        local id, icon = findStone(kind)
        if id then
            if b.itemID ~= id then
                b.itemID = id
                b:SetAttribute("type", "macro")
                b:SetAttribute("macrotext", "/use item:" .. id .. "\n/use 16")
                b.icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or DEFAULT_ICON)
                b.icon:SetDesaturated(false)
                b.text:SetText(kind == "blunt" and "WEIGHT" or "SHARPEN")
                b.text:SetTextColor(0.6, 0.85, 1)
                b.glow:Show()
            end
            show()
        elseif DB.stoneNeed ~= false then
            if b.itemID or not b.need then
                b.itemID = nil
                b:SetAttribute("type", nil)
                b.icon:SetTexture(kind == "blunt" and "Interface\\Icons\\INV_Stone_WeightStone_01"
                                  or "Interface\\Icons\\INV_Stone_SharpeningStone_01")
                b.icon:SetDesaturated(true)
                b.text:SetText("NO STONE")
                b.text:SetTextColor(0.6, 0.6, 0.6)
                b.glow:Hide()
            end
            b.need = kind == "blunt" and "Weightstone" or "Sharpening Stone"
            show()
        else
            hide()
        end
    end
    DBagsAlertsState.stoneUpdate = update

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
                         "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local due = 0
    ev:SetScript("OnEvent", function() due = 0 end)
    ev:SetScript("OnUpdate", function(_, e)
        due = due - e
        if due > 0 then return end
        due = 3                                          -- also every 3 s (stone wearing off)
        pcall(update)
    end)
end

do   -- click buttons (own block: Lua's 200 top-level locals limit)
    -- Blizzard's secure unit buttons over our frames: right-click = the normal WoW
    -- menu (invite, whisper, trade...), left-click = target, mouseover = tooltip.
    -- They sit on UIParent (not inside our frames) so hiding/moving our frames in
    -- combat never touches them; they can only be moved out of combat.
    local function makeClicker(unit, name)
        local b = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
        b:SetAttribute("unit", unit)
        b:SetAttribute("*type1", "target")
        b:SetAttribute("*type2", "togglemenu")
        b:RegisterForClicks("AnyUp")
        b.unit = unit
        b:SetScript("OnEnter", function(self)
            if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
            else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local tClick = makeClicker("target", "DBagsAlertsTargetClick")
    local pClick = makeClicker("player", "DBagsAlertsPlayerClick")
    if RegisterUnitWatch then RegisterUnitWatch(tClick) end   -- shows only while you have a target
    local wanted = false
    -- copy a frame's on-screen box onto a click button (positions in UIParent units)
    local function cover(btn, f, h)
        local l, t = f:GetLeft(), f:GetTop()
        if not l or not t then return end
        local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * k, t * k)
        btn:SetSize(f:GetWidth() * k, (h or f:GetHeight()) * k)
    end
    local function place()
        if InCombatLockdown() then wanted = true return end   -- Blizzard rule: move them after combat
        wanted = false
        cover(tClick, tf, 18 + 9 + 28 + 9 + 8)    -- name line + health + power
        cover(pClick, healthBar)
        pClick:SetShown(DB.target ~= false)
        if DB.target == false then
            if UnregisterUnitWatch then UnregisterUnitWatch(tClick) end
            tClick:Hide()
        end
    end
    DBagsAlertsState.placeClickers = place
    local w = CreateFrame("Frame")
    w:RegisterEvent("PLAYER_REGEN_ENABLED")
    w:SetScript("OnEvent", function() if wanted then place() end end)
end   -- click buttons

do   -- cursor ring (own block: Lua's 200 top-level locals limit)
    -- A smooth ring in your class color around the mouse. Hidden while you hold
    -- right-click to turn the camera (the cursor is hidden then too).
    local cr = CreateFrame("Frame", "DBagsAlertsCursorRing", UIParent)
    cr:SetFrameStrata("TOOLTIP")
    cr:SetSize(48, 48)
    cr:EnableMouse(false)
    cr.t = cr:CreateTexture(nil, "OVERLAY")
    cr.t:SetAllPoints()
    cr.t:SetTexture(MEDIA .. "Ring.tga")
    cr:Hide()
    local lastX, lastY
    local function refresh()
        if not DB then return end
        local s = DB.cursorSize or 48
        cr:SetSize(s, s)
        local cc = CLASS and RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS]
        if cc then cr.t:SetVertexColor(cc.r, cc.g, cc.b, 0.9) else cr.t:SetVertexColor(1, 0.82, 0.2, 0.9) end
        lastX = nil
    end
    DBagsAlertsState.cursorRefresh = refresh
    local drv = CreateFrame("Frame")
    drv:SetScript("OnUpdate", function()
        if not DB then return end
        local want = DB.cursor ~= false and not (IsMouselooking and IsMouselooking())
            and (not DB.cursorCombat or InCombatLockdown())
        if not want then
            if cr:IsShown() then cr:Hide() end
            return
        end
        if not cr:IsShown() then cr:Show() end
        local x, y = GetCursorPosition()
        if x ~= lastX or y ~= lastY then           -- only move it when the mouse moved
            lastX, lastY = x, y
            local sc = UIParent:GetEffectiveScale() or 1
            if sc <= 0 then sc = 1 end
            cr:ClearAllPoints()
            cr:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
        end
    end)
end   -- cursor ring

do   -- events block (own scope: Lua's 200 top-level locals limit)
---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- How it runs (copied from smooth addons): events mark what changed; work happens
-- once, on the next frame. Alerts: at most 10x a second, and only when something
-- changed - plus a slow check (3x a second in a fight, 2x out) for timers running out.
local elapsed, auraDirty, errShown = 0, false, false
local alertsDirty, lastAlerts = true, 0
local spellsDirty, spellsAt = false, 0

local function run(f)
    local ok, err = pcall(f)
    if not ok and not errShown then   -- report once, never spam
        errShown = true
        say("|cffff5555error:|r %s", tostring(err))
    end
end

local function rebuildSpells()
    local before = 0
    for _, id in pairs(spell) do before = before + id end
    buildSpells()
    findNearSpell()
    wipe(durCache)
    local after = 0
    for _, id in pairs(spell) do after = after + id end
    if after ~= before then          -- only redo the layout when your spells really changed
        for _, a in ipairs(ALERTS) do a.iconName = nil end
        layout()
    end
end

main:SetScript("OnUpdate", function(_, dt)
    if not DB then return end
    if barsDirty.health then barsDirty.health = false; run(updateHealth) end
    if barsDirty.power then barsDirty.power = false; run(updatePower) end
    if barsDirty.threat then barsDirty.threat = false; run(updateThreat) end
    if tDirty.all then
        tDirty.all, tDirty.hp, tDirty.pw, tDirty.tot = false, false, false, false
        run(updateTarget)
    else
        if tDirty.hp then tDirty.hp = false; run(updateTargetHealth) end
        if tDirty.pw then tDirty.pw = false; run(updateTargetPower) end
        if tDirty.tot then tDirty.tot = false; run(updateToT) end
    end
    if tDirty.castP then tDirty.castP = false; run(function() refreshCast(castPlayer, "player", false) end) end
    if tDirty.castT then tDirty.castT = false; run(function() refreshCast(tf.cast, "target", true) end) end
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    local now = GetTime()
    local fight = ctx.combat or ctx.hostile
    if not alertsDirty and now - lastAlerts < (fight and 0.33 or 0.5) then return end
    elapsed, alertsDirty, lastAlerts = 0, false, now
    if spellsDirty and now - spellsAt > 0.5 and not InCombatLockdown() then
        spellsDirty = false
        run(rebuildSpells)
    end
    if auraDirty and not InCombatLockdown() then auraDirty = false; readAll() end
    run(update)
end)

-- Swing bar: its own every-frame driver so it slides smoothly (one SetValue per frame).
local swingDriver = CreateFrame("Frame")
local rangeAt = 0
swingDriver:SetScript("OnUpdate", function(_, dt)
    if not DB then return end
    updateSwing()
    fadeCDs(dt)
    local now = GetTime()
    if now - rangeAt >= 0.1 then rangeAt = now; run(updateRange) end   -- range dot keeps up as you move
end)

-- Druid: power type follows the form (mana / rage / energy)
DRU.refreshPower = function()
    if CLASS ~= "DRUID" then return end
    local p = plain(UnitPowerType("player"), POWER)
    if type(p) ~= "number" or p == POWER then return end
    POWER = p
    barsDirty.power = true
    pcall(layout)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if not CLASS_ALERTS[class] then main:Hide(); return end
        CLASS, ALERTS, CD_SPELLS = class, CLASS_ALERTS[class], CLASS_CDS[class]
        POWER = (class == "PALADIN" or class == "WARLOCK") and MANA or RAGE
        if class == "DRUID" then POWER = plain(UnitPowerType("player"), MANA) or MANA end
        if POWER == MANA then rageBar:SetStatusBarColor(0.15, 0.4, 1) end
        DBagsAlertsState.alerts = ALERTS
        -- Was "ProtAlerts": take its settings once, then turn the old addon off
        -- (both at once = two of everything on screen).
        if not DBagsAlertsDB and type(ProtAlertsDB) == "table" then DBagsAlertsDB = CopyTable(ProtAlertsDB) end
        local A = C_AddOns or {}
        local loaded = (A.IsAddOnLoaded or IsAddOnLoaded or function() return false end)("ProtAlerts")
        if loaded then
            pcall(A.DisableAddOn or DisableAddOn, "ProtAlerts")
            say("|cffff5555The old ProtAlerts addon is now turned off. Type /reload once.|r")
        end
        DBagsAlertsDB = DBagsAlertsDB or {}
        DB = DBagsAlertsDB
        for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = type(v) == "table" and CopyTable(v) or v end end
        buildSpells()
        findNearSpell()
        layout()
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterUnitEvent("UNIT_AURA", "player")
        -- "something changed" events: they only set flags; the work happens once per frame
        local function reg(e, u1, u2)
            if u1 then pcall(self.RegisterUnitEvent, self, e, u1, u2) else pcall(self.RegisterEvent, self, e) end
        end
        reg("UNIT_HEALTH", "player", "target"); reg("UNIT_MAXHEALTH", "player", "target")
        reg("UNIT_POWER_FREQUENT", "player", "target"); reg("UNIT_MAXPOWER", "player", "target")
        reg("UNIT_TARGET", "target")
        for _, e in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
            reg(e, "player", "target")
        end
        reg("UNIT_THREAT_LIST_UPDATE"); reg("UNIT_THREAT_SITUATION_UPDATE")
        reg("PLAYER_TARGET_CHANGED"); reg("PLAYER_REGEN_DISABLED")
        reg("SPELL_UPDATE_COOLDOWN"); reg("SPELL_UPDATE_USABLE")
        reg("NAME_PLATE_UNIT_ADDED"); reg("NAME_PLATE_UNIT_REMOVED")
        reg("UPDATE_SHAPESHIFT_FORM"); reg("UNIT_DISPLAYPOWER", "player")
        for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do reg(e, "player", "target") end
        swing.hasEvent = pcall(self.RegisterEvent, self, "PLAYER_SWING")
        pcall(self.RegisterUnitEvent, self, "UNIT_COMBAT", "player", "target")
        pcall(self.RegisterUnitEvent, self, "UNIT_ATTACK_SPEED", "player")
        readSpeed()
        readAll()
        hideBlizzard()
        if DBagsAlertsState.cursorRefresh then DBagsAlertsState.cursorRefresh() end
        say("%s loaded. /pa for settings.",
            CLASS == "PALADIN" and (DB.tank and "Paladin (tank)" or "Paladin (damage)")
            or CLASS == "DRUID" and "Druid" or CLASS == "WARLOCK" and "Warlock" or "Warrior")
        return
    end
    alertsDirty = true                 -- every event below can change what should light up
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- fires a lot (stance swaps...): rebuild once, half a second after it settles
        spellsDirty, spellsAt = true, GetTime()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then
        DRU.refreshPower()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local unit = ...
        if unit == "target" then tDirty.hp = true else barsDirty.health = true end
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
        local unit, ptype = ...
        if unit == "target" then tDirty.pw = true
        else
            barsDirty.power = true
            if ptype == "RAGE" then onRage() end
        end
    elseif event == "UNIT_TARGET" then
        tDirty.tot = true
    elseif event == "PLAYER_TARGET_CHANGED" then
        barsDirty.threat = true
        tDirty.all = true
        -- if the game hides mob IDs, all mobs share one memory slot: wipe it for the new mob
        rendAt["?"], sunder["?"], lastDebuff = nil, nil, nil
        for _, t in pairs(DRU.dotAt) do t["?"] = nil end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        barsDirty.threat = true
        tDirty.tot = true
    elseif event:find("^UNIT_SPELLCAST_") and event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit == "player" then tDirty.castP = true elseif unit == "target" then tDirty.castT = true end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        onCast(spellID)
    elseif event == "PLAYER_SWING" then
        onSwing(...)
    elseif event == "UNIT_COMBAT" then
        local unit, action = ...
        if unit == "target" then onTargetCombat(action) else onUnitCombat(...) end
    elseif event == "UNIT_ATTACK_SPEED" then
        onAttackSpeed()
    elseif event == "UNIT_AURA" then
        auraDirty = true          -- read once on the next tick, not on every aura event
    elseif event == "PLAYER_REGEN_ENABLED" then
        readAll()
        if event == "PLAYER_REGEN_ENABLED" then readSpeed() end
    end
end)

end   -- events block

-- (settings + macro code lives in its own block: Lua allows only 200 top-level locals)
local makeMacros, toggleSettings
do
---------------------------------------------------------------------------
-- Settings window (/pa). Plain words, big boxes, no commands to remember.
---------------------------------------------------------------------------
-- What each alert means, in plain words (shown in the settings window).
local PLAIN = {
    lowhp = { "Low health", "Shows your best defensive cooldown." },
    taunt = { "Taunt", "Your target isn't attacking you." },
    kick = { "Interrupt", "Your target is casting." },
    loose = { "Loose mobs", "Mobs attacking your group." },
    block = { "Shield Block", "Less damage, more rage." },
    revenge = { "Revenge", "Ready after a block, dodge or parry." },
    slam = { "Shield Slam", "Off cooldown." },
    vrush = { "Victory Rush", "Heal after a kill." },
    clap = { "Thunder Clap", "Packs and elites." },
    demo = { "Demo Shout", "Mobs deal less damage." },
    execute = { "Execute", "Target under 20%." },
    dump = { "Spend rage", "Heroic Strike or Cleave. Waits longer during heavy hits." },
    sunder = { "Sunder Armor", "Stack to your Sunder setting." },
    rend = { "Rend", "Start of a fight." },
    shout = { "Battle Shout", "Buff missing." },
    bloodrage = { "Bloodrage", "Low rage or before a pull." },
    rfury = { "Righteous Fury", "Tank threat buff missing." },
    seal = { "Seal", "No seal active." },
    holyshield = { "Holy Shield", "Not active." },
    swift = { "Swift Judgement", "Off cooldown." },
    judge = { "Judgement", "Off cooldown, seal active." },
    consecrate = { "Consecration", "Packs and elites." },
    holystrike = { "Holy Strike", "Off cooldown." },
    exorcism = { "Exorcism", "Undead and demons." },
    wrath = { "Hammer of Wrath", "Target under 20%." },
    lowmana = { "Low mana", "Under your Low mana setting." },
    bless = { "Blessing", "Blessing missing." },
    aura = { "Aura", "No aura active." },
    -- warlock
    fear = { "Fear", "Solo, 2+ mobs, health low." },
    trance = { "Free Shadow Bolt", "Nightfall proc." },
    drainlife = { "Drain Life", "Health under half." },
    drainsoul = { "Drain Soul", "Dying mob, shards low." },
    sburn = { "Shadowburn", "Finish a mob." },
    conflag = { "Conflagrate", "Immolate is on." },
    brand = { "Searing Pain", "Brand your pet's target." },
    corrupt = { "Corruption", "Missing on target." },
    bane = { "Bane of Agony", "Missing. Never early." },
    immolate = { "Immolate", "Missing on target." },
    siphon = { "Siphon Life", "Long fights." },
    filler = { "Filler", "Shadow Bolt, wand or Incinerate." },
    armor = { "Demon Armor", "Buff missing." },
    pet = { "Summon pet", "No pet out." },
    soullink = { "Soul Link", "Not active." },
    curse = { "Curse", "Elites only." },
    mkstone = { "Make Healthstone", "None in bags." },
    lifetap = { "Life Tap", "Mana low, health fine." },
    funnel = { "Health Funnel", "Pet health low." },
    rof = { "Rain of Fire", "Group, 3+ mobs." },
}

---------------------------------------------------------------------------
-- Macro maker. WoW keeps macros inside the game (and on Blizzard's servers), so
-- editing the file on disk gets overwritten. The addon makes them in game instead,
-- using Blizzard's own CreateMacro. Normal macros: one press = one thing.
---------------------------------------------------------------------------
local Q = 134400   -- question-mark icon: with #showtooltip WoW shows the real spell icon
-- Every attack macro starts auto-attack. Defensive-only moves swap you back to
-- Defensive Stance first (press once = stance, again = the move), so they also
-- work after a stance dance. Shield Block rides along on Slam/Revenge - it is off
-- the global cooldown (Icy Veins' own "Shield Slam with Shield Block" macro idea).
local WARRIOR_MACROS = {
    -- rotation
    { "PA Slam", "#showtooltip Shield Slam\n/startattack\n/cast Shield Block\n/cast Shield Slam",
      "Shield Slam + Shield Block + auto-attack." },
    { "PA Revenge", "#showtooltip Revenge\n/startattack\n/cast [nostance:2] Defensive Stance; Shield Block\n/cast [stance:2] Revenge",
      "Revenge + Shield Block + auto-attack." },
    { "PA Clap", "#showtooltip Thunder Clap\n/startattack\n/cast Thunder Clap",
      "Thunder Clap + auto-attack." },
    { "PA Sunder", "#showtooltip Sunder Armor\n/startattack\n/cast Sunder Armor",
      "Sunder + auto-attack." },
    { "PA Rend", "#showtooltip Rend\n/startattack\n/cast Rend",
      "Rend + auto-attack." },
    { "PA Strike", "#showtooltip\n/startattack\n/cast [mod:shift] Cleave; Heroic Strike",
      "Heroic Strike. Shift: Cleave." },
    { "PA VRush", "#showtooltip Victory Rush\n/startattack\n/cast Victory Rush",
      "Victory Rush + auto-attack." },
    { "PA Bloodrage", "#showtooltip Bloodrage\n/startattack\n/cast Bloodrage",
      "Bloodrage (free rage) + auto-attack." },
    { "PA Block", "#showtooltip Shield Block\n/startattack\n/cast [nostance:2] Defensive Stance; Shield Block",
      "Shield Block (goes Defensive first if needed)." },
    -- threat / control
    { "PA Taunt", "#showtooltip Taunt\n/startattack\n/cast [nostance:2] Defensive Stance; [@mouseover,harm,nodead][] Taunt",
      "Mouseover taunt (goes Defensive first if needed)." },
    { "PA Interrupt", "#showtooltip\n/startattack\n/cast [@mouseover,harm,nodead,stance:3][stance:3] Pummel; [@mouseover,harm,nodead][] Shield Bash",
      "Mouseover Shield Bash / Pummel." },
    { "PA Charge", function()
          -- Vanguard (talent, 25+): Charge works in Defensive, so don't leave it
          local okI, info = pcall(C_Spell.GetSpellInfo, "Vanguard")
          local vid = okI and type(info) == "table" and not sectable(info) and plain(info.spellID, nil)
          local known = vid and IsPlayerSpell and plain(IsPlayerSpell(vid), false)
          if known then return "#showtooltip Charge\n/startattack\n/cast Charge" end
          return "#showtooltip Charge\n/startattack\n/cast [nostance:1] Battle Stance; Charge"
      end,
      "Charge. Before Vanguard (25): 1st press Battle, 2nd Charge. Run /pa macros again after 25." },
    { "PA Pull", "#showtooltip\n/cast [equipped:Bows] Shoot Bow; [equipped:Guns] Shoot Gun; [equipped:Crossbows] Shoot Crossbow; Throw",
      "Ranged pull." },
    -- stance dancing in combat
    { "PA Overpower", "#showtooltip Overpower\n/startattack\n/cast [nostance:1] Battle Stance; Overpower",
      "Battle Stance, then Overpower." },
    { "PA Mocking", "#showtooltip Mocking Blow\n/startattack\n/cast [nostance:1] Battle Stance; Mocking Blow",
      "Battle Stance, then Mocking Blow." },
    { "PA Intercept", "#showtooltip Intercept\n/startattack\n/cast [nostance:3] Berserker Stance; Intercept",
      "Berserker Stance, then Intercept." },
    { "PA Fear Break", "#showtooltip Berserker Rage\n/cast [nostance:3] Berserker Stance; Berserker Rage",
      "Berserker Stance, then Berserker Rage." },
    { "PA Wall", "#showtooltip Shield Wall\n/cast [nostance:2] Defensive Stance; Shield Wall",
      "Shield Wall (goes Defensive first if needed)." },
    { "PA Stance", "#showtooltip\n/cast [stance:2] Battle Stance; Defensive Stance",
      "Swap stance: Defensive <-> Battle. Icon shows where it goes.", "PA Defensive" },
}

-- Paladin: no stances. Attacks start auto-attack; help spells work on the friend
-- under your mouse (or you). Different names so they never clash with warrior ones.
local PALADIN_MACROS = {
    { "PP Judge", "#showtooltip Judgement\n/startattack\n/cast Judgement",
      "Judgement + auto-attack (taunts with Seal of Fury)." },
    { "PP Taunt", "#showtooltip Judgement\n/startattack\n/cast [@mouseover,harm,nodead][] Judgement",
      "Mouseover Judgement taunt." },
    { "PP Snap", "#showtooltip Swift Judgement\n/startattack\n/cast [@mouseover,harm,nodead][] Swift Judgement\n/cast [@mouseover,harm,nodead][] Judgement",
      "Emergency taunt: Swift Judgement + Judgement." },
    { "PP Strike", "#showtooltip Holy Strike\n/startattack\n/cast Holy Strike",
      "Holy Strike + auto-attack." },
    { "PP Consecrate", "#showtooltip Consecration\n/startattack\n/cast Consecration",
      "Consecration + auto-attack." },
    { "PP Shield", "#showtooltip Holy Shield\n/startattack\n/cast Holy Shield",
      "Holy Shield + auto-attack." },
    { "PP Exorcism", "#showtooltip Exorcism\n/startattack\n/cast Exorcism",
      "Exorcism + auto-attack." },
    { "PP Stun", "#showtooltip Hammer of Justice\n/startattack\n/cast [@mouseover,harm,nodead][] Hammer of Justice",
      "Mouseover Hammer of Justice (stops casts)." },
    { "PP LoH", "#showtooltip Lay on Hands\n/cast [@mouseover,help,nodead][@player] Lay on Hands",
      "Lay on Hands on mouseover friend, or you." },
    { "PP BoP", "#showtooltip Blessing of Protection\n/cast [@mouseover,help,nodead][] Blessing of Protection",
      "Blessing of Protection on mouseover friend." },
    { "PP Freedom", "#showtooltip Blessing of Freedom\n/cast [@mouseover,help,nodead][@player] Blessing of Freedom",
      "Blessing of Freedom on mouseover friend, or you." },
}
-- Druid: forms never cancel by accident (!), attacks start auto-attack, heals and buffs
-- work on the friend under your mouse (or you).
local CLASS_MACROS = { WARRIOR = WARRIOR_MACROS, PALADIN = PALADIN_MACROS, DRUID = {
    { "PD Bear", function()
          local f = spell["Dire Bear Form"] and "Dire Bear Form" or "Bear Form"
          return "#showtooltip " .. f .. "\n/cast !" .. f
      end, "Bear Form. Pressing it again never drops you out." },
    { "PD Cat", "#showtooltip Cat Form\n/cast !Cat Form", "Cat Form. Pressing it again never drops you out." },
    { "PD Maul", "#showtooltip Maul\n/startattack\n/cast Maul", "Maul + auto-attack." },
    { "PD Swipe", "#showtooltip Swipe\n/startattack\n/cast Swipe", "Swipe + auto-attack." },
    { "PD Growl", "#showtooltip Growl\n/startattack\n/cast [@mouseover,harm,nodead][] Growl", "Mouseover taunt." },
    { "PD Bash", "#showtooltip Bash\n/startattack\n/cast [@mouseover,harm,nodead][] Bash", "Mouseover Bash (stops casts)." },
    { "PD Claw", "#showtooltip Claw\n/startattack\n/cast Claw", "Claw + auto-attack." },
    { "PD Rake", "#showtooltip Rake\n/startattack\n/cast Rake", "Rake + auto-attack." },
    { "PD Rip", "#showtooltip Rip\n/startattack\n/cast Rip", "Rip + auto-attack." },
    { "PD Prowl", "#showtooltip Prowl\n/cast [nostealth] Prowl", "Prowl. Pressing it again never drops stealth." },
    { "PD Opener", function()
          if spell["Ravage"] then return "#showtooltip\n/startattack\n/cast [stealth] Ravage; Shred" end
          return "#showtooltip Shred\n/startattack\n/cast Shred"
      end, "From Prowl: Ravage (Shred before you have it)." },
    { "PD Rejuv", "#showtooltip Rejuvenation\n/cast [@mouseover,help,nodead][@player] Rejuvenation", "Rejuvenation on mouseover friend, or you." },
    { "PD Regrowth", "#showtooltip Regrowth\n/cast [@mouseover,help,nodead][@player] Regrowth", "Regrowth on mouseover friend, or you." },
    { "PD Swiftmend", "#showtooltip Swiftmend\n/cast [@mouseover,help,nodead][@player] Swiftmend", "Swiftmend on mouseover friend, or you." },
    { "PD Mark", "#showtooltip Mark of the Wild\n/cast [@mouseover,help,nodead][@player] Mark of the Wild", "Mark of the Wild on mouseover friend, or you." },
    { "PD Thorns", "#showtooltip Thorns\n/cast [@mouseover,help,nodead][@player] Thorns", "Thorns on mouseover friend (tank), or you." },
    { "PD Innervate", "#showtooltip Innervate\n/cast [@mouseover,help,nodead][@player] Innervate", "Innervate on mouseover healer, or you." },
},
-- Warlock: main nukes send your pet in too; DoTs, curses and Fear work on the mob
-- under your mouse (spread DoTs without changing target).
WARLOCK = {
    { "PK Bolt", "#showtooltip Shadow Bolt\n/petattack\n/cast Shadow Bolt", "Shadow Bolt + pet attacks." },
    { "PK Immolate", "#showtooltip Immolate\n/petattack\n/cast Immolate", "Immolate + pet attacks." },
    { "PK Searing", "#showtooltip Searing Pain\n/petattack\n/cast Searing Pain", "Searing Pain + pet attacks." },
    { "PK Conflag", "#showtooltip Conflagrate\n/petattack\n/cast Conflagrate", "Conflagrate + pet attacks." },
    { "PK Corruption", "#showtooltip Corruption\n/cast [@mouseover,harm,nodead][] Corruption", "Mouseover Corruption." },
    { "PK Agony", function()
          local n = spell["Bane of Agony"] and "Bane of Agony" or "Curse of Agony"
          return "#showtooltip " .. n .. "\n/cast [@mouseover,harm,nodead][] " .. n
      end, "Mouseover Bane of Agony." },
    { "PK Siphon", "#showtooltip Siphon Life\n/cast [@mouseover,harm,nodead][] Siphon Life", "Mouseover Siphon Life." },
    { "PK Curse", function()
          local n = spell["Curse of the Elements"] and "Curse of the Elements" or "Curse of Weakness"
          return "#showtooltip " .. n .. "\n/cast [@mouseover,harm,nodead][] " .. n
      end, "Mouseover Curse of the Elements (Weakness before you have it)." },
    { "PK Fear", "#showtooltip Fear\n/cast [@mouseover,harm,nodead][] Fear", "Mouseover Fear." },
    { "PK Drain Life", "#showtooltip Drain Life\n/cast Drain Life", "Drain Life." },
    { "PK Drain Soul", "#showtooltip Drain Soul\n/cast Drain Soul", "Drain Soul (shards)." },
    { "PK Life Tap", "#showtooltip Life Tap\n/cast Life Tap", "Life Tap." },
    { "PK Healthstone", "#showtooltip\n/use Major Healthstone\n/use Greater Healthstone\n/use Healthstone\n"
          .. "/use Lesser Healthstone\n/use Minor Healthstone", "Eat your Healthstone (any size)." },
    { "PK Make Stone", "#showtooltip Create Healthstone\n/cast Create Healthstone", "Make a Healthstone." },
    { "PK Funnel", "#showtooltip Health Funnel\n/cast Health Funnel", "Heal your pet." },
    { "PK Wand", "#showtooltip Shoot\n/cast !Shoot", "Wand. Pressing it again never stops it." },
    { "PK Pet", "#showtooltip\n/petattack [@mouseover,harm,nodead][]", "Pet attacks mouseover mob, or your target." },
    { "PK Pet Back", "/petfollow", "Pet comes back to you." },
} }

makeMacros = function()
    local list = CLASS_MACROS[CLASS]
    if not list then say("no macros for this class.") return end
    if InCombatLockdown() then say("can't create macros in combat.") return end
    if not (CreateMacro and EditMacro and GetMacroIndexByName) then say("macros unavailable.") return end
    local made, updated, failed = 0, 0, 0
    for _, m in ipairs(list) do
        local name, body = m[1], m[2]
        if type(body) == "function" then body = body() end   -- some macros depend on talents
        local idx = GetMacroIndexByName(name)
        -- renamed macro: rewrite the old one in place so it stays on your action bar
        if (not idx or idx == 0) and m[4] then idx = GetMacroIndexByName(m[4]) end
        local ok
        if idx and idx > 0 then
            ok = pcall(EditMacro, idx, name, Q, body)
            if ok then updated = updated + 1 end
        else
            local okC, newIdx = pcall(CreateMacro, name, Q, body, true)   -- true = this character only
            ok = okC and newIdx and newIdx > 0
            if not ok then   -- character slots full: use the shared (all characters) tab instead
                okC, newIdx = pcall(CreateMacro, name, Q, body, false)
                ok = okC and newIdx and newIdx > 0
            end
            if ok then made = made + 1 end
        end
        if not ok then failed = failed + 1 end
    end
    say("macros: %d new, %d updated%s.", made, updated, failed > 0 and (", " .. failed .. " failed (slots full?)") or "")
    say("Open /macro, character tab.")
    for _, m in ipairs(list) do say("  |cffffd100%s|r - %s", m[1], m[3]) end
end

local settings
local function C(r, g, b) return r, g, b end

local function makeCheck(parent, label, tip, get, set)
    local b = CreateFrame("CheckButton", nil, parent)
    b:SetSize(22, 22)
    b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.text = b:CreateFontString(nil, "OVERLAY")
    styleText(b.text, 13, C(0.95, 0.95, 0.95))
    b.text:SetPoint("LEFT", b, "RIGHT", 2, 0)
    b.text:SetText(label)
    b:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0.2)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    b.refresh = function() b:SetChecked(get() and true or false) end
    return b
end

local function makeSlider(parent, label, minV, maxV, step, fmt, get, set)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(190, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.2, 0.2, 0.24, 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s.title = s:CreateFontString(nil, "OVERLAY")
    styleText(s.title, 13, C(1, 0.82, 0.2))
    s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
    s.title:SetText(label)
    s.val = s:CreateFontString(nil, "OVERLAY")
    styleText(s.val, 14, C(1, 1, 1))
    s.val:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        if self.busy then return end
        set(v)
        self.val:SetText(string.format(fmt, v))
    end)
    s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * step) end)
    s.refresh = function()
        s.busy = true; s:SetValue(get()); s.busy = false
        s.val:SetText(string.format(fmt, get()))
    end
    return s
end

local function makeButton(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 24)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0.18, 0.18, 0.22, 1)
    addBorder(b, 0, 0, 0, 1, 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 0.82, 0.2, 0.15)
    b.text = b:CreateFontString(nil, "OVERLAY")
    styleText(b.text, 13, C(1, 0.9, 0.5)); b.text:SetPoint("CENTER"); b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function heading(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    styleText(fs, 15, C(1, 0.82, 0.2))
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0.2, 0.25)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3); line:SetSize(328, 1)
    return fs
end

local function buildSettings()
    local w = CreateFrame("Frame", "DBagsAlertsSettings", UIParent)
    w:SetSize(360, 662)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetMovable(true); w:EnableMouse(true); w:SetClampedToScreen(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w.bg = w:CreateTexture(nil, "BACKGROUND")
    w.bg:SetAllPoints(); w.bg:SetColorTexture(0.06, 0.06, 0.08, 0.96)
    addBorder(w, 0, 0, 0, 1, 1)
    local accent = w:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(3)
    local cc = CLASS and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(CLASS))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS]))
    if cc then accent:SetColorTexture(cc.r, cc.g, cc.b, 1) else accent:SetColorTexture(1, 0.82, 0.2, 1) end
    if UISpecialFrames then table.insert(UISpecialFrames, "DBagsAlertsSettings") end  -- Esc closes it

    local title = w:CreateFontString(nil, "OVERLAY")
    styleText(title, 18, C(1, 1, 1)); title:SetPoint("TOP", 0, -12)
    title:SetText("DBagsAlerts")
    local sub = w:CreateFontString(nil, "OVERLAY")
    styleText(sub, 10, C(0.7, 0.7, 0.75)); sub:SetPoint("TOP", title, "BOTTOM", 0, -3)
    sub:SetText("")
    local close = makeButton(w, "X", 24, function() w:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local items = {}
    local function add(x) table.insert(items, x) return x end

    -- LOOK
    heading(w, "Display", -52)
    local size = add(makeSlider(w, "Size", 0.6, 2.0, 0.05, "%.2fx", function() return DB.scale end,
        function(v) DB.scale = v; main:SetScale(v) end))
    size:SetPoint("TOPLEFT", 20, -92)
    local lock = add(makeCheck(w, "Lock position", "Uncheck to drag. Mouse wheel resizes.",
        function() return DB.locked end, function(v) DB.locked = v; layout() end))
    lock:SetPoint("TOPLEFT", 16, -114)
    local function relayout() layout() end
    local big = add(makeCheck(w, "Big icon", "One icon: the next button to press.",
        function() return DB.stack ~= false end, function(v) DB.stack = v; relayout() end))
    big:SetPoint("TOPLEFT", 16, -136)
    local nm = add(makeCheck(w, "Spell names", "Name under the big icon.",
        function() return DB.names end, function(v) DB.names = v; relayout() end))
    nm:SetPoint("TOPLEFT", 180, -136)
    local rg = add(makeCheck(w, "Aggro dot", "Dot over every mob in a fight. Green: it's on you. Yellow: about to lose it. Red: it's not hitting you.",
        function() return DB.range end, function(v) DB.range = v; relayout() end))
    rg:SetPoint("TOPLEFT", 16, -158)
    local tip = add(makeCheck(w, "Rage tips", "Short tip line under the rage bar.",
        function() return DB.advice end, function(v) DB.advice = v; relayout() end))
    tip:SetPoint("TOPLEFT", 180, -158)
    local tfc = add(makeCheck(w, "Target frame", "Target name, health, and who it's hitting.",
        function() return DB.target end, function(v) DB.target = v; relayout() end))
    tfc:SetPoint("TOPLEFT", 16, -180)
    local cbc = add(makeCheck(w, "Cast bars", "Your cast bar and your target's. White line on yours: from there you can start your next spell (bar turns green).",
        function() return DB.casts end, function(v) DB.casts = v; relayout() end))
    cbc:SetPoint("TOPLEFT", 180, -180)
    local hb = add(makeCheck(w, "Hide Blizzard frames", "Hides the normal player, target and cast frames. Uncheck + /reload to get them back.",
        function() return DB.hideBlizz end, function(v) DB.hideBlizz = v; if v then hideBlizzard() else say("type /reload to bring them back.") end end))
    hb:SetPoint("TOPLEFT", 16, -202)
    local cs = add(makeCheck(w, "Classic WoW frames", "Gold WoW frames and glossy bars. Uncheck for plain thin lines.",
        function() return DB.style ~= "clean" end, function(v) DB.style = v and "classic" or "clean"; relayout() end))
    cs:SetPoint("TOPLEFT", 180, -202)
    local cur = add(makeCheck(w, "Cursor ring", "A ring around your mouse so you never lose it.",
        function() return DB.cursor ~= false end, function(v) DB.cursor = v end))
    cur:SetPoint("TOPLEFT", 16, -224)
    local curc = add(makeCheck(w, "Ring only in combat", "Show the cursor ring only while you fight.",
        function() return DB.cursorCombat end, function(v) DB.cursorCombat = v end))
    curc:SetPoint("TOPLEFT", 180, -224)
    local nag = add(makeCheck(w, "Buff reminder", "Shows your missing buff (Battle Shout) next to the icons, even out of combat. Hidden in towns.",
        function() return DB.buffNag ~= false end, function(v) DB.buffNag = v end))
    nag:SetPoint("TOPLEFT", 16, -246)
    local snag = add(makeCheck(w, "Stance reminder", "Flashes DEFENSIVE above your character when you fight in another stance (warrior).",
        function() return DB.stanceNag ~= false end, function(v) DB.stanceNag = v end))
    snag:SetPoint("TOPLEFT", 180, -246)
    local fnag = add(makeCheck(w, "Eat reminder", "Shows an EAT button when you have no Well Fed (+5% XP) but carry food that gives it. Click it to eat.",
        function() return DB.foodNag ~= false end, function(v) DB.foodNag = v end))
    fnag:SetPoint("TOPLEFT", 16, -268)
    local stn = add(makeCheck(w, "Weapon stone", "Button to put a sharpening stone or weightstone on your weapon when it has none.",
        function() return DB.stoneNag ~= false end, function(v) DB.stoneNag = v end))
    stn:SetPoint("TOPLEFT", 180, -268)
    local stn2 = add(makeCheck(w, "Show if I have none", "Grey NO STONE icon when your bags have no stone for your weapon.",
        function() return DB.stoneNeed ~= false end, function(v) DB.stoneNeed = v end))
    stn2:SetPoint("TOPLEFT", 16, -290)
    local test = makeButton(w, "Preview", 200, function() testUntil = GetTime() + 8 end)
    test:SetPoint("TOPLEFT", 20, -320)
    if CLASS_MACROS[CLASS] then
        local mk = makeButton(w, "Create macros", 200, makeMacros)
        mk:SetPoint("TOPLEFT", 20, -348)
        mk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Create macros", 1, 0.82, 0.2)
            GameTooltip:AddLine("Adds " .. #CLASS_MACROS[CLASS] .. " character macros. Find them in /macro. Running it again updates them." ..
                "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        mk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- WARNINGS
    heading(w, "Thresholds", -384)
    local y = -424
    local hp = add(makeSlider(w, "Low health", 10, 80, 5, "%d%%", function() return DB.lowHp end,
        function(v) DB.lowHp = v end))
    hp:SetPoint("TOPLEFT", 20, y)
    y = y - 40
    if CLASS == "WARRIOR" then
        local dump = add(makeSlider(w, "Spend rage at", 30, 100, 5, "%d rage", function() return DB.dumpAt end,
            function(v) DB.dumpAt = v; layout() end))
        dump:SetPoint("TOPLEFT", 20, y)
        y = y - 40
        local dumpT = add(makeSlider(w, "Spend rage at (heavy hits)", 50, 100, 5, "%d rage",
            function() return DB.dumpTank or 90 end, function(v) DB.dumpTank = v end))
        dumpT:SetPoint("TOPLEFT", 20, y)
        y = y - 40
        local sun = add(makeSlider(w, "Sunder stacks (normal mobs)", 0, 5, 1, "%d", function() return DB.sunderGoal end,
            function(v) DB.sunderGoal = v end))
        sun:SetPoint("TOPLEFT", 20, y)
        y = y - 30
    else
        local mana = add(makeSlider(w, "Low mana", 5, 60, 5, "%d%%", function() return DB.lowMana end,
            function(v) DB.lowMana = v; layout() end))
        mana:SetPoint("TOPLEFT", 20, y)
        y = y - 30
        if CLASS == "WARLOCK" then
            y = y - 10
            local sh = add(makeSlider(w, "Soul Shards to keep", 1, 20, 1, "%d", function() return DB.shardGoal or 5 end,
                function(v) DB.shardGoal = v end))
            sh:SetPoint("TOPLEFT", 20, y)
            y = y - 30
        else
            local tank = add(makeCheck(w, "Tank mode",
                "On: Righteous Fury, Seal of Fury, Sanctuary. Off: Righteousness, Might.",
                function() return DB.tank end, function(v) DB.tank = v end))
            tank:SetPoint("TOPLEFT", 16, y)
            y = y - 26
        end
    end
    local snd = add(makeCheck(w, "Sound on danger alerts", "Raid warning sound.",
        function() return DB.sound end, function(v) DB.sound = v end))
    snd:SetPoint("TOPLEFT", 16, y)
    y = y - 44
    local crs = add(makeSlider(w, "Cursor ring size", 24, 120, 4, "%d", function() return DB.cursorSize or 48 end,
        function(v) DB.cursorSize = v; if DBagsAlertsState.cursorRefresh then DBagsAlertsState.cursorRefresh() end end))
    crs:SetPoint("TOPLEFT", 20, y)
    y = y - 34

    -- WHICH ALERTS
    heading(w, "Alerts", y)
    y = y - 24
    local col = 0
    local list = {}
    for _, a in ipairs(ALERTS) do table.insert(list, a.key) end
    table.insert(list, "cooldowns"); table.insert(list, "swing")
    PLAIN.cooldowns = { "Cooldowns", "Cooldown row under the bars." }
    PLAIN.swing = { "Swing timer", "Auto-attack timer." }
    for _, key in ipairs(list) do
        local p = PLAIN[key] or { key, "" }
        local cb = add(makeCheck(w, p[1], p[2], function() return not DB.off[key] end,
            function(v) DB.off[key] = (not v) or nil; layout() end))
        cb:SetPoint("TOPLEFT", 16 + col * 168, y)
        col = col + 1
        if col == 2 then col = 0; y = y - 22 end
    end
    if col == 1 then y = y - 22 end
    w:SetHeight(-y + 16)

    w.refresh = function() for _, it in ipairs(items) do it.refresh() end end
    return w
end

toggleSettings = function()
    if not settings then settings = buildSettings() end
    if settings:IsShown() and settings.opened then settings:Hide() return end
    settings.opened = true
    settings.refresh()
    settings:Show()
end

end   -- settings + macro block

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function desc(v)
    if secret(v) then return "|cffff5555SECRET|r" end
    if sectable(v) then return "|cffff5555SECRET TABLE|r" end
    return tostring(v)
end

SLASH_DBAGSALERTS1 = "/pa"
SLASH_DBAGSALERTS2 = "/dba"
SlashCmdList.DBAGSALERTS = function(msg)
    if not DB then say("warriors and paladins only.") return end
    local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "settings" or cmd == "options" then
        toggleSettings()
    elseif cmd == "unlock" or cmd == "lock" then
        DB.locked = cmd == "lock"; layout()
        say(DB.locked and "locked." or "unlocked. Drag to move, scroll to resize.")
    elseif cmd == "macros" or cmd == "macro" then
        makeMacros()
    elseif cmd == "test" then
        testUntil = GetTime() + 8; say("preview on.")
    elseif cmd == "scale" and tonumber(rest) then
        DB.scale = math.max(0.5, math.min(2, tonumber(rest))); layout()
    elseif cmd == "toggle" and rest ~= "" then
        local found = rest == "cooldowns" or rest == "swing"
        for _, a in ipairs(ALERTS) do if a.key == rest then found = a end end
        if not found then say("no alert named %s. /pa list", rest) return end
        DB.off[rest] = not DB.off[rest] or nil; layout()
        say("%s is now %s.", rest, DB.off[rest] and "OFF" or "ON")
    elseif cmd == "list" then
        for _, a in ipairs(ALERTS) do say("  %s (%s) - %s", a.key, a.label, DB.off[a.key] and "OFF" or "on") end
        say("  cooldowns (cooldown row) - %s", DB.off.cooldowns and "OFF" or "on")
        say("  swing (swing timer bar) - %s", DB.off.swing and "OFF" or "on")
    elseif cmd == "sunder" and tonumber(rest) then
        DB.sunderGoal = math.max(0, math.min(5, tonumber(rest))); say("Sunder goal on normal mobs: %d", DB.sunderGoal)
    elseif cmd == "tank" then
        DB.tank = not DB.tank
        say("tank mode %s.", DB.tank and "on" or "off")
    elseif cmd == "mana" and tonumber(rest) then
        DB.lowMana = math.max(5, math.min(90, tonumber(rest))); say("LOW MANA alert below %d%%.", DB.lowMana)
    elseif cmd == "dump" and tonumber(rest) then
        DB.dumpAt = math.max(20, math.min(100, tonumber(rest))); say("Rage dump alert at %d%%.", DB.dumpAt)
    elseif cmd == "hp" and tonumber(rest) then
        DB.lowHp = math.max(5, math.min(90, tonumber(rest))); say("LOW HP alert below %d%%.", DB.lowHp)
    elseif cmd == "sound" then
        DB.sound = not DB.sound; say("danger sound %s.", DB.sound and "ON" or "OFF")
    elseif cmd == "reset" then
        DBagsAlertsDB = nil; ReloadUI()
    elseif cmd == "food" then
        if DBagsAlertsState.foodUpdate then pcall(DBagsAlertsState.foodUpdate) end
        local d = DB.foodDebug
        if d then say("eat button: %s %s", tostring(d.why), tostring(d.extra or ""))
        else say("eat button: not checked yet (try out of combat).") end
    elseif cmd == "range" then
        local d = DB.rangeDebug
        if d then say("range %s: bar=%s book=%s 10yd=%s", tostring(d.spell), d.bar, d.book, d.close)
        else say("range: target an enemy first.") end
    elseif cmd == "debug" then
        -- Run this once out of combat and once IN combat; it shows what Forever lets addons read.
        say("combat=%s  enemies=%s  loose=%s", tostring(InCombatLockdown()), tostring(ctx.enemies), tostring(ctx.loose))
        say("%s UnitPower=%s max=%s", POWER == MANA and "mana" or "rage", desc(UnitPower("player", POWER)), desc(UnitPowerMax("player", POWER)))
        say("health=%s  target health=%s", desc(UnitHealth("player")), desc(UnitHealth("target")))
        local id = spell["Revenge"] or spell["Heroic Strike"]
        if id then
            local c = C_Spell.GetSpellCooldown(id)
            if type(c) == "table" and not sectable(c) then
                say("cooldown isActive=%s isOnGCD=%s duration=%s", desc(c.isActive), desc(c.isOnGCD), desc(c.duration))
            end
            local u = C_Spell.IsSpellUsable(id)
            say("IsSpellUsable=%s", desc(u))
        end
        local t = UnitDetailedThreatSituation("player", "target")
        say("threat isTanking=%s  target casting=%s", desc(t), desc(UnitCastingInfo("target")))
        say("curve helpers: power=%s health=%s bool=%s", tostring(UnitPowerPercent ~= nil),
            tostring(UnitHealthPercent ~= nil), tostring(C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean ~= nil))
        local okS, mh = pcall(UnitAttackSpeed, "player")
        say("swing: PLAYER_SWING event=%s  weapon speed=%s  last swing=%.1fs", tostring(swing.hasEvent),
            okS and desc(mh) or "error", swing.dur)
        local n = 0 for _ in pairs(spell) do n = n + 1 end
        say("%d spells known. Shield Block lasts %ss, Battle Shout %ss.", n, durationOf("Shield Block"), durationOf("Battle Shout"))
    else
        say("commands:")
        say("  /pa unlock | lock  - move it")
        say("  /pa test           - show all alerts for 8s")
        say("  /pa scale 1.2      - size")
        say("  /pa list | toggle <name> - turn alerts on/off")
        say("  /pa sunder 2 | dump 70 | hp 35 - tune thresholds (warrior)")
        say("  /pa tank | mana 20 - paladin: tank or damage setup, low mana %%")
        say("  /pa sound          - sound on danger alerts")
        say("  /pa debug          - what the game lets addons read (try in combat)")
    end
end
