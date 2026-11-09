from pathlib import Path
import runpy
ctx=runpy.run_path(str(Path(__file__).with_name('party_cooldowns.py')))
a=ctx['client']('Tank','Healer','WARRIOR','PRIEST')
a.execute(r"""
Enum.SendAddonMessageResult={Success=0,AddOnMessageLockdown=11}
local s=DBagsAlertsState.partyCooldowns
C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return true end
local attempts=0
C_ChatInfo.SendAddonMessage=function() attempts=attempts+1;return 0 end
for i=1,8 do ADVANCE(.6);TICK();TICK() end
assert(attempts>0 and s.lastSendResult=='Success','realm flag suppressed successful normal API')
C_ChatInfo.SendAddonMessage=function() attempts=attempts+1;return 11 end
ADVANCE(4);TICK();TICK()
local rejected=attempts
assert(s.lastSendResult=='AddOnMessageLockdown' and s.sendBlocked,'actual restriction not respected')
for i=1,8 do ADVANCE(.6);TICK();TICK() end
assert(attempts==rejected,'repeated blocked calls')
C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return false end
C_ChatInfo.SendAddonMessage=function() attempts=attempts+1;return 0 end
ADVANCE(4);TICK();TICK()
assert(attempts>rejected and s.lastSendResult=='Success','did not resume after restriction cleared')

-- Throttling while the realm flag is set must recover without a reload.
C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return true end
C_ChatInfo.SendAddonMessage=function() attempts=attempts+1;return 3 end
ADVANCE(4);TICK();TICK()
local throttled=attempts
assert(s.retryAt and not s.sendBlocked,'throttle treated as permanent restriction')
ADVANCE(.5);TICK();TICK();assert(attempts==throttled,'retry ignored backoff')
C_ChatInfo.SendAddonMessage=function() attempts=attempts+1;return 0 end
ADVANCE(3);TICK();TICK()
assert(attempts>throttled and s.lastSendResult=='Success' and not s.retryAt,'throttle never recovered')
for msg in pairs(ERRORS) do error(msg) end
""")
print('Normal API success, one rejection, no repeated blocked sends, and restriction-clear recovery PASS')
