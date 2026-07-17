#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
packager="${repo_root}/scripts/package-google-places-secrets.sh"
template="${repo_root}/SAV-E/Resources/Secrets.plist.template"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/save-secrets-test.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

source_root="${temporary_root}/source"
mkdir -p "${source_root}/SAV-E/Resources"
cp "$template" "${source_root}/SAV-E/Resources/Secrets.plist.template"

run_packager() {
  local configuration="$1"
  local build_directory="$2"
  local release_plist="${3:-}"

  env \
    CONFIGURATION="$configuration" \
    SRCROOT="$source_root" \
    TARGET_BUILD_DIR="$build_directory" \
    UNLOCALIZED_RESOURCES_FOLDER_PATH="SAVE.app" \
    SAVE_RELEASE_SECRETS_PLIST="$release_plist" \
    "$packager"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"${temporary_root}/${label}.log" 2>&1; then
    printf 'Expected failure: %s\n' "$label" >&2
    exit 1
  fi
}

assert_private_copy() {
  local source="$1"
  local destination="$2"
  cmp -s "$source" "$destination" || {
    printf 'Packaged plist did not match its selected source.\n' >&2
    exit 1
  }
  [[ "$(stat -f '%Lp' "$destination")" == "600" ]] || {
    printf 'Packaged plist permissions were not private.\n' >&2
    exit 1
  }
}

debug_build="${temporary_root}/debug-build"
run_packager Debug "$debug_build"
assert_private_copy \
  "${source_root}/SAV-E/Resources/Secrets.plist.template" \
  "${debug_build}/SAVE.app/Secrets.plist"

dummy_plist="${temporary_root}/release-secrets.plist"
cp "$template" "$dummy_plist"
plutil -replace GOOGLE_PLACES_API_KEY -string 'TEST_ONLY_NON_SECRET_VALUE' "$dummy_plist"

cp "$dummy_plist" "${source_root}/SAV-E/Resources/Secrets.plist"
debug_override_build="${temporary_root}/debug-override-build"
run_packager Debug "$debug_override_build"
assert_private_copy \
  "${source_root}/SAV-E/Resources/Secrets.plist" \
  "${debug_override_build}/SAVE.app/Secrets.plist"

expect_failure release_missing run_packager Release "${temporary_root}/release-missing-build"
expect_failure release_not_regular run_packager Release "${temporary_root}/release-not-regular-build" "$temporary_root"
expect_failure release_placeholder run_packager Release "${temporary_root}/release-placeholder-build" "$template"

blank_plist="${temporary_root}/blank-release-secrets.plist"
cp "$template" "$blank_plist"
plutil -replace GOOGLE_PLACES_API_KEY -string '   ' "$blank_plist"
expect_failure release_blank run_packager Release "${temporary_root}/release-blank-build" "$blank_plist"

wrong_type_plist="${temporary_root}/wrong-type-release-secrets.plist"
cp "$template" "$wrong_type_plist"
plutil -replace GOOGLE_PLACES_API_KEY -integer 123 "$wrong_type_plist"
expect_failure release_wrong_type run_packager Release "${temporary_root}/release-wrong-type-build" "$wrong_type_plist"

release_build="${temporary_root}/release-build"
run_packager Release "$release_build" "$dummy_plist"
assert_private_copy "$dummy_plist" "${release_build}/SAVE.app/Secrets.plist"

printf 'Secrets packaging regression checks passed.\n'
