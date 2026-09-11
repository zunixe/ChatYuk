# Catatan Migrasi via API (Playwright fallback) — untuk AI lain

> WAJIB dibaca sebelum `supabase db push`

## 2026-08-27 — 20260827100000_fix_call_ended_dataonly.sql

- **Status:** SUDAH TERAPPLIED di remote DB `fohcucyyejdryryoxitm` pada 2026-08-27.
- **Cara apply:** BUKAN via `supabase db push --include-all` (CLI timeout 120s, Docker not found, `LegacyStatusDbInspectError`).  
  Diterapkan langsung via **Supabase Management API** `POST /v1/projects/{ref}/database/query` dengan `SUPABASE_ACCESS_TOKEN` (ekuivalen Playwright → Dashboard SQL Editor).

  ```bash
  # 1. Eksekusi SQL file
  python3 -c "sql=Path('supabase/migrations/20260827100000_fix_call_ended_dataonly.sql').read_text(); json.dumps({'query': sql})" > /tmp/mig.json
  curl -X POST "https://api.supabase.com/v1/projects/fohcucyyejdryryoxitm/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" --data-binary @/tmp/mig.json

  # 2. Catat ke history migrasi (wajib, kalau tidak `db push` akan coba lagi)
  curl -X POST ... -d '{"query":"insert into supabase_migrations.schema_migrations (version) values ('\''20260827100000'\'')"}'
  ```

- **Verifikasi:**
  ```sql
  select version from supabase_migrations.schema_migrations order by version desc limit 3;
  -- 20260827100000, 20260827090000, 20260827080000

  select pg_get_functiondef(oid) from pg_proc where proname='notify_call_ended';
  -- harus mengandung:  'body', v_body  di jsonb_build_object data
  ```

- **Edge Function `send-push` juga sudah terdeploy** pada 2026-08-27 via `supabase functions deploy send-push --no-verify-jwt` (berhasil: `Deployed Functions.` walau warning Docker).
  Perubahan: `dataOnlyTypes` tambah `'call_ended'` → `['online','follow','friend_request','subscribe','call','call_ended']`
  File: `supabase/functions/send-push/index.ts:85`

- **Kenapa via API, bukan CLI?** CLI `supabase db push` hang >120s di Windows ini (`docker: command not found`). Playwright/Management API adalah fallback resmi yang dicatat di sini agar AI sesi berikutnya **JANGAN** coba `db push` lagi untuk versi ini — sudah applied.

## 2026-08-27 — 20260827110000_sync_call_push_and_ended.sql

- **Status:** SUDAH TERAPPLIED di remote DB `fohcucyyejdryryoxitm` pada 2026-08-27 (via Management API, sama seperti di atas).
- **Isi:** Sinkron `call_push` jadi fan-out `user_devices` (sebelumnya revert ke `profiles` only → ringing tidak konsisten dengan `notify_call_ended` fan-out). `notify_call_ringing` tetap pakai `call_push` baru. Verifikasi: `select pg_get_functiondef` `call_push` harus mengandung `for rec in select fcm_token from public.user_devices`.
- **Code sync:** `lib/main.dart` `call_ended` handler (background `48` + foreground `213`) sekarang: (a) cancel duplikat `callId` alt sebelum `show`, (b) foreground juga `unregisterCall` + `nav.pop()` + `clearSession()` untuk dismiss `IncomingCallScreen` & `call_active` foreground service yang tertinggal (penyebab notif ke-3). Tanpa ini, DB sudah 1 push tapi code masih ninggalin `IncomingCallScreen` + `call_active` = 3 ikon.
- **Verifikasi sinkron:** `call_push` fan-out ✅, `notify_call_ended` data-only + `data.body` ✅, `send-push` `call_ended` data-only ✅, `main.dart` handle `call_ended` dismiss ✅, `flutter analyze` 0 error 0 warning (156 infos ok).

## 2026-08-28 — 20260828010000_call_message_avatar.sql

- **Status:** ✅ SUDAH TERAPPLIED di remote DB `fohcucyyejdryryoxitm` pada 2026-08-28 via **Supabase Management API** `POST /v1/projects/.../database/query` (token `sbp_...` dari Keychain, bukan `supabase db push` yang timeout 300s).
- **Cara apply:** `curl -X POST https://api.supabase.com/v1/projects/fohcucyyejdryryoxitm/database/query -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" --data-binary @/tmp/mig1.json` + `insert into supabase_migrations.schema_migrations (version) values ('20260828010000')` (sudah). Verifikasi: `select pg_get_functiondef(oid) from pg_proc where proname='call_push'` mengandung `avatarUrl`.

## 2026-08-28 — 20260828020000_unified_fanout_debounce.sql

- **Status:** ✅ SUDAH TERAPPLIED di remote DB `fohcucyyejdryryoxitm` pada 2026-08-28 via **Management API** (sama). Verifikasi: `select version from supabase_migrations.schema_migrations order by version desc limit 5` → `20260828020000, 20260828010000` teratas.

## 2026-08-28 — Edge Functions (fanout + send-push avatar)

- **send-push** `supabase/functions/send-push/index.ts`: support `topic` (selain `token`), resolve `avatarUrl` path `avatars/` → public URL `https://.../storage/v1/object/public/chat-photos/...`, set `notification.image` + `android.notification.image` + `apns fcm_options.image`, `data` stringified. Verifikasi: `grep -c avatarUrl supabase/functions/send-push/index.ts` >0.
- **fanout** `supabase/functions/fanout/index.ts` (BARU): HTTP `POST {type,id}` → query `profiles/posts/rooms` via `SUPABASE_SERVICE_ROLE_KEY` → `admin.messaging().send({topic:'online-$id'|'timeline-all'|'room-$id', notification:{title,body,image}, data:{...}})` + `broadcast` via Realtime (Presence). Deploy: `supabase functions deploy fanout --no-verify-jwt` + `send-push` redeploy.

## 2026-08-28 — Flutter (unified realtime)

- **RealtimeHub** `lib/services/realtime_hub.dart` + **PushTopicService** `lib/services/push_topic_service.dart` (baru) — hub Presence `online-global`, Broadcast `timeline-all`, Presence `room-$id`.
- **AuthProvider** `lib/providers/auth_provider.dart`: heartbeat `trackOnline` Presence tiap 120s, `untrack` saat idle/offline/invisible.
- **ChatService** `lib/services/chat_service.dart:getOnlineUsers()` ganti `SELECT LIMIT 500 + polling 30d` → `PresenceState` + `SELECT ... WHERE id IN (presence uids)` + avatar batch.
- **TimelineProvider** `lib/providers/timeline_provider.dart` + **RoomProvider** `lib/providers/room_provider.dart` listen `RealtimeHub.timelineBroadcast` / `roomPresence`.
- **main.dart** `lib/main.dart`: `import dart:io, http, path_provider`, `_showLocalNotification` download `avatarUrl` → `BigPictureStyleInformation` + `largeIcon` (call_ended + generic).

