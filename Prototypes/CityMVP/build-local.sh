#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
CITY_MVP_ROOT="$PWD/Prototypes/CityMVP"
# mkdir is the exclusive ownership primitive; never steal an existing build lock.
mkdir "$CITY_MVP_ROOT/.build-lock"
trap 'rmdir "$CITY_MVP_ROOT/.build-lock"' EXIT
python3 "$CITY_MVP_ROOT/generate-project.py"
export SAVE_XCODEBUILD_LOG="$CITY_MVP_ROOT/build.log"
scripts/xcodebuild-clean.sh \
  -project SavvyCityMVP.xcodeproj -scheme SavvyCityMVP -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$CITY_MVP_ROOT/.build" \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  "$@" build
CITY_MVP_APP="$CITY_MVP_ROOT/.build/Build/Products/Debug-iphonesimulator/SavvyCityMVP.app"
if [[ -f "$CITY_MVP_ROOT/Amap.local.plist" ]]; then
  plutil -lint "$CITY_MVP_ROOT/Amap.local.plist" >/dev/null
  cp "$CITY_MVP_ROOT/Amap.local.plist" "$CITY_MVP_APP/Amap.local.plist"
fi
