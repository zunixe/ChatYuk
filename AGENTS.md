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

### Token family ke-2 — nilai non-`AppText` (SAH)

Aturan "jangan tulis `fontSize:`" berlaku untuk **angka mentah**. Nilai ukuran
yang diambil dari **token resmi** tetap sah walau ditulis sebagai `fontSize:`
di luar `theme.dart`, karena token itu sendiri yang menjaga skala:

- `AppText.*` — teks UI (lihat tabel di atas). Ini jalur utama.
- `AppGlyph.*` — emoji, ikon dekoratif, inisial avatar (`avatarInitial`).
- `StoryText.*` — teks overlay story (skala khusus story).

```dart
// BENAR — nilai dari token (skala tetap terjaga)
TextStyle(fontSize: AppGlyph.sm)
Text(StoryText.size(...))

// SALAH — angka mentah (ini yang dilarang)
TextStyle(fontSize: 13)
TextStyle(fontSize: 11.5)
```

**Yang dilarang hanya angka literal.** Kalau butuh ukuran baru, tambahkan
token baru di `theme.dart` — jangan tulis angkanya langsung.

### Line height

Sudah termasuk di token. Jangan tulis `height:` sendiri.
Referensi: teks padat 1.2, teks yang dibaca 1.35, angka besar 1.15.

### Checklist sebelum commit
- [ ] `grep -rnE 'fontSize: [0-9]' lib --exclude-dir=config` → **0 hasil**
      (angka mentah — token `AppText`/`AppGlyph`/`StoryText` sah)
- [ ] `grep -rn 'height: 1\.' lib --exclude-dir=config` → **0 hasil**
- [ ] Tidak ada `copyWith(fontSize:` di mana pun
- [ ] `flutter analyze` → 0 error, 0 warning

## SQL / Migrasi (WAJIB — baca SEBELUM mengubah DB)

**Latar:** di project ini fungsi SQL sering di-`create or replace` dengan
**copy-paste seluruh isi lalu tambah 1-2 baris** — tanpa sadar MENGHAPUS cabang
yang ditambahkan orang/migrasi lain. Kasus nyata: `ai_presence_tick` di-replace
8x, `ai_always_online` (Admin Chatyuk) hilang 2x → harus bikin migrasi
"restore". Ini yang bikin "pas migrasi, fitur lain rusak".

### Aturan pantang dilanggar

1. **DILARANG redefine fungsi FROZEN dengan copy-paste.** Daftar ada di
   `scripts/frozen_functions.txt` (30 fungsi: presence/AI, notif, chat, poin,
   admin). Kalau HARUS mengubahnya:
   - Ambil versi TERBARU dari `supabase/snapshots/functions.sql` (yang
     mencerminkan DB live), jangan dari migrasi lama/memori.
   - Tempel header komentar: `-- menyentuh: <nama_fn>` — kalau tidak,
     `scripts/check_migrations.sh` akan MENOLAK.
   - Setelah migrasi, WAJIB jalankan `scripts/snapshot_functions.sh`,
     review `git diff supabase/snapshots/functions.sql` untuk memastikan
     **tidak ada cabang hilang**, lalu commit snapshot-nya.
2. **Timestamp migrasi harus UNIK.** Format `YYYYMMDDHHMMSS_nama.sql`.
   Tabrakan (2 file prefix sama) = urutan apply tidak deterministik → CI
   menolak. Naikkan detik kalau bentrok.
3. **DROP TABLE / DROP COLUMN / ALTER COLUMN TYPE** wajib penanda di baris
   yang sama: `-- SAFE: alasan + siapa/tabel mana yang sudah tidak pakai`.
   CI menolak tanpa penanda.
4. **Jangan ubah semantik kolom yang dipakai lintas-fitur** tanpa cek
   `docs/FEATURE_MAP.md`. Kolom/flag kritis (mis. `dummy_accounts.ai_always_online`,
   `ai_no_sleep`, `ai_wake_until`, `ai_offline_until`, `profiles.status`,
   `app_settings.ai_global_enabled`, `ai_internal_config.callback_secret`)
   dipakai presence, notif, chat, admin, poin sekaligus.
5. **Penerapan SQL di Mac ini HANYA lewat Management API** (CLI `db push`/`db query`
   HANG). Cheat sheet: `supabase/migrations/APPLIED_VIA_API.md`.

### Checklist sebelum commit migrasi

