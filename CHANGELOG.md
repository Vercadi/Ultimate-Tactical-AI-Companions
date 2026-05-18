# UTAC Changelog

All notable changes to Ultimate Tactical AI Companions (UTAC) are recorded here.

---

## [Unreleased]

No unreleased public changes yet.

## [1.1.3.0] - 2026-05-18

### Added
- Added three new early/test archetypes: Unarmed, Primal Druid, and Summoner/Conjurer.
- Added conservative AI helper spells for Action Surge, Cunning Action Dash, and Primal Druid Wild Shape Combat.
- Helper spells only appear for valid UTAC-controlled actors that already have the real ability, and are cleaned up after combat/release.
- Added summon reload recovery scans to help auto-controlled summons recover after save/quit/reload.

### Changed
- Slightly improved Assassin and Skirmisher opportunity-attack avoidance tuning.

### Notes
- The new archetypes are early and need more testing.
- Summoner supports existing summons/control behavior, but does not force summon spell casting yet.

## [1.1.2.6] - 2026-05-14

### Fixed
- Fixed the UTAC Spell Policy block list failing to prevent some blocked spells, especially in NPC Mode.
- Dynamic blocked-spell stat patching now uses a TAC/AI Allies-style `not HasStatus('UTAC_ALLY')` requirement gate instead of context-dependent caster checks.
- Fixed reload/restart cases where BG3 could reload stats after UTAC marked a spell as patched, wiping the requirement gate until the MCM list was edited again.
- Spell Policy now refreshes from the saved MCM snapshot on stats/session/level load and idempotently reapplies gates to every enabled blocked spell.
- Kept spell removal, queue purge, and post-leak cleanup as fallback layers for edge cases.
- Removed the Support Healer nonurgent General AI override path so Healer stays on the healer archetype at all times.
- Increased Support Healer ally-heal weighting, low-HP target bias, downed-ally pressure, and neutral/story NPC support safety.
- Tuned Protector toward bodyguard behavior: stronger ally positioning, ally buffs, downed-ally rescue pressure, and lower priority than Healer for pure triage healing.
- Updated BG3MM metadata version to `1.1.2.6`.

### Notes
- Spell Policy remains optional and default off.
- This hotfix does not add new blocked spells by default. Archetype scoring changes are limited to Support Healer and Protector support-role tuning.

## [1.1.1] - 2026-05-06

### Changed
- Tuned all UTAC archetypes to score neutral/yellow/story NPCs as unsafe harmful targets instead of viable targets.
- General, Summon, and Spellcaster no longer positively score neutral targets.
- Added explicit neutral damage/control/DoT penalties using vanilla-confirmed AI multiplier keys.
- Added cheap combat enter/exit guards to avoid unnecessary summon/template and cleanup work for obvious non-UTAC actors.
- Updated BG3MM metadata version to `1.1.1.0`.

### Notes
- No individual spell blocks were added for Hold Person, Cloud of Daggers, Mass Healing Word, or story spells.
- No protected-NPC diagnostics, runtime protected-neutral tagging, MCM changes, or NPC Mode ownership changes were added.

## [1.1.0] - 2026-05-05

### Added
- Added explicit player/main-character self-target support for UTAC archetype, release, and archetype-check spells.
- Player/main characters can now opt into UTAC AI control manually; this is never auto-applied.

### Changed
- Hard-blocked UTAC NPC Mode for host/player characters. Player characters use regular UTAC combat statuses only and do not receive the NPC Mode passive.
- Updated BG3MM metadata version to `1.1.0.0`.

### Fixed
- Repaired summon exclusion matching for Pack Rats-style templates by resolving root template `MapKey` values from Script Extender template userdata and falling back to the known Pack Rats template-name-to-UUID mapping when the runtime handle exposes only `VSH_PackRat_*_<uuid>`.

### Notes
- Companion NPC Mode behavior is intentionally unchanged.
- Pack Rats exclusions still need runtime confirmation from an updated build/log.

## [1.0.9] - 2026-05-04

