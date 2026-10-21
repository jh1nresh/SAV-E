#!/usr/bin/env bash
# Render DESIGN gate 5 evidence on a booted iOS Simulator (macOS CI).
# Usage: capture-map-photo-pin-gate5.sh <udid> <output-dir>
set -euo pipefail

UDID="${1:?simulator udid}"
OUT="${2:?output directory}"
BUNDLE="${SAVE_BUNDLE_ID:-com.wanderly.app}"

mkdir -p "$OUT"

launch_app() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@"
}

screenshot() {
  local file="$1"
  xcrun simctl io "$UDID" screenshot "$file"
  [[ -s "$file" ]]
}

xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light

launch_app --uitest-map-photo-pin-catalog --uitest-complete-onboarding --skip-map-tour
sleep 4
screenshot "$OUT/simulator-catalog-light.png"

xcrun simctl ui "$UDID" appearance dark
launch_app --uitest-map-photo-pin-catalog --uitest-dark --uitest-complete-onboarding --skip-map-tour
sleep 4
screenshot "$OUT/simulator-catalog-dark.png"

xcrun simctl ui "$UDID" appearance light
launch_app --uitest-map-photo-pin-catalog --uitest-map-photo-pin-zh --uitest-complete-onboarding --skip-map-tour
sleep 4
screenshot "$OUT/simulator-catalog-zh-Hant.png"

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/gate5-motion-60fps.mp4" &
rec_pid=$!
sleep 1
launch_app --uitest-map-photo-pin-motion --uitest-complete-onboarding --skip-map-tour
sleep 9
screenshot "$OUT/simulator-motion-end.png"
kill -INT "$rec_pid" >/dev/null 2>&1 || true
wait "$rec_pid" || true
[[ -s "$OUT/gate5-motion-60fps.mp4" ]]

printf 'Gate 5 simulator evidence written to %s\n' "$OUT"
ls -la "$OUT"