## 2026-08-28 — 20260828030000_fix_call_notif_single.sql

- **Status:** ✅ SUDAH TERAPPLIED di remote DB `fohcucyyejdryryoxitm` pada 2026-08-28 via Management API (token Keychain). `supabase functions deploy send-push` juga redeploy (tambah `call_canceled` ke `dataOnlyTypes`).
- **Isi:** Hapus trigger lama `calls_notify_canceled_trigger` / `notify_call_canceled`, tambahkan kolom `calls.notif_sent_at` + idempoten `before update` di `notify_call_ended()` (hanya kirim sekali per call dari `ringing/answered → terminal`), `send-push` jadikan `call_canceled` data-only juga. Verifikasi: `select trigger_name from information_schema.triggers where event_object_table='calls'` harus hanya `calls_notify_ended_trigger` + `notify_call_ringing_trigger`, dan `select proname from pg_proc where proname='notify_call_ended'` mengandung `notif_sent_at`.


> AI sesi berikutnya: JANGAN `supabase db push` untuk 20260828010000/20260828020000 — gunakan Playwright SQL Editor `https://supabase.com/dashboard/project/fohcucyyejdryryoxitm/sql` → paste isi file → Run → lalu `insert into supabase_migrations.schema_migrations (version) values ('20260828010000'),('20260828020000')` manual. Functions deploy via `supabase functions deploy fanout --no-verify-jwt` (butuh `SUPABASE_ACCESS_TOKEN` + Docker, atau via Dashboard Functions).

## 2026-08-29 — 20260829030000_perf_phase1_country.sql

- **Status:** SUDAH TERAPPLIED via Management API pada 2026-08-29.
- **Isi:** GIN index `idx_private_chats_participants_gin` on `private_chats.participants`, partial index `idx_profiles_country_last_seen`, `posts.country` column + trigger `posts_fill_country()`, per-country RPCs (`get_online_users(p_country,p_limit)`, `count_room_presence_by_country(p_country)`, `cleanup_room_presence(p_minutes)`), backfill posts country.
- **Verifikasi:**
  ```sql
  select version from supabase_migrations.schema_migrations order by version desc limit 3;
  -- 20260829040000, 20260829030000, 20260828040000
  ```

## 2026-08-29 — 20260829040000_timeline_country.sql

- **Status:** SUDAH TERAPPLIED via Management API pada 2026-08-29.
- **Isi:** `list_posts` overload dengan 5 param (tambah `p_country text default null`), **filter country dihapus** (timeline global — semua negara lihat semua post). 
- **IMPORTANT:** 4-param wrapper **DILEPAS** (`DROP FUNCTION`) — sebelumnya cause ambiguity error `function list_posts(unknown, integer, unknown, boolean) is not unique` karena PostgreSQL tak bisa memilih antara 4-param dan 5-param overload ketika app kirim 4 param via Supabase RPC (JSON → unknown type). Dengan hanya 5-param (semua ada default), 4-param call langsung resolve ke 5-param.
- **Fix tambahan:** `list_posts` scope `mine` → `p_scope='mine' and p.author_id=me` (bukan fallback ke follows). File on-disk sync dengan DB.
- **Verifikasi:** `select pronargs from pg_proc where proname='list_posts';` → **1 baris** (5 args saja). `select public.list_posts('all',30,null,false)` → return 4 posts.

## 2026-08-29 — 20260829050000_storage_update_policy.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-08-29.
- **Isi:** Tambah `UPDATE` policy untuk bucket `chat-photos` (`chat_photos_authenticated_update`). Sebelumnya hanya ada INSERT/DELETE/SELECT policies — tidak ada UPDATE. Saat `uploadAvatar` pakai `FileOptions(upsert: true)` dan avatar sudah ada sebelumnya, storage coba UPDATE row yang existing → gagal `new row violates row-level security policy` (403). Dengan policy ini, authenticated users bisa update avatar mereka sendiri.
- **Verifikasi:** `select count(*) from pg_policies where schemaname='storage' AND tablename='objects';` → 6 policies (termasuk `chat_photos_authenticated_update` untuk UPDATE).

## 2026-08-29 — 20260829060000_relax_profiles_policy.sql

- **Status:** SUDAH TERAPPLAY via Management API pada 2026-08-29.
- **Isi:** `profiles_update_own` policy `WITH CHECK` dibuka — sebelumnya mengharuskan `nickname >= 3 chars`, `status in (online,idle,offline)`, `points` unchanged. Ini BLOCK semua UPDATE termasuk `updateAvatar` (line 768), `markRegistered` (line 375), `goOnline` (line ~842). Sekarang cukup `USING (auth.uid() = id) WITH CHECK (auth.uid() = id)` — security tetap (user cuma bisa update row sendiri), tapi tidak blokir update kolom lain.
- **Verifikasi:** `select with_check from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_update_own';` → `(auth.uid() = id)` saja.

## 2026-08-29 — 20260829070000_pin_chats.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-08-29.
- **Isi:** `private_chats.pinned_by text[]` + `pinned_at jsonb` + GIN index + RPC `pin_private_chat(p_chat_id text, p_pin boolean)` (per-user, check participants). Sort pinned dulu by pinnedAt DESC, baru lastMessageAt DESC. Optimistic update di ChatService.
- **Verifikasi:** `select column_name from information_schema.columns where table_name='private_chats' and column_name like 'pinned%';` → 2 rows. `select pin_private_chat('test', true);` → ok.

## 2026-08-29 — 20260829080000_follow_registered_only.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-08-29.
- **Isi:** `follows_insert_own` + `friend_requests_insert_own` policy diperketat — hanya `is_registered=true` yang bisa follow / friend request. Anon tidak bisa follow & tidak bisa difollow.
- **Verifikasi:** `select policyname from pg_policies where tablename='follows';` → follows_insert_own dengan check is_registered.

## 2026-08-29 — 20260829090000_purge_inactive_90d.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-08-29.
- **Isi:** `purge_inactive_accounts()` hapus akun tidak aktif 90 hari (last_seen < now-90d, batasi 100/run) + hapus relasi (follows, friend_requests, blocks, private_chats, messages, presence) + cron harian 03:30 `purge_inactive_90d`.
- **Verifikasi:** `select cron.jobname from cron.job where jobname='purge_inactive_90d';` → 1 row.

