# Battle Buddy changes (formerly DBagsAlerts)

Every released version, newest first.

## 1.2.2 (2026-11-20)

- **Warlock DoT timers fixed.** A DoT you cast on the mob under your mouse is now timed on that mob, not your target. Before, your target could show a timer for a DoT that wasn't there, and the real mob showed none.
- **DoT numbers match the game.** Timers learn each DoT's real length when the game shows it, and round like the game's own numbers, so they no longer run a second behind the nameplates.
- **Seen DoTs stay lit.** If the game shows your DoT on the target but not its time, the icon stays lit instead of grey.
- **Mouseover macros.** Type `/bbuddy macros` to update them. Shadow Bolt, Immolate, Searing Pain, Conflagrate, Drain Life, Drain Soul and Agony now hit the mob under your mouse, or your target if there is none. Your pet stays on your target. The Agony macro works whether your game calls it Bane or Curse of Agony.

Type `/reload` after updating.

## 1.2.1 (2026-11-20)

- **Warlock between pulls.** Out of combat, clickable rows under your mana bar show what to do before the next pull. One click does it.
- **EAT** when your health is low. It eats food from your bags, or says **NO FOOD**.
- **LIFE TAP** when your mana is low and your health is fine.
- **HEAL PET** casts Health Funnel. **MAKE STONE** when you have no Healthstone. **0 SHARDS** means Drain Soul your next kill.
- The rows hide in combat, when mounted and when dead. Type `/bbuddy why` to see what each check sees.

Type `/reload` after updating.

## 1.2.0 (2026-11-18)

- **All nine classes.** Mage, Hunter, Rogue and Shaman now get the next button to press, danger cues and buff reminders, like the other classes. Mage: procs, finishers and your filler spell. Hunter: Hunter's Mark, Serpent Sting, Summon Hawk, Aimed Shot and Mend Pet. Rogue: Stealth openers, Slice and Dice, Eviscerate at 5 points and poison reminders. Shaman: Stormstrike, shocks, free Lightning Bolts, shields and weapon buffs. These are new, so tell us what feels wrong.
- **Priest in combat.** Priests now also get shield, self-heal, Shadow Word: Pain, Mind Blast and filler cues during a fight, when the game hides exact health numbers from addons.
- **Five more languages.** In German, French, Spanish, Russian and Simplified Chinese games, cues show the game's own spell names, and cue words like LOW HP and the main Settings lines are translated. Chat messages and some smaller windows are still in English. Only English has been tested in the game. If something looks wrong in your language, please report it.
- **New look.** The Settings window and the Legacy picks panel now look like a big WoW tooltip, the same as ProfessionPal, Market Ledger and Savings Pal.
- **Voice alerts.** Battle Buddy can say danger alerts out loud, like "low health". Off until you tick **Alert voice** in Settings or type `/pa voice`. It uses the game's own text-to-speech.
- **Trainer reminder.** When you reach an even level, it reminds you to visit your class trainer for new spell ranks, and again when you walk into town, until you open a trainer. Type `/bbtrain` to turn it off.
- **Warlock: Wrack.** Affliction Warlocks at level 51 and up get a WRACK cue once Corruption and your Bane are on a target that will live a while. Low health still shows Drain Life first.

Fully restart WoW after updating (a new file was added).

## 1.1.1 (2026-11-17)

- **Update messages** now only come from real CurseForge releases, so you never hear about a version that isn't out yet.

Type `/reload` after updating.

## 1.1.0 (2026-11-16)

- **New name: Battle Buddy.** DBagsAlerts is now called Battle Buddy. It's the same addon with the same settings, so there's nothing to set up again. A one-time popup explains this after you update.
- New command `/bbuddy`. The old `/dba` and the other commands still work.
- **Taunt and Mocking Blow icons** above nameplates no longer show while those spells are on cooldown.
- **Update notices.** If someone in your guild or group has a newer version, you get one message saying an update is out in the CurseForge app. Only version numbers are shared, and nothing is sent in combat.

Fully restart WoW after updating (a new file was added).

## 1.0.23 (2026-11-15)

- **Follow buddy:** the FOLLOWING text no longer gets stuck on screen after follow ends. It clears when you stand still for 3 seconds, when your buddy is out of sight, or after a loading screen.
- Pressing your follow key while it says FOLLOWING now follows again, so a follow that quietly broke is fixed with one press.

Type `/reload` after updating.

## 1.0.22 (2026-11-15)

