# UTAC Roadmap

Last updated: 2026-05-11

This file is the high-level planning tracker for Ultimate Tactical AI Companions. Detailed research notes stay in `UTAC Docs/Audit`, but this roadmap should be the first place to check what is shipped, next, deferred, or not planned.

## Current Priority

Keep releases narrow. Each Nexus patch should change one major thing so bug reports are easy to attribute.

Current planned sequence:

1. Release next `1.1.2.x` hotfix - Spell Policy turn-scoped `CanNotUse` enforcement, using the dynamic MCM blocked-spell list.
2. Next small summon reliability patch - post-load summon auto-apply recovery scan for saved/modded summons that miss summon DB events after reload.
3. Next suitable QoL patch - UTAC Control container with a panic-style Release All AI Control spell.
4. Later/TBD - auto-apply default AI to companions joining the party, if scoped safely around summons/followers/NPC-mode transitions.
5. Later/TBD - optional strict role-helper prototype, only if testing supports it.

Versioning note:

- Use patch versions such as `1.0.10` for narrow fixes with no new user-facing feature.
- Use minor versions such as `1.1.0` when adding a new capability, such as allowing the player's own character to be put under UTAC AI control.

## Done In Workspace

### Version 1.0.4 - MCM Localization

Status: implemented, pending in-game MCM UI verification and release packaging.

Scope:

- Added localization handles for all current MCM tabs, sections, setting names, and setting descriptions.
- Added matching English XML localization entries.
- Added translator notes for external language patches.
- No gameplay behavior changed.
- No stats, passives, statuses, archetypes, summon automation, NPC mode, or MCM defaults changed.

Validation completed:

- `MCM_blueprint.json` parses as JSON.
- `english.xml` parses as XML.
- All MCM handles referenced in the blueprint exist in `english.xml`.
- No duplicate `contentuid` values.
- No MCM setting IDs, types, defaults, or fallback strings changed.

Remaining validation:

- Open MCM in-game and confirm every visible string renders correctly.

### Version 1.0.5 - Sculpt Spells Safety Helper

Status: implemented, pending in-game MCM/runtime verification and release packaging.

Scope:

- Added hidden `UTAC_SCULPT_SPELLS_HELPER` status granting `SculptSpells`.
- Added default-off `AI Sculpt Spells Safety` MCM toggle.
- Synced helper through tracked UTAC characters and summons.
- Added cleanup on toggle off, release AI control, full UTAC disable, and rebuild paths.
- Updated BG3MM metadata version to `1.0.5.0`.

Remaining validation:

- Open MCM in-game and confirm the toggle renders and defaults off.
- Test toggle on/off on a UTAC-controlled companion.
- Test Release AI Control cleanup.
- Test a supported Evocation ally-overlap spell such as Fireball or Burning Hands.
- Confirm known exceptions such as Moonbeam are not advertised as fully protected.
- Confirm BG3MM reports `1.0.5.0`.

### Version 1.0.6 - Healer Reliability / Triage Fix

Status: implemented, pending in-game runtime verification and release packaging.

Scope:

- Added healer-specific combat participant discovery that supplements party/tracked allies.
- Kept downed-but-not-dead allies visible to healer triage without globally treating downed enemies as active units.
- Added self HP, lowest heal candidate, urgent candidate count, and participant-discovery metadata to healer debug output.
- Rebalanced `Support_Healer` toward vanilla/AI Allies proportions while keeping healer identity stronger than vanilla.
- Updated BG3MM metadata version to `1.0.6.0`.

Remaining validation:

- Healer low HP, no other injured allies: healer should consider self-preservation/self-heal.
- Tav/host injured and another companion lower HP: healer should not always tunnel Tav.
- Downed ally nearby: healer triage should detect the downed ally.
- Healer with no heal spells or no spell slots: behavior should not regress into worse skipped turns.
- Normal offensive/control behavior should remain possible when no urgent healing need exists.
- NPC Mode companions should still enter/exit combat correctly.
- Summon automation should still avoid log spam.

### Version 1.0.7 - UTAC Spell Policy And Spell Slot Limiter

Status: implemented, pending in-game runtime verification and release packaging.

Trigger:

- Nexus user reports that large caster spell lists cause slow turns and poor utility casts such as Feather Fall or Fog Cloud.
- Existing `ConserveHighSlots` is only a soft resource-helper gate and does not actually block high-level slots.

Goal:

- Give users opt-in tools to reduce bad caster AI choices without changing default behavior.
- Block selected utility spells only for UTAC-controlled actors.
- Temporarily block high normal spell slots during low-pressure combat.

Scope:

- Default off for both spell policy and slot limiter.
- Added dedicated `Server/UTACSpellPolicy.lua` module, not a full merge of the standalone Spell Blocker mod.
- Added default-off `MCM_EnableUTACSpellPolicy` and editable `MCM_UTACBlockedSpellList`.
- Added default-off `MCM_EnableSpellSlotLimiter`, `MCM_SpellSlotLimiter_MinLevel`, and `MCM_SpellSlotLimiter_AllowEnemiesAtLeast`.
- Initial implementation added dynamic stat gates plus spell removal/restoration and a scoped `UsingSpell` fallback guard. Later hotfixes moved the hard gate to a TAC/AI Allies-style `not HasStatus('UTAC_ALLY')` requirement check.
- Added `RemoveSpell`/`AddSpell` tracking and a scoped `UsingSpell` guard as fallback layers.
- Slot limiter blocks normal `SpellSlot` only in the first implementation.
- Do not block `WarlockSpellSlot`, custom spell resources, Lay on Hands, Channel Divinity, or Channel Oath in the first pass.
- Slot limiter applies only to caster-oriented roles: Spellcaster, AoE Specialist, Healer, and General if normal spell slots are present.
- Slot limiter does not apply to Summon, Bruiser, Marksman, Protector, Skirmisher, or Assassin.
- Updated BG3MM metadata version to `1.0.7.0`.