### Added
- Added optional `Block Jump for UTAC allies` MCM setting, default off, using a narrow static gate for common companion Jump.
- Added hidden `UTAC_JUMPING_DISABLED` runtime status.
- Added throw diagnostics for UTAC-controlled `Throw_*` spell use, including NPC Mode/status state and whether the spell is covered by UTAC's static throw gate.

### Changed
- Clarified Throw block MCM wording: it covers common Throw, Improvised Weapon, and Frenzied Throw actions, but not every story/modded throw spell.
- Tuned Bruiser movement safety by reducing extreme enemy-proximity/pathing incentives, enabling AOO avoidance, and increasing self-fall-damage penalty.
- Tuned Assassin pathing safety by reducing risky enemy-adjacent/flanking end-position scoring and softening target-tunnel weights.
- Hardened spell policy stat patching so blocked spells get a caster-side `RequirementConditions` gate, while spell removal/restoration and the late `UsingSpell` guard remain fallback layers.
- Updated BG3MM metadata version to `1.0.9.0`.

### Notes
- Jump, Throw, Dash, and Shove blocks remain opt-in.
- `Throw_Telekinesis` and broad `Throw_*` blocking were intentionally not added.
- Spell policy remains default off and dynamic through the MCM blocked-spell list.

## [1.0.8] - 2026-05-03

### Added
- Added advanced editable `Summon auto-apply exclusions` MCM list, seeded with confirmed Pack Rats root/template UUIDs.
- Added UUID-only summon exclusion parsing for enabled list rows.
- Added runtime cleanup for excluded already-tracked auto summons; UTAC removes only its auto-summon/control statuses and does not unsummon anything.

### Changed
- Tuned Assassin away from low-value AoE/zone casts and unsafe enemy-adjacent pathing while preserving priority-target pressure.
- Tuned Healer hostile-control scoring down and added explicit neutral-control safety multipliers.
- Updated BG3MM metadata version to `1.0.8.0`.

### Notes
- Summon exclusions intentionally match root/template UUIDs only. Runtime spawned character UUIDs usually change and are not supported for this first public version.
- Hold Person, Mass Healing Word, and Cloud of Daggers were not added to default spell blocks.

## [1.0.7] - 2026-05-01

### Added
- Added optional **Block selected utility spells** MCM policy, default off, scoped to UTAC-controlled actors only.
- Added editable `list_v2` blocked spell list with default entries for `Shout_FeatherFall`, `Target_FogCloud`, and `Target_BlessingOfTheTrickster`.
- Added optional **Limit high spell slots** MCM toggle, default off, that temporarily blocks normal `SpellSlot` levels during low-pressure caster turns.
- Added hidden `UTAC_SPELL_POLICY_BLOCKED` and `UTAC_SLOT_LIMIT_L2_PLUS` through `UTAC_SLOT_LIMIT_L6_PLUS` statuses.
- Added `Server/UTACSpellPolicy.lua` to own spell stat gating, spell remove/restore tracking, `UsingSpell` guard handling, and slot limiter cleanup.

### Changed
- Reorganized MCM spell/action/resource controls into a dedicated **Spells & Resources** tab.
- Clarified soft high-slot conservation vs. hard spell-slot blocking labels/descriptions in MCM.
- Added extra disabled-by-default utility spell candidates to the editable blocked spell list.
- Clarified spell-policy MCM wording so users know the toggle enables an editable blocked-spell list.
- Updated BG3MM metadata version to `1.0.7.0`.

### Notes
- Spell blocking reduces native AI selection. Scripted `UseSpell` paths from story or other mods may still bypass normal AI selection.
- First pass blocks only normal `SpellSlot` resources. Warlock pact slots, custom resources, Lay on Hands, Channel Divinity, and Channel Oath are not blocked.

## [1.0.6] - 2026-04-30

