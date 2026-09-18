#!/usr/bin/env bash
# Benchmark RPC via HTTP dengan sesi user asli (RLS ikut teruji).
# Pakai: scripts/stress/bench_rpc.sh [iterasi]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
REF="${REF:-fohcucyyejdryryoxitm}"
URL="https://fohcucyyejdryryoxitm.supabase.co"
IT="${1:-20}"

KEY="$(cat /tmp/stress/svc.key 2>/dev/null)"
[ -z "$KEY" ] && {
  KEY=$(curl -s "https://api.supabase.com/v1/projects/$REF/api-keys?reveal=true" -H "Authorization: Bearer $TOK" --max-time 30 | python3 -c "
import json,sys
for k in json.load(sys.stdin):
  if k.get('name')=='service_role': print(k.get('api_key','')); break")
  echo "$KEY" > /tmp/stress/svc.key
}

JWT=$(curl -s -X POST "$URL/auth/v1/token?grant_type=password" \
  -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"stress_0001@stress.local","password":"StressTest123!"}' --max-time 30 \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))")
[ -z "$JWT" ] && { echo "login gagal"; exit 1; }

bench() {
  local name="$1" body="$2"
  python3 - "$URL" "$KEY" "$JWT" "$name" "$body" "$IT" <<'PY'
import json,sys,time,urllib.request
url,key,jwt,name,body,it=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5],int(sys.argv[6])
ts=[]
for _ in range(it):
    req=urllib.request.Request(f"{url}/rest/v1/rpc/{name}",data=body.encode(),
        headers={"apikey":key,"Authorization":f"Bearer {jwt}","Content-Type":"application/json"})
    t=time.perf_counter()
    try:
        urllib.request.urlopen(req,timeout=30).read()
    except Exception as e:
        ts.append(-1); continue
    ts.append((time.perf_counter()-t)*1000)
ok=[x for x in ts if x>=0]
if not ok:
    print(f"{name:26} GAGAL"); sys.exit()
ok.sort()
print(f"{name:26} n={len(ok):<3} mean={sum(ok)/len(ok):7.1f}  p50={ok[len(ok)//2]:7.1f}  p95={ok[int(len(ok)*0.95)-1 if len(ok)>1 else 0]:7.1f}  max={ok[-1]:7.1f} ms")
PY
}

echo "=== RPC benchmark via HTTP (RLS aktif, user stress_0001) ==="
bench story_tray '{}'
bench get_online_users '{"p_limit":100}'
bench list_posts '{"p_scope":"all","p_limit":30}'
bench list_posts_following '{"p_scope":"following","p_limit":30}'
bench timeline_pricing '{}'