- [ ] `bash scripts/check_migrations.sh --all` → **OK bersih**
- [ ] Kalau menyentuh fungsi FROZEN: header `-- menyentuh: <fn>` ada +
      `scripts/snapshot_functions.sh` dijalankan + diff snapshot direview
- [ ] Kalau mengubah perilaku fitur: tambah/aktifkan test di
      `supabase/tests/` (pgTAP) dan `flutter test` tetap 100% hijau
- [ ] Catat migrasi yang di-apply di `docs/MIGRATION_LOG.md`
- [ ] Kalau menyentuh performa (render/rebuild/animasi/prefetch): baca
      `docs/PERFORMANCE.md` DULU, ukur sebelum-sesudah, lalu catat perubahannya
      di sana. Jangan membalik optimasi yang sudah ada (mis. mengembalikan
      `context.watch` yang sudah jadi `select`, menghapus `TickerMode` /
      `RepaintBoundary`, atau memindahkan komputasi berat kembali ke `build()`).

## Struktur Project

- `lib/screens/` — UI screen (dilarang import `services/` — lihat Modularitas)
- `lib/providers/` — state management (ChangeNotifier) + pembungkus service
- `lib/services/` — SERVICE saja: Supabase API/RPC, presence, realtime, call
- `lib/core/` — helper murni non-service (bukan I/O bisnis):
  - `core/cache/` — `message_cache`, `media_disk_cache`, `photo_cache`,
    `post_photo_cache`, `offline_outbox`
  - `core/media/` — `chat_photo_helper`, `forensic_watermark`, `chat_background`,
    `link_preview_service`
  - `core/perf/` — `perf_probe`
  - `core/screen_secure_service.dart`, `core/admin_gate.dart`
- `lib/mixins/` — modul bersama lintas screen (chat)
- `lib/config/` — theme, strings, supabase config, regions
- `lib/models/` — data models
- `lib/screens/<screen>/widgets/` — widget privat milik screen itu (co-located)

## Modularitas (WAJIB — untuk AI berikutnya)

**Acuan modul bersama private ↔ room = `private_chat_screen.dart` (terbaru).
Jangan balik: room yang menyesuaikan, bukan private.**

1. **Batas ukuran:** file baru MAKS ~800 baris. Widget privat > 100 baris →
   pindah ke `lib/screens/<screen>/widgets/<nama>_widgets.dart`. Kelas publik
   (dipakai lintas file) TIDAK boleh diawali `_`.
2. **Dilarang duplikasi** logika chat private ↔ room. Modul bersama SUDAH ADA
   (pakai ini, jangan copy-paste):
   - antrean offline → `lib/mixins/chat_outbox_mixin.dart` (`ChatOutboxMixin`)
   - seleksi/reaksi/edit/forward → `lib/mixins/chat_selection_mixin.dart`
     (`ChatSelectionMixin`)
   - alur kirim pesan (teks/foto/caption/poin) → `lib/mixins/chat_send_mixin.dart`
   - pemrosesan foto (resize/watermark) → `lib/core/media/chat_photo_helper.dart`
   - perekam voice → `lib/mixins/voice_recorder_mixin.dart`
   - composer → `lib/widgets/chat_composer_input.dart` (`ChatComposerInput`)
   
   Butuh yang sama di dua screen? Pakai modul itu — JANGAN copy-paste.
3. **BOUNDARY TEGAK — screen DILARANG import `services/` (0, tanpa pengecualian).**
   Semua I/O bisnis lewat `lib/providers/`. Helper murni ada di `lib/core/`.
   **`lib/core/` juga DILARANG import `services/`** — kalau butuh I/O,
   inject dari luar (mis. `PostPhotoCache.downloader` di-wire di
   `lib/main.dart`) atau pindahkan file ke `lib/services/`.
   Gate: `bash scripts/check_screen_boundary.sh` (jalan di CI). Kalau butuh
   service baru di screen: tambah method passthrough di provider terkait,
   atau (helper murni) taruh di `lib/core/`.
4. **`ChatService` SUDAH dipecah per domain** lewat `part` + mixin
   (`chat_service_private/private_chatlist/room/typing/presence/gift.dart`),
   dengan `ChatBase` untuk state bersama. Jangan menaruh method baru di file
   monolit — taruh di mixin domain yang sesuai. Pemanggil tetap import
   `services/chat_service.dart` (satu entry). Jangan ubah pola `part`
   menjadi import biasa (field privat lintas-domain akan putus).