### Fixed
- Improved healer triage candidate discovery with a healer-specific combat participant path that supplements party/tracked allies.
- Downed-but-not-dead allies can now remain visible to healer triage instead of being filtered out before urgency checks.
- Self HP is now tracked as a first-class healer urgency signal, including lowest-heal-candidate debug data.

### Changed
- Rebalanced `Support_Healer` toward vanilla/AI Allies proportions: self and ally healing weights are closer together, heal caps are back inside the vanilla-documented range, and downed/resurrect weights are strong but no longer extreme.
- Updated BG3MM metadata version to `1.0.6.0`.

### Notes
- This does not script exact healing spells. Healer behavior still uses BG3 native AI scoring, now with better candidate visibility and less extreme healer weights.

## [1.0.5] - 2026-04-29

### Added
- Added optional **AI Sculpt Spells Safety** MCM toggle, default off.
- Added hidden `UTAC_SCULPT_SPELLS_HELPER` status that grants BG3's `SculptSpells` passive while enabled for UTAC-controlled characters.
- Sculpt helper syncs through existing UTAC control, summon tracking, settings rebuild, release control, and mod-disable cleanup paths.

### Changed
- Updated `meta.lsx` ModuleInfo and PublishVersion `Version64` to `36028807756382208` so BG3MM reports version `1.0.5.0`.
- Updated public/readme version references to `1.0.5`.

### Notes
- Sculpt Spells only affects spells that respect BG3's `SculptSpells` passive behavior. It does not protect against every AoE, surface, aura, or modded spell.

## [1.0.0] - 2026-04-25

### Added
- **Changelog** â€” Added the public release changelog.
- **Critical fixes plan** â€” Added private planning notes for the first stabilization pass.
- **Targeted runtime checklist** - Added private runtime validation notes for the remaining BG3-only trap, surface, iterator, target-order, helper, and vanilla-action checks.

### Fixed (Critical)
- **Durable state** - Replaced live `PersistentVars` dependency for disabled assignment snapshots with registered ModVars, kept post-heal state runtime-only, and added legacy snapshot migration.
- **Manual target orders** - Focus/Ignore orders now maintain runtime order state, use documented preferred-target tag calls for focused targets, skip auto-priority on ignored targets, and clear order state on release/combat end.
- **Combat participant rebuild** - Sparse combat cache recovery now uses `CombatGetGuidFor`/`DB_Is_InCombat` membership plus the old party/tracked fallback. Avoided `IterateActiveObjectsInSameCombatGroup` because its callback event names must exist as compiled story symbols.
- **Trap awareness after combat** - Controlled allies reapply `UTAC_AVOID_DANGER` and `AI_TRAP_AWARENESS` after leaving combat so exploration safety is restored.
- **Optional action blocks** - Dash/Throw blocks now resync immediately from MCM, and Shove blocking is optional instead of globally blocking every `UTAC_ALLY`.
- **AIFlags casing** - AI-only Dash variants now use `AIFlags` consistently with the rest of the stats data.
- **Normalized character IDs** â€” All writes and reads of `_G.UTAC_Companions` and `_G.UTAC_BaseStatusByCharacter` now use `CC_Normalize(character)` so lookups (Rally, LeftCombat, TurnStarted, Dialog, etc.) are reliable across GUIDSTRING vs UUID.
- **Rally teleport** â€” Caster is normalized and compared to normalized companion keys so the caster is never teleported and all companions are found.
- **Session load** â€” `ReinforceUTACControl()` is called from `SessionLoaded` after pruning dead companions so statuses and passives re-apply on save load.
- **Debug logging** â€” `InfoPrint` runs only when **Enable Debug Logging** is on (no longer tied to AI Indicators).
- **Bootstrap optimization** - `BootstrapServer.lua` now uses shared helper functions for host spell policy and minimizes normal log noise (errors only unless bootstrap debug is enabled).
- **SessionLoaded stability** - Rebuild/reinforce now retries when Osiris is in restricted context, preventing `Attempted to call Osiris function in restricted context` errors from `GetHostCharacter` during load.
- **Healer urgency gating** - Support Healer resource-helper encouragement now triggers only for urgent cases (downed ally, ally at/below triage threshold, or healer self at/below threshold).
- **Healer baseline tuning** - `Support_Healer` heal/self-heal multipliers were reduced and low-HP bias increased to curb premature top-off healing while keeping triage behavior strong.
- **Debug visibility** - TurnStart debug log now prints `triage=<threshold>` for direct verification of active healer threshold.
- **Healer mode switching** - Added `UTAC_HEALER_NONURGENT_OVERRIDE` (General AI override priority 2) so Support Healer only enters full healer behavior when triage urgency exists.
- **Participant filtering** - Combat participant cache now excludes dead/dying/HP<=0/non-character entries to reduce inflated enemy counts from stale combat members.
- **Healer debug mode** - TurnStart logs now include `healerMode=urgent|nonurgent` for Support Healer verification.
- **Archetype hit-chance stupidity** - Set `MODIFIER_HIT_CHANCE_STUPIDITY` to `0.0` across all UTAC archetype files.
- **Healer retune (v2)** - Support Healer healing multipliers adjusted (`ally=7.0`, `self=1.0`, `maxHeal=2.0`, `maxSelf=1.8`, `healthBias=2.0`) to reduce non-urgent top-off heals while allowing better self-heal behavior.

