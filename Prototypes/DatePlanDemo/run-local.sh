#!/bin/zsh
set -euo pipefail
DEMO_HEADLESS=0
if [[ "${1:-}" == "--headless" ]]; then
  DEMO_HEADLESS=1
elif [[ -n "${1:-}" ]]; then
  echo '用法：./run-local.sh [--headless]'
  exit 64
fi
DEMO_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
DEMO_REPO="$(cd -- "$DEMO_ROOT/../.." && pwd)"
export SAVE_DERIVED_DATA="$DEMO_REPO/Prototypes/CityMVP/.build-main"
export SAVE_DERIVED_DATA_PATH="$SAVE_DERIVED_DATA"
DEMO_LOCK="$DEMO_REPO/Prototypes/CityMVP/.build-main-lock"
DEMO_DEVICE="06BE9771-5352-4009-9F51-0BEE7708E7EB"
DEMO_DEVICE_LOCK="/private/tmp/savvy-date-plan-demo-simulator.lock"
DEMO_BOOTED=0
DEMO_HAS_DEVICE_LOCK=0
python3 -c 'import shutil,sys; sys.exit(0 if shutil.disk_usage(sys.argv[1]).free >= 10*1024**3 else "可用空間低於 10 GiB，先停止預覽。")' "$DEMO_ROOT"
if ! mkdir "$DEMO_LOCK" 2>/dev/null; then
  echo '已有編譯工作使用快取，請等它完成後再執行。'
  exit 1
fi
DEMO_OWNER="date-demo-manual-$$"
printf '%s' "$DEMO_OWNER" > "$DEMO_LOCK/manual-owner"
release_owned_demo_lock() {
  python3 - "$1" "$DEMO_OWNER" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);f=p/'manual-owner'
if f.is_file() and f.read_text()==sys.argv[2] and list(p.iterdir())==[f]:
    f.unlink();p.rmdir()
PY
}
cleanup_demo() {
  DEMO_EXIT_CODE=$?
  DEMO_STOPPED=1
  if (( DEMO_BOOTED )); then
    xcrun simctl shutdown "$DEMO_DEVICE" >/dev/null 2>&1 || true
    if ! xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); own=[v for a in d["devices"].values() for v in a if v["udid"]==sys.argv[1]]; sys.exit(0 if len(own)==1 and own[0]["state"]=="Shutdown" else 1)' "$DEMO_DEVICE"; then
      DEMO_STOPPED=0
    fi
  fi
  release_owned_demo_lock "$DEMO_LOCK"
  if (( DEMO_STOPPED && DEMO_HAS_DEVICE_LOCK )); then
    release_owned_demo_lock "$DEMO_DEVICE_LOCK"
  elif (( ! DEMO_STOPPED )); then
    echo "模擬器尚未確認關閉，已保留裝置鎖：$DEMO_DEVICE_LOCK"
    DEMO_EXIT_CODE=1
  fi
  exit "$DEMO_EXIT_CODE"
}
trap cleanup_demo EXIT
trap 'exit 130' INT TERM HUP
cd "$DEMO_ROOT"
xcodegen generate --spec project.yml
"$DEMO_REPO/scripts/xcodebuild-clean.sh" -project "$DEMO_ROOT/SavvyDateDemo.xcodeproj" \
  -scheme SavvyDateDemo -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$SAVE_DERIVED_DATA" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
python3 -c 'import shutil,sys; sys.exit(0 if shutil.disk_usage(sys.argv[1]).free >= 10*1024**3 else "編譯後可用空間低於 10 GiB，停止啟動模擬器。")' "$DEMO_ROOT"
if ! mkdir "$DEMO_DEVICE_LOCK" 2>/dev/null; then
  echo '這台模擬器已有操作擁有者，請等它結束再開預覽。'
  exit 1
fi
printf '%s' "$DEMO_OWNER" > "$DEMO_DEVICE_LOCK/manual-owner"
DEMO_HAS_DEVICE_LOCK=1
if xcrun simctl list devices booted | rg -q "$DEMO_DEVICE"; then
  echo '指定模擬器已在使用中，這次不接管；請先結束原本的操作。'
  exit 1
fi
DEMO_BOOTED=1
xcrun simctl boot "$DEMO_DEVICE"
xcrun simctl bootstatus "$DEMO_DEVICE" -b
xcrun simctl install "$DEMO_DEVICE" "$SAVE_DERIVED_DATA/Build/Products/Debug-iphonesimulator/SavvyDateDemo.app"
xcrun simctl launch --terminate-running-process "$DEMO_DEVICE" local.savvy.date-preview
if (( DEMO_HEADLESS )); then
  echo '已啟動 headless 本地 Savvy 約會預覽；未開啟視窗，未安裝到實體 iPhone。'
else
  open -a Simulator --args -CurrentDeviceUDID "$DEMO_DEVICE"
  echo '已開啟本地 Savvy 約會預覽；未安裝到實體 iPhone。'
fi
read -r '?看完後按 Enter，會關閉這台模擬器並釋放預覽鎖。'
