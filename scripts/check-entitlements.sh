#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/save-entitlement-check.XXXXXX")"
trap 'find "$output" -maxdepth 1 -type f -delete; rmdir "$output"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -D SAVE_ENTITLEMENT_HOST_CHECK -parse-as-library \
  "$repo_root/SAV-EShared/SAVEProAccessPolicy.swift" \
  "$repo_root/SAV-E/Services/SaveStoreKitService.swift" \
  "$repo_root/SAV-E/Services/SaveEntitlementStore.swift" \
  "$repo_root/Tests/SocialPlacePipelineTests/SaveEntitlementWiringTests.swift" \
  "$repo_root/scripts/entitlement-check/Stubs.swift" \
  "$repo_root/scripts/entitlement-check/main.swift" \
  -o "$output/check-entitlements"
"$output/check-entitlements"
