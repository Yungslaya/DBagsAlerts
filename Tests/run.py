import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent / "deps"))
from lupa import lua51

BASE = __import__("pathlib").Path(__file__).parent
ADDON = str((BASE / "DBagsAlerts.lua") if (BASE / "DBagsAlerts.lua").exists() else (BASE.parent / "DBagsAlerts" / "DBagsAlerts.lua"))
HARNESS = sys.argv[1]

DRIVER = r"""
local chunk = ...
chunk("DBagsAlerts", {})
FIRE("PLAYER_LOGIN")
TICK()
-- pull: combat, casts, rage, a caster target
MODE.combat = true
MODE.casting = true
for _, id in ipairs(CAST_IDS) do FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", id) end
FIRE("UNIT_POWER_UPDATE", "player", "RAGE")
FIRE("PLAYER_SWING", MODE.secret and setmetatable({}, getmetatable(UnitPower())) or 2.4, 0)
ADVANCE(0.5); TICK()
local function swingText()
    for _, f in ipairs(FRAMES) do
        local t = rawget(f, "_text")
        if type(t) == "string" and t:find("^%d+%.%d$") then return t end
    end
end
print("swing bar 0.5s after a swing: " .. tostring(swingText() or "NO SWING TEXT"))
SPEED = 1.2; FIRE("UNIT_ATTACK_SPEED", "player"); ADVANCE(0.06); TICK()
print("after attack speed doubles: " .. tostring(swingText() or "NO SWING TEXT"))
FIRE("UNIT_AURA", "player", {})
-- TARGETCHECK
FIRE("PLAYER_TARGET_CHANGED"); FIRE("UNIT_SPELLCAST_START", "target"); FIRE("UNIT_SPELLCAST_START", "player"); TICK()
local found = {}
for _, f in ipairs(FRAMES) do local t = rawget(f, "_text"); if type(t) == "string" and (t:find("%%") or t:find(">>") or t == "<secret text>") then found[#found+1] = t end end
print("target/cast texts: " .. table.concat(found, " | "))
for i = 1, 5 do ADVANCE(0.2); TICK() end
ADVANCE(10); TICK()
MODE.target = false; TICK()
MODE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); TICK()
for _, c in ipairs({"", "test", "unlock", "lock", "scale 1.3", "list", "toggle rend", "toggle nope",
                    "sunder 3", "dump 60", "hp 40", "sound", "tank", "tank", "mana 25", "debug"}) do
    SlashCmdList.DBAGSALERTS(c)
end
MODE.combat = true; MODE.target = true; ADVANCE(40); TICK()
print("calm, 85 rage -> " .. tostring((function() for _, f in ipairs(FRAMES) do local t = rawget(f, "_text"); if type(t) == "string" and t:find("rage") and t:find("!") then return t end end end)() or "(no warning - already in tanking-hard mode)"))
for i = 1, 5 do FIRE("UNIT_COMBAT", "player", "WOUND", "", 120, 1); ADVANCE(0.5) end
FIRE("UNIT_COMBAT", "player", "HEAL", "", 300, 2)
TICK()
for _, f in ipairs(FRAMES) do
    local t = rawget(f, "_text")
    if type(t) == "string" and (t:find("hit a lot") or t:find("HIT A LOT") or t:find("press") or t:find("Extra")) then print("tanking hard -> " .. t .. "  alpha=" .. tostring(f._alpha)) end
end
SlashCmdList.DBAGSALERTS("debug")
local out = {}
for _, a in ipairs(DBagsAlertsState.alerts) do
    local state = "off"
    if a.root and a.root._alpha == 1 then
        state = "LIT"
        for i = 1, 4 do if a.gates[i]._alpha == "secret" then state = "LIT(secret-gated)" break end end
    end
    out[#out + 1] = a.key .. "=" .. state
end
print("ALERTS: " .. table.concat(out, ", "))
-- advice line: which sentence is visible right now (rage 85 in the fake)
for _, f in ipairs(FRAMES) do
    local t = rawget(f, "_text")
    if type(t) == "string" and (t:find("rage") or t:find("mana")) and f._alpha ~= 0 then print("advice visible: " .. t .. " alpha=" .. tostring(f._alpha)) end
end
-- settings window: open it, click every box, move every slider, close it
SlashCmdList.DBAGSALERTS("")
local clicks, slides = 0, 0
for _, f in ipairs(FRAMES) do
    if rawget(f, "_OnClick") then f._OnClick(f); clicks = clicks + 1 end
    if rawget(f, "_OnValueChanged") then f._OnValueChanged(f, 50); slides = slides + 1 end
    if rawget(f, "_OnEnter") then f._OnEnter(f) end
end
TICK()
SlashCmdList.DBAGSALERTS("")
print("settings: clicked " .. clicks .. " buttons/boxes, moved " .. slides .. " sliders")
SlashCmdList.DBAGSALERTS("help")
MODE.combat = false
SlashCmdList.DBAGSALERTS("macros")
SlashCmdList.DBAGSALERTS("macros")
print("macros stored: " .. #MACROS)
for _, m in ipairs(MACROS) do print("MACRO " .. m.name .. " | " .. m.body:gsub("\n", " / ")) end
local texts, cds = {}, 0
for _, f in ipairs(FRAMES) do
    if rawget(f, "_cdobj") then cds = cds + 1 end
end
print("cooldown spirals fed a secret duration: " .. cds)
-- DOTCHECK
DBagsAlertsDB.range = true
MODE.combat = true; MODE.target = true; ADVANCE(1); TICK()
local shown = {}
for _, f in ipairs(FRAMES) do if rawget(f, "_shown") and rawget(f, "_tex") then shown[#shown+1] = f._tex end end
local D = DBagsAlertsState.dot
print("dot: shown=" .. tostring(D._shown) .. " green=" .. tostring(D.g._alpha) .. " orange=" .. tostring(D.o._alpha) .. " red=" .. tostring(D.r._alpha))

local SB = DBagsAlertsState.stoneButton
if SB then
  DBagsAlertsDB.stoneNag = true; DBagsAlertsDB.stoneNeed = true
  local oldSec = MODE.secret
  MODE.secret = false; MODE.combat = false
  BAG[3] = { itemID = 2862, iconFileID = 2862 }; STONED = false; DBagsAlertsState.stoneUpdate()
  print("stone: have stone, not applied: shown=" .. tostring(SB._shown) .. " text=" .. tostring(rawget(SB.text, "_text")) .. " item=" .. tostring(SB.itemID))
  STONED = true; DBagsAlertsState.stoneUpdate()
  print("stone: applied: shown=" .. tostring(SB._shown))
  STONED = false; BAG[3] = nil; DBagsAlertsState.stoneUpdate()
  print("stone: none in bags: shown=" .. tostring(SB._shown) .. " text=" .. tostring(rawget(SB.text, "_text")))
  DBagsAlertsDB.stoneNeed = false; DBagsAlertsState.stoneUpdate()
  print("stone: none, 'show if none' off: shown=" .. tostring(SB._shown))
  DBagsAlertsDB.stoneNeed = true; MODE.secret = oldSec
end

do
  DBagsAlertsDB.range = true
  local oldSec = MODE.secret
  MODE.secret = false; MODE.combat = true; MODE.target = true
  ADVANCE(0.2); TICK()
  local parts = {}
  for plate, d in pairs(DBagsAlertsState.dotPool or {}) do
    local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    parts[#parts+1] = u .. "=" .. (d._shown and ((d.g._alpha == 1 and "green") or (d.o._alpha == 1 and "yellow") or (d.r._alpha == 1 and "red") or "?") or "hidden")
  end
  table.sort(parts)
  print("all plates: " .. table.concat(parts, " "))
  MODE.combat = false; ADVANCE(0.2); TICK()
  local n = 0
  for _, d in pairs(DBagsAlertsState.dotPool or {}) do if d._shown then n = n + 1 end end
  print("all plates, no combat: dots shown=" .. n)
  MODE.secret = oldSec
end

do
  local D2 = DBagsAlertsState.dot
  DBagsAlertsDB.range = true
  local oldSec = MODE.secret
  MODE.secret = false; MODE.combat = true; MODE.target = true
  TARGET_PLATE.IsVisible = function() return false end
  if DBagsAlertsState.targetFrame then DBagsAlertsState.targetFrame._shown = true end
  for _, v in ipairs({ 3, 2, 1, 0 }) do
    TSTAT = v; ADVANCE(0.2); TICK()
    print("aggro " .. v .. ": g=" .. tostring(D2.g._alpha) .. " y=" .. tostring(D2.o._alpha) .. " r=" .. tostring(D2.r._alpha))
  end
  TSTAT = "default"; MODE.secret = oldSec
  TARGET_PLATE.IsVisible = function() return true end
end

local EB = DBagsAlertsState.eatButton
if EB then
  DBagsAlertsDB.foodNag = true
  local oldSec = MODE.secret
  MODE.secret = false; MODE.combat = false
  WELL_FED = false; DBagsAlertsState.foodUpdate()
  print("eat: not fed: shown=" .. tostring(EB._shown) .. " item=" .. tostring(EB.itemID))
  WELL_FED = true; DBagsAlertsState.foodUpdate()
  print("eat: fed: shown=" .. tostring(EB._shown))
  WELL_FED = false; BAG[1] = nil; DBagsAlertsState.foodUpdate()
  print("eat: only bread: shown=" .. tostring(EB._shown))
  print("eat debug: " .. tostring(DBagsAlertsDB.foodDebug.why) .. " | " .. tostring(DBagsAlertsDB.foodDebug.extra))
  BAG[1] = { itemID = 117, iconFileID = 1117 }; MODE.secret = oldSec
end

local SN = DBagsAlertsState.stanceNag
if SN then
  DBagsAlertsDB.stanceNag = true
  MODE.combat = true; MODE.target = true; STANCE_DEF = false
  for i = 1, 14 do ADVANCE(0.2); TICK() end
  print("stance nag, battle stance in combat: shown=" .. tostring(SN._shown))
  STANCE_DEF = true; ADVANCE(0.2); TICK(); ADVANCE(0.2); TICK()
  print("stance nag, defensive: shown=" .. tostring(SN._shown))
  STANCE_DEF = false; MODE.combat = false; ADVANCE(0.2); TICK(); ADVANCE(0.2); TICK()
  print("stance nag, out of combat: shown=" .. tostring(SN._shown))
end

local N = DBagsAlertsState.buffNag
if N then
  DBagsAlertsDB.buffNag = true
  MODE.combat = false; ADVANCE(1); TICK(); TICK()
  print("nag with shout up: shown=" .. tostring(N._shown))
  NO_SHOUT = true; ADVANCE(1); TICK(); TICK()
  for k, v in pairs(ERRORS) do print("ERR", k, v) end

  print("nag shout missing: shown=" .. tostring(N._shown) .. " text=" .. tostring(rawget(N.text, "_text")))
  NO_SHOUT = false

  -- the bug: shout is up, then combat hides auras (lookup returns nothing)
  local oldSec = MODE.secret
  MODE.combat = false; MODE.secret = false; ADVANCE(1); TICK(); TICK()
  MODE.combat = true; MODE.secret = true; NO_SHOUT = true; ADVANCE(1); TICK(); TICK()
  print("nag in combat, shout up but hidden: shown=" .. tostring(N._shown))
  NO_SHOUT = false; MODE.secret = oldSec; MODE.combat = false
end

MODE.combat = false; ADVANCE(2); TICK()
local rd = DBagsAlertsDB.rangeDebug or {}; print("rd", rd.spell, rd.bar, rd.book, rd.close, InCombatLockdown())
print("dot far, no combat: green=" .. tostring(D.g._alpha) .. " orange=" .. tostring(D.o._alpha) .. " red=" .. tostring(D.r._alpha))
-- GLOWCHECK
DBagsAlertsDB.off = {}; DBagsAlertsDB.stack = true
SlashCmdList.DBAGSALERTS("toggle swing"); SlashCmdList.DBAGSALERTS("toggle swing")
MODE.combat = true; MODE.target = true; ADVANCE(1); TICK(); ADVANCE(1); TICK()
do
    local g = {}
    for _, f in ipairs(FRAMES) do
        local gg = rawget(f, "glowGates")
        if gg and rawget(f, "name") and f._shown ~= false then
            local a = gg[1]._alpha
            if a == 1 or a == "secret" then g[#g + 1] = f.name .. (a == "secret" and "(locked)" or "") end
        end
    end
    print("glowing: " .. table.concat(g, ", "))
end
-- RENDCHECK
if MODE_CLASS == "WARRIOR" then
    SlashCmdList.DBAGSALERTS("toggle rend")
    MODE.combat = true; MODE.target = true
    local function rendLit() for _, a in ipairs(DBagsAlertsState.alerts) do if a.key == "rend" then return a.rootA == 1 end end end
    ADVANCE(40); FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 27); ADVANCE(0.2); TICK(); ADVANCE(0.4); TICK()
    print("rend just landed -> suggested? " .. tostring(rendLit()))
    ADVANCE(40); FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 27); FIRE("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
    ADVANCE(0.2); TICK(); ADVANCE(0.4); TICK()
    print("rend dodged -> suggested again? " .. tostring(rendLit()))
end
-- DRUIDCHECK
if MODE_CLASS == "DRUID" then
    local function lit()
        local t = {}
        for _, a in ipairs(DBagsAlertsState.alerts) do
            if a.rootA == 1 then
                local secretGate = false
                for i = 1, 4 do if a.gates[i]._alpha == "secret" then secretGate = true end end
                local hidden = false
                for i = 1, 4 do if a.gates[i]._alpha == 0 then hidden = true end end
                if not hidden then t[#t + 1] = a.key .. (secretGate and "?" or "") end
            end
        end
        return table.concat(t, " ")
    end
    MODE.combat = true; MODE.target = true
    for _, f in ipairs({ { "bear", 5, 1, false }, { "cat", 1, 3, false }, { "cat-prowl", 1, 3, true }, { "caster", 0, 0, false } }) do
        FORM_ID, PTYPE, STEALTH = f[2], f[3], f[4]
        FIRE("UPDATE_SHAPESHIFT_FORM"); ADVANCE(0.5); TICK(); ADVANCE(0.5); TICK()
        print("druid " .. f[1] .. ": " .. lit())
    end
end
-- Cast clock: real duration text, no early movement recommendation.
do
    local cb = DBagsAlertsState.castPlayer
    DBagsAlertsDB.casts = true
    if MODE_CLASS == "WARLOCK" then SlashCmdList.DBAGSALERTS("newlook") end
    MODE.casting = false; PCAST = GetTime()
    FIRE("UNIT_SPELLCAST_START", "player", "guid", 201); TICK()
    ADVANCE(1.1); TICK()
    assert(cb._shown == true, "player cast bar missing")
    assert(cb.safe == nil or type(cb.safe) == "function", "old movement zone remains")
    print("CAST actual timer=" .. tostring(rawget(cb.left, "_text")) .. " queue=" .. tostring(cb.queueMark._shown))
    if MODE.secret then assert(cb.queueMark._shown == false, "guessed queue during hidden timings") end
    PCAST = nil; FIRE("UNIT_SPELLCAST_STOP", "player"); TICK()
    assert(cb._shown == false, "cast bar stays after stop")
end
-- WARLOCKCHECK
if MODE_CLASS == "WARLOCK" then
    local function lit()
        local t = {}
        for _, a in ipairs(DBagsAlertsState.alerts) do
            if a.rootA == 1 then
                local secretGate, hidden = false, false
                for i = 1, 4 do
                    if a.gates[i]._alpha == "secret" then secretGate = true end
                    if a.gates[i]._alpha == 0 then hidden = true end
                end
                local label = a.c and rawget(a.c.text, "_text")
                if not hidden then t[#t + 1] = a.key .. (secretGate and "?" or "") .. "[" .. tostring(label) .. "]" end
            end
        end
        return table.concat(t, " ")
    end
    local function step() ADVANCE(0.5); TICK(); ADVANCE(0.5); TICK() end
    DBagsAlertsDB.off = {}; DBagsAlertsDB.shardGoal = 5
    MODE.combat = true; MODE.target = true; PET = true; BAG = {}
    ADVANCE(60); step()
    print("warlock fight, pet out, empty bags: " .. lit())
    do
        local cb = DBagsAlertsState.castPlayer
        local h = DBagsAlertsState.casterHUD
        assert(h.width == 300 and h.dotY == 112, "caster layout mismatch")
        assert(cb._h == 26 and cb._w == 253, "cast bar size mismatch")
        assert(h.castY < h.utilityY, "cast bar separated by utility icons")
        for _, a in ipairs(DBagsAlertsState.alerts) do
            if a.hudSpot == "next" then assert(a.root._w == 60, "main cue not large")
            elseif a.hudSpot then assert(a.root._w == 28, "helper not small") end
        end
        SlashCmdList.DBAGSALERTS("oldlook")
        assert(h.frame._shown == false, "new HUD still visible in oldlook")
        SlashCmdList.DBAGSALERTS("newlook")
        assert(h.frame._shown == true, "new HUD not restored")
        print("HUD: 300px, one 60px action, 28px helpers, 26px cast, old/new toggle PASS")
    end
    PET = false; step()
    print("warlock fight, no pet: " .. lit())
    PET = true
    for _, id in ipairs({ 203, 204, 202, 208, 211 }) do FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", id) end
    step()
    print("warlock after Corruption/Agony/Immolate/Siphon/Elements: " .. lit())
    ADVANCE(5); for _, f in ipairs(FRAMES) do if rawget(f, "_OnUpdate") then f._OnUpdate(f, 0.2) end end
    local tt = {}
    for _, f in ipairs(DBagsAlertsState.dotTiles or {}) do tt[#tt + 1] = f.name .. "=" .. tostring(rawget(f.num, "_text")) .. (f.shade._alpha == 1 and "(missing)" or "") end
    print("dot tiles 5s later: " .. table.concat(tt, ", "))
    FIRE("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 201); TRANCE_AURA = true; step()
    print("warlock Nightfall proc: " .. lit())
    FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 201); TRANCE_AURA = false; step()
    print("warlock after free bolt: " .. lit())
    BAG = { { itemID = 6265, iconFileID = 6265 }, { itemID = 6265, iconFileID = 6265 }, { itemID = 5512, iconFileID = 5512 } }
    ADVANCE(2); step()
    print("warlock 2 shards + healthstone: " .. lit())
    MODE.combat = false; MODE.target = false; BAG = { { itemID = 6265, iconFileID = 6265 } }; ADVANCE(2); step()
    print("warlock out of combat, 1 shard, no stone: " .. lit())
    MODE.combat = true; MODE.target = true; SOLO = true; ADVANCE(1); step()
    print("warlock solo, 2 mobs on you, 30% hp: " .. lit())
    SOLO = false
end
return DBagsAlertsDB
"""

