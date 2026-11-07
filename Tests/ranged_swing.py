from pathlib import Path
from lupa import lua51
root=Path(__file__).resolve().parents[1]
for hidden in (False,True):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="WARRIOR"; CAST_IDS={}')
    lua.execute((root/'Tests/harness.lua').read_text(encoding="utf-8"))
    lua.execute("""
        Enum.PlayerSwingType={MainHand=0,OffHand=1,Ranged=2}
        RANGED_SPEED=2.3
        function UnitRangedDamage() return RANGED_SPEED end
    """)
    lua.execute("MODE.secret="+str(hidden).lower())
    chunk=lua.eval("function(s) return assert(loadstring(s)) end")((root/'DBagsAlerts/DBagsAlerts.lua').read_text(encoding="utf-8"))
    lua.execute("""
        local chunk=...; chunk("DBagsAlerts",{}); FIRE("PLAYER_LOGIN")
        local s=DBagsAlertsState.swing
        MODE.combat=true
        FIRE("PLAYER_SWING",2.4,0)
        assert(not s.ranged and s.dur==2.4,"melee timer")
        local started=s.start
        ADVANCE(0.2); FIRE("PLAYER_SWING",1.2,1)
        assert(s.start==started and s.dur==2.4,"offhand reset")
        FIRE("START_AUTOREPEAT_SPELL")
        assert(s.ranged and s.dur==0,"Shoot start invented a shot")
        FIRE("PLAYER_SWING",2.3,2)
        assert(s.ranged and s.dur==2.3,"gunshot timer missing")
        ADVANCE(0.5); TICK()
        RANGED_SPEED=1.15; FIRE("UNIT_RANGEDDAMAGE","player")
        local remaining=s.start+s.dur-GetTime()
        assert(math.abs(remaining-0.9)<0.001,"ranged haste rescale")
        FIRE("STOP_AUTOREPEAT_SPELL")
        assert(not s.ranged and s.dur==0,"stopped shot retained")
        FIRE("PLAYER_SWING",2.4,0)
        assert(not s.ranged and s.dur==2.4,"melee did not return")
        if MODE.secret then
            FIRE("PLAYER_SWING",UnitPower(),2)
            assert(s.ranged and s.dur==RANGED_SPEED,"hidden shot duration fallback")
            s.rangedSpeed=nil; RANGED_SPEED=nil
            FIRE("PLAYER_SWING",UnitPower(),2)
            assert(s.dur==0,"unknown gun speed reused melee speed")
        end
        FIRE("PLAYER_EQUIPMENT_CHANGED",18)
        assert(s.dur==0,"equipment swap retained old shot")
        for msg in pairs(ERRORS) do error(msg) end
    """,chunk)
    print("Ranged swing", "hidden" if hidden else "plain", "PASS")
