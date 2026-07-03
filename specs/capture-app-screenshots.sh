#!/bin/bash
# Repeatable real-UI App Store screenshot rail.
#
# Runs the SAVEScreenshotRailTests UI test (review-demo session: seeded
# places, no real network) on the pinned simulator, then extracts the
# XCTAttachment screenshots as PNGs into specs/app-store-screenshots/real-ui/.
#
# Usage: specs/capture-app-screenshots.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SAVE_SHOTS_SIM_ID:-53A8DA29-D4F6-43AF-A81E-47929D1DF97D}"
RESULT_BUNDLE="${SAVE_SHOTS_RESULT_BUNDLE:-/tmp/save-shots.xcresult}"
OUT_DIR="$REPO_ROOT/specs/app-store-screenshots/real-ui"

rm -rf "$RESULT_BUNDLE"
mkdir -p "$OUT_DIR"

echo "==> Booting simulator $SIM_ID (ok if already booted)"
xcrun simctl boot "$SIM_ID" 2>/dev/null || true

# Fresh install every run: the review-demo seeding is skipped when the local
# vault already has places, so stale app state would yield non-demo screenshots.
echo "==> Uninstalling com.wanderly.app for a clean demo-seeded run"
xcrun simctl uninstall "$SIM_ID" com.wanderly.app 2>/dev/null || true

echo "==> Running screenshot rail UI test"
xcodebuild test \
  -project "$REPO_ROOT/SAV-E.xcodeproj" \
  -scheme SAV-E \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:SAVEUITests/SAVEScreenshotRailTests \
  -resultBundlePath "$RESULT_BUNDLE" || {
    echo "warning: xcodebuild test exited non-zero (an XCTSkip mid-rail still leaves partial screenshots)" >&2
  }

echo "==> Extracting attachment PNGs to $OUT_DIR"
EXPORT_DIR="$(mktemp -d /tmp/save-shots-export.XXXXXX)"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$EXPORT_DIR"

# The manifest maps exported file names to the human attachment names the
# test set (screenshot-01-..., etc). Copy each screenshot under that name.
python3 - "$EXPORT_DIR" "$OUT_DIR" <<'PY'
import json, pathlib, shutil, sys

export_dir = pathlib.Path(sys.argv[1])
out_dir = pathlib.Path(sys.argv[2])
manifest_path = export_dir / "manifest.json"
copied = []

if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text())
    for test in manifest:
        for att in test.get("attachments", []):
            exported = export_dir / att["exportedFileName"]
            human = att.get("suggestedHumanReadableName") or att["exportedFileName"]
            if not exported.exists():
                continue
            suffix = exported.suffix or ".png"
            name = human if human.endswith(suffix) else human + suffix
            if not name.lower().endswith(".png"):
                continue
            dest = out_dir / name
            shutil.copyfile(exported, dest)
            copied.append(dest)
else:
    for png in export_dir.glob("*.png"):
        dest = out_dir / png.name
        shutil.copyfile(png, dest)
        copied.append(dest)

if not copied:
    sys.exit("error: no screenshot attachments found in the result bundle")

print(f"Extracted {len(copied)} screenshot(s):")
for path in sorted(copied):
    print(f"  {path} ({path.stat().st_size} bytes)")
PY

rm -rf "$EXPORT_DIR"
echo "==> Done. PNGs in $OUT_DIR"
