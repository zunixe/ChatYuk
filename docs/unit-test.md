# Unit Test ChatYuk

## Kapan dipakai

1. **Sebelum commit** — `flutter test` + `flutter analyze` harus hijau
   (0 error, 0 warning). `strings_test` sengaja digagalkan duluan kalau ada
   hardcode Indonesia / `fontSize` numerik / `height` manual.
2. **Sesudah ubah kode** — ubah model/provider/utils → jalankan file test
   terkait dulu (`flutter test test/models_test.dart`), baru full suite.
3. **Saat refactor** — `MessageModel`, `PrivateChatInfo`, `rt_resilient`,
   `MessageStore` dikunci test (roundtrip, trim 500, backoff). Test merah =
   refactor merusak.
4. **CI / sesi AI berikutnya** — jaring pengaman lintas-sesi: pelanggaran
   bilingual/tipografi ketahuan tanpa harus baca AGENTS.md.

## Perintah

```bash
flutter test                              # full suite
flutter test test/models_test.dart        # per-file saat iterasi cepat
flutter test --coverage                   # + gate CI: providers/services/models >= 60%
flutter analyze                           # 0 error, 0 warning
```

## Isi test

| File | Yang dikunci |
|---|---|
| `strings_test.dart` | bilingual `strings.dart`, tanpa hardcode ID di `Text`/`tooltip`, tanpa `fontSize`/`height` manual di luar `lib/config` |
| `widget_test.dart` | token `AppText`/`AppGlyph`/`StoryText`, `AdminGate.isRealAdmin` |
| `providers_test.dart` | `NavProvider`, `LocaleProvider`, `ThemeProvider` |
| `models_test.dart` | privasi hapus `MessageModel`, default `User/Room/Story`, `PrivateChatInfo` |
| `mention_test.dart` | parsing mention (token aktif, filter kandidat, `@all` gating, boundary nama berspasi), `MessageModel.mentions` + `OutboxEntry.mentions` round-trip & privasi hapus |
| `mention_widget_test.dart` | `mentionAwareSpans` (highlight mention vs `@all` global-room, URL tak tumpang tindih), `MentionAwareText`, panel `MentionAutocomplete` (sisip `@Nama`, caret, allowAll) |
| `notification_prefs_service_test.dart` | gate `shouldShowForFcmType('mention')` ikut `chat`, master switch, mute per-chat |
| `utils_test.dart` | `BoundedCache`, `snakeToCamel`, `formatBytes`, `formatMmSs`, `dateChipLabel` |
| `utils_extra_test.dart` | `parseDate`, `isValidEmail`, `isValidNickname`, `normalizeNicknameForBan`, `colorHashForUid`, `formatBubbleTime`, `formatTime`, `isValidImageBase64` |
| `models_extra_test.dart` | `ActiveCallInfo` (fromJson/elapsed clamp), `UserPhoto.fromMap`, `LegalSection`, `giftById` + katalog gift (id unik, harga positif) |
| `widgets_extra_test.dart` | `RoomIcon` (kategori vs fallback emoji), `ReplyQuote` (guard privasi terhapus), `StoryTextOverlay` (clamp x/y/scale, colorIndex out-of-range) |
| `connectivity_provider_test.dart` | fake platform connectivity: awal dari `checkConnectivity`, event none/online, dedup notify, dispose |
| `social_provider_test.dart` | state set sosial kosong, getter unmodifiable, guard logout (tanpa sesi), `clearAnonSocial` |
| `services_extra_test.dart` | `LinkPreviewService.extractUrl`, `PerfProbe` mode off (timed passthrough, counter 0, tab no-op) |
| `chat/timeline_provider_test.dart` | delegasi pin/mute/archive, offline-safe feed, passthrough `mentions` |
| `message_store_test.dart` | roundtrip, window terbaru, trim 500, kv |
| `rt_resilient_test.dart` | retry/backoff/cancel/dispose |
| `auth_room_di_test.dart` | DI `AuthProvider`/`RoomProvider` (injeksi service + skip autoInit), state awal |
| `flow_chat_test.dart` | alur kritis: pin dari daftar → service 1× (hermetic, ikut CI) |
| `flow_points_test.dart` | alur kritis: klaim online 5 mnt dari UI → service 1× |
| `flow_story_test.dart` | alur kritis: refresh tray → 1 author tampil |
| `widgets/call_overlay_test.dart` | smoke mount widget |
| `chat_service_io_test.dart` | `ChatService` (room msg/delete/edit) — `SupabaseClient` asli + HTTP palsu, assert payload PostgREST |
| `points_service_io_test.dart` | `PointsService` — nama RPC + params (`one_time_bonus`, `claim_weekly_quest`, `unlock_photo`, `points_leaderboard` incl. paginasi) |
| `story_social_io_test.dart` | `StoryService` (`create_story`, `mark_story_seen_bulk`) + `SocialService` (`follow_user`, `respond_friend_request`, `clear_anon_social`) |
| `economy_room_io_test.dart` | `send_coins`/`send_gift`, `mark_chat_read`, `pin`/`mute_private_chat`, `create`/`join_private_room` |

