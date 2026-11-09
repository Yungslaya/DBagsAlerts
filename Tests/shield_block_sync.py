from pathlib import Path
import runpy
ctx=runpy.run_path(str(Path(__file__).with_name('party_cooldowns.py')))
tank,healer,deliver=ctx['tank'],ctx['healer'],ctx['deliver']
for client in (tank,healer):
 client.execute('DUNGEON=true;DBagsAlertsDB.partyDefensives.enabled=true;DBagsAlertsDB.partyDefensives.share=true;MODE.combat=false;FIRE("PLAYER_REGEN_ENABLED");ADVANCE(1);TICK();TICK();OUT={}')
tank.execute(r"""
 local s=DBagsAlertsState.partyCooldowns
 MODE.combat=true
 local original=C_SpellBook.GetNumSpellBookSkillLines
 C_SpellBook.GetNumSpellBookSkillLines=function() error('spellbook scanned in combat') end
 local count=#s.known
 FIRE('SPELLS_CHANGED');ADVANCE(1);TICK();TICK()
 assert(#s.known==count and count>0,'combat stance event erased known spells')
 -- Recover a real defensive ID even if the spellbook snapshot missed it.
 local getName=C_Spell.GetSpellName
 C_Spell.GetSpellName=function(id) if id==2565 then return 'Shield Block' end return getName(id) end
 TESTCD[2565]={isActive=true,isOnGCD=false,startTime=GetTime(),duration=5}
 FIRE('UNIT_SPELLCAST_SUCCEEDED','player','cast',2565)
 ADVANCE(1.1);TICK();TICK()
 local found
 for _,e in ipairs(s.own) do if e.name=='Shield Block' then found=e end end
 assert(found and found.status=='C' and found.remaining>0,'Shield Block not shared in combat')
 C_SpellBook.GetNumSpellBookSkillLines=original
""")
healer.execute(r"""
 MODE.combat=true
 local original=C_Spell.GetSpellName
 C_Spell.GetSpellName=function(id) if id==2565 then return nil end return original(id) end
""")
deliver(tank,healer,'Tank')
healer.execute(r"""
 local found
 for _,e in ipairs(DBagsAlertsState.partyCooldowns.get('party1')) do
  if e.id==2565 then found=e end
 end
 assert(found and found.status=='C' and found.remaining>0,'receiver lost in-combat Shield Block')
 local row=DBagsAlertsState.partyDefensives.rows.party1
 assert(row:IsShown(),'combat cooldown row hidden')
 local visible=false
 for _,icon in ipairs(row.icons) do if rawget(icon,'entry') and icon.entry.id==2565 and icon:IsShown() then visible=true end end
 assert(visible,'Shield Block icon missing in combat')
 for msg in pairs(ERRORS) do error(msg) end
""")
tank.execute('for msg in pairs(ERRORS) do error(msg) end')
print('Combat spellbook deferral and Shield Block sender-to-healer sync PASS')

# Forever surname display separators must match complete party identities.
a=ctx['client']('Royy Kentt','Snehorn Dragonborn','WARRIOR','PRIEST')
b=ctx['client']('Snehorn Dragonborn','Royy Kentt','PRIEST','WARRIOR')
deliver(a,b,'Royy-Kentt')
b.execute('assert(DBagsAlertsState.partyCooldowns.stats.received>0,"surname separator prevented synchronization")')
print('Forever surname sender matching PASS')
