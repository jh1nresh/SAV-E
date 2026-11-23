#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${POCKET_CITY_NATIVE_BUILD:-/tmp/savvy-apple-native}"
port=0
mode=start
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]{1,5}$ || "$((10#$2))" -gt 65535 ]]; then
        echo "Usage: $0 [--port 0–65535] [--background | --build-only]" >&2
        exit 2
      fi
      port="$((10#$2))"
      shift 2 ;;
    --background) mode=background; shift ;;
    --build-only) mode=build; shift ;;
    *)
      echo "Usage: $0 [--port 0–65535] [--background | --build-only]" >&2
      exit 2 ;;
  esac
done
if [[ ! -f "$root/data/city170/index.json" ]]; then
  echo "Run python3 prepare_data.py in $root first." >&2
  exit 1
fi
mkdir -p "$build_dir"
available_kb="$(df -Pk "$build_dir" | awk 'END {print $4}')"
if [[ -z "$available_kb" || "$available_kb" -lt 10485760 ]]; then
  echo "The native preview build requires at least 10 GiB of free space." >&2
  exit 1
fi

app="$build_dir/Savvy Pocket City.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$build_dir/module-cache"
cp "$root/native/Info.plist" "$app/Contents/Info.plist"
printf '%s' "$root" > "$app/Contents/Resources/preview-root.txt"
xcrun --sdk macosx swiftc -swift-version 5 -target "$(uname -m)-apple-macos15.0" \
  -module-cache-path "$build_dir/module-cache" -framework AppKit -framework MapKit -framework WebKit \
  "$root/native/main.swift" -o "$app/Contents/MacOS/SavvyPocketCity"
codesign --force --sign - "$app"
echo "$app"
if [[ "$mode" == start ]]; then
  open -a "$app" --args "$root" "$port"
elif [[ "$mode" == background ]]; then
  open -g -n -a "$app" --args "$root" "$port" --background
fi
