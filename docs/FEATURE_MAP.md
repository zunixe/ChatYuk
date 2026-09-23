# FEATURE_MAP — peta fitur → kode → SQL → test

> **Untuk AI/dev berikutnya.** Sebelum mengubah apa pun, cari fitur di sini,
> lihat file + fungsi SQL + test yang terlibat. Kalau kamu mengubah salah satu
> kolom/fungsi yang dipakai >1 fitur, aktifkan test terkait.
>
> Sumber kebenaran SQL = `supabase/snapshots/functions.sql` (auto-generate).
> Daftar fungsi beku = `scripts/frozen_functions.txt`.

---

## 1. Presence (online/idle/offline) — PALING RAWAN REGRESI

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/online_users_screen.dart`, `chats_screen.dart` |
| Provider | `lib/providers/online_users_provider.dart`, `auth_provider.dart` |
| Service | `lib/services/chat_service.dart` (`effectiveStatusOf`, `getUserStatus`), `rt_resilient.dart` |
| SQL inti | `ai_presence_tick()`, `presence_idle_tick` cron, `get_online_users()` |
| Cron | `chatyuk-ai-presence` (*/5m), `chatyuk-presence-idle` (*/1m) |
| Kolom kritis | `profiles.status`, `profiles.last_seen`, `dummy_accounts.ai_always_online`, `ai_active_hours`, `ai_wake_until`, `ai_offline_until` |
| Test | `test/presence_test.dart`, `test/online_users_provider_test.dart`, `test/online_visibility_test.dart`, `supabase/tests/presence_test.sql` |

**Regresi yang pernah terjadi:**
- `ai_always_online` (Admin Chatyuk) hilang saat `ai_presence_tick` di-replace
  oleh migrasi `...13150000` + `...13180000` → harus restore `...14020000`.
- Dummy idle tanpa presence tidak tampil di daftar online → fix `...13190000`.

**Invariant (dijaga test):**
1. Dummy `ai_always_online=true` → selalu `online` setelah tick, apa pun jamnya.
2. Dummy `status='invisible'` → tick TIDAK menyentuh (AI tetap balas).
3. `ai_wake_until` aktif → paksa online sampai lewat; lalu dibersihkan.
4. `ai_offline_until` (ngambek) aktif → paksa offline, abaikan jadwal.
5. Dummy jadwal-normal: dalam jam aktif → online/idle (drift); luar → offline.
6. `effectiveStatusOf`: last_seen >30 mnt = offline; `invisible` = offline.

---

## 2. AI Dummy (balasan chat, proaktif, life)

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/private_chat_screen.dart`, `lib/widgets/private_chat_message.dart` |
| Edge | `supabase/functions/ai-reply/index.ts` (+ `_shared/ai-helpers.ts`), `ai-daily-life/index.ts` |
| SQL inti | `ai_reply_enqueue()`, `ai_reply_post()`, `ai_reply_claim_recovery()`, `admin_set_dummy_ai()`, `admin_ai_settings()`, `admin_register_dummy()` |
| Cron | `ai-proactive-10m`, `chatyuk-ai-claim-recovery` (*/5m), `chatyuk-ai-missed-recovery` (*/3m), `chatyuk-ai-daily-life` (22:00) |
| Kolom kritis | `dummy_accounts.ai_enabled`, `ai_hold_active`, `ai_no_rate_limit`, `ai_always_reply`, `ai_no_sleep`, `ai_mood`, `ai_persona` (jsonb: `profession`, `appearance`), `app_settings.ai_global_enabled`, `ai_internal_config.callback_secret` |
| Test | `supabase/functions/_shared/ai-helpers.test.ts` (32 Deno), `supabase/tests/ai_test.sql` |

**Alur:** `private_messages INSERT` → trigger `ai_reply_enqueue` → helper
`ai_reply_post` (kirim `x-app-secret`) → edge `ai-reply` → insert balasan
sebagai dummy.

**Invariant:**
1. `app_settings.ai_global_enabled` harus `true`, kalau `false` semua dummy diam.
2. `ai_internal_config.callback_secret` kosong → fail-closed (semua diam).
3. `ai_reply_post()` harus menghasilkan row claim; recovery cron membangkitkan
   claim basi (10 mnt–1 jam).
