#!/bin/bash
# Buat/perbaiki android/app/src/play/google-services.json dari project
# Firebase AKTIF (chatyuk-7c9e4).
#
# LATAR: file ini di-gitignore, jadi tiap clone/sesi baru harus dibuat ulang.
# Pernah salah pakai project LAMA chatyuk-8470e → Google Sign-In di build Play
# GAGAL (AAB ber-google_app_id 990163663226 padahal kode pakai Web client 7c9e4).
#
# Sumber: android/app/google-services.json (project aktif). Untuk flavor play
# kita HANYA butuh client paket `com.chatyuk.chatyuk` (appId sama).
#
# Pakai: bash scripts/setup_play_google_services.sh
#        bash scripts/setup_play_google_services.sh --check   (hanya verifikasi)

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="android/app/google-services.json"
DST="android/app/src/play/google-services.json"
EXPECTED="chatyuk-7c9e4"
PKG="com.chatyuk.chatyuk"

if [ "${1:-}" = "--check" ]; then
  if [ -f "$DST" ] && grep -q "\"$EXPECTED\"" "$DST"; then
    echo "OK  : $DST sudah project $EXPECTED"
    exit 0
  fi
  echo "GAGAL: $DST tidak ada / bukan project $EXPECTED" >&2
  echo "       Perbaiki: bash scripts/setup_play_google_services.sh" >&2
  exit 1
fi

if [ ! -f "$SRC" ]; then
  echo "GAGAL: $SRC tidak ada. Ambil dari Firebase Console (project $EXPECTED)." >&2
  exit 1
fi

python3 - "$SRC" "$DST" "$PKG" "$EXPECTED" <<'PY'
import json, sys
src, dst, pkg, expected = sys.argv[1:5]
d = json.load(open(src))
proj = d.get('project_info', {}).get('project_id')
if proj != expected:
    print(f"GAGAL: {src} memakai project '{proj}' != '{expected}'.", file=sys.stderr)
    print("       Ambil dari Firebase Console project yang benar.", file=sys.stderr)
    sys.exit(1)
clients = [c for c in d.get('client', [])
           if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == pkg]
if not clients:
    print(f"GAGAL: {src} tidak memuat paket {pkg}.", file=sys.stderr)
    sys.exit(1)
out = {'project_info': d['project_info'],
       'client': clients,
       'configuration_version': d.get('configuration_version', '1')}
with open(dst, 'w') as f:
    json.dump(out, f, indent=2)
print(f"OK  : {dst} dibuat (project {expected}, paket {pkg})")
PY

echo "Verifikasi: bash scripts/check_google_signin.sh"
