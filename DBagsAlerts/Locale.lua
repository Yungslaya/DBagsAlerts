--[[ Battle Buddy - other languages

  English is written in the code. When the game runs in another language:
    - a cue that is just a spell's name ("REVENGE") shows the game's own name for that spell;
    - other cues ("LOW HP", "FINISH WITH WAND") and the Settings window use the lines below;
    - anything without a translation stays in English.
  Nothing here runs on text that changes during a fight (health numbers, timers): only the
  fixed words of cues and settings pass through DBagsAlertsLocale.T().

  A language file adds its lines with DBagsAlertsLocale:AddLocale("deDE", { lines }, { patterns }).
]]
DBagsAlertsLocale = { LOCALES = {}, cache = {} }
local L = DBagsAlertsLocale

local locale = (GetLocale and GetLocale()) or "enUS"
if locale == "esMX" then locale = "esES" end
L.locale = locale

local lines, patterns

function L:AddLocale(code, exact, shaped)
    L.LOCALES[code] = { exact = exact or {}, patterns = shaped or {} }
    if code == L.locale then lines, patterns = L.LOCALES[code].exact, L.LOCALES[code].patterns end
end

-- For tests: switch language after loading.
function L:UseLocale(code)
    L.locale = code
    local l = L.LOCALES[code]
    lines, patterns = l and l.exact or nil, l and l.patterns or nil
    L.cache = {}
end

function L.Active() return lines ~= nil end

-- A fixed line of text. Unknown text stays as it is.
function L.T(text)
    if not lines or type(text) ~= "string" or text == "" then return text end
    if issecretvalue and issecretvalue(text) then return text end
    local cached = L.cache[text]
    if cached ~= nil then return cached or text end
    local out = lines[text]
    if not out then
        for i = 1, #patterns do
            local rule = patterns[i]
            if text:find(rule[1]) then out = text:gsub(rule[1], rule[2]); break end
        end
    end
    L.cache[text] = out or false
    return out or text
end

-- The words on a cue. text = what English would show, spellName / spellID = the cue's spell.
-- A cue that only names its spell uses the game's own name for it, in the same letter case.
function L.Cue(text, spellName, spellID)
    if not lines or type(text) ~= "string" then return text end
    local hit = lines[text]
    if hit then return hit end
    if spellID and type(spellName) == "string" and text:upper() == spellName:upper()
        and C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            if text == text:upper() and text ~= text:lower() then
                local okU, upper = pcall(string.upper, name)
                -- string.upper only knows plain letters; for other alphabets keep the game's spelling
                return (okU and locale ~= "ruRU" and locale ~= "zhCN") and upper or name
            end
            return name
        end
    end
    return L.T(text)
end
