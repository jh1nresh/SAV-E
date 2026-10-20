# Savvy Doodle v1 — parity targets (2026-10-20)
Rendered from spec (2026-10-19-doodle-v1-spec.md §1–2, redlines), NOT crops. Source: gen.py → *.html → headless Chrome (google-chrome --headless=new, window 402×874, DSF 1 and 3).
Files: {home,map,passport,friends,paywall}-{light,dark}.png (402×874) + @3x (1206×2622), .html sources, map-mask.png(+@3x; white=exempt Apple Maps surface, black=chrome: status 0–62, city strip y70–118, place card y590–782, tab bar y790–874), contact.png.

## Frame
402×874 pt, full-bleed, no device frame. Status bar 0–62 (9:41). Home indicator 134×5 at bottom 8. Tab bar 84 tall (50 content + 34 bottom safe area), top hairline. Content starts y=70 (62 safe + 8).
## Tokens (light / dark — spec §1 table; dark values from spec, repo not re-read)
paper #FFF9EB/#1E1C19 · ink #2F2E23/#F4F1E4 · forest #0E4A33/#B9E0C9 · muted #62594F/#CFC4B8 · coral #F26B4A/#D97861 · kraft #EADDC6/#4A3F32 · kraftLight #F0E3CA/#3A332A · line #DCCFB9/#4A443B · pencil #A39C8E/#8A8478 · stampRed #C8372D/#E0675C · gold #B8902F/#D9B45A.
Paper: light = 1pt dot grid 16pt ink 7% on page bg only; dark = flat (no dots). Grain noise NOT rendered (deterministic targets). Cards/sheets plain paper.
Shape: 1pt line hairlines, radius 12, list dividers 1pt dashed, no shadows. Coral only on tappables/selected/pins/+; stampRed only stamps, visited pin, Collected strip.
## Measurements
Margins 24. Titles Caveat 600 34pt (h44 at y70). City "Near you · 天壇 Tiantan ▾" Caveat 20 + 2pt coral underline (y118). Chips 32h, r16, gap 8. Home mini-map 354×160 at y198, 3 coral pins. Clues line y366 (24h). Rows 64h, 48pt stickers, gap 12. Collected strip 44h y654 kraft bg, stampRed text. Tab icons 24pt SVG 1.6 stroke, selected coral.
Map: city strip card 48h y70; place card y590 h192 (64 row + note + 44 buttons). Pins 28×36, coral; one stampRed ✓ (visited).
Passport: city chips (北京 7/23, 上海 2/9, 台北 0/4); 6 stickers (3×2, 88pt) on kraftLight panel y198 h328; saved=pencil dashed outline, visited=fill+stamp ring (1×=single red, 3×=double red, 5×=gold). No missions/streak/ledger.
Friends: invite chip + 4 activity rows; no shared-map strip.
Paywall (fullScreenCover, no tab bar): close 44pt, Pro title, one row ✓ "Unlimited saved places" (64h card), note, CTA 56h coral y594, renewal/cancel legal 11pt, Restore/Terms/Privacy 44h links.
Sample data (Tiantan): 天壇公園 Go 0.3km (3×), 四季民福烤鴨 天壇店 Eat 0.8km (1×), 紅橋市場 Go 1.1km, 錦芳小吃 磁器口 Eat 1.4km, 北京自然博物館 (5×). Collected 7/23.
## Fallbacks / deviations
- Body font: SF Pro Rounded unavailable on Linux → Nunito (metrics differ slightly; compare layout boxes, not glyphs).
- Caveat = Google Fonts variable TTF; Iansui = google/fonts Iansui-Regular.ttf (full, not subset). Mixed zh/en titles fall back Caveat→Iansui per glyph.
- Stickers/icons are simple SVG placeholders, not the final hand-drawn assets; parity on position/size only.
- Map surface is a generic placeholder (exempt via mask). Price "¥38/year" is placeholder copy.
- Repo Color+Theme.swift was not re-read for this pass; hex values taken from spec §1 (which cites repo).
- Status-bar icons approximate.
