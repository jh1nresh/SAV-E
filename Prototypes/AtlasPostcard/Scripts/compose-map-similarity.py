#!/usr/bin/env python3
"""Side-by-side Doodle Map mock vs live capture, with the live map masked."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def parse_rect(value: str) -> tuple[int, int, int, int]:
    parts = [int(float(part)) for part in value.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("mask must be x,y,w,h")
    return parts[0], parts[1], parts[2], parts[3]


def load(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB")


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    if image.size == size:
        return image
    return image.resize(size, Image.Resampling.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--diff", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--mask", required=True, type=parse_rect)
    parser.add_argument("--status", required=True)
    parser.add_argument("--threshold", required=True)
    args = parser.parse_args()

    payload = json.loads(args.result.read_text())
    target = fit(load(args.target), (402, 874))
    actual = fit(load(args.actual), (402, 874))
    diff = fit(load(args.diff), (402, 874))
    x, y, w, h = args.mask
    overlay = Image.new("RGBA", actual.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle((x, y, x + w, y + h), fill=(20, 20, 24, 90))
    actual_masked = Image.alpha_composite(actual.convert("RGBA"), overlay).convert("RGB")
    target_masked = Image.alpha_composite(target.convert("RGBA"), overlay).convert("RGB")

    gap = 16
    header = 48
    canvas = Image.new("RGB", (402 * 3 + gap * 4, 874 + header + gap * 2), (31, 28, 25))
    canvas.paste(target_masked, (gap, header + gap))
    canvas.paste(actual_masked, (gap * 2 + 402, header + gap))
    canvas.paste(diff, (gap * 3 + 402 * 2, header + gap))
    caption = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    score = payload.get("composite")
    caption.text((gap, 16), "Doodle mock (map masked)", fill=(244, 241, 228), font=font)
    caption.text((gap * 2 + 402, 16), "Live Map (map masked)", fill=(244, 241, 228), font=font)
    caption.text(
        (gap * 3 + 402 * 2, 16),
        f"Diff  score={score}  {args.status}  gate={args.threshold}",
        fill=(244, 241, 228),
        font=font,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, "PNG")
    report = {
        "status": args.status,
        "threshold": float(args.threshold),
        "composite": payload.get("composite"),
        "edgeF1": payload.get("edgeF1"),
        "appearanceSimilarity": payload.get("appearanceSimilarity"),
        "mask": {"x": x, "y": y, "width": w, "height": h},
        "maskReason": (
            "Founder lock: default Apple MapKit surface is excluded. "
            "The 0.90 gate scores Doodle chrome (header chips, paper sheet, tab bar) "
            "and layout against the Doodle v1 Map mock."
        ),
        "sideBySide": str(args.output),
        "passed": payload.get("passed"),
    }
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