5. **Provider baru (Fase 9)** untuk service yang dipakai screen: Storage,
   Location(+geo), DeviceInfo, Contact, Avatar, NotificationPrefs,
   MessageReaction. Pakai ini — jangan bikin import services di screen.
6. Verifikasi tiap perubahan struktural: `flutter analyze` 0 error/0 warning +
   `flutter test` 100% hijau.
7. **Jangan hapus optimasi performa yang sudah ada** (lihat `docs/PERFORMANCE.md`).

### Checklist sebelum commit refactor
- [ ] Tidak ada file baru > ~800 baris
- [ ] Tidak ada kode yang diduplikat private ↔ room
- [ ] `bash scripts/check_screen_boundary.sh` → OK (0 screen import services)
- [ ] `flutter analyze` 0/0 + `flutter test` hijau

## Konvensi Code

- Ikuti style Flutter standar (`flutter analyze` harus bersih — 0 error, 0 warning)
- Jangan tambahkan komentar kecuali diperlukan
- Komentar singkat dalam bahasa Indonesia (konsisten dengan codebase)
- Jangan import library yang tidak dipakai (cek `flutter analyze`)
- Gunakan `copyWith` untuk update model parsial

## Build & Signing

- **SATU-SATUNYA PROSEDUR BUILD TERVERIFIKASI — build dari tool/AI lain
  yang tidak mengikuti ini MEMBUAT LOGIN GOOGLE GAGAL (`12500,null/null`):**
  build "asal" (debug-signing atau tanpa env keystore) menghasilkan SHA-1
  yang tidak dikenal Firebase. Selalu ikuti langkah persis di bawah —
  clean manual Android-only, env `KEYSTORE_PASS`+`KEY_PASS`, flag
  `--flavor` + `--dart-define` lengkap. Setelah build, verify SHA-1 APK
  (lihat bagian Google Sign-In) sebelum dipush ke HP.

- **FLAVOR-GATE ADMIN (WAJIB dipahami sebelum build):**
  - Kode admin TERPISAH dari build rilis. Entry rilis = default `lib/main.dart`
    (TIDAK mengandung kode admin — dijamin tree-shaking via `lib/core/admin_gate.dart`).
  - Entry admin = `-t lib/main_admin.dart` + flavor `admin` (appId
    `com.chatyuk.chatyuk.admin`) — HANYA untuk HP pribadi, DILARANG upload store.
  - Gerbang wajib SEBELUM upload rilis: `./scripts/check_release_apk.sh <apk>`
    → harus "OK bersih". Kalau DITOLAK, build salah target.
- Keystore aktif: `android/keystore/chatyuk-release-v2.jks` (alias `chatyuk`, pass `chatyuk2024secure`)
- **WAJIB** pakai obfuscation + split debug info supaya kode Dart sulit di-reverse engineering:
   - Flavor **apkpure** (default; appId `com.chatyuk.chatyuk`):
     ```bash
     KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
       flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
       --obfuscate --split-debug-info=build/app/symbols
     ```
   - Flavor **play** (Google Play; appId `com.chatyuk.chatyuk` — sama dengan apkpure; `google-services.json` khusus di `android/app/src/play/`):
     ```bash
     KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
       flutter build apk --release --flavor playProd --dart-define=APP_FLAVOR=play \
       --obfuscate --split-debug-info=build/app/symbols
     ```
   - **Kedua flavor memiliki PERILAKU SAMA** — app chat + koin sebagai digital
     goods murni (bonus/quest/gift → fitur premium). Fitur finansial (top-up
     iPaymu/Midtrans, KYC, withdraw/cash-out) **telah dihapus total** — dari
     kode maupun server. Flavor hanya membedakan appId & google-services.
     Kode finansial lama tersimpan di git tag `archive/financial-features`
     (lihat `docs/restore-financial-features.md`).
  - Build TANPA `--flavor` akan gagal (dua flavor terdaftar).
- AAB untuk Google Play juga pakai flag yang sama (flavor play):
  ```bash
  KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
    flutter build appbundle --release --flavor playProd --dart-define=APP_FLAVOR=play \
    --obfuscate --split-debug-info=build/app/symbols
  ```
