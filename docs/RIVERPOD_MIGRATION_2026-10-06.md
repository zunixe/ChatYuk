# Migrasi Provider → Riverpod — 2026-10-06 (Mac, lanjut di laptop lain)

Lanjutan dari Fase 1d/1e (2026-10-05). Pola: strangler — `ProviderScope` +
`MultiProvider` hidup bareng; global = `NotifierProvider` tanpa `autoDispose`;
action-only = `Provider`. `flutter_riverpod: ^2.6.1` (v3 butuh Dart ^3.12).

## Commit hari ini (10, branch `develop`)

| Commit | Fase | Isi |
|---|---|---|
| `87089dd` | 1f | SocialProvider → `SocialNotifier` (14 call-site) |
| `1f105c8` | 1g | OnlineUsersProvider → `OnlineUsersNotifier` (6 call-site) |
| `8f8ba26` | 1h | StoryProvider → `StoryNotifier` (6 call-site) |
| `0c01dac` | 1i | TimelineProvider → `TimelineNotifier` (7 call-site) |
| `b68f642` | 1j | RoomProvider → `RoomNotifier` (12 call-site) |
| `5699aaa` | 1k | PointsProvider → `PointsNotifier` (22 call-site, terbesar) |
| `c727572` | 1l | ChatProvider → `ChatNotifier` (18 call-site, alias lawan tabrakan nama) |
| `39d69fb` | 1m | CallProvider → `CallNotifier` (singleton `.instance` → container/rootContainer) |
| `dc2b472` | 1n | AuthProvider → `AuthNotifier` + `AuthData` (45 file, terbesar) |
| `585ff8f` | fix | `_emit` isi uid/sesi/flags (regresi: list chat hilang + bubble kiri semua) |

File baru: `lib/providers/riverpod/{social,online_users,story,timeline,room,points,chat,call,auth}_provider.dart`.
File lama (`lib/providers/*_provider.dart`) BELUM dihapus — masih dipakai test
unit lama. Hapus di akhir migrasi (sesudah Locale/Theme/Admin).

## Selesai (lanjutan sesi 2026-10-07, Windows)

1. **LocaleProvider** — `riverpod/locale_provider.dart` + mirror `AppLocale`
   (untuk `main.dart` non-widget). 119 file lib dikonversi; 58 kelas widget →
   Consumer. Test lama (42 file) migrasi off `LocaleProvider`/`ThemeProvider`.
2. **ThemeProvider** — `riverpod/theme_provider.dart` di-wire; 41 file lib.
3. **AdminProvider** — tetap kelas ChangeNotifier besar, tapi kini dikelola
   Riverpod (`riverpod/admin_provider.dart` = `ChangeNotifierProvider`).
   `AdminGate.extraProviders` dihapus.
4. **Cleanup tuntas:**
   - 9 file provider lama DIHAPUS: auth, chat, social, points, story,
     timeline, room, online_users, call (+ locale, theme).
   - `admin_provider.dart` + `lib/providers/admin/` tetap (kelas utama).
   - **Dependency `provider` DIHAPUS dari `pubspec.yaml`.** Tidak ada lagi
     `package:provider` di `lib/` maupun `test/`.
   - `lib/providers/` tinggal `admin_provider.dart` (kelas) + `riverpod/`.

## Test

- `flutter analyze` (seluruh project) → **0 error / 0 warning**.
- Full `flutter test` → **1800 lulus / 0 gagal (100% hijau)**.
- Fix test legacy: `new_providers`, `passthrough_providers`, `storage_provider`,
  `story_viewer_avatar`, `my_status_sheet`, `privacy_*`, `providers_test`,
  `settings_account`, `points/room/timeline/story/chat/social/online_users`
  provider tests, `flow_*`, `auth_login_flow`, `post_*`, `user_info_seed`, dll.
- `storage_paths`: `StoragePhotoService._stamp()` (counter monotonik) — cap
  microsecond tak unik di Windows.
- 2 test `story_provider`: TTL gate 45 dtk → tambah `debugResetTrayTtl()`.
- Pola test: `ProviderContainer` + `UncontrolledProviderScope` +
  `TestXxx extends XxxNotifier` (build override hermetic); listener via
  `container.listen(provider, ...)`; dispose container di dalam test body bila
  ada timer pending.


## Insiden hari ini

1. **List chat hilang + bubble kiri semua** (build 07:49): `_emit` Auth tidak
   mengisi field baru (script replace gagal diam-diam) → `uid` null.
   Pelajaran: tiap generate-notifier via script, verifikasi `_emit` mengisi
   SEMUA field state. Fix `585ff8f`, verified di HP.