- **Rend fix:** with Rend on two mobs, tabbing between them now shows each mob's own Rend timer, even in combat. The same fix keeps Sunder stacks and Druid and Warlock DoT timers on the right mob.
- **Revenge** leads your attack cue on one enemy. **Thunder Clap** takes the lead when a pack is nearby.
- **Sunder Armor** asks for a refresh in its last 5 seconds, even at your stack goal.
- **Demoralizing Shout** follows the real debuff on your target when the game shows it, with a reminder 5 seconds before it runs out.
- **Revenge** and **Heroic Strike** stay quiet when you can't use them.
- **Bloodrage** stays quiet when your health is low (below your low-health warning, at least 35%).

Type `/reload` after updating.

## 1.0.21 (2026-11-14)

- **Legacy picks** checked against Method, Icy Veins, Mobalytics and Wowhead. The leveling picks are unchanged.
- Two new builds on the button at the top: **Leveling + professions** and **Gathering and gold**.
- The panel now reads every Legacy tree, and at level 60 it tells you which build to switch to.

Advice only. It never buys or changes a talent. Type `/reload` after updating.

## 1.0.20 (2026-11-10)

Added Priest support, Warrior recovery icons and an optional combat-only character marker. Type /reload after updating.

## 1.0.19 (2026-11-09)

Recover from temporary cooldown message limits and pause group distance warnings in cities and resting areas. Update and /reload.

## 1.0.18 (2026-11-08)

Party cooldown test update



- Keeps defensive tracking intact through combat stance changes.

- Improves Shield Block sharing and party-name matching.

- Adds connection details to /dbadebug for troubleshooting missing cooldowns.



Update everyone testing together, then /reload outside combat. If cooldowns still fail during a pull, copy /dbadebug from both players after using Shield Block.

## 1.0.17 (2026-11-08)

- Added a wand timer for Warlock, Mage and Priest.
- The timer keeps counting while you move and turns green when your wand is ready.
- Fixed "Opening - No Text" on the cast bar.

Restart WoW after updating.

## 1.0.16 (2026-11-08)



- Quieter first-install setup: core combat HUD stays on; extra frames, reminders, cursor/aggro tools and party warnings are opt-in. Existing settings are preserved.

- Starter setup and Restore my setup let existing users try the new defaults without losing custom geometry, macros or spell history.

- Party cooldown sync v2 separates sharing from showing icons. Matching addon clients exchange readable live cooldowns even when the sender hides their own icons. Hidden timing uses clearly labeled estimates.

- Players without the addon can be tracked from readable casts and defensive buffs. Estimates can differ with talents, resets or missed events.

- Removed the restricted combat-log subscription that triggered a blocked-action popup on reload. Startup protected-action warnings now remain visible in the debug report.

- /dbaparty status and /dbadebug include sync diagnostics.



Update, then /reload. Everyone using live sync needs this updated build. Party helpers operate in five-player dungeons.

## 1.0.15 (2026-11-08)



- Fixed the Druid DoT HUD error: **Auras cannot be accessed when secret while tainted by DBagsAlerts**.

- Checks aura access before requesting aura IDs. While access is restricted, the display uses readable timers from your own casts. Native aura displays resume when access is allowed.

- Fixed blocked HUD resizing and positioning during Druid form changes in combat. Layout changes now wait until combat ends, then apply the latest form.



### Updating



Type **/reload** after updating. In **/dbadebug**, use **Clear log** to remove errors saved before this fix.

## 1.0.14 (2026-11-08)



- Added a small **Legacy picks** guide beside the Legacy talent window.

- Shows your current ranks, the next recommended rank, and a short explanation.

- Outdoor leveling order: **Thrill of Adventure 5/5 → Well Rested 5/5 → Talented 5/5 → Field Medicine 1/2**.

- Switch to **Dungeon leveling** to prioritize Well Rested and Talented. Thrill of Adventure does not work inside dungeons.

- Recommendations follow point changes and refunds. Unavailable ranks show **?** instead of guessing.

- At level 60, the guide explains that Talented no longer helps and stops recommending leveling picks.

- Advice only: you choose and apply every talent yourself.



### How to use



Restart WoW fully after installing this update because it adds a new file. Open **Legacy → talent trees**; the guide appears beside the window.

## 1.0.13 (2026-11-08)



- Fixed the debug window Lua error when opening or refreshing a report.



- Long reports resize correctly for scrolling; short reports shrink back to the minimum height.



