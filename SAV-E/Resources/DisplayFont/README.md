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
- Bundled file: `Iansui-SavvySubset.ttf` — every MOE 4808 common character,
  ASCII 0x20–0x7E, and CJK punctuation. Rebuild with
  `scripts/subset-iansui.py --src Iansui-Regular.ttf`
- The 4808 table lives in `scripts/doodle-fonts/` so it is **not** copied
  into the app bundle
- License: SIL Open Font License 1.1 (`LICENSES/iansui/OFL.txt`)
- PostScript name remains `Iansui-Regular` (no Reserved Font Name)
- Missing glyphs cascade to PingFang TC via `kCTFontCascadeListAttribute`

Size gate is 1.5 MB. iOS `UIAppFonts` / `CTFontManager` accept TTF and OTF
only, not WOFF2, so the file stays a TTF. The rebuild drops hinting and
GSUB/GPOS, simplifies handwritten outlines (max error 64/1000 em), then
sets UPEM to 500 so more glyf deltas pack as short vectors.

Runtime registration is in `SaveDisplayType`. `UIAppFonts` also lists these
files. Titles scale with Dynamic Type (`UIFontMetrics`).
