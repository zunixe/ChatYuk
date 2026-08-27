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

## Pola untuk AI berikutnya

Jika `supabase db push` timeout lagi:
1. Gunakan Management API seperti di atas (paling cepat, tidak butuh Docker/Playwright login).
2. Alternatif Playwright: buka `https://supabase.com/dashboard/project/fohcucyyejdryryoxitm/sql` → paste SQL → Run → lalu `insert into supabase_migrations...`.
3. Selalu update file ini + `supabase_migrations.schema_migrations` agar tidak double-apply.
4. **Pastikan sinkron code ↔ DB**: setiap ubah `notify_call_*` / `call_push` di SQL, cek juga `supabase/functions/send-push/index.ts` (`dataOnlyTypes`) dan `lib/main.dart` (`_firebaseMessagingBackgroundHandler` + `_showLocalNotification`). 3 tempat harus sama tipe `call`/`call_ended`/`call_canceled`.
