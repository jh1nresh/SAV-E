#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output="$repo_root/.tmp/account-export"
mkdir -p "$output"
xcrun swiftc -swift-version 6 -D DEBUG -parse-as-library \
  "$repo_root/SAV-E/Services/DebugVaultExporter.swift" \
  "$repo_root/scripts/account-export-check/main.swift" \
  -o "$output/check-account-export"
"$output/check-account-export"