2. **Typing lag: app utama vs ChatYuk Dev** (investigasi terbuka):
   - Gradle BUKAN penyebab: flavor beda appId/nama saja; `profile` tanpa
     minify/shrink. Kedua APK profile → konfigurasi identik.
   - Dev terpasang = build 2026-10-05 21:13 (Fase 1d/1e) + signature debug
     key (tak bisa ditimpa tanpa uninstall). Kemungkinan: kode lama, backend
     lokal (`run_dev.sh` → Supabase local), atau akun/data beda.
   - Ukuran data mirip (app_flutter 135M vs 146M). `gfxinfo`: jank sedikit,
     tapi `High input latency: 141` vs 14.
   - Belum selesai: bandingkan apel-vs-apel (dev build kode-sekarang) atau
     ukur saat mengetik.

## Build terpasang di HP (Xiaomi 24129PN74G, `192.168.18.72:37421`)

- `com.chatyuk.chatyuk` v1.2.70 profile (keystore v2, SHA-1 `8ccc42e3…`):
  `~/Downloads/chatyuk_profile.apk`. Fase 1n + fix.
- `com.chatyuk.chatyuk.dev` v1.2.70-dev = build lama 2026-10-05 (debug key).

## Yang TIDAK ikut commit (milik sesi paralel, tetap di tree Mac ini)

- `docs/MIGRATION_LOG.md` (modifikasi call billing)
- `lib/providers/points_provider.dart` (guard billing)
- `supabase/migrations/20261006200000_call_billing_master_toggle.sql`
- `supabase/tests/call_billing_toggle_test.sql`


---

# Optimasi Memori � "sama kaya WhatsApp" (2026-10-07, Windows)

Keluhan: private chat "ngetik ngelag / freeze lalu kedelte semua" di HP.

## Diagnosa (terukur `dumpsys meminfo` + `PerfProbe` di device)

- **Render SEHAT**: `frames=686 build[p50=1.7 p90=4.5 max=20.1ms] janky=2`. Bukan
  rebuild UI/Riverpod (list/composer TIDAK rebuild per-ketikan).
- **Swap = biang**: ChatYuk `SwapPss 58�134MB`, Native heap reserved **~541MB**
  (used cuma ~55MB). vs WhatsApp: `SwapPss 5.7MB`, native heap **96MB**.
  ? engine Flutter/Dart menahan arena besar (base64+bytes hidup di heap Dart,
  disalin lintas isolate); proses di-swap; saat ngetik, page ter-swap di-fault
  balik = stall ? karakter muncul borongan.
- Kontaminasi: build **profile** menyalakan semua `dlog` (`kDebugMode||kProfileMode`)
  ? overhead. RILIS membuang `dlog`.

## Fase A � Tuning Dart (tanpa native)

- **A1** Hapus `dlog` hot-path: `[ONLINE-EMIT]` (presence), `[TYPING]`, `[PHOTO-DBG]`,
  `[AVATAR]` verbose, `[prefetch]`. (Sisakan log error.)
- **A2** Trim agresif: saat composer fokus + memory-pressure + background ? buang
  `PhotoCache`/`PostPhotoCache`/`decodedImageCache`/Flutter `imageCache`
  (`ImageCacheHygiene.clearAll` sudah meng-cover app-cache terdaftar).
- **A3** Retensi: `ChatStreamSession._maxMessages` 300?150?**100**;
  `_decodedCacheMax` 16?**12**; `imageCache` 80/48MB?**60/24MB**.

## Fase B � Native image pipeline (Kotlin, MethodChannel)

- **B0�B2** `android/.../image/ImageBridge.kt`, channel
  `com.chatyuk.chatyuk/image`, dijalankan di **executor background** +
  **`LruCache` native 24MB** (bytes gambar tak hidup di Dart heap � kunci
  kenapa WA stabil). Metode: `aspectRatio`, `decodeThumb`, `decodeAvatar`,
  `decodeBytes`, `decodeWithDims`, `processJpeg`.
- **Fallback transparan**: `lib/core/media/native_image.dart` (`NativeImage`)
  jatuh ke `compute`+`package:image` bila channel tak ada (unit test/PC/
  kegagalan native). Semua jalur Dart lama tetap ada.
- **B3** Call-site dimigrasi: avatar (`user_avatar`, `profile_avatar`,
  `leaderboard_screen`, `post_card`), thumbnail (`async_photo`), bubble+viewer
  chat (`private_chat_message`), proses-kirim foto (`chat_photo_send_mixin`).
  View-once **watermark tetap Dart** (algoritma embed belum di native).

## Hasil (device release, 2026-10-07)

| Metrik | Sebelum | Sesudah A+B |
|---|---|---|
| SwapPss (user) | 58�134 MB | **175 KB** |
| Native heap reserved | ~541 MB | **62 MB** |
| analyze (lib+test) | 0/0 | **0/0** |
| flutter test | 1800 hijau | **1808 hijau** |

Gate terpenuhi: SwapPss < 20MB, Native heap < 150MB. Build release user+admin
terpasang & jalan (tanpa crash / MissingPlugin pada channel image).

Catatan: pengukuran "sesudah" di device berbeda (192.168.18.72) yang tidak
sedang tertekan swap � angka "sebelum" dari device lama (192.168.137.215).
