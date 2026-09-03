#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOTYPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REFERENCE_SOURCE="$PROTOTYPE_ROOT/Reference/ProductionTargets"
PARITY_SCRIPT="$SCRIPT_DIR/VisualParity.swift"
DERIVED_DATA="${ATLAS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/SAVE-AtlasPrototype}"
ARTIFACT_DIR="${ATLAS_PARITY_ARTIFACTS:-}"
THRESHOLD="0.90"
RESULT_BUNDLE=""
SCREENSHOTS_DIR=""
DESTINATION="${ATLAS_DESTINATION:-}"
BOOTED_BEFORE=""

usage() {
    cat <<'EOF'
Usage:
  Scripts/run-visual-parity.sh --destination 'platform=iOS Simulator,id=<UDID>'
  Scripts/run-visual-parity.sh --result-bundle /path/to/Test.xcresult
  Scripts/run-visual-parity.sh --screenshots-dir /path/to/pngs

Options:
  --artifacts DIR       Write reference/output/diff/results under DIR.
  --threshold NUMBER    Gate threshold. Must be at least 0.90 (default 0.90).

The screenshots directory must contain home.png, saves.png, plan.png, and
map.png. The result-bundle mode prefers the live five-tab-home attachment for
Home and falls back to atlas-home for prototype-only runs. Saves, Plan, and Map
use the stable atlas-saves, atlas-plan, and atlas-map XCTest attachments.
EOF
}

while (($#)); do
    case "$1" in
        --destination)
            DESTINATION="${2:?missing value for --destination}"
            shift 2
            ;;
        --result-bundle)
            RESULT_BUNDLE="${2:?missing value for --result-bundle}"
            shift 2
            ;;
        --screenshots-dir)
            SCREENSHOTS_DIR="${2:?missing value for --screenshots-dir}"
            shift 2
            ;;
        --artifacts)
            ARTIFACT_DIR="${2:?missing value for --artifacts}"
            shift 2
            ;;
        --threshold)
            THRESHOLD="${2:?missing value for --threshold}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! awk -v threshold="$THRESHOLD" \
    'BEGIN { exit !(threshold >= 0.90 && threshold <= 1.0) }'
then
    echo "error: threshold must be between 0.90 and 1.0" >&2
    exit 2
fi

input_count=0
[[ -n "$DESTINATION" ]] && ((input_count += 1))
[[ -n "$RESULT_BUNDLE" ]] && ((input_count += 1))
[[ -n "$SCREENSHOTS_DIR" ]] && ((input_count += 1))
if ((input_count != 1)); then
    echo "error: choose exactly one of --destination, --result-bundle, or --screenshots-dir" >&2
    usage >&2
    exit 2
fi

if [[ -z "$ARTIFACT_DIR" ]]; then
    ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/AtlasPostcardVisualParity.XXXXXX")"
