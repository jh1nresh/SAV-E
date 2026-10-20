#!/usr/bin/env python3
"""Crop the real Doodle Map mock to the 402x874 parity viewport.

The source is a landscape device-in-frame PNG. Inner-screen crop (black
bezel excluded) is resized to the VisualParity viewport. Live MapKit is
later masked at 0,168,402,392; this script does not change that rect.

Usage:
  python3 Prototypes/AtlasPostcard/Scripts/generate-doodle-map-target.py \\
    --source /path/to/2026-10-19-doodle-v1-map.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image
import numpy as np

WIDTH, HEIGHT = 402, 874
# Inclusive inner-screen box on the 1280x720 device-in-frame mock.
CROP = (354, 21, 923, 697)
OUT = Path("Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png")


def inpaint_bottom_bezel(image: Image.Image) -> Image.Image:
    """Replace scored bottom-corner bezel pixels with tab-bar cream."""
    pixels = np.array(image.convert("RGB"))
    height, width, _ = pixels.shape
    lum = pixels.mean(axis=2)
    yy, xx = np.ogrid[:height, :width]
    radius = 42
    dark = lum < 200
    bottom = yy >= height - 48
    bottom_left = ((xx - 0) ** 2 + (yy - (height - 1)) ** 2 <= radius * radius) & dark & bottom
    bottom_right = ((xx - (width - 1)) ** 2 + (yy - (height - 1)) ** 2 <= radius * radius) & dark & bottom
    band = pixels[height - 40 : height - 8, 40 : width - 40]
    band_lum = lum[height - 40 : height - 8, 40 : width - 40]
    cream = band[band_lum > 200]
    fill = (
        np.median(cream, axis=0).astype(np.uint8)
        if len(cream)
        else np.array([255, 249, 237], dtype=np.uint8)
    )
    pixels[bottom_left | bottom_right] = fill
    return Image.fromarray(pixels)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    source = Image.open(args.source).convert("RGB")
    target = source.crop(CROP).resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    target = inpaint_bottom_bezel(target)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    target.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT} {target.size}")


if __name__ == "__main__":
    main()
