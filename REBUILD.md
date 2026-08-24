# Rebuild & Deploy — ChatYuk

Catatan biar tidak bolak-balik build karena perubahan tidak muncul di device.

## ALUR WAJIB SEKARANG: push ke folder Download SAJA (tanpa adb install)

User install manual dari File Manager di masing-masing HP. JANGAN buang waktu
dengan `adb install` satu-per-satu — cukup:

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
APK=/Users/zunixe/Documents/ChatYuk/build/app/outputs/flutter-apk/app-apkpure-release.apk
H=$(md5 -q "$APK"); echo "local $H"

# Push ke folder Download SEMUA device + verifikasi hash
for d in 192.168.18.33:42679 192.168.18.240:39199 59UYD25830201037 \
         adb-c2bcd797-YOnXBr._adb-tls-connect._tcp.; do
  adb -s "$d" push "$APK" /sdcard/Download/chatyuk.apk >/dev/null 2>&1
  R=$(adb -s "$d" shell md5sum /sdcard/Download/chatyuk.apk 2>/dev/null | awk '{print $1}')
  [ "$R" = "$H" ] && echo "$d -> OK" || echo "$d -> GAGAL"
done
```

Device list (update kalau berubah):
- Xiaomi 15      : `192.168.18.33:42679`
- Redmi Note 9P  : `192.168.18.240:39199`
- Huawei MRDI-W09: `59UYD25830201037` (USB)
- Redmi Note 9P lama: `adb-c2bcd797-YOnXBr._adb-tls-connect._tcp.`

Laporan ke user cukup: **"sudah disimpan di folder Download semua device"** +
status hash. Selesai.

Gotcha MIUI: file APK kadang lenyap dibersihkan cleaner/security MIUI.
Kalau user bilang "belum ada", push ulang + verifikasi `ls -l`.

## Kapan pakai rebuild PENUH

Kalau sudah build + install tapi **tampilan/teks tidak berubah** di device,
hampir selalu karena salah satu:

- Incremental build memakai cache lama (`.dart_tool`, `build/`).
- `flutter install`/`adb install -r` cuma update di atas versi lama — kadang
  aset/string lama masih nyangkut.

Solusi: **clean rebuild + fresh install (uninstall dulu)**.

## Perintah rebuild PENUH (copy-paste)

```bash
cd /Users/zunixe/Documents/ChatYuk

# 1. Bersihkan semua cache build
flutter clean
flutter pub get

# 2. Build release (flavor apkpure — fitur penuh) + obfuscation
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
```

APK keluar di: `build/app/outputs/flutter-apk/app-apkpure-release.apk`

## Clean Android-only (CEPAT — pakai ini untuk kerja harian)

JANGAN `flutter clean` penuh — itu fetch Xcode/SPM iOS ~4 menit sia-sia
(Android tidak pakai Xcode sama sekali). Cukup:

```bash
cd /Users/zunixe/Documents/ChatYuk
rm -rf build/app/outputs build/app/symbols build/app/intermediates \
  build/app/tmp .dart_tool/flutter_build

KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
```

Full `flutter clean` hanya wajib kalau ubah `pubspec.yaml` / plugin native.

## Fresh install ke device (WAJIB uninstall dulu kalau UI ga update)

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
APK=/Users/zunixe/Documents/ChatYuk/build/app/outputs/flutter-apk/app-apkpure-release.apk

# Ganti daftar device sesuai `adb devices`
for d in 192.168.18.33:37501 192.168.18.242:42205 adb-c2bcd797-YOnXBr._adb-tls-connect._tcp.; do
  echo "=== $d ==="
  adb -s "$d" uninstall com.chatyuk.chatyuk        # HAPUS versi lama dulu
  adb -s "$d" install "$APK"                        # install fresh
done
```

`adb install -r` (tanpa uninstall) cukup untuk update biasa, tapi kalau
tampilan tidak berubah → **uninstall dulu** seperti di atas.

## Verifikasi benar ter-update

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for d in 192.168.18.33:37501 192.168.18.242:42205 adb-c2bcd797-YOnXBr._adb-tls-connect._tcp.; do
  echo "=== $d ==="
  adb -s "$d" shell dumpsys package com.chatyuk.chatyuk | grep -E "versionName|lastUpdateTime"
done
```

Pastikan `lastUpdateTime` = waktu install barusan. Kalau masih waktu lama,
berarti install gagal / device salah.

## Buka app setelah install

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s 192.168.18.33:37501 shell am force-stop com.chatyuk.chatyuk
adb -s 192.168.18.33:37501 shell am start -n com.chatyuk.chatyuk/.MainActivity
```

## Checklist sebelum build

- [ ] `flutter analyze` → 0 error, 0 warning
- [ ] Perubahan string ada di `lib/config/strings.dart` (bilingual `s.`)
- [ ] Kalau ubah UI dan tidak muncul → `flutter clean` + fresh install (uninstall)

## Flavor play (Google Play — topup & cash-out disembunyikan)

```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build appbundle --release --flavor play --dart-define=APP_FLAVOR=play \
  --obfuscate --split-debug-info=build/app/symbols
```

## Kredensial

Semua secret ada di `.env` (tidak di-commit). Load dengan:
```bash
set -a; source .env; set +a
```