- Debug symbols disimpan di `build/app/symbols` (jangan dihapus) — dipakai `flutter symbolize` untuk baca stack trace saat crash.
- **JANGAN build flavor `play` / AAB untuk Google Play tanpa instruksi eksplisit dari user.** Default build = flavor `apkpure`. Kalau ragu, tanya dulu.
- Build flavor `admin` (internal): `-t lib/main_admin.dart` + `--flavor admin` — output `app-admin-release.apk`, appId `com.chatyuk.chatyuk.admin`. DILARANG upload ke store mana pun.
- Sebelum selesai, selalu: `flutter analyze` → `flutter clean` (WAJIB — build incremental sering tidak memasukkan perubahan terbaru) → `flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=build/app/symbols` → copy ke `~/Downloads/chatyuk.apk` → push ke HP (lihat "Build & Push ke HP")

### Build cepat — LEWATI iOS (WAJIB untuk kerja Android-only)
Kita HANYA rilis Android (flavor `apkpure`); iOS tidak pernah di-build untuk distribusi.
`flutter clean` utuh membuang waktu ~210 detik cuma untuk fetch Xcode workspace iOS
yang tidak kita butuhkan. Ganti `flutter clean` dengan pembersihan Android saja:

```bash
rm -rf build/app/outputs build/app/symbols build/app/intermediates \
  build/app/tmp .dart_tool/flutter_build
# lalu langsung build apkpure (tanpa `flutter clean`):
flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
```

### Build diagnosis TANPA obfuscation (WAJIB saat cari crash)

Saat debug/nelusuri crash di HP, **JANGAN pakai `--obfuscate`**. Obfuscation membuat
nama class jadi `kr`/`Ew` dan stack trace tidak bisa di-symbolize ke file:line
(kecuali simbol cocok PERSIS per build_id, yang sering tidak cocok karena build_id
berubah tiap build). Akibatnya jam terbuang cuma untuk nebak lokasi error.

Untuk build diagnosis, lewati `--obfuscate` DAN `--split-debug-info` agar nama
class asli (`FlexParentData`, `StackParentData`, dll) dan pesan Flutter
("Incorrect use of ParentDataWidget ... parent: Column") tetap utuh di APK:

```bash
rm -rf build/app/outputs build/app/symbols build/app/intermediates \
  build/app/tmp .dart_tool/flutter_build
flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure
cp build/app/outputs/flutter-apk/app-apkpure-release.apk ~/Downloads/chatyuk_dbg.apk
```

- Nama file `chatyuk_dbg.apk` (bukan `chatyuk.apk`) supaya tidak tertukar dengan
  build rilis. User install `chatyuk_dbg.apk`, lalu baca log — error sudah jelas
  sebut file:line + parent widget.
- Build diagnosis TIDAK boleh diupload ke store/Play (tidak diobfuskasi).

Catatan: `flutter clean` tetap wajib KALAU ada perubahan di `pubspec.yaml` (dependency
baru) atau plugin native berubah. Untuk perubahan kode Dart murni, pakai cara di atas.
- Keamanan: jangan pernah simpan secret server (password DB, Supabase service_role key) di app — hanya `publishableKey` di `lib/config/supabase_config.dart`. Data dilindungi RLS per-user.

## Fastlane Upload ke Google Play

Upload AAB otomatis ke Google Play (flavor play) pakai fastlane:

```bash
fastlane play track:alpha      # upload ke track "Pengujian tertutup - Alpha"
fastlane play track:production # upload ke production (release)
```

Syarat:
- `fastlane/google-play.json` — service account key (`chatyuk-play-upload@chatyuk-7c9e4.iam.gserviceaccount.com`, project Firebase/GCP utama ChatYuk), JANGAN commit (sudah di `.gitignore`).
- Service account harus terdaftar di Play Console → Pengguna dan izin (izin: rilis ke produksi + rilis ke track pengujian).
- Google Play Android Developer API harus enabled di GCP project `chatyuk-7c9e4` (sudah aktif).

Catatan penting:
- **Wajib** bump `version: x.y.z+N` di `pubspec.yaml` sebelum upload (versionCode tidak boleh dipakai ulang).
- Setelah bump, jalankan `flutter clean` dulu agar `android/local.properties` (flutter.versionCode) ter-refresh.
- Track beta = "Pengujian tertutup - Alpha" (nama API-nya `alpha`, bukan `beta`).
- Keystore dibaca dari `android/key.properties` (bukan dari Fastfile).

### Guard Google Sign-In Play (WAJIB — insiden 2026-09-19)

Google Sign-In **gagal di build Play** (walau `apkpure` normal) karena 2 sebab.
Keduanya sekarang ada guard otomatis:

1. **`android/app/src/play/google-services.json` wajib project `chatyuk-7c9e4`**
   — pernah salah pakai project LAMA `chatyuk-8470e` → `google_app_id` di AAB
   = 990163663226 → Sign-In gagal. File ini **gitignored** → buat ulang dengan:
   ```bash
   bash scripts/setup_play_google_services.sh
   ```
   **Guard Gradle** (`android/app/build.gradle.kts`) menghentikan build kalau
   salah project (error `GUARD Firebase: ...`).

2. **SHA Play App Signing wajib terdaftar di Firebase project `chatyuk-7c9e4`**
   (AAB di-resign Google — SHA beda dari keystore upload). Lihat bagian
   "Fitur Khusus → Google Sign-In" untuk nilai SHA + cara verifikasi.

**Cek sebelum upload** (Fastfile `play`/`play_upload` menjalankannya otomatis):
```bash
bash scripts/check_google_signin.sh   # harus "SEMUA COCOK"
```
Skrip ini memverifikasi: SHA keystore cocok, **kedua** `google-services.json`
(`main` & `play`) memakai 7c9e4, dan `serverClientId` kode sinkron. Kalau gagal,
**JANGAN upload** — perbaiki dulu.

### Kebijakan versi — bump HANYA saat upload Google Play

**Jangan bump `version:` di `pubspec.yaml` untuk build biasa (install ke HP / distribusi APKPure).**
VersionCode hanya boleh dipakai ulang sekali untuk Google Play; kalau di-bump tiap build sesi, akan boros & bisa bentrok dengan versionCode yang sudah pernah di-upload.

Aturan:
- Build untuk **install ke HP / APKPure** → **tidak usah bump**. Pakai versi yang sedang aktif di `pubspec.yaml`.
- **Hanya sebelum `fastlane play track:...`** → bump `version:` lalu `flutter clean` → `flutter build appbundle --flavor play` → upload.
- Setelah upload, biarkan versi baru itu tetap aktif sampai upload berikutnya.

### Cara menentukan versi berikutnya (WAJIB — agar berurutan walau AI beda)

`pubspec.yaml` adalah **sumber kebenaran tunggal**. Format `version: X.Y.Z+N`:
- `X.Y.Z` = **versionName** (tampil ke user; di Play jadi `X.Y.Z-play`).
- `N` = **versionCode** (integer monoton naik, tidak boleh dipakai ulang).

Algoritma bump untuk upload Google Play — selalu jalankan urutan ini, TANPA mengira-ngira:

1. Baca `grep -n "^version:" pubspec.yaml` → dapat versi aktif, mis. `1.2.4+18`.
2. Cek versionCode terakhir yang benar-benar sudah di-upload ke Play:
   ```bash
   git log --all --format='%h %s' -- pubspec.yaml | head -20
   ```
   Cari commit paling atas yang mengandung `upload Google Play` → pastikan `N` aktif > versionCode commit itu. Kalau `N` aktif masih SAMA dengan yang sudah di-upload → WAJIB bump `N+1`.
3. Bump **keduanya** (jangan cuma salah satu):
   - versionCode: `N` → `N + 1` (selalu).
   - versionName: naikkan **minimal patch** `Z + 1` (mis. `1.2.4` → `1.2.5`), atau lebih tinggi kalau diminta. Jangan pernah turun.
4. Tulis ke `pubspec.yaml`, lalu `flutter clean` (agar `android/local.properties` ter-refresh), lalu build/upload.

Contoh berurutan yang benar:
```
1.2.3+17  (upload Play alpha)  → commit
1.2.4+18  (upload Play alpha)  → commit
1.2.5+19  (upload Play alpha)  → commit
```

Kalau ragu apakah suatu versionCode sudah terpakai di Play: **jangan dipakai**, ambil `N+1` dari versi aktif sekarang. Lebih aman naik 2 daripada bentrok di Play Console.

Catatan lintas-sesi: setelah upload selesai, **jangan** revert/bump `pubspec.yaml` lagi — biarkan versi terbaru tetap tertulis di file sebagai titik awal sesi AI berikutnya. Referensi versi Play terakhir selalu: `git log --oneline --all -- pubspec.yaml` (cari commit ber-keterangan "upload Google Play").

## Build & Push ke HP (WAJIB clean rebuild + push ke Downloads)

