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
| `mixins/chat_selection_logic_test.dart` | seleksi pesan: toggle/long-press (tolak terhapus & pending), clear, single, edit↔balas eksklusif, cancel |
| `mixins/chat_outbox_flow_test.dart` | antrean offline: simpan ke disk, guard flush ganda, offline skip, error permanen dibuang |
| `mixins/voice_recorder_logic_test.dart` | state machine voice: timer naik + sinyal, auto-stop 59s, lock, cancel reset, stop saat tak merekam = no-op |
| `call_watch_service_test.dart` | `WatchSession` peserta (caller+callee), `WatchParticipant` default, `ActiveCallInfo` elapsed clamp |
| `widgets_session_changes_test.dart` | `ProfileAvatar` (default `avatarBg`, inisial, badge), `AsyncCircleAvatar` fallback, `ReplyQuote` privasi terhapus |
| `config_core_test.dart` | `SecureSessionStorage` kontrak, `ScreenSecureService` prioritas (viewOnce>donasi>admin), `CallConfig` fallback ICE |
| `strings_test.dart` | bilingual `strings.dart`, tanpa hardcode ID di `Text`/`tooltip`, tanpa `fontSize`/`height` manual di luar `lib/config` |
| `widget_test.dart` | token `AppText`/`AppGlyph`/`StoryText`, `AdminGate.isRealAdmin`, `AppTheme.statusColor`, `avatarBg` opaque |
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
| `privacy_service_io_test.dart` | `PrivacyService` — nama RPC + params (`my_privacy_settings`, `update_privacy_settings` 6 param snake_case, `replace_privacy_exclusions` `p_uids` List, `privacy_friends` + guard tanpa sesi/error) |
| `privacy_widget_test.dart` | `PrivacySettingsScreen` — `load()` 1×, sheet 4 opsi visibility, pilih value → `update()`, alur `except` → picker teman → `updateExclusions()`, empty state, switch read-receipts |

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

## Functional test (`test/functional/`)

Alur nyata dari sisi UI/provider — hermetic (tanpa network/plugin), jalan di CI.
Mount widget PRODUKSI (bukan dummy tombol) lalu verifikasi perilaku.

| File | Alur |
|---|---|
| `composer_send_flow_test.dart` | composer nyata: ketik → tombol kirim → `onSend` 1×; chip attach (foto/view-once/koin/gift) memanggil callback tepat; chip koin tersembunyi saat poin OFF |
| `composer_mention_flow_test.dart` | ketik `@bud` → panel kandidat → pilih → teks `@Budi ` + caret; spasi menutup panel |
| `bubble_swipe_reply_flow_test.dart` | bubble nyata: drag ≥48px → balas; <48px batal; pesan sendiri tanpa aksi |
| `reaction_bar_flow_test.dart` | `ReactionBar`: tap emoji → `onReact(emoji)`; semua emoji bisa ditap; `⋯` → `onMore` |
| `entry_form_flow_test.dart` | `ProfileFormCard`: ketik nickname, submit, tombol disabled saat loading |
| `chat_send_mentions_io_test.dart` | `ChatProvider` → `ChatService` (HTTP palsu): payload `mentions` benar; tanpa mention kolom absen |

## Regression test (`test/regression/`)

Mengunci insiden NYATA yang pernah terjadi. Tiap test sudah diuji-negatif
(di-`revert` bug-nya → test GAGAL), jadi bukan test hampa.

| File | Regresi yang dikunci |
|---|---|
| `r_read_receipt_test.dart` | Read-receipt monoton maju (null/tua tidak mundur) + batas inklusif `<=` (dulu `isBefore` ketat → centang-2 telat) |
| `r_swipe_reply_test.dart` | `SwipeToReply` wajib publik; `enabled=false` → `child` apa adanya; ambang 48px; hanya geser kanan |
| `r_auth_sensitive_cols_test.dart` | `registerProfile` upsert TANPA email/fcm/ip (anti `42501`); kolom sensitif via `PATCH` terpisah |
| `r_settings_no_stream_test.dart` | `watchGlobalSettings`/`watchEnabled` TIDAK pakai `.stream()` (`.stream()` selalu `SELECT *` → sentuh `app_shared_secret` → 42501 + retry tanpa henti) |
| `r_stream_replay_test.dart` | `ChatStreamSession` me-replay snapshot ke listener yang datang belakangan (dulu: layar kosong dulu) |
| `r_build_deps_test.dart` | `pubspec.yaml` tanpa dev-dep `integration_test` (dulu bikin build release gagal) |
| `supabase/tests/regression_test.sql` | `fn_archive_deleted_user` `coalesce(is_registered)`; hardening profiles tanpa SELECT level-tabel; trigger mention; `ai_always_online` di presence tick; `_social_registered_guard` menangani `friend_requests` (`from_id`/`to_id`) |

### Refactor pendukung (2a)
`lib/core/chat/read_receipt.dart` — logika read-receipt dipindah dari screen
ke helper MURNI agar bisa diuji. `private_chat_screen.dart` memakainya
(perilaku identik).

## Test SQL (Lapis 3)

