# 💬 ChatYuk

Aplikasi chat gratis, bebas iklan, dan aman untuk semua.

## Fitur

- 🔴 **Online Users** — lihat pengguna yang sedang online, filter berdasarkan negara & gender
- 💬 **Private Chat** — chat 1-on-1 dengan status realtime, foto, dan fitur sekali-lihat (view once)
- 🏠 **Chat Rooms** — room per negara dengan berbagai kategori (General, Curhat, Teknologi, Gaming, dll)
- 👤 **Profil** — avatar, galeri foto, ganti username, status, dan edit profil
- 🌐 **Bilingual** — Indonesia & English (switch bahasa di profil)
- 🔐 **Auth multi-metode** — Anonymous, Email, dan Google Sign-In
- 🔔 **Push Notification** — via Firebase Cloud Messaging
- 📵 **Anti-screenshot** — kontrol admin untuk mengaktifkan/menonaktifkan screenshot

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
├── config/        # Theme, strings (i18n), supabase config, regions
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

```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Build AAB untuk Google Play:
```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

## Konfigurasi

Semua konfigurasi penting (Supabase, OAuth, keystore, Play Console) ada di [`CONFIG.md`](CONFIG.md).

## Aturan Pengembangan

Baca [`AGENTS.md`](AGENTS.md) untuk aturan coding — termasuk aturan wajib bahasa bilingual (Indonesia + English) untuk semua string UI.

## Lisensi

Private project — semua hak dilindungi.