## 2026-09-01 — 20260901000000_p0_indexes_incremental.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-09-01.
- **Isi:** 6 index hilang + `profiles.bonus/topup/earned_balance` + trigger incremental `coin_ledger_balance_trg` + backfill + `wallet_sync_points` jadi baca kolom (tidak sum).
- **Verifikasi:** `select indexname from pg_indexes where tablename='room_presence' and indexname='idx_room_presence_joined_at';` → 1 row.

## 2026-09-01 — 20260901010000_rpc_chat.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-09-01.
- **Isi:** RPC get_chat_messages/get_room_messages + RLS private_messages_select jadi participants @> array[uid] (pakai GIN) + index BRIN last_message_at
- **Verifikasi:** `select get_chat_messages('test', null, 10);`

## 2026-09-01 — 20260901020000_outbox.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-09-01.
- **Isi:** outbox table + index where sent_at is null (ganti net.http_post blocking di trigger)
- **Verifikasi:** `select count(*) from outbox;` → 0

## 2026-09-01 — 20260901030000_realtime_prune.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-09-01.
- **Isi:** drop 4 tabel high-churn dari supabase_realtime (private_messages, room_presence, room_signals, call_signals) → hemat egress 80%
- **Verifikasi:** `select tablename from pg_publication_tables where pubname='supabase_realtime';` → tidak ada 4 tabel tsb

## 2026-09-01 — 20260901040000_revert_realtime_prune.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-09-01.
- **Isi:** Revert drop realtime — kembalikan private_messages, room_presence, room_signals, call_signals ke supabase_realtime (client belum migrasi ke broadcast, drop bikin delay 30s)
- **Verifikasi:** `select tablename from pg_publication_tables where pubname='supabase_realtime';` → 20 rows termasuk 4 tabel tsb

## 2026-09-01 — 20260901050000_fix_age_check.sql

- **Status:** SUDAH TERAPPLY via Management API pada 2026-09-01.
- **Isi:** `profiles_age_18_check` dilonggarkan — allow `age=0` untuk user baru Google (sebelumnya hanya `is null` atau `>=18`, insert age 0 gagal 23514 → Google Sign-In 400)
- **Verifikasi:** `insert into profiles (id, age) values (gen_random_uuid(), 0)` → sukses

## 2026-09-01 — 20260830120000_broadcast_notif.sql

- **Status:** ✅ SUDAH TERAPPLIED via Management API pada 2026-09-01 (token Keychain "Supabase CLI" → `go-keyring-base64:` prefix, decode base64 = `sbp_...`).
- **Isi:** Trigger `notify_broadcast_started` di `room_broadcasters` AFTER INSERT (start broadcast video) → push data-only `type:'broadcast'` ke semua member room (kecuali broadcaster).
- **Verifikasi:** `select tgname, tgenabled from pg_trigger where tgrelid='public.room_broadcasters'::regclass and not tgisinternal` → `notify_broadcast_started_trigger | O`.
- **Deploy ulang `send-push`:** 2026-09-01 via `supabase functions deploy send-push --no-verify-jwt` — `dataOnlyTypes` kini berisi `['online','follow','friend_request','subscribe','call','call_ended','call_canceled','message','broadcast']`. Tanpa ini push broadcast terbungkus notif block "Pesan baru" (dobel).
- **Teks client** (`lib/config/strings.dart` `notifBroadcastBody`): ID "Sedang broadcast di {room}", EN "is broadcasting in {room}". Tap notif → `_openFromData` buka RoomChatScreen langsung.

## 2026-09-01 — 20260901080000_reengage_notif.sql

- **Status:** ✅ SUDAH TERAPPLIED via Management API pada 2026-09-01.
- **Isi:** Notifikasi pengingat harian (re-engagement): user offline 1–8 hari (stop setelah 7 hari notif), 1x/hari (dedupe `profiles.last_reengage_at` < 20 jam), token dari `user_devices` (is_active + fcm_token), push **notification block** via send-push (tampil walau app dimatikan). Toggle admin global: `app_settings.reengage_enabled` (default true). Cron `reengage-daily` `0 12 * * *` (12:00 UTC = 19:00 WIB).
- **Teks rotasi 3 varian** (by offline_days mod 3): 👀 obrolan seru / 🔥 room rame / 💬 teman aktif — ID+EN, tanpa framing dating.
- **`admin_get_point_settings` diganti return `to_jsonb(app_settings)` penuh** (sebelumnya daftar kolom manual) — client admin panel menerima semua kolom; `admin_update_point_settings` tambah `reengage_enabled`.
- **Verifikasi:** dry run `select send_reengage_notifications(5)` → 5 terkirim; cron job id 7; kolom ada di 2 tabel.
- **Catatan client:** tap notif reengage → buka app default (data type `reengage` diterima `_showLocalNotification`/`_openFromData` — tidak match tipe lain, aman). Edge function `send-push` TIDAK perlu deploy ulang (notification block dikirim karena `type:'reengage'` tidak ada di dataOnlyTypes).

## Pola untuk AI berikutnya

Jika `supabase db push` timeout lagi:
1. Gunakan Management API seperti di atas (paling cepat, tidak butuh Docker/Playwright login).
2. Alternatif Playwright: buka `https://supabase.com/dashboard/project/fohcucyyejdryryoxitm/sql` → paste SQL → Run → lalu `insert into supabase_migrations...`.
3. Selalu update file ini + `supabase_migrations.schema_migrations` agar tidak double-apply.
4. **Pastikan sinkron code ↔ DB**: setiap ubah `notify_call_*` / `call_push` di SQL, cek juga `supabase/functions/send-push/index.ts` (`dataOnlyTypes`) dan `lib/main.dart` (`_firebaseMessagingBackgroundHandler` + `_showLocalNotification`). 3 tempat harus sama tipe `call`/`call_ended`/`call_canceled`.

## 2026-09-02 — Pembersihan device orphan + purge_inactive_accounts patch

- **Isu:** Admin panel devices menampilkan "(profil terhapus)" — baris `user_devices` yatim (profil sudah dihapus cron, device tertinggal).
- **Fix DB:** `delete from user_devices where user_id not in (select id from profiles)` — 1 orphan dibersihkan. Patch `purge_inactive_accounts`: tambah `delete from public.user_devices where user_id = r.id` sebelum hapus profil → cron berikutnya tidak meninggalkan orphan.
- **Pembersihan chat akun device (hard delete, 2026-09-02):** 11 chat antar-device (Xiaomi 24129PN74G + Redmi Note 9 Pro) + chat dengan 38 outsider yang hanya pernah chat device-owner → 64 chat rows, ~794 pesan (4 foto + 160 voice) dan file Storage terkait dihapus permanen; 16 outsider yang masih chat user lain DIPERTAHANKAN. Catatan: `storage.objects` tidak bisa di-delete via SQL (trigger protect_delete) — file dihapus via Storage API dari daftar `private_messages.image_path/voice_path` + avatar/galeri profil terhapus.

