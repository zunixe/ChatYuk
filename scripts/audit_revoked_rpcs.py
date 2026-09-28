#!/usr/bin/env python3
"""Audit: fungsi yang DIPANGGIL app tapi role authenticated TIDAK boleh EXECUTE.

Latar insiden 2026-09-28: hardening REVOKE memakai deteksi grep SATU BARIS
(`grep "_rpc('x'"`) → MELEWATKAN pemanggilan multi-baris:
    await _rpc(
      'admin_registrations_daily', params: {...});
Akibatnya 6 fungsi admin dicabut padahal dipakai → 42501 di produksi.

PENDEKATAN BENAR (authoritative): jangan menebak dari file migrasi (banyak
`revoke ... from public` historis yang tidak memengaruhi `authenticated`).
Tanyakan LANGSUNG ke DB: untuk tiap fungsi yang dipanggil app, apakah
`has_function_privilege('authenticated', fn, 'EXECUTE')`?

Pakai:
  SUPABASE_ACCESS_TOKEN=... python3 scripts/audit_revoked_rpcs.py
Exit 1 kalau ada yang bocor (bisa dipakai di CI).

Fungsi yang MEMANG boleh tidak-EXECUTE-able (sengaja internal/trigger) taruh
di ALLOWLIST di bawah — beri alasan.
"""
import glob
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.environ.get("SUPABASE_PROJECT_REF", "fohcucyyejdryryoxitm")

# Fungsi internal/trigger yang SENGAJA tidak boleh dipanggil authenticated
# (mis. trigger-only). WAJIB ada alasan.
ALLOWLIST = {
    # contoh: 'handle_new_private_message',  # trigger only
}


def called_functions():
    """Nama fungsi yang dipanggil dari lib/ (regex multi-baris)."""
    names = set()
    for f in glob.glob(os.path.join(ROOT, "lib/**/*.dart"), recursive=True):
        s = open(f, encoding="utf-8", errors="ignore").read()
        for pat in (
            r"_rpc\(\s*'([a-z_][a-z0-9_]*)'",
            r"measuredRpc\(\s*[^,]+,\s*'([a-z_][a-z0-9_]*)'",
            r"\.rpc\(\s*'([a-z_][a-z0-9_]*)'",
        ):
            for m in re.finditer(pat, s):
                names.add(m.group(1))
    return names


def live_query(token, sql):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": sql}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read())


def main():
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        print("SUPABASE_ACCESS_TOKEN tidak diset — lewati (butuh akses live).")
        return 0
    called = sorted(called_functions())
    names_sql = ",".join("'" + c.replace("'", "''") + "'" for c in called)
    sql = (
        "select p.proname, "
        "bool_or(has_function_privilege('authenticated', p.oid,'EXECUTE')) auth_ok "
        f"from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
        f"where n.nspname='public' and p.proname in ({names_sql}) group by p.proname"
    )
    rows = live_query(token, sql)
    ok = {r["proname"] for r in rows if r["auth_ok"]}
    missing = [
        r["proname"] for r in rows
        if not r["auth_ok"] and r["proname"] not in ALLOWLIST
    ]
    print(f"fungsi dipanggil app        : {len(called)}")
    print(f"ada di DB & auth boleh EXEC : {len(ok)}")
    if not missing:
        print("OK: semua fungsi yang dipanggil app bisa di-EXECUTE authenticated.")
        return 0
    print(f"\nBAHAYA ({len(missing)}) — dipanggil app tapi authenticated DITOLAK:")
    for m in sorted(missing):
        print(f"  - {m}")
    print(
        "\nPerbaiki: tambah `grant execute on function public.<fn>(<args>) "
        "to authenticated;` (kalau fungsi punya guard admin internal) ATAU "
        "hapus pemanggilnya dari lib/."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
