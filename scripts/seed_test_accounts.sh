#!/usr/bin/env bash
# Seed akun test + aktifkan fitur YukCoin v2 untuk pengujian di ChatYuk Dev
# (Supabase LOCAL). Idempoten — aman dijalankan berulang.
#
# Kenapa perlu: `supabase db reset` menghapus semua user & data lokal, dan
# `app_settings.yukcoin_v2_enabled` kembali default OFF. Skrip ini mengembalikan
# kondisi siap-uji dalam satu perintah.
#
# Yang dilakukan:
#   1. Pastikan Supabase local jalan (kalau belum → `supabase start`).
#   2. Buat 2 akun email+password (langsung terkonfirmasi di local).
#   3. Buat profil + saldo YukCoin besar (bonus 500 + earned 500) utk uji berbayar.
#   4. Nyalakan flag app_settings.yukcoin_v2_enabled = true.
#   5. Jalankan fix overload lokal-only (get_online_users) agar daftar online jalan.
#
# Pakai:   bash scripts/seed_test_accounts.sh
# Setelah: login di ChatYuk Dev pakai email/password di bawah.
#
# CATATAN: hanya menyentuh DB LOCAL (127.0.0.1:54321). TIDAK menyentuh prod.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DB_CONTAINER="supabase_db_ChatYuk"
LOCAL_API="http://127.0.0.1:54321"

# ── Akun test (ubah di sini bila perlu) ──
ACC1_EMAIL="test@chatyuk.dev";  ACC1_PASS="test1234";   ACC1_NICK="tester1"
ACC2_EMAIL="dev@chatyuk.dev";   ACC2_PASS="chatyuk123"; ACC2_NICK="tester2"
SEED_BONUS=500
SEED_EARNED=500

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── 1. Pastikan Supabase local jalan ──
if ! curl -s -o /dev/null --max-time 3 "$LOCAL_API/rest/v1/"; then
  say ">> Supabase local belum jalan — menjalankan supabase start..."
  (cd supabase && supabase start) || die "gagal supabase start"
fi

# ── 2. Ambil anon key local ──
ANON_KEY="$(cd supabase && supabase status -o env 2>/dev/null | grep '^ANON_KEY=' | cut -d'"' -f2)"
[ -z "$ANON_KEY" ] && die "gagal baca ANON_KEY dari 'supabase status'"
say ">> anon key local: ${ANON_KEY:0:12}..."

is_local_db() {
  docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"
}
is_local_db || die "container $DB_CONTAINER tidak jalan (jalankan: supabase start)"

psql_local() { docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1; }

# ── 3. Buat akun via Auth API (idempoten: abaikan bila sudah ada) ──
create_user() {
  local email="$1" pass="$2" nick="$3"
  local resp uid
  resp="$(curl -s -X POST "$LOCAL_API/auth/v1/signup" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
    --data "{\"email\":\"$email\",\"password\":\"$pass\"}" --max-time 20)"
  uid="$(printf '%s' "$resp" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('user',{}).get('id') or '')" 2>/dev/null)"
  if [ -z "$uid" ]; then
    # Sudah ada → ambil uid dari DB (buang header/spasi; hanya pola uuid valid).
    uid="$(printf 'select id from auth.users where email=%s;\n' "'$email'" | \
      psql_local -t -A 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)"
  fi
  [ -z "$uid" ] && die "gagal membuat/menemukan user $email"
  printf '%s' "$uid"
}

say ">> membuat/memastikan akun test..."
U1="$(create_user "$ACC1_EMAIL" "$ACC1_PASS" "$ACC1_NICK")"
U2="$(create_user "$ACC2_EMAIL" "$ACC2_PASS" "$ACC2_NICK")"
say "   $ACC1_EMAIL → $U1"
say "   $ACC2_EMAIL → $U2"

# ── 4. Profil + saldo + flag v2 (via SQL, idempoten) ──
say ">> membuat profil + saldo YukCoin + menyalakan flag v2..."
psql_local <<SQL
do \$\$
declare
  u1 uuid := '$U1';
  u2 uuid := '$U2';
  cnt int;
begin
  update app_settings set yukcoin_v2_enabled = true where id = 'global';

  if not exists (select 1 from public.profiles where id = u1) then
    insert into public.profiles(id, nickname) values (u1, '$ACC1_NICK');
  end if;
  if not exists (select 1 from public.profiles where id = u2) then
    insert into public.profiles(id, nickname) values (u2, '$ACC2_NICK');
  end if;

  -- Beri saldo sekali per user (via ledger; trigger menjaga profiles.points).
  select count(*) into cnt from public.coin_ledger
   where user_id = u1 and metadata->>'reason' = 'seed_test';
  if cnt = 0 then
    insert into public.coin_ledger(user_id,bucket,type,amount,metadata) values
      (u1,'bonus','seed_test',$SEED_BONUS, '{"reason":"seed_test"}'),
      (u1,'earned','seed_test',$SEED_EARNED,'{"reason":"seed_test"}'),
      (u2,'bonus','seed_test',$SEED_BONUS, '{"reason":"seed_test"}'),
      (u2,'earned','seed_test',$SEED_EARNED,'{"reason":"seed_test"}');
  end if;

  raise notice 'tester1 points = %', (select points from public.profiles where id = u1);
  raise notice 'tester2 points = %', (select points from public.profiles where id = u2);
  raise notice 'yukcoin_v2_enabled = %',
    (select yukcoin_v2_enabled from public.app_settings where id = 'global');
end \$\$;
SQL

# ── 5. Fix overload lokal-only (get_online_users) ──
if [ -f "$ROOT/supabase/local_only_fix_overloads.sql" ]; then
  say ">> menerapkan fix overload lokal-only..."
  psql_local < "$ROOT/supabase/local_only_fix_overloads.sql" || true
fi

# ── Ringkasan ──
# Baca saldo via docker exec TANPA stdin (hindari tabrakan heredoc sebelumnya).
P1="$(docker exec "$DB_CONTAINER" psql -U postgres -d postgres -t -A -c \
  "select points from public.profiles where id='$U1';" 2>/dev/null | head -1 | tr -d '[:space:]')"
P2="$(docker exec "$DB_CONTAINER" psql -U postgres -d postgres -t -A -c \
  "select points from public.profiles where id='$U2';" 2>/dev/null | head -1 | tr -d '[:space:]')"
cat <<TXT

=====================================================
  AKUN TEST CHATYUK DEV (Supabase LOCAL) — SIAP
=====================================================
  Email                  Password       YukCoin
  ---------------------  -------------  ---------
  $ACC1_EMAIL   $ACC1_PASS    ${P1:-?}
  $ACC2_EMAIL    $ACC2_PASS   ${P2:-?}

  Fitur YukCoin v2: ON
  Jalankan app:  bash tool/run_dev.sh
=====================================================
TXT
