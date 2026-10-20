# Savvy Doodle v1 — parity targets v2 (2026-10-20)
v2 replaces v1's SVG placeholders and generic fonts. The art is cut from the approved mocks (2026-10-19-doodle-v1-*.png) by cut.py: PIL crop, 3× Lanczos plus unsharp, an alpha matte against the cream, and in dark mode ink lines are lifted to light ink and green to light forest. Layout comes from gen.py, with HTML rendered in headless Chrome at 402×874 and @3x.
Fonts: Patrick Hand (stand-in body hand-lettering; Caveat stays the brand title font), Iansui as fallback. Titles and wordmark are cropped art.
Masks: home-mask / map-mask (+@3x), white = exempt Apple Maps surface, black = graded (chrome and pins).
Content follows the mocks: Siji Minfu Roast Duck 450m, Fangzhuanchang Noodles 800m, Grey Cafe 1.1km, Collected 4/12, Mia/Leo/Kai/Ana, Beijing 4 of 12.
Deliberate deviations from the mocks: Friends has no shared-map strip (cut in v1). Map uses Eat/Go chips, not Nearby/Saved/Friends, per the HoP filter rule. Paywall has one benefit row (18:29 lock), keeps the legal text, and has no tab bar (fullScreenCover).
