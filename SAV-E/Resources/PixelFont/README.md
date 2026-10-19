# Pixel display faces

Used only for the Savvy wordmark and page titles. Stamp names stay
San Francisco until the shared stamp PR. Body copy stays San Francisco
via `SaveAtlasType` (system rounded).

## Pixelify Sans — Latin

- Files: `PixelifySans-Regular.ttf`, `PixelifySans-SemiBold.ttf`
- Source: https://github.com/eifetx/Pixelify-Sans
- License: SIL Open Font License 1.1 (`LICENSES/pixelify-sans/OFL.txt`)
- PostScript names: `PixelifySans-Regular`, `PixelifySans-SemiBold`
- Why this face: the 2026-10-19 v5 mocks use mixed-case pixel titles
  (`Savvy`, `Passport`). Silkscreen is also OFL but is all-caps and a poorer
  match. Pixelify remains unmodified.

## Fusion Pixel 12px Prop zh-Hant — CJK fallback

- File: `fusion-pixel-12px-proportional-zh_hant.otf`
- Source: https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.10.16
- License: SIL Open Font License 1.1 (`LICENSES/fusion-pixel/OFL.txt`)
- Component notices: Ark Pixel, Cubic 11, Galmuri (same folder)
- PostScript name: `Fusion-Pixel-12px-Prop-zh-Hant-Regular`
- Why this face: Zpix (最像素) was named in the v5 packet but is **not** OFL.
  Commercial use is USD $1000 / product and modification is forbidden, so it
  is not bundled. Fusion Pixel is OFL, covers Traditional Chinese, and is the
  cascade fallback after Pixelify Sans. Unmodified upstream font.

Runtime registration is in `SavePixelType`. `UIAppFonts` also lists these
files. Titles scale with Dynamic Type (`UIFontMetrics`). Draw pixel chrome
with nearest-neighbour interpolation; do not upscale blurry bitmaps.
