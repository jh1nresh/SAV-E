#!/usr/bin/env python3
"""Side-by-side Doodle Map mock vs live capture.

Full-frame Map comparison is an explicit no-mask mode. Optional `--mask` /
`--mask-image` remain for other callers and still shade those pixels.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

def parse_rect(value: str) -> tuple[int, int, int, int]:
    parts = [int(float(part)) for part in value.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("mask must be x,y,w,h")
    return parts[0], parts[1], parts[2], parts[3]


def load(path: Path):
    from PIL import Image
    return Image.open(path).convert("RGB")


def fit(image, size: tuple[int, int]):
    from PIL import Image
    if image.size == size:
        return image
    return image.resize(size, Image.Resampling.LANCZOS)


def panel_captions(*, no_mask: bool) -> tuple[str, str]:
    if no_mask:
        return "Doodle mock", "Live Map"
    return "Doodle mock (map masked)", "Live Map (map masked)"


def build_similarity_report(
    *,
    status: str,
    threshold: str,
    payload: dict,
    mask: tuple[int, int, int, int] | None,
    mask_image: Path | None,
    no_mask: bool,
    side_by_side: str,
) -> dict:
    used_mask_image = bool(mask_image and mask_image.exists())
    report: dict = {
        "status": status,
        "threshold": float(threshold),
        "composite": payload.get("composite"),
        "edgeF1": payload.get("edgeF1"),
        "appearanceSimilarity": payload.get("appearanceSimilarity"),
        "sideBySide": side_by_side,
        "passed": payload.get("passed"),
    }
    if no_mask:
        report["mask"] = {"coverage": "full-frame"}
        return report
    if used_mask_image:
        report["mask"] = {"image": str(mask_image), "coverage": "mask-image"}
        report["maskReason"] = (
            f"Mask image {mask_image.name} excludes the live MapKit pixels."
        )
        return report
    x, y, w, h = mask if mask is not None else (0, 0, 0, 0)
    report["mask"] = {"x": x, "y": y, "width": w, "height": h}
    report["maskReason"] = (
        "Founder lock: default Apple MapKit surface is excluded. "
        f"Fallback rectangle {x},{y},{w},{h}."
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--diff", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--mask", type=parse_rect)
    parser.add_argument("--mask-image", type=Path)
    parser.add_argument("--no-mask", action="store_true")
    parser.add_argument("--status", required=True)
    parser.add_argument("--threshold", required=True)
    parser.add_argument("--light", type=Path)
    parser.add_argument("--dark", type=Path)
    parser.add_argument("--modes-output", type=Path)
    args = parser.parse_args()
    if not args.no_mask and args.mask is None and not args.mask_image:
        parser.error("one of --no-mask, --mask, or --mask-image is required")

    from PIL import Image, ImageDraw, ImageFont

    payload = json.loads(args.result.read_text())
    target = fit(load(args.target), (402, 874))
    actual = fit(load(args.actual), (402, 874))
    diff = fit(load(args.diff), (402, 874))
    used_mask_image = bool(args.mask_image and args.mask_image.exists())
    if args.no_mask:
        target_panel = target
        actual_panel = actual
    else:
        overlay = Image.new("RGBA", actual.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        x, y, w, h = args.mask if args.mask is not None else (0, 0, 0, 0)
        if used_mask_image:
            mask = fit(load(args.mask_image), (402, 874)).convert("L")
            shade = Image.new("RGBA", actual.size, (20, 20, 24, 90))
            overlay.paste(shade, (0, 0), mask.point(lambda v: 255 if v >= 240 else 0))
        else:
            draw.rectangle((x, y, x + w, y + h), fill=(20, 20, 24, 90))
        actual_panel = Image.alpha_composite(actual.convert("RGBA"), overlay).convert("RGB")
        target_panel = Image.alpha_composite(target.convert("RGBA"), overlay).convert("RGB")

    gap = 16
    header = 48
    canvas = Image.new("RGB", (402 * 3 + gap * 4, 874 + header + gap * 2), (31, 28, 25))
    canvas.paste(target_panel, (gap, header + gap))
    canvas.paste(actual_panel, (gap * 2 + 402, header + gap))
    canvas.paste(diff, (gap * 3 + 402 * 2, header + gap))
    caption = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    score = payload.get("composite")
    mock_caption, live_caption = panel_captions(no_mask=args.no_mask)
    caption.text((gap, 16), mock_caption, fill=(244, 241, 228), font=font)
    caption.text((gap * 2 + 402, 16), live_caption, fill=(244, 241, 228), font=font)
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
    report = build_similarity_report(
        status=args.status,
        threshold=args.threshold,
        payload=payload,
        mask=args.mask,
        mask_image=args.mask_image,
        no_mask=args.no_mask,
        side_by_side=str(args.output),
    )
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
