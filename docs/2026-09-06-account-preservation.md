# Account preservation before backend cutover

The existing TestFlight app still displays the user's data. That observation may
include cached data and does not establish that all old API data is backed up.
Keep the app's production API unchanged until an authenticated inventory and
reconciliation are complete.

## Prepared exporter

`DebugVaultExporter` is DEBUG-only and runs after the app has an authenticated
session. It uses the existing service's GET method; credentials remain inside
the app. Run in a separate test installation, preserving the user's existing
phone installation and its local data. This change does not enable an export
button in an already installed TestFlight build.

Launch arguments for the old backend:

```text
--debug-export-vault
--debug-export-vault-api https://wanderly-api-production.up.railway.app
```

For the managed backend, use the same account with:

```text
--debug-export-vault
--debug-export-vault-api https://save-backend-production.up.railway.app
```

Only those two HTTPS origins are accepted. No custom hosts, credentials, ports,
paths, queries or fragments are allowed. These arguments change only the
exporter's read target; they do not switch the app's normal API.

Each run creates a private `Documents/vault-export/<UUID>/` directory. The
manifest records source, timestamps, resource paths, raw-file sizes and SHA-256
checksums, plus failed resources. An interrupted or failed run must not be
combined with earlier files. Preserve the whole directory and verify each
checksum after copying it to the user's private backup folder. Response bodies,
account names, access tokens and error payloads are not logged.

Covered API resources: profile, places, trips, review candidates, origin captures,
memory preferences, recommendation outcomes, and collaborative lists including
their embedded items. Each valid list also exports members; owner-role lists
export share codes. Member access is still enforced by the backend. Unsupported
or denied endpoints are recorded as failures rather than interpreted as empty
lists. A second profile read checks that the account has not changed during the
run. This is a sequential API export, not a transactionally consistent database
snapshot; pause edits while taking and comparing exports.

## Cutover gate

`allRequestsSucceeded` means only that the declared requests and file writes
succeeded. `safeToCutOver` remains false. Device-only state, binary media,
resources without export routes, other accounts and historical server-only data
are not covered. Shared lists are not assumed to be owned by the exporting user.
Do not replay memberships or recreate someone else's shared list as user-owned.

Before any migration write or app switch:

1. Back up the managed database and preserve the old app and API.
2. Obtain both real account exports. Verify manifests/checksums and compare IDs,
   contents, relations and unresolved resources, not just total record counts.
3. Inventory local-only data and media separately. Resolve missing or unsupported
   resources and ownership constraints explicitly.
4. Produce an idempotent migration plan that preserves newer target data and
   flags conflicts. The old `DebugLegacyMigrator` covers only places/trips and
   skips matching IDs without proving field parity; it is not this gate.
5. Verify migrated records and relations before changing production defaults or
   distributing a new app. Do not delete old data as part of this work.

## Verification receipt

Run `scripts/check-account-export.sh` on macOS. It compiles the real exporter
against service-signature stubs and checks raw-file checksums, private file
permissions, independent snapshots, partial failures, malformed payloads,
profile identity changes, list owner/member behavior and source restrictions.
It does not contact live services or prove an authenticated iOS export.
Native compilation/CI, signed-in runtime exports and data reconciliation remain
separate gates. No production API switch or migration writes are included in
this patch.
