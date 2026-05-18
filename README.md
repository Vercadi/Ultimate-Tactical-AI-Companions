# Ultimate Tactical AI Companions

[![Source release](https://img.shields.io/github/v/release/Vercadi/Ultimate-Tactical-AI-Companions?label=source%20release)](https://github.com/Vercadi/Ultimate-Tactical-AI-Companions/releases)
[![License](https://img.shields.io/badge/license-source--available-lightgrey)](LICENSE)
[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-player%20download-orange)](https://www.nexusmods.com/baldursgate3/mods/22558)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-ff5f5f)](https://ko-fi.com/vercadi)
[![Patreon](https://img.shields.io/badge/Patreon-support-f96854)](https://www.patreon.com/cw/Vercadi)

Ultimate Tactical AI Companions (UTAC) adds tactical AI control for Baldur's Gate 3 companions, summons, and party allies. The main goal is AI control: assignment, archetype behavior, target ordering, combat/exploration control state, and safe enable/disable behavior.

Optional mechanical assistance exists, but it is MCM-gated and off by default.

This GitHub repository is for source/reference use. Players should download the packaged mod from Nexus Mods.

## Media

Screenshots, images, and packaged player files are hosted on the [Nexus Mods page](https://www.nexusmods.com/baldursgate3/mods/22558). No screenshot asset is currently tracked in this source repository.

## Download

- Player download: [UTAC on Nexus Mods](https://www.nexusmods.com/baldursgate3/mods/22558)
- Source release: [GitHub Releases](https://github.com/Vercadi/Ultimate-Tactical-AI-Companions/releases)
- Source repository: [GitHub](https://github.com/Vercadi/Ultimate-Tactical-AI-Companions)

Do not install GitHub source archives as packaged BG3 mods. Use the Nexus file for normal play.

## Requirements

- Baldur's Gate 3
- BG3 Script Extender
- BG3 Mod Configuration Menu (BG3MCM)

BG3MCM is a hard dependency. UTAC uses it for the supported settings UI and host-authoritative settings behavior.

## Installation

1. Install or update BG3 Script Extender.
2. Install BG3MCM.
3. Download the packaged `.pak` from [Nexus Mods](https://www.nexusmods.com/baldursgate3/mods/22558).
4. Install it with your normal BG3 mod manager workflow.
5. Enable the mod and load the game.

## Update

Download the latest packaged file from Nexus Mods and replace the old version through your BG3 mod manager. Review the [changelog](CHANGELOG.md) before updating a long-running save, especially when using NPC Mode, spell policy, or modded spell packs.

## Usage

- Assign companions, summons, or party allies to tactical AI archetypes.
- Use companion AI control and release spells to hand control over or take it back.
- Use Manual Focus Target and Ignore Target orders for priority decisions.
- Configure optional helpers, action blocks, spell policy, and summon exclusions in BG3MCM.

Main AI archetypes: Bruiser, Skirmisher, Assassin, Marksman, Protector, Healer, AoE Specialist, Spellcaster, General AI, Unarmed, Primal Druid, and Summoner.

## Important Notes

- UTAC's default experience is AI control, not hidden combat power.
- Optional helper and buff systems are off by default.
- Action Surge and some resource/self-targeting actions usually behave best with NPC Mode enabled on that AI companion.
- In co-op, UTAC logic runs on the host. Only the host's MCM settings affect gameplay.
- NPC Mode is optional and per-character. Archetypes still matter in NPC Mode because UTAC applies NPC-mode combat statuses with the same AI archetype overrides.
- Other mods that override AI archetypes, vanilla action spells, or the same statuses may conflict.
- Modded classes, modded spells, and custom action resources are not fully tested. Report exact class/spell/resource mods when behavior looks wrong.
- Native AI pathing can still misread environmental hazards that are not represented as dangerous surfaces.
- Sculpt Spells safety only affects spells that respect BG3's `SculptSpells` passive behavior. It does not protect against every AoE, surface, aura, or modded spell.
- Spell policy and spell-slot limiter are optional and default off. Prepared/class spells may still appear in the spellbook or hotbar because BG3 owns that UI.
- Dash, Throw, Jump, and Shove blocks are optional and default off. Throw blocking covers common Throw, Improvised Weapon, and Frenzied Throw actions, not every story/modded throw variant.
- Summon automation supports vanilla summons and common temporary party-follower summon patterns. Utility summons can be excluded by root/template UUID in MCM.

## Compatibility

UTAC works through BG3 Script Extender and BG3MCM. Conflicts are most likely with mods that edit the same AI archetypes, statuses, action spells, or spell metadata. AoE Specialist can expose unsafe or incomplete AI metadata in modded AoE spell packs; use Spellcaster or General AI if a modded AoE caster skips turns or crashes.

## Bug Reports / Support

Please include:

- full Script Extender Runtime log
- party composition and level
- which companions/summons were UTAC-controlled
- selected archetypes and relevant MCM settings
- whether the issue happened in combat, exploration, after save/load, or after long rest
- exact reproduction steps when possible

Use [Nexus Mods](https://www.nexusmods.com/baldursgate3/mods/22558) for player-facing support and [GitHub Issues](https://github.com/Vercadi/Ultimate-Tactical-AI-Companions/issues) for source or compatibility work. Support continued work through [Ko-fi](https://ko-fi.com/vercadi) or [Patreon](https://www.patreon.com/cw/Vercadi).

## Source Layout

- `UTAC/` - BG3 mod source folder.
- `CHANGELOG.md` - public release changelog.
- `LICENSE` - source-available license terms.

Package archives, build outputs, logs, and internal planning notes are intentionally not tracked in this public repository.

## Project Metadata

- Public mod name: `Ultimate Tactical AI Companions`
- Short name: `UTAC`
- Module folder: `UTAC`
- Module UUID: `300fb883-8af8-4be9-a101-171b56698dc5`
- Version: `1.1.3.0`

## License

See [LICENSE](LICENSE).