4. `ai_no_sleep=true` → abaikan aturan tidur random 20–23 / bangun 4–6 & jumatan.
5. NSFW blocklist TIDAK pernah dilanggar (input & output).

---

## 3. Chat & Private Room

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/private_chat_screen.dart`, `private_chats_screen.dart`, `room_chat_screen.dart`, `chats_screen.dart`, `online_users_screen.dart` |
| Widget bubble | `lib/widgets/private_chat_message.dart` — `MessageBubble`, `SwipeToReply` |
| Provider | `lib/providers/chat_provider.dart`, `room_provider.dart` |
| Service | `lib/services/chat_service.dart`, `chat_stream_session.dart`, `message_cache.dart`, `room_service.dart`, `message_store.dart`, `private_room_service.dart` |
| SQL inti | `create_private_room()`, `join_private_room()`, `extend_private_room()`, `deduct_chat_point()`, `new_chat_bonus()`, `notify_private_message()`, `handle_new_private_message()`, `mark_chat_read()` |
| Test | `test/chat_provider_test.dart`, `test/message_store_test.dart`, `test/chat_service_io_test.dart` (payload PostgREST via HTTP palsu), `test/economy_room_io_test.dart`, `test/functional/` (composer/mention/bubble/reaction), `test/regression/r_read_receipt_test.dart`, `r_swipe_reply_test.dart`, `r_stream_replay_test.dart`, `supabase/tests/notif_chat_test.sql` |

**Invariant:** titik poin terpotong 1× per pesan (idempoten); bonus chat baru
hanya 1× per pasangan; notif hanya 1× per pesan (dedup).

### 3a. Buka chat instan + centang-2 (anti-lag) — RAWAN REGRESI

Tujuan: buka private chat harus terasa seperti WhatsApp — pesan & centang-2
sudah ada sejak frame pertama, tanpa layar kosong atau centang yang "nyusul".

| Lapis | Lokasi |
|---|---|
| Transisi route | `private_chats_screen.dart:626` (tap list), `online_users_screen.dart:907`, `story_viewer_screen.dart:718` — `PageRouteBuilder` 150 ms slide |
| Prime centang-2 | `private_chat_screen.dart` — `_primeReadFromCache()` (sinkron), `_loadCachedRead()` (fallback kv), `_persistRead()` |
| Stream pesan | `chat_stream_session.dart` — `replay onListen`, emit memori → SQLite → server (merge) |
| Pemanasan cache | `private_chats_screen.dart` — `_warmTopChats()` (6 chat teratas) → `ChatService.prefetchPrivateChat()` → `MessageCache.preloadMessages()` |
| Snapshot list | `chat_service.dart` — `_privateChatsLast`, `_applyChatEvent()`, `_applyLocalRead()`, `lastPrivateChatsSnapshot()` |

**Aturan yang TIDAK boleh dilanggar (kalau dilanggar, lag balik lagi):**

1. **Read receipt monoton maju.** `_otherLastRead` hanya boleh diganti nilai
   yang LEBIH BARU. Nilai `null`/lebih tua dari stream/disk tidak boleh
   menurunkan status → kalau dilanggar, centang-2 muncul belakangan/kedip.
2. **Prime sinkron sebelum frame pertama.** `_primeReadFromCache()` harus baca
   DUA sumber memori (snapshot live `_privateChatsLast` + `peekRawList`) dan
   ambil yang terbaru. Jangan tambahkan `await` di jalur ini.
3. **Broadcast stream wajib replay.** `ChatStreamSession` membuat stream di
   `initState` sebelum `StreamBuilder` subscribe; tanpa `controller.onListen`
   yang meng-emit ulang `_current`, emit memori HILANG → tampil kosong dulu.
4. **`initialData` StreamBuilder = `MessageCache.peekMessages()`** (sinkron),
   bukan `const []`. Jangan ganti ke future/async.
5. **Subscription non-kritis ditunda ke post-frame** (`_subscribeStatus`,
   `_subscribeTyping`, `_chatInfoSub`, fetch profil lawan, `markAsRead`).
   Jangan dikembalikan ke `initState` langsung — frame pertama jadi berat.
6. **Toast bonus sekali per buka chat** (`_bonusToastScheduled`). Jangan pakai
   `Future.microtask` mentah di dalam `build()` — dulu ke-dobel tiap rebuild.
7. **Bubble typing = item list paling bawah** (`itemCount + 1`, index 0 saat
   `reverse: true`). Kalau ditaruh di luar `ListView`, bubble tidak ikut scroll.
8. **Transisi route tetap ada** (150 ms `SlideTransition`), jangan di-nol-kan
   (terasa "patah") dan jangan dinaikkan ke 300 ms+ (terasa lag).

**Regresi yang pernah terjadi (jangan diulang):**
- Transisi 320 ms → terasa jeda saat buka chat.
- `_primeReadFromCache` hanya baca `peekRawList` yang bisa basi → centang-2 telat.
- Handler stream menimpa `_otherLastRead` dengan nilai apa pun (termasuk null)
  → centang-2 balik jadi centang-1 lalu muncul lagi.
- Batas `isBefore` (ketat) → pesan yang timestamp-nya persis sama dengan waktu
  baca tidak ikut centang-2. Sekarang pakai `!isAfter` (`<=`).
- Prefetch saat tap jalan paralel dengan build screen → frame pertama miss cache.
- Bubble typing di luar `ListView` → tidak ikut scroll (keluhan user).

### 3b. Swipe-to-reply (geser kanan = balas) — private & grup

| Lapis | Lokasi |
|---|---|
| Widget | `lib/widgets/private_chat_message.dart` — `SwipeToReply` (publik, dipakai 2 screen) |
| Private | `private_chat_screen.dart` — `onSwipeReply: isMe \|\| msg.isDeleted ? null : () => _replyMessage(msg)` |
| Grup/room | `room_chat_screen.dart` — `SwipeToReply(enabled: m.senderId != auth.uid && !m.isDeleted, ...)` |

**Cara kerja:** `onHorizontalDragUpdate` menggeser bubble 0–72 px ke kanan,
ikon `reply` di kiri muncul & menguat seiring tarikan. Lepas ≥48 px → `_replyMessage`
(composer masuk mode balas + fokus). Lepas <48 px → spring balik ke 0.

**Aturan yang tidak boleh dilanggar:**
1. **Pesan sendiri (`isMe`) TIDAK boleh di-swipe-reply.** Menggeser ke kanan dari
   tepi kiri adalah gesture swipe-back sistem di iOS; kalau pesan sendiri juga
   aktif, user tidak bisa keluar chat. Semua screen wajib mengecualikan `isMe`.
2. **Pesan terhapus tidak di-swipe** (`msg.isDeleted` → null).
3. **Pakai `onHorizontalDrag*`, bukan `Dismissible`** — `Dismissible` menggeser
   permanen & berkonflik dengan long-press action bar.
4. **`enabled=false` harus mengembalikan `child` apa adanya** (tanpa `Stack`),
   supaya screen read-only (monitor admin) tidak menanggung biaya layout.

**Catatan regresi:**
- `SwipeToReply` harus PUBLIK (tanpa underscore). Sempat ditulis `_SwipeToReply`
  (privat) → tidak bisa dipakai dari `room_chat_screen.dart`.

---

## 4. Notifikasi (FCM + in-app)

| Lapis | Lokasi |
|---|---|
| UI | `lib/main.dart` (background handler), `lib/services/call_notification.dart` |
| Edge | `supabase/functions/send-push/`, `fanout/` (+ `_shared/fcm.ts`) |
| SQL inti | `notify_private_message()`, `notify_call_ended()`, `call_push()` |
| Test | `test/notification_prefs_service_test.dart`, `supabase/tests/notif_chat_test.sql`, `supabase/tests/contract_test.sql` |

**Invariant:** string notif bilingual (via prefs `isId`); 1 notif per event;
`to_uid` benar (fix `...13130001`).

---

## 5. Poin / Ekonomi (koin, gift, quest)

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/leaderboard_screen.dart`, `missions_screen.dart`, `donate_screen.dart`, `point_history_screen.dart` |
| Provider | `lib/providers/points_provider.dart` |
| Service | `lib/services/points_service.dart` |
| SQL inti | `one_time_bonus()`, `send_coins()`, `send_gift()`, `room_read_bonus()`, `daily_login_bonus()`, `claim_weekly_quest()`, `points_leaderboard()` |
| Test | `test/points_provider_test.dart`, `test/points_service_io_test.dart` (payload RPC via HTTP palsu), `supabase/tests/points_test.sql` |

