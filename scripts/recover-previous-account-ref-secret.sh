#!/usr/bin/env bash
# Recover the pre-2026-08-04 account-ref HMAC secret from the old Railway
# project and register it as SAVE_ACCOUNT_REF_PREVIOUS_SECRETS on the new
# save-backend, so devices provisioned before the rebuild verify as
# "previous" and rotate instead of locking out.
#
# The value never touches the terminal display or shell history: it moves
# CLI -> chmod-600 temp file -> Railway variable, then the file is removed.
#
# Run it twice; it detects which phase applies from which login it finds.
#   Phase A needs the OLD Railway account (the GitHub-OAuth login that owns
#   the old "wanderly" project). Phase B needs jhinresh@gmail.com.
set -euo pipefail

OLD_PROJECT="f0ec5a3d-dded-4483-90d3-2ece7a0f465a"
OLD_ENV="9bddf914-23fa-42d0-99ea-74d5deeffaa0"
STASH="$HOME/.save-old-account-ref-secret"
NEW_PROJECT_DIR="$HOME/projects/sav-e/backend"

phase_a() {
  echo "Phase A: reading the old project's secret."
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  cd "$workdir"
  railway link --project "$OLD_PROJECT" --environment "$OLD_ENV" \
    || { echo "This login cannot see the old project — log in with the OLD account (railway login) and rerun."; exit 1; }

  # The old backend may predate the dedicated var; take the legacy name too.
  vars="$(railway variables --kv 2>/dev/null || true)"
  old_secret="$(printf '%s\n' "$vars" | grep -m1 '^SAVE_ACCOUNT_REF_SECRET=' | cut -d= -f2- || true)"
  legacy="$(printf '%s\n' "$vars" | grep -m1 '^SAVE_MY_SAVES_SECRET=' | cut -d= -f2- || true)"
  combined="$(printf '%s,%s' "$old_secret" "$legacy" | sed 's/^,//; s/,$//')"
  [ -n "$combined" ] || { echo "Neither SAVE_ACCOUNT_REF_SECRET nor SAVE_MY_SAVES_SECRET exists on the old project. Pick the service holding them (railway service) and rerun."; exit 1; }

  umask 077
  printf '%s' "$combined" > "$STASH"
  echo "Captured $(printf '%s' "$combined" | tr -cd ',' | wc -c | tr -d ' ') comma(s)+1 value(s) into $STASH (600, value not shown)."
  echo "Now: railway login  (as jhinresh@gmail.com), then rerun this script."
}

phase_b() {
  echo "Phase B: registering on save-backend."
  cd "$NEW_PROJECT_DIR"
  value="$(cat "$STASH")"
  railway variables --service save-backend --set "SAVE_ACCOUNT_REF_PREVIOUS_SECRETS=$value" >/dev/null
  rm -f "$STASH"
  echo "Set SAVE_ACCOUNT_REF_PREVIOUS_SECRETS (value not shown) and removed the stash."
  echo "Verify: railway variables --service save-backend --kv | cut -d= -f1 | grep PREVIOUS"
  echo "Then relaunch the app on the ORIGINAL phone — it should verify as 'previous' and rotate."
}

if [ -f "$STASH" ]; then
  phase_b
else
  phase_a
fi
