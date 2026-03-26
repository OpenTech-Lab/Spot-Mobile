#!/usr/bin/env bash
set -euo pipefail

SQL_DIR="${1:-}"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required." >&2
  exit 1
fi

if [[ -z "$SQL_DIR" ]]; then
  echo "SQL directory argument is required." >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required to apply metadata SQL migrations." >&2
  exit 1
fi

shopt -s nullglob
sql_files=("$SQL_DIR"/*.sql)

if (( ${#sql_files[@]} == 0 )); then
  echo "No SQL files found in $SQL_DIR" >&2
  exit 1
fi

for file in "${sql_files[@]}"; do
  echo "Applying $(basename "$file")"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
done
