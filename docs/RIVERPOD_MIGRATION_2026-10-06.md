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

## Sisa (belum migrasi)

1. **LocaleProvider** (121 file, 166 watch) — mekanis, codemod di akhir.
2. **ThemeProvider** (45 file; `riverpod/theme_provider.dart` sudah ada tapi belum di-wire).
3. **AdminProvider** + `lib/providers/admin/`.
4. Hapus file provider lama + rapikan test yang masih import path lama.

## Test

- `dart analyze lib/` → 0 error (setelah tiap fase).
- Full `flutter test`: **12 gagal pra-ada** (test masih import provider lama
  yang file-nya dihapus fase 1d: privacy/avatar/nav/storage/dll + 2 flaky
  `story_provider_test`). Bukan dari migrasi ini.
- Pola test widget baru: `ProviderContainer` + `UncontrolledProviderScope` +
  `TestXxx extends XxxNotifier` (build override hermetic). PENTING: kalau kode
  baca **getter notifier langsung** (bukan state), override juga getter-nya
  (kasus `TestAuth.profile/uid` di `chat_send_flow_test`).

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
