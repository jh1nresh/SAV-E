#!/usr/bin/env python3
"""402x874 Doodle Map parity target. Live MapKit canvas is later masked."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 402, 874
CANVAS = (255, 249, 235)
PAPER = (255, 249, 235)
FOREST = (14, 74, 51)
INK = (47, 46, 35)
MUTED = (98, 89, 79)
CORAL = (242, 107, 74)
LINE = (220, 207, 185)
KRAFT = (234, 221, 198)
MAP_FILL = (210, 214, 208)


def main() -> None:
    image = Image.new("RGB", (WIDTH, HEIGHT), CANVAS)
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()

    # Full-bleed map area (masked at 0,168,402,392 during the 0.90 compare).
    draw.rectangle((0, 48, WIDTH, 791), fill=MAP_FILL)

    # Header: city + Eat/Go.
    draw.rounded_rectangle((24, 62, 170, 104), radius=8, fill=CANVAS)
    draw.text((28, 70), "Taipei", fill=FOREST, font=font)
    draw.rectangle((28, 100, 86, 102), fill=CORAL)
    draw.rounded_rectangle((214, 70, 286, 102), radius=16, fill=CORAL)
    draw.text((236, 78), "Eat", fill=(255, 255, 255), font=font)
    draw.rounded_rectangle((294, 70, 378, 102), radius=16, outline=INK, width=1)
    draw.text((318, 78), "Go", fill=INK, font=font)

    # Paper place sheet.
    sheet_top = 560
    draw.rounded_rectangle((24, sheet_top, 378, 775), radius=12, fill=PAPER, outline=LINE, width=1)
    draw.rounded_rectangle((183, sheet_top + 8, 219, sheet_top + 13), radius=3, fill=LINE)
    draw.rounded_rectangle((48, sheet_top + 28, 112, sheet_top + 92), radius=8, outline=INK, width=1)
    draw.text((128, sheet_top + 36), "Saved place", fill=INK, font=font)
    draw.text((128, sheet_top + 58), "Eat · nearby", fill=MUTED, font=font)
    draw.rounded_rectangle((48, sheet_top + 116, 201, sheet_top + 164), radius=12, fill=CORAL)
    draw.text((86, sheet_top + 134), "Directions", fill=(255, 255, 255), font=font)
    draw.rounded_rectangle((213, sheet_top + 116, 354, sheet_top + 164), radius=12, outline=INK, width=1)
    draw.text((232, sheet_top + 134), "I've been here", fill=INK, font=font)

    # Tab bar.
    draw.rectangle((0, 791, WIDTH, HEIGHT), fill=PAPER)
    draw.line((0, 791, WIDTH, 791), fill=LINE, width=1)
    draw.ellipse((175, 800, 227, 852), fill=CORAL)

    out = Path("Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png")
    image.save(out, "PNG")
    print(f"wrote {out} {image.size}")


if __name__ == "__main__":
    main()