### Update



Update, then `/reload`.



Debug history survives reloads. Use `/dbadebug` → Clear log to remove old saved errors.

## 1.0.12 (2026-11-08)



- Independent width, height and left/right/up/down controls for target, health, power, both cast bars, threat and swing timer in the floating HUD.



- Pet frame width, health height and position controls, also accessible on Hunters through `/dbapet`. Narrow frames wrap pet buttons into rows; protected changes wait until combat ends.



- Separate size and position controls for spell cues, DoT timers, cooldown icons and buff/stance/food/weapon-stone reminders. Icons stay square.



- Sizes settings show one selected component at a time. The shared HUD drag anchor stays fixed.



### Use it



Update, then `/reload`. Open `/dba` → Sizes, enable Separate sizes, and use `<` / `>` to choose the component.

## 1.0.11 (2026-11-08)



- Pet action right-clicks use Blizzard's native pet buttons to toggle autocast, avoiding the protected call in addon Lua.



- Individual size sliders keep the shared HUD drag anchor fixed, so resizing a section does not resize and shift the parent anchor.



### Update



Update, then type `/reload` in game.

## 1.0.10 (2026-11-08)

- Settings are organized into Display, Frames, Sizes, Reminders, Alerts, Class settings, Group and Tools pages.

- Familiar WoW buttons and borders, readable labels and consistent spacing replace the long settings wall.

- Frames > Target of Target adds an optional name and health strip. Off by default.

- Sizes > Separate sizes lets the floating HUD resize the target, health/power bars, spell cues, debuff timers, cast bars and cooldown row independently. Off by default; your existing whole-HUD scale is retained.

- Layout spacing adapts to larger sections. Helper reminders, party icons, cursor and pet size controls are available too.



### Update

Update, then /reload. Open /dba for settings.

## 1.0.9 (2026-11-08)

### Party defensive tracker

- Other party members do not need DBagsAlerts installed.

- Dim spell icons are class/level placeholders. Training and talents are unconfirmed until observed.

- A public observed cast starts a base-cooldown estimate, including in combat. Higher ranks match by spell name.

- RDY~ means estimated ready; RDY means confirmed from a current self-report; UP means an active buff. Estimates may differ with talents, resets and missed/restricted casts.

- Optional addon reports improve accuracy. Generic question-mark icons are removed. Toggle Placeholders under /dbaparty.

- Retains public cooldown observations across combat restrictions. Failed active-aura reads cannot hide the entire cooldown row.



### Debug tools

- /dbadebug opens Record debug log and Show Lua errors options plus a copyable report.

- /dbadebug on starts bounded recording. Reproduce the issue, then /dbadebug and Select report, Ctrl+C.

- /dbadebug errors on turns on WoW's Lua error display; errors off disables it.

- Reports group repeated errors and include stack traces, combat/instance context and recent relevant events.

- Timer update guards back off after failures instead of throwing every frame.



The generic too-many-errors popup does not identify which addon caused it.



### Install

Update, then fully restart WoW for the new modules.

Only the person viewing the tracker needs the addon.

## 1.0.8 (2026-11-08)

- Druid DoT row now uses your actual current-target debuff icons and Blizzard's native countdowns.

- Works with hidden aura names/timing without comparing those values or relying on target GUIDs.

- Your existing DoTs remain visible after switching away and back, including after a form change.

- Readable refresh glows remain. Restricted timing is displayed without guessing its refresh window.



### Update

Update, then /reload.

Apply two DoTs, switch to another target, then switch back. Check that both countdowns return.

## 1.0.7 (2026-11-08)

- DoT timers restore from your own existing target debuffs when switching back. Refreshes and removals update immediately; aura reads are cached.

- Retaliation is tracked in the Warrior cooldown row.

- Dungeon party defensive icons recognize readable Forever defensive buffs without the native category and locate nested party frames.

- /dbaparty status reports whether frames and active defensives are found.



Party defensive icons show active buffs, not ready abilities or cooldowns after those buffs end.



### Update

Update, then /reload.

## 1.0.6 (2026-11-08)

- Pet health/resource frame, native pet commands and movable layout. Warlock demon and Hunter care buttons show only learned spells. Hunter pet support does not include a Hunter rotation.

- Follow uses your keypress and the game's normal follow command. Set the buddy and key in /dbafollow; drag the status or lock it in settings.

- WAKE UP uses confirmed same-map distances, waits two seconds, and has slower red edges. Set a temporary pause key in /dbagroup.

