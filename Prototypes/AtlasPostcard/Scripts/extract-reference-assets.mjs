#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const prototypeDirectory = path.resolve(scriptDirectory, "..");
const targetsDirectory = path.join(prototypeDirectory, "Reference", "Targets");
const assetsDirectory = path.join(prototypeDirectory, "Resources", "Assets.xcassets");
const manifestPath = path.join(prototypeDirectory, "Reference", "asset-manifest.json");

const specs = [
  {
    name: "HomeAtlasScene",
    role: "illustrated Tokyo atlas and contextual Memo peek behind review card",
    target: "home.png",
    crop: { x: 0, y: 99, width: 402, height: 275 },
    filename: "home-atlas-scene.png",
    transform: "none",
  },
  {
    name: "SavesMemoSorting",
    role: "Memo sorting saved link cards",
    target: "saves.png",
    crop: { x: 286, y: 100, width: 112, height: 112 },
    filename: "saves-memo-sorting.png",
    transform: "borderBackgroundCutout",
  },
  {
    name: "SavesEnvelope",
    role: "kraft paper pocket texture, postmark, and empty seal decoration; live title and count are supplied by SwiftUI",
    target: "saves.png",
    crop: { x: 0, y: 568, width: 402, height: 207 },
    filename: "saves-envelope.png",
    transform: "envelopeDecorationWithoutLiveContent",
  },
  {
    name: "PlanRouteRibbon",
    role: "multicolor route ribbon and numbered route nodes",
    target: "plan.png",
    crop: { x: 0, y: 229, width: 64, height: 493 },
    filename: "plan-route-ribbon.png",
    transform: "borderBackgroundCutout",
  },
  {
    name: "TsukijiThumbnail",
    role: "Tsukiji Outer Market stop image",
    target: "plan.png",
    crop: { x: 74, y: 248, width: 74, height: 78 },
    filename: "tsukiji-thumbnail.png",
    transform: "borderBackgroundCutout",
  },
  {
    name: "KoffeeMameyaThumbnail",
    role: "Koffee Mameya stop image",
    target: "plan.png",
    crop: { x: 74, y: 372, width: 74, height: 82 },
    filename: "koffee-mameya-thumbnail.png",
    transform: "borderBackgroundCutout",
  },
  {
    name: "TeamLabThumbnail",
    role: "teamLab Borderless stop image",
    target: "plan.png",
    crop: { x: 74, y: 497, width: 74, height: 83 },
    filename: "teamlab-thumbnail.png",
    transform: "borderBackgroundCutout",
  },
  {
    name: "ShibuyaSkyThumbnail",
    role: "Shibuya Sky stop image",
    target: "plan.png",
    crop: { x: 74, y: 624, width: 74, height: 84 },
    filename: "shibuya-sky-thumbnail.png",
    transform: "borderBackgroundCutout",
  },
  {
    name: "MapAtlasScene",
    role: "illustrated Tokyo map, route, landmarks, pins, and contextual Memo pose",
    target: "map.png",
    crop: { x: 0, y: 91, width: 402, height: 480 },
    filename: "map-atlas-scene.png",
    transform: "none",
  },
  {
    name: "PaperTexture",
    role: "seamless cream paper canvas texture tile",
    target: "saves.png",
    crop: { x: 170, y: 262, width: 32, height: 32 },
    filename: "paper-texture.png",
    transform: "mirroredSeamlessTile",
  },
];

