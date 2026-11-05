-- ProtAlerts: Protection Warrior alerts for WoW Forever.
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
local POWER = RAGE        -- set at login: rage for warriors, mana for paladins
local CLASS               -- "WARRIOR" or "PALADIN"
local ALERTS, CD_SPELLS   -- picked at login from the class tables below
local spendLine           -- function, defined with the advice code below
local tankingHard         -- function, defined with the advice code below
local DB
local function say(fmt, ...) print("|cffc79c6eProtAlerts|r: " .. string.format(fmt, ...)) end

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
    range = true,        -- melee range ring around the big icon
    lowMana = 20,        -- paladin: mana % for the LOW MANA warning
    dumpTank = 90,       -- warrior: spend line while you are getting hit a lot
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
local PERMANENT = { AURA = true }       -- auras last until changed
-- Which groups to re-read from real aura data whenever it is readable.
local READ = {
    WARRIOR = { "Battle Shout", "Shield Block" },
    PALADIN = { "Righteous Fury", "SEAL", "BLESSING", "AURA", "Holy Shield" },
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
ProtAlertsState = { ctx = ctx }   -- read-only peek for /pa debug and testing

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
          local worth = (ctx.enemies or 0) >= 2 or ctx.elite
          need(st, ctx.combat and worth and timeLeft("Demoralizing Shout") <= durationOf("Demoralizing Shout") * 0.3)   -- pandemic: refresh at 30% left
          need(st, usable("Demoralizing Shout"))
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

local CLASS_ALERTS = { WARRIOR = WARRIOR_ALERTS, PALADIN = PALADIN_ALERTS }

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
}
local SPOT_SIZE = { danger = 64, next = 64, buff = 44, extra = 64 }   -- big, easy to see

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local main = CreateFrame("Frame", "ProtAlertsFrame", UIParent)
main:SetSize(10, 10)
main:SetMovable(true)
main:SetClampedToScreen(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB.point = { p, rp, x, y }
    if ProtAlertsState.placeClickers then ProtAlertsState.placeClickers() end
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
local MEDIA = "Interface\\AddOns\\ProtAlerts\\Media\\"
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
    local show = (not DB.off.swing and (left > 0 or (ctx.combat and ctx.hostile))) and true or false
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
}
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
    -- Important buttons: one centered row right under health + rage (only ones you know)
    for _, f in pairs(cdIcons) do f:Hide() end
    local known = {}
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
    y = y + gb + 10 + gb + 10 + (classic() and 8 or 3)
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
    if ProtAlertsState.placeClickers then ProtAlertsState.placeClickers() end   -- right-click menus follow
end

local function setIcon(a, name, label)
    name = name or a.icon
    if a.iconName ~= name then
        a.iconName = name
        local id = spell[name]
        local tex = id and C_Spell.GetSpellTexture(id)
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
    pcall(rageBar.text.SetFormattedText, rageBar.text, "%d", UnitPower("player", POWER))
    colorRage()
    updateAdvice()
end

local function updateThreat()
    -- Threat on your target. Always shown so the panel never jumps; dim without a target.
    threatBar:SetAlpha(ctx.hostile and 1 or 0)        -- no enemy target: nothing to show
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
-- Range dot above your target's head: pinned on top of its nameplate (turn enemy
-- nameplates on with V). Uses WoW's own round status dots.
-- Green = in melee, orange = one step out, red = out of range.
local dot = CreateFrame("Frame", nil, UIParent)
dot:SetSize(24, 24)
dot:SetFrameStrata("HIGH")
dot:Hide()
local function dotTex(path, r, g, b)
    local t = dot:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(); t:SetTexture(path); t:SetAlpha(0)
    if r then t:SetVertexColor(r, g, b) end
    return t
