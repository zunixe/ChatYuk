#!/usr/bin/env bash
# Lapis 2: snapshot definisi 25 fungsi FROZEN dari DB live.
#
# Tujuan: mendeteksi regresi "create or replace function" yang diam-diam
# menghapus cabang (penyebab Admin Chatyuk offline 2x — lihat
# docs/FEATURE_MAP.md). Snapshot = teks `pg_get_functiondef()` asli,
# disimpan + di-commit. Setiap migrasi yang mengubah fungsi FROZEN WAJIB
# menjalankan ulang skrip ini, mereview diff, lalu commit.
#
# Pakai: scripts/snapshot_functions.sh
#   Butuh token Management API (diambil otomatis dari keychain Supabase CLI).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REF="${REF:-fohcucyyejdryryoxitm}"
LIST="$ROOT/scripts/frozen_functions.txt"
OUT="$ROOT/supabase/snapshots/functions.sql"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
if [ -z "$TOK" ]; then
  echo "token Management API tidak ditemukan di keychain" >&2
  exit 1
fi

# migrasi terakhir yang menyentuh tiap fungsi (untuk stamp @file)
stamp_for() {
  local fn="$1"
  local last
  last=$(grep -rlE "create[[:space:]]+or[[:space:]]+replace[[:space:]]+function[[:space:]]+public\.${fn}\b" "$ROOT/supabase/migrations" --include="*.sql" 2>/dev/null | sort | tail -1 || true)
  [ -z "$last" ] && echo "unknown" || basename "$last"
}

q() { # query SQL -> JSON
  python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" "$1" > /tmp/snapq.json
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data-binary @/tmp/snapq.json --max-time 60
}

mkdir -p "$(dirname "$OUT")"
{
  echo "-- SNAPSHOT fungsi FROZEN (auto-generate). JANGAN edit manual."
  echo "-- Regenerate: scripts/snapshot_functions.sh"
  echo "-- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
} > "$OUT"

n_ok=0; n_miss=0
while IFS= read -r fn; do
  [ -z "$fn" ] && continue
  case "$fn" in \#*) continue ;; esac
  stamp="$(stamp_for "$fn")"
  resp="$(q "select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${fn}' order by p.oid limit 1;")"
  def="$(python3 -c "import json,sys
try:
    d=json.load(sys.stdin)
    rows=d if isinstance(d,list) else (d.get('rows') or d.get('result') or [])
    print((rows[0].get('def') if rows and rows[0].get('def') else '').strip())
except Exception:
    print('')" <<< "$resp")"
  {
    echo "-- snapshot-fn: ${fn} @ ${stamp}"
    if [ -n "$def" ]; then
      echo "$def"
    else
      echo "-- (TIDAK DITEMUKAN di DB — fungsi belum ter-apply atau nama overload beda)"
    fi
    echo
  } >> "$OUT"
  if [ -n "$def" ]; then n_ok=$((n_ok+1)); else n_miss=$((n_miss+1)); echo "  miss: $fn"; fi
done < "$LIST"

echo "snapshot: $n_ok fungsi tersimpan, $n_miss tidak ditemukan → $OUT"
