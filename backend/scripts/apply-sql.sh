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

Examples:
  ./scripts/apply-sql.sh friend-ratings.sql
  ./scripts/apply-sql.sh friend-ratings.sql --apply

SSL: strips ?query from DATABASE_URL (pooler URLs often carry
sslmode=no-verify, which modern libpq rejects) and invokes
  PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -1 -f <file>
unless PGSSLMODE is already a valid libpq value (disable, allow, prefer,
require, verify-ca, verify-full). Legacy no-verify is overridden to require
for this psql process only; the Railway service env is not rewritten.
EOF
}

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

echo "file: backend/sql/${base}"
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

echo "psql: PGSSLMODE=${sslmode} psql \"\${DATABASE_URL%%\\?*}\" -v ON_ERROR_STOP=1 -1 -f backend/sql/${base}"

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

url="${DATABASE_URL%%\?*}"
echo "applying (URL redacted)…"
PGSSLMODE="$sslmode" psql "$url" -v ON_ERROR_STOP=1 -1 -f "$sql_file"
