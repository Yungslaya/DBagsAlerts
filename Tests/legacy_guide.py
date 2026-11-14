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
-- Two trees: Adventure (nodes 1-6) and Professions/Resourcefulness (nodes 7-12). Only the first four
-- talents have known spell IDs; the rest are found by name.
Constants={LegacyConsts={LEGACY_TREE_ADVENTURE_ID=42,LEGACY_TREE_PROFESSIONS_ID=43,SOMETHING_ELSE=7}}
RANKS={0,0,0,0,0,0,0,0,0,0,0,0}; SPELLS={1225472,1225478,1225474,1225475,9005,9006,9007,9008,9009,9010,9011,9012}
NAMES={[9005]="Field Guide",[9006]="Frequent Flier",[9007]="Working Overtime",[9008]="Bountiful Harvest",
 [9009]="Bartering",[9010]="Master Chef",[9011]="Dedicated Study",[9012]="Luremaster"}
CANBUY=true; MISSING=false; SECRET_RANK=false; ONE_TREE=false
C_Spell={GetSpellName=function(id) return NAMES[id] end}
C_Traits={
 GetConfigIDByTreeID=function(tree) assert(tree==42 or tree==43); if ONE_TREE and tree==43 then return nil end; return 50+tree end,
 GetTreeNodes=function(tree) assert(tree==42 or tree==43);return tree==42 and {1,2,3,4,5,6} or {7,8,9,10,11,12} end,
 GetNodeInfo=function(config,node)
  assert(config==92 or config==93)
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
RANKS[4]=1;S.update();assert(not S.nextID and S.head._text=='Picks complete')
-- A refund returns the earlier recommendation; staged state is read directly.
RANKS[1]=3;S.update();assert(S.nextID==1225472 and S.nextRank==4)
CANBUY=false;S.update();assert(S.note._text:find('more points'))
MISSING=true;S.update();assert(not S.nextID and S.reason._text:find('unreadable'))
MISSING=false;MODE.secret=true;SECRET_RANK=true;S.update();assert(not S.nextID)
MODE.secret=false;SECRET_RANK=false
-- Dungeon route skips outdoor-only regen and keeps Well Rested prerequisite.
RANKS={0,0,0,0,0,0,0,0,0,0,0,0};S.mode._OnClick();assert(S.nextID==1225478 and S.mode._text:find('Dungeon leveling',1,true))
RANKS[2]=5;S.update();assert(S.nextID==1225474)
assert(not S.rows[3].frame:IsShown() and not S.rows[4].frame:IsShown())
RANKS[3]=5;S.update();assert(not S.nextID)
LEVEL=60;S.update();assert(not S.nextID and S.head._text=='Leveling finished' and S.reason._text:find('Gathering and gold',1,true))
LEVEL=30
-- Leveling + professions (Method): Thrill, Working Overtime, Field Guide, Field Medicine 2/2, Frequent Flier.
RANKS={0,0,0,0,0,0,0,0,0,0,0,0};S.mode._OnClick();assert(S.mode._text:find('Leveling + professions',1,true))
assert(S.nextID==1225472 and S.rows[5].frame:IsShown() and not S.rows[6].frame:IsShown())
RANKS[1]=5;S.update();assert(S.nextID=='Working Overtime' and S.head._text=='Next: Working Overtime' and S.nextRank==1)
RANKS[7]=5;S.update();assert(S.nextID=='Field Guide')
RANKS[5]=3;S.update();assert(S.nextID==1225475 and S.rows[4].rank._text=='0/2')
RANKS[4]=2;S.update();assert(S.nextID=='Frequent Flier')
RANKS[6]=1;S.update();assert(not S.nextID and S.head._text=='Picks complete')
LEVEL=60;S.update();assert(S.head._text=='Picks complete','no Talented in this build, so level 60 changes nothing');LEVEL=30
-- Gathering and gold (Method's gatherer build), six picks, works at any level.
RANKS={0,0,0,0,0,0,0,0,0,0,0,0};S.mode._OnClick();assert(S.mode._text:find('Gathering and gold',1,true))
assert(S.nextID=='Bountiful Harvest' and S.rows[6].frame:IsShown())
RANKS[8]=5;S.update();assert(S.nextID=='Bartering')
RANKS[9]=2;S.update();assert(S.nextID=='Master Chef')
RANKS[10]=5;S.update();assert(S.nextID=='Dedicated Study')
RANKS[11]=1;S.update();assert(S.nextID=='Luremaster')
-- "The Quick and the Dead" is in a tree this fake game does not expose: say so, do not guess.
RANKS[12]=2;S.update();assert(not S.nextID and S.rows[6].rank._text=='?/2' and S.reason._text:find('unreadable',1,true))
-- A tree the game will not open leaves its picks unreadable, never zero.
ONE_TREE=true;S.update();assert(not S.nextID and S.rows[1].rank._text=='?/5');ONE_TREE=false
-- The old dungeon switch still means the dungeon build; the button then goes round to outdoor again.
DBagsAlertsDB.legacyGuide={dungeons=true};RANKS={0,0,0,0,0,0,0,0,0,0,0,0};S.update()
assert(S.nextID==1225478 and DBagsAlertsDB.legacyGuide.mode=='dungeon' and DBagsAlertsDB.legacyGuide.dungeons==nil)
S.mode._OnClick();S.mode._OnClick();S.mode._OnClick();assert(S.nextID==1225472 and S.mode._text:find('Outdoor leveling',1,true))
LEVEL=60;S.update();assert(not S.nextID and S.head._text=='Leveling finished')
-- Safe when data or the namespace is unavailable, including older client shims.
C_Traits=nil;LEVEL=30;S.update();assert(not S.nextID)
local original=S.frame;FIRE('ADDON_LOADED','OtherAddon');assert(S.frame==original)
for msg in pairs(ERRORS) do error(msg) end
''')
    print(cls, 'Legacy ranks, ordering, refunds, missing/secret data, four builds, name lookup, level 60, read-only checks PASS')
