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

## Tipografi (WAJIB)

**JANGAN pernah menulis `fontSize:` di luar `lib/config/theme.dart`.**
Semua ukuran font memakai token `AppText` dari `lib/config/theme.dart`.

### Skala resmi — 8 ukuran, 11 token

| Token | Size | Weight | Pakai untuk |
|---|---|---|---|
| `AppText.micro` | 10 | w500 | timestamp pesan, badge unread, counter overlay |
| `AppText.caption` | 11 | w400 | label di atas nilai, helper text, teks di dalam chip status |
| `AppText.label` | 12 | w600 | section label, label tab, teks chip/badge |
| `AppText.bodySmall` | 12 | w400 | subtitle list, deskripsi setting, teks sekunder |
| `AppText.body` | 14 | w400 | isi bubble chat, isi dialog, composer, paragraf |
| `AppText.bodyStrong` | 14 | w600 | judul list tile, label setting, nilai info |
| `AppText.button` | 16 | w700 | label tombol CTA |
| `AppText.titleEmphasis` | 16 | w700 | judul kartu / section (admin) |
| `AppText.title` | 17 | w700 | judul AppBar, judul dialog, judul bottom sheet |
| `AppText.headline` | 20 | w800 | nama user di header profil |
| `AppText.display` | 24 | w800 | saldo wallet, angka hero, tagline |

Angka yang dipakai: **10, 11, 12, 14, 16, 17, 20, 24**. Tidak ada yang lain.
`label`/`bodySmall` sama-sama 12 dan `button`/`titleEmphasis` sama-sama 16 —
hierarki dibedakan oleh **weight**, bukan size. Ini disengaja.

### Tabel keputusan — teks apa pakai token apa

| Kalau kamu menulis... | Pakai |
|---|---|
| judul halaman / AppBar | biarkan kosong (sudah dari `appBarTheme`) |
| judul `AlertDialog` / bottom sheet | biarkan kosong (sudah dari `dialogTheme`) |
| isi `AlertDialog` | biarkan kosong (sudah dari `dialogTheme`) |
| `ListTile` title / subtitle | biarkan kosong (sudah dari `listTileTheme`) |
| label `TabBar` | biarkan kosong (sudah dari `tabBarTheme`) |
| isi `SnackBar` | biarkan kosong (sudah dari `snackBarTheme`) |
| label `ElevatedButton`/`FilledButton` | biarkan kosong (sudah dari theme) |
| nama user di list | `AppText.bodyStrong` |
| baris "gender · umur · kota" di bawah nama | `AppText.bodySmall` |
| label setting (kiri switch) | `AppText.bodyStrong` |
| deskripsi setting (di bawah label) | `AppText.bodySmall` |
| label kecil di atas sebuah nilai | `AppText.caption` |
| nilai di bawah label kecil | `AppText.bodyStrong` |
| header grup section | `AppText.label` |
| teks di dalam chip / badge / pill | `AppText.label` |
| status "online/idle/offline" | `AppText.caption` |
| jam pesan chat | `AppText.micro` |
| angka unread | `AppText.micro` |
| isi bubble chat | `AppText.body` |
| nama pengirim di bubble room | `AppText.label` |
| teks input composer chat | `AppText.body` |
| empty state judul | `AppText.bodyStrong` |
| empty state penjelasan | `AppText.bodySmall` |
| helper / catatan di bawah field | `AppText.caption` |
| saldo koin, angka besar | `AppText.display` |

Kalau ragu antara dua token: pilih yang **lebih kecil**, lalu naikkan weight.

### Cara pakai

```dart
// Benar — token apa adanya
Text(s.labelStatus, style: AppText.caption)

// Benar — ganti warna saja
Text(s.labelStatus, style: AppText.caption.copyWith(color: AppTheme.textSecondary))

// Benar — biarkan theme yang atur
ListTile(title: Text(s.labelUsername))

// SALAH — fontSize manual
Text(s.labelStatus, style: const TextStyle(fontSize: 11))

// SALAH — override size lewat copyWith
Text(s.labelStatus, style: AppText.caption.copyWith(fontSize: 12))
```

`copyWith` hanya boleh untuk `color`, `decoration`, `fontStyle`.
**Tidak boleh** untuk `fontSize` dan `height`.

### Emoji & ikon dekoratif

Emoji dan ikon **bukan** teks — pakai `AppGlyph`, bukan `AppText`:

| Token | Size | Pakai untuk |
|---|---|---|
| `AppGlyph.sm` | 20 | emoji inline, ikon room di list |
| `AppGlyph.md` | 24 | emoji bubble, sel emoji picker |
| `AppGlyph.lg` | 28 | emoji gift picker |
| `AppGlyph.xl` | 40 | emoji empty state |

Inisial avatar **selalu** `AppGlyph.avatarInitial(diameter)` — jangan angka manual.
Fungsinya `diameter * 0.38`, jadi rasio inisial ke bulatan selalu sama.

Ukuran `Icon(size:)` — panduan, bukan wajib: **14** (inline teks kecil),
**16** (dalam tombol), **18** (list dense), **20** (list/AppBar standar),
**24** (aksi utama), **40** (empty state). Hindari angka lain.

