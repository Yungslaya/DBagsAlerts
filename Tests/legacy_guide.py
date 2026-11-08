from pathlib import Path
from lupa import lua51

root = Path(__file__).resolve().parents[1]
module = root / 'DBagsAlerts' / 'LegacyGuide.lua'
if not module.exists():
    module = Path(__file__).with_name('LegacyGuide.lua')
for cls in ('WARRIOR', 'PALADIN', 'DRUID', 'WARLOCK'):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('MODE_CLASS="%s"; CAST_IDS={}' % cls)
    harness = root / 'Tests' / 'harness.lua'
    if not harness.exists():
        harness = Path(r'C:\Users\brand\Documents\DBagsAlerts\Tests\harness.lua')
    lua.execute(harness.read_text(encoding='utf-8'))
    lua.execute('''
DBagsAlertsState={}; DBagsAlertsDB={}; LEVEL=30
function UnitLevel() return LEVEL end
Constants={LegacyConsts={LEGACY_TREE_ADVENTURE_ID=42}}
RANKS={0,0,0,0}; SPELLS={1225472,1225478,1225474,1225475}
CANBUY=true; MISSING=false; SECRET_RANK=false
C_Traits={
 GetConfigIDByTreeID=function(tree) assert(tree==42);return 99 end,
 GetTreeNodes=function(tree) assert(tree==42);return {1,2,3,4} end,
 GetNodeInfo=function(config,node)
  assert(config==99)
  if MISSING and node==1 then return nil end
  return {entryIDs={node},currentRank=SECRET_RANK and UnitPower() or RANKS[node],canPurchaseRank=CANBUY}
 end,
 GetEntryInfo=function(config,entry) return {definitionID=entry} end,
 GetDefinitionInfo=function(def) return {spellID=SPELLS[def]} end,
}
-- Any mutation is a test failure.
for _, name in ipairs({'PurchaseRank','RefundRank','CommitConfig','ResetTree','RollbackConfig','SetSelection'}) do
 C_Traits[name]=function() error('Protected talent mutation') end
end
''')
    lua.execute(module.read_text(encoding='utf-8'))
    lua.execute('''
assert(not DBagsAlertsState.legacyGuide.frame,'loaded before Blizzard panel')
LegacySystemFrame=newObjPublic(); LegacySystemFrame.TreePage=newObjPublic()
FIRE('ADDON_LOADED','Blizzard_LegacySystem')
local S=DBagsAlertsState.legacyGuide
assert(S.frame and S.nextID==1225472 and S.nextRank==1)
RANKS[1]=4;S.update();assert(S.nextRank==5)
RANKS[1]=5;S.update();assert(S.nextID==1225478)
RANKS[2]=5;S.update();assert(S.nextID==1225474)
RANKS[3]=5;S.update();assert(S.nextID==1225475)
RANKS[4]=1;S.update();assert(not S.nextID and S.head._text=='Leveling picks complete')
-- A refund returns the earlier recommendation; staged state is read directly.
RANKS[1]=3;S.update();assert(S.nextID==1225472 and S.nextRank==4)
CANBUY=false;S.update();assert(S.note._text:find('more points'))
MISSING=true;S.update();assert(not S.nextID and S.reason._text:find('unreadable'))
MISSING=false;MODE.secret=true;SECRET_RANK=true;S.update();assert(not S.nextID)
MODE.secret=false;SECRET_RANK=false
-- Dungeon route skips outdoor-only regen and keeps Well Rested prerequisite.
RANKS={0,0,0,0};S.mode._OnClick();assert(S.nextID==1225478)
RANKS[2]=5;S.update();assert(S.nextID==1225474)
assert(not S.rows[3].frame:IsShown() and not S.rows[4].frame:IsShown())
RANKS[3]=5;S.update();assert(not S.nextID)
S.mode._OnClick();assert(S.nextID==1225472)
LEVEL=60;S.update();assert(not S.nextID and S.head._text=='Leveling finished')
-- Safe when data or the namespace is unavailable, including older client shims.
C_Traits=nil;LEVEL=30;S.update();assert(not S.nextID)
local original=S.frame;FIRE('ADDON_LOADED','OtherAddon');assert(S.frame==original)
for msg in pairs(ERRORS) do error(msg) end
''')
    print(cls, 'Legacy ranks, ordering, refunds, missing/secret data, dungeon route, level 60, read-only checks PASS')
