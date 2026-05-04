# UTAC Changelog

Public release notes for Ultimate Tactical AI Companions (UTAC).

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

- Added optional `Block selected utility spells` MCM policy, default off, scoped to UTAC-controlled actors only.
- Added editable blocked spell list with default entries for `Shout_FeatherFall`, `Target_FogCloud`, and `Target_BlessingOfTheTrickster`.
- Added optional `Limit high spell slots` MCM toggle, default off, that temporarily blocks normal `SpellSlot` levels during low-pressure caster turns.
- Added hidden spell policy and spell slot limiter statuses.
- Added `Server/UTACSpellPolicy.lua` to own spell stat gating, spell remove/restore tracking, `UsingSpell` guard handling, and slot limiter cleanup.

### Changed

- Reorganized MCM spell/action/resource controls into a dedicated `Spells & Resources` tab.
- Clarified spell-policy MCM wording so users know the toggle enables an editable blocked-spell list.
- Reduced nonurgent healer top-off bias and applied the healer nonurgent override immediately on combat-status application.
- Updated BG3MM metadata version to `1.0.7.0`.

### Notes

- Spell blocking reduces native AI selection but cannot stop every scripted `UseSpell` from story or other mods.
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

- Added optional `AI Sculpt Spells Safety` MCM toggle, default off.
- Added hidden `UTAC_SCULPT_SPELLS_HELPER` status that grants BG3's `SculptSpells` passive while enabled for UTAC-controlled characters.
- Sculpt helper syncs through existing UTAC control, summon tracking, settings rebuild, release control, and mod-disable cleanup paths.

### Changed

- Updated BG3MM metadata version to `1.0.5.0`.

### Notes

- Sculpt Spells only affects spells that respect BG3's `SculptSpells` passive behavior. It does not protect against every AoE, surface, aura, or modded spell.

## [1.0.4] - 2026-04-28

### Added

- Added localization handles for MCM tabs, sections, setting names, and setting descriptions.
- Added English XML entries for MCM localization.
- Added translator-facing notes for future translation patches.

### Notes

- No gameplay behavior changed in this release.

## [1.0.0] - 2026-04-25

### Added

- Initial public release of Ultimate Tactical AI Companions.
- Added tactical AI archetypes, companion AI control spells, NPC Mode support, target orders, summon automation, optional helper systems, and MCM configuration.
