#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Required by validate/CI: never use DATABASE_URL or an app database. PostgreSQL
# server tools are available on the Ubuntu Actions image; local runs need them.
pg_bin="$(pg_config --bindir)"
for binary in initdb pg_ctl createdb; do
  if [[ ! -x "$pg_bin/$binary" ]]; then
    echo "Missing PostgreSQL server tool: $pg_bin/$binary" >&2
    exit 1
  fi
done
fixture_root="$(mktemp -d /tmp/save-paid-readiness-ci-XXXXXX)"
started=false
cleanup() {
  if [[ "$started" == true ]]; then
    if ! "$pg_bin/pg_ctl" -D "$fixture_root/data" -m fast -w stop; then
      echo "Could not stop test database; retained $fixture_root" >&2
      return 1
    fi
  fi
  # Only the random directory created by this invocation is removed.
  find "$fixture_root" -depth -delete
}
trap cleanup EXIT
mkdir "$fixture_root/socket"
"$pg_bin/initdb" -D "$fixture_root/data" -U save_fixture -A trust --no-locale > "$fixture_root/init.log"
# A unique Unix socket directory isolates concurrent runs; no TCP listener.
"$pg_bin/pg_ctl" -D "$fixture_root/data" -l "$fixture_root/server.log" \
  -o "-k $fixture_root/socket -p 55439 -c listen_addresses=''" -w start
started=true
"$pg_bin/createdb" -h "$fixture_root/socket" -p 55439 -U save_fixture save_paid_fixture
SAVE_ENTITLEMENT_TEST_DATABASE_URL="postgresql://save_fixture@localhost:55439/save_paid_fixture?host=$fixture_root/socket" \
  node --test --test-concurrency=1 dist/entitlementPersistence.test.js dist/backendDataPrivacy.test.js
