#!/usr/bin/env bash
# Apply one pending backend/sql/*.sql file against DATABASE_URL.
# Local/ops only. Never invoked on server boot. Founder-owned production apply.
# Does not deploy Railway. Does not print secrets.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: apply-sql.sh <name.sql> [--apply]

  Dry-read (default): print statement order and a redacted psql command.
  --apply: run that command. Requires DATABASE_URL. Not used on boot.

Examples (from backend/):
  ./scripts/apply-sql.sh friend-ratings.sql
  ./scripts/apply-sql.sh friend-ratings.sql --apply

SSL: drops only sslmode= from DATABASE_URL (pooler URLs often carry
sslmode=no-verify, which modern libpq rejects) and invokes
  PGSSLMODE=require psql <rewritten-url> -v ON_ERROR_STOP=1 -1 -f sql/<file>
from backend/. Other query params (options, target_session_attrs, …) are kept.
--apply uses this script's absolute sql path, so cwd does not matter.

Unless PGSSLMODE is already a valid libpq value (disable, allow, prefer,
require, verify-ca, verify-full). Legacy no-verify is overridden to require
for this psql process only; the Railway service env is not rewritten.

The documented founder one-liner still strips the whole query string
(${DATABASE_URL%%\?*}) because the known prod URL only carries sslmode.
Use this helper, or restore extra params by hand, when the URL has more.
EOF
}

# Drop sslmode=… only. Never print the result; callers must not echo it.
psql_url() {
  local raw="$1"
  local base="${raw%%\?*}"
  if [[ "$raw" != *"?"* ]]; then
    printf '%s' "$raw"
    return
  fi
  local query="${raw#*\?}"
  local kept=""
  local part
  local IFS='&'
  for part in $query; do
    case "$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')" in
      sslmode=*|sslmode|"") continue ;;
    esac
    if [[ -n "$kept" ]]; then
      kept="${kept}&${part}"
    else
      kept="$part"
    fi
  done
  if [[ -n "$kept" ]]; then
    printf '%s?%s' "$base" "$kept"
  else
    printf '%s' "$base"
  fi
}

if [[ "${1:-}" == "--self-test" ]]; then
  expect() {
    local got
    got="$(psql_url "$1")"
    if [[ "$got" != "$2" ]]; then
      echo "self-test failed: $(printf '%q' "$1") -> $(printf '%q' "$got") (want $(printf '%q' "$2"))" >&2
      exit 1
    fi
  }
  expect "postgresql://u:p@h:5432/db" "postgresql://u:p@h:5432/db"
  expect "postgresql://u:p@h:5432/db?sslmode=no-verify" "postgresql://u:p@h:5432/db"
  expect "postgresql://u:p@h:5432/db?sslmode=require" "postgresql://u:p@h:5432/db"
  expect "postgresql://u:p@h:5432/db?sslmode=no-verify&options=-c%20search_path%3Dpublic" \
    "postgresql://u:p@h:5432/db?options=-c%20search_path%3Dpublic"
  expect "postgresql://u:p@h:5432/db?options=-c%20search_path%3Dpublic&sslmode=no-verify&target_session_attrs=read-write" \
    "postgresql://u:p@h:5432/db?options=-c%20search_path%3Dpublic&target_session_attrs=read-write"
  echo "apply-sql self-test passed"
  exit 0
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sql_dir="$(cd "${script_dir}/../sql" && pwd)"
apply=0
name=""

for arg in "$@"; do
  case "$arg" in
    --apply) apply=1 ;;
    --self-test) echo "--self-test must be the only argument" >&2; exit 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$name" ]]; then
        echo "only one SQL file is allowed" >&2
        exit 2
      fi
      name="$arg"
      ;;
  esac
done

if [[ -z "$name" ]]; then
  usage >&2
  exit 2
fi

base="$(basename -- "$name")"
if [[ "$base" != "$name" && "$name" != "sql/$base" && "$name" != "backend/sql/$base" ]]; then
  echo "refusing path outside backend/sql: $name" >&2
  exit 2
fi
if [[ "$base" != *.sql || "$base" == *..* ]]; then
  echo "expected a *.sql basename under backend/sql" >&2
  exit 2
fi

sql_file="${sql_dir}/${base}"
if [[ ! -f "$sql_file" ]]; then
  echo "missing ${sql_file}" >&2
  exit 2
fi

echo "file: sql/${base} (from backend/; --apply uses this script's absolute path)"
echo "boot: never (manual / founder-owned only)"
echo "order:"
awk '
  BEGIN { n = 0 }
  /^[[:space:]]*--/ { next }
  /^[[:space:]]*$/ { next }
  {
    line = $0
    sub(/^[[:space:]]+/, "", line)
    if (line ~ /^(create|alter|drop|insert|update|delete|do)[[:space:]]/) {
      n += 1
      printf "  %d. %s\n", n, line
    }
  }
' "$sql_file"

if [[ "$base" == "friend-ratings.sql" ]]; then
  index_line="$(grep -n -i 'create unique index if not exists idx_places_id_user_id' "$sql_file" | head -n 1 | cut -d: -f1)"
  fk_line="$(grep -n -i 'references places(id, user_id)' "$sql_file" | head -n 1 | cut -d: -f1)"
  if [[ -z "$index_line" || -z "$fk_line" || "$index_line" -ge "$fk_line" ]]; then
    echo "order check failed: idx_places_id_user_id must be created before the composite FK" >&2
    exit 1
  fi
  echo "order check: idx_places_id_user_id (line ${index_line}) before composite FK (line ${fk_line})"
fi

sslmode="$(printf '%s' "${PGSSLMODE:-}" | tr '[:upper:]' '[:lower:]')"
case "$sslmode" in
  disable|allow|prefer|require|verify-ca|verify-full) ;;
  no-verify|"")
    if [[ "$sslmode" == "no-verify" ]]; then
      echo "ssl: overriding legacy PGSSLMODE=no-verify -> require for this psql only"
    else
      echo "ssl: defaulting this psql to PGSSLMODE=require"
    fi
    sslmode="require"
    ;;
  *)
    echo "ssl: unsupported PGSSLMODE=${PGSSLMODE}; using require for this psql only" >&2
    sslmode="require"
    ;;
esac

echo "psql: (from backend/) PGSSLMODE=${sslmode} psql <url, sslmode query dropped> -v ON_ERROR_STOP=1 -1 -f sql/${base}"

if [[ "$apply" -eq 0 ]]; then
  echo "dry-read only; pass --apply to execute (requires DATABASE_URL)"
  exit 0
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required for --apply" >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is not on PATH" >&2
  exit 2
fi

url="$(psql_url "$DATABASE_URL")"
echo "applying (URL redacted)…"
PGSSLMODE="$sslmode" psql "$url" -v ON_ERROR_STOP=1 -1 -f "$sql_file"
