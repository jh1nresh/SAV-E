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
  local expected_url="${4-https://wanderly-api-production.up.railway.app}"
  local product_folder="${5:-SAVE.app}"

  env \
    CONFIGURATION="$configuration" \
    SRCROOT="$source_root" \
    TARGET_BUILD_DIR="$build_directory" \
    UNLOCALIZED_RESOURCES_FOLDER_PATH="$product_folder" \
    SAVE_RELEASE_SECRETS_PLIST="$release_plist" \
    SAVE_EXPECTED_API_URL="$expected_url" \
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

expect_failure release_target_missing run_packager Release "${temporary_root}/no-target" "$dummy_plist" ""
expect_failure release_stale_backend run_packager Release "${temporary_root}/stale-backend" "$dummy_plist" "https://save-backend-production.up.railway.app"
[[ ! -e "${temporary_root}/stale-backend/SAVE.app/Secrets.plist" ]] || exit 1
managed_plist="${temporary_root}/managed.plist"
cp "$dummy_plist" "$managed_plist"
plutil -replace SAVE_API_URL -string 'https://save-backend-production.up.railway.app' "$managed_plist"
plutil -replace WANDERLY_API_URL -string 'https://wanderly-api-production.up.railway.app' "$managed_plist"
expect_failure release_conflicting_alias run_packager Release "${temporary_root}/conflicting" "$managed_plist" "https://save-backend-production.up.railway.app"
plutil -replace WANDERLY_API_URL -string 'https://save-backend-production.up.railway.app' "$managed_plist"
run_packager Release "${temporary_root}/managed" "$managed_plist" "https://save-backend-production.up.railway.app"
assert_private_copy "$managed_plist" "${temporary_root}/managed/SAVE.app/Secrets.plist"

release_build="${temporary_root}/release-build"
run_packager Release "$release_build" "$dummy_plist"
assert_private_copy "$dummy_plist" "${release_build}/SAVE.app/Secrets.plist"

clip_build="${temporary_root}/clip-release"
run_packager Release "$clip_build" "$dummy_plist" \
  "https://wanderly-api-production.up.railway.app" "SAVEClip.app"
assert_private_copy "$dummy_plist" "${clip_build}/SAVEClip.app/Secrets.plist"

expect_failure clip_stale_backend run_packager Release "${temporary_root}/clip-stale" \
  "$dummy_plist" "https://save-backend-production.up.railway.app" "SAVEClip.app"
[[ ! -e "${temporary_root}/clip-stale/SAVEClip.app/Secrets.plist" ]] || exit 1

python3 - "$repo_root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
yml = (root / "project.yml").read_text()
start = yml.find("\n  SAVEClip:\n")
if start < 0:
    raise SystemExit("SAVEClip target missing from project.yml")
rest = yml[start + 1:]
next_markers = [
    rest.find("\n  SAVEShareExtension:"),
    rest.find("\n  SAVEiMessageExtension:"),
    rest.find("\n  SAVETests:"),
]
ends = [index for index in next_markers if index >= 0]
block = rest[: min(ends)] if ends else rest
if "Package App Secrets.plist" not in block:
    raise SystemExit("SAVEClip project.yml is missing Package App Secrets.plist")
if "scripts/package-google-places-secrets.sh" not in block:
    raise SystemExit("SAVEClip project.yml does not invoke the secrets packager")

pbx = (root / "SAV-E.xcodeproj/project.pbxproj").read_text()
target = re.search(
    r"/\* SAVEClip \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);",
    pbx,
    re.S,
)
if target is None:
    raise SystemExit("SAVEClip native target missing from pbxproj")
phase_ids = re.findall(r"([A-F0-9]{24}) /\* ([^*]+) \*/", target.group(1))
if not any(name.strip() == "Package App Secrets.plist" for _, name in phase_ids):
    raise SystemExit("SAVEClip pbxproj is missing Package App Secrets.plist phase")
for phase_id, name in phase_ids:
    if name.strip() != "Package App Secrets.plist":
        continue
    phase = re.search(
        rf"{phase_id} /\* Package App Secrets.plist \*/ = \{{(.*?)\n\t\t\}};",
        pbx,
        re.S,
    )
    if phase is None or "package-google-places-secrets.sh" not in phase.group(1):
        raise SystemExit("SAVEClip secrets phase does not invoke the packager")
PY

printf 'Secrets packaging regression checks passed.\n'