**Invariant:** klaim bonus idempoten (tidak bisa dobel); milestone online
5/30/60/120 mnt; saldo = cache ledger `profiles.points`.

---

## 6. Feed / Sosial / Story

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/timeline_screen.dart`, `story_*.dart`, `social_list_screen.dart`, `nearby_screen.dart` |
| Provider | `lib/providers/timeline_provider.dart`, `story_provider.dart`, `social_provider.dart` |
| SQL inti | `list_posts()`, `create_story()`, `story_slides()`, `follow_count_sync()`, `nearby_users()` |
| Cron | `purge-stories` (17:00), `purge_inactive_90d` |
| Test | `test/story_provider_test.dart`, `test/timeline_provider_test.dart`, `test/story_social_io_test.dart` (payload RPC story/social via HTTP palsu) |

**Invariant:** visibility story ikut follower; counter sosial konsisten
(`follow_count_sync`); timeline hanya user terdaftar.

---

## 7. Call (voice/video)

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/call_screen.dart`, `incoming_call_screen.dart`, `lib/widgets/call_banner.dart`, `chat_call_overlay.dart` |
| Provider | `lib/providers/call_provider.dart` |
| Service | `lib/services/call_service.dart`, `admin_call_watch_service.dart` |
| UI sistem | `lib/services/call/` (CallUi) + `android/.../call/` (ConnectionService) — lihat `docs/CALL_NATIVE.md` |
| Edge | `supabase/functions/turn-credentials/` |
| SQL inti | `call_push()`, `notify_call_ended()`, monitor `calls` realtime, `admin_sweep_calls()` |
| Cron | `chatyuk-call-sweep` (*/5m) — akhiri ringing/answered zombie + retensi `call_signals` >1 jam |
| Test | `test/call_provider_test.dart`, `test/call_overlay_test.dart`, `supabase/tests/call_test.sql` |