Important limitations:

- This reduces AI selection options; it does not guarantee another story/mod script cannot force `UseSpell`.
- Native AI still evaluates movement, items, cantrips, class actions, reactions, and modded spells.
- Blocking too many spells can make caster AI weaker or cause worse fallback turns.
- Warlock and custom-resource behavior need separate testing.

Remaining validation:

- Norbyte stats validation for new status entries.
- JSON/XML validation for new MCM settings and localization.
- Runtime test disabled defaults, MCM list edits, combat enter/end cleanup, Release AI Control cleanup, NPC Mode caster cleanup, Warlock unaffected behavior, and no summon log spam.

Reference plan:

- `UTAC Docs/Audit/SPELL_POLICY_AND_SLOT_LIMITER_RESEARCH_2026-05-01.md`
- `UTAC Docs/Audit/SPELL_SLOT_LIMITING_PLAN_2026-04-29.md`
- `UTAC Docs/Audit/HEALER_TRIAGE_AND_SPELL_POLICY_PLAN_2026-04-30.md`

### Version 1.0.8 - Summon Exclusions And Archetype Safety Tuning

Status: implemented, pending in-game runtime verification and release packaging.

Scope:

- Added advanced editable UUID-only summon auto-apply exclusions, seeded with confirmed Pack Rats root/template UUIDs.
- Added runtime cleanup for excluded already-tracked auto summons without unsummoning anything.
- Tuned `Hybrid_Assassin` away from low-value AoE/zone casts and obvious opportunity-attack pathing.
- Tuned `Support_Healer` down for hostile control and added explicit neutral-control safety values.
- Updated BG3MM metadata version to `1.0.8.0`.

Remaining validation:

- Pack Rats rats should not receive `UTAC Summon` with the default exclusion list.
- Vanilla Find Familiar cat should still receive `UTAC Summon`.
- Removing Pack Rats UUIDs from the MCM exclusion list should allow Pack Rats rats to receive UTAC summon control again.
- Adding a custom root/template UUID should exclude that summon without disabling all summon automation.
- Assassin should prefer priority-target pressure over obvious one-target zone/AoE turns.
- Healer should still heal/revive and use control against real enemies.

## Active / Next Planned

### Next Small Patch - Summon Reload Recovery

Status: planned.

Trigger:

- Nexus user report: auto-applied summon AI worked for several summons, including modded summons, then stopped after quitting and reloading the save.
- The current reload path rebuilds tracked UTAC actors from party/team/cache/status candidates, but existing saved summons may not always re-fire `DB_PlayerSummons`, `DB_PartyFollowers`, `CharacterJoinedParty`, or `EnteredCombat` in the same order after reload.

Planned scope:

- Add a delayed post-load summon recovery scan after `SessionLoaded` and/or `LevelGameplayStarted`.
- Reuse existing `ScanKnownSummonCandidates` / `ScheduleAutoSummonRetry` logic instead of creating a new summon automation path.
- Include `DB_PlayerSummons` and `DB_PartyFollowers` candidates in rebuild/reinforcement where safe.
- Do not unsummon anything.
- Do not change Pack Rats exclusions, summon exclusion semantics, NPC Mode, or normal companion tracking.
- Keep Release AI Control + reapply as the user-facing workaround for stale summon state until this is patched.

Runtime validation needed:

- Summons that worked before saving still receive/retain active UTAC summon control after quitting to desktop and reloading.
- Modded summons that appear in `DB_PlayerSummons` or `DB_PartyFollowers` are picked up by the recovery scan.
- Vanilla Find Familiar still receives `UTAC Summon`.
- Pack Rats exclusions still prevent default `UTAC Summon`.
- Release AI Control on a stale summon followed by manual Balanced/Summon AI reapply still recovers control.

### Version 1.1.0 - Player Character AI Control And Summon Exclusion Repair

Status: implemented in workspace, pending validation and release packaging.

Trigger:

- Nexus user request: allow the player to cast UTAC AI control spells on their own character, not only companions.
- Nexus user confirmation after `1.0.8`/`1.0.9`: Pack Rats rats still show `UTAC Summon`, so the default summon exclusion list is not preventing auto-control in the user's runtime setup.

Player-character AI control scope:

- UTAC archetype, release, and archetype-check spells can now explicitly target `Self()`.
- Player/main characters can opt into UTAC AI manually and are tracked like other UTAC-controlled actors.
- Player/main characters are not auto-applied by companion or summon automation.
- NPC Mode is intentionally blocked for host/player characters; they use regular UTAC combat statuses only.

Pack Rats / summon exclusion repair scope:

- Runtime template resolver now handles Script Extender template userdata `MapKey` values.
- Pack Rats fallback maps known `VSH_PackRat_*` template names to the UUIDs already seeded in the MCM exclusion list.
- Do not fall back to broad name matching like any `Rat`, because that can exclude vanilla or modded combat rats unintentionally.
- Do not unsummon excluded summons.
- If a summon is already tracked and later matches an exclusion, remove only UTAC-owned auto-summon/control statuses and untrack it.

Current Pack Rats findings:

- The seeded Pack Rats UUIDs in UTAC are present in the unpacked Pack Rats mod as `RootTemplates`.
- The same UUIDs are used by Pack Rats `Summon(...)` functors in `Status_BOOST.txt`.
- Therefore the likely bug is runtime-side: either UTAC is not resolving those template UUIDs from the live summoned rat, or MCM is not providing the default exclusion list as expected for that user.
- Updated user logs or local reproduction are needed to confirm the repair in-game.

Runtime validation needed:

- Existing user with upgraded MCM settings: verify default exclusion entries are present/enabled in MCM.
- Fresh profile/install: verify default exclusion entries are present/enabled in MCM.
- Spawn Pack Rats with debug logging on and confirm what template/root values UTAC sees.
- Confirm excluded Pack Rats lose/avoid `UTAC Summon`.
- Confirm vanilla Find Familiar and normal combat summons still receive `UTAC Summon`.
- Confirm player-character AI can be applied and released without breaking party control, dialogue, inventory, or turn ownership.

### Version 1.1.1 - Protected NPC Targeting Safety And Combat Enter/Exit Performance Cleanup

Status: implemented in workspace, pending validation and release packaging.

Implementation plan: `Audit/UTAC_1_1_1_IMPLEMENTATION_PLAN_2026-05-06.md`

Trigger:

- Nexus/user reports show UTAC-controlled companions can sometimes target yellow/non-party/story NPCs such as Isobel, Mirkon, or other protected combatants.
- Research found UTAC General/Summon/Spellcaster currently use positive neutral scoring, while vanilla base AI uses negative neutral scoring.
- Local testing showed `LeftCombat` handlers can take hundreds of milliseconds during flee-to-camp / combat-exit transitions, even when no character is actively UTAC-controlled.
- Log review showed `EnteredCombat` still runs summon exclusion/template resolution for normal combat participants, producing noisy "could not resolve root/template UUID" lines.

Protected/yellow NPC targeting scope:

- Implement the archetype-only Phase 1 from `Audit/NEUTRAL_PROTECTED_NPC_TARGETING_RESEARCH_2026-05-06.md`.
- Remove positive neutral scoring from UTAC archetypes, especially `General_AI`, `Summon_AI`, and `Spellcaster`.
- Use vanilla-confirmed multiplier keys only.
- Recommended first-pass values:
  - `MULTIPLIER_SCORE_ON_NEUTRAL -0.9`
  - `MULTIPLIER_DAMAGE_NEUTRAL_NEG` equal to that role's existing `MULTIPLIER_DAMAGE_ALLY_NEG`
  - `MULTIPLIER_CONTROL_NEUTRAL_POS 0.0` for control-capable roles
  - `MULTIPLIER_CONTROL_NEUTRAL_NEG` equal to or slightly below that role's `MULTIPLIER_CONTROL_ALLY_NEG`
  - `MULTIPLIER_DOT_NEUTRAL_NEG` equal to `MULTIPLIER_DOT_ALLY_NEG` where that role has DoT/zone behavior
- Do not block `Hold Person`, `Cloud of Daggers`, or other individual spells for this issue.
- Do not add protected-NPC diagnostics in the first implementation unless testing later proves they are needed.
- Do not add runtime protected-neutral tagging in the first implementation unless archetype-only tuning fails.

Performance cleanup scope:

- Add a cheap UTAC runtime-state guard before expensive `LeftCombat` cleanup.
- Skip `UTACSpellPolicy.ClearForCharacter` and block-status sync for characters with no UTAC state.
- Add a cheap `UTACSpellPolicy.HasStateForCharacter(character)` helper so clear calls can return immediately when no stripped spells, policy status, or slot limiter state exist.
- Pre-filter `EnteredCombat` summon automation so template/exclusion checks run only for likely summons or party followers.
- Evaluate combat-only summon AI application as an optional safer model for utility summons: detect summons when they appear, but defer applying `UTAC Summon`/combat control until combat starts, then clear/relax control after combat if appropriate.
- Compare that model against the current always-on summon automation before changing behavior, because combat-only control may be safer for Pack Rats-style utility summons but worse for users who want summons controlled immediately.
- Keep full cleanup on Release AI Control, mod disable, settings rebuild, and real UTAC-controlled combat exits.
- Do not change combat behavior, NPC Mode ownership/restore, spell policy behavior, or summon automation outcomes.

Runtime validation needed:

- Last Light Inn ambush: UTAC actors should not attack/control Isobel when real enemies exist.
- Harpy fight: UTAC actors should not control/damage Mirkon.
- Bugbear assassin / Soul Coin tiefling: UTAC actors should not control/damage the protected yellow NPC.
- Normal enemy-only combat: UTAC roles should still attack real enemies normally.
- No UTAC statuses, one enemy, flee combat to camp: `LeftCombat` handler time should drop sharply.
- Normal UTAC companion combat enter/end still applies and clears helpers correctly.
- NPC Mode companion still becomes NPC in combat and returns after combat.
- Vanilla Find Familiar still receives `UTAC Summon`.
- Pack Rats exclusions still prevent `UTAC Summon`.

### Version 1.1.2.5 - Spell Policy And Support Role Hotfix

Status: implemented in workspace, pending release packaging.

Trigger:

- User testing showed blocked spells could still fire even when dynamic stat patching and late `UsingSpell` cleanup detected the attempt.
- Healer could lose healer identity through the nonurgent General AI override path, making it harder to evaluate healer behavior and weakening ally-heal consistency.

Scope:

- Change dynamic blocked-spell patching to a simple TAC/AI Allies-style `RequirementConditions` gate: `not HasStatus('UTAC_ALLY')`.
- Keep exact spell-ID matching and MCM `list_v2` behavior.
- Reapply blocked-spell stat gates on `StatsLoaded`, `SessionLoaded`, and `LevelGameplayStarted` so persisted MCM lists survive reload/restart stat resets.
- Always reverify already-patched blocked spells instead of trusting stale `patchedSpells` state.
- Keep spell removal/restoration, queue purge, and post-leak cleanup as fallback layers only.
- Keep `UTAC_SPELL_POLICY_BLOCKED` as a compatibility/diagnostic cleanup status, but do not depend on it as the primary hard gate.
- Remove the Support Healer nonurgent General AI override path so Support Healer stays on the healer archetype at all times.
- Retune Support Healer ally-heal and low-HP target bias upward.
- Clarify MCM wording that the editable spell list blocks selected spell IDs, not just nudges the AI away from them.

Runtime validation needed:

- With Spell Policy enabled, blocked vanilla spells such as `Target_BlessingOfTheTrickster`, `Target_Sanctuary`, and `Zone_Thunderwave` should not fire from UTAC-controlled actors.
- NPC Mode casters should respect the same blocked-spell list.
- MCM list edits should still require exact spell stat IDs.
- Combat end, Release AI Control, and UTAC disable should still restore removed spells and clear temporary policy/slot limiter state.
- Support Healer should keep healer archetype behavior across urgent and nonurgent turns.

### Version 1.1.2 Candidate - UTAC Control QoL / Release All AI Control

Status: planned notes only.

Trigger:

- User-facing QoL request: if an AI-controlled companion makes a bad choice mid-combat, there should be a fast way to stop UTAC control without individually targeting every actor.
- This is especially useful for edge-case story fights, accidental self-AI control, or when a user wants to immediately take manual control back.

Proposed scope:

- Add a new host-only `UTAC Control` spell container.
- Move/duplicate control utilities into that container so the existing archetype and order containers stay less cluttered.
- Add a new no-target `Release All AI Control` shout.
- Keep existing single-target `Release AI Control`.
- Optionally include `Check Archetype` in the same control container if it keeps UX clearer.
- Grant the container through the existing host-only bootstrap path, like `Target_UTAC`, `Target_UTAC_Orders`, and `Shout_UTAC_Rally`.

Implementation notes:

- The new shout should be handled in Lua, not only through stat `RemoveStatus` functors.
- The Lua handler should iterate known/tracked UTAC-controlled actors and call the existing `ReleaseUTACControl(target, caster, "release all control")` path for each one.
- This is required because `ReleaseUTACControl` clears runtime tracking, combat cache state, spell policy state, slot limiter statuses, NPC-mode restore state, target orders, helper statuses, passive grants, and player/NPC ownership safely.
- The shout must not touch non-UTAC actors, enemies, neutral NPCs, or manually unrelated statuses.
- Summons should lose UTAC control/statuses but should not be unsummoned.
- If the entire party, including the host/player character, is currently AI-controlled, the spell may be unavailable until the player regains a controllable actor. That is an acceptable consequence of letting users put the host under AI control.

Runtime validation needed:

- Single-target Release AI Control still works.
- Release All AI Control removes UTAC control from every tracked companion/summon/player AI actor in combat.
- Release All AI Control does not remove non-UTAC statuses.
- Release All AI Control clears spell policy and slot limiter state.
- Release All AI Control does not break NPC Mode cleanup for future combats.

### Version 1.0.9 - Bruiser/Assassin Pathing, Jump Block, And NPC Mode Throw Safety

Status: implemented in workspace, pending validation and release packaging.

Implementation plan: `Audit/UTAC_1_0_9_IMPLEMENTATION_PLAN_2026-05-04.md`

Trigger:

- Nexus user report: Bruiser companions can leap down from high places, e.g. Goblin Camp beams near Dror Ragzlin, even without Feather Fall.
- Nexus/user report: thrown items can sometimes explode in a party member's face when companions are using NPC Mode.
- Local 1.0.8 testing: Assassin can still over-prioritize reaching a preferred target and run through opportunity attacks more often than other tested archetypes.
- Local 1.0.8/1.0.7 spell-policy log review: `Target_BlessingOfTheTrickster` can still reach the late `UsingSpell` guard, which proves UTAC spell policy is active but suggests the early dynamic stat patch is not reliably preventing native AI selection.
- Existing static action blocks for Dash, Throw, and Shove appear more reliable than dynamic spell policy because they are stat-level gates present before native AI evaluates the action.

Current findings:

- `Melee_Bruiser` currently strongly rewards closing to enemies: `MULTIPLIER_ENDPOS_ENEMIES_NEARBY 10.0`, `MULTIPLIER_CONTACT_BOOST 2.5`, and `MULTIPLIER_PLANNED_ACTION_WITH_MOVE_SPELL 2.0`.
- `Melee_Bruiser` explicitly has `ENABLE_MOVEMENT_AVOID_AOO 0.0`, unlike safer movement roles.
- Vanilla AI has fallback jump and fall-damage scoring, but UTAC Bruiser's aggressive melee scoring can amplify native bad vertical choices.
- Assassin already has `ENABLE_MOVEMENT_AVOID_AOO 1.0`, and vanilla `base.txt` also sets `ENABLE_MOVEMENT_AVOID_AOO 1.0`, so missing AOO avoidance is probably not the root issue.
- Assassin remains a target-pressure outlier: `MULTIPLIER_TARGET_PREFERRED 12.0`, `MULTIPLIER_DAMAGE_ENEMY_POS 4.0`, `MULTIPLIER_KILL_ENEMY 3.0`, `MULTIPLIER_TARGET_KNOCKED_DOWN 3.0`, and `MULTIPLIER_TARGET_INCAPACITATED 3.0`.
- Assassin also still rewards moving to enemy/flanking end positions: `MULTIPLIER_ENDPOS_ENEMIES_NEARBY 0.8`, `MULTIPLIER_ENDPOS_FLANKED 0.25`, and `MULTIPLIER_ENDPOS_TURNED_INVISIBLE 0.80`. This likely contributes to the observed "runs toward enemies, then away from enemies in the same turn" opportunity-attack pattern.
- Vanilla `base.txt` uses `MULTIPLIER_TARGET_PREFERRED 2.0`; vanilla rogue has very low/neutral end-position pressure; AI Allies trickster uses `MULTIPLIER_TARGET_PREFERRED 6.0`, `MULTIPLIER_ENDPOS_ENEMIES_NEARBY 0.0`, and `MULTIPLIER_ENDPOS_TURNED_INVISIBLE 0.80`.
- `MULTIPLIER_MOVEMENT_COST_MULTPLIER` exists but vanilla `base.txt` marks it deprecated, so do not rely on it as the main Assassin AOO fix.
- `MULTIPLIER_POSITION_LEAVE` exists in vanilla, but vanilla comments describe it as jump/teleport leave-position scoring, not general walking/AOO path safety, so treat it as secondary/experimental.
- UTAC already has an optional `Block Throw for UTAC allies` setting that gates `Throw_Throw`, `Throw_ImprovisedWeapon`, and `Throw_FrenziedThrow` through `UTAC_THROWING_DISABLED`.
- UTAC already gates Dash/Throw/Shove with static `Block_UTAC.txt` overrides using `not HasStatus('UTAC_ALLY') or not HasStatus('<DISABLE_STATUS>')`, then applies the disable status at runtime through MCM settings.
- If throw explosions happen while that setting is disabled, the practical user workaround is enabling it. If it happens while enabled, UTAC is missing a throw variant or NPC Mode is bypassing the stat gate.
- Vanilla/common jump is represented as projectile jump spells such as `Projectile_Jump`; several story or creature-specific variants use or derive from jump spells. Jump blocking should start narrow with common player/companion jump, not broad story/monster jump variants.
- AI Allies blocks selected utility spells with hardcoded spell stat overrides and one shared hidden status, `AlliesBannedActions`; it does not create one status per spell.
- Gabe's AI addon does not appear to include a generic spell blocker; the main Gabe mod uses `AIFlags "CanNotUse"` for its own command/container spell, which is not suitable for an editable UTAC blocked-spell list.
- Standalone Spell Blocker is the closest reference for a dynamic list: patch `RequirementConditions`/`TargetConditions`, remove owned spells, and keep `UsingSpell` purge as the last safety net. Earlier UTAC builds used context-dependent caster gates; the current hotfix path uses a simpler no-context `UTAC_ALLY` gate in `RequirementConditions`.

Goal:

- Keep Bruiser aggressive, but reduce obviously unsafe vertical pathing and fall-damage jumps.
- Keep Assassin mobile and priority-target focused, but reduce target tunneling that overpowers native AOO avoidance.
- Add an optional static `Block Jump for UTAC allies` setting using the same approach as Dash/Throw/Shove, so users can stop AI-controlled companions from spending actions or taking unsafe vertical jumps.
- Harden UTAC spell policy so blocked spells are rejected during native AI spell selection, not only caught by the late `UsingSpell` guard.
- Improve discoverability/reliability of throw safety for NPC Mode without globally changing default behavior unless testing proves it is needed.
- Avoid adding broad hard blocks that flatten Bruiser into Protector/General.

Proposed scope:

- Tune `Melee_Bruiser.txt` only:
- Lower `MULTIPLIER_ENDPOS_ENEMIES_NEARBY` from the extreme current value.
- Lower or normalize `MULTIPLIER_PLANNED_ACTION_WITH_MOVE_SPELL`.
- Set `ENABLE_MOVEMENT_AVOID_AOO 1.0`.
- Consider adding/raising `MULTIPLIER_FALL_DAMAGE_SELF` if validator/runtime testing confirms it affects jump-down behavior.
- Do not disable jumping entirely.
- Tune `Hybrid_Assassin.txt` only for Assassin AOO follow-up:
- Prioritize end-position scoring before adding obscure/deprecated movement-cost knobs.
- Lower `MULTIPLIER_ENDPOS_ENEMIES_NEARBY` from `0.8` to `0.0`, matching vanilla rogue / AI Allies trickster behavior.
- Lower `MULTIPLIER_ENDPOS_FLANKED` from `0.25` to `0.0`, matching vanilla rogue and removing incentive to reposition around enemies just for flank scoring.
- Lower `MULTIPLIER_ENDPOS_TURNED_INVISIBLE` from `0.80` to around `0.3-0.5` so invisibility does not over-reward risky repositioning after the AI has already approached.
- Lower `MULTIPLIER_TARGET_PREFERRED` from `12.0` toward AI Allies-style values, likely `8.0` first and `6.0` only if testing still shows hard target tunneling.
- Lower `MULTIPLIER_TARGET_KNOCKED_DOWN` and `MULTIPLIER_TARGET_INCAPACITATED` from `3.0` to around `2.0`.
- Optionally lower `MULTIPLIER_KILL_ENEMY` from `3.0` to around `2.25` only if Assassin still accepts bad pathing for kill attempts.
- Keep `ENABLE_MOVEMENT_AVOID_AOO 1.0`.
- Do not use `MULTIPLIER_MOVEMENT_COST_MULTPLIER` as the main fix because vanilla marks it deprecated.
- Treat `MULTIPLIER_POSITION_LEAVE` as a secondary suspect only for jump/teleport-style turns because vanilla describes it as jump/teleport leave-position scoring, not general walking/AOO pathing.
- Add optional Jump block via the existing static action-block pattern:
- Add hidden `UTAC_JUMPING_DISABLED` status alongside `UTAC_DASHING_DISABLED`, `UTAC_THROWING_DISABLED`, and `UTAC_SHOVING_DISABLED`.
- Add MCM checkbox `MCM_DisableUTACJump`, default `false`.
- Add localized MCM wording: `Block Jump for UTAC allies`.
- Description should explain it blocks normal AI Jump while active, useful if companions make unsafe vertical jumps, but may reduce mobility/pathing.
- Add `Projectile_Jump` to `Block_UTAC.txt` with `RequirementConditions` gated by `UTAC_ALLY` and `UTAC_JUMPING_DISABLED`.
- Review and only add additional player/companion jump variants if confirmed safe and not story/creature-specific.
- Do not globally block all spells with `IsJump`, because that risks breaking scripted NPC/monster/story jump behavior.
- Sync `UTAC_JUMPING_DISABLED` exactly like Dash/Throw/Shove on combat apply, TurnStarted, setting changes, cleanup, and combat end.
- Harden `UTACSpellPolicy.lua` without per-spell statuses:
- Keep the single shared hidden status `UTAC_SPELL_POLICY_BLOCKED` for compatibility/diagnostics, but do not rely on it as the primary hard gate.
- Do not create hardcoded statuses for each blocked spell.
- Keep the editable MCM blocked-spell list.
- Use the current hotfix gate `not HasStatus('UTAC_ALLY')` in `RequirementConditions`, matching TAC/AI Allies-style simplicity while still being dynamically patched from the editable MCM list.
- Do not patch `TargetConditions` in the current hotfix path; target conditions often evaluate target context differently from caster requirements and caused unreliable behavior.
- Keep `RemoveSpell`/`AddSpell` tracking as a fallback and cleanup layer for blocked spells that are owned by the character.
- Keep `UsingSpell` + `PurgeOsirisQueue` as the final guard only; logs should make clear when a spell reached this late guard so leaks can be identified.
- Add debug diagnostics that can print the post-patch `RequirementConditions` and `TargetConditions` for each enabled blocked spell when spell policy debug is enabled or during a one-shot resync log.
- Do not add static `Block_UTAC` entries for arbitrary user MCM spell IDs; the MCM list must stay dynamic.
- Review throw spell variants against vanilla stats and add missing UTAC throw gates only if confirmed.
- Consider clearer MCM wording for `Block Throw for UTAC allies`, especially that it is useful when NPC Mode causes unsafe thrown-item behavior.
- Do not change NPC Mode ownership/restore behavior in this patch unless direct evidence shows it is required.

Runtime validation:

- Bruiser on elevated platforms should not jump down into avoidable fall damage just to close distance.
- Bruiser should still engage melee targets when safe routes exist.
- Assassin should remain a mobile priority-target eliminator, but should be less willing to run through obvious opportunity attacks just to reach a marked/killable target.
- Assassin should not regress into preferring low-value one-target AoE/zone casts.
- With `Block Jump for UTAC allies` enabled, common companion Jump should be unavailable to UTAC-controlled companions in combat.
- With `Block Jump for UTAC allies` disabled, normal jump behavior should remain unchanged.
- Jump block should not affect manual player-controlled characters outside UTAC control and should not break story/creature-specific jump variants.
- With spell policy enabled, `Target_BlessingOfTheTrickster` should be rejected before AI action selection when Shadowheart has `UTAC_ALLY`; the late `UsingSpell` guard should not be the normal path.
- Default blocked spells (`Shout_FeatherFall`, `Target_FogCloud`, `Target_BlessingOfTheTrickster`) should still be editable through MCM, and user-added spell IDs should still be dynamically patched where stats exist.
- Combat end, Release AI Control, UTAC disable, and spell-policy disable should restore removed spells and clear temporary spell policy / slot limiter state.
- Debug/log review should show whether a blocked spell was patched, removed, restored, or late-guarded.
- `Block Throw for UTAC allies` should prevent common throw/improvised/frenzied throw actions for both normal UTAC combat statuses and NPC Mode combat statuses.
- NPC Mode companions should still enter/exit combat correctly.
- Assassin 1.0.8 pathing tuning should not regress.

## Implemented Plan Details

### Version 1.0.8 - Summon Exclusions And Archetype Safety Tuning

Status: implemented in workspace; retained as detailed design notes.

Trigger:

- Nexus user Illius confirmed on 2026-04-28 that Pack Rats utility rats receive `UTAC Summon` on examination.
- Local testing showed Assassin can overvalue AoE/zone spells, e.g. casting `Cloud of Daggers` on a single target.
- Local testing showed Assassin can overvalue aggressive repositioning and trigger opportunity attacks while running past enemies.
- User reports and local testing suggest Healer may be too eager to use hostile control in some story/protected-NPC fights.

Goal:

- Let users exclude utility summons from automatic UTAC summon control.
- Keep normal vanilla summon automation working.
- Keep manual archetype assignment possible if a user deliberately targets an excluded summon.
- Reduce obvious role-score outliers without flattening archetype identity.
- Make Healer less eager to use hostile control without globally blocking valid control spells.

Design:

- Add an advanced editable MCM list for summon exclusion root/template UUIDs.
- Seed the default list with confirmed Pack Rats utility summon root/template UUIDs so Pack Rats compatibility works out of the box.
- Accept root/template UUIDs only. Do not accept plain names, status names, or passive names in the first public version.
- Make MCM wording clear that runtime spawned character UUIDs usually change and should not be used.
- Check exclusions before applying `UTAC_SUMMON` or `UTAC_IS_CONTROLLED`.
- If an excluded summon was already tracked by UTAC, remove only UTAC-owned summon/control statuses and untrack it.
- Avoid retry/log spam.
- Do not add `Target_HoldPerson` to the default spell block list just because it was used on a neutral/protected NPC.
- Lower `Hybrid_Assassin` AoE and multi-target scoring so Assassin remains a priority-target eliminator instead of a zone/AoE caster.
- Do not block `Cloud of Daggers`; fix the archetype weighting first.
- Add explicit Assassin opportunity-attack movement safety, likely `ENABLE_MOVEMENT_AVOID_AOO 1.0`, so behavior does not depend only on inherited base values.
- Lower Assassin enemy-proximity and flanking end-position weights so it stays mobile without overvaluing dangerous pathing through threatened spaces.
- Do not hard-disable Assassin movement, Dash, rogue mobility, or target-seeking behavior; tune scoring first.
- Consider lowering `Support_Healer` `MULTIPLIER_CONTROL_ENEMY_POS` so healer uses hostile control less eagerly.
- Consider adding explicit healer neutral-control safety values such as `MULTIPLIER_CONTROL_NEUTRAL_POS 0.0` and a stronger `MULTIPLIER_CONTROL_NEUTRAL_NEG`, after stats validation.
- Do not globally block `Hold Person`; use diagnostics and scoring before blacklists.
- Do not add `Mass Healing Word` diagnostics in 1.0.8. Handle it later only if stronger runtime evidence justifies it.

Validation gate:

- Pack Rats validation targets are root/template UUIDs, not status names:
- `242bfc84-42ad-4719-8b34-ff854332317d`
- `c04db4ef-3902-4ffb-9b84-e0f443b12bb3`
- `99c92762-14b2-4660-9781-6a365f8ccebd`
- `0d6d85ce-c985-4a1f-be91-a2aaba8e3c57`
- `6d730ba9-0573-4351-8227-f077c0181082`
- `b99d4d1f-c68f-4ed7-8962-7cb2d288a89b`
- `1a8fe2e9-518c-4e64-bfef-54b1ebb5d242`
- `58712c7a-84fa-46a7-beaf-d7e8c480203d`
- Assassin should stop preferring AoE/zone spells for single-target assassin behavior.
- Assassin should avoid obvious opportunity-attack pathing more reliably while still behaving like a mobile priority-target role.
- Healer should be less eager to use hostile control while still keeping control spells available against real enemies.
- Stats validator must accept any newly added neutral-control archetype multipliers before release.

Reference plan:

- `UTAC Docs/Audit/UTAC_1_0_8_IMPLEMENTATION_PLAN_2026-05-03.md`
- `UTAC Docs/Audit/USER_FEEDBACK_COMPATIBILITY_PLAN_2026-04-27.md`

## Planned But Riskier

### Spell Slot Limiter Follow-Ups

Status: deferred until after the first UTAC spell policy / limiter patch.

Goal:

- Give users an opt-in way to make caster AI faster and more conservative.
- Temporarily block high-level normal spell slots during low-pressure combat.
- Reduce early high-slot spending without changing default behavior.

Current decision:

- Default off.
- Use new MCM settings instead of repurposing `ConserveHighSlots`.
- Block normal `SpellSlot` only in the first implementation.
- Do not block `WarlockSpellSlot` by default.
- Apply only to caster-oriented UTAC roles in the first pass: Spellcaster, AoE Specialist, Healer, and General if the character has normal spell slots.
- Do not apply to Summon, Bruiser, Marksman, Protector, Skirmisher, or Assassin until tested.

Likely design:

- Add hidden statuses such as `UTAC_SLOT_LIMIT_L3_PLUS`.
- Use `ActionResourceBlock(SpellSlot,n)` for blocked levels.
- Sync the limiter on TurnStarted before existing combat tactics.
- Remove the limiter under pressure, healer emergencies, release control, combat end, mod disable, and cleanup/rebuild paths.
- Keep logging minimal and avoid retry loops.

Important limitations:

- This reduces spell-slot options, but it will not fix every slow caster turn.
- Native AI still evaluates movement, items, cantrips, class actions, reactions, and modded spells.
- Custom spell resources are not covered in the first pass.
- Warlock behavior needs separate testing because warlock slots always scale upward.
- If configured too aggressively, this can make caster AI weaker or cause worse fallback turns.

Validation gate:

- Norbyte stats validation for all new limiter statuses.
- JSON/XML validation for new MCM settings and localization.
- In-game test with Wizard/Sorcerer low-pressure and high-pressure fights.
- Healer urgent/downed-ally test.
- Release AI Control and combat-end cleanup test.
- NPC Mode caster test.
- Warlock test to confirm warlock slots remain unblocked by default.

