# Doodle display faces

Used only for the Savvy wordmark and page titles (≥20pt). Stamp names stay
San Francisco until the shared stamp PR. Body copy stays San Francisco
via `SaveAtlasType` (system rounded).

## Caveat SemiBold — Latin

- File: `Caveat-SemiBold.ttf`
- Source: https://github.com/googlefonts/caveat and
  https://github.com/google/fonts/tree/main/ofl/caveat
- Instantiated at `wght=600` from the upstream variable `Caveat[wght].ttf`
  (403,648 bytes) with `fontTools.varLib.instancer`
- License: SIL Open Font License 1.1 (`LICENSES/caveat/OFL.txt`)
- PostScript name: `Caveat-SemiBold`
- No Reserved Font Name

## Iansui (芫荽) Regular — CJK titles

- Upstream: Iansui v1.020 `Iansui-Regular.ttf` (9,447,424 bytes)
  https://github.com/ButTaiwan/iansui/releases/tag/v1.020
- Bundled file: `Iansui-SavvySubset.ttf` — MOE 4808 common characters plus
  fixed title / city-switcher strings. Rebuild with
  `scripts/subset-iansui.py --src Iansui-Regular.ttf`
- Charset tables live in `scripts/doodle-fonts/` so this folder ships only
  the font files and OFL licenses
- License: SIL Open Font License 1.1 (`LICENSES/iansui/OFL.txt`)
- PostScript name remains `Iansui-Regular` (no Reserved Font Name)
- Missing glyphs cascade to PingFang TC via `kCTFontCascadeListAttribute`

The handwritten Iansui glyf table does not compress to the spec's 1.5 MB
hope at 4808 coverage. The shipped subset is the smallest TTF that still
keeps those characters; leftover glyphs fall back to PingFang TC.

The App Clip ships `Iansui-ClipTitles.ttf` (state-title glyphs only; rebuild
with `scripts/subset-iansui-clip.py`). Missing Clip title glyphs cascade to
Caveat (`UIFontDescriptor.AttributeName.cascadeList`), then the system font.
Do not copy `Iansui-SavvySubset.ttf` into the Clip. See `11-iansui-proof.md`.

Runtime registration is in `SaveDisplayType`. `UIAppFonts` also lists these
files. Titles scale with Dynamic Type (`UIFontMetrics`).