### Line height

Sudah termasuk di token. Jangan tulis `height:` sendiri.
Referensi: teks padat 1.2, teks yang dibaca 1.35, angka besar 1.15.

### Checklist sebelum commit
- [ ] `grep -rn 'fontSize:' lib --exclude-dir=config` → **0 hasil**
- [ ] `grep -rn 'height: 1\.' lib --exclude-dir=config` → **0 hasil**
- [ ] Tidak ada `copyWith(fontSize:` di mana pun
- [ ] `flutter analyze` → 0 error, 0 warning

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
  - Flavor **apkpure** (default, fitur penuh — Midtrans topup, KYC, withdraw; appId `com.chatyuk.chatyuk`):
    ```bash
    KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
      flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure \
      --obfuscate --split-debug-info=build/app/symbols
    ```
  - Flavor **play** (Google Play — topup & cash-out disembunyikan via `lib/config/app_flavor.dart`; appId `com.chatyuk.chatyuk.play`; `google-services.json` khusus di `android/app/src/play/`):
    ```bash
    KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
      flutter build apk --release --flavor play --dart-define=APP_FLAVOR=play \
      --obfuscate --split-debug-info=build/app/symbols
    ```
  - Build TANPA `--flavor` akan gagal (dua flavor terdaftar).
- AAB untuk Google Play juga pakai flag yang sama (flavor play):
  ```bash
  KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
    flutter build appbundle --release --flavor play --dart-define=APP_FLAVOR=play \
    --obfuscate --split-debug-info=build/app/symbols
  ```
- Debug symbols disimpan di `build/app/symbols` (jangan dihapus) — dipakai `flutter symbolize` untuk baca stack trace saat crash.
- **JANGAN build flavor `play` / AAB untuk Google Play tanpa instruksi eksplisit dari user.** Default build = flavor `apkpure`. Kalau ragu, tanya dulu.
- Sebelum selesai, selalu: `flutter analyze` → `flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=build/app/symbols` → install & test
- Keamanan: jangan pernah simpan secret server (password DB, Supabase service_role key) di app — hanya `publishableKey` di `lib/config/supabase_config.dart`. Data dilindungi RLS per-user.

## Fastlane Upload ke Google Play

Upload AAB otomatis ke Google Play (flavor play) pakai fastlane:

```bash
fastlane play track:alpha      # upload ke track "Pengujian tertutup - Alpha"
fastlane play track:production # upload ke production (release)
```

Syarat:
- `fastlane/google-play.json` — service account key (`chatyuk-play-upload@chatyuk-504910.iam.gserviceaccount.com`), JANGAN commit (sudah di `.gitignore`).
- Service account harus terdaftar di Play Console → Pengguna dan izin (izin: rilis ke produksi + rilis ke track pengujian).
- Google Play Android Developer API harus enabled di GCP project `chatyuk-504910`.

Catatan penting:
- **Wajib** bump `version: x.y.z+N` di `pubspec.yaml` sebelum upload (versionCode tidak boleh dipakai ulang).
- Setelah bump, jalankan `flutter clean` dulu agar `android/local.properties` (flutter.versionCode) ter-refresh.
- Track beta = "Pengujian tertutup - Alpha" (nama API-nya `alpha`, bukan `beta`).
- Keystore dibaca dari `android/key.properties` (bukan dari Fastfile).

## Install ke Device (WAJIB clean install, bukan `-r`)

Saat install ke HP, **selalu hapus cache/data dulu** (uninstall → install fresh).
Jangan pakai `adb install -r` karena APK lama bisa bikin UI tidak ter-update.

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
APK="build/app/outputs/flutter-apk/app-apkpure-release.apk"

# Device wireless debugging (ganti IP:port sesuai `adb devices`):
for d in 192.168.18.242:42205 192.168.18.33:40591; do
  adb -s "$d" uninstall com.chatyuk.chatyuk
  adb -s "$d" install "$APK"
done
```

Catatan:
- MIUI/Xiaomi sering menolak `adb install` dengan `INSTALL_FAILED_USER_RESTRICTED`
  → user harus tap **"Ijinkan"** di layar HP saat popup muncul, lalu jalankan
  `adb install` sekali lagi.
- `adb shell pm clear com.chatyuk.chatyuk` **tidak bisa** via wireless adb
  di MIUI (SecurityException). Cara bersih = `uninstall` → `install` fresh.
- Setelah install, launch: `adb -s <device> shell monkey -p com.chatyuk.chatyuk -c android.intent.category.LAUNCHER 1`

## Fitur Khusus

- **Screenshot toggle**: `app_settings.screenshot_enabled` (admin `zunixe@gmail.com`) → `ScreenSecureService`
- **Deep link**: `chatyuk://login-callback` → `lib/main.dart` `_handleDeepLink()`
- **Google Sign-In**: native `google_sign_in` + Supabase `signInWithIdToken`. JANGAN pakai OAuth client dari project `chatyuk.admin` (banned).