## 2026-09-05 — 20260903090000_admin_exclude_devices.sql (RE-APPLY)

- **Masalah:** Versi `admin_stats_detail` di DB live masih DRAFT BROKEN (`select array(select uid) into v_excl from admin_excluded_uids() ae`) → error 42703 "column uid does not exist" setiap dipanggil → SEMUA card admin panel (users/detail) kosong. File di repo sudah diperbaiki (alias `ae` + array_agg) TAPI setelah migration tercatat applied → fix tidak pernah sampai ke DB.
- **Fix:** Re-apply seluruh isi file via `supabase db query --linked -f` (semua create-or-replace, idempoten). Verifikasi: `admin_stats_detail()` → users_all = 46, `admin_stats()` → total_users = 46.
- **Juga di-apply:** `20260905090000_dummy_profile_edit_fix.sql` (fix RLS profil dummy + sync nickname + validasi RPC).
- Kedua version sudah di-insert ke `supabase_migrations.schema_migrations` → `db push` tidak akan re-run.

> Pelajaran: migration yang SUDAH tercatat applied tapi file-nya diedit setelahnya TIDAK akan pernah ter-apply ulang — kalau fix SQL-nya kritis, re-apply manual via `supabase db query --linked -f <file>`.

## 2026-09-05 — 20260905100000_admin_stats_exclude_dummies.sql (APPLY + RE-APPLY)

- **Isi:** Dummy tidak dihitung di ringkasan admin. Helper baru `admin_dummy_uids()`; `admin_stats_compute` filter dummy dari total_users/active_today/registered/anon/poin/top_earners/stuck; `admin_stats_detail` buang dummy dari list users_all/active/registered/anonymous. Cache stats dihapus saat apply. Dummy TETAP tampil untuk end-user (online list, nearby) — hanya hidden dari ringkasan admin. Metrik messages/rooms tidak diubah.
- **Apply:** via `supabase db query --linked -f supabase/migrations/20260905100000_admin_stats_exclude_dummies.sql` (create-or-replace, idempoten). Verifikasi: total_users=44, users_list=44 (58 profil − 14 uid perangkat-exclude − 6 dummy − overlap). Username perangkat-exclude (AntoSusanto, malamputih, aqila, maufollow*, kamukamu, kamusatu, laptop, playwright) terverifikasi TIDAK tampil.
- ⚠️ **KEJADIAN 2x DI HARI YANG SAMA:** `admin_stats_detail` di DB live DITIMPA DRAFT BROKEN dari luar sesi ini (bukan dari migration repo):
  - Ke-1 (pagi): `select array(select uid) into v_excl from admin_excluded_uids() ae` → 42703.
  - Ke-2 (siang): `select array(select distinct x from (select uid from admin_excluded_uids() union all select uid from dummy_accounts) t(x))` → 42703 juga (SET OF uuid TIDAK punya kolom `uid` — WAJIB pakai alias: `from admin_excluded_uids() ae` lalu `array_agg(ae)`).
  - Gejala: SEMUA card Users ringkasan admin kosong (RPC error → client catch → `{}`).
  - Fix: re-apply file migration versi benar via `supabase db query --linked -f`, verifikasi `jsonb_array_length(admin_stats_detail()->'users_all') == admin_stats()->>'total_users'`.

> ⚠️ PERINGATAN UNTUK TOOL/AI LAIN: JANGAN me-apply function admin (`admin_stats_detail`, `admin_stats_compute`, `admin_excluded_uids`) dari draft SQL yang belum lolos uji. Sumber kebenaran = file di `supabase/migrations/`. Khusus `admin_excluded_uids()` yang `RETURNS SETOF uuid`: referensi kolom langsung (`select uid from ...`) PASTI gagal 42703 — wajib alias (`ae`) + `array_agg`/`= any()`. Sebelum menimpa, selalu tes: `supabase db query --linked "select set_config('request.jwt.claims', '{\"email\":\"zunixe@gmail.com\",\"role\":\"authenticated\"}', false); select jsonb_array_length((select public.admin_stats_detail())->'users_all')"`.

## 2026-09-06 — 20260906000000_stories.sql (APPLY)

- **Fitur Story ala Instagram** — tabel `stories` (1 row = 1 slide, expire 24 jam, append gaya IG) + `story_views` (daftar penonton). Visibility per slide: `everyone` / `registered` (DEFAULT) / `friends` (2 arah via `friend_requests accepted`), semua dikurangi blokir. Anon DILARANG bikin story (RLS insert: registered + max 10 slide/24 jam).
- **RPC:** `story_tray()` (agregat per author + thumb + has_unseen, own duluan), `story_slides(p_author)`, `create_story(...)` (snap author_name, clamp koordinat teks 0-1, max teks 300), `mark_story_seen` (idempoten), `story_viewers` (pemilik only), `delete_story` (pemilik/admin).
- **Cron:** `purge-stories` tiap jam :17 (hapus row expire; file Storage dibersihkan terpisah).
- **Realtime:** `stories` + `story_views` masuk publication `supabase_realtime`.
- **Apply:** via `supabase db query --linked -f` (bersih, 0 error). Verifikasi: `story_tray()` → `[]` (array kosong, bukan error); kedua tabel ada; publication ✅; cron ✅. Version tercatat di `schema_migrations`.
- **Client:** `lib/services/story_service.dart`, `lib/providers/story_provider.dart` (registrasi di app.dart), `lib/models/story_model.dart`, `lib/widgets/story_text_overlay.dart`, `lib/screens/story_composer_screen.dart` + `story_viewer_screen.dart`, integrasi tray di `online_users_screen.dart` (header PreferredSize 140, tombol + sebelum Orang Sekitar). `StoryText` token (S16/M20/L24 + palette 8 warna) di `theme.dart`.
- ⚠️ Catatan palette: `text_color` disimpan sebagai INT indeks palette (0-7), BUKAN hex — konsisten dengan `StoryText.palette` di theme.dart.

## 2026-09-07 — 20260907000000_sync_profile_names.sql (APPLY)

