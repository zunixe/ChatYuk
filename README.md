# 💬 ChatYuk

Aplikasi chat gratis, bebas iklan, dan aman untuk semua.

## Fitur

- 🔴 **Online Users** — lihat pengguna yang sedang online, filter berdasarkan negara & gender
- 💬 **Private Chat** — chat 1-on-1 dengan status realtime, foto, voice message, fitur sekali-lihat (view once), reply, dan hadiah/koin
- 🏠 **Chat Rooms** — room per negara dengan berbagai kategori (General, Curhat, Teknologi, Gaming, dll) + room private berbayar koin (perpanjang 7 hari)
- 👥 **Group Chat** — grup pribadi dengan info grup, media, dan anggota
- 📞 **Voice & Video Call 1:1** — panggilan suara & video via WebRTC, lengkap dengan notifikasi panggilan masuk & missed call
- 📸 **Stories** — kamera capture, composer, dan story viewer
- 📝 **Timeline** — posting & interaksi status
- 🗺️ **Nearby** — pengguna sekitar berbasis lokasi (flutter_map/OSM)
- 🏆 **Leaderboard & Missions** — gamifikasi koin lewat bonus & quest
- 👤 **Profil** — avatar, galeri foto, ganti username, status, dan edit profil
- 🌐 **Bilingual** — Indonesia & English (switch bahasa di profil)
- 🔐 **Auth multi-metode** — Anonymous, Email, dan Google Sign-In
- 🔔 **Push Notification** — via Firebase Cloud Messaging, bisa diatur per kategori
- 📵 **Anti-screenshot** — kontrol admin untuk mengaktifkan/menonaktifkan screenshot
- 🪙 **Koin & Gift** — kirim koin & hadiah sebagai digital goods (fitur finansial topup/KYC/withdraw sudah dihapus dari app)

## Tech Stack

| Teknologi | Digunakan untuk |
|-----------|----------------|
| Flutter | Cross-platform UI |
| Supabase | Database (PostgreSQL), Auth, Realtime |
| Firebase | Push notification (FCM) |
| Google Sign-In | Autentikasi Google SSO |
| Provider | State management |

## Struktur Project

```
lib/
├── config/        # Theme, strings (i18n), supabase config, regions, app flavor
├── models/        # Data models (User, Room, Message, dll)
├── providers/     # State management (ChangeNotifier)
├── screens/       # UI screens
└── services/      # Supabase API calls, geo, screen secure
```

## Cara Menjalankan

### Prasyarat
- Flutter SDK `^3.11.5`
- Android SDK

### Setup
1. Clone repositori
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Jalankan:
   ```bash
   flutter run
   ```

## Build Release

Build WAJIB memakai flavor + obfuscation. Build tanpa `--flavor` akan gagal
(two flavor dimensions: store × env). Fitur finansial (topup/KYC/withdraw)
SUDAH DIHAPUS TOTAL — flavor hanya membedakan appId & google-services.

### Flavor apkpureProd (default — APKPure & install HP; appId `com.chatyuk.chatyuk`)

```bash
flutter clean
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
# Output: build/app/outputs/flutter-apk/app-apkpureprod-release.apk
```

### Flavor playProd (Google Play — appId sama `com.chatyuk.chatyuk`, google-services.json khusus `android/app/src/play/`)

```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build appbundle --release --flavor playProd --dart-define=APP_FLAVOR=play \
  --obfuscate --split-debug-info=build/app/symbols
# Output: build/app/outputs/flutter-apk/app-playprod-release.aab
```

### Flavor adminProd (internal — JANGAN upload store; appId `com.chatyuk.chatyuk.admin`)

```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor adminProd -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=build/app/symbols
# Output: build/app/outputs/flutter-apk/app-adminprod-release.apk
```

Catatan:
- **JANGAN build flavor `play`/AAB untuk Play tanpa instruksi eksplisit** — default `apkpureProd`.
- Sebelum push rilis, jalankan gerbang anti-admin: `./scripts/check_release_apk.sh <apk>` → harus "OK bersih".
- Debug symbols di `build/app/symbols` jangan dihapus (dipakai `flutter symbolize`).
- Keystore aktif: `android/keystore/chatyuk-release-v2.jks` (alias `chatyuk`, pass `chatyuk2024secure`).

## Push ke HP (install manual)

MIUI/Xiaomi menolak `adb install` — install manual dari File Manager
(atau `adb install -r` bila popup "Izinkan" di-approve user):

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
APK="build/app/outputs/flutter-apk/app-apkpureprod-release.apk"

KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols

cp "$APK" "$HOME/Downloads/chatyuk.apk"
adb push "$HOME/Downloads/chatyuk.apk" /sdcard/Download/chatyuk.apk
# User install dari File Manager → Download → chatyuk.apk
```

## Upload ke Google Play (fastlane)

```bash
fastlane play track:alpha      # upload ke track "Pengujian tertutup - Alpha"
fastlane play track:production # upload ke production (release)
```

Aturan wajib:
- **Bump `version:` di `pubspec.yaml` HANYA sebelum upload Google Play** — jangan bump untuk build biasa/APKPure.
- Setelah bump: `flutter clean` dulu (agar `android/local.properties` ter-refresh), lalu build AAB flavor play.
- Service account key `fastlane/google-play.json` (sudah di `.gitignore`).

## Konfigurasi

Semua konfigurasi penting (Supabase, OAuth, keystore, Play Console) ada di [`CONFIG.md`](CONFIG.md).

## Aturan Pengembangan

Baca [`AGENTS.md`](AGENTS.md) untuk aturan coding — termasuk aturan wajib bahasa bilingual (Indonesia + English) untuk semua string UI, tipografi (token `AppText`/`AppGlyph`), dan aturan build & signing.

## Lisensi

Private project — semua hak dilindungi.