Reference plans:

- `UTAC Docs/Audit/SPELL_SLOT_LIMITING_PLAN_2026-04-29.md`
- `UTAC Docs/Audit/SPELL_POLICY_AND_SLOT_LIMITER_RESEARCH_2026-05-01.md`

### Later/TBD - Strict Role Helpers

Status: planned as experimental, not guaranteed.

Goal:

- Add optional hidden mechanical nudges to discourage clearly off-role actions.
- Keep this default off.
- Do not replace archetype scoring with hard behavior locks.

Current scope:

- Include only Bruiser, Marksman, and Spellcaster in the first prototype.
- Skip Healer. Healer should be tuned through triage/resource logic first.
- Skip General and Summon because they are fallback/balanced profiles.
- Skip Skirmisher and Assassin initially because they are intentionally hybrid/mobile.
- Defer Protector aura because it may encourage clumping.

Current role-helper ideas:

- Bruiser: modest ranged-attack penalty only.
- Marksman: modest melee-attack penalty only.
- Spellcaster: modest weapon-attack penalty and possibly small spell-attack support.

Do not do in first pass:

- Do not add broad disadvantage everywhere.
- Do not add Healer weapon penalties.
- Do not add Protector aura until clumping risk is tested.
- Do not force Bladesinger-style hybrids into Spellcaster. Use Skirmisher, Assassin, or Balanced instead.

Validation gate:

- Stats validator for every conditional boost.
- In-game tests with resource-starved turns.
- Test hybrid builds so fallback behavior is not destroyed.
- Confirm AI does not skip more turns.

Reference plan:

- `UTAC Docs/Audit/COMBINED_SCULPT_ROLE_HELPER_MCM_LOCALIZATION_PLAN_2026-04-28.md`
- `UTAC Docs/Audit/SCULPT_SPELLS_AND_ROLE_HELPER_IMPLEMENTATION_PLAN_2026-04-28.md`

## Compatibility Backlog

### AmbientAI Compatibility Contract

Status: researched, external coordination preferred.

Goal:

- Avoid out-of-combat idle automation touching UTAC-controlled summons or NPC-mode/combat actors.

Preferred solution:

- UTAC exposes a small compatibility signal/helper.
- AmbientAI skips characters that UTAC marks as controlled, NPC-mode pending, or active combat automation targets.

Fallback:

- Add UTAC-side compatibility only if users report concrete runtime conflicts and there is a safe way to scope it.

Reference plan:

- `UTAC Docs/Audit/SCULPT_SPELLS_AND_AMBIENTAI_RESEARCH_2026-04-27.md`

## Archetype Coverage

Status: no role changes planned right now.

Current roles are distinct enough:

- Bruiser: aggressive melee/frontline pressure.
- Marksman: ranged single-target pressure and distance.
- Protector: defensive bodyguard, ally proximity, buffs/support, control, revive priority.
- Healer: triage healing and emergency support.
- Skirmisher: mobile melee or hybrid hit-and-run.
- Assassin: priority-target burst, opportunistic ranged/melee/spell hybrid.
- AoE Specialist: clustered-target and area damage focus.
- Spellcaster: spell-first safe-distance caster, not strictly single-target.
- Balanced: general fallback.
- Summon: balanced summon-specific fallback.

Current decision:

- Do not add a dedicated Debuffer/Controller now. BG3 debuffs and CC are already strong, and current Spellcaster/AoE/Protector/Skirmisher/Assassin profiles already value control or enemy debuffs enough that users are seeing Polymorph, Hold Person, and similar openers.
- Do not change Protector into a pure buffer. Protector is already the bodyguard/buffer role and should keep caring about both allies and nearby enemies.
- Keep a future Buffer/Enabler or Tactician archetype as a low-priority idea only if users specifically want support behavior that is not healing.

Future archetype research:

- `UTAC Unarmed` is the cleanest next role candidate. It should target monk / tavern-brawler / unarmed builds, disable weapon pickup, and stay separate from Druid/Wild Shape behavior.
- Druid support should be split later into caster druid behavior and optional Wild Shape behavior. Vanilla Wild Shape uses spell/status helpers and beast/melee overrides after transformation, so it should not be treated as a simple archetype-only patch.
- `UTAC Summon` remains a role for already-summoned units. A true Summoner/Conjurer caster role should wait until UTAC has a safer spell preference/helper system because vanilla summon-related multipliers mostly affect existing summons, not casting summon spells.
- AI-only spell variants are a separate future pass. The first small candidate is `Shout_UTAC_ActionSurge_AI`, modeled after AI Allies' Action Surge variant, but it may still work reliably only in NPC Mode and must be tested before release.

Reference plan:

- `UTAC Docs/Audit/DEBUFF_BUFF_ARCHETYPE_ROADMAP.md`
- `UTAC Docs/Audit/ARCHETYPE_EXPANSION_RESEARCH_2026-05-08.md`

## Not Planned Right Now

- No broad refactor.
- No new role archetypes before Sculpt and compatibility work.
- No strict role helpers by default.
- No Healer role penalty.
- No hard action blacklists for classes or items unless a specific bug requires it.
- No packaging automation; packaging remains manual.

## Release Rules

Before any release:

- Review `git diff`.
- Keep unrelated gameplay systems out of the patch.
- Validate touched JSON/XML/stats files.
- Run `git diff --check`.
- Update `UTAC Docs/CHANGELOG.md`.
- Write a short Nexus changelog.
- Do at least one in-game smoke test for touched systems.