elif [[ -e "$ARTIFACT_DIR" ]]; then
    if [[ ! -d "$ARTIFACT_DIR" ]] ||
        [[ -n "$(find "$ARTIFACT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]
    then
        echo "error: artifacts path must be a new or empty directory: $ARTIFACT_DIR" >&2
        exit 2
    fi
else
    mkdir -p "$ARTIFACT_DIR"
fi

booted_devices() {
    xcrun simctl list devices booted |
        awk -F '[()]' '/\(Booted\)/ { print $2 }'
}

simulator_state() {
    local device="$1"
    xcrun simctl list devices |
        awk -F '[()]' -v id="$device" '
            $2 == id {
                print $4
                found = 1
                exit
            }
            END {
                if (!found) {
                    exit 1
                }
            }
        '
}

cleanup_new_simulators() {
    local original_status=$?
    local cleanup_status=0
    local after=""
    local device=""
    local state=""
    local attempt=0

    trap - EXIT

    if [[ -n "$BOOTED_BEFORE" && -f "$BOOTED_BEFORE" ]]; then
        if ! after="$(mktemp)"; then
            echo "error: could not create simulator cleanup snapshot" >&2
            cleanup_status=1
        elif ! booted_devices >"$after"; then
            echo "error: could not list simulators during cleanup" >&2
            cleanup_status=1
        else
            while IFS= read -r device; do
                [[ -n "$device" ]] || continue
                if grep -Fqx "$device" "$BOOTED_BEFORE"; then
                    continue
                fi

                if ! xcrun simctl shutdown "$device" >/dev/null; then
                    echo "error: failed to shut down simulator $device" >&2
                    cleanup_status=1
                fi

                state=""
                for ((attempt = 0; attempt < 20; attempt += 1)); do
                    if ! state="$(simulator_state "$device")"; then
                        state=""
                        break
                    fi
                    [[ "$state" == "Shutdown" ]] && break
                    sleep 0.25
                done

                if [[ "$state" != "Shutdown" ]]; then
                    echo "error: simulator $device did not report Shutdown" >&2
                    cleanup_status=1
                fi
            done <"$after"
        fi
    fi

    if [[ -n "$after" ]] && ! rm -f "$after"; then
        echo "error: could not remove simulator cleanup snapshot: $after" >&2
        cleanup_status=1
    fi
    if [[ -n "$BOOTED_BEFORE" ]] && ! rm -f "$BOOTED_BEFORE"; then
        echo "error: could not remove simulator baseline snapshot: $BOOTED_BEFORE" >&2
        cleanup_status=1
    fi

    if ((original_status != 0)); then
        exit "$original_status"
    fi
    if ((cleanup_status != 0)); then
        exit "$cleanup_status"
    fi
    exit 0
}

capture_booted_simulators() {
    BOOTED_BEFORE="$(mktemp)"
    if ! booted_devices >"$BOOTED_BEFORE"; then
        echo "error: could not list simulators before the test run" >&2
        rm -f "$BOOTED_BEFORE"
        BOOTED_BEFORE=""
        exit 2
    fi
}

mkdir -p \
    "$ARTIFACT_DIR/reference" \
    "$ARTIFACT_DIR/output" \
    "$ARTIFACT_DIR/diff" \
    "$ARTIFACT_DIR/results"

for screen in home saves plan map; do
    source="$REFERENCE_SOURCE/$screen.png"
    if [[ ! -f "$source" ]]; then
        echo "error: missing reference image: $source" >&2
        exit 2
    fi
    cp "$source" "$ARTIFACT_DIR/reference/$screen.png"
done

if [[ -n "$DESTINATION" ]]; then
    capture_booted_simulators
    trap cleanup_new_simulators EXIT

    RESULT_BUNDLE="$ARTIFACT_DIR/AtlasPostcardVisualParity.xcresult"
    (
        cd "$PROTOTYPE_ROOT"
        xcodegen generate
        xcodebuild test \
            -project AtlasPostcardPrototype.xcodeproj \
            -scheme AtlasPostcardPrototype \
            -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA" \
            -resultBundlePath "$RESULT_BUNDLE" \
            -only-testing:AtlasPostcardPrototypeUITests/AtlasPostcardScreenshotTests/testCaptureFourLockedScreens \
            CODE_SIGNING_ALLOWED=NO \
            COMPILER_INDEX_STORE_ENABLE=NO
    )
fi

if [[ -n "$RESULT_BUNDLE" ]]; then
    if [[ ! -d "$RESULT_BUNDLE" ]]; then
        echo "error: result bundle not found: $RESULT_BUNDLE" >&2
        exit 2
    fi

    export_dir="$(mktemp -d)"
    xcrun xcresulttool export attachments \
        --path "$RESULT_BUNDLE" \
        --output-path "$export_dir"

    manifest="$export_dir/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        echo "error: attachment export did not create manifest.json" >&2
        rm -rf "$export_dir"
        exit 2
    fi

    test_index=0
    # xcresulttool folds every attempt of a test into a single manifest entry,
    # so a retried test contributes each screenshot more than once. Collect all
    # candidates with their timestamps and keep the newest copy of each screen:
    # this gate only runs once the test step has succeeded, so the final attempt
    # is the one that passed and its screenshots are the ones worth comparing.
    candidates=""
    tab="$(printf '\t')"
    while attachment_count="$(
        plutil -extract "$test_index.attachments" raw -o - "$manifest" 2>/dev/null
    )"; do
        for ((attachment_index = 0; attachment_index < attachment_count; attachment_index += 1)); do
            prefix="$test_index.attachments.$attachment_index"
            human_name="$(
                plutil -extract "$prefix.suggestedHumanReadableName" raw -o - "$manifest"
            )"
            exported_name="$(
                plutil -extract "$prefix.exportedFileName" raw -o - "$manifest"
            )"
            timestamp="$(
                plutil -extract "$prefix.timestamp" raw -o - "$manifest" 2>/dev/null
            )" || timestamp=0
            case "$human_name" in
                five-tab-home*)
                    screen="home"
                    priority=1
                    ;;
                atlas-home*)
                    screen="home"
                    priority=0
                    ;;
                atlas-saves*)
                    screen="saves"
                    priority=0
                    ;;
                atlas-plan*)
                    screen="plan"
                    priority=0
                    ;;
                atlas-map*)
                    screen="map"
                    priority=0
                    ;;
                *)
                    continue
                    ;;
            esac

            candidates="$candidates$screen$tab$priority$tab$timestamp$tab$exported_name
"
        done
        ((test_index += 1))
    done

    for screen in home saves plan map; do
        newest="$(
            printf '%s' "$candidates" |
                awk -F"$tab" -v want="$screen" '
                    $1 == want && (file == "" || $2 + 0 > best_priority || ($2 + 0 == best_priority && $3 + 0 >= best_timestamp)) {
                        best_priority = $2 + 0
                        best_timestamp = $3 + 0
                        file = $4
                    }
                    END { print file }
                '
        )"
        if [[ -z "$newest" ]]; then
            echo "error: result bundle has no $screen attachment" >&2
            rm -rf "$export_dir"
            exit 2
        fi

        attempts="$(
            printf '%s' "$candidates" |
                awk -F"$tab" -v want="$screen" '$1 == want { n += 1 } END { print n + 0 }'
        )"
        if ((attempts > 1)); then
            echo "note: $screen has $attempts candidate attachments; using the highest-priority newest"
        fi

        cp "$export_dir/$newest" "$ARTIFACT_DIR/output/$screen.png"
    done
    rm -rf "$export_dir"
else
    if [[ ! -d "$SCREENSHOTS_DIR" ]]; then
        echo "error: screenshots directory not found: $SCREENSHOTS_DIR" >&2
        exit 2
    fi
    for screen in home saves plan map; do
        if [[ ! -f "$SCREENSHOTS_DIR/$screen.png" ]]; then
            echo "error: missing screenshot: $SCREENSHOTS_DIR/$screen.png" >&2
            exit 2
        fi
        cp "$SCREENSHOTS_DIR/$screen.png" "$ARTIFACT_DIR/output/$screen.png"
    done
fi

gate_failed=0
for screen in home saves plan map; do
    actual="$ARTIFACT_DIR/output/$screen.png"
    if [[ ! -f "$actual" ]]; then
        echo "error: missing exported attachment for $screen" >&2
        exit 2
    fi

    if xcrun swift "$PARITY_SCRIPT" \
        --target "$ARTIFACT_DIR/reference/$screen.png" \
        --actual "$actual" \
        --diff "$ARTIFACT_DIR/diff/$screen.png" \
        --threshold "$THRESHOLD" \
        >"$ARTIFACT_DIR/results/$screen.json"
    then
        status="PASS"
    else
        comparison_status=$?
        if ((comparison_status == 1)); then
            status="FAIL"
            gate_failed=1
        else
            echo "error: parity comparison failed for $screen" >&2
            cat "$ARTIFACT_DIR/results/$screen.json" >&2
            exit "$comparison_status"
        fi
    fi

    score="$(
        plutil -extract composite raw -o - "$ARTIFACT_DIR/results/$screen.json"
    )"
    printf '%-5s %-5s score=%s threshold=%s\n' "$status" "$screen" "$score" "$THRESHOLD"
done

echo "reference: $ARTIFACT_DIR/reference"
echo "output:    $ARTIFACT_DIR/output"
echo "diff:      $ARTIFACT_DIR/diff"
echo "results:   $ARTIFACT_DIR/results"

if ((gate_failed)); then
    exit 1
fi
