#!/bin/zsh
# ============================================================
# GERBANG PRA-UPLOAD — cek APK rilis TIDAK memuat kode/string admin.
# Jalankan SEBELUM upload ke APKPure / Uptodown / Google Play:
#
#   ./scripts/check_release_apk.sh build/app/outputs/flutter-apk/app-apkpure-release.apk
# ============================================================
APK="${1:-build/app/outputs/flutter-apk/app-apkpure-release.apk}"

if [ ! -f "$APK" ]; then
  echo "DITOLAK: file tidak ditemukan: $APK"
  exit 1
fi

PATTERNS='admin_get_dummy_token|admin_renew_dummy_token|admin_stats_detail|Peta User|Chat Sebagai|dummy_token_missing|dummySwapFailed'

HITS=$(unzip -p "$APK" 'lib/arm64-v8a/libapp.so' 2>/dev/null | strings | grep -ciE "$PATTERNS")

if [ "${HITS:-0}" != "0" ]; then
  echo "DITOLAK: $HITS string admin ditemukan di $APK"
  echo "Kemungkinan build TANPA entry user yang benar."
  echo "Rilis WAJIB: flutter build apk --release --flavor apkpure (entry default lib/main.dart)"
  exit 1
fi

echo "OK bersih dari kode admin: $APK"