end
-- our own dot art (Forever has no Interface\COMMON\Indicator-* files)
dot.g = dotTex(MEDIA .. "Dot.tga", 0.2, 1, 0.2)
dot.o = dotTex(MEDIA .. "Dot.tga", 1, 0.55, 0.1)
dot.r = dotTex(MEDIA .. "Dot.tga", 1, 0.15, 0.15)
local dotState
ProtAlertsState.dot = dot

local function placeDot()
    if not DB.range or not ctx.hostile then dot:Hide(); dot.plate = nil return false end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    if not ok or (plate and plate.IsForbidden and plate:IsForbidden())
       or (plate and plate.IsVisible and not plate:IsVisible()) then plate = nil end
    -- no nameplate (plates off, or too far): sit on our target frame instead
    local tfr = ProtAlertsState.targetFrame
    local anchor = plate or (tfr and tfr:IsShown() and tfr) or nil
    if not anchor then dot:Hide(); dot.plate = nil return false end
    if dot.plate ~= anchor then
        dot.plate = anchor
        dot:ClearAllPoints()
        local okP
        if plate then okP = pcall(dot.SetPoint, dot, "BOTTOM", plate, "TOP", 0, 4)
        else okP = pcall(dot.SetPoint, dot, "CENTER", anchor, "TOPRIGHT", -12, -12) end
        if not okP then dot:Hide() return false end
    end
    dot:Show()
    return true
end

updateRange = function()
    if not placeDot() then return end
    local m = rangeOf(firstKnown(MELEE[CLASS] or {}), true)
    if secret(m) then                         -- locked: green or red only
        dotState = nil
        boolAlpha(dot.g, m, 1, 0); boolAlpha(dot.r, m, 0, 1); dot.o:SetAlpha(0)
        return
    end
    if m == nil then dot:Hide() return end    -- no range info for this target
    local state = "far"
    if m then state = "in"
    else
        local n = rangeOf(nearSpell)
        if not secret(n) and n then state = "near" end
    end
    if state ~= dotState then
        dotState = state
        dot.g:SetAlpha(state == "in" and 1 or 0)
        dot.o:SetAlpha(state == "near" and 1 or 0)
        dot.r:SetAlpha(state == "far" and 1 or 0)
    end
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
ProtAlertsState.targetFrame = tf
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
    if ProtAlertsState.placeClickers then ProtAlertsState.placeClickers() end   -- keep the right-click area on it
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
    castPlayer:ClearAllPoints()
    castPlayer:SetWidth(blockW - 23)
    castPlayer:SetPoint("TOPLEFT", main, "TOPLEFT", x + 23, -(y + gb + 2))
    y = y + 22 + gb + 6
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
        ProtAlertsState.buffNag = f

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
    ProtAlertsState.stanceNag = f

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
    ProtAlertsState.inDefensive = inDefensive

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
    local tClick = makeClicker("target", "ProtAlertsTargetClick")
    local pClick = makeClicker("player", "ProtAlertsPlayerClick")
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
    ProtAlertsState.placeClickers = place
    local w = CreateFrame("Frame")
    w:RegisterEvent("PLAYER_REGEN_ENABLED")
    w:SetScript("OnEvent", function() if wanted then place() end end)
end   -- click buttons

