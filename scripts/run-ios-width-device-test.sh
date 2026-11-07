#!/usr/bin/env bash
# Boot one real 375 / 390 / 430 simulator for one or all three width tests.
# Letterboxing a 402pt device does not count as width evidence.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/run-ios-width-device-test.sh \
    --width 375|390|430 \
    --test SAVEUITests/SAVEScreenshotRailTests/testPassportWidth375 \
    --xctestrun PATH \
    --output-dir DIR \
    --result-bundle PATH \
    --log PATH

Repeat --test for Map, Friends and Passport to run the complete width group
in one XCTest session. A single --test remains supported.
EOF
}

width=""
test_selectors=()
xctestrun=""
output_dir=""
result_bundle=""
log_path=""
runtime="com.apple.CoreSimulator.SimRuntime.iOS-26-5"

while (($#)); do
    case "$1" in
        --width)
            width="${2:?missing value for --width}"
            shift 2
            ;;
        --test)
            test_selectors+=("${2:?missing value for --test}")
            shift 2
            ;;
        --xctestrun)
            xctestrun="${2:?missing value for --xctestrun}"
            shift 2
            ;;
        --output-dir)
            output_dir="${2:?missing value for --output-dir}"
            shift 2
            ;;
        --result-bundle)
            result_bundle="${2:?missing value for --result-bundle}"
            shift 2
            ;;
        --log)
            log_path="${2:?missing value for --log}"
            shift 2
            ;;
        --runtime)
            runtime="${2:?missing value for --runtime}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$width" || ${#test_selectors[@]} -eq 0 || -z "$xctestrun" || -z "$output_dir" || -z "$result_bundle" || -z "$log_path" ]]; then
    usage >&2
    exit 2
fi

surfaces=()
for test_selector in "${test_selectors[@]}"; do
    case "$test_selector" in
        */testMapWidth"$width") surface=map ;;
        */testFriendsWidth"$width") surface=friends ;;
        */testPassportWidth"$width") surface=passport ;;
        *)
            echo "unsupported width screenshot test: $test_selector" >&2
            exit 2
            ;;
    esac
    case " ${surfaces[*]-} " in
        *" $surface "*) echo "duplicate width screenshot test: $test_selector" >&2; exit 2 ;;
    esac
    surfaces+=("$surface")
done
if ((${#surfaces[@]} != 1 && ${#surfaces[@]} != 3)); then
    echo "select one surface or the complete Map/Friends/Passport width group" >&2
    exit 2
fi

case "$width" in
    375)
        prefs='com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation,com.apple.CoreSimulator.SimDeviceType.iPhone-SE-2nd-generation'
        ;;
    390)
        # iPhone 16 is 393pt; iPhone 16 Pro is 402pt. Do not pick those.
        prefs='com.apple.CoreSimulator.SimDeviceType.iPhone-14,com.apple.CoreSimulator.SimDeviceType.iPhone-13,com.apple.CoreSimulator.SimDeviceType.iPhone-12'
        ;;
    430)
        # iPhone 16 Pro Max is 440pt. Do not pick it for 430 evidence.
        prefs='com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max,com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus,com.apple.CoreSimulator.SimDeviceType.iPhone-15-Plus,com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max'
        ;;
    *)
        echo "width must be 375, 390, or 430 (got $width)" >&2
        exit 2
        ;;
esac

device_type="$(
    xcrun simctl list -j devicetypes | python3 -c "
import json, sys
prefs = sys.argv[1].split(',')
types = json.load(sys.stdin)['devicetypes']
idents = {item.get('identifier') for item in types}
print(next((pref for pref in prefs if pref in idents), ''))
" "$prefs"
)"
if [[ -z "$device_type" ]]; then
    echo "no simulator device type for ${width}pt among: $prefs" >&2
    exit 1
fi

mkdir -p "$output_dir"
args_file="$(mktemp)"
trap 'rm -f "$args_file"' EXIT
for test_selector in "${test_selectors[@]}"; do
    printf '%s\n' "-only-testing:${test_selector}"
done > "$args_file"

