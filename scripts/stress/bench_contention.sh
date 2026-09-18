#!/usr/bin/env bash
# Test KONTENSI: N operasi tulis bersamaan → cari lock wait / deadlock / gagal.
# Fokus: kirim pesan (trigger update baris chat yang sama) + poin (lock saldo).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

TOK="$(security find-generic-password -s "Supabase CLI" -a "supabase" -w 2>/dev/null | sed 's/^go-keyring-base64://' | base64 -d 2>/dev/null || true)"
REF="${REF:-fohcucyyejdryryoxitm}"
URL="https://fohcucyyejdryryoxitm.supabase.co"
CONC="${1:-20}"

echo "=== KONTENSI: $CONC insert pesan paralel ke 1 chat ==="
python3 - "$REF" "$TOK" "$URL" "$CONC" <<'PY'
import json,sys,time,urllib.request,urllib.error,concurrent.futures
ref,tok,url,conc=sys.argv[1],sys.argv[2],sys.argv[3],int(sys.argv[4])

def q(sql):
    req=urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({'query':sql}).encode(),
        headers={"Authorization":f"Bearer {tok}","Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=60))

key=open('/tmp/stress/svc.key').read().strip()
ids=open('/tmp/stress/account_ids.txt').read().split()
u1,u2=ids[0],ids[1]
chat=f"{min(u1,u2)}_{max(u1,u2)}"

# Pastikan chat ada
q(f"""insert into public.private_chats (chat_id, participants, participant_names)
values ('{chat}', array['{u1}','{u2}']::uuid[], '{{}}'::jsonb)
on conflict (chat_id) do nothing;""")

def send(i):
    body=json.dumps({"chat_id":chat,"sender_id":u1,"sender_name":"stress","sender_gender":"other",
                     "text":f"stress msg {i}","type":"text"}).encode()
    req=urllib.request.Request(f"{url}/rest/v1/private_messages",data=body,
        headers={"apikey":key,"Authorization":f"Bearer {key}","Content-Type":"application/json","Prefer":"return=minimal"})
    t=time.perf_counter()
    try:
        urllib.request.urlopen(req,timeout=30); return (time.perf_counter()-t)*1000, None
    except Exception as e:
        return (time.perf_counter()-t)*1000, str(e)[:100]

t0=time.perf_counter()
with concurrent.futures.ThreadPoolExecutor(max_workers=conc) as ex:
    res=list(ex.map(send, range(conc*5)))
wall=(time.perf_counter()-t0)*1000
lat=sorted(r[0] for r in res)
errs=[r[1] for r in res if r[1]]
print(f"  total={len(res)} wall={wall:.0f}ms throughput={len(res)/(wall/1000):.1f}/s")
print(f"  p50={lat[len(lat)//2]:.0f}ms p95={lat[int(len(lat)*0.95)]:.0f}ms max={lat[-1]:.0f}ms")
print(f"  error={len(errs)}" + (f" contoh: {errs[0]}" if errs else ""))

# Cek konsistensi: message_count vs jumlah pesan nyata
r=q(f"select message_count, (select count(*) from public.private_messages where chat_id='{chat}') as real_msgs from public.private_chats where chat_id='{chat}';")
print(f"  konsistensi: {r[0]}")
PY
