# ProtAlerts (work in progress)

Tank helper for **WoW: Forever** (Interface 16001). Protection Warrior and Paladin.

> **WIP:** it's being built and tested while leveling. Expect changes and rough edges.

## What it does

- Big icons for what matters right now: danger (low HP, loose mobs, taunt, kick), next button, buffs/debuffs to refresh (pandemic window).
- Health, rage/mana, threat and swing timer bars.
- Emergency cooldown row with proc glow.
- Target frame with cast bar. Right-click it for the normal menu.
- Aggro dot over your target: green = it's on you, yellow = about to lose it, red = it's not hitting you.
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