const pythonProgram = String.raw`
import json
import os
import sys
from collections import deque
from PIL import Image, ImageDraw, ImageFilter, ImageOps

payload = json.load(sys.stdin)
targets_dir = payload["targetsDirectory"]
assets_dir = payload["assetsDirectory"]
results = []

def border_background_cutout(image, tolerance=25):
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    border = []
    for x in range(width):
        border.append(pixels[x, 0][:3])
        border.append(pixels[x, height - 1][:3])
    for y in range(height):
        border.append(pixels[0, y][:3])
        border.append(pixels[width - 1, y][:3])
    background = tuple(
        sorted(pixel[channel] for pixel in border)[len(border) // 2]
        for channel in range(3)
    )
    tolerance_squared = tolerance * tolerance

    def is_background(x, y):
        red, green, blue = pixels[x, y][:3]
        distance = (
            (red - background[0]) ** 2
            + (green - background[1]) ** 2
            + (blue - background[2]) ** 2
        )
        return distance <= tolerance_squared

    visited = bytearray(width * height)
    queue = deque()
    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        offset = y * width + x
        if visited[offset] or not is_background(x, y):
            continue
        visited[offset] = 1
        if x > 0:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    alpha = Image.new("L", (width, height), 255)
    alpha_pixels = alpha.load()
    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                alpha_pixels[x, y] = 0
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.45))
    rgba.putalpha(alpha)
    return rgba

def envelope_top_cutout(image):
    rgba = image.convert("RGBA")
    width, height = rgba.size
    scale = 4
    mask = Image.new("L", (width * scale, height * scale), 0)
    draw = ImageDraw.Draw(mask)
    top_boundary = [
        (0, 0),
        (8, 1),
        (14, 5),
        (21, 13),
        (29, 22),
        (41, 28),
        (55, 31),
        (348, 31),
        (362, 29),
        (374, 23),
        (383, 14),
        (391, 6),
        (402, 1),
    ]
    polygon = [
        (x * scale, y * scale) for x, y in top_boundary
    ] + [
        (width * scale, height * scale),
        (0, height * scale),
    ]
    draw.polygon(polygon, fill=255)
    mask = mask.resize((width, height), Image.Resampling.LANCZOS)
    rgba.putalpha(mask)
    return rgba

def remove_envelope_live_content(image):
    rgba = envelope_top_cutout(image)
    rgb = rgba.convert("RGB")
    width, height = rgb.size

    clean_patch = rgb.crop((180, 140, 212, 172))
    texture_tile = mirrored_seamless_tile(clean_patch)
    texture = Image.new("RGB", (width, height))
    for y in range(0, height, texture_tile.height):
        for x in range(0, width, texture_tile.width):
            texture.paste(texture_tile, (x, y))

    live_content_mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(live_content_mask)
    mask_draw.rounded_rectangle((101, 61, 262, 113), radius=10, fill=255)
    mask_draw.rounded_rectangle((316, 48, 351, 91), radius=10, fill=255)
    mask_draw.rounded_rectangle((302, 86, 362, 133), radius=10, fill=255)
    live_content_mask = live_content_mask.filter(ImageFilter.GaussianBlur(1.1))

    cleaned = Image.composite(texture, rgb, live_content_mask).convert("RGBA")
    cleaned.putalpha(rgba.getchannel("A"))
    cleaned_pixels = cleaned.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = cleaned_pixels[x, y]
            if alpha == 0:
                cleaned_pixels[x, y] = (0, 0, 0, 0)
    return cleaned

def mirrored_seamless_tile(image):
    source = image.convert("RGB")
    row = Image.new("RGB", (source.width * 2, source.height))
    row.paste(source, (0, 0))
    row.paste(ImageOps.mirror(source), (source.width, 0))
    tile = Image.new("RGB", (row.width, row.height * 2))
    tile.paste(row, (0, 0))
    tile.paste(ImageOps.flip(row), (0, row.height))
    return tile

for spec in payload["specs"]:
    source_path = os.path.join(targets_dir, spec["target"])
    with Image.open(source_path) as source:
        source.load()
        if source.size != (402, 874):
            raise RuntimeError(
                f'{spec["target"]} must be 402x874, found {source.size[0]}x{source.size[1]}'
            )
        crop = spec["crop"]
        bounds = (
            crop["x"],
            crop["y"],
            crop["x"] + crop["width"],
            crop["y"] + crop["height"],
        )
        image = source.convert("RGB").crop(bounds)

    transform = spec["transform"]
    if transform == "borderBackgroundCutout":
        image = border_background_cutout(image)
    elif transform == "envelopeTopCutout":
        image = envelope_top_cutout(image)
    elif transform == "envelopeDecorationWithoutLiveContent":
        image = remove_envelope_live_content(image)
    elif transform == "mirroredSeamlessTile":
        image = mirrored_seamless_tile(image)
    elif transform != "none":
        raise RuntimeError(f"Unknown transform: {transform}")

    imageset = f'{spec["name"]}.imageset'
    output_directory = os.path.join(assets_dir, imageset)
    os.makedirs(output_directory, exist_ok=True)
    output_path = os.path.join(output_directory, spec["filename"])
    image.save(output_path, format="PNG", optimize=True)

    with Image.open(output_path) as verification:
        verification.load()
        if verification.format != "PNG":
            raise RuntimeError(f"{output_path} is not a readable PNG")
        width, height = verification.size
        mode = verification.mode

    results.append(
        {
            "name": spec["name"],
            "imageset": imageset,
            "filename": spec["filename"],
            "width": width,
            "height": height,
            "mode": mode,
        }
    )

json.dump(results, sys.stdout)
`;