## Integration / E2E — BELUM ADA (dan alasannya)

**Tidak ada** integration test device. `integration_test/` hanya berisi README;
`IntegrationTestWidgetsFlutterBinding` nol pemakaian; dev-dep `integration_test`
sudah dihapus dari `pubspec.yaml` (merusak build rilis:
`GeneratedPluginRegistrant.java` release menyertakan plugin yang tak ada di
Gradle release → `package dev.flutter.plugins.integration_test does not exist`).
Juga tidak ada Patrol/Maestro/test_driver, dan CI tanpa emulator.

**Gantinya (4 lapis):**

1. **Widget hermetic** — `test/flow_{chat,points,story}_test.dart`.
2. **Semi-integrasi I/O** — `*_io_test.dart` + `supabase_test_client.dart`:
   `SupabaseClient` asli + `MockClient` → nama RPC & payload PostgREST teruji
   tanpa jaringan. Helper `rpcRequestOf`/`rpcParamsOf` untuk assert params.
3. **DB integrasi** — `supabase/tests/*.sql` (transaksional, rollback).
4. **Manual device** — `scripts/stress/*` + `docs/STRESS_TEST.md` Lapis 4.

Yang **belum** terkunci otomatis: login Google native, kirim chat sungguhan,
WebRTC call, publish story. Jalur itu hanya divalidasi manual di HP.
Kalau suatu saat butuh E2E: runner harus punya emulator + flavor `dev`
memerlukan `google-services.json` sendiri (sekarang belum ada).

## Test SQL (Lapis 3)

Invariant DB di `supabase/tests/*.sql` (transaksional, `BEGIN`/`ROLLBACK` —
tidak menyentuh data produksi). Jalankan: `bash scripts/run_sql_tests.sh`
(atau `bash scripts/run_sql_tests.sh mention_test.sql` untuk satu file).
Dijalankan CI di job `sql-tests`.

| File | Yang dikunci |
|---|---|
| `schema_sync_test.sql` | kolom/RPC anti-regresi (mute/archive, gift, room mute, dummy kind, reaksi) |
| `notif_chat_test.sql` | `notify_private_message`/`call_push`/`handle_new_private_message` |
| `contract_test.sql` | kontrak Edge↔DB (wallet, forward, AI, presence, `dummy_uids`) |
| `mention_test.sql` | kolom `mentions` (jsonb, default `[]`) + `notify_mention_room()` & trigger `type=mention`/`toUid` |
| `call_test.sql` | `calls`/`call_signals` + kolom heartbeat/notif, index, RPC call, RLS, cron `chatyuk-call-sweep`, perilaku `admin_sweep_calls()` |

> Job CI `sql-contract` hanya berjalan bila repo punya secret
> `SUPABASE_ACCESS_TOKEN` + variable `SUPABASE_PROJECT_REF`. Kalau belum
> diset, jalankan manual: `bash scripts/run_sql_tests.sh`.

Kontrak Edge murni (`send-push`/`fanout`) dikunci `deno test
supabase/functions/_shared/` — termasuk `SEND_PUSH_DATA_ONLY_TYPES` yang wajib
memuat `mention`, `call`, `call_ended`, dst.

## Batasan

`AuthProvider`/`RoomProvider` sudah DI-ready (`{authService/service/chatService,
autoInit}`) dan dikunci `auth_room_di_test.dart` untuk konstruksi + state
awal. Logika dalam `_init`/`_listenAuthState`/subscription realtime belum
di-unit-test — butuh fake stream + `fake_async` sebelum bisa dikunci penuh.
`PointsProvider` sudah DI (`{service}`) + `points_provider_test.dart`.

Belum ada test (butuh refactor ringan agar testable — service memakai `http.get`
top-level / plugin native secara langsung):
- `geo_service.dart` — parsing provider IP & mapping `_countryNames` butuh
  injeksi `http.Client` (sekarang panggilan global). Network live tidak diuji.
- `push_topic_service.dart` — `FirebaseMessaging` plugin native; error ditelan
  senyap, jadi rendah nilai tanpa fake plugin.
- `admin_provider.dart` — paging & TTL detail; butuh DI `AdminService`.
- Screen kompleks (`room_chat_screen`, `private_chat_screen`, dll) — belum
  di-smoke-test; mengandalkan test provider/model + test alur kritis.
