#!/usr/bin/env bash
# Run xcodebuild up to N times. Retry only the tests that failed. Stop as
# soon as the same test fails two consecutive attempts (deterministic).
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/run-ios-xcodebuild-retry.sh \
    --max-attempts N \
    --result-bundle PATH \
    --log PATH \
    --only-testing-file PATH \
    -- xcodebuild-args...
EOF
}

max_attempts=3
result_bundle=""
log_path=""
only_testing_file=""
xcodebuild_args=()

while (($#)); do
    case "$1" in
        --max-attempts)
            max_attempts="${2:?missing value for --max-attempts}"
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
        --only-testing-file)
            only_testing_file="${2:?missing value for --only-testing-file}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            xcodebuild_args=("$@")
            break
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ((${#xcodebuild_args[@]} == 0)) || [[ -z "$result_bundle" || -z "$log_path" || -z "$only_testing_file" ]]; then
    usage >&2
    exit 2
fi
if ((max_attempts < 1)); then
    echo "error: --max-attempts must be >= 1" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
selector="$only_testing_file"
previous_failed=""
: >"$log_path"

merge_xcresult() {
    local existing="$1"
    local incoming="$2"
    local merged="$3"
    rm -rf "$merged"
    if [[ ! -d "$existing" ]]; then
        mv "$incoming" "$merged"
        return 0
    fi
    if xcrun xcresulttool merge "$existing" "$incoming" --output-path "$merged"; then
        rm -rf "$existing" "$incoming"
        return 0
    fi
    if xcrun xcresulttool merge --output-path "$merged" "$existing" "$incoming"; then
        rm -rf "$existing" "$incoming"
        return 0
    fi
    echo "error: xcresulttool merge failed" >&2
    return 1
}

for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do
    attempt_log="${log_path%.log}-attempt${attempt}.log"
    attempt_bundle="${result_bundle%.xcresult}-attempt${attempt}.xcresult"
    rm -rf "$attempt_bundle"
    echo "UI attempt ${attempt}/${max_attempts}" >&2

    ui_args=()
    while IFS= read -r argument; do
        [[ -n "$argument" ]] || continue
        ui_args+=("$argument")
    done <"$selector"
    if ((${#ui_args[@]} == 0)); then
        echo "error: no -only-testing selectors for attempt ${attempt}" >&2
        exit 1
    fi

    set +e
    SAVE_XCODEBUILD_LOG="$attempt_log" \
        "$script_dir/xcodebuild-clean.sh" \
        "${xcodebuild_args[@]}" \
        -resultBundlePath "$attempt_bundle" \
        "${ui_args[@]}"
    status=$?
    set -e

    if [[ -f "$attempt_log" ]]; then
        cat "$attempt_log" >>"$log_path"
    fi

    if [[ -d "$attempt_bundle" ]]; then
        if [[ -d "$result_bundle" ]]; then
            merge_xcresult "$result_bundle" "$attempt_bundle" "${result_bundle}.merging.xcresult"
            mv "${result_bundle}.merging.xcresult" "$result_bundle"
        else
            mv "$attempt_bundle" "$result_bundle"
        fi
    fi

    if ((status == 0)); then
        echo "UI tests passed on attempt ${attempt}" >&2
        exit 0
    fi

    current_failed="${log_path%.log}-failed-${attempt}.txt"
    python3 -B "$script_dir/ios_ui_retry.py" failed-tests "$attempt_log" >"$current_failed"
    if [[ ! -s "$current_failed" ]]; then
        echo "xcodebuild failed before reporting Test Case results; retrying the same selectors." >&2
        continue
    fi

    if [[ -n "$previous_failed" ]]; then
        if ! python3 -B "$script_dir/ios_ui_retry.py" fail-fast "$previous_failed" "$current_failed"; then
            echo "Failing fast after a deterministic UI failure." >&2
            exit 1
        fi
    fi

    if ((attempt == max_attempts)); then
        echo "UI tests still failing after ${max_attempts} attempts." >&2
        exit 1
    fi

    echo "Retrying only the tests that failed attempt ${attempt}:" >&2
    cat "$current_failed" >&2
    selector="$current_failed"
    previous_failed="$current_failed"
done

exit 1