CASTS = {"WARRIOR": "{17, 17, 12, 24, 16, 15, 27, 999, 120}",
         "PALADIN": "{31, 32, 34, 36, 45, 47, 37, 999}",
         "DRUID": "{76, 77, 999}",
         "WARLOCK": "{213, 999}"}
bad = False
for cls, secret in (("WARRIOR", False), ("WARRIOR", True), ("PALADIN", False), ("PALADIN", True), ("DRUID", False), ("DRUID", True), ("WARLOCK", False), ("WARLOCK", True)):
    print("=" * 20, cls, "SECRET mode (combat lock)" if secret else "PLAIN mode")
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute('MODE_CLASS = "%s"; CAST_IDS = %s' % (cls, CASTS[cls]))
    L.execute(open(HARNESS, encoding="utf-8").read())
    L.execute("MODE.secret = %s" % ("true" if secret else "false"))
    res = L.eval("loadstring")(open(ADDON, encoding="utf-8").read(), "DBagsAlerts.lua")
    chunk, err = (res if isinstance(res, tuple) else (res, None))
    if chunk is None:
        print("SYNTAX ERROR:", err); sys.exit(1)
    try:
        L.execute(DRIVER, chunk)
    except Exception as e:
        bad = True
        print("UNCAUGHT ERROR:", e)
    errs = L.globals().ERRORS
    if len(list(errs.items())): bad = True
    for msg, n in errs.items():
        print("  pcall caught x%d: %s" % (n, msg))
    for line in list(L.globals().LOG.values()):
        print("  log:", line)
