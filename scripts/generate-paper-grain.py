#!/usr/bin/env python3
"""Generate placeholder PaperGrain tiles until DESIGN ships the official asset.

Spec §2: 256pt tile, faint fiber noise (ink 3%) plus a 16pt-spaced 1pt
dot grid (ink 7%). Dark keeps noise at 2% and drops the dots.
Each PNG is capped at 60 KB.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

CANVAS_LIGHT = (0xFF, 0xF9, 0xEB)
INK_LIGHT = (0x2F, 0x2E, 0x23)
CANVAS_DARK = (0x1E, 0x1C, 0x19)
INK_DARK = (0xF4, 0xF1, 0xE4)
TILE_PT = 256
DOT_SPACING_PT = 16


def mix(base: tuple[int, int, int], ink: tuple[int, int, int], opacity: float) -> tuple[int, int, int]:
    return tuple(int(round(b * (1 - opacity) + i * opacity)) for b, i in zip(base, ink))


def hash32(x: int, y: int, salt: int) -> int:
    n = (x * 374761393 + y * 668265263 + salt * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return n ^ (n >> 16)


def palette_and_pixels(scale: int, *, dark: bool) -> tuple[list[tuple[int, int, int]], list[int]]:
    size = TILE_PT * scale
    canvas = CANVAS_DARK if dark else CANVAS_LIGHT
    ink = INK_DARK if dark else INK_LIGHT
    peak = 0.02 if dark else 0.03
    colors = [
        canvas,
        mix(canvas, ink, peak * 0.45),
        mix(canvas, ink, peak * 0.70),
        mix(canvas, ink, peak),
    ]
    if not dark:
        colors.append(mix(canvas, ink, 0.07))
    pixels = [0] * (size * size)
    # Sparse fibers: about 8% of pixels, so the tile stays under 60 KB.
    threshold = 20 if dark else 22
    for y in range(size):
        row = y * size
        for x in range(size):
            n = hash32(x, y, 19 if dark else 5)
            if (n & 0xFF) < threshold:
                pixels[row + x] = 1 + ((n >> 8) % 3)
    if not dark:
        spacing = DOT_SPACING_PT * scale
        radius = max(1, scale // 2)
        for gy in range(spacing // 2, size, spacing):
            for gx in range(spacing // 2, size, spacing):
                for dy in range(-radius, radius + 1):
                    for dx in range(-radius, radius + 1):
                        if dx * dx + dy * dy > radius * radius:
                            continue
                        px, py = gx + dx, gy + dy
                        if 0 <= px < size and 0 <= py < size:
                            pixels[py * size + px] = 4
    return colors, pixels


def save_png(scale: int, path: Path, *, dark: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    colors, pixels = palette_and_pixels(scale, dark=dark)
    size = TILE_PT * scale
    image = Image.new("P", (size, size))
    flat = []
    for color in colors:
        flat.extend(color)
    image.putpalette(flat + [0] * (768 - len(flat)))
    image.putdata(pixels)
    image.save(path, format="PNG", optimize=True, compress_level=9)
    nbytes = path.stat().st_size
    if nbytes > 60 * 1024:
        raise SystemExit(f"{path} is {nbytes} bytes; spec cap is 60 KB")
    print(f"wrote {path} ({nbytes} bytes, {size}x{size}, {len(colors)} colors)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True, type=Path)
    args = parser.parse_args()
    light = args.assets / "PaperGrain.imageset"
    dark = args.assets / "PaperGrainDark.imageset"
    for scale, name in ((1, "paper-grain.png"), (2, "paper-grain@2x.png"), (3, "paper-grain@3x.png")):
        save_png(scale, light / name, dark=False)
    for scale, name in ((1, "paper-grain-dark.png"), (2, "paper-grain-dark@2x.png"), (3, "paper-grain-dark@3x.png")):
        save_png(scale, dark / name, dark=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
