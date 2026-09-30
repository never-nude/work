#!/usr/bin/env bash
# Spins up a throwaway Postgres, applies the migration on a Supabase auth shim, runs the RLS scenarios.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | tail -1)"
PARENT="$(mktemp -d)"
chmod 777 "$PARENT"
DATA="$PARENT/data"
PORT=55432
as_pg() { if [ "$(id -u)" = 0 ]; then su postgres -s /bin/bash -c "$*"; else bash -c "$*"; fi; }
as_pg "$BIN/initdb -D $DATA -A trust -U postgres >/dev/null"
as_pg "$BIN/pg_ctl -D $DATA -o '-p $PORT -k $DATA' -l $DATA/log -w start >/dev/null"
trap 'as_pg "$BIN/pg_ctl -D $DATA -m immediate stop >/dev/null" || true; rm -rf "$PARENT"' EXIT
PSQL=(psql -h "$DATA" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -X -t -A)
"${PSQL[@]}" -c "create database sniffari" >/dev/null
"${PSQL[@]}" -d sniffari -f "$HERE/shim.sql" >/dev/null 2>&1
for m in "$HERE"/../migrations/*.sql; do "${PSQL[@]}" -d sniffari -f "$m" >/dev/null; done
"${PSQL[@]}" -d sniffari -f "$HERE/rls_test.sql" 2>&1 | sed -n 's/^.*NOTICE:  /  /p; /PASSED/p; /FAIL/p; /ERROR/p'
