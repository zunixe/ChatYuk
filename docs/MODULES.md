# MODULES — tanggung jawab & aturan dependensi ChatYuk

> Kerangka awal (2026-10-10, dari audit read-only). Sumber kebenaran fitur tetap
> `FEATURE_MAP.md`; konvensi di `ARCHITECTURE_RULES.md`. Lengkapi bertahap, jangan
> duplikasi `FEATURE_MAP.md`.

## Aturan dependensi (enforced, gate diperluas 2026-10-10)

```
screens → providers → services → core (+ models, config, utils)
```

- `lib/screens/`, `lib/widgets/`, `lib/mixins/`: UI/kontrak saja, DILARANG import
  `services/` langsung. Semua I/O via `lib/providers/` (passthrough).
- `lib/core/`: helper murni, DILARANG import `services/` maupun `providers/`.
  Butuh I/O → inject dari luar (contoh: `PostPhotoCache.downloader` di-wire di
  `lib/main.dart`).
- Gate: `scripts/check_screen_boundary.sh` (CI). Pelanggaran saat ini = FAIL.

## Pelanggaran terdata (riwayat + status)

**STATUS 2026-10-10 (Fase B SELESAI): 0 pelanggaran.** Gate
`scripts/check_screen_boundary.sh` kini mencakup `screens/` + `widgets/` +
`mixins/` (dilarang `services/`) DAN `core/` (dilarang `services/` +
`providers/`). Semua temuan di bawah sudah ditutup:
- B1: `topup_provider`, `room_voice_provider` (baru), `describeReferrer` →
  `core/attribution_format.dart`, screen pakai provider.
- B2: `message_cache` predikat path DIINJEKSI (`MessageCache.isStoragePath`
  di main.dart), `guardOfflineCtx` → `connectivity_provider.dart`,
  `core/storage_paths.dart` (murni), user_info → `avatarProvider`.
- B3: 16 widget + 3 mixin → provider; helper `service_locator.dart`
  (`safeAvatar`/`safeStorage`) untuk widget yang di-mount tanpa ProviderScope.

Riwayat temuan (sudah diperbaiki, disimpan sebagai catatan):

| Lokasi | Import terlarang | Perbaikan |
|---|---|---|
| `screens/room_chat_screen.dart:42`, `screens/room_chat/widgets/voice_stage_strip.dart:4`, `screens/room_chat/widgets/voice_diagnostics_sheet.dart:5` | `room_voice_service.dart` | ✅ `room_voice_provider` |
| `screens/user_info_screen.dart:17-18` (+ `screens/user_info/user_info_init.dart:27`) | `storage_photo_service`, `avatar_service` | ✅ `avatarProvider` + `core/storage_paths.dart` |
| `screens/admin_attribution_tab.dart:10` | `attribution_service` | ✅ `core/attribution_format.dart` |
| `screens/point_history/widgets/topup_sheet.dart:5-6` | `points_service`, `topup_service` | ✅ `topup_provider` + passthrough |
| `core/cache/message_cache.dart:8` | `storage_photo_service` | ✅ injeksi `MessageCache.isStoragePath` |
| `core/admin_err.dart:5,8` | `flutter_riverpod`, `connectivity_provider` | ✅ `guardOfflineCtx` → provider |
| `widgets/` 16 hits | berbagai service | ✅ semua → provider |
| `mixins/` 3 hits | storage/reaction service | ✅ `storageProvider`/`messageReactionProvider` |

## Struktur lapisan (aktual)

- `screens/` (61 file): UI saja. Acuan private↔room = `private_chat_screen.dart`
  (3117 baris — god-screen, JANGAN tambah tanggung jawab baru di sini).
- `providers/riverpod/` (29 file): passthrough + state. Hotspot:
  `locale_provider` (~140 importir), `auth_provider` (~51), `admin_provider` (~35).
- `services/` (48 file): satu-satunya I/O. Pola `part`+`mixin` satu entry:
  `chat_service.dart` + 6 part, `auth_service.dart` + 3 part,
  `admin_service.dart` + 3 part, `call/call_session.dart` + 3 part.
- `core/`: `cache/` (message_store, message_cache, photo_cache,
  post_photo_cache, media_disk_cache, offline_outbox, crypto_native),
  `media/` (chat_photo_helper, forensic_watermark, native_image, ...),
  `chat/`, `call/`, `perf/`, `ui/`, + `admin_gate`, `nav_guard`,
  `screen_secure_service`.
- `mixins/` (5): `chat_outbox_mixin`, `chat_selection_mixin`,
  `chat_send_mixin`, `chat_photo_send_mixin`, `voice_recorder_mixin` — dipakai
  kedua chat screen via `with`. Jangan copy-paste private↔room lagi.
- `widgets/` (60+): bersama; `chat_composer_input.dart` (`ChatComposerInput`)
  contoh baik (reuse, bukan duplikat).
- `models/` (9), `config/` (15: `strings.dart` 4167 + `strings_admin.dart` 1519
  = data i18n, bukan logic).

## Modul tanpa provider (tight coupling — SELESAI)

- ~~`room_voice`~~ → `room_voice_provider` (B1).
- ~~`topup_service`~~ → `topup_provider` (B1).
- ~~`attribution_service`~~ (bagian murni) → `core/attribution_format.dart` (B1).

## Keputusan terbuka

- Gate `widgets/`+`mixins/` diperluas (2026-10-10) DAN berlaku sekarang: UI
  non-screen wajib passthrough provider. Helper murni tanpa I/O → `core/`
  (mis. `storage_paths.dart`, `attribution_format.dart`). Inject dari
  composition root bila butuh service tanpa import: `MessageCache.isStoragePath`,
  `VoicePrefetch.downloader` (pola sama `PostPhotoCache.downloader`).
- Widget yang mungkin di-mount tanpa `ProviderScope` (unit test murni/preview)
  pakai `providers/riverpod/service_locator.dart` (`safeAvatar`/`safeStorage`/
  `safeReactions`/`safeRead`) — baca provider bila scope ada, fallback singleton.
