#!/usr/bin/env bash
# Lapis 2: snapshot definisi 25 fungsi FROZEN dari DB live.
#
# Tujuan: mendeteksi regresi "create or replace function" yang diam-diam
# menghapus cabang (penyebab Admin Chatyuk offline 2x — lihat
# docs/FEATURE_MAP.md). Snapshot = teks `pg_get_functiondef()` asli,
# disimpan + di-commit. Setiap migrasi yang mengubah fungsi FROZEN WAJIB
# menjalankan ulang skrip ini, mereview diff, lalu commit.
#
# Pakai: scripts/snapshot_functions.sh            -> hanya FROZEN (default)
#        scripts/snapshot_functions.sh --all      -> SEMUA fungsi public
#   Butuh token Management API (diambil otomatis dari keychain Supabase CLI).
#
# REVIEW_2026-10-24 BUILD-04: RPC non-FROZEN (mis. refund_chat_point,
# deduct_chat_point) sebelumnya tak punya sumber kebenaran di repo — reviewer
# harus menebak versi terakhir. Mode `--all` menulis
# `supabase/snapshots/functions_all.sql` (read-only, tidak mengubah DB).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REF="${REF:-fohcucyyejdryryoxitm}"
LIST="$ROOT/scripts/frozen_functions.txt"
ALL_MODE=0
[ "${1:-}" = "--all" ] && ALL_MODE=1
if [ "$ALL_MODE" = "1" ]; then
  OUT="$ROOT/supabase/snapshots/functions_all.sql"
else
  OUT="$ROOT/supabase/snapshots/functions.sql"
fi

# Token: prioritaskan env SUPABASE_ACCESS_TOKEN (mis. dari .env), lalu keychain CLI.
TOK="${SUPABASE_ACCESS_TOKEN:-}"
[ -z "$TOK" ] && TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
if [ -z "$TOK" ]; then
  echo "token Management API tidak ditemukan di keychain" >&2
  exit 1
fi

# migrasi terakhir yang menyentuh tiap fungsi (untuk stamp @file)
stamp_for() {
  local fn="$1"
  local last
  last=$(grep -rliE "create[[:space:]]+or[[:space:]]+replace[[:space:]]+function[[:space:]]+public\.${fn}\b" "$ROOT/supabase/migrations" --include="*.sql" 2>/dev/null | sort | tail -1 || true)
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
# Mode --all: SATU query untuk SEMUA fungsi public (sebelumnya 1 request per
# fungsi -> ~424 request, sangat lambat). Query agregat = 1 round-trip.
if [ "$ALL_MODE" = "1" ]; then
  resp_all="$(q "select p.proname as fn, pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.prokind='f' order by p.proname, p.oid;")"
  printf '%s' "$resp_all" > /tmp/snap_all.json
  cat > /tmp/snap_all.py <<'PYALL'
import json, sys, datetime
out = sys.argv[1]
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    d = []
rows = d if isinstance(d, list) else (d.get('rows') or d.get('result') or [])
# Satu nama bisa punya >1 overload: gabungkan semua definisinya.
by_name = {}
for r in rows:
    fn = r.get('fn') or ''
    dfn = (r.get('def') or '').strip()
    if not fn:
        continue
    by_name.setdefault(fn, []).append(dfn)
lines = [
    "-- SNAPSHOT SEMUA fungsi public (auto-generate). JANGAN edit manual.",
    "-- Regenerate: scripts/snapshot_functions.sh --all",
    "-- Timestamp: %s" % datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "",
]
ok = 0
for fn in sorted(by_name):
    for i, dfn in enumerate(by_name[fn]):
        suffix = "" if len(by_name[fn]) == 1 else " (overload %d)" % (i + 1)
        lines.append("-- snapshot-fn: %s%s" % (fn, suffix))
        lines.append(dfn if dfn else "-- (TIDAK DITEMUKAN)")
        lines.append("")
        if dfn:
            ok += 1
with open(out, "w") as f:
    f.write("\n".join(lines))
print("snapshot(--all): %d fungsi, %d definisi -> %s" % (len(by_name), ok, out), file=sys.stderr)
PYALL
  python3 /tmp/snap_all.py "$OUT" < /tmp/snap_all.json
  exit 0
fi

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
