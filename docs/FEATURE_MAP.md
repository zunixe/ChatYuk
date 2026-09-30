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
| SQL inti | `ai_presence_tick()`, `presence_idle_tick` cron, `get_online_users()`, `notify_contact_online()` |
| Cron | `chatyuk-ai-presence` (*/5m, menit 2-59/5), `chatyuk-housekeeping` (*/1m — presence idle + voice + room cleanup sekaligus) |
| Kolom kritis | `profiles.status`, `profiles.last_seen`, `dummy_accounts.ai_always_online`, `ai_active_hours`, `ai_wake_until`, `ai_offline_until` |
| Test | `test/presence_test.dart`, `test/online_users_provider_test.dart`, `test/online_visibility_test.dart`, `supabase/tests/presence_test.sql`, `supabase/tests/online_notify_test.sql` |

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
7. Notif "X online" (2026-09-30): penerima = UNION(teman mutual |
   follower-ku | pernah 1:1 chat), kecuali author/blokir/author-dummy;
   via outbox (transaksi tak menunggu HTTP). Tap: ada chatId → chat,
   tanpa chatId → profil (`UserInfoScreen`).

---

## 2. AI Dummy (balasan chat, proaktif, life)

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/private_chat_screen.dart`, `lib/widgets/private_chat_message.dart` |
| Edge | `supabase/functions/ai-reply/index.ts` (+ `_shared/ai-helpers.ts`), `ai-daily-life/index.ts` |
| SQL inti | `ai_reply_enqueue()`, `ai_reply_post()`, `ai_reply_claim_recovery()`, `admin_set_dummy_ai()`, `admin_ai_settings()`, `admin_register_dummy()` |
| Cron | `ai-proactive-10m`, `chatyuk-ai-claim-recovery` (*/5m, menit 3-59/5), `chatyuk-ai-missed-recovery` (*/3m) — `chatyuk-ai-daily-life` (22:00) DIMATIKAN 2026-09-28 (belum dipakai) |
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
| SQL inti | `create_private_room()` (+`p_category`; kategori ASLI = gratis/terbuka, legacy `'private'` bayar), `join_private_room()`, `extend_private_room()`, `deduct_chat_point()`, `new_chat_bonus()`, `notify_private_message()`, `handle_new_private_message()`, `mark_chat_read()`, `list_room_explore()` + `mark_room_read()` + tabel `room_reads` (explore + unread sync) |
| Test | `test/chat_provider_test.dart`, `test/message_store_test.dart`, `test/chat_service_io_test.dart` (payload PostgREST via HTTP palsu), `test/economy_room_io_test.dart`, `test/functional/` (composer/mention/bubble/reaction), `test/regression/r_read_receipt_test.dart`, `r_swipe_reply_test.dart`, `r_stream_replay_test.dart`, `supabase/tests/notif_chat_test.sql` |

**Invariant:** titik poin terpotong 1× per pesan (idempoten); bonus chat baru
hanya 1× per pasangan; notif hanya 1× per pesan (dedup).

### 3b. PEMISAH Global Room vs Grup — WAJIB BACA sebelum menyentuh room

| | GLOBAL ROOM (tab Global Room) | GRUP (tab Grup, legacy) |
|---|---|---|
| `rooms.is_private` | `false` | `true` |
| `rooms.category` | 10 id (`general`/`curhat`/...) | SELALU `'private'` |
| Anggota/password | TIDAK ADA (chat terbuka) | `room_members` + BISA password/approval |
| Kelola/hapus | admin panel saja | owner (extend/delete) + admin |
| Buat via | `RoomService.createGlobalRoom` (GRATIS, tanpa param password) | `RoomService.createPrivateRoom` (bayar poin) |
| List via | `list_room_explore()` (filter `is_private=false`) | `list_my_groups()` |
| Unread | `room_reads` + `mark_room_read()` | — |

**ATURAN KERAS:** room kategori TIDAK PERNAH `is_private=true` / berpassword
(dipaksa di `create_private_room`; JANGAN dilonggarkan). Nama RPC
`create_private_room` historis (dipakai APK lama) — JANGAN rename; bedakan
di wrapper client. `RoomIcon`: `rooms.icon` = emoji ATAU path
`room-icons/<uid>/...` (upload via `uploadRoomIcon`).

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
| Edge | `supabase/functions/send-push/`, `fanout/`, **`outbox-worker/`** (+ `_shared/fcm.ts`) |
| SQL inti | `notify_private_message()`, `notify_call_ended()`, `call_push()`, **helper `user_fcm_tokens(uid)`** |
| Cron | **`chatyuk-outbox-worker` (*/1m)** — menguras `public.outbox` → send-push |
| Test | `test/notification_prefs_service_test.dart`, `supabase/tests/notif_chat_test.sql`, **`supabase/tests/outbox_notif_test.sql`**, `supabase/tests/contract_test.sql` |

**Invariant:** string notif bilingual (via prefs `isId`); 1 notif per event;
`to_uid` benar (fix `...13130001`).

**ARsitektur OUTBOX (sejak 2026-09-27) — WAJIB diketahui:**
- Trigger notif (`notify_private_message`, `notify_mention_room`, `call_push`
  ×2 overload, `notify_call_ended`) **TIDAK** lagi `net.http_post` sinkron →
  `insert into public.outbox (type, payload)` (cepat, transaksi tulis pesan
  tidak menunggu HTTP). Pengiriman dilakukan edge **`outbox-worker`** via cron
  `chatyuk-outbox-worker` (*/1m). **Kalau worker/cron mati → notif tidak
  terkirim** (pesan tetap aman, bukan data loss).
- Token notif DIAMBIL dari **`user_devices.fcm_token`** (helper
  `user_fcm_tokens(uid)` = devices aktif + fallback `profiles.fcm_token`).
  JANGAN kembali membaca `profiles.fcm_token` langsung — kolom itu sudah
  dikosongkan (`20260827000000`) → notif ke device klien baru akan hilang.
- Fungsi `net.http_post` sinkron tersisa (fanout topical & AI) sengaja belum
  dipindah (prioritas lebih rendah). Jangan tambah pola http_post sinkron BARU.

---

## 5. Poin / Ekonomi (koin, gift, quest)

> **Overhaul 2026-10:** poin gratis DIHAPUS. Coin = satu saldo (`coin_ledger`,
> cache `profiles.points`), masuk HANYA dari topup Google Play Billing +
> welcome bonus + income call. Nelp = murni coin (audio 6 / video 20 per menit).

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/point_history_screen.dart` (+ `point_history/widgets/*`: topup_sheet, yukcoin_header, history_tile), `donate_screen.dart` |
| Provider | `lib/providers/points_provider.dart` |
| Service | `lib/services/points_service.dart`, `lib/services/topup_service.dart` (Play Billing) |
| Edge fn | `welcome-bonus` (klaim bonus, IP server-side), `play-topup-verify` (verifikasi pembelian Play) |
| SQL engine | `charge_metered()` (potong+split generik), `call_billing_tick()` (tagih call/menit), `gate_feature()` (akses harian: filter gender, nearby), `credit_welcome_bonus()` (bonus anto-farming), `credit_play_topup()` (topup), `feature_enabled_for()`/`admin_set_feature_flag()` (publish) |
| Fitur berbayar | call (`call_billing`), filter gender (`gender_filter_paid`), orang sekitar (`nearby_paid`), topup (`play_topup`) |
| Test | `test/points_provider_test.dart`, `test/points_service_io_test.dart`, `test/flow_points_test.dart` |

