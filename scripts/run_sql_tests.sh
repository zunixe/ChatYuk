#!/usr/bin/env bash
# Lapis 3: jalankan semua test SQL (supabase/tests/*.sql) via Management API.
# Test bersifat transaksional (BEGIN/ROLLBACK) → data produksi tak tersentuh.
# Pakai: scripts/run_sql_tests.sh [nama_file.sql]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REF="${REF:-fohcucyyejdryryoxitm}"
TESTS_DIR="$ROOT/supabase/tests"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
[ -z "$TOK" ] && { echo "token Management API tidak ada di keychain" >&2; exit 1; }

run_one() {
  local f="$1" name; name="$(basename "$f")"
  python3 -c "import json,sys; print(json.dumps({'query': open(sys.argv[1]).read()}))" "$f" > /tmp/sqlq.json
  local resp
  resp="$(curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data-binary @/tmp/sqlq.json --max-time 90)"
  if echo "$resp" | grep -qiE '"message":.*(ERROR|error)'; then
    echo "  FAIL  $name"; echo "$resp" | head -c 800; return 1
  fi
  # Harness mengembalikan satu baris "TOTAL=n PASS=n FAIL=n[\nFAIL: ...]".
  local line
  line="$(echo "$resp" | python3 -c "import json,sys
try:
  d=json.load(sys.stdin)
  r=d if isinstance(d,list) else [d]
  for row in r:
    if isinstance(row,dict):
      for v in row.values():
        s=str(v)
        if 'TOTAL=' in s: print(s); sys.exit(0)
except Exception: pass
print('')" 2>/dev/null)"
  if [ -z "$line" ]; then
    echo "  ??    $name (tak ada ringkasan TOTAL= — cek file test)"; return 1
  fi
  local fail
  fail="$(echo "$line" | sed -nE 's/.*FAIL=([0-9]+).*/\1/p')"
  if [ "${fail:-1}" != "0" ]; then
    echo "  FAIL  $name"
    echo "$line" | sed 's/^/        /'
    return 1
  fi
  local total pass
  total="$(echo "$line" | sed -nE 's/.*TOTAL=([0-9]+).*/\1/p')"
  pass="$(echo "$line" | sed -nE 's/.*PASS=([0-9]+).*/\1/p')"
  echo "  ok    $name ($pass/$total assert)"; return 0
}

FAIL=0
echo "== Lapis 3: SQL tests (harness) =="
if [ "$#" -gt 0 ]; then
  files=("$TESTS_DIR/$1")
else
  files=("$TESTS_DIR"/*.sql)
fi
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  run_one "$f" || FAIL=1
done

echo
[ "$FAIL" -ne 0 ] && { echo "==> SQL tests: GAGAL"; exit 1; }
echo "==> SQL tests: semua lolos."
