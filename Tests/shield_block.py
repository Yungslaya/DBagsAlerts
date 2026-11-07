from pathlib import Path
from lupa import lua51
root = Path(__file__).resolve().parents[1]
for hidden in (False, True):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="WARRIOR"; CAST_IDS={}')
    lua.execute((root / "Tests/harness.lua").read_text(encoding="utf-8"))
    lua.execute("MODE.secret=" + str(hidden).lower())
    lua.execute("""
        TANKING=true; BLOCK_READY=true; BLOCK_USABLE=true
        local unit=UnitIsUnit
        UnitIsUnit=function(a,b)
            if a=="targettarget" and b=="player" then return TANKING end
            return unit(a,b)
        end
        local cd=C_Spell.GetSpellCooldown
        C_Spell.GetSpellCooldown=function(id)
            if id==12 and not BLOCK_READY then return {isActive=true,isOnGCD=false} end
            return cd(id)
        end
        local usable=C_Spell.IsSpellUsable
        C_Spell.IsSpellUsable=function(id)
            if id==12 and not BLOCK_USABLE then return false end
            return usable(id)
        end
    """)
    chunk=lua.eval("function(s) return assert(loadstring(s)) end")((root / "DBagsAlerts/DBagsAlerts.lua").read_text(encoding="utf-8"))
    lua.execute("""
        local chunk=...; chunk("DBagsAlerts",{}); FIRE("PLAYER_LOGIN")
        MODE.combat=true; MODE.target=true
        local function step() ADVANCE(1); TICK(); TICK() end
        step()
        local block, dump
        for _,a in ipairs(DBagsAlertsState.alerts) do
            if a.key=="block" then block=a elseif a.key=="dump" then dump=a end
        end
        assert(block.rootA==1,"ready Block missing")
        assert(block.root._w==40 and block.root._x~=dump.root._x,"Block shares another helper slot")
        assert(block.c.glowF:IsShown(),"Block glow missing")
        assert(block.c.text._text=="BLOCK","Block wording")
        TANKING=false; step(); assert(block.rootA==0,"off-tank Block cue")
        TANKING=true; BLOCK_READY=false; step(); assert(block.rootA==0,"Block cue on cooldown")
        BLOCK_READY=true; BLOCK_USABLE=false; step(); assert(block.rootA==0,"unusable Block cue")
        BLOCK_USABLE=true; step(); assert(block.rootA==1,"Block cue not restored")
        MODE.combat=false; step(); assert(block.rootA==0,"idle Block cue")
        MODE.combat=true; MODE.target=false; step(); assert(block.rootA==0,"Block without enemy")
        for msg in pairs(ERRORS) do error(msg) end
    """,chunk)
    print("Shield Block", "hidden" if hidden else "plain", "PASS")
