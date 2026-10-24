#!/usr/bin/env python3
"""Side-by-side Doodle Map mock vs live capture, with the live map masked."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:
    raise SystemExit(
        "Pillow is required for compose-map-similarity.py. "
        "Install with: python3 -m pip install Pillow"
    ) from exc


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
    parser.add_argument("--mask-image", type=Path)
    parser.add_argument("--status", required=True)
    parser.add_argument("--threshold", required=True)
    parser.add_argument("--light", type=Path)
    parser.add_argument("--dark", type=Path)
    parser.add_argument("--modes-output", type=Path)
    args = parser.parse_args()

    payload = json.loads(args.result.read_text())
    target = fit(load(args.target), (402, 874))
    actual = fit(load(args.actual), (402, 874))
    diff = fit(load(args.diff), (402, 874))
    overlay = Image.new("RGBA", actual.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    x, y, w, h = args.mask
    used_mask_image = bool(args.mask_image and args.mask_image.exists())
    if used_mask_image:
        mask = fit(load(args.mask_image), (402, 874)).convert("L")
        shade = Image.new("RGBA", actual.size, (20, 20, 24, 90))
        overlay.paste(shade, (0, 0), mask.point(lambda v: 255 if v >= 240 else 0))
    else:
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

    if args.modes_output and args.light:
        light = fit(load(args.light), (402, 874))
        dark = fit(load(args.dark), (402, 874)) if args.dark else Image.new("RGB", (402, 874), (31, 28, 25))
        modes = Image.new("RGB", (402 * 3 + gap * 4, 874 + header + gap * 2), (31, 28, 25))
        modes.paste(target, (gap, header + gap))
        modes.paste(light, (gap * 2 + 402, header + gap))
        modes.paste(dark, (gap * 3 + 402 * 2, header + gap))
        labels = ImageDraw.Draw(modes)
        labels.text((gap, 16), "DESIGN mock", fill=(244, 241, 228), font=font)
        labels.text((gap * 2 + 402, 16), "Light sim", fill=(244, 241, 228), font=font)
        labels.text((gap * 3 + 402 * 2, 16), "Dark sim", fill=(244, 241, 228), font=font)
        args.modes_output.parent.mkdir(parents=True, exist_ok=True)
        modes.save(args.modes_output, "PNG")
    report = {
        "status": args.status,
        "threshold": float(args.threshold),
        "composite": payload.get("composite"),
        "edgeF1": payload.get("edgeF1"),
        "appearanceSimilarity": payload.get("appearanceSimilarity"),
        "mask": (
            {
                "kind": "image",
                "path": str(args.mask_image),
                "fallbackRectangle": {"x": x, "y": y, "width": w, "height": h},
            }
            if used_mask_image
            else {"kind": "rectangle", "x": x, "y": y, "width": w, "height": h}
        ),
        "maskReason": (
            f"Image mask {args.mask_image.name}: white pixels are live Apple Maps "
            "(ignored). Rectangle bounds are provenance only when no image mask is supplied."
            if used_mask_image
            else (
                f"Rectangle mask {x},{y},{w},{h} covers live MapKit in both "
                "capture and mock."
            )
        ),
        "sideBySide": str(args.output),
        "passed": payload.get("passed"),
    }
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
