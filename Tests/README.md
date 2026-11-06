# Addon checks

Install Python and `lupa`, then from the repo run:

```
python Tests/run.py Tests/harness.lua
```

Checks Warrior, Paladin, Druid and Warlock with ordinary and hidden combat values. Also checks the early-level Warlock spellbook, cast duration text, hidden queue timing, spell placeholders, and old/new layout switches on every class. Druid checks cover Cat, Bear, travel and caster, including a travel-to-caster switch with the same mana power type. A caught addon error fails the run.

The fake game catches Lua errors and logic regressions. It does not confirm real server timing or the exact in-game appearance. No early-movement guarantee is made.
