# DBagsAlerts (work in progress)

Alerts, bars and helpers for **WoW: Forever** (Interface 16001): **Warrior, Paladin, Druid** (Bear, Cat, Balance and Restoration) **and Warlock** (Affliction, Demonology, Destruction). This was **ProtAlerts**.

> **WIP:** it's being built and tested while leveling. Expect changes and rough edges.

## What's new

- **1.0.5:** Tank-only healer checks: LOW MANA (default 30%), DRINKING, and a separate TOO FAR badge that can show alongside either warning. Compact gold-pulsing helper above your HUD. Automatic healer-role detection or manual name; separate toggles, threshold, Test button and status under /pa → Healer checks or /dbahealer. Handles native hidden mana/range values and low-level Protection Warriors. Shows SET HEALER when selection is unresolved. Pre-pull only; range is the native group check, not exact yards or line of sight. Restart WoW after updating.

- **1.0.4:** Separate glowing Cleave helper for 2+ engaged enemies, with a 40-rage buffer (60 with Shield Slam or heavy hits). Hides when queued; toggle Cleave in /pa. Added PA Retaliation: Battle Stance, then Retaliation, with auto-attack. Run /pa macros after /reload. The existing swing bar follows gun/bow/crossbow shots in blue and returns to melee on your next main-hand swing. Uses Forever's native swing type, ignores offhand swings, and handles ranged speed changes. Timing starts after a real shot event. /reload.

- **1.0.3:** Upkeep timer icons glow gold when missing or due for refresh. Rend lights at 30% remaining and stops glowing when reapplied. Other spells keep their existing refresh timing. Restored the single Battle Shout reminder above the helper icons in the floating HUD. Shield Block gets its own glowing BLOCK cue when your target is attacking you and the spell is ready and usable. Friendly players and NPCs now show in the target frame too; its right-click area fits the compact header. /reload.

- **1.0.2:** Warlock added. Warrior, Paladin, Druid and Warlock now share the floating HUD with no enclosing panel: next-spell cue beside the bars, small helper alerts, DoT countdowns, health/mana, shard count, and a cast bar that appears while casting. Idle target/DoT clutter stays hidden. Melee keeps slim threat/swing strips. Druid timers and resources follow Bear, Cat, caster and travel forms. Thin blue marker means queue your next spell; there is no guessed "safe to move" cue. Only learned spells show. `/pa oldlook` restores the previous layout. `/reload`.
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
