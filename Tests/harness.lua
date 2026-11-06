-- Fake WoW API to load and exercise ProtAlerts.lua outside the game.
-- MODE.secret = true makes combat values "secret": comparing/doing math on them errors,
-- like the real client.
MODE = { secret = false, combat = false, target = true, casting = false }
ERRORS = {}
LOG = {}

local SECRET_MT = {}
local function boom() error("attempt to compare/arith a SECRET value", 2) end
SECRET_MT.__lt = boom; SECRET_MT.__le = boom; SECRET_MT.__add = boom; SECRET_MT.__sub = boom
SECRET_MT.__mul = boom; SECRET_MT.__div = boom; SECRET_MT.__unm = boom; SECRET_MT.__eq = boom
SECRET_MT.__concat = boom; SECRET_MT.__index = function() boom() end; SECRET_MT.__len = boom
SECRET_MT.__tostring = function() return "<secret>" end
local function S(v) if MODE.secret then return setmetatable({ __v = v }, SECRET_MT) end return v end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
function issecrettable(v) return false end

-- pcall that records failures so wrapped errors are not hidden from the test
local realpcall = pcall
function pcall(f, ...)
    local r = { realpcall(f, ...) }
    if not r[1] then
        local msg = tostring(r[2])
        if not ERRORS[msg] then ERRORS[msg] = 0 end
        ERRORS[msg] = ERRORS[msg] + 1
    end
    return unpack(r)
end