### Removed
- **Dead target-order status** - Removed the unused `UTAC_AVOID_TARGET` status and orphan localization handles after source search confirmed it had no active applier or reference.
- **MCM options** â€” "Show AI Decision Indicators" and "Display Danger Zones" removed from the Debug tab. Default `MCM_ShowDangerWarnings` removed from MCMHelper. Danger avoidance (mines, fire) remains AI-internal only; no player-facing indicators.

### Changed
- **MCM wording** - Renamed helper/buff sections to make optional mechanical assistance explicit and kept those boosts default-off.
- **Mechanical assistance tuning** - Down-tuned archetype/helper buffs and set emergency spell slot restoration default to `0` so the default mod remains AI control, not hidden power scaling.

### MCM audit
- Added private MCM audit notes for UX, sync, and co-op safety; prioritized recommendations included preset-on-change, host-only notes, event filtering, and optional dropdown/localization work.

### MCM improvements (P1â€“P3)
- **P1:** Preset applies when user changes Archetype preset in MCM (`MCM_Setting_Saved` for `ArchetypePresetIndex`); preset also writes to `MCM.Set()` so UI and store stay in sync; README documents co-op (host's MCM only) and MCM JSON storage.
- **P2:** All MCM event handlers filter by UTAC mod UUID; Healer preset kept as **slider_int** (0â€“3) because Volitio's MCM 1.39 does not support type `dropdown`; description clarifies 0/1/2/3 and "Takes effect immediately"; Core section and key settings use Handles + contentuids in `english.xml` for localization.
- **P3:** Additional Spell Resources description mentions comma/semicolon; `MCM_Setting_Reset` subscribed for `MCM_CustomSpellResources` to refresh tracked resources.
- Preset application removed from TurnStarted (only LevelGameplayStarted and MCM_Setting_Saved now).

### Documentation (2.4)
- **README.md** documents requirements (BG3, Script Extender, MCM), note that RequiredVersion 9 is minimum and SE is often higher (e.g. 30), mod version 1.0.
- **AIArchetypeManager.lua** header comment: requires Script Extender (Config RequiredVersion min 9), mod version 1.0 (meta.lsx).
- **Validation against BG3 Search** - confirmed `RestoreResource(SpellSlot,1,1)` syntax is used in vanilla data, and confirmed `Spell_Prepare_Buff_BlessingOfTheTickster_L1to3` / `_Loop` are valid prepare sound IDs while cast/impact use `...Trickster...`.

### Refactor (3.1)
- **Split AIArchetypeManager.lua into modules:**
  - **Config.lua** â€” Constants and data tables (CombatStatusMap, CombatStatusNPCMap, StatusToArchetype, TemporaryHelpers, AllPermanentHelpers, UTAC_SpellMappings, PRESETS, TRIAGE_RADIUS_M, NZ, etc.).
  - **CombatCache.lua** â€” CC_Normalize, CC_Add, CC_Remove, CC_CombatMembersFor, GetCombatParticipants; EnteredCombat/LeftCombat/Died listeners; UTAC_DistanceToNearestEnemy/Ally, UTAC_HasAdvantage, HighestSpellSlotLevelAvailable.
  - **HealerTactics.lua** â€” Factory taking GetHealerTriageThreshold and GetCombatParticipants; returns AnalyzeCombatState (triage, revive ladder, combat state analysis).
  - **ArchetypeTactics.lua** â€” Factory taking MCM/helpers; returns UpdateTargetPriorities and ManageCombatTactics.
  - **AIArchetypeManager.lua** â€” MCMHelper, globals, helpers (IsModEnabled, InfoPrint, GetMCM_*, UTAC_ModifySpells, preset application, PostHealActive, spell resources, ClearPermanentHelpers), requires all modules, ReinforceUTACControl, ApplyCombatStatus, ClearTemporaryHelpers, and all remaining Osiris/Ext listeners (StatusApplied/Removed, EnteredCombat companion branch, TurnStarted, Rally, UsingSpellOnTarget, Dialog*, ShortRested, SessionLoaded).
- **Bugfix:** DialogActorJoined now stores `_G.UTAC_TransformedForDialog[actorKey]` (normalized key) so DialogEnded can look up and re-apply AI control correctly.

---

## Past changes (summary)

*Below is a summary of changes made during earlier development and playtest fixes. Exact dates/versions can be filled in as you tag releases.*

### Combat & state
- Fixed Osiris listeners: `CharacterDied/3` â†’ `Died/1`; removed invalid `Summoned/6`; summon detection moved to `EnteredCombat`.
- Combat cache: normalize character IDs with `CC_Normalize()` so cache lookups work across GUIDSTRING vs UUID.
- GetCombatParticipants: use host as party anchor so ally/enemy classification works when companions are in NPC mode.
- Added `ReinforceUTACControl` grant of `UTAC_ToggleNPC` passive on level/rest so it appears after save load.

### Spells & host
- Host-only spells: grant only when `IsPartyFollower(host, 1) == 0`; cleanup removes from companions only.
- Rally: `RequirementConditions "not Combat()"` in Block_UTAC so it is never usable in combat (host or companion).
- Target_UTAC target conditions updated so NPC-mode companions can be targeted (Party or UTAC_IS_CONTROLLED or Ally).
- Removed Melee Bruiser spell animation override so it inherits from parent; fixed Ignore Target icon.

### MCM & options
- MCM reorganized into tabs: Core, AI Helpers, Healer, Debug.
- Added `MCM_EnableArchetypeBuffs` (default off); archetype helper buffs gated by this and by existing helper toggles.

### AI behavior
- Increased `MULTIPLIER_DAMAGE_ALLY_NEG` on Melee Skirmisher, Bruiser, Hybrid Assassin, Ranged Marksman, General AI, Spellcaster to reduce friendly fire.
- Block Shove for UTAC allies in Block_UTAC.txt to stop AI shoving dead bodies.
- Healer: `GetCombatParticipants` fallback uses DB_PartyMembers + UTAC_Companions; `alliesLowHP` uses MCM Healer_TriageThreshold.

### NPC toggle
- `UTAC_ToggleNPC` passive granted via Lua `Osi.AddPassive` (and in `ReinforceUTACControl`); status Passives field approach removed.
- Dialog handling and LeftCombat safety sweep use NPC combat status cleanup and MakePlayer where needed.

### Statuses & passives
- Added icon for `AI_ASSASSIN_ISOLATION_BONUS`.
- Danger avoidance (mines, fire, etc.) is AI-internal only; no player-facing danger zone/indicator options intended.

---

*Changelog format: [Unreleased] for in-progress work; version headings like [1.0.1] when you tag releases.*