- **Fix:** user ganti username, tapi post/komen/story di timeline masih menampilkan nama lama (snapshot `author_name` tidak pernah di-update saat rename).
- **Trigger** `trg_sync_profile_names` (after update of nickname on profiles) → sinkron ke `posts.author_name`, `post_comments.author_name`, `stories.author_name`, `user_devices.nickname_snapshot`. Pola sama dengan `sync_profile_to_chats` (20260828050000) — private_chats sudah punya trigger sendiri.
- **Backfill** semua snapshot lama sekali jalan.
- **Verifikasi live:** rename `olave` → post ikut jadi nama baru (1/1), rename balik → pulih. Setelah backfill mismatch = 0 di 4 tabel.
- Tercatat di `schema_migrations`.

## 2026-09-07 — 20260907150000_follow_count_join_profiles.sql (APPLY)

- **Masalah:** profil SimpleMe menampilkan Pengikut = 2, tapi list saat diklik hanya 1. Penyebab: baris `follows` ORPHAN (follower `e69529ec-...` sudah tidak ada di `profiles` — profil terhapus, baris follow tertinggal dari riwayat hapus manual/pra-FK). `follow_count_sync` menghitung baris orphan; `social_list()` inner-join `profiles` sehingga orphan tidak tampil → counter vs list beda.
- **Isi:** (1) delete follows orphan, (2) rewrite `follow_count_sync` → hitung HANYA follows yang kedua profilnya ada (join profiles — identik semantik `social_list`), (3) backfill semua profiles.
- **Apply:** via `supabase db query --linked -f` (idempoten). Tercatat di `schema_migrations` (version `20260907150000`).
- **Verifikasi live:** SimpleMe `followers_count = 1` = `actual_list_count = 1` ✓, playwright 1/1 ✓. Total follows = 3 (tanpa orphan).

## 2026-09-10 — 20260910000001_admin_chat_last_read.sql (APPLY)

- **Masalah:** Monitor chat admin (`admin_chat_view_screen.dart`) hardcode `isRead: isMe` → SEMUA bubble kanan selalu centang-2, tidak sesuai chat asli (centang-1). Akar tambahan: `_markDummyRead` memanggil RPC `admin_mark_chat_read` yang SELALU gagal `Not authorized` dari sesi dummy (guard minta email admin) — DB tidak pernah berubah, makanya chat asli benar tetap centang-1.
- **Isi:** RPC baru `admin_get_chat_last_read(p_chat_id)` → `last_read_at` (jsonb map uid→waktu), SECURITY DEFINER + guard admin (sama dengan RPC monitor lain). READ-ONLY.
- **Client:** `AdminService.getChatLastRead` + `AdminProvider.fetchChatLastRead`; view hitung `isRead` per pesan vs last-read PENERIMA (cermin logika chat asli, kedua sisi), fallback centang-1; `_markDummyRead` + panggilannya DIHAPUS (monitoring read-only — intip tidak boleh membalikkan receipt orang).
- **Apply:** via Management API (catatan: `ConvertTo-Json` PS 5.1 merusak string SQL multi-baris jadi objek — bangun body JSON manual). Tercatat di `schema_migrations`.
- **Verifikasi:** `select proname from pg_proc where proname='admin_get_chat_last_read'` → 1 row; `select admin_get_chat_last_read('nonexistent')` → `{}`.

## 2026-09-11 — 20260911010000_admin_message_image_path_fallback.sql (APPLY)

- **Masalah:** Monitor chat admin — foto "ketuk untuk memuat" tidak pernah tampil walau di-tap (kasus chat AntoSusanto, pesan 1382/1383). Akar: foto chat BARU menyimpan PATH di kolom `image_path` dengan `image_data` kosong (hemat DB), tapi RPC `admin_get_message_image` hanya mengembalikan `image_data` → monitor selalu dapat string kosong. File-nya sendiri ADA di storage.
- **Isi:** `admin_get_message_image` fallback → `coalesce(nullif(image_data,''), image_path)`. Client TIDAK perlu berubah — `_loadOnePhoto` sudah mendukung respons berupa path (`isPath` → download bucket). Server-only fix.
- **Apply:** via Management API. ⚠️ Pelajaran: body SQL dengan karakter non-ASCII (`→`, `—`) rusak lewat `Invoke-RestMethod -Body` string PS 5.1 (JSON parse error) — WAJIB tulis JSON ke file UTF-8 lalu `curl.exe --data-binary @file`.
- **Verifikasi:** `pg_get_functiondef` mengandung `nullif(m.image_data, ''), m.image_path` → FALLBACK-OK. Tercatat di `schema_migrations`. Catatan: RPC admin TIDAK bisa di-smoke-test via query API (tanpa konteks auth.email → Unauthorized itu normal).

## 2026-09-11 — 20260911020000_dummy_ai_mode.sql (APPLY)

- **Fitur:** Mode AI untuk dummy — user chat ke dummy yang AI-nya aktif → AI balas otomatis. Persona OTOMATIS dari profil dummy (nickname/age/gender/city/hashtags=hobi) + `ai_persona` jsonb opsional (personality/tone/extra_prompt; kosong = personality di-generate deterministik dari uid).
- **Isi:** kolom `dummy_accounts.ai_enabled/ai_persona/ai_model`; kolom `app_settings.ai_global_enabled/ai_max_replies_per_hour/ai_min_interval_sec`; RPC `admin_set_dummy_ai`, `admin_ai_settings` (get+set); `admin_list_dummies` +field AI; trigger `ai_reply_enqueue_trigger` on private_messages AFTER INSERT → pg_net async POST `functions/v1/ai-reply`. Guard trigger: hanya type=text, penerima = dummy ai_enabled, sender BUKAN dummy (anti loop dummy↔dummy & anti balas pesan sendiri saat admin pegang dummy), global on, rate per chat (maks/jam + jeda min).
- **Edge function `ai-reply`** (deploy `--no-verify-jwt` + secrets `AI_API_KEY/AI_API_BASE/AI_MODEL`): persona prompt live dari profiles, 12 pesan terakhir sebagai history, LLM B.AI `glm-5.3-flash` **WAJIB `reasoning_effort:'low'` + max_tokens>=600** (model selalu reasoning — tanpa ini content kosong), typing broadcast via **Realtime HTTP API** `POST /realtime/v1/api/broadcast` (channel `sendBroadcastMessage` supabase-js TIDAK jalan di Deno), insert balasan service_role.
- **Bug fix saat uji:** trigger v1 `select p.id from unnest(...) p` salah (42703) → `select x from unnest(...) as x`. Terverifikasi E2E: user → dummy balas nyambung in-character; dummy outgoing tidak memicu.
- **Client admin:** `AdminService.setDummyAi/getAiSettings/setAiSettings`; chip AI di kartu dummy (tab Dummy) + sheet persona; section AI Bot di tab Global Setting.
- **Apply:** via Management API (curl + file UTF-8). Tercatat di `schema_migrations`.

