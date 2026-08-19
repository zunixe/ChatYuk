# 💬 ChatYuk

Aplikasi chat gratis, bebas iklan, dan aman untuk semua.

## Fitur

- 🔴 **Online Users** — lihat pengguna yang sedang online, filter berdasarkan negara & gender
- 💬 **Private Chat** — chat 1-on-1 dengan status realtime, foto, fitur sekali-lihat (view once), reply, dan hadiah/koin
- 🏠 **Chat Rooms** — room per negara dengan berbagai kategori (General, Curhat, Teknologi, Gaming, dll)
- 👤 **Profil** — avatar, galeri foto, ganti username, status, dan edit profil
- 🌐 **Bilingual** — Indonesia & English (switch bahasa di profil)
- 🔐 **Auth multi-metode** — Anonymous, Email, dan Google Sign-In
- 🔔 **Push Notification** — via Firebase Cloud Messaging
- 📵 **Anti-screenshot** — kontrol admin untuk mengaktifkan/menonaktifkan screenshot
- 💰 **Koin & Gift** (flavor apkpure) — topup Midtrans, kirim hadiah, KYC, dan withdraw

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

Build WAJIB memakai flavor + obfuscation. Build tanpa `--flavor` akan gagal (dua flavor terdaftar).

### Flavor apkpure (default, fitur penuh — topup, KYC, withdraw; appId `com.chatyuk.chatyuk`)

```bash
flutter clean
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
# Output: build/app/outputs/flutter-apk/app-apkpure-release.apk
```

### Flavor play (Google Play — topup & cash-out disembunyikan; appId `com.chatyuk.chatyuk.play`)

```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build appbundle --release --flavor play --dart-define=APP_FLAVOR=play \
  --obfuscate --split-debug-info=build/app/symbols
# Output: build/app/outputs/bundle/playRelease/app-play-release.aab
```

Catatan:
- **JANGAN build flavor `play` tanpa instruksi eksplisit** — default selalu `apkpure`.
- Debug symbols di `build/app/symbols` jangan dihapus (dipakai `flutter symbolize`).
- Debug symbols disimpan di `build/app/symbols` (jangan dihapus) — dipakai `flutter symbolize` untuk baca stack trace saat crash.
- Keystore aktif: `android/keystore/chatyuk-release-v2.jks` (alias `chatyuk`, pass `chatyuk2024secure`).

## Push ke HP (install manual)

MIUI/Xiaomi menolak `adb install` — install manual dari File Manager:

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
APK="build/app/outputs/flutter-apk/app-apkpure-release.apk"

flutter clean
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure \
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