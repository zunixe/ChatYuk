#!/usr/bin/env bash
# Smoke test live: alur registrasi anon persis seperti aplikasi
# (signup anon → upsert ignore-duplicates → PATCH → verifikasi profil).
# Dibuat setelah insiden anon 2026-09-22 (upsert merge-duplicates gagal 42501
# karena REVOKE SELECT — tak terdeteksi guard statis).
#
# WAJIB dijalankan setelah migrasi apa pun yang menyentuh: auth, tabel
# profiles (kolom/grant/RLS/policy/trigger), atau fungsi terkait profil.
#
# Membersihkan user test setelah selesai (pola delete_my_account:
# session_replication_role='replica' untuk ledger append-only), lalu
# verifikasi sisa = 0. Data produksi tidak tersentuh selain baris test.
#
# Pakai: scripts/smoke_anon_register.sh
#   Env opsional: SUPABASE_URL, SUPABASE_ANON_KEY (default = prod, publik),
#   SUPABASE_ACCESS_TOKEN (untuk cleanup via Management API; fallback keychain).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
URL="${SUPABASE_URL:-https://fohcucyyejdryryoxitm.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-sb_publishable_aFQQbXscy1mqVq5jHX7p2w_wzs2GAKg}"
REF="${SUPABASE_PROJECT_REF:-fohcucyyejdryryoxitm}"
if [ -n "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  TOK="$SUPABASE_ACCESS_TOKEN"
else
  TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
fi

FAIL=0
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL=1; }
ok() { printf '\033[32m  ok\033[0m %s\n' "$1"; }

NICK="smokeanon$(date +%s)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TUID=""
AT=""

mgmt() { # query SQL via Management API (superuser) → stdout JSON
  python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" "$1" > /tmp/smokeq.json
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data-binary @/tmp/smokeq.json --max-time 60
}

cleanup() { # hapus user+profil+ledger test, verifikasi sisa 0
  [ -z "$TUID" ] && return 0
  if [ -z "$TOK" ]; then
    echo "  (cleanup dilewati: token Management API tidak ada — hapus manual $TUID)"
    return 0
  fi
  mgmt "set session_replication_role='replica'; delete from public.coin_ledger where user_id='$TUID'; delete from auth.users where id='$TUID'; delete from public.profiles where id='$TUID'; reset session_replication_role;" > /dev/null
  local left
  left=$(mgmt "select (select count(*) from auth.users where id='$TUID') + (select count(*) from public.profiles where id='$TUID') as n;" | python3 -c "import json,sys; d=json.load(sys.stdin); r=d if isinstance(d,list) else d.get('rows',[]); print(r[0]['n'] if r else '?')" 2>/dev/null)
  if [ "$left" = "0" ]; then ok "cleanup: user test terhapus tuntas"; else fail "cleanup: sisa $left baris untuk $TUID"; fi
}

echo "== smoke: registrasi anon ($NICK) =="

# 1. signup anon (seperti _sb.auth.signInAnonymously)
resp=$(curl -s -X POST "$URL/auth/v1/signup" -H "apikey: $KEY" \
  -H "Content-Type: application/json" -d '{}' --max-time 30)
AT=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
TUID=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('user',{}).get('id',''))" 2>/dev/null)
if [ -z "$AT" ] || [ -z "$TUID" ]; then
  fail "signup anon gagal: $(echo "$resp" | head -c 300)"
  exit 1
fi
ok "signup anon OK ($TUID)"

# 2. upsert pola app: ignore-duplicates (TANPA return=representation,
#    persis header client Dart) — merge-duplicates di sini = 42501.
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/rest/v1/profiles" \
  -H "apikey: $KEY" -H "Authorization: Bearer $AT" \
  -H "Content-Type: application/json" \
  -H "Prefer: resolution=ignore-duplicates,return=minimal" \
  -d "{\"id\":\"$TUID\",\"nickname\":\"$NICK\",\"gender\":\"male\",\"age\":18,\"country\":\"Indonesia\",\"city\":\"Jakarta\",\"status\":\"online\",\"avatar\":\"\",\"is_registered\":false,\"login_at\":\"$NOW\",\"created_at\":\"$NOW\",\"last_seen\":\"$NOW\"}" \
  --max-time 30)
if [ "$code" = "201" ] || [ "$code" = "200" ] || [ "$code" = "204" ]; then
  ok "upsert ignore-duplicates HTTP $code"
else
  fail "upsert ignore-duplicates HTTP $code (harus 2xx)"
  cleanup
  exit 1
fi

# 3. PATCH susulan pola app (baris existing).
code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$URL/rest/v1/profiles?id=eq.$TUID" \
  -H "apikey: $KEY" -H "Authorization: Bearer $AT" \
  -H "Content-Type: application/json" \
  -d "{\"nickname\":\"$NICK\",\"status\":\"online\"}" --max-time 30)
[ "$code" = "204" ] && ok "PATCH susulan HTTP 204" || { fail "PATCH susulan HTTP $code"; }

# 4. verifikasi profil benar-benar ada (atas nama anon sendiri).
got=$(curl -s "$URL/rest/v1/profiles?id=eq.$TUID&select=nickname" \
  -H "apikey: $KEY" -H "Authorization: Bearer $AT" --max-time 30)
if echo "$got" | grep -q "$NICK"; then
  ok "profil terbaca kembali ($NICK)"
else
  fail "profil tidak terbaca: $(echo "$got" | head -c 300)"
fi

cleanup
echo
if [ "$FAIL" -ne 0 ]; then echo "==> smoke anon: GAGAL"; exit 1; fi
echo "==> smoke anon: OK bersih."
