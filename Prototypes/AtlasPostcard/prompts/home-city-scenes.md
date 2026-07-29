# Home City Scene Asset Prompt

## Taipei v0

- Tool: built-in image generation
- Reference: local founder-approved `HomeAtlasScene` Tokyo asset
- Use: production SAV-E Home hero
- Output: original Taipei city-atlas background at 1x, 2x, and 3x

Prompt:

> Create an original illustrated Taipei city atlas in SAV-E's warm
> Postcard Pocket visual family. Use a soft gouache/watercolor texture, cream
> paper, pale mint streets, powder-blue waterways, coral and forest-green
> accents, and rounded landmark forms. Include Taipei 101, Chiang Kai-shek
> Memorial Hall, a Longshan Temple roof or gate, Elephant Mountain greenery,
> the Tamsui River, pink flowering trees, and low-rise city blocks. Keep the
> center and lower center open for live city text and the existing Memo asset.
> Do not include text, labels, pins, badges, mascot, logo, UI, watermark, or
> photorealism.

The generated source was center-cropped to the Home hero aspect ratio and
deterministically resampled for the asset catalog. City text and Memo remain
live SwiftUI layers.

## New York v0

- Asset: `HomeAtlasSceneNewYork`
- Landmarks: Statue of Liberty, Empire State Building, Chrysler Building,
  Brooklyn Bridge, Central Park
- Detection: New York city names or the bounded New York City coordinate box

## Shanghai v0

- Asset: `HomeAtlasSceneShanghai`
- Landmarks: Oriental Pearl Tower, Shanghai Tower, Jin Mao Tower, the Bund,
  shikumen roofs, Huangpu River
- Detection: Shanghai／上海／上海市 or the bounded Shanghai coordinate box

## Seoul v0

- Asset: `HomeAtlasSceneSeoul`
- Landmarks: N Seoul Tower, Gyeongbokgung, hanok roofs, Lotte World Tower, Han
  River bridges
- Detection: Seoul／서울／首爾／首尔 or the bounded Seoul coordinate box

All three assets were generated with the built-in image-generation path using
the approved Taipei scene as a style/composition reference. Each source was
center-cropped and deterministically resampled to 402 x 275, 804 x 550, and
1206 x 825. Text, Memo, pins, badges, logo, UI, and watermarks remain forbidden
inside the bitmap.
