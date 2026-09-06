# App Clip header

`app-clip-header-1800x1200.png` is a wordless Atlas Postcard illustration for the system App Clip invocation card. A coral location pin and paper-plane postage communicate a shared place. It replaces the local legacy screenshot crop as the proposed header asset.

## Export receipt

- Date: 2026-09-07, Asia/Taipei.
- Final format: PNG, 1800x1200 pixels, RGB, no alpha channel.
- SHA-256: `f0a158d066d14300a263f7593df33e90a8eb38662189298f83dbd350196336dd`.
- Generation: built-in Codex ImageGen, one hosted generation, no revision.
- Source render: 1536x1024; proportionally resampled with macOS `sips --resampleHeightWidth 1200 1800` without cropping or added content.
- Local source: `.tmp/design-work/2026-09-07-appclip-header/evidence/generated-source.png`; generated original `exec-4997104b-7d62-41be-b6fb-92a3ae761061.png`.
- Review: full artwork and 360x240 thumbnail inspected; intact postcard edge, dominant location pin, subordinate postal mark, no readable copy or UI.
- No photographs, third-party logos, real addresses, sender details or user content were used. The map is generic illustration, not geographic or product-state evidence.
- Colour texture varies around the production Atlas palette; this raster does not define or replace theme tokens.
- App Store Connect upload and live configuration verification have not been performed. This file is not an app-bundled resource; changing it in Git does not change the live App Clip card.
- Requirements checked against [Apple App Clips HIG](https://developer.apple.com/design/human-interface-guidelines/app-clips): 1800x1200 opaque PNG/JPEG; prefer graphics or photography and avoid UI screenshots and text.

## Generation prompt

Create one final standalone raster illustration for Savvy's iOS App Clip header. Use case: illustration-story / brand asset. Landscape exact 3:2 aspect ratio, ideally 1800 by 1200 pixels. This is a wordless image communicating receiving a shared place as a beautiful travel postcard. Art direction is Atlas Postcard, artful printed paper illustration, crisp controlled shapes with restrained fine paper grain, not a UI mockup, not a photo and not 3D clay.

Composition: warm cream canvas #FDF8F3. ONE large landscape paper postcard #FFFDF7, very slightly counterclockwise tilted, occupies roughly the central 75% width and 72% height. All essential details inside central 80% canvas. One coherent physical postcard silhouette with subtle scalloped postage edge and very soft warm shadow. The postcard's face is one beautifully composed illustrated abstract neighbourhood map: generous cream streets between simple kraft city blocks, a small forest green park, one gentle sky blue river. In the center of this map, ONE large coral #F26B4A map pin with a cream circular hole marks a destination; pin is printed flat graphic, strong silhouette, not raised 3D. Sparse and legible map, no tiny clutter. A narrow restrained coral and sky airmail stripe along the postcard bottom edge. At upper right of the same postcard face a small coral scalloped postage stamp containing a simple cream paper-airplane symbol. A very faint empty circular postal cancellation with three short parallel lines can connect to this stamp, without letters/numbers. The postage stamp is subordinate to the central location pin. Nice asymmetry and authentic paper craft precision. The visual story must read in one second at 360 by 240: a place sent on a postcard.

Palette strictly restricted to cream #FDF8F3, ivory #FFFDF7, forest #0E4A33, coral #F26B4A, sky #B5E3F5, kraft #F0CFA1, warm subtle lines #A68F78. Coral is the single bright accent. Avoid mint confirmation fills. No text at all, no letters or numbers, no brand wordmark, no logos, no mascot, no real place or street labels, no flags, no stars or checkmarks, no ratings, no QR code, no buttons, no smartphone frame, no UI chrome, no arrows suggesting navigation, no extra cards, no envelope, no detached props, no hands, no sticker collage, no gradients or glows. Fill full canvas with an opaque cream background. The result must be one clean production header artwork, not a contact sheet.