**Build WAJIB pakai `flutter clean` dulu** — build incremental sering tidak
memasukkan perubahan terbaru ke APK (sudah pernah terjadi: string baru tidak
masuk sampai di-clean). Selalu: `flutter clean` → `flutter build` → copy ke
`~/Downloads/chatyuk.apk` → push ke folder Downloads HP → user install manual
dari file manager (MIUI menolak `adb install`).

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
APK="build/app/outputs/flutter-apk/app-apkpure-release.apk"

flutter clean
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols

cp "$APK" "$HOME/Downloads/chatyuk.apk"

# Device wireless debugging (ganti IP:port sesuai `adb devices`):
for d in 192.168.18.242:42205 192.168.18.33:44607; do
  adb -s "$d" push "$HOME/Downloads/chatyuk.apk" /sdcard/Download/chatyuk.apk
done
```

Catatan:
- User install manual dari **File Manager → Download → `chatyuk.apk`**. Jangan
  pakai `adb install` — MIUI/Xiaomi menolak dengan `INSTALL_FAILED_USER_RESTRICTED`
  (kecuali user tap "Ijinkan" saat popup muncul, baru `adb install` sekali lagi).
- App lama di HP tidak otomatis ter-uninstall saat install APK baru — kalau
  butuh fresh, uninstall dulu dari HP atau jalankan `adb uninstall com.chatyuk.chatyuk`.
- `adb shell pm clear com.chatyuk.chatyuk` **tidak bisa** via wireless adb
  di MIUI (SecurityException). Cara bersih = uninstall → install fresh.
- Jika perlu launch dari adb: `adb -s <device> shell monkey -p com.chatyuk.chatyuk -c android.intent.category.LAUNCHER 1`
  (kalau monkey gagal, cek nama activity via `cmd package resolve-activity`).

## Upload ke Store (APKPure / Uptodown)

### ATURAN VERSI & BUILD APKPure (WAJIB)

**APKPure WAJIB merilis versi yang SAMA dengan versi yang sedang LIVE di
Google Play production saat itu** (versionCode identik). Jangan upload versi
lain/lebih tua/lebih baru untuk APKPure.

**APKPure WAJIB obfuscated** (`--obfuscate --split-debug-info=build/app/symbols`).

Langkah:
1. Cek versi Play production (harus == `version:` di `pubspec.yaml`):
   ```bash
   # via Play API (fastlane service account)
   ruby -e 'require "json";require "googleauth";require "google/apis/androidpublisher_v3";
   k=JSON.parse(File.read("fastlane/google-play.json"));
   a=Google::Auth::ServiceAccountCredentials.make_creds(json_key_io:StringIO.new(k.to_json),scope:"https://www.googleapis.com/auth/androidpublisher");
   s=Google::Apis::AndroidpublisherV3::AndroidPublisherService.new;s.authorization=a;
   e=s.insert_edit("com.chatyuk.chatyuk");t=s.get_edit_track("com.chatyuk.chatyuk",e.id,"production");
   puts (t.releases||[]).select{|r|r.status=="completed"}.flat_map{|r|r.version_codes||[]}.max;s.delete_edit("com.chatyuk.chatyuk",e.id)'
   ```
   Kalau beda → samakan `pubspec.yaml` ke versi Play (jangan build versi lain).
2. Build APK obfuscated:
   ```bash
   flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
     --obfuscate --split-debug-info=build/app/symbols
   ```
3. **GATE WAJIB** sebelum upload (menolak kalau salah keystore / non-obfuscate /
   versi beda dari Play / ada kode admin / salah flavor):
   ```bash
   ./scripts/check_release_apk.sh
   ```
   Harus "OK BERSIH". Kalau DITOLAK, JANGAN upload.

- Nama file APK output: `build/app/outputs/flutter-apk/app-apkpureprod-release.apk`
  (bukan `app-apkpure-release.apk`).

**Saat menulis deskripsi / "what's new" / changelog untuk upload ke store, JANGAN berbau dating / jasa pertemanan / transaksi.** Uptodown pernah menolak & men-banned ChatYuk karena deskripsi yang terlalu berbau dating ("meet new people", "nearby people finder", "filter gender") dan fitur koin/gift.

### DILARANG (frasa yang memicu penolakan):
- `meet new people` / `make new friends` (dalam konteks pencarian orang asing)
- `nearby people` / `location-based discovery` / `people finder`
- `filter by gender, age, city` / `find nearby users`
- `send coins and gifts to your favorite people` / `top up coins` / `withdraw`
- Kata `dating`, `match`, `profile browsing`, `flirt`

### DISARANKAN (ganti dengan framing chat & privasi):
- `chat with your friends, family, and communities`
- `join topic-based chat rooms`
- `share photos` / `photo sharing`
- `private and secure` / `built-in moderation and reporting tools`
- `online, idle, and offline status`

### Aturan tambahan:
- Deskripsi full body minimal 100 kata, short description maks 70 karakter.
- **Jangan upload versi yang LEBIH RENDAH dari versi terakhir** di Uptodown — setelah app di-reject, upload versi lebih rendah dianggap "circumvent review" → app BANNED. Kalau perlu versi baru, bump ke angka lebih tinggi.
- Kalau app di-reject: kirim ticket via "Contact Us" (kanan bawah console, https://www.uptodown.dev) minta alasan spesifik, perbaiki, baru submit ulang. Jangan submit ulang tanpa tahu alasan.
- Support Uptodown hanya menjawab dalam Bahasa Inggris atau Spanyol.

## Fitur Khusus

- **Screenshot toggle**: `app_settings.screenshot_enabled` (admin `zunixe@gmail.com`) → `ScreenSecureService`
- **Deep link**: `chatyuk://login-callback` → `lib/main.dart` `_handleDeepLink()`
- **Google Sign-In**: native `google_sign_in` + Supabase `signInWithIdToken`. JANGAN pakai OAuth client dari project `chatyuk.admin` (banned).
  - **WAJIB: build selalu ditandatangani `android/keystore/chatyuk-release-v2.jks`**
    (alias `chatyuk`, pass di atas). Error `"10, null, null"` saat login Google =
    **DEVELOPER_ERROR** → SHA-1 signing tidak terdaftar di Firebase project
    `chatyuk-7c9e4` untuk paket `com.chatyuk.chatyuk`.
  - **SHA-1 keystore aktif (v2):**
    `8C:CC:42:E3:FE:93:37:21:6C:E4:25:0E:2B:FC:CB:22:94:1E:50:A2`
    Cek kapan pun:
    ```bash
    keytool -list -v -keystore android/keystore/chatyuk-release-v2.jks \
      -alias chatyuk -storepass chatyuk2024secure | grep SHA1
    ```
  - SHA ini harus ada di Firebase Console → Project settings → Your apps →
    Android `com.chatyuk.chatyuk` → **SHA certificate hashes** (bersama Web
    client `599111437536-hg56...` sebagai serverClientId). Kalau keystore baru,
    daftarkan SHA barunya sebelum upload/rilis.
  - **SHA Play App Signing (PENTING untuk build `play`/AAB):** AAB yang
    di-upload ke Play **ditandatangani ULANG oleh Google** — SHA-nya BUKAN
    keystore upload kita. Kalau SHA Play ini tidak terdaftar di Firebase
    project `chatyuk-7c9e4` untuk paket `com.chatyuk.chatyuk`, Google Sign-In
    **gagal di versi Play** walau build `apkpure` (upload key) jalan normal.
    - SHA-1 Play App Signing: `7A:19:AF:A5:22:11:E9:AA:61:F5:8E:16:54:28:04:E8:32:EE:3C:B1`
    - SHA-256: `9778574b360e91f03c7e53b4a14dfdf4112d3b9a6c0b07d69886da60ac0d56ce`
    - Cara dapat: install app dari **Play** di HP → `adb pull` `base.apk` →
      `apksigner verify --print-certs base.apk | grep SHA-1`. Atau Play Console
      → Rilis → Penyiapan → Penandatanganan aplikasi → sertifikat penandatanganan aplikasi.
    - Daftarkan SHA-1 + SHA-256 ini di Firebase Console (project 7c9e4) →
      Android `com.chatyuk.chatyuk` → SHA certificate hashes.
  - **`google-services.json` flavor `play` WAJIB project `chatyuk-7c9e4`**
    (BUKAN project lama `chatyuk-8470e`). Pernah salah pakai 8470e →
    `google_app_id` di AAB = 990163663226 → Sign-In Play gagal. Cek:
    `bash scripts/check_google_signin.sh` (menolak project selain 7c9e4).
  - **DUA Android OAuth client WAJIB ada** (GCP hanya izinkan 1 SHA-1/client):
    | Client ID (project `599111437536` / 7c9e4) | Package | SHA-1 | Dipakai oleh |
    |---|---|---|---|
    | `…r1rb2m8pfko85lh1nu8ufdesiinv4cso` | `com.chatyuk.chatyuk` | `8C:CC:42:E3:…` (upload key) | APK **apkpure** (HP/APKPure) |
    | `…pc5vquunrmjoqvvq4hs5rpj2ec8tf26k` | `com.chatyuk.chatyuk` | `7A:19:AF:A5:…` (**Play App Signing**) | AAB **play** (Google Play) |
    | `…hg56bq0nc2m6kig6hg41lmrbtfel5n2c` | — | — | **Web** client = `serverClientId`/`aud` (dipakai kode) |
    - Nama di Console: `ChatYuk User Android` (upload) & `ChatYuk User Android (Play Signing)` (Play).
    - Kalau ada SHA baru (keystore baru / Play re-sign), **buat client Android baru**
      untuk SHA itu — jangan edit yang lama (bikin apkpure rusak).
    - **`serverClientId` di kode = Web client `hg56bq0n…`** (SAMA untuk apkpure & play).
    - Setelah tambah client baru → daftarkan juga di Supabase
      (`external_google_client_id`, comma-separated) untuk validasi `azp`.
  - **Client yang TIDAK dipakai (jangan dihidupkan):** `qsg6m4mr5mgakftvgn2apnb6r4u7bsq9`
    (ChatYuk Dev Android) & `20n1hrbddb85ubhg10j8e1urqs2h2ma3` (Admin Debug/probe —
    flavor `adminDev` sudah tidak pernah dibangun).
  - Kalau SHA & client sudah benar tapi device tetap `"10, null, null"`:
    cache Google Play Services di HP basi → hapus data Google Play Services
    (Setelan → Aplikasi → Google Play Services → Hapus data) lalu reboot HP.
  - **Error 400 saat `signInWithIdToken` (GoTrue v2.195.0+)** — GoTrue kini
    memvalidasi KEDUANYA: `aud` DAN `azp` idToken Google terhadap whitelist.
    Token dari Android punya `aud` = Web client dan `azp` = Android client,
    jadi keduanya WAJIB di-whitelist Supabase:
    - `external_google_client_id` (via Management API) = **kedua client
      comma-separated**: Web `599111437536-hg56bq0nc2m6kig6hg41lmrbtfel5n2c`
      + Android `599111437536-r1rb2m8pfko85lh1nu8ufdesiinv4cso`.
    - Diagnostic: pesan `Unacceptable audience in id_token` = `aud` tidak
      terdaftar; token valid tapi 400 "Internal Server Error" = azp/aud
      mismatch. Baca payload token dari logcat `[GOOGLE] idToken payload`.
    - **PENTING**: Management API PATCH `external_google_additional_client_ids`
      BUGGY (selalu gagal / malah menimpa `client_id`) — gunakan
      comma-separated di `external_google_client_id`.
    - Config dianggap "belum lengkap" kalau salah satu client hilang → semua
      device gagal login 400 secara berulang.
  - **Error `12500,null,null` saat login Google** = APK TIDAK ditandatangani
    keystore v2 (mis. build debug, atau build dibuat oleh tool/AI lain tanpa
    env `KEYSTORE_PASS`+`KEY_PASS` dan flag flavor yang benar). Firebase hanya
    mengenal SHA-1 keystore v2 → build "asal" langsung gagal sign-in. Solusi:
    build SELALU pakai prosedur "Build & Push ke HP" di bawah (release +
    `--flavor apkpure` + keystore v2), JANGAN pernah pakai `flutter build apk`
    tanpa flavor/keystore. Kalau build dari tool lain, verify cert APK
    (AGP kini sign v2-only → `keytool -printcert -jarfile` gagal
    "Not a signed jar file"; pakai apksigner):
    ```bash
    apksigner verify --print-certs app-apkpure-release.apk | grep 'SHA-256'
    # harus: 84e9639899edfa69da1ffd01514ec871d2b23f383f781f932f2f76c2be9fa4b2
    # (= SHA-256 keystore v2; SHA-1: 8C:CC:42:E3:...:50:A2)
    ```
  - **Account picker**: `auth_service.dart` memanggil `googleSignIn.signOut()`
    sebelum `signIn()` — JANGAN dihapus; tanpa itu picker tidak muncul dan
    login diam-diam pakai akun Google terakhir (keinginan user: selalu pilih
    akun tiap klik "Lanjutkan dengan Google").
