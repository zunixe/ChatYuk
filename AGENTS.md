# Aturan Coding ChatYuk

Aturan ini dibaca otomatis oleh AI coding tools. Patuhi selalu.

## Bahasa / Internasionalisasi (WAJIB)

**Semua teks yang tampil ke pengguna WAJIB bilingual (Indonesia + English) — TIDAK BOLEH hardcode bahasa Indonesia.**

### Aturan:
1. Semua string UI disimpan di `lib/config/strings.dart` sebagai getter `S`:
   ```dart
   String get btnSave => isId ? 'Simpan' : 'Save';
   ```
2. Screen memakai `s.xxx` — jangan menulis `Text('Simpan')` langsung.
3. Tambahkan getter baru di `strings.dart` ketika butuh string baru.
4. String yang bersifat proper noun / angka / data key TIDAK perlu diterjemahkan:
   - Nama app: `'ChatYuk'`
   - Status key: `'online'`, `'idle'`, `'offline'`
   - Angka/format: `'$i'`, `'$unread'`, `'${_secondsLeft}s'`
   - Nama network wallet: `'Tron Network'`, dll.

### Checklist sebelum commit:
- [ ] Tidak ada `Text('...')` hardcode bahasa Indonesia di `lib/screens/`
- [ ] Tidak ada `SnackBar(content: Text('...'))` hardcode bahasa Indonesia
- [ ] Tidak ada `tooltip: '...'` hardcode bahasa Indonesia
- [ ] Semua string lewat `s.`

## Struktur Project

- `lib/screens/` — UI screen
- `lib/providers/` — state management (ChangeNotifier)
- `lib/services/` — Supabase API calls
- `lib/config/` — theme, strings, supabase config, regions
- `lib/models/` — data models

## Konvensi Code

- Ikuti style Flutter standar (`flutter analyze` harus bersih — 0 error, 0 warning)
- Jangan tambahkan komentar kecuali diperlukan
- Komentar singkat dalam bahasa Indonesia (konsisten dengan codebase)
- Jangan import library yang tidak dipakai (cek `flutter analyze`)
- Gunakan `copyWith` untuk update model parsial

## Build & Signing

- Keystore aktif: `android/keystore/chatyuk-release-v2.jks` (alias `chatyuk`, pass `chatyuk2024secure`)
- **WAJIB** pakai obfuscation + split debug info supaya kode Dart sulit di-reverse engineering:
  ```bash
  KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
    flutter build apk --release --obfuscate --split-debug-info=build/app/symbols
  ```
- AAB untuk Google Play juga pakai flag yang sama:
  ```bash
  KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
    flutter build appbundle --release --obfuscate --split-debug-info=build/app/symbols
  ```
- Debug symbols disimpan di `build/app/symbols` (jangan dihapus) — dipakai `flutter symbolize` untuk baca stack trace saat crash.
- Sebelum selesai, selalu: `flutter analyze` → `flutter build apk --release --obfuscate --split-debug-info=build/app/symbols` → install & test
- Keamanan: jangan pernah simpan secret server (password DB, Supabase service_role key) di app — hanya `publishableKey` di `lib/config/supabase_config.dart`. Data dilindungi RLS per-user.

## Fitur Khusus

- **Screenshot toggle**: `app_settings.screenshot_enabled` (admin `zunixe@gmail.com`) → `ScreenSecureService`
- **Deep link**: `chatyuk://login-callback` → `lib/main.dart` `_handleDeepLink()`
- **Google Sign-In**: native `google_sign_in` + Supabase `signInWithIdToken`. JANGAN pakai OAuth client dari project `chatyuk.admin` (banned).
