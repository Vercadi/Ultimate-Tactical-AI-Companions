# Ultimate Tactical AI Companions

Ultimate Tactical AI Companions (UTAC) adds tactical AI control for Baldur's Gate 3 companions, summons, and party allies. The main goal is AI control: assignment, archetype behavior, target ordering, combat/exploration control state, and safe enable/disable behavior.

Optional mechanical assistance exists, but it is MCM-gated and off by default.

## Requirements

- Baldur's Gate 3
- Baldur's Gate 3 Script Extender
- BG3MCM

BG3MCM is a hard dependency. UTAC uses it for the supported settings UI and host-authoritative settings behavior.

## Main Features

- Nine tactical AI archetypes: Bruiser, Skirmisher, Assassin, Marksman, Protector, Healer, AoE Specialist, Spellcaster, and General AI.
- Companion AI control and release spells.
- Optional NPC-mode toggle for AI-controlled allies.
- Manual Focus Target and Ignore Target orders.
- Trap and dangerous-surface awareness for exploration safety.
- Optional MCM-gated helper tiers for movement, resource encouragement, archetype buffs, and debug-tier enhanced buffs.
- Optional MCM-gated Sculpt Spells safety helper for supported Evocation AoE spells.
- Optional MCM-gated Dash, Throw, Jump, and Shove blocks for UTAC-controlled allies.
- Optional MCM-gated spell policy and normal spell-slot limiter for UTAC-controlled caster AI.
- Advanced UUID-only summon auto-apply exclusion list for utility summons such as Pack Rats.

## Installation

1. Install or update BG3 Script Extender.
2. Install BG3MCM.
3. Install the packaged `.pak` with your normal BG3 mod manager workflow.
4. Enable the mod and load the game.

This repository contains source files. Packaged release archives are distributed separately on Nexus Mods.

Nexus page: https://www.nexusmods.com/baldursgate3/mods/22558

## Important Notes

- UTAC's default experience is AI control, not hidden combat power.
- Optional helper and buff systems are off by default.
- Action Surge and some resource/self-targeting actions usually behave best with NPC Mode enabled on that AI companion.
- NPC Mode is optional and per-character. Archetypes still matter in NPC Mode because UTAC applies NPC-mode combat statuses with the same AI archetype overrides.
- In co-op, UTAC logic runs on the host. Only the host's MCM settings affect gameplay.
- Other mods that override AI archetypes, vanilla action spells, or the same statuses may conflict.
- Modded classes, modded spells, and custom action resources are not fully tested. Report exact class/spell/resource mods when behavior looks wrong.
- AoE Specialist can expose unsafe or incomplete AI metadata in modded AoE spell packs. Use Spellcaster or General AI if a modded AoE caster skips turns or crashes.
- Native AI pathing can still misread environmental hazards that are not represented as dangerous surfaces.
- Sculpt Spells safety only affects spells that respect BG3's `SculptSpells` passive behavior. It does not protect against every AoE, surface, aura, or modded spell.
- Spell policy and spell-slot limiter are optional and default off. Spell blocking uses turn-scoped AI selection blocking for UTAC-controlled actors; prepared/class spells may still appear in the spellbook or hotbar because BG3 owns that UI. The first slot limiter pass blocks normal `SpellSlot` only, not warlock or custom resources.
- Action blocks are optional and default off. Throw blocking covers common Throw, Improvised Weapon, and Frenzied Throw actions, not every story/modded throw variant.
- Summon automation supports vanilla summons and common temporary party-follower summon patterns. Utility summons can be excluded by root/template UUID in MCM.

## Bug Reports

Please include:

- full Script Extender Runtime log
- party composition and level
- which companions/summons were UTAC-controlled
- selected archetypes and relevant MCM settings
- whether the issue happened in combat, exploration, after save/load, or after long rest
- exact reproduction steps when possible

## Repository Layout

- `UTAC/` - BG3 mod source folder.
- `CHANGELOG.md` - public release changelog.

Package archives, build outputs, logs, and internal planning notes are intentionally not tracked in this public repository.

## Naming

- Public mod name: `Ultimate Tactical AI Companions`
- Short name: `UTAC`
- Module folder: `UTAC`
- Module UUID: `300fb883-8af8-4be9-a101-171b56698dc5`
- Version: `1.1.2.6`

## License

See `LICENSE`.
