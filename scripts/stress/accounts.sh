#!/usr/bin/env bash
# Kelola akun sintetis untuk stress test.
#   scripts/stress/accounts.sh create <N>   — buat N akun stress_*
#   scripts/stress/accounts.sh list         — tampilkan akun yang ada
#   scripts/stress/accounts.sh purge        — hapus SEMUA akun stress_* + data terkait
#
# Akun dibuat via Admin API (service role) supaya bisa login & dites RLS-nya.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
REF="${REF:-fohcucyyejdryryoxitm}"
SUPA_URL="https://fohcucyyejdryryoxitm.supabase.co"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
[ -z "$TOK" ] && { echo "token tidak ada" >&2; exit 1; }

# Service role key dari Management API (secrets) — dipakai untuk Admin API.
mgt() {
  python3 -c "import json,sys;print(json.dumps({'query':sys.argv[1]}))" "$1" > /tmp/stress/_aq.json
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    --data-binary @/tmp/stress/_aq.json --max-time 60
}

get_service_key() {
  curl -s "https://api.supabase.com/v1/projects/$REF/api-keys?reveal=true" \
    -H "Authorization: Bearer $TOK" --max-time 30 \
  | python3 -c "
import json,sys
try:
  d=json.load(sys.stdin)
except Exception:
  print(''); sys.exit()
for k in d if isinstance(d,list) else []:
  if k.get('name')=='service_role': print(k.get('api_key','')); break
"
}

CMD="${1:-list}"
N="${2:-100}"

case "$CMD" in
  create)
    KEY="$(get_service_key)"
    [ -z "$KEY" ] && { echo "service key tidak didapat"; exit 1; }
    echo "membuat $N akun stress_* ..."
    python3 - "$SUPA_URL" "$KEY" "$N" <<'PY'
import json,sys,urllib.request,time
url,key,n=sys.argv[1],sys.argv[2],int(sys.argv[3])
ok=0; ids=[]
for i in range(1,n+1):
    email=f"stress_{i:04d}@stress.local"
    body=json.dumps({"email":email,"password":"StressTest123!","email_confirm":True}).encode()
    req=urllib.request.Request(f"{url}/auth/v1/admin/users",data=body,
        headers={"apikey":key,"Authorization":f"Bearer {key}","Content-Type":"application/json"})
    try:
        r=json.load(urllib.request.urlopen(req,timeout=20))
        ids.append(r.get("id")); ok+=1
    except Exception as e:
        try:
            r=json.load(e)
            if r.get("id"): ids.append(r["id"]); ok+=1
        except Exception:
            have = "already" in str(e).lower()
            if not have: print("  gagal", email, str(e)[:80])
    if i%25==0: print(f"  ...{i}/{n}",flush=True)
print(f"selesai: {ok} akun")
open("/tmp/stress/account_ids.txt","w").write("\n".join([x for x in ids if x]))
print("id tersimpan -> /tmp/stress/account_ids.txt")
PY
    ;;
  list)
    mgt "select count(*) as stress_users from auth.users where email like 'stress\\_%';"
    ;;
  purge)
    echo "menghapus akun stress_* + data terkait ..."
    mgt "
      with u as (select id from auth.users where email like 'stress\\_%')
      select count(*) as akan_dihapus from u;
    "
    mgt "
      delete from public.private_messages pm
       using public.private_chats pc
       where pm.chat_id = pc.chat_id
         and (pc.chat_id like '%'||(select string_agg(id::text,'|') from auth.users where email like 'stress\\_%')||'%'
              or pc.participants && array(select id from auth.users where email like 'stress\\_%'));
      delete from public.private_chats
       where participants && array(select id from auth.users where email like 'stress\\_%');
      delete from auth.users where email like 'stress\\_%';
    "
    mgt "select (select count(*) from auth.users where email like 'stress\\_%') as sisa_stress, (select count(*) from auth.users) as total_users;"
    ;;
  *) echo "pakai: create <N> | list | purge";;
esac