for (const spec of specs) {
  await mkdir(path.join(assetsDirectory, `${spec.name}.imageset`), {
    recursive: true,
  });
}

const pillowCheck = spawnSync(
  "python3",
  ["-c", "from PIL import Image, ImageDraw, ImageFilter, ImageOps"],
  { encoding: "utf8" },
);

if (pillowCheck.error?.code === "ENOENT") {
  console.error(
    "Asset extraction requires Python 3. Install Python 3, then rerun this script.",
  );
  process.exit(1);
}

if (pillowCheck.status !== 0) {
  console.error(
    "Asset extraction requires Pillow. Install it with `python3 -m pip install --user Pillow`, then rerun this script.",
  );
  process.exit(1);
}

const extraction = spawnSync("python3", ["-c", pythonProgram], {
  input: JSON.stringify({
    targetsDirectory,
    assetsDirectory,
    specs,
  }),
  encoding: "utf8",
  maxBuffer: 1024 * 1024,
});

if (extraction.status !== 0) {
  process.stderr.write(extraction.stderr);
  process.exit(extraction.status ?? 1);
}

const outputs = JSON.parse(extraction.stdout);
const outputsByName = new Map(outputs.map((output) => [output.name, output]));

for (const spec of specs) {
  const output = outputsByName.get(spec.name);
  const contents = {
    images: [
      {
        filename: output.filename,
        idiom: "universal",
        scale: "1x",
      },
    ],
    info: {
      author: "xcode",
      version: 1,
    },
  };
  await writeFile(
    path.join(assetsDirectory, output.imageset, "Contents.json"),
    `${JSON.stringify(contents, null, 2)}\n`,
  );
}

const previousManifest = JSON.parse(await readFile(manifestPath, "utf8"));
const memoMascot = previousManifest.assets.find(
  (asset) => asset.name === "MemoMascot",
) ?? {
  name: "MemoMascot",
  role: "existing Savvy brand mark",
  source: "production Savvy asset copied unchanged",
};

const manifest = {
  policy: previousManifest.policy,
  extraction: {
    script: "Scripts/extract-reference-assets.mjs",
    targetViewportPixels: { width: 402, height: 874 },
    prerequisites: ["Node.js 22+", "Python 3", "Pillow"],
    note: "Only local illustration fragments are extracted; no whole-screen screenshot is used as a background.",
  },
  assets: [
    {
      ...memoMascot,
      output: {
        imageset: "MemoMascot.imageset",
        filename: "memo-mascot.png",
        width: 512,
        height: 512,
        scale: "1x",
      },
      status: "complete",
    },
    ...specs.map((spec) => {
      const output = outputsByName.get(spec.name);
      return {
        name: spec.name,
        role: spec.role,
        source: `Reference/Targets/${spec.target}`,
        sourceCrop: spec.crop,
        transform: spec.transform,
        output: {
          imageset: output.imageset,
          filename: output.filename,
          width: output.width,
          height: output.height,
          scale: "1x",
          colorMode: output.mode,
        },
        status: "complete",
      };
    }),
  ],
};

await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

for (const output of outputs) {
  console.log(
    `${output.name}: ${output.width}x${output.height} ${output.mode} -> ${output.imageset}/${output.filename}`,
  );
}
