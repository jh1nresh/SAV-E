#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

: "${CONFIGURATION:?CONFIGURATION is required}"
: "${SRCROOT:?SRCROOT is required}"
: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is required}"

template_path="${SRCROOT}/SAV-E/Resources/Secrets.plist.template"
debug_secrets_path="${SRCROOT}/SAV-E/Resources/Secrets.plist"

case "$CONFIGURATION" in
  Debug)
    if [[ -f "$debug_secrets_path" ]]; then
      source_path="$debug_secrets_path"
    else
      source_path="$template_path"
    fi
    ;;
  Release)
    source_path="${SAVE_RELEASE_SECRETS_PLIST:-}"
    [[ -n "$source_path" ]] || fail "Release requires SAVE_RELEASE_SECRETS_PLIST."
    ;;
  *)
    fail "Unsupported build configuration for secrets packaging."
    ;;
esac

[[ -f "$source_path" ]] || fail "The selected secrets plist is missing or not a regular file."
plutil -lint "$source_path" >/dev/null 2>&1 || fail "The selected secrets file is not a valid plist."

if [[ "$CONFIGURATION" == "Release" ]]; then
  key_type="$(plutil -type GOOGLE_PLACES_API_KEY "$source_path" 2>/dev/null || true)"
  [[ "$key_type" == "string" ]] || fail "Release secrets must contain GOOGLE_PLACES_API_KEY as a string."

  key="$(plutil -extract GOOGLE_PLACES_API_KEY raw -o - "$source_path" 2>/dev/null || true)"
  key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  normalized_key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"

  case "$normalized_key" in
    ""|your_key_here|replace_me|changeme|todo|*placeholder*|*your*key*here*|*replace*me*|*not*configured*|\<*\>)
      fail "Release GOOGLE_PLACES_API_KEY is blank or still a placeholder."
      ;;
  esac
fi

destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.plist"
temporary_destination="${destination}.tmp.$$"
trap 'rm -f "$temporary_destination"' EXIT

umask 077
mkdir -p "$(dirname "$destination")"
cp "$source_path" "$temporary_destination"
chmod 600 "$temporary_destination"
mv -f "$temporary_destination" "$destination"
trap - EXIT
