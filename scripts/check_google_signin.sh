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
# Flavor play WAJIB memakai project Firebase AKTIF yang sama (7c9e4) —
# project lama chatyuk-8470e sudah tidak dipakai; pernah bikin Sign-In Play
# gagal karena AAB ber-google_app_id 8470e.
PLAY_GS="android/app/src/play/google-services.json"
WEB_CLIENT="599111437536-hg56bq0nc2m6kig6hg41lmrbtfel5n2c"
PKG="com.chatyuk.chatyuk"
EXPECTED_PROJECT="chatyuk-7c9e4"
# SHA Play App Signing (Google re-sign) — beda dari keystore upload kita.
# Harus terdaftar di GCP 7c9e4 utk paket user, kalau tidak Sign-In di build
# Play gagal walau build apkpure (upload key) jalan.
PLAY_SIGN_SHA1="7A:19:AF:A5:22:11:E9:AA:61:F5:8E:16:54:28:04:E8:32:EE:3C:B1"

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

python3 - "$GS" "$PLAY_GS" "$PKG" "$WEB_CLIENT" "$EXPECTED_PROJECT" <<'PY' || fail=1
import json, sys
gs, play_gs, pkg, web, expected_project = sys.argv[1:6]
ok = True

def check(path, label, must_project=True):
    global ok
    try:
        d = json.load(open(path))
    except Exception as e:
        print(f"GAGAL: {path} tidak bisa dibaca: {e}"); ok = False; return
    pkgs = {
        c.get('client_info', {}).get('android_client_info', {}).get('package_name')
        for c in d.get('client', [])
    }
    oauths = {
        o.get('client_id', '')
        for c in d.get('client', [])
        for o in c.get('oauth_client', [])
    }
    proj = d.get('project_info', {}).get('project_id')
    if must_project and proj != expected_project:
        print(f"GAGAL: {label} memakai project '{proj}' != '{expected_project}' "
              f"(project lama = Sign-In gagal)"); ok = False
    if pkg not in pkgs:
        print(f"GAGAL: {label} tidak memuat paket {pkg}"); ok = False
    if not any(x.startswith(web) for x in oauths):
        print(f"GAGAL: {label} tidak memuat Web client {web[:24]}...(serverClientId)"); ok = False
    if proj == expected_project and pkg in pkgs:
        print(f"OK  : {label} project {proj} + paket + Web client cocok")

check(gs, "main/google-services.json")
check(play_gs, "play/google-services.json")
sys.exit(0 if ok else 1)
PY

dart_line=$(grep -A1 "googleWebClientIdDefault =" lib/services/auth_service.dart | grep -c "$WEB_CLIENT" || true)
if [ "${dart_line}" -eq 0 ]; then
  echo "GAGAL: serverClientId di lib/services/auth_service.dart != Web client gs.json"
  fail=1
else
  echo "OK  : serverClientId kode == Web client gs.json"
fi

# Ingatkan (tidak menggagalkan): SHA Play App Signing harus terdaftar juga.
echo ""
echo "CATATAN (manual, tidak dicek otomatis):"
echo "  Build Play ditandatangani ULANG Google (Play App Signing). SHA-nya:"
echo "    SHA-1  : $PLAY_SIGN_SHA1"
echo "    SHA-256: 9778574b360e91f03c7e53b4a14dfdf4112d3b9a6c0b07d69886da60ac0d56ce"
echo "  WAJIB terdaftar di Firebase Console project chatyuk-7c9e4 →"
echo "  Android app com.chatyuk.chatyuk → SHA certificate hashes."
echo "  Verifikasi SHA APK Play dari HP:"
echo "    apksigner verify --print-certs <base.apk-terinstall-dari-Play> | grep SHA-1"

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "== HASIL: GAGAL — perbaiki sebelum build rilis."
  echo "   Panduan remote: AGENTS.md → Fitur Khusus → Google Sign-In"
  exit 1
fi
echo ""
echo "== HASIL: SEMUA COCOK — aman untuk build rilis."
