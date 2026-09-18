#!/usr/bin/env bash
# Monitor live DB selama stress test — tulis CSV ke /tmp/stress/monitor.csv
# Pakai: scripts/stress/monitor.sh [interval_detik] [durasi_detik]
# Berhenti otomatis kalau koneksi > 50 (jaga-jaga plan Free = 60).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
REF="${REF:-fohcucyyejdryryoxitm}"
OUT="${OUT:-/tmp/stress/monitor.csv}"
INTERVAL="${1:-5}"
DURATION="${2:-3600}"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
[ -z "$TOK" ] && { echo "token tidak ada" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
[ -f "$OUT" ] || echo "t,conns,active,locks,waiting,longest_ms,slow_queries" > "$OUT"

q() {
  python3 -c "import json,sys;print(json.dumps({'query':sys.argv[1]}))" "$1" > /tmp/stress/_mq.json
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data-binary @/tmp/stress/_mq.json --max-time 20
}

SQL="select
  (select count(*) from pg_stat_activity) as conns,
  (select count(*) from pg_stat_activity where state='active') as active,
  (select count(*) from pg_locks where not granted) as waiting_locks,
  (select count(*) from pg_stat_activity where wait_event_type='Lock') as waiting,
  coalesce((select round(max(extract(epoch from now()-query_start))*1000)
            from pg_stat_activity where state='active'),0)::int as longest_ms,
  (select count(*) from pg_stat_activity where state='active'
     and now()-query_start > interval '1 second') as slow_queries;"

START=$(date +%s)
while true; do
  NOW=$(date +%s)
  [ $((NOW-START)) -ge "$DURATION" ] && break
  ROW="$(q "$SQL")"
  LINE=$(echo "$ROW" | python3 -c "
import json,sys
try:
  d=json.load(sys.stdin)
  r=d[0] if isinstance(d,list) and d else {}
  print('%s,%s,%s,%s,%s,%s' % (r.get('conns'),r.get('active'),r.get('waiting_locks'),r.get('waiting'),r.get('longest_ms'),r.get('slow_queries')))
except Exception:
  print('-,-,-,-,-,-')
" 2>/dev/null)
  echo "$(date +%s),$LINE" >> "$OUT"
  CONNS=$(echo "$LINE" | cut -d, -f1)
  if [ "$CONNS" != "-" ] && [ "$CONNS" -gt 50 ] 2>/dev/null; then
    echo "!! ABORT: koneksi=$CONNS (>50 dari limit 60)" >> "$OUT"
    break
  fi
  sleep "$INTERVAL"
done
echo "monitor selesai -> $OUT"
