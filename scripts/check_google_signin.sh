#!/bin/bash
# Cek pra-rilis: konfigurasi Google Sign-In lokal harus cocok dengan yang
# terdaftar di Firebase/GCP (project chatyuk-7c9e4).
#
# Yang dicek (sisi lokal):
#   1. SHA-1 keystore aktif == SHA-1 yang terdaftar di GCP client
#      "ChatYuk User Android" (konstanta di bawah).
#   2. google-services.json memuat paket com.chatyuk.chatyuk + Web client hg56
#      (serverClientId di auth_service.dart).
# Sisi remote (client GCP/Firebase) dicek manual via AGENTS.md bila gagal.
#
# Pakai: ./scripts/check_google_signin.sh  → exit 0 = OK, exit 1 = GAGAL

set -euo pipefail
cd "$(dirname "$0")/.."

EXPECTED_SHA="8C:CC:42:E3:FE:93:37:21:6C:E4:25:0E:2B:FC:CB:22:94:1E:50:A2"
KEYSTORE="android/keystore/chatyuk-release-v2.jks"
ALIAS="chatyuk"
PASS="chatyuk2024secure"
GS="android/app/google-services.json"
WEB_CLIENT="599111437536-hg56bq0nc2m6kig6hg41lmrbtfel5n2c"
PKG="com.chatyuk.chatyuk"

fail=0

sha=$(keytool -list -v -keystore "$KEYSTORE" -alias "$ALIAS" -storepass "$PASS" \
  2>/dev/null | grep -m1 'SHA1:' | sed 's/.*SHA1: //; s/,.*//' | tr -d ' ')
if [ "$sha" != "$EXPECTED_SHA" ]; then
  echo "GAGAL: SHA-1 keystore ($sha) != SHA terdaftar di GCP ($EXPECTED_SHA)"
  echo "       → JANGAN rilis build ini. Daftarkan SHA baru dulu atau perbaiki keystore."
  fail=1
else
  echo "OK  : SHA-1 keystore cocok dengan client GCP"
fi

python3 - "$GS" "$PKG" "$WEB_CLIENT" <<'PY' || fail=1
import json, sys
gs, pkg, web = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(gs))
pkgs = {
    c.get('client_info', {}).get('android_client_info', {}).get('package_name')
    for c in d.get('client', [])
}
oauths = {
    o.get('client_id', '')
    for c in d.get('client', [])
    for o in c.get('oauth_client', [])
}
ok = True
if pkg not in pkgs:
    print(f"GAGAL: {gs} tidak memuat paket {pkg}"); ok = False
if not any(x.startswith(web) for x in oauths):
    print(f"GAGAL: {gs} tidak memuat Web client {web[:24]}...(serverClientId)"); ok = False
if ok:
    print("OK  : google-services.json paket + Web client cocok", end="")
sys.exit(0 if ok else 1)
PY

dart_line=$(grep -A1 "googleWebClientIdDefault =" lib/services/auth_service.dart | grep -c "$WEB_CLIENT" || true)
if [ "${dart_line}" -eq 0 ]; then
  echo "GAGAL: serverClientId di lib/services/auth_service.dart != Web client gs.json"
  fail=1
else
  echo "OK  : serverClientId kode == Web client gs.json"
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "== HASIL: GAGAL — perbaiki sebelum build rilis."
  echo "   Panduan remote: AGENTS.md → Fitur Khusus → Google Sign-In"
  exit 1
fi
echo ""
echo "== HASIL: SEMUA COCOK — aman untuk build rilis."