do   -- cursor ring (own block: Lua's 200 top-level locals limit)
    -- A smooth ring in your class color around the mouse. Hidden while you hold
    -- right-click to turn the camera (the cursor is hidden then too).
    local cr = CreateFrame("Frame", "ProtAlertsCursorRing", UIParent)
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
    ProtAlertsState.cursorRefresh = refresh
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

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if not CLASS_ALERTS[class] then main:Hide(); return end
        CLASS, ALERTS, CD_SPELLS = class, CLASS_ALERTS[class], CLASS_CDS[class]
        POWER = class == "PALADIN" and MANA or RAGE
        if POWER == MANA then rageBar:SetStatusBarColor(0.15, 0.4, 1) end
        ProtAlertsState.alerts = ALERTS
        ProtAlertsDB = ProtAlertsDB or {}
        DB = ProtAlertsDB
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
        for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do reg(e, "player", "target") end
        swing.hasEvent = pcall(self.RegisterEvent, self, "PLAYER_SWING")
        pcall(self.RegisterUnitEvent, self, "UNIT_COMBAT", "player", "target")
        pcall(self.RegisterUnitEvent, self, "UNIT_ATTACK_SPEED", "player")
        readSpeed()
        readAll()
        hideBlizzard()
        if ProtAlertsState.cursorRefresh then ProtAlertsState.cursorRefresh() end
        say("%s loaded. /pa for settings.",
            CLASS == "PALADIN" and (DB.tank and "Paladin (tank)" or "Paladin (damage)") or "Warrior")
        return
    end
    alertsDirty = true                 -- every event below can change what should light up
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- fires a lot (stance swaps...): rebuild once, half a second after it settles
        spellsDirty, spellsAt = true, GetTime()
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
local CLASS_MACROS = { WARRIOR = WARRIOR_MACROS, PALADIN = PALADIN_MACROS }

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
    local w = CreateFrame("Frame", "ProtAlertsSettings", UIParent)
    w:SetSize(360, 600)
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
    if UISpecialFrames then table.insert(UISpecialFrames, "ProtAlertsSettings") end  -- Esc closes it

    local title = w:CreateFontString(nil, "OVERLAY")
    styleText(title, 18, C(1, 1, 1)); title:SetPoint("TOP", 0, -12)
    title:SetText("ProtAlerts")
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
    local rg = add(makeCheck(w, "Range dot", "Dot over your target's head. Green: melee. Orange: one step out. Red: too far. Needs enemy nameplates (V).",
        function() return DB.range end, function(v) DB.range = v; relayout() end))
    rg:SetPoint("TOPLEFT", 16, -158)
    local tip = add(makeCheck(w, "Rage tips", "Short tip line under the rage bar.",
        function() return DB.advice end, function(v) DB.advice = v; relayout() end))
    tip:SetPoint("TOPLEFT", 180, -158)
    local tfc = add(makeCheck(w, "Target frame", "Target name, health, and who it's hitting.",
        function() return DB.target end, function(v) DB.target = v; relayout() end))
    tfc:SetPoint("TOPLEFT", 16, -180)
    local cbc = add(makeCheck(w, "Cast bars", "Your cast bar and your target's.",
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
    local test = makeButton(w, "Preview", 200, function() testUntil = GetTime() + 8 end)
    test:SetPoint("TOPLEFT", 20, -276)
    if CLASS_MACROS[CLASS] then
        local mk = makeButton(w, "Create macros", 200, makeMacros)
        mk:SetPoint("TOPLEFT", 20, -304)
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
    heading(w, "Thresholds", -340)
    local y = -380
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
        local tank = add(makeCheck(w, "Tank mode",
            "On: Righteous Fury, Seal of Fury, Sanctuary. Off: Righteousness, Might.",
            function() return DB.tank end, function(v) DB.tank = v end))
        tank:SetPoint("TOPLEFT", 16, y)
        y = y - 26
    end
    local snd = add(makeCheck(w, "Sound on danger alerts", "Raid warning sound.",
        function() return DB.sound end, function(v) DB.sound = v end))
    snd:SetPoint("TOPLEFT", 16, y)
    y = y - 44
    local crs = add(makeSlider(w, "Cursor ring size", 24, 120, 4, "%d", function() return DB.cursorSize or 48 end,
        function(v) DB.cursorSize = v; if ProtAlertsState.cursorRefresh then ProtAlertsState.cursorRefresh() end end))
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

SLASH_PROTALERTS1 = "/pa"
SLASH_PROTALERTS2 = "/protalerts"
SlashCmdList.PROTALERTS = function(msg)
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
        ProtAlertsDB = nil; ReloadUI()
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