**Invariant:** coin hanya dari topup/bonus/income (tidak ada faucet gratis);
nelp ditagih server dari `calls.answered_at` (afford-guard → saldo tak minus);
welcome bonus idempoten per `install_id` + limit IP/hari; `charge_metered`
hanya `service_role` (user tak bisa mendebit orang lain); saldo = cache ledger
`profiles.points`.

---

## 6. Feed / Sosial / Story

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/timeline_screen.dart`, `story_*.dart`, `social_list_screen.dart`, `nearby_screen.dart` |
| Provider | `lib/providers/timeline_provider.dart`, `story_provider.dart`, `social_provider.dart` |
| SQL inti | `list_posts()`, `get_post()`, `create_story()`, `story_slides()`, `follow_count_sync()`, `nearby_users()`, `notify_post_followers()` |
| Cron | `purge-stories` (17:00), `purge_inactive_90d` |
| Test | `test/story_provider_test.dart`, `test/timeline_provider_test.dart`, `test/story_social_io_test.dart` (payload RPC story/social via HTTP palsu) |

**Invariant:** visibility story ikut follower; counter sosial konsisten
(`follow_count_sync`); timeline hanya user terdaftar.

**Notif post baru (2026-09-29) — sesuai visibilitas post:**
- `public` → SEMUA user (registered, non-dummy, non-exclude, tanpa blokir);
  `followers` → follower saja; `subscribers` → subscriber aktif saja.
- Fanout topic `timeline-all` HANYA untuk `public` (dulu semua visibilitas →
  bocor isi followers/subscribers-only).
- Tap notif (`timeline_post`/`timeline` + `postId`) → `PostDetailScreen`
  (`get_post`, hormat visibilitas); tanpa postId → tab Timeline.

---

## 7. Call (voice/video)

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/call_screen.dart`, `incoming_call_screen.dart`, `call_history_screen.dart` (Panggilan Terbaru), `lib/widgets/call_banner.dart`, `chat_call_overlay.dart` |
| Provider | `lib/providers/call_provider.dart` (`recentCalls`/`lookupNames`) |
| Service | `lib/services/call_service.dart` (`listMyRecentCalls`), `admin_call_watch_service.dart` |
| Core | `lib/core/call/call_history_entry.dart` (klasifikasi arah/outcome — murni) |
| Entry | menu ⋮ tab Pesan `lib/screens/chats_screen.dart` → `CallHistoryScreen` |
| UI sistem | `lib/services/call/` (CallUi) + `android/.../call/` (ConnectionService) — lihat `docs/CALL_NATIVE.md` |
| Edge | `supabase/functions/turn-credentials/` |
| SQL inti | `call_push()`, `notify_call_ended()`, monitor `calls` realtime, `admin_sweep_calls()` |
| Cron | `chatyuk-call-sweep` (*/5m) — akhiri ringing/answered zombie + retensi `call_signals` >1 jam |
| Test | `test/call_provider_test.dart`, `test/call_overlay_test.dart`, `supabase/tests/call_test.sql` |