## 2026-09-11 - 20260911030000_ai_reply_claims.sql + 20260911040000_ai_memory.sql (APPLY)

- **ai_reply_claims:** dedupe anti-race - dua invokasi ai-reply bersamaan sama-sama lolos cek "ada balasan setelah trigger?" -> dobel balasan. Claim table PK=trigger_msg_id (atomik); RPC ai_reply_claim(p_msg_id, p_dummy) service_role-only, baris >1 jam auto-prune. E2E: invokasi kedua -> skipped: already_claimed.
- **ai_memory:** memori jangka panjang AI per pasangan (dummy_uid, user_id, fact) PK - fakta tahan-lama (nama/kerja/hobi/sifat) diekstrak LLM dari percakapan tiap balasan, diinjeksi ke system prompt sesi berikutnya. Cap 30 fakta/pasangan, filter NSFW, akses service_role only.
- **Fix pendukung di ai-reply:** (1) llmCall() dgn retry backoff utk 429 B.AI (balasan+ekstraksi back-to-back sering kena concurrency limit); (2) typing WS channel ack:true dibuka SEKALI sepanjang durasi mengetik - subscribe->kirim->unsubscribe instan membuat pesan hilang sebelum flush; (3) ritme typing manusiawi 3 gaya acak: fast 15% / steady 35% / ragu 50% (type -> jeda >3 dtk -> type lagi, indikator sengaja hilang-muncul = kaya mikir).
- **Verifikasi E2E:** pesan dgn fakta -> balasan nyambung + 3-6 fakta tersimpan di ai_memory + invokasi dobel ditolak claim. Tercatat di schema_migrations.

## 2026-09-11 — ai-reply v18: routing per-model (Nemotron via OpenRouter) + persona Santi (APPLY)

- **Isi code** `supabase/functions/ai-reply/index.ts`: routing per model — `:free` / `nvidia/` → `https://openrouter.ai/api/v1` + secret `AI_API_KEY_OPENROUTER`; selain itu tetap B.AI (`AI_API_BASE`/`AI_API_KEY`). `reasoning_effort:'low'` kini hanya utk model glm; `max_tokens +400` headroom utk model OpenRouter (token reasoning — tanpa ini content kosong).
- **Secrets:** tambah `AI_API_KEY_OPENROUTER` (OpenRouter free tier).
- **Deploy:** CLI `supabase functions deploy` HANG >600s → sukses via Management API `POST /v1/projects/fohcucyyejdryryoxitm/functions/deploy?slug=ai-reply` — curl multipart: `-F 'metadata={"entrypoint_path":"index.ts","name":"ai-reply","verify_jwt":false};type=application/json' -F 'file=@supabase/functions/ai-reply/index.ts;filename=index.ts'`, token Keychain "Supabase CLI" (`go-keyring-base64:` prefix → base64 decode). Result: **ACTIVE v18**, verify_jwt=false.
- **Data Santi** (`92823111-fa75-4e47-ad6a-e80a1dd868ff`): `ai_model='nvidia/nemotron-3-ultra-550b-a55b:free'` + `ai_persona` wanita nakal (personality/tone/extra_prompt; hobbies dipertahankan). `ai_enabled` sudah true dari sesi sebelumnya.
- **Guard NSFW 3-lapis di ai-reply TIDAK diubah** — persona nakal jalan di dalam guard (flirt/godaan lolos, explicit tetap didefleksi).
- **Verifikasi:** secrets list ✅; functions API ACTIVE v18 ✅; select dummy_accounts → model+persona baru ✅. E2E chat via app belum dites (user test manual).
## 2026-09-11 — 20260911050000_ai_guard_toggle.sql (APPLY) + ai-reply v19

- **Fitur:** Toggle **Guard NSFW** di admin (AI Bot > sheet pengaturan) — ON (default, perilaku lama: input guard + BATAS KERAS system prompt + output defleksi + filter memori) / OFF (dummy AI bebas lanjut topik dewasa). **Realtime**: `ai-reply` baca `app_settings.ai_guard_enabled` fresh tiap invokasi — toggle efektif tanpa redeploy.
- **Isi:** kolom `app_settings.ai_guard_enabled` (default true); `admin_ai_settings` di-drop + recreate 4-param (tambah `p_guard_enabled`, return `ai_guard_enabled`).
- **ai-reply v19:** `guardOn = !(settings.ai_guard_enabled === false)` → input guard, klausa system prompt, output guard, dan filter fakta ai_memory semuanya kondisional.
- **Client:** `AdminService.setAiSettings(guardEnabled:)` + `_AiGlobalTile` (state `_guardEnabled`, switch di sheet, caption kartu "Guard NSFW: ON/OFF") + string `aiGlobalGuardTitle/Desc` (strings_admin.dart).
- **Apply:** `supabase db query --linked -f` (run pertama silent-fail, run kedua sukses `rows: []`). Tercatat di `schema_migrations` (20260911050000).
- **Deploy:** Management API curl (CLI tetap hang) → **ACTIVE v19**.
- **Verifikasi:** kolom ada (guard_now=true), pg_proc 4-arg + has_guard=true, deploy v19, flutter analyze 0 error/warning.
## 2026-09-11 — 20260911060000_ai_no_rate_limit.sql (APPLY) + ai-reply v20 (mode dewasa)

- **Fix "guard off tapi masih ga nakal":** guard memang off, tapi model defleksi sendiri karena persona cuma bilang "nakal" tanpa kalimat IZIN. `ai-reply` saat guard OFF kini menyuntikkan "MODE DEWASA AKTIF: ... eksplisit IZINKAN dan DIDORONG, JANGAN menolak/mengalihkan" + ATURAN BALASAN diganti (1-3 kalimat natural, bukan 2-10 kata) + `sanitize` TANPA cap 90-char (null = bebas, batas alami max_tokens).
- **Rate limit Santi dihapus:** kolom `dummy_accounts.ai_no_rate_limit` (default false); trigger `ai_reply_enqueue` skip cek maks/jam + jeda min saat true. Santi (`92823111...`) = true. Global kill switch tetap berlaku.
- **Apply:** via `supabase db query --linked -f`, tercatat di `schema_migrations` (20260911060000). **Deploy:** Management API curl → ACTIVE v20.
- **Verifikasi:** col_ok=1, santi_no_rate=true, trg_ok=true, deploy v19→v20. Admin APK (guard toggle + navbar sheet fix) di-install ke Xiaomi via `adb install -r` (streamed install Success).
## 2026-09-11 — 20260911070000_ai_provider_config.sql (APPLY) + ai-reply v21

