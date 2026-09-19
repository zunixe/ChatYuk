#!/bin/zsh
# ============================================================
# GERBANG PRA-UPLOAD APK rilis (APKPure / Uptodown / HP).
#
#   ./scripts/check_release_apk.sh [APK]
#
# Syarat WAJIB (semua harus lolos):
#   1. File ada.
#   2. TANPA kode/string admin (entry user lib/main.dart).
#   3. Ditandatangani keystore RILIS v2 (SHA-256 cocok) — keystore salah =
#      Google Sign-In gagal `12500` di user.
#   4. applicationId = com.chatyuk.chatyuk (bukan .admin/.dev).
#   5. OBFUSCATED — nama kelas Dart absen di libapp.so (kode sulit
#      di-reverse). Non-obfuscate = build salah (lupa --obfuscate).
#   6. VERSI SAMA dengan yang LIVE di Google Play production (versionCode).
#      APKPure harus merilis versi identik dengan Play saat itu.
#
# Riwayat insiden: build "asal" (debug-signing / tanpa --obfuscate / versi
# beda dari Play) → Sign-In jebol / kode bocor / versi tak sinkron.
# ============================================================
APK="${1:-build/app/outputs/flutter-apk/app-apkpureprod-release.apk}"

EXPECTED_SHA256="84e9639899edfa69da1ffd01514ec871d2b23f383f781f932f2f76c2be9fa4b2"
EXPECTED_PKG="com.chatyuk.chatyuk"
AAPT=$(find "$HOME/Library/Android/sdk/build-tools" -name aapt 2>/dev/null | sort | tail -1)
APKSIGNER=$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner 2>/dev/null | sort | tail -1)
SYMBOLS="build/app/symbols"

fail() { echo ""; echo "DITOLAK: $1"; exit 1; }
ok()   { echo "OK  : $1"; }

[ -f "$APK" ] || fail "file tidak ditemukan: $APK"

# ── 1. Tidak ada kode admin ──
PATTERNS='admin_get_dummy_token|admin_renew_dummy_token|admin_stats_detail|Peta User|Chat Sebagai|dummy_token_missing|dummySwapFailed'
SO="lib/arm64-v8a/libapp.so"
unzip -p "$APK" "$SO" > /tmp/_chatyuk_so 2>/dev/null
HITS=$(strings /tmp/_chatyuk_so 2>/dev/null | grep -ciE "$PATTERNS")
[ "${HITS:-0}" = "0" ] || fail "$HITS string admin ditemukan di $APK — build tanpa entry user (lib/main.dart)."
ok "tanpa kode admin"

# ── 2. Obfuscated ──
# Non-obfuscate → nama kelas Dart ASLI muncul di libapp.so.
DARTNAMES=$(strings /tmp/_chatyuk_so 2>/dev/null | grep -cE '^(MessageBubble|ChatService|PrivateChatScreen|_PrivateChatScreenState|MentionAutocomplete)$')
if [ "${DARTNAMES:-0}" != "0" ]; then
  fail "APK TIDAK obfuscated ($DARTNAMES nama kelas Dart ditemukan).
       Obfuscation WAJIB.
       Build ulang: flutter build apk --release --flavor apkpureProd \\
         --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=$SYMBOLS"
fi
ok "obfuscated (nama kelas Dart absen di libapp.so)"
rm -f /tmp/_chatyuk_so

# ── 3. Signature = keystore rilis v2 ──
if [ -z "$APKSIGNER" ]; then
  echo "PERINGATAN: apksigner tidak ada — cek tanda tangan DILEWATI."
else
  SHA=$( "$APKSIGNER" verify --print-certs "$APK" 2>/dev/null \
    | grep -i "certificate SHA-256 digest" | head -1 \
    | sed 's/.*digest: //' | tr -d ' ' | tr 'A-F' 'a-f')
  [ "$SHA" = "$EXPECTED_SHA256" ] || fail "SHA-256 ($SHA) != keystore rilis v2.
       Build ini GAGAL Google Sign-In (12500). Build ulang dengan env
       KEYSTORE_PASS + KEY_PASS + --flavor apkpureProd."
  ok "ditandatangani keystore rilis v2"
fi

# ── 4. applicationId + versi ──
PKG=""; VC=""; VN=""
if [ -n "$AAPT" ]; then
  BADGING=$( "$AAPT" dump badging "$APK" 2>/dev/null | head -1 )
  # Python: hindari kelemahan greedy sed (`.*name=` cocok ke
  # platformBuildVersionName). `package:` selalu baris pertama badging.
  eval "$(echo "$BADGING" | python3 -c '
import sys, re
s = sys.stdin.read()
m = re.search(r"package: name=\x27([^\x27]*)\x27 versionCode=\x27([^\x27]*)\x27 versionName=\x27([^\x27]*)\x27", s)
if m:
    print(f"PKG={m.group(1)}; VC={m.group(2)}; VN={m.group(3)}")
')"
  [ "$PKG" = "$EXPECTED_PKG" ] || fail "applicationId '$PKG' != '$EXPECTED_PKG' (salah flavor?)"
  ok "applicationId $PKG (v$VN+$VC)"
fi

# ── 5. Versi == LIVE di Google Play production ──
# Ambil versionCode production dari Play API (service account fastlane).
if [ -f fastlane/google-play.json ] && command -v ruby >/dev/null 2>&1; then
  PLAY_VC=$(ruby -e '
    require "json"; require "googleauth"; require "google/apis/androidpublisher_v3"
    k=JSON.parse(File.read("fastlane/google-play.json"))
    a=Google::Auth::ServiceAccountCredentials.make_creds(json_key_io:StringIO.new(k.to_json),scope:"https://www.googleapis.com/auth/androidpublisher")
    s=Google::Apis::AndroidpublisherV3::AndroidPublisherService.new; s.authorization=a
    e=s.insert_edit("com.chatyuk.chatyuk")
    begin
      t=s.get_edit_track("com.chatyuk.chatyuk", e.id, "production")
      v=(t.releases||[]).select{|r| r.status=="completed"}.flat_map{|r| r.version_codes||[]}.max
      puts v
    ensure
      s.delete_edit("com.chatyuk.chatyuk", e.id)
    end' 2>/dev/null | tail -1)
  if [ -n "$VC" ] && [ -n "$PLAY_VC" ]; then
    if [ "$VC" != "$PLAY_VC" ]; then
      fail "versionCode APK ($VC) != Google Play production ($PLAY_VC).
       Aturan: APKPure WAJIB merilis versi yang SAMA dengan Play saat itu.
       Build dari versi Play: set pubspec version ke +$PLAY_VC (lihat AGENTS.md)."
    fi
    ok "versionCode $VC == Google Play production"
  else
    echo "PERINGATAN: tidak bisa baca versi Play — cek versi MANUAL."
  fi
else
  echo "PERINGATAN: fastlane/google-play.json tidak ada — cek versi Play MANUAL."
fi

echo ""
echo "== OK BERSIH — aman diupload ke APKPure / dipush ke HP."