**Invariant:** 1 call aktif per user; notif missed 1×; `activeCallId` cocok.

### 7b. Voice stage global room (audio-only, max 6 mic) — 2026-09-26

| Lapis | Lokasi |
|---|---|
| UI | `room_chat_screen.dart` (tombol mic AppBar + `VoiceStageStrip`), `room_chat/widgets/voice_stage_strip.dart` |
| Service | `lib/services/room_voice_service.dart` (mesh audio, pola `room_broadcast_service.dart`) |
| SQL inti | `room_voice_signals` (signaling), `room_voice_speakers` (stage+heartbeat), RPC `room_voice_join/heartbeat/leave/mute/sweep`, sweep ikut cron `chatyuk-housekeeping` (*/1m) |
| Test | `test/room_voice_session_test.dart` (state awal; handshake butuh 2 HP) |

**Invariant:**
1. Max 6 mic enforced **server** (`room_voice_join` hitung heartbeat <45 dtk) — client hanya menampilkan "penuh".
2. Mute paksa hanya owner room / app admin (server cek ulang) — sinyal `v_mute` terarah.
3. Keluar room/dispose SELALU `stop()` (leave RPC + tutup PC) — mic tidak nyangkut; watchdog cron 45 dtk sebagai jaring pengaman.
4. Tulis speakers HANYA via RPC (RLS tanpa policy tulis) — jangan tambah policy insert/update/delete.
5. `room_voice_signals` global terbuka / member (pola `room_signals`); jangan longgarkan ke anon.

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

**Kartu "Registrasi Email" (Ringkasan, 2026-10-05):** menampilkan KPI CEO
(total terdaftar, konversi anon, baru bulan ini, rata-rata/hari, aktif hari
ini, hari terbaik) + tren 12 bulan + bar harian + sumber akuisisi. Data dari
`admin_registration_kpis()` & `admin_registrations_monthly(p_months)` —
**keduanya mengecualikan dummy + excluded uid** (user nyata; beda dari
`admin_stats_compute` yang tidak buang dummy). Jangan hilangkan filter dummy
di dua RPC ini.

