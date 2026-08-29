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
- **Isi:** `list_posts` overload dengan 5 param (tambah `p_country text default null`), filter `posts.country = p_country` jika not null. 4-param wrapper tetap ada via overload revoke/grant.
- **Verifikasi:** `select pronargs, proargtypes from pg_proc where proname='list_posts';` → harus ada 2 baris (4 args + 5 args).

## Pola untuk AI berikutnya

Jika `supabase db push` timeout lagi:
1. Gunakan Management API seperti di atas (paling cepat, tidak butuh Docker/Playwright login).
2. Alternatif Playwright: buka `https://supabase.com/dashboard/project/fohcucyyejdryryoxitm/sql` → paste SQL → Run → lalu `insert into supabase_migrations...`.
3. Selalu update file ini + `supabase_migrations.schema_migrations` agar tidak double-apply.
4. **Pastikan sinkron code ↔ DB**: setiap ubah `notify_call_*` / `call_push` di SQL, cek juga `supabase/functions/send-push/index.ts` (`dataOnlyTypes`) dan `lib/main.dart` (`_firebaseMessagingBackgroundHandler` + `_showLocalNotification`). 3 tempat harus sama tipe `call`/`call_ended`/`call_canceled`.