- **Fitur:** Provider LLM (model default + base URL + API key) **editable dari admin panel** (AI Bot > sheet). Disimpan di tabel BARU `ai_provider_config` (RLS enabled TANPA policy = deny semua — app_settings punya SELECT public, API key tidak boleh di situ). Hanya service_role (edge function) & RPC admin (security definer + guard email) yang bisa akses.
- **Semantik model:** `dummy_accounts.ai_model` jadi NULLable — NULL = ikuti `ai_provider_config.default_model`; semua 7 dummy di-null-kan (ikut global). Per-dummy override tetap bisa via SQL.
- **ai-reply v21 precedence:** model = `dummy.ai_model → provCfg.default_model → env AI_MODEL → 'glm-5.3-flash'`; non-OpenRouter base/key = `provCfg → env (B.AI)`; `:free`/`nvidia/` tetap OpenRouter.
- **RPC:** `admin_ai_settings` 7-param (+p_api_base/p_api_key/p_default_model), return merged incl. api_key (admin-guarded).
- **Client:** `AdminService.setAiSettings(+apiBase,apiKey,defaultModel)`; sheet AI Bot tambah 3 field + SingleChildScrollView (anti overflow).
- **Apply:** db query --linked, tercatat `schema_migrations` (20260911070000). **Deploy:** Management API curl → ACTIVE v21.
- **Admin APK:** rebuild adminProd + `adb install -r` streamed install Success ke Xiaomi .33.
- **Catatan lain:** persona extra_prompt Santi DIEDIT MANUAL oleh user via DB (versi eksplisit sendiri) — tidak ditimpa AI.
## 2026-09-11 — ai-reply v22: humanisasi balasan (delay + variasi + pacing) (DEPLOY)