### 8.1 Tab Atribusi (sumber user / kanal install)

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/admin_attribution_tab.dart` (tab ke-9 di `admin_panel_screen.dart`) |
| Provider | `lib/providers/admin/admin_attribution.dart` (mixin `AdminAttributionMx`) |
| Instrumentasi | `lib/services/attribution_service.dart` (Play Install Referrer + Firebase Analytics) |
| Jalur simpan | `device_info_service.dart` → RPC `upsert_device` (param `p_attr_*`) → kolom `user_devices.attribution_*` |
| SQL | `admin_attribution_summary(p_days)`, `admin_attribution_users_page(p_source,limit,offset)`; migrasi `20261004000000_attribution.sql` |
| Test | `test/attribution_test.dart` (normalisasi sumber & parse referrer) |

**Cara kerja:** link iklan (FB/IG/TikTok) ditempeli `?referrer=utm_source%3D…`
di Play Store; Google Ads otomatis `gclid`. Saat first-launch, app baca
Install Referrer → normalisasi ke `facebook|instagram|google|tiktok|referral|
organic|unknown` → simpan via `upsert_device`. Server **TULIS SEKALI**
(`coalesce(existing, excluded)`) supaya resume/re-login tidak menimpa kanal
asli. Data **hanya** terkumpul untuk install baru (referrer tidak retroaktif).
iOS/web → `unknown` (Install Referrer Android-only).

---

**Kebijakan EXCLUDE (sejak 2026-09-27):** admin melihat **SEMUA** user di
ringkasan/peta — user ter-exclude (device/uid) TETAP tampil dengan flag
`'excluded': true` (UI kasih badge "EXCLUDED"), TIDAK lagi disembunyikan total.
`admin_stats_detail` (FROZEN) & `admin_stats_users_page` mengembalikan flag itu;
`admin_stats_compute` (kartu angka) tetap menghitung TANPA excluded (metrik
tidak melonjak). **DUMMY tetap dibuang** dari ringkasan admin.
JANGAN mengembalikan filter `not (id = any(v_excl))` ke dua fungsi itu.
Jalur user nyata (`list_posts`, `nearby_users`, `create_private_room`) TETAP
mengecualikan device/uid exclude — biarkan (akun test/dev tak boleh tampil
ke user asli). Dikunci: `supabase/tests/schema_sync_test.sql`.

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
| Kolom | `profiles.{presence,last_seen,profile_photo,about,story}_visibility` (6 nilai: everyone/everyone_except/friends/friends_except/**only**/nobody; **only** = daftar PUTIH di `profile_privacy_exclusions` — hanya uid terpilih yang lolos; `update_privacy_settings` MENOLAK `only` bila daftar field itu kosong), `profiles.read_receipts_enabled`, `profile_privacy_exclusions` (tabel yang sama dipakai sebagai daftar hitam `*_except` maupun daftar putih `only`), `user_photos.photo` (di-revoke), `user_photos.photo_preview` |
| Test | `test/privacy_settings_test.dart`, `test/privacy_service_io_test.dart`, `test/privacy_provider_test.dart`, `test/privacy_widget_test.dart`, `test/photo_privacy_access_test.dart`, `supabase/tests/privacy_test.sql`, `supabase/tests/privacy_only_test.sql` |

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
   false; `everyone_except`/`friends_except` → cek `profile_privacy_exclusions`
   (daftar HITAM); `friends`/`friends_except` → cek `_privacy_are_friends`
   (mutual follow); `only` (2026-09-29) → **daftar PUTIH**: lolos HANYA bila
   viewer ADA di `profile_privacy_exclusions(owner, field, viewer)` — teman/
   follower TIDAK otomatis lolos (kebalikan `everyone_except`).
4. `update_privacy_settings` allowlist = 6 nilai; `only` DITOLAK bila daftar
   field itu masih kosong (client `replace_privacy_exclusions` dulu, baru set
   nilai) → cegah mode "Hanya orang tertentu (0)".
5. `story_tray` WAJIB cek `privacy_can_view(author,'story')` + mask avatar —
   dulu tidak (story "nobody" bocor di tray).
6. `mark_chat_read`: `read_receipts_enabled=false` → unread tetap 0 tapi
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
| `profiles.location_mocked` / `location_mock_reason` / `location_accuracy_m` / `location_flagged_at` | deteksi Fake GPS (2026-10-02) — **SELECT di-revoke**; ditulis `update_my_location()`, dibaca admin lewat `admin_stats_detail()` / `admin_user_detail()`. **Hanya MENANDAI** (badge merah di peta/detail) — tak memblokir |
| `user_photos.photo` | galeri — **SELECT di-revoke** (paywall); baca lewat `get_user_photos_access()` / `my_photos()`; `photo_preview` tetap publik |
| `dummy_accounts.ai_*` (enabled/always_online/no_sleep/wake/offline/mood/persona) | AI reply, presence tick, admin, daily-life, proaktif |
| `app_settings.ai_global_enabled` | AI reply, admin toggle |
| `ai_internal_config.callback_secret` | ai_reply_post, semua AI |
| `profiles.points` | poin, gift, chat bonus, leaderboard, admin |
| `private_messages.*` | chat, notif, AI enqueue, admin monitor — **policy `private_messages_admin_select`** (2026-09-29): admin boleh SELECT (syarat realtime monitor); user biasa tetap policy peserta; admin sudah baca semua via RPC |
| `messages.mentions`, `private_messages.mentions` | highlight mention + push terarah mention (room/grup); `@all` hanya grup/private room (owner/admin), mati di global room. **Notif mention (room) via OUTBOX:** trigger `notify_mention_room` menulis `public.outbox`; dikirim oleh edge `outbox-worker` + cron `chatyuk-outbox-worker` (*/1m). Kalau worker/cron mati → notif mention tidak terkirim (pesan tetap aman). Lihat `20260927140000` & `20260927150000`. |
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

---

## 10. Semantik & konvensi yang SENGAJA berbeda (jangan "diperbaiki" tanpa keputusan)

### 10a. "Blocked" berbeda antara chat dan timeline — KEPUTUSAN SADAR
| Jalur | Implementasi | Arti |
|---|---|---|
| Chat (`ChatProvider.isBlocked`) | `ChatService.getBlockedUids` → `blocks.blocker_id = me` | **satu arah**: saya blokir X → saya tak lihat X |
| Timeline (`TimelineProvider._blockedIds`) | `blocks` di-query `.or(blocker=me, blocked=me)` | **dua arah**: blokir saling menyembunyikan |

Alasan: chat = kontrol **diri** (saya memilih tak berinteraksi); timeline =
**keamanan** (post orang yang memblokir saya jangan muncul). Keduanya
sengaja tidak disatukan. Kalau nanti ingin disatukan, itu keputusan produk —
ubah di SATU tempat (`ChatService.getBlockedUids`) lalu konsumsi di timeline,
jangan sebaliknya.

### 10b. Tabel TTL cache admin (jangan salah pilih)
| Cache | TTL | Lokasi |
|---|---|---|
| `_detailCache` (stats detail) | 60 dtk | `admin/admin_stats.dart` |
| `_storageTtl` (storage stats) | 10 mnt | `admin/admin_stats.dart` |
| `_excludedTtl` (excluded devices) | 5 mnt | `services/admin_service.dart` |
| cache stats server | 5 mnt | server-side (RPC) |
| `_commentTtl` timeline | 30 dtk | `providers/timeline_provider.dart` |

### 10c. Instrumentasi RPC — SATU jalur
Semua service (admin & user) memakai `measuredRpc()` (`lib/core/perf/
rpc_probe.dart`): metrik `rpc.<fn>` saat `PERF_PROBE` on, nol overhead saat
off. Admin memakai label `admin.<fn>`. JANGAN kembali menulis `_sb.rpc`
langsung untuk RPC baru, dan jangan tambah konvensi ketiga
(`PerfProbe.timed` manual hanya untuk jalur butuh `.timeout()` chaining,
mis. `story_service`).

### 10d. Widget bersama (jangan bikin salinan baru)
`lib/widgets/`: `detail_row.dart` (DetailRow), `sheet_drag_handle.dart`
(SheetDragHandle), `initial_avatar.dart` (InitialAvatarBox/Circle),
`admin_error_view.dart` (AdminErrorView), `toggle_tile.dart` (ToggleTile),
`search_field.dart` (SearchField), `filter_chip_pill.dart` (FilterChipPill).
Utilitas bersama: `utils.matchesQuery`, `admin/admin_grouping.dart`
(groupByDevice/filterDeviceGroups), `core/ui/scroll_pagination.dart`
(ScrollPagination).
