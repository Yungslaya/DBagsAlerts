# ProtAlerts (work in progress)

Tank helper for **WoW: Forever** (Interface 16001). Protection Warrior and Paladin.

> **WIP:** it's being built and tested while leveling. Expect changes and rough edges.

## What's new

- **0.9.11:** Demoralizing Shout now shows early in every fight, not only on packs and elites. /reload.
- **0.9.10:** Aggro dots only run while you are in combat. /reload.
- **0.9.9:** Aggro dot over every mob in a fight, not just your target. /reload.
- **0.9.8:** The dot over your target shows aggro instead of range. /reload.
- **0.9.7:** EAT button when you're missing Well Fed (+5% XP) and carry food. /reload.
- **0.9.6:** Flashing DEFENSIVE stance reminder; Charge macro knows Vanguard. /reload, then /pa macros.

## What it does

- Big icons for what matters right now: danger (low HP, loose mobs, taunt, kick), next button, buffs/debuffs to refresh (pandemic window).
- Health, rage/mana, threat and swing timer bars.
- Emergency cooldown row with proc glow.
- Target frame with cast bar. Right-click it for the normal menu.
- Aggro dot over every mob in a fight: green = it's on you, yellow = about to lose it, red = it's not hitting you.
- Cursor ring.
- Makes your tank macros in game (stance dancing, mouseover taunt/kick, /startattack).

## Install

Copy the `ProtAlerts` folder into `World of Warcraft\_forever_\Interface\AddOns\`, then fully restart WoW.

## Commands

- `/pa` - settings
- `/pa macros` - make the macros
- `/pa unlock` - move it
- `/pa range` - show what the range check sees

## Rules it follows

Display only. It never presses buttons, casts or moves for you. It only shows what Blizzard's addon API lets it read.

## Credits

Swing timer technique from AKForeverCombatTimers (MIT). Textures are made by the scripts in `tools/`.
