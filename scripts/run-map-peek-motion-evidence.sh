#!/usr/bin/env bash
# Record the production Map card in both real OS motion modes on a caller-owned simulator.
set -euo pipefail

sim_udid="${1:?simulator udid}"
xctestrun="${2:?xctestrun path}"
output_dir="${3:?output directory}"
result_bundle="${4:?result bundle path}"
log_path="${5:?test log path}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$xctestrun" ]]
mkdir -p "$output_dir"
video="$output_dir/production-map-peek.mp4"
[[ ! -e "$video" ]] || { echo 'Refusing to overwrite motion evidence.' >&2; exit 1; }
args_file="$(mktemp)"
printf '%s\n' '-only-testing:SAVEUITests/SAVEScreenshotRailTests/testMapPeekMotionEvidence' > "$args_file"
record_pid=""
record_status=0

recorder_running() {
    [[ -n "$record_pid" ]] && kill -0 "$record_pid" 2>/dev/null || return 1
    # A subshell can retain stale job state. Check the live child as well,
    # and never signal a recycled PID belonging to another process owner.
    local recorder_parent
    recorder_parent="$(ps -p "$record_pid" -o ppid= 2>/dev/null)" || return 1
    [[ "${recorder_parent//[[:space:]]/}" == "$$" ]] || return 1
    jobs -pr | grep -Fxq -- "$record_pid"
}

stop_recording() {
    if [[ -n "$record_pid" ]]; then
        if recorder_running; then
            kill -INT "$record_pid" 2>/dev/null || true
            for _ in {1..50}; do
                recorder_running || break
                sleep 0.1
            done
            if recorder_running; then
                record_status=1
                kill -TERM "$record_pid" 2>/dev/null || true
                for _ in {1..20}; do
                    recorder_running || break
                    sleep 0.1
                done
                if recorder_running; then kill -KILL "$record_pid" 2>/dev/null || true; fi
            fi
        fi
        if wait "$record_pid"; then :; else
            recorder_exit=$?
            [[ "$recorder_exit" == 130 ]] || record_status=1
        fi
        record_pid=""
    fi
    return 0
}

trap 'stop_recording; rm -f "$args_file"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
xcrun simctl io "$sim_udid" recordVideo --codec=h264 "$video" > "$output_dir/recording.log" 2>&1 &
record_pid=$!
recorder_running || { echo 'Screen recorder did not start.' >&2; exit 1; }

set +e
"$script_dir/run-ios-xcodebuild-retry.sh" \
    --max-attempts 3 --result-bundle "$result_bundle" --log "$log_path" \
    --only-testing-file "$args_file" -- \
    -xctestrun "$xctestrun" -destination "platform=iOS Simulator,id=$sim_udid" \
    COMPILER_INDEX_STORE_ENABLE=NO test-without-building
test_status=$?
set -e
# The recorder must span the complete test, rather than leave an early partial movie.
recorder_running || record_status=1
stop_recording

evidence_status=0
attachments="$output_dir/attachments"
if [[ -f "$result_bundle/Info.plist" ]]; then
    xcrun xcresulttool export attachments --path "$result_bundle" --output-path "$attachments" || evidence_status=1
    python3 "$script_dir/extract-named-ui-screenshots.py" "$attachments" "$output_dir" \
        --expect peek-motion-normal-reopened --expect peek-motion-normal-switched \
        --expect peek-motion-reduced-reopened --expect peek-motion-reduced-switched || evidence_status=1
    python3 - "$attachments" "$output_dir" <<'PY' || evidence_status=1
import json
import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
expected = {"peek-motion-mode-normal": ("normal", "false"),
            "peek-motion-mode-reduced": ("reduced", "true")}
found = set()
for test in json.loads((source / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "").split("_0_", 1)[0]
        if name not in expected:
            continue
        filename = attachment["exportedFileName"]
        if Path(filename).name != filename:
            raise ValueError("Unexpected receipt path")
        content = (source / filename).read_text()
        mode, enabled = expected[name]
        if f"mode={mode}" not in content or f"UIAccessibility.isReduceMotionEnabled={enabled}" not in content:
            raise ValueError(f"Wrong OS motion receipt: {name}")
        (output / f"{name}.txt").write_text(content)
        found.add(name)
if found != set(expected):
    raise ValueError("Both real OS motion receipts are required")
PY
else
    echo 'Motion test result bundle is missing.' >&2
    evidence_status=1
fi
[[ -s "$video" ]] || evidence_status=1
for state in normal-reopened normal-switched reduced-reopened reduced-switched; do
    [[ -s "$output_dir/peek-motion-${state}.png" ]] || evidence_status=1
done
[[ "$test_status" == 0 ]] || exit "$test_status"
[[ "$record_status" == 0 && "$evidence_status" == 0 ]]
