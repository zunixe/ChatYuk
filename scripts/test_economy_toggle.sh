#!/usr/bin/env bash
# Matriks E2E flag points_enabled — AMAN untuk dijalankan kapan saja.
#
# Baterai uji berjalan dalam SATU transaksi (BEGIN ... ROLLBACK):
#   - window flag OFF hanya ~milidetik — tak perlu maintenance window,
#   - semua tulisan (ledger, antrean, flag) ikut rollback,
#   - kalau error lolos ke luar → transaksi batal → flag kembali ON sendiri.
# Ditambah trap keluar: script putus di tengah → flag dipaksa ON.
#
# Pakai:  bash scripts/test_economy_toggle.sh
#         SUPABASE_ACCESS_TOKEN=... bash scripts/test_economy_toggle.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REF="${SUPABASE_PROJECT_REF:-fohcucyyejdryryoxitm}"
FN=_econ_toggle_matrix

if [ -n "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  TOK="$SUPABASE_ACCESS_TOKEN"
else
  TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
fi
[ -z "$TOK" ] && { echo "❌ token Management API tidak ada (env SUPABASE_ACCESS_TOKEN / keychain)" >&2; exit 1; }

sql() { # sql "<query>" → JSON response
  python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" "$1" > /tmp/econ_q.json
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data-binary @/tmp/econ_q.json --max-time 90
}

restore_flag() {
  sql "drop function if exists public.$FN(); update public.app_settings set points_enabled = true where id = 'global';" >/dev/null 2>&1 || true
}
trap restore_flag EXIT INT TERM

echo "== Pre-check: flag harus ON sebelum mulai =="
resp="$(sql "select points_enabled::text as v from public.app_settings where id='global';")"
echo "$resp" | grep -q '"v": *"\?true"' || { echo "❌ points_enabled tidak true — mungkin ada sesi uji lain. Abort."; exit 1; }
echo "   ok (points_enabled = true)"

echo "== Siapkan fungsi uji sementara (service_role only) =="
resp="$(sql "
create or replace function public.$FN()
  returns table(check_name text, passed boolean, detail text)
  language plpgsql security definer set search_path = public as \$f\$
declare
  m0   uuid; m1 uuid; f1 uuid;
  bal0 int;  r jsonb;  p record;
begin
  -- hanya akun dummy (aturan repo: dilarang menyentuh akun asli)
  select da.uid into m0 from dummy_accounts da join profiles p2 on p2.id = da.uid
    where p2.gender = 'male' and p2.points = 0 limit 1;
  select da.uid into m1 from dummy_accounts da join profiles p2 on p2.id = da.uid
    where p2.gender = 'male' and p2.points > 2 limit 1;
  select da.uid into f1 from dummy_accounts da join profiles p2 on p2.id = da.uid
    where p2.gender = 'female' limit 1;
  if m0 is null or m1 is null or f1 is null then
    raise exception 'dummy accounts tidak lengkap';
  end if;
  perform set_config('request.jwt.claim.sub', m1::text, true);
  select points into bal0 from profiles where id = m1;

  update public.app_settings set points_enabled = false where id = 'global';

  begin -- 1. free-pass: spend menolak tagih saat OFF
    r := public.spend_yukcoin(m1, 'match_search', 2, 'econ-toggle', '{}'::jsonb);
    check_name := 'spend_yukcoin free-pass';
    passed := coalesce((r->>'free')::boolean,false) and (r->>'charged')::int = 0
              and (select points from profiles where id=m1) = bal0;
    detail := r::text; return next;
  exception when others then
    check_name := 'spend_yukcoin free-pass'; passed := false;
    detail := 'raise: '||sqlerrm; return next;
  end;

  begin -- 2. free-pass: metered call tak menagih saat OFF
    r := public.charge_metered(m1, 'call_video', 'econ-toggle');
    check_name := 'charge_metered free-pass';
    passed := coalesce((r->>'charged')::int,-1) = 0;
    detail := r::text; return next;
  exception when others then
    check_name := 'charge_metered free-pass'; passed := false; detail := sqlerrm; return next;
  end;

  begin -- 3. block: gift ditolak saat OFF
    select * into p from public.send_gift('[TEST]-toggle', m0, 'rose');
    check_name := 'send_gift block'; passed := false; detail := 'tidak raise'; return next;
  exception when others then
    check_name := 'send_gift block'; passed := position('disabled' in sqlerrm) > 0;
    detail := sqlerrm; return next;
  end;

  begin -- 4. no-credit: klaim misi ditolak saat OFF
    r := public.claim_mission_reward(m1, 'daily_login');
    check_name := 'claim_mission_reward no-credit';
    passed := coalesce(r->>'error','') = 'POINTS_DISABLED'; detail := r::text; return next;
  exception when others then
    check_name := 'claim_mission_reward no-credit';
    passed := position('POINTS_DISABLED' in sqlerrm) > 0; detail := sqlerrm; return next;
  end;

  begin -- 5. block: withdraw ditolak saat OFF
    perform set_config('request.jwt.claim.sub', f1::text, true);
    r := public.request_withdraw(200000, '081234567890', '[TEST] Dana');
    check_name := 'request_withdraw block';
    passed := coalesce((r->>'ok')::boolean,true) = false
              and coalesce(r->>'error','') = 'POINTS_DISABLED';
    detail := r::text;
    perform set_config('request.jwt.claim.sub', m1::text, true); return next;
  exception when others then
    check_name := 'request_withdraw block';
    passed := position('POINTS_DISABLED' in sqlerrm) > 0; detail := sqlerrm;
    perform set_config('request.jwt.claim.sub', m1::text, true); return next;
  end;

  begin -- 6. no-credit: welcome bonus ditahan saat OFF
    r := public.credit_welcome_bonus(m0, 'install-toggle', 'register', '127.0.0.1');
    check_name := 'credit_welcome_bonus no-credit';
    passed := coalesce((r->>'granted')::boolean,true) = false;
    detail := r::text; return next;
  exception when others then
    check_name := 'credit_welcome_bonus no-credit'; passed := false; detail := sqlerrm; return next;
  end;

  update public.app_settings set points_enabled = true where id = 'global';

  begin -- 7. jalur bayar hidup lagi: male saldo 0 ditolak saat ON
    perform set_config('request.jwt.claim.sub', m0::text, true);
    r := public.spend_yukcoin(m0, 'match_search', 2, 'econ-toggle', '{}'::jsonb);
    check_name := 'charge path aktif (ON)'; passed := false;
    detail := 'saldo 0 lolos: '||r::text;
    perform set_config('request.jwt.claim.sub', m1::text, true); return next;
  exception when others then
    check_name := 'charge path aktif (ON)';
    passed := position('tidak cukup' in sqlerrm) > 0; detail := sqlerrm;
    perform set_config('request.jwt.claim.sub', m1::text, true); return next;
  end;
end \$f\$;
revoke all on function public.$FN() from anon, authenticated;
grant execute on function public.$FN() to service_role;")"
echo "$resp" | grep -qiE '"message".*(error|ERROR)' && {
  echo "❌ gagal membuat fungsi uji:"; echo "$resp" | head -c 600; exit 1; }

echo "== Jalankan matriks (satu transaksi, auto-rollback) =="
resp="$(sql "select * from public.$FN();")"
sql "drop function if exists public.$FN();" >/dev/null 2>&1

echo "$resp" | python3 -c "
import json,sys
try: data = json.load(sys.stdin)
except Exception:
    print('  (resp non-JSON)'); print(open('/tmp/econ_q.json').read()[:200]); sys.exit(2)
rows = [r for r in data if isinstance(r,dict) and 'check_name' in r]
fails = 0
for r in rows:
    mark = 'PASS' if r['passed'] else 'FAIL'
    if not r['passed']: fails += 1
    print(f\"  {mark}  {r['check_name']:<34} {str(r['detail'])[:80]}\")
print(f'  {len(rows)-fails}/{len(rows)} lolos')
sys.exit(1 if fails else 0)
"
rc=$?

# Verifikasi final: flag persisten ON di luar transaksi.
final="$(sql "select points_enabled::text as v from public.app_settings where id='global';")"
if echo "$final" | grep -q '"v": *"\?true"'; then
  echo "== points_enabled = true (live, diverifikasi di luar transaksi) =="
else
  echo "❌ FLAG TIDAK ON — restore_flag sudah dijalankan oleh trap"
fi
exit $rc