print("FAILED" if bad else "no uncaught errors")



if bad: sys.exit(1)

# Early-level book: no Drain Life/Death Coil/Life Tap yet. Never show shield fallbacks.
for hidden in (False, True):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute('MODE_CLASS="WARLOCK"; CAST_IDS={}')
    L.execute(open(HARNESS, encoding="utf-8").read())
    L.execute("MODE.secret=" + ("true" if hidden else "false"))
    L.execute('''
        local book = {{"Shadow Bolt",201},{"Immolate",202},{"Demon Skin",240},{"Summon Imp",214}}
        C_SpellBook.GetSpellBookSkillLineInfo = function() return {itemIndexOffset=0,numSpellBookItems=#book} end
        C_SpellBook.GetSpellBookItemInfo = function(i)
            return {spellID=book[i][2], name=book[i][1], itemType=1,isPassive=false}
        end
        local oldName = C_Spell.GetSpellName
        C_Spell.GetSpellName = function(id) if id==240 then return "Demon Skin" end return oldName(id) end
    ''')
    chunk = L.eval("function(s) return assert(loadstring(s)) end")(open(ADDON,encoding="utf-8").read())
    L.execute('''
        local chunk=...; chunk("DBagsAlerts",{}); FIRE("PLAYER_LOGIN"); TICK()
        MODE.combat=true; MODE.target=true; FIRE("PLAYER_REGEN_DISABLED"); ADVANCE(1); TICK()
        assert(#DBagsAlertsState.dotTiles==1, "unlearned DoT tiles")
        assert(DBagsAlertsState.dotTiles[1].name=="Immolate", "wrong early DoT")
        for _,a in ipairs(DBagsAlertsState.alerts) do
            if a.key=="lowhp" or a.key=="lowmana" then
                assert(a.rootA==0, "unknown spell/warrior placeholder lit up")
            end
        end
        SlashCmdList.DBAGSALERTS("test"); ADVANCE(1); TICK()
        for _,a in ipairs(DBagsAlertsState.alerts) do
            if a.key=="lowhp" then assert(a.rootA==0,"test preview shows unknown defensive") end
        end
    ''', chunk)
    if list(L.globals().ERRORS.items()):
        raise AssertionError(str(list(L.globals().ERRORS.items())))
    print("Early-level Warlock", "hidden" if hidden else "plain", "PASS")
print("All four classes + hidden timing + early-level spellbook PASS")