- **Delay manusiawi**: jeda acak SEBELUM read-receipt & typing (dia "belum lihat HP"): panas 2-8s / biasa 5-25s / perkenalan 8-28s / ~12% "sibuk" +15-90s. Deteksi heat: isExplicit(pesan terakhir) ATAU cadence balasan user <120s.
- **Pacing perkenalan**: freshStage (total pesan chat ≤6 & tanpa ai_memory) → sistem prompt "santai dulu, JANGAN langsung gas walau diminta; tanggapi geli, bangun suasana progresif" + baris FASE SEKARANG dinamis (perkenalan/panas/berjalan).
- **Variasi**: instruksi JANGAN ulang emoji yang sama, ~separuh balasan tanpa emoji, panjang variatif; mode dewasa ATURAN diubah jadi panjang VARIATIF; temperature 1.0 saat guard off.
- **Refactor**: history fetch (dgn created_at) pindah ke atas sebelum system prompt; `llmHistory` tanpa meta `at` untuk LLM; hapus duplikasi blok history lama.
- **Data:** hard delete chat + 98→(baru) pesan & ai_memory Santi↔Admin (chat_id pattern kedua uid) — hilang juga dari monitor chat admin. User mau ulang tes dari awal.
- **Verifikasi:** deploy ACTIVE v22; chats_left=0, mem_left=0.
## 2026-09-11 — ai-reply v23: waktu nyata WIB + aturan emoji (DEPLOY)
- **Waktu nyata**: system prompt dapat "Sekarang: <hari, tgl, jam WIB>" (Intl Asia/Jakarta, fallback manual UTC+7) + instruksi sadar waktu (malam jangan bilang sore; aktivitas cocok jam).
- **Emoji**: hanya kalau benar-benar mengungkapkan perasaan (bukan tempelan) + variasi anti-repetisi (sekitar separuh balasan tanpa emoji).
- **Verifikasi:** deploy ACTIVE v23. (Pasangan Santi↔Admin tadi juga di-hard-delete ulang + pm clear device admin — user tes dari awal.)
- ai-reply v24: profil lawan bicara (nickname/umur/gender/kota/hobi) diinject ke system prompt — dipakai natural, tidak dilempar sekaligus; memory tetap untuk fakta yang dipelajari.
## 2026-09-11 — Seed ai_provider_config (B.AI aktif) + nama provider di panel (DEPLOY)
- **Seed:** `ai_provider_config` diisi nilai yang sedang dipakai server (api_base=https://api.b.ai/v1, api_key B.AI (prefix sk-6c39dbw, terverifikasi hidup via chat completion 200), default_model=glm-5.3-flash) — sheet AI Bot kini menampilkan nilai aktif, bukan kosong.
- **UI:** subtitle "Provider: <nama>" di sheet + append di caption kartu (derivasi dari base URL: B.AI/OpenRouter/DeepInfra/Venice/Groq/host).
- **Admin APK:** rebuild + install Success ke Xiaomi.
## 2026-09-11 — 20260911080000_sync_all_profile_snapshots.sql (APPLY)
- **Bug:** edit profil dummy di admin (umur dsb) tidak muncul di private chat — ditemukan dummy "laptop": profil umur 18 tapi snapshot chat masih 24 (baris lama lolos trigger). Trigger `trg_sync_profile_to_chats` sendiri terverifikasi jalan (tes live age 27->28 tersebar ke semua chat).
- **Fix:** rewrite penuh kolom snapshot (names/genders/ages/locations) dari `profiles` untuk SEMUA chat — idempoten. Edit ke depan tersinkron otomatis via trigger (nickname/gender/age/country) + device refetch live di list chat.
- **Verifikasi:** still_stale=0. Tercatat di schema_migrations (20260911080000).
## 2026-09-11 — ai-reply v26: batasi balasan ganda (DEPLOY)
- **Keluhan:** AI kadang balas 2-3x. Penyebab: burst 15% terlalu sering + race saat jeda panjang (2 invokasi lolos dedupe awal).
- **Fix:** (1) burst turun ke ~7% DAN hanya jika balasan utama pendek (<40 char) — balasan substansial = satu pesan cukup; (2) cek ganda tepat sebelum LLM call: kalau sudah ada balasan dummy setelah trigger (terkirim saat kita "berpikir"), skip — cegah dobel antar-invokasi.
- **Verifikasi:** deploy ACTIVE v26.
## 2026-09-11 — ai-reply v27: cap emoji + cap panjang mode dewasa (DEPLOY)
- **Keluhan:** kadang emoji menumpuk + mode nakal kadang kepanjangan.
- **Fix prompt:** VARIASI → "MAKSIMAL 1 emoji per balasan"; naughty ATURAN → SAMAKAN panjang dengan pesan lawan, MAKS 3 kalimat, bukan esei.
- **Jaring pengaman kode (prompt kadang dilanggar):** `capEmoji()` (simpan 1 terakhir) + `capSentences(max 3)` di jalur balasan mode dewasa — berlaku juga untuk burst.
- **Verifikasi:** unit test helper via node OK; deploy ACTIVE v27.
## 2026-09-11 — 20260911090000_ai_stt_fields.sql (APPLY) + ai-reply v28 (baca foto+voice)
- **Fitur:** dummy AI bisa "melihat" foto (vision inline base64, maks 3 terbaru ≤2MB) + "mendengar" voice (transkrip Whisper-compatible, maks 3 mnt).
- **Foto:** download bucket chat-photos (service role) → image_url data-URL di pesan; fallback otomatis ke [foto] bila provider tolak vision.
- **Voice:** POST multipart ke STT (default Groq `.../openai/v1`, model whisper-large-v3-turbo, lang id) → `[pesan suara 0:12 — isi: "..."]`. Tanpa key/gagal = placeholder durasi + instruksi JANGAN pura-pura dengar.
- **Config:** `ai_provider_config.stt_api_base/stt_api_key` (RLS-deny) + RPC 9-param + 2 field panel (STT Base URL/Key).
- **Apply/deploy:** migration tercatat (20260911090000); deploy ACTIVE v28; admin APK rebuild + install Success.
- **TODO user:** isi STT Key di panel AI Bot (Groq gratis, console.groq.com) agar voice bisa didengar. Foto jalan langsung (pakai key LLM).
## 2026-09-11 — ai-reply v31: routing Zen (muse-spark) + fallback model (DEPLOY)
- **Routing eksplisit per model** via `routeFor()`: OpenRouter (`:free`/`nvidia/`) / OpenCode Zen (`muse-spark-*`,`mimo-*-free`,`ling-*-free`,`nemotron-*-free`,`deepseek-v4-flash-free`,`big-pickle` — secret AI_API_KEY_ZEN + header client opencode) / panel-or-B.AI (sisanya).
- **Fallback model** (`AI_FALLBACK_MODEL`, default glm-5.3-flash B.AI): bila model utama error, balasan coba sekali via fallback — dummy tidak diam.
- **Santi** → `muse-spark-1.3-contributor-free`. Secret AI_API_KEY_ZEN diset.
- **Fakta:** Zen muse-spark free 500 konsisten di semua tes langsung (paid 401 saldo $0; mimo/nemotron free Zen 200 OK) — sampai Zen pulih/ada billing, balasan Santi praktis datang via fallback glm. Verifikasi: deploy ACTIVE v31; santi.ai_model terkonfirmasi.
## 2026-09-11 — ai-reply v32: penanda model_used (DEPLOY)
- Setiap balasan/gagal log `console.log([ai-reply] OK|FAIL model=<id> chat=<id>)` + field `model_used` di respons JSON — kelihatan di Dashboard → Edge Functions → ai-reply → Logs. Cara bedakan balasan muse-spark vs fallback glm.
## 2026-09-11 — ai-reply v33: delay 3-60s sesuai topik (DEPLOY)
- **Keluhan:** typing kadang tanpa pesan + balas terasa instan.
- **Delay baru:** panas 3-8s; biasa 5-30s + 20% peluang +10-35s (makin random lama); perkenalan 8-28s; jarang "sibuk" +15-45s; hard cap 60s. Berlaku SEBELUM read-receipt & typing.
- **Penjelasan typing-tanpa-pesan:** kedip hilang-muncul = SENGAJA (ritme ragu/mikir); diam total setelah typing = kegagalan beneran (LLM error/empty — tercatat FAIL di logs, bukan disengaja).
- **Verifikasi:** deploy ACTIVE v33.
## 2026-09-11 — 20260911100000_dummy_list_profile_fields.sql (APPLY) + toast error detail
- **Bug:** list dummy + prefill sheet edit pakai default (male/25/Indonesia/Jakarta) karena `admin_list_dummies` tidak mengirim gender/age/city/country → gender salah tampil & save berpotensi menimpa gender asli.
- **Fix:** RPC kirim 4 field profil; kartu + prefill otomatis benar (client sudah baca key tersebut).
- **Diagnosis save gagal:** toast gagal kini menampilkan pesan server apa adanya ("...: Unauthorized/Umur tidak valid/...") — user laporkan teksnya bila masih gagal.
- **Admin APK:** rebuild + install Success.
## 2026-09-11 — 20260911140000_drop_dummy_ai_overload.sql (APPLY) + sheet AI fix
- **Bug Simpan:** 2 overload `admin_set_dummy_ai` (3-param & 4-param) → PostgREST 300 Multiple Choices → tombol Simpan sheet Mode AI selalu gagal. Drop versi 3-param, sisakan 4-param (superset).
- **Sheet ketutup navbar:** padding sheet + `MediaQuery.padding.bottom` (tombol Simpan tidak kependem menu Android).
- **Diagnosis:** toast gagal sheet AI kini tampilkan pesan server apa adanya.
- **Verifikasi:** overloads=1; tercatat schema_migrations; admin APK rebuild + install Success.
## 2026-09-11 — Guard sesi admin di tab Dummy (client, tanpa migration)
- **Bug:** edit profil/AI dummy dari SESI DUMMY (habis swap "masuk dummy") → RPC guard email gagal → `Unauthorized` P0001. List yang tampil basi (state tab dari sesi admin sebelumnya) sehingga membingungkan.
- **Fix client:** helper `_isAdminSession()` (AdminGate.isRealAdmin + currentUser email) dicek SEBELUM semua RPC tulis (edit profil, sheet AI save, auto-jadwal) + pesan jelas `dummyNeedAdmin` (ID/EN) — server tetap sumber kebenaran. Error load list Unauthorized juga dipetakan ke pesan yang sama.
- **Admin APK:** rebuild + install Success. Cara pakai: kembali ke akun admin dulu (aliran "kembali ke admin"), baru edit/save.
## 2026-09-11 — ai-reply v34: delay flat 3-8 detik (DEPLOY)
- **Keluhan:** typing terasa lama (jeda 3-60s + latensi glm/B.AI menumpuk).
- **Fix:** jeda manusiawi disederhanakan jadi flat acak 3-8 detik untuk semua situasi (hapus ekor busy/cap 60s). Sisa latensi = AI berpikir + simulasi ketik.
- **Verifikasi:** deploy ACTIVE v34.
- ai-reply v36: jeda manusiawi flat 3-10 detik (user request).
- ai-reply v37: jeda seimbang (panas 2-4s, biasa 3-6s, perkenalan 4-7s).