- Active personal defensive icons next to native party frames in five-player dungeons.

- Cleaner draggable settings, one window at a time, and scrolling.

- Fixed Druid form resources triggering healer LOW MANA and moved the target cast bar away from alert icons.



### Install

Update, then fully restart WoW for the new files and bindings.



Pet settings: /dbapet. Follow: /dbafollow. Group warning: /dbagroup. Party defensives: /dbaparty.

## 1.0.5 (2026-11-08)

- Tank-only pre-pull healer helper, styled to match the HUD: LOW MANA or DRINKING, with a separate TOO FAR badge. Drinking and distance warnings can appear together.

- Automatic detection of a single marked healer, or enter your healer's name manually. Unresolved selection shows SET HEALER instead of staying silent.

- Default mana threshold is 30%, adjustable in /pa → Healer checks or /dbahealer. Separate drinking/range toggles and a Test button.

- Fixed low-level Protection Warrior eligibility and hidden-mana display. Hidden range flags go directly to native display gates.

- /dbahealer status prints what the healer checker is doing.



### Update

Extract DBagsAlerts.zip into your Forever Interface/AddOns folder. Restart WoW after updating to load the new healer module. Configure it under /pa → Healer checks.



### Limits

These warnings hide during combat. Distance uses the game's group-range check; it does not measure exact yards or check line of sight. Drinking detection requires an accessible Drink aura.



Work in progress.

## 1.0.4 (2026-11-07)

- Separate glowing CLEAVE helper for two or more nearby engaged enemies. Shows with at least 40 rage, or 60 with Shield Slam learned or heavy incoming hits. Hides when queued; toggle Cleave in /pa.

- Added PA Retaliation to the Warrior macro generator: starts auto-attack, switches to Battle Stance, then casts Retaliation on the next press if a stance change was needed.

- Existing swing bar tracks ranged shots in blue, then returns to melee on a main-hand swing. Ignores offhand swings, handles ranged speed changes and resets on weapon swaps. Shot timing begins after a real shot event.



### Update

Extract DBagsAlerts.zip into your Forever Interface/AddOns folder. Type /reload, then /pa macros to create the new Retaliation macro.

## 1.0.3 (2026-11-07)

- Dedicated glowing BLOCK reminder when your target is attacking you and Shield Block is ready and usable. It stays separate from your next attack and other helper icons.

- Friendly players and NPCs now appear in the target frame, with health and the normal right-click menu. The click area fits the compact header.

- Upkeep timer icons glow when missing or due for refresh. Rend lights at 30% remaining and stops glowing when reapplied.

- Restored the single Battle Shout reminder in the floating HUD, including out of combat.



### Update

Extract DBagsAlerts.zip into your Forever Interface/AddOns folder. Type /reload after updating.

## 1.0.2 (2026-11-06)



#### A cleaner layout for every class

- Warrior, Paladin, Druid, and Warlock now use a floating layout that leaves the game visible.

- Removed the enclosing box, purple title stripe, large gold glows, and empty cast-bar background.

- One large next-spell cue sits beside your bars. Smaller icons handle danger, buffs, and other helpers.

- Idle DoT icons and dead-target clutter stay hidden.

- Melee classes keep slim threat and swing strips.



#### Warlock added

- Alerts for Corruption, Bane of Agony, Immolate, Siphon Life, and other learned spells.

- Life Tap, pet, Demon Armor, Healthstone, Drain Soul, and Nightfall reminders.

- Readable DoT countdowns and a simple Soul Shard bag count.

- 18 "PK" macros available through `/pa macros`.



#### Druid follows your form

- Bear, Cat, caster, and travel forms each show the right resources and timers.

- Cat keeps energy and combo points. Bear uses rage; caster and travel forms use mana.

- Fixed layout updates when changing forms without changing the power type.



#### Cast bar corrections

- Cast fill and countdown follow the game's own cast duration.

- The thin blue end marker means you can queue your next spell early.

- Removed the unreliable "MOVE" prediction. Finish the cast before moving.

- The queue marker stays hidden when the game hides its timing.



#### Small fixes

- Removed unknown-spell defensive placeholders on early-level Warlocks.

- Toned down stance and item reminders to match the quieter layout.

- Fixed overlapping cast-bar labels.



### How to update

Install the ZIP below. If DBagsAlerts is already installed, type `/reload` in WoW. A first install needs a full game restart.



