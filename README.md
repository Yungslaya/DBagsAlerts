# DBagsAlerts (work in progress)

Alerts, bars and helpers for **WoW: Forever** (Interface 16001): **Warrior, Paladin, Druid** (Bear, Cat, Balance and Restoration) **and Warlock** (Affliction, Demonology, Destruction). This was **ProtAlerts**.

> **WIP:** it's being built and tested while leveling. Expect changes and rough edges.

## Party cooldown repair

`/dbaparty` separates Show party cooldowns from Share my cooldowns. Sharing starts on in five-player dungeons, even when the sender's own icon display is off; switch it off to opt out. No traffic outside the dungeon scope.

No-addon members: readable casts and active defensive buffs seed estimated timers. Repeated buff scans do not restart a timer. Hidden identities are not decoded; missed uses, talents and resets can affect estimates.

Addon members: v2 messages carry readable cooldown snapshots and readiness, with a tagged own-cast estimate if live timing is restricted. Exact and estimated states stay distinct. Upgrade both clients to this build for the new messages; v1 reports are still accepted. `/dbaparty status` and `/dbadebug` include sync counters to diagnose missing reports or restricted casts.

## Starter setup (starter setup)

New installs keep the combat HUD, readable bars, spell cues, DoT timers and buff reminder. Optional target/cast replacement frames, cursor ring, aggro dots, stance/food/stone reminders, healer/party checks, party-distance screen flashes, pet replacement frame and follow helper start off. Native Blizzard frames stay visible. Custom sizing and sounds start off.

`/dba` → Display → Use starter setup, or `/dba starter`, previews this on an existing character. `/dba restore` restores the previous feature choices. `/reload` completes the frame change. Your macros, custom sizes/positions, timers and chosen follow name are retained. Existing users are never switched automatically.

Combat coverage: Protection Warrior; Protection Paladin with basic Retribution damage-mode cues; Feral Bear/Cat and Balance Druid; shared Affliction/Demonology/Destruction Warlock leveling cues. Restoration has basic upkeep/self-care, not party-healing guidance. Hunter has pet tools only; no Hunter rotation.

## What's new

- **1.0.17:** Wand timer stays visible while moving and turns green when ready. Fixed extra text on the cast bar. Restart WoW after updating.

- **1.0.16:** Starter setup with optional extras, preserved existing preferences, and reversible presentation presets. See the release notes for fixes and validation.

- **1.0.15:** Fixed the Druid DoT display querying aura IDs when Forever blocks aura access. Restricted mode uses readable own-cast timers; native auras resume when permitted. HUD layout changes, including form changes, wait until combat ends because secure helper buttons protect the shared anchor. Regression checks now forbid aura API calls while restricted and protected anchor changes in combat. `/reload` after updating; in-game confirmation pending.

- **1.0.14:** A small Legacy picks guide attaches beside the Legacy talent page. Shows current ranks, next recommended rank and a short reason; follows staged purchases and refunds without spending points. Outdoor leveling: Thrill of Adventure 5, Well Rested 5, Talented 5, Field Medicine 1. Switch to Dungeon leveling to prioritize Well Rested and Talented. Missing/hidden ranks show ?; level 60 stops leveling advice. Uses Blizzard's read-only trait API. Restart WoW once for the new file. Automated Legacy and four-class checks pass; the latest in-game debug report recorded zero errors. Exact Legacy panel appearance still needs in-game confirmation.

- **1.0.13:** Fixed the debug report window throwing a Lua error when opened or refreshed. Long reports now measure wrapped text correctly and remain scrollable. Regression checks pass; a fresh in-game report showed zero errors. `/reload` after updating. Old saved errors can be removed with `/dbadebug` → Clear log.

- **1.0.12:** Independent width, height and left/right/up/down controls for the floating HUD's target, health, power, player/target cast, threat and swing bars, plus pet-frame width/health height/position. Spell cues, DoTs, cooldown icons and buff/stance/food/stone reminders have their own size and position controls; icons stay square. In `/dba` → Sizes, enable Separate sizes and use `<` / `>` to choose one component at a time. Pet controls also expose width, health height and position, including on Hunters. Narrow pet frames wrap action buttons into rows; protected changes wait until combat ends. Shared drag anchor remains fixed. `/reload` after updating. Simulated checks pass; live visual confirmation pending.

- **1.0.11:** Fixed pet autocast right-clicks by delegating to Blizzard's native pet buttons instead of calling a protected function from addon Lua. Separate section sizes keep the shared HUD drag anchor fixed. Automated pet, sizing and layout checks pass; live confirmation pending. `/reload` after updating.

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
