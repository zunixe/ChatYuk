#!/usr/bin/env bash
# Lapis 3: test REALTIME konkuren — buka N websocket Supabase, subscribe
# channel seperti app, ukur connect sukses/gagal + latensi event.
# Ini titik terlemah plan Free (limit concurrent realtime ~200).
#
# Pakai: scripts/stress/realtime.sh [start] [step] [max] [hold_detik]
#   contoh: scripts/stress/realtime.sh 50 50 300 20
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
REF="${REF:-fohcucyyejdryryoxitm}"
ANON="$(cat /tmp/stress/anon.key)"
URL="https://fohcucyyejdryryoxitm.supabase.co"

START="${1:-50}"; STEP="${2:-50}"; MAX="${3:-300}"; HOLD="${4:-20}"

echo "=== REALTIME CONCURRENCY TEST ($START → $MAX, step $STEP, hold ${HOLD}s) ==="
echo "url=$URL"

N="$START"
while [ "$N" -le "$MAX" ]; do
  echo; echo "--- $N koneksi ---"
  node scripts/stress/realtime.mjs "$URL" "$ANON" "$N" "$HOLD"
  N=$((N + STEP))
done