`/pa oldlook` restores the previous layout. `/pa newlook` switches back to the floating layout.

## 1.0.1 (2026-11-06)

What changed:
- New: racials for every race. Your combat racials go on the cooldown row (only the ones you have).
- Elune's Light (Night Elf), Blood Fury (Orc) and Berserking (Troll) light up as a big icon on tough fights: an elite, 2+ mobs, or heavy hits.
- War Stomp (Tauren) shows when a mob is casting and your interrupt isn't ready.
- /reload to get it.

## 1.0.0 (2026-11-06)

What changed:
- New name: ProtAlerts is now DBagsAlerts.
- New: Druid, all forms. The alerts follow your form: Bear (Primal Bite, Lacerate/Swipe, Maul, Growl, Bash), Cat (Ravage from Prowl, Rip, Rake, Claw/Shred, Shifting Power) and caster (Moonfire, Insect Swarm, Wrath, Hurricane, Innervate). Mark of the Wild + Thorns reminders. From the Icy Veins WoW Forever druid guides.
- Druid bar shows rage, energy + combo points, or mana for the form you're in.
- 17 Druid macros: /pa macros.
- Coming from ProtAlerts: your settings carry over and the old ProtAlerts turns itself off. /reload once, then you can delete the old ProtAlerts folder.
- New addon folder: fully restart WoW.

## 0.9.13 (2026-11-06)

What changed:
- New: weapon stone button. Your main hand has no stone? Click it to sharpen (swords, axes, daggers) or weight (maces, staves) it.
- No stone in your bags: grey NO STONE icon. Turn it off with 'Show if I have none' in /pa.
- EAT button fix: food that WoW hadn't loaded yet is checked again. New /pa food says why the button is or isn't showing.
- /reload to get it.

## 0.9.11 (2026-11-05)

What changed:
- Demoralizing Shout now shows early in every fight (Icy Veins: use it early to take less damage), not only on packs and elites.
- On a single normal mob it skips Demo once the mob is under 40% health.
- /reload to get it.

## 0.9.10 (2026-11-05)

What changed:
- Aggro dots only show while you are in combat. Out of combat the addon doesn't read nameplates at all (less work for your PC).

## 0.9.9 (2026-11-05)

What changed:
- Aggro dot now shows over EVERY mob in a fight, not just your target: green = on you, yellow = slipping, red = hitting someone else.
- Target with no nameplate: its dot shows on the target frame.
- Turn enemy nameplates on (V).

## 0.9.8 (2026-11-05)

What changed:
- The dot over your target now shows AGGRO instead of range: green = it's on you, yellow = about to lose it, red = it's not hitting you.
- Setting renamed to 'Aggro dot' in /pa.

## 0.9.7 (2026-11-05)

What changed:
- New: green EAT button when you have no Well Fed (+5% XP in Forever) but carry cooked food that gives it. Click it to eat.
- Only out of combat; hidden on a mount, when dead, while eating and at max level. Toggle 'Eat reminder' in /pa.

## 0.9.6 (2026-11-05)

What changed:
- New: flashing DEFENSIVE reminder above your character when you fight in another stance for 2+ seconds (Icy Veins: Charge, then Defensive). Toggle 'Stance reminder' in /pa.
- PA Charge knows Vanguard: after level 25 it Charges from Defensive. Run /pa macros again.
- Fixed: Battle Shout reminder showed in combat while you had the buff.
- Fixed: two Battle Shout icons at once.

## 0.9.4 (2026-11-05)

What changed:
- New: glowing Battle Shout reminder left of the icons when your shout is missing, even out of combat.
- No rage out of combat? It shows Bloodrage first, then Shout.
- Hidden in towns, on a mount and when dead. Turn it off with 'Buff reminder' in /pa.

## 0.9.3 (2026-11-05)

PA Charge goes to Battle Stance first if you're not in it (1st press Battle, 2nd press Charge). Run /pa macros after updating.

## 0.9.2 (2026-11-05)

PA Stance macro swaps Defensive and Battle Stance (replaces PA Defensive in the same action bar spot). Run /pa macros after updating.

## 0.9.1 (2026-11-05)

Health bar fades green to yellow to orange to red as you lose health. Works in combat too.

## 0.9.0 (2026-11-05)

Work in progress. Tank alerts with glow, bars, range dot, target frame, cursor ring and macros for Prot Warrior and Paladin in WoW: Forever. Fully restart WoW after installing.