-- generic frame object
local function newObj()
    local o = { _alpha = 1 }
    return setmetatable(o, { __index = function(t, k)
        if k == "SetAlpha" then return function(self, a)
            if issecretvalue(a) then self._alpha = "secret" else self._alpha = a end end end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" or k == "CreateAnimation" then
            return function() local o = newObj(); FRAMES[#FRAMES + 1] = o; return o end end
        if k == "SetText" then return function(self, s) self._text = s end end
        if k == "SetFormattedText" then return function(self, fmt, ...)
            for i = 1, select("#", ...) do if issecretvalue(select(i, ...)) then self._text = "<secret text>" return end end
            self._text = string.format(fmt, ...) end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "SetWidth" then return function(self, v) self._w = v end end
        if k == "SetHeight" then return function(self, v) self._h = v end end
        if k == "SetSize" then return function(self, w, h) self._w = w; self._h = h end end
        if k == "GetFont" then return function(self) return "Fonts\FRIZQT__.TTF", self._fs or 12, "" end end
        if k == "SetFont" then return function(self, f, sz) self._fs = sz end end
        if k == "GetWidth" then return function(self) return self._w end end
        if k == "SetStatusBarColor" then return function(self, r, g, b) self._color = (type(r) == "number" and type(g) == "number" and type(b) == "number") and string.format("%.2f,%.2f,%.2f", r, g, b) or "?" end end
        if k == "SetPoint" then return function(self, a, rel, b, x) if type(x) == "number" then self._x = x end end end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "IsShown" then return function(self) return self._shown ~= false end end
        if k == "SetCooldownFromDurationObject" then return function(self) self._cdobj = true end end
        if k == "SetScript" then return function(self, n, f) self["_" .. n] = f end end
        return function() end
    end })
end
UIParent = newObj()
function newObjPublic() return newObj() end
GameTooltip = newObj()
UISpecialFrames = {}
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, DRUID = { r = 1, g = 0.49, b = 0.04 } }
FRAMES = {}
function CreateFrame() local o = newObj(); FRAMES[#FRAMES + 1] = o; return o end
function FIRE(event, ...)
    for _, f in ipairs(FRAMES) do if rawget(f, "_OnEvent") then f._OnEvent(f, event, ...) end end
end
function TICK() for _, f in ipairs(FRAMES) do if rawget(f, "_OnUpdate") then f._OnUpdate(f, 0.2) end end end

local now = 1000
function GetTime() return now end
function ADVANCE(s) now = now + s end
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end LOG[#LOG + 1] = table.concat(t, " ") end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function ReloadUI() end
function PlaySound() LOG[#LOG + 1] = "SOUND" end
SOUNDKIT = { RAID_WARNING = 8959 }
SlashCmdList = {}
Enum = { PowerType = { Rage = 1 }, SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 },
         LuaCurveType = { Linear = 0, Step = 1 } }

local PALADIN_SPELLS = {
    { "Righteous Fury", 31 }, { "Seal of Fury", 32 }, { "Seal of Righteousness", 33 }, { "Holy Shield", 34 },
    { "Swift Judgement", 35 }, { "Judgement", 36 }, { "Consecration", 37 }, { "Holy Strike", 38 },
    { "Exorcism", 39 }, { "Hammer of Wrath", 40 }, { "Hammer of Justice", 41 }, { "Templar's Bulwark", 42 },
    { "Divine Protection", 43 }, { "Lay on Hands", 44 }, { "Blessing of Sanctuary", 45 }, { "Blessing of Might", 46 },
    { "Devotion Aura", 47 },
}
local SPELLS = {
    { "Revenge", 11 }, { "Shield Block", 12 }, { "Victory Rush", 13 }, { "Shield Slam", 14 },
    { "Thunder Clap", 15 }, { "Demoralizing Shout", 16 }, { "Sunder Armor", 17 }, { "Shield Bash", 18 },
    { "Taunt", 19 }, { "Heroic Strike", 20 }, { "Cleave", 21 }, { "Shield Wall", 22 }, { "Last Stand", 23 },
    { "Battle Shout", 24 }, { "Bloodrage", 25 }, { "Elune's Light", 90 }, { "Shadowmeld", 91 }, { "Execute", 26 }, { "Rend", 27 }, { "Heroic Strike", 120 }, { "Defensive Stance", 72 },
}
local DRUID_SPELLS = {
    { "Bear Form", 51 }, { "Cat Form", 52 }, { "Maul", 53 }, { "Swipe", 54 }, { "Lacerate", 55 }, { "Primal Bite", 56 },
    { "Enrage", 57 }, { "Demoralizing Roar", 58 }, { "Growl", 59 }, { "Bash", 60 }, { "Faerie Fire (Feral)", 61 },
    { "Claw", 62 }, { "Rake", 63 }, { "Rip", 64 }, { "Ferocious Bite", 65 }, { "Shred", 66 }, { "Ravage", 67 },
    { "Prowl", 68 }, { "Shifting Power", 69 }, { "Moonfire", 70 }, { "Insect Swarm", 71 }, { "Wrath", 72 },
    { "Hurricane", 73 }, { "Rejuvenation", 74 }, { "Regrowth", 75 }, { "Mark of the Wild", 76 }, { "Thorns", 77 },
    { "Innervate", 78 }, { "Barkskin", 79 }, { "Frenzied Regeneration", 80 }, { "Nature's Grasp", 81 }, { "Dash", 82 },
}
if MODE_CLASS == "PALADIN" then SPELLS = PALADIN_SPELLS end
if MODE_CLASS == "DRUID" then SPELLS = DRUID_SPELLS end
local NAME = {} for _, s in ipairs(SPELLS) do NAME[s[2]] = s[1] end
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #SPELLS + 1 } end,
    GetSpellBookItemInfo = function(i)
        if i == #SPELLS + 1 then return { spellID = 999, name = "Future Spell", itemType = 2 } end
        local s = SPELLS[i]
        return { spellID = s[2], name = s[1], itemType = 1, isPassive = false }
    end,
}
C_Spell = {
    GetSpellSubtext = function(id) return id == 120 and "Rank 2" or "Rank 1" end,
    GetSpellCooldown = function(id) return { isActive = S(false), isOnGCD = false, duration = S(0), startTime = S(0) } end,
    IsSpellUsable = function(id) return S(true), S(false) end,
    GetSpellName = function(id) return NAME[id] end,
    GetSpellTexture = function(id) return 100 + id end,
    GetSpellDescription = function(id) if NAME[id] == "Shield Block" then return "Block for 6 sec." end return "" end,
    IsSpellInRange = function() return S(true) end,
    GetSpellCooldownDuration = function(id) return { duration = true } end,
    GetSpellInfo = function(id) local n = NAME[id]; return { name = n, minRange = 0, maxRange = (n == "Judgement" or n == "Hammer of Justice") and 10 or 5 } end,
    IsSpellHarmful = function(id) return true end,
}
CurveConstants = { ScaleTo100 = {} }
C_UnitAuras = { GetAuraDataBySpellName = function(u, name)
    if name == "Battle Shout" then return { duration = 120, expirationTime = now + 50 } end
    return nil end }
local plates = { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" }, { UnitFrame = { unit = "nameplate3" } } }
C_NamePlate = { GetNamePlates = function() return plates end }
local Curve = {}
Curve.__index = Curve
function Curve:SetType() end
function Curve:AddPoint(x, y) self.p[#self.p + 1] = { x, y } end
C_CurveUtil = {
    CreateCurve = function() return setmetatable({ p = {} }, Curve) end,
    EvaluateColorValueFromBoolean = function(b, t, f) return S(0.5) end,
}
function UnitPowerPercent(u, p, pred, curve) return S(0.5) end
function UnitHealthPercent(u, pred, curve) return S(0.5) end

function UnitClass() return "X", MODE_CLASS or "WARRIOR" end
function UnitPower() return S(85) end
function UnitPowerMax() return S(100) end
function UnitHealth(u) if u == "target" then return S(800) end return S(300) end
function UnitHealthMax() return S(1000) end
function UnitExists(u) return MODE.target end
function UnitCanAttack() return S(true) end
function UnitIsDead() return S(false) end
function UnitClassification() return "elite" end
function UnitLevel() return 20 end
function UnitCreatureType() return MODE_CLASS == "PALADIN" and "Undead" or "Humanoid" end
function UnitGUID(u) return S("Creature-0-1") end
function UnitAffectingCombat() return S(MODE.combat) end
function InCombatLockdown() return MODE.combat end
function IsInGroup() return true end
function IsMounted() return false end
function UnitDetailedThreatSituation() return S(false), S(1), S(64) end
-- nameplate1: on you (tanking). nameplate2: on you, but party1 has its aggro (loose).
-- nameplate3: fighting a stranger - you are NOT on its threat list.
function UnitThreatSituation(who, mob)
    if who == "player" then
        if mob == "nameplate3" then return nil end
        if mob == "nameplate2" then return S(1) end
        return S(3)
    end
    if who == "party1" and mob == "nameplate2" then return S(3) end
    return nil
end
function IsInRaid() return false end
function GetNumGroupMembers() return 2 end
function UnitIsUnit(a, b) return a == b end
function UnitCastingInfo() if MODE.casting then return S("Fireball"), nil, nil, nil, nil, nil, nil, S(false) end end
function UnitChannelInfo() return nil end
-- Forever: the old global is gone, only C_Spell.IsCurrentSpell exists
C_Spell.IsCurrentSpell = function() return S(false) end
IsCurrentSpell = nil
MACROS = {}
function GetMacroIndexByName(n) for i, m in ipairs(MACROS) do if m.name == n then return i end end return 0 end
function CreateMacro(n, icon, body, perChar)
    assert(#n <= 16, "macro name too long: " .. n)
    assert(#body <= 255, "macro body too long: " .. n)
    if #MACROS >= 30 then error("too many macros") end
    MACROS[#MACROS + 1] = { name = n, body = body }
    return #MACROS
end
function EditMacro(i, n, icon, body) assert(#body <= 255); MACROS[i].body = body; return i end
SPEED = 2.4
function UnitAttackSpeed() if MODE.combat then return S(SPEED), nil end return SPEED, nil end

-- target frame / cast bar mocks
function UnitName(u) return S("Defias Thug") end
function UnitReaction() return 2 end
function UnitIsTapDenied() return false end
function UnitIsPlayer() return false end
function UnitPowerType() return 0 end
function UnitCastingDuration(u) if MODE.casting then return { dur = true } end end
function UnitChannelDuration(u) return nil end
PlayerFrame, TargetFrame, PlayerCastingBarFrame = newObjPublic(), newObjPublic(), newObjPublic()
C_Secrets = { ShouldAurasBeSecret = function() return MODE.secret end, ShouldSpellAuraBeSecret = function() return true end }
TARGET_PLATE = newObj(); TARGET_PLATE.IsVisible = function() return true end; TARGET_PLATE.IsForbidden = function() return false end
C_NamePlate.GetNamePlateForUnit = function(u) if u == "target" then return TARGET_PLATE end end
CURSOR_X = 500
function GetCursorPosition() CURSOR_X = CURSOR_X + 3; return CURSOR_X, 400 end
function IsMouselooking() return false end
-- far away out of combat: the 10 yd check says no
function CheckInteractDistance(u, i) return false end
C_ActionBar = { FindSpellActionButtons = function() return { 5 } end, IsActionInRange = function() return S(true) end }
function UnitIsDeadOrGhost() return false end
function IsResting() return false end
NO_SHOUT = false
local oldAura = C_UnitAuras.GetAuraDataBySpellName
C_UnitAuras.GetAuraDataBySpellName = function(u, name, f)
    if NO_SHOUT and name == "Battle Shout" then return nil end
    return oldAura(u, name, f)
end
STANCE_DEF = false
function GetNumShapeshiftForms() return 2 end
function GetShapeshiftFormInfo(i)
    if i == 1 then return 1, not STANCE_DEF, true, 71 end   -- Battle Stance
    return 2, STANCE_DEF, true, 72                          -- Defensive Stance
end
function IsPlayerSpell() return false end
-- bags: slot 1 = Tough Jerky (well fed food), slot 2 = vendor bread (no buff)
BAG = { { itemID = 117, iconFileID = 1117 }, { itemID = 4540, iconFileID = 1540 } }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
    GetContainerItemInfo = function(bag, slot) return BAG[slot] end,
}
C_TooltipInfo = { GetItemByID = function(id)
    if id == 117 then return { lines = { { leftText = "Tough Jerky" }, { leftText = "Use: Restores 61 health. If you spend at least 10 seconds eating you will become well fed." } } } end
    return { lines = { { leftText = "Tough Hunk of Bread" }, { leftText = "Use: Restores 61 health." } } }
end }
C_Item = { GetItemInfo = function(id) return "x", "x", 1, 1, 1 end }
function GetMaxPlayerLevel() return 60 end
DRIVER = {}
function RegisterStateDriver(f, k, v) DRIVER[f] = v; f._shown = true end
function UnregisterStateDriver(f) DRIVER[f] = nil end
WELL_FED = false
local oa2 = C_UnitAuras.GetAuraDataBySpellName
C_UnitAuras.GetAuraDataBySpellName = function(u, name, f)
    if name == "Well Fed" then return WELL_FED and { duration = 900, expirationTime = 9999 } or nil end
    return oa2(u, name, f)
end
C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
TSTAT = "default"
local oldTS = UnitThreatSituation
function UnitThreatSituation(who, mob)
    if mob == "target" and TSTAT ~= "default" then return TSTAT end
    return oldTS(who, mob)
end
-- weapon: a one-hand sword (class 2, sub 7); stone state + bag stone
function GetInventoryItemID(u, slot) if slot == 16 then return 2488 end end
C_Item.GetItemInfoInstant = function(id) if id == 2488 then return id, "Weapon", "Swords", "INVTYPE_WEAPON", 1, 2, 7 end return id, "x", "x", "", 1, 0, 5 end
STONED = false
function GetWeaponEnchantInfo() return STONED, STONED and 1700000 or 0 end
local oldGII = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
    if id == 2862 then return "Rough Sharpening Stone", "x", 1, 5, 1 end
    return oldGII(id)
end

-- druid forms
FORM_ID, PTYPE, STEALTH, CP = 5, 1, false, 4
function GetShapeshiftFormID() return FORM_ID end
function IsStealthed() return STEALTH end
local oldUP = UnitPower
function UnitPower(u, pt) if pt == 4 then return S(CP) end return oldUP(u, pt) end
local oldUPT = UnitPowerType
function UnitPowerType(u) if MODE_CLASS == "DRUID" then return PTYPE end return oldUPT(u) end

-- warlock
local WARLOCK_SPELLS = {
    { "Shadow Bolt", 201 }, { "Immolate", 202 }, { "Corruption", 203 }, { "Bane of Agony", 204 }, { "Life Tap", 205 },
    { "Drain Life", 206 }, { "Drain Soul", 207 }, { "Siphon Life", 208 }, { "Fear", 209 }, { "Death Coil", 210 },
    { "Curse of the Elements", 211 }, { "Curse of Weakness", 212 }, { "Demon Armor", 213 }, { "Summon Imp", 214 },
    { "Summon Voidwalker", 215 }, { "Create Healthstone", 216 }, { "Health Funnel", 217 }, { "Rain of Fire", 218 },
    { "Searing Pain", 219 }, { "Conflagrate", 220 }, { "Shadowburn", 221 }, { "Howl of Terror", 222 }, { "Soul Link", 223 },
}
if MODE_CLASS == "WARLOCK" then
    SPELLS = WARLOCK_SPELLS
    for k in pairs(NAME) do NAME[k] = nil end
    for _, s in ipairs(SPELLS) do NAME[s[2]] = s[1] end
end
PET = true
local oldUE = UnitExists
function UnitExists(u) if u == "pet" then return PET end return oldUE(u) end
TRANCE_AURA = false
local oa3 = C_UnitAuras.GetAuraDataBySpellName
C_UnitAuras.GetAuraDataBySpellName = function(u, name, f)
    if name == "Shadow Trance" then return TRANCE_AURA and { duration = 10, expirationTime = now + 8 } or nil end
    return oa3(u, name, f)
end
RAID_CLASS_COLORS.WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }
-- warlock plain mode: our dots are really on the target while they last
CASTED = {}
local DOT_LEN = { Corruption = 18, ["Bane of Agony"] = 24, Immolate = 15, ["Siphon Life"] = 30, ["Curse of the Elements"] = 300 }
local oldFIRE = FIRE
function FIRE(event, a1, a2, a3, ...)
    if MODE_CLASS == "WARLOCK" and event == "UNIT_SPELLCAST_SUCCEEDED" and NAME[a3] then CASTED[NAME[a3]] = now end
    return oldFIRE(event, a1, a2, a3, ...)
end
local oa4 = C_UnitAuras.GetAuraDataBySpellName
C_UnitAuras.GetAuraDataBySpellName = function(u, name, f)
    if MODE_CLASS == "WARLOCK" and u == "target" and DOT_LEN[name] and CASTED[name] and now - CASTED[name] < DOT_LEN[name] then
        return { duration = DOT_LEN[name], expirationTime = CASTED[name] + DOT_LEN[name] }
    end
    return oa4(u, name, f)
end
SOLO = false
local oldIG = IsInGroup
function IsInGroup() if SOLO then return false end return oldIG() end

-- player cast for the slidecast check: Shadow Bolt, 2.5 s, started CAST_START
PCAST = nil
CVARS = { SpellQueueWindow = "400" }
function GetCVar(k) return CVARS[k] end
local oldUCI = UnitCastingInfo
function UnitCastingInfo(u)
    if u == "player" and PCAST then
        return S("Shadow Bolt"), nil, 136197, S(PCAST * 1000), S((PCAST + 2.5) * 1000), false, S(7), S(false), S(201)
    end
    return oldUCI(u)
end

local oldUCD = UnitCastingDuration
function UnitCastingDuration(u) if u == "player" and PCAST then return { dur = true } end return oldUCD(u) end

local oldGSI = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function(id) local t = oldGSI(id); if t and id == 201 then t.castTime = 2500 end; return t end

-- Duration object updates its own clock; hidden durations may be rendered, never inspected.
local realCastingDuration = UnitCastingDuration
function UnitCastingDuration(u)
    if u == "player" and PCAST then
        local untilAt = PCAST + 2.5
        return {GetRemainingDuration = function() return S(math.max(0, untilAt - GetTime())) end}
    end
    return realCastingDuration(u)
end
