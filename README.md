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
- 🪙 **Koin & Gift** — kirim koin & hadiah sebagai digital goods
- 💳 **Top Up YukCoin** — top up koin via Google Play Billing (hanya build flavor `play`; kebijakan Play untuk digital goods). Fitur finansial lama (KYC/withdraw/Midtrans/iPaymu) TIDAK dipakai di app
- 🛡️ **Admin Panel** (build internal) — statistik, monitoring chat, peta user (termasuk layar penuh), perangkat, atribusi sumber user, kelola dummy & poin

## Tech Stack

| Teknologi | Digunakan untuk |
|-----------|----------------|
| Flutter | Cross-platform UI |
| Supabase | Database (PostgreSQL), Auth, Realtime, Edge Functions |
| Firebase | Push notification (FCM) & Analytics |
| Google Sign-In | Autentikasi Google SSO |
| in_app_purchase | Top up YukCoin via Google Play Billing (flavor `play`) |
| Provider | State management |

## Struktur Project

```
lib/
├── config/        # Theme, strings (i18n), supabase config, regions, app flavor
├── core/          # Cache (SQLite terenkripsi), media, perf probe, nav guard
├── models/        # Data models (User, Room, Message, dll)
├── providers/     # State management (ChangeNotifier)
├── screens/       # UI screens (termasuk panel admin & widget-nya)
└── services/      # Supabase API calls, geo, screen secure, topup

supabase/
├── functions/     # Edge Functions (play-topup-verify, welcome-bonus, dll)
└── migrations/    # Skema & RPC (SQL)
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
(two flavor dimensions: store × env). Fitur finansial lama (KYC/withdraw/
Midtrans/iPaymu) tidak diaktifkan; **top up YukCoin memakai Google Play
Billing** dan hanya tampil di build flavor `play` (kebijakan Play untuk
digital goods). Build `apkpure`/`admin` tidak menampilkan jalur top up.

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

## Arsitektur & Dokumentasi Teknis

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — ikhtisar arsitektur (lapisan client, backend Supabase, realtime, flavor).
- [`docs/FEATURE_MAP.md`](docs/FEATURE_MAP.md) — peta fitur → kode → SQL → test.
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) — metodologi & hasil pengukuran performa.
- [`docs/SECURITY_AUDIT.md`](docs/SECURITY_AUDIT.md) — audit keamanan (RLS, ACL, secret).

## Performa (PerfProbe)

Ada alat ukur internal untuk mendiagnosa lag (frame build/raster, tap tab →
frame pertama, dan latensi tiap RPC). Nyalakan **tanpa mengubah kode**:

```bash
flutter build apk --release --flavor adminProd -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=apkpure --dart-define=PERF_PROBE=true \
  --obfuscate --split-debug-info=build/app/symbols
# lalu: adb logcat | grep '\[PERF\]'
```

Saat `PERF_PROBE` tidak diset, probe = no-op (nol overhead). Ringkasan
dicetak otomatis saat app di-background.

**Catatan penting (koneksi basi):** koneksi HTTP keep-alive Supabase menjadi
basi setelah app idle, sehingga request pertama setelah resume bisa
menggantung lama bila tidak dibatasi. Karena itu `SupabaseConfig.init()`
memasang `HttpClient` dengan `connectionTimeout` 5s + `idleTimeout` 15s, dan
app melakukan warm-up koneksi saat resume. Jangan hapus tanpa menggantinya —
gejalanya "app ngelag setelah didiamkan".

## Aturan Pengembangan

Baca [`AGENTS.md`](AGENTS.md) untuk aturan coding — termasuk aturan wajib bahasa bilingual (Indonesia + English) untuk semua string UI, tipografi (token `AppText`/`AppGlyph`), dan aturan build & signing.

## Lisensi

Private project — semua hak dilindungi.