# Host env does not reach the xctestrun UI runner. Inject a simulator-writable
# fallback; copy those files out from the device data root after the test.
python3 - "$xctestrun" /tmp/SAVE-First-Run <<'PY'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
screenshot_dir = sys.argv[2]
data = plistlib.loads(path.read_bytes())

def inject(obj):
    if isinstance(obj, dict):
        for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
            existing = obj.get(key)
            if isinstance(existing, dict):
                existing["SAVE_SCREENSHOT_DIR"] = screenshot_dir
            elif key in obj:
                obj[key] = {"SAVE_SCREENSHOT_DIR": screenshot_dir}
        if any(k in obj for k in (
            "BlueprintName",
            "TestHostBundleIdentifier",
            "ProductModuleName",
        )):
            env = obj.setdefault("EnvironmentVariables", {})
            if isinstance(env, dict):
                env["SAVE_SCREENSHOT_DIR"] = screenshot_dir
            testing = obj.setdefault("TestingEnvironmentVariables", {})
            if isinstance(testing, dict):
                testing["SAVE_SCREENSHOT_DIR"] = screenshot_dir
        for value in obj.values():
            inject(value)
    elif isinstance(obj, list):
        for value in obj:
            inject(value)

inject(data)
path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
print(f"injected SAVE_SCREENSHOT_DIR into {path}")
PY

udid="$(xcrun simctl create "SAV-E CI ${width}pt" "$device_type" "$runtime")"
status=1
cleanup() {
    local cleanup_status=0
    local devices=""
    xcrun simctl shutdown "$udid" || true
    if ! devices="$(xcrun simctl list devices)"; then
        cleanup_status=1
    elif ! grep -F "$udid" <<< "$devices" | grep -Fq '(Shutdown)'; then
        echo "width simulator shutdown could not be verified" >&2
        cleanup_status=1
    else
        echo "Verified width ${width} simulator shutdown: $udid"
    fi
    if ! xcrun simctl delete "$udid"; then
        cleanup_status=1
    elif ! devices="$(xcrun simctl list devices)"; then
        cleanup_status=1
    elif grep -Fq "$udid" <<< "$devices"; then
        echo "width simulator deletion could not be verified" >&2
        cleanup_status=1
    else
        echo "Verified width ${width} simulator deletion: $udid"
    fi
    return "$cleanup_status"
}
trap 'script_status=$?; rm -f "$args_file"; if ! cleanup; then script_status=1; fi; exit "$script_status"' EXIT

xcrun simctl bootstatus "$udid" -b
set +e
scripts/run-ios-xcodebuild-retry.sh \
    --max-attempts 3 \
    --result-bundle "$result_bundle" \
    --log "$log_path" \
    --only-testing-file "$args_file" \
    -- \
    -xctestrun "$xctestrun" \
    -destination "platform=iOS Simulator,id=$udid" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    test-without-building
status=$?
set -e

sim_shots="$HOME/Library/Developer/CoreSimulator/Devices/${udid}/data/tmp/SAVE-First-Run"
if [[ -d "$sim_shots" ]]; then
    cp -R "$sim_shots/." "$output_dir/"
    echo "copied simulator SAVE_SCREENSHOT_DIR from $sim_shots"
fi
if [[ -f "$result_bundle/Info.plist" ]]; then
    # One export contains the entire group. Keep its manifest separate from
    # named rasters, including when legacy single-test calls share output_dir.
    attachment_prefix="${surfaces[0]}"
    if ((${#surfaces[@]} == 3)); then attachment_prefix=width; fi
    attachments="$(mktemp -d "$output_dir/${attachment_prefix}-${width}-attachments.XXXXXX")"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$attachments" \
        || echo "xcresulttool export failed; keep SAVE_SCREENSHOT_DIR rasters."
    if [[ -f "$attachments/manifest.json" ]]; then
        expected=()
        for surface in "${surfaces[@]}"; do expected+=(--expect "${surface}-${width}"); done
        python3 scripts/extract-named-ui-screenshots.py "$attachments" "$output_dir" \
            "${expected[@]}"
    fi
fi

for surface in "${surfaces[@]}"; do
    [[ -s "$output_dir/${surface}-${width}.png" ]] || status=1
done

exit "$status"
