#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${SAVE_DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData/SAVE-Codex}"
minimum_free_kib=$((10 * 1024 * 1024))
owned_simulator=""

cleanup() {
  local command_status=$?
  local cleanup_status=0
  trap - EXIT

  if [[ -z "$owned_simulator" ]]; then
    exit "$command_status"
  fi

  xcrun simctl shutdown "$owned_simulator" >/dev/null 2>&1 || true
  if xcrun simctl list devices | grep -F "$owned_simulator" | grep -Fq "(Shutdown)"; then
    echo "social place regression: simulator shutdown verified" >&2
  else
    echo "social place regression: simulator shutdown could not be verified" >&2
    cleanup_status=1
  fi
  if ! xcrun simctl delete "$owned_simulator" >/dev/null 2>&1; then
    echo "social place regression: simulator deletion failed" >&2
    cleanup_status=1
  elif xcrun simctl list devices | grep -Fq "$owned_simulator"; then
    echo "social place regression: simulator deletion could not be verified" >&2
    cleanup_status=1
  fi

  if [[ "$command_status" -ne 0 ]]; then
    exit "$command_status"
  fi
  exit "$cleanup_status"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

if [[ "${1:-}" == "--dry-run" ]]; then
  printf '%q ' \
    "$repo_root/scripts/xcodebuild-clean.sh" \
    -project "$repo_root/SAV-E.xcodeproj" \
    -scheme SAV-E \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=<ephemeral-simulator-udid>" \
    -derivedDataPath "$derived_data" \
    "-only-testing:SAVETests/SocialPlacePipelineTests/testSocialPipelineRegressionCasesStayStable" \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    test
  printf '\n'
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "usage: swift scripts/social_place_regression.swift [--dry-run]" >&2
  exit 64
fi

free_kib="$(df -Pk "$repo_root" | awk 'NR == 2 { print $4 }')"
if [[ -z "$free_kib" ]]; then
  echo "social place regression: could not determine free disk space" >&2
  exit 2
fi
if [[ "$free_kib" -lt "$minimum_free_kib" ]]; then
  echo "social place regression: requires at least 10 GiB free before running on a simulator (found $((free_kib / 1024 / 1024)) GiB)" >&2
  exit 2
fi

if [[ -n "${SAVE_TEST_SIMULATOR_UDID:-}" ]]; then
  simulator_udid="$SAVE_TEST_SIMULATOR_UDID"
else
  runtime_identifier="$(
    xcrun simctl list runtimes |
      awk '$1 == "iOS" && $NF ~ /^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/ && $0 !~ /unavailable/ { runtime = $NF } END { print runtime }'
  )"
  if [[ -z "$runtime_identifier" ]]; then
    echo "social place regression: no available iOS Simulator runtime" >&2
    exit 2
  fi

  device_type_identifier="$(
    xcrun simctl list devicetypes |
      awk -F '[()]' '/^iPhone 16 Pro / { print $2; exit }'
  )"
  if [[ -z "$device_type_identifier" ]]; then
    device_type_identifier="$(
      xcrun simctl list devicetypes |
        awk -F '[()]' '/^iPhone / { print $2; exit }'
    )"
  fi
  if [[ -z "$device_type_identifier" ]]; then
    echo "social place regression: no available iPhone Simulator device type" >&2
    exit 2
  fi

  owned_simulator="$(
    xcrun simctl create \
      "SAV-E Social Place Regression" \
      "$device_type_identifier" \
      "$runtime_identifier"
  )"
  simulator_udid="$owned_simulator"
  xcrun simctl boot "$simulator_udid"
  xcrun simctl bootstatus "$simulator_udid" -b
fi

"$repo_root/scripts/xcodebuild-clean.sh" \
  -project "$repo_root/SAV-E.xcodeproj" \
  -scheme SAV-E \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  "-only-testing:SAVETests/SocialPlacePipelineTests/testSocialPipelineRegressionCasesStayStable" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test
