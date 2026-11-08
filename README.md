# DBagsAlerts (work in progress)

Alerts, bars and helpers for **WoW: Forever** (Interface 16001): **Warrior, Paladin, Druid** (Bear, Cat, Balance and Restoration) **and Warlock** (Affliction, Demonology, Destruction). This was **ProtAlerts**.

> **WIP:** it's being built and tested while leveling. Expect changes and rough edges.

## What's new

- **1.0.10:** Rebuilt settings into Display, Frames, Sizes, Reminders, Alerts, Class settings, Group and Tools pages with native WoW buttons/borders. Added an optional target-of-target name/health strip, off by default. Separate section sizes are also off by default; the floating HUD reflows target, player bars, spell cues, DoTs, casts and cooldown icons independently. Helpers, party icons and cursor size have controls; pet sizing remains in Pet controls. Existing HUD scale is retained. /reload, then /dba. Tested with simulated plain/hidden values; live visual confirmation pending.

- **1.0.9:** Five-player dungeon party cooldowns now work without other players installing DBagsAlerts. Dim class/level spell placeholders become estimated countdowns after a public observed cast; RDY~ means estimated ready, RDY means confirmed from a current addon report, UP means active buff. No generic question-mark tiles. Unknown training/talents are not claimed ready. Optional reports improve accuracy. Existing public observations stay visible in combat; blocked aura reads cannot hide the cooldown row. /dbaparty has a Placeholders toggle. Baseline timers may differ with talents, resets and missed casts. Restart WoW for the new modules. Debug adds Record debug log, Show Lua errors, and a copyable bounded report. Run /dbadebug on before reproducing a problem, then /dbadebug to select and copy the report.

- **1.0.8:** Druid timers now display your actual current-target harmful auras through native icons and countdowns, including combat-restricted aura fields. No spell-name lookup or target GUID is needed for this row. Existing DoTs survive target and form changes. Readable refresh glows remain; hidden timing is displayed without guessing a refresh window. Automated restricted-aura tests pass; live confirmation is pending. `/reload` after updating.

- **1.0.7:** DoT timers restore from your own current-target auras after switching targets, with immediate refresh/removal updates and a short cache. Added Retaliation to the Warrior cooldown row. Dungeon defensive icons now recognize readable Forever defensive buffs that lack the native category and find nested party frames. These icons show active buffs, not ready cooldowns. `/dbaparty status` reports tracker status. Automated checks pass; live confirmation is pending. `/reload` after updating.

- **1.0.6:** Pet support: independent movable pet health/resource frame, right-click pet menu, 10 native action slots, right-click autocast and Shift-drag rearranging. Warlock demon summons/Health Funnel and Hunter Call/Revive/Mend/Feed/Train/Dismiss buttons show only when learned. Hunter happiness, loyalty, training points and food tooltip; Growl/Torment reminder in dungeons. /dbapet opens settings, including on Hunters. Follow status is independently draggable above center; lock/move controls in /dbafollow. Cleaner, draggable settings with one window at a time and scrolling. Party defensive icons for five-player dungeons. WAKE UP uses confirmed 40-yard measurements on your map, explicitly hides when the majority is nearby, and waits two seconds before showing; slow red edges pause during settings. Set a timed pause key and 10–300 second duration in /dbagroup. Follow buddy now calls Blizzard's native FollowUnit only from your keypress; set the name and key in /dbafollow, with confirmed/failed/stopped status. Druid Cat/Bear resources no longer trigger healer LOW MANA. Target cast bar stays above the target header. Restart WoW for new modules/bindings.

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
- `/dbapet` - pet frame and controls (including Hunter pet support; no Hunter rotation)
- `/dbafollow` - follow name, key and movable status
- `/dbagroup` - group distance warning and pause key
- `/dbaparty` - party defensive placeholders, observed cooldowns and active buffs in five-player dungeons
- `/dbadebug` - error recording, Show Lua errors and copyable report
- `/dbadebug on` - start bounded debug recording
- `/dbadebug errors on` - show native Lua error popups

## Rules it follows

Alerts use Blizzard's addon API. Pet commands, spell buttons and Follow require your click or keypress; the addon never starts them on a timer. Follow uses the game's normal follow behavior.

## Credits

Swing timer technique from AKForeverCombatTimers (MIT). Textures are made by the scripts in `tools/`.


## Party cooldown estimates

Other players do not need the addon. Class spell placeholders are filtered by level and stay unconfirmed until observed. Public successful casts start base-cooldown estimates; higher ranks match by readable spell name. RDY~ means estimated ready, not confirmed availability. Training, talents, resets, pet availability, Forbearance and missed/restricted casts can affect actual use. Current self-reports from another DBagsAlerts user can improve accuracy, but are optional. A generic question-mark icon is never used for an absent addon.

Baseline sources: [Icy Veins Forever Warrior guide](https://www.icy-veins.com/wow-forever/protection-warrior-tank-pve-rotation-cooldowns-abilities), and its Forever spell database entries for [Divine Protection](https://db.icy-veins.com/wow-forever/spells/498), [Barkskin](https://db.icy-veins.com/wow-forever/spells/22812), [Death Coil](https://db.icy-veins.com/wow-forever/spells/6789), [Deterrence](https://db.icy-veins.com/wow-forever/spells/19263), [Fade](https://db.icy-veins.com/wow-forever/spells/10942), [Nature's Swiftness](https://db.icy-veins.com/wow-forever/spells/16188), [Ice Block](https://db.icy-veins.com/wow-forever/spells/11958) and [Evasion](https://db.icy-veins.com/wow-forever/spells/5277).

Debug records are opt-in and saved in DBagsAlertsDB.debugLog (30 grouped errors and 40 recent events). They include stack traces and addon/game context, with no chat-message collection or secret-value decoding. Error capture can identify other addons too; a generic error warning alone does not identify its source. Disabling recording restores the previous error handler when safe. Guarded timer failures back off and report once instead of throwing every frame.