Invariant DB di `supabase/tests/*.sql` (transaksional, `BEGIN`/`ROLLBACK` —
tidak menyentuh data produksi). Jalankan: `bash scripts/run_sql_tests.sh`
(atau `bash scripts/run_sql_tests.sh mention_test.sql` untuk satu file).
Dijalankan CI di job `sql-tests`.

| File | Yang dikunci |
|---|---|
| `regression_test.sql` | insiden nyata: `fn_archive_deleted_user` null-fix, hardening profiles, trigger mention, `ai_always_online`, guard `friend_requests` |
| `schema_sync_test.sql` | kolom/RPC anti-regresi (mute/archive, gift, room mute, dummy kind, reaksi) |
| `notif_chat_test.sql` | `notify_private_message`/`call_push`/`handle_new_private_message` |
| `contract_test.sql` | kontrak Edge↔DB (wallet, forward, AI, presence, `dummy_uids`) |
| `mention_test.sql` | kolom `mentions` (jsonb, default `[]`) + `notify_mention_room()` & trigger `type=mention`/`toUid` |
| `call_test.sql` | `calls`/`call_signals` + kolom heartbeat/notif, index, RPC call, RLS, cron `chatyuk-call-sweep`, perilaku `admin_sweep_calls()` |
| `privacy_test.sql` | perilaku `_are_friends()` & `privacy_can_view()` per visibility (`everyone`/`friends`/`except`/`nobody`, owner=viewer, viewer null, field tak dikenal); masking `profile_public()`; RPC `auth.uid()` via `set_config('request.jwt.claims')`; kontrak `mark_chat_read`/`get_online_users` + grant role |

> Job CI `sql-contract` hanya berjalan bila repo punya secret
> `SUPABASE_ACCESS_TOKEN` + variable `SUPABASE_PROJECT_REF`. Kalau belum
> diset, jalankan manual: `bash scripts/run_sql_tests.sh`.

Kontrak Edge murni (`send-push`/`fanout`) dikunci `deno test
supabase/functions/_shared/` — termasuk `SEND_PUSH_DATA_ONLY_TYPES` yang wajib
memuat `mention`, `call`, `call_ended`, dst.

## Edge function — `_shared/` (Deno)

```bash
deno test --allow-read --allow-env supabase/functions/_shared/
```

| File | Yang dikunci |
|---|---|
| `ai-helpers.test.ts` | 36+ fungsi AI murni: sanitize (kapitalisasi/fenced-code), cap emoji/kalimat/baris, hasWord boundary, isExplicit/isInsult, tidur/WIB, mermaid/chart, mood/image marker, flux URL |
| `auth.test.ts` | gerbang keamanan semua endpoint: `checkAppSecret` (fail-closed saat env kosong), `isServiceRoleJwt` (role benar/salah/token rusak), `unauthorized` 401 |
| `edge-contract.test.ts` | sinkron `dataOnlyTypes` send-push + topic fanout |

> **PENTING (anti-drift):** helper AI adalah **satu sumber** di
> `_shared/ai-helpers.ts` yang **diimpor** `ai-reply/index.ts`. JANGAN menyalin
> balik ke index.ts — dulu salinan manual itu tertinggal (sanitize 40 vs 95
> baris) sehingga test menguji kode yang bukan produksi. Lihat header file.

## Batasan

`AuthProvider`/`RoomProvider` sudah DI-ready (`{authService/service/chatService,
autoInit}`) dan dikunci `auth_room_di_test.dart` untuk konstruksi + state
awal. Logika dalam `_init`/`_listenAuthState`/subscription realtime belum
di-unit-test — butuh fake stream + `fake_async` sebelum bisa dikunci penuh.
`PointsProvider` sudah DI (`{service}`) + `points_provider_test.dart`.

**Pelajaran harness (2026-09-20):** `testWidgets` memakai FakeAsync — **file I/O
nyata (SQLite) TIDAK akan selesai** dan test menggantung. Untuk jalur I/O pakai
`test()` biasa (lihat `message_store_test.dart` / `mixins/chat_outbox_flow_test.dart`).
Timer di provider yang dibuat di dalam `testWidgets` juga bikin "did not
complete" — buat provider di `create:` agar Provider men-dispose-nya.

**Coverage gate CI (ratchet, 2026-09-20):** providers 25% · services 15% ·
models 75% · mixins 14%. Terukur saat penetapan: 26.3 / 16.3 / 78.2 / 15.5.
`screens/` masih 0.2% (13.780 baris) — target terbesar berikutnya.

Belum ada test (butuh refactor ringan agar testable — service memakai `http.get`
top-level / plugin native secara langsung):
- `geo_service.dart` — parsing provider IP & mapping `_countryNames` butuh
  injeksi `http.Client` (sekarang panggilan global). Network live tidak diuji.
- `push_topic_service.dart` — `FirebaseMessaging` plugin native; error ditelan
  senyap, jadi rendah nilai tanpa fake plugin.
- `admin_provider.dart` — paging & TTL detail; butuh DI `AdminService`.
- Screen kompleks (`room_chat_screen`, `private_chat_screen`, dll) — belum
  di-smoke-test; mengandalkan test provider/model + test alur kritis.
