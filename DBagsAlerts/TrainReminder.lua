-- Trainer reminder: in WoW: Forever your class trainer has new spell ranks every two levels.
-- When you reach an even level this reminds you to visit the trainer, again each time you
-- walk into a town or inn, until you open any trainer window. Display only.
-- Turn it off in chat with /bbtrain.
local S = { due = nil }
DBagsAlertsState.trainReminder = S
local hidden = issecretvalue or function() return false end
local TAG = "|cffff7d0aBattle|r |cffc79c6eBuddy|r: "

local function db()
    DBagsAlertsDB = DBagsAlertsDB or {}
    return DBagsAlertsDB
end

local function on() return db().trainNag ~= false end

-- Say it on screen and in chat.
function S.remind()
    local level = db().trainDue
    if not (on() and level) then return false end
    local text = "Level " .. level .. ": new spell ranks. Visit your class trainer."
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(TAG .. text) end
    return true
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "TRAINER_SHOW", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, level)
    if event == "PLAYER_LEVEL_UP" then
        if type(level) == "number" and not hidden(level) and level % 2 == 0 and level <= 60 then
            db().trainDue = level
            S.remind()
        end
    elseif event == "TRAINER_SHOW" then
        db().trainDue = nil
    elseif db().trainDue then
        -- walked into a town or inn, or just logged in: one reminder
        local resting = IsResting and IsResting()
        if event == "PLAYER_ENTERING_WORLD" or (not hidden(resting) and resting == true) then S.remind() end
    end
end)

SLASH_DBAGSTRAIN1 = "/bbtrain"
SlashCmdList.DBAGSTRAIN = function()
    db().trainNag = not on()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(TAG .. "trainer reminder " .. (on() and "ON." or "OFF."))
    end
end
