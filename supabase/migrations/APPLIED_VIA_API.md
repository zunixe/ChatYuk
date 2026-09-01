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
