# UTAC Translator Notes

These notes are for translation patches for Ultimate Tactical AI Companions (UTAC).

## What To Translate

- Use `UTAC/Mods/UTAC/Localization/English/english.xml` as the source string table.
- Translate only the text between `<content>` and `</content>`.
- Do not edit `contentuid`.
- Do not edit `version` unless you intentionally know why the localization version must change.
- Keep XML valid. Escape special XML characters when needed, for example `&amp;`, `&lt;`, and `&gt;`.

## Language Folders

Translation patches should mirror the same contentuid values in the target language folder, for example:

- `Localization/Japanese/japanese.xml`
- `Localization/Korean/korean.xml`

If your build pipeline requires compiled localization, compile the translated XML into the matching `.loca` file before packaging.

## Patch Mod Loading

Translation patches should depend on UTAC and load after UTAC so the translated strings override the original English entries.

## MCM Strings

UTAC MCM entries keep English fallback strings in `MCM_blueprint.json`. Translators should not edit `MCM_blueprint.json`; translate the matching content entries in the localization XML instead.
