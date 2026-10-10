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

## Pelanggaran terdata (TODO perbaiki, satu grup per commit)

| Lokasi | Import terlarang | Perbaikan |
|---|---|---|
| `screens/room_chat_screen.dart:42`, `screens/room_chat/widgets/voice_stage_strip.dart:4`, `screens/room_chat/widgets/voice_diagnostics_sheet.dart:5` | `room_voice_service.dart` | TODO: `room_voice_provider` baru |
| `screens/user_info_screen.dart:17-18` (+ `screens/user_info/user_info_init.dart:27`) | `storage_photo_service`, `avatar_service` | TODO: passthrough `storage_provider`/`avatar_provider` |
| `screens/admin_attribution_tab.dart:10` | `attribution_service` | TODO: `attribution_provider` baru |
| `screens/point_history/widgets/topup_sheet.dart:5-6` | `points_service`, `topup_service` | TODO: passthrough provider + `topup_provider` |
| `core/cache/message_cache.dart:8` (dipakai `:434-435`) | `storage_photo_service` | TODO: injeksi fungsi `isPath`/`isVoicePath` |
| `core/admin_err.dart:5,8` (dipakai `:104-105`) | `flutter_riverpod`, `connectivity_provider` | TODO: callback, bukan import provider |
| `widgets/` 16 hits (`profile_avatar`, `person_avatar`, `comment_avatar`, `author_avatar`, `leaderboard_sheet` → avatar; `voice_bubble`, `chat_video_bubble`, `message_image`, `view_once_image` → storage; `chat_call_overlay`, `admin_call_watch_overlay`, `reaction_detail_sheet`, `location_picker_sheet`) | berbagai service | TODO: putuskan per widget — passthrough provider atau props |
| `mixins/` 3 hits (`chat_outbox_mixin:12`, `chat_photo_send_mixin:18`, `chat_selection_mixin:14`) | storage/reaction service | TODO: injeksi via kontrak mixin |

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

## Modul tanpa provider (tight coupling — TODO)

- `room_voice` (`RoomVoiceSession extends ChangeNotifier` di service,
  diinstansiasi screen langsung), `topup_service`, `attribution_service`.

## Keputusan terbuka

- Apakah `widgets/`/`mixins/` yang import `services/` dikecualikan tertulis atau
  wajib passthrough semua? (Keputusan 2026-10-10: wajib passthrough — tabel di
  atas adalah backlog-nya.)