**Invariant:** 1 call aktif per user; notif missed 1×; `activeCallId` cocok.

---

## 8. Admin Panel (flavor terpisah)

| Lapis | Lokasi |
|---|---|
| Entry | `lib/main_admin.dart` (gate `lib/core/admin_gate.dart`) |
| UI | `lib/screens/admin_*.dart`, `lib/admin/` |
| Provider | `lib/providers/admin_provider.dart` |
| SQL inti | `admin_list_dummies()` (18× replace!), `admin_stats_detail()` (12×), `admin_set_dummy_ai()`, `admin_ai_settings()` |
| Test | `test/admin_provider_di_test.dart`, `supabase/tests/schema_sync_test.sql` (tabel/RPC admin anti-regresi) |

**Invariant:** admin list tidak bocor ke build rilis (tree-shake lewat
`admin_gate.dart`); fitur admin 24/7 (`ai_always_online`) tetap utuh.

---

## 9. Privasi (visibilitas presence/photo/about/story) — RAWAN BYPASS

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/privacy_settings_screen.dart` |
| Provider | `lib/providers/privacy_provider.dart` |
| Service | `lib/services/privacy_service.dart` |
| Model | `lib/models/privacy_settings.dart` |
| SQL inti | `privacy_can_view()`, `_privacy_are_friends()`, `my_privacy_settings()`, `update_privacy_settings()`, `replace_privacy_exclusions()`, `privacy_excludable_users()`, `profile_public()`, `get_online_users()`, `nearby_users()`, `story_slides()`, `story_tray()` |
| RPC baca ber-privacy (baru 2026-09-22) | `presence_for(uuid[])`, `avatar_for(uuid)`, `avatars_for(uuid[])`, `my_photos()`, `get_user_photos_access()` |
| Kolom | `profiles.{presence,last_seen,profile_photo,about,story}_visibility` (5 nilai: everyone/everyone_except/friends/friends_except/nobody), `profiles.read_receipts_enabled`, `profile_privacy_exclusions`, `user_photos.photo` (di-revoke), `user_photos.photo_preview` |
| Test | `test/privacy_settings_test.dart`, `test/privacy_service_io_test.dart`, `test/privacy_provider_test.dart`, `test/privacy_widget_test.dart`, `test/photo_privacy_access_test.dart`, `supabase/tests/privacy_test.sql` |

**Invariant (dijaga test — JANGAN diregresikan):**
1. **Kolom sensitif TIDAK boleh ter-grant SELECT** ke `anon`/`authenticated`:
   `profiles.status`, `last_seen`, `avatar`, `share_location`, `ip_address`,
   `email`, `fcm_token`, `about`, `lat*`, `lon*`; dan `user_photos.photo`.
   Kalau perlu baca → **WAJIB lewat RPC ber-privacy** (`presence_for`,
   `avatar_for`, `avatars_for`, `my_photos`, `profile_public`,
   `get_user_photos_access`). Jangan `from('profiles').select('avatar')` lagi.
2. `user_photos` punya **table-level** SELECT grant (menutupi revoke kolom) →
   untuk cabut, revoke TABLE-level lalu grant kolom aman (`id, user_id,
   photo_preview, created_at`).
3. `privacy_can_view(owner, field, viewer)`: owner=self → true; `nobody` →
   false; `everyone_except`/`friends_except` → cek `profile_privacy_exclusions`;
   `friends`/`friends_except` → cek `_privacy_are_friends` (mutual follow).
4. `story_tray` WAJIB cek `privacy_can_view(author,'story')` + mask avatar —
   dulu tidak (story "nobody" bocor di tray).
5. `mark_chat_read`: `read_receipts_enabled=false` → unread tetap 0 tapi
   `last_read_at` tidak ditulis (centang-2 lawan tidak muncul).

**Review/diagnosa cepat:** `select has_column_privilege('authenticated',
'public.profiles','<kolom>','SELECT');` harus **false** untuk kolom sensitif.

---

## Peta kolom lintas-fitur (JANGAN ubah semantik tanpa cek semua)

| Kolom | Dipakai oleh |
|---|---|
| `profiles.status`, `profiles.last_seen` | presence, chat list, nearby, online users, admin — **SELECT di-revoke** (2026-09-22); baca lewat `presence_for()` / `get_online_users()` |
| `profiles.avatar` | avatar list/chat/feed — **SELECT di-revoke**; baca lewat `avatar_for()` / `avatars_for()` / `profile_public()` |
| `profiles.share_location` | lokasi peta — **SELECT di-revoke**; admin lewat RPC admin |
| `user_photos.photo` | galeri — **SELECT di-revoke** (paywall); baca lewat `get_user_photos_access()` / `my_photos()`; `photo_preview` tetap publik |
| `dummy_accounts.ai_*` (enabled/always_online/no_sleep/wake/offline/mood/persona) | AI reply, presence tick, admin, daily-life, proaktif |
| `app_settings.ai_global_enabled` | AI reply, admin toggle |
| `ai_internal_config.callback_secret` | ai_reply_post, semua AI |
| `profiles.points` | poin, gift, chat bonus, leaderboard, admin |
| `private_messages.*` | chat, notif, AI enqueue, admin monitor |
| `messages.mentions`, `private_messages.mentions` | highlight mention + push terarah mention (room/grup); `@all` hanya grup/private room (owner/admin), mati di global room |
| `private_chats.last_read_at` (map uid→ts) | centang-2 di chat, unread badge, mark_chat_read, admin monitor |
| Registrasi: 12 kolom `profiles` wajib tulis | `id,nickname,gender,age,country,city,status,avatar,is_registered,login_at,created_at,last_seen` harus tetap `INSERT`+`UPDATE` untuk `authenticated` — pola tulis **split-write** (`upsert ignoreDuplicates` + `PATCH`), JANGAN `merge-duplicates` (butuh SELECT → 42501 bila kolom di-revoke). Insiden: `docs/INCIDENT_ANON_REGISTER_42501.md`. Dikunci: `supabase/tests/auth_write_path_test.sql` + `scripts/smoke_anon_register.sh` |
| `private_chats.last_message_at` | urutan list chat, pinned sort, cache warm |

---

## Cara pakai bersama guardrail

```bash
# sebelum commit perubahan SQL apa pun:
bash scripts/check_migrations.sh --all          # timestamp, DROP/ALTER, header
bash scripts/snapshot_functions.sh              # kalau sentuh fungsi frozen
git diff supabase/snapshots/functions.sql       # REVIEW: ada cabang hilang?
flutter test && deno test --allow-read supabase/functions/_shared/
```
