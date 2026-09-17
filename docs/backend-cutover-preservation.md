# Build 125 backend mismatch: preservation and release gate

The signed 1.0.0 (125) archive contains `SAVE_API_URL` pointing to
`https://wanderly-api-production.up.railway.app`. The backend repaired on
2026-09-17 is `https://save-backend-production.up.railway.app`. Upload success,
source tests and the managed backend health check did not prove that those
backend repairs reached the installed app. Both origins remain distinct.

## Implementation and remaining boundary

This patch blocks an archive when its packaged API differs from the explicitly
selected deployment target. It restores and extends the isolated DEBUG exporter
from the closed, unmerged account-preservation work (#219), and adds an offline
comparison of both account snapshots. It does not change production URLs,
migrate or delete user records, guess unresolved venues, or deploy a build.
Old account data must be preserved before replacing its service. The current
Railway account cannot manage the legacy project. A currently valid old-project
login would permit a different repair route; otherwise signed-in account export
is the next required evidence. Do not extract device/keychain tokens.

## Same-account diagnostic export

Build Debug in a separate test installation and sign in to the user's existing
Savvy account. Preserve their current phone installation and its local vault.
Launch with:

```
--debug-export-vault-pair
```

The normal API URL is unchanged. Both known HTTPS origins are read through the
app's normal authenticated GET layer; tokens remain in-process. The exporter
checks session generation and account identity before and after every response.
Each snapshot is a separate UUID directory under `Documents/vault-export`, with
0700 directories, 0600 files, raw bytes, SHA-256 checksums and a manifest. Failures
are recorded, not replaced with empty data. Logs contain no records, tokens or
server error bodies. A per-account subject hash binds the snapshots to the same
Privy account without logging that subject.

Declared API resources: profile, places, trips, review candidates, source
captures, memory preferences, recommendation outcomes, and lists with embedded
items. Lists additionally export members; share codes are requested only for
owner-role lists. Two read-only service probes record success/failure category
and available HTTP status for `/v0/shared-posts/mine` and `/v0/social-profile`.
These distinguish missing old routes from auth failures without saving response
bodies. Probe success alone does not prove valid app decoding or UI behavior.

Single-origin mode remains available:

```
--debug-export-vault --debug-export-vault-api https://wanderly-api-production.up.railway.app
```

The two known origins are allowlisted; credential URLs, alternate hosts, ports,
paths, queries and fragments are rejected. The older
`--debug-migrate-legacy-commit` path is not a complete migration and must not be
used for this cutover.

## Compare private snapshots

After copying both whole export directories to a private backup location:

```sh
python3 scripts/compare-account-exports.py \
  --source /private/backup/legacy-snapshot \
  --target /private/backup/managed-snapshot \
  --output /private/backup/new-comparison.json
```

The output must not already exist. It is created with mode 0600; terminal output
contains only status. The tool verifies origin, account binding, completion,
checksums, resource coverage, list ownership and record identities. It rejects
symlinks/path traversal, duplicate IDs, omitted files and partial snapshots.
It reports missing target records, target-only records and same-ID content
conflicts, plus exact provider-ID duplicate places and unresolved candidate IDs.
It never automatically merges/deletes records or settles an analysis workflow.

`apiSnapshotsEquivalent` compares only the declared returned records. Even exact
parity leaves `safeToCutOver=false`: device-only records, binary media, resources
without export routes, all other accounts, and edits during sequential export
remain unverified. In particular the current recommendation-outcomes GET is
limited to 200 rows. Do not claim a full database backup or complete migration.
Same-name places with different/unknown provider IDs need account-specific review.

## Release packaging

Every Release build now requires both variables:

```sh
SAVE_RELEASE_SECRETS_PLIST=/private/release/Secrets.plist \
SAVE_EXPECTED_API_URL=https://save-backend-production.up.railway.app \
  scripts/xcodebuild-clean.sh ...
```

Use the independently verified deployment origin, not a value inferred from the
old archive. The packager checks `SAVE_API_URL` and any `WANDERLY_API_URL` alias
against that origin before copying secrets into main app or App Clip. Missing,
conflicting, malformed and stale target settings fail without printing values.
This is a target consistency gate, not permission to switch: backup, inventory,
conflict resolution and actual account verification still precede cutover.
CI's unsigned synthetic candidate explicitly retains its legacy fixture target;
CI is not an authenticated production or migration check.

## Verification and execution order

1. `scripts/test-package-google-places-secrets.sh` reproduces the build125 mismatch.
2. `scripts/check-account-export.sh` compiles the real exporter with service stubs.
3. `python3 -B -m unittest discover -s Tests/account_preservation -p 'test_*.py' -v`
   covers checksum, identity, partial-failure, ownership and conflict boundaries.
4. Build the app against the generic iOS Simulator destination without booting.
5. Obtain authenticated old/new snapshots and a separate local-only/media inventory.
6. Back up the managed DB; review a record-specific, idempotent migration plan
   that preserves newer target values, ownership and independent pending workflows.
7. Only after approval, apply and re-read that exact migration, then change the
   release configuration and verify the installed app's actual authenticated API.

Merge, production migration, cutover and TestFlight release remain explicit
human-controlled actions. Never claim user's three symptoms resolved from these
fixture checks alone.
