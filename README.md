# DBagsAlerts (work in progress)

Alerts, bars and helpers for **WoW: Forever** (Interface 16001): **Warrior, Paladin, Druid** (Bear, Cat, Balance and Restoration) **and Warlock** (Affliction, Demonology, Destruction). This was **ProtAlerts**.

> **WIP:** it's being built and tested while leveling. Expect changes and rough edges.

## What's new

- **1.0.2:** Warlock added. New compact HUD: one next-spell cue, small helper alerts, DoT countdowns, health/mana, shard count, and an attached cast bar. Thin blue marker means queue your next spell; there is no guessed "safe to move" cue. Only learned spells show. `/pa oldlook` restores the previous layout. `/reload`.
- **1.0.1:** Racials: your race's combat racials go on the cooldown row. Elune's Light, Blood Fury and Berserking light up on tough fights, and War Stomp stops casts. /reload.
- **1.0.0:** Renamed from ProtAlerts to DBagsAlerts. **Druid added:** the alerts follow your form (Bear, Cat, caster), and the bar shows rage, energy plus combo points, or mana. Your old ProtAlerts settings carry over, and old ProtAlerts turns itself off. Full WoW restart.
- **0.9.13:** Weapon stone button: click to sharpen (blades) or weight (maces) your weapon; grey NO STONE when you have none (can turn off). /reload.
- **0.9.12:** EAT button fix: food is re-checked when WoW hadn't loaded it yet; new /pa food check. /reload.
- **0.9.11:** Demoralizing Shout now shows early in every fight, not only on packs and elites. /reload.
- **0.9.10:** Aggro dots only run while you are in combat. /reload.
- **0.9.9:** Aggro dot over every mob in a fight, not just your target. /reload.

## What it does

- Big icons for what matters right now: danger (low HP, loose mobs, taunt, stop a cast), next button, buffs and debuffs to refresh.
- **Druid:** Bear (Primal Bite, Lacerate/Swipe, Maul, Demo Roar, Faerie Fire), Cat (Ravage from Prowl, Rip, Rake, Claw/Shred, Shifting Power), caster (Moonfire, Insect Swarm, Wrath, Hurricane), Mark of the Wild + Thorns, Rejuvenation before a pull, Innervate. From the Icy Veins WoW Forever druid guides.
- **Warlock:** Corruption, Bane of Agony (never early), Immolate, Siphon Life on mobs that will live; free Shadow Bolt (Nightfall); Conflagrate, Shadowburn, Searing Pain brand; Drain Life when low; Drain Soul on a dying mob when shards are low; Life Tap when mana is low and health is fine; pet out (unless Demonic Sacrifice), Demon Armor, Soul Link, curse on elites, Healthstone (eat it when low, make one when you have none). From the Icy Veins WoW Forever warlock guides.
- Health, power, threat and swing timer bars.
- Emergency cooldown row with proc glow.
- Target frame with cast bar. Right-click it for the normal menu.
- Aggro dot over every mob in a fight: green = it's on you, yellow = about to lose it, red = it's not hitting you.
- EAT button (Well Fed +5% XP), weapon stone button (Warrior, Paladin), cursor ring.
- Makes your macros in game: `/pa macros`.

## Install

Easiest: the [Dragbags Addon Updater](https://github.com/Yungslaya/DragbagsAddonUpdater). Or copy the `DBagsAlerts` folder into `World of Warcraft\_forever_\Interface\AddOns\`, then fully restart WoW.

Coming from ProtAlerts? Install DBagsAlerts, start WoW once (it turns ProtAlerts off for you), then you can delete the old `ProtAlerts` folder.

## Commands

- `/pa` or `/dba` - settings
- `/pa macros` - make the macros
- `/pa unlock` - move it
- `/pa food` - why the EAT button is or isn't showing

## Rules it follows

Display only. It never presses buttons, casts or moves for you. It only shows what Blizzard's addon API lets it read.

## Credits

Swing timer technique from AKForeverCombatTimers (MIT). Textures are made by the scripts in `tools/`.
