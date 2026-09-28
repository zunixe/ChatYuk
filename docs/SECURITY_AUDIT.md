# Audit Security Advisor — Supabase (2026-09-28)

Ringkasan temuan **Security Advisor** Supabase untuk project `ChatYuk`
(`fohcucyyejdryryoxitm`). Total **467 temuan**, mayoritas **WARN/INFO** yang
sudah punya mitigasi internal — hanya beberapa yang perlu tindakan.

> Cara tarik ulang:
> `GET https://api.supabase.com/v1/projects/{ref}/advisors/security`
> (header `Authorization: Bearer <SUPABASE_ACCESS_TOKEN>`).

## Status (sesudah perbaikan 2026-09-28)

**Total 467 → 288** (semua sisa = WARN/INFO yang punya mitigasi/by-design).

| # | Lint | Level | Sebelum | Sesudah | Risiko | Status |
|---|---|---|---|---|---|---|
| 0 | `security_definer_view` (`profiles_public`) | — | 1 | **0** | — | ✅ DONE (`20260928110000`) |
| 3 | `anon_security_definer_function_executable` | WARN | 88 | **32** | Sedang→Rendah | ✅ DONE (`20260928120000`) — sisa 32 = publik by-design |
| 4 | `function_search_path_mutable` | WARN | 28 | **0** | Sedang | ✅ DONE (`20260928130000`) |
| 7 | `auth_leaked_password_protection` | WARN | 1 | **0** | Sedang | ✅ DONE (HIBP enabled) |
| 2 | `authenticated_security_definer_function_executable` | WARN | 277 | **183** | **Rendah** | ✅ DONE sebagian (`20260928140000`) — sisa = fungsi klien |
| 1 | `auth_allow_anonymous_sign_ins` | WARN | 54 | 54 | **Rendah** (by-design) | Tidak perlu — RLS per-baris (`id = auth.uid()`) |
| 5 | `rls_enabled_no_policy` | INFO | 16 | 16 | **Rendah** | OK (deny-all by design) |
| 6 | `extension_in_public` | WARN | 3 | 3 | **Rendah** | ⛔ SENGAJA TIDAK DIUBAH (lihat §6) |

---

## 1. ✅ SUDAH DIPERBAIKI — `profiles_public` (SECURITY DEFINER view)

**Temuan:** *"View public.profiles_public is defined with the SECURITY DEFINER
property."*

**Dampak nyata (bocor):** view milik `postgres` dieksekusi dengan hak OWNER
(menembus RLS `profiles`), di-GRANT `SELECT/INSERT/UPDATE/DELETE/TRUNCATE` ke
`anon` + `authenticated`. Siapa pun (termasuk anon) bisa
`select * from profiles_public` → menarik `avatar`, `last_seen`, `status`
SEMUA user. Ini membatalkan hardening yang mencabut SELECT `profiles.avatar`.

**Verifikasi pendukung:** kolom `profiles` (`avatar`/`last_seen`/`fcm_token`/
`status`) TIDAK punya SELECT untuk anon/authenticated — hardening utuh; view
inilah satu-satunya celah.

**Fix:** `supabase/migrations/20260928110000_drop_profiles_public_view.sql`
(`drop view if exists public.profiles_public;`) — **sudah di-apply**.
Verifikasi: `count(*) profiles_public = 0`. Tidak ada dependensi (0 view/fungsi
lain) & 0 referensi di kode app.

---

## 2. `anon_security_definer_function_executable` (88) — PRIORITAS UTAMA BERIKUT

88 fungsi `SECURITY DEFINER` bisa dieksekusi role `anon`. Sebagian **publik
by-design** (`get_online_users`, `get_room_messages`, `check_email_exists`,
`list_gifts`, `get_points_enabled`, dll). Sebagian lain **ber-guard internal**
(mis. `admin_*` cek `auth.jwt()->>'email'` = email admin). TAPI mengekspos
`EXECUTE` ke anon adalah permukaan serangan — sebaiknya **minimal privilege**.

### Yang WAJIB diaudit (fungsi admin/internal yang bocor ke anon)
```
public.admin_contact_delete          public.admin_contact_messages_page
public.admin_contact_set_read        public.admin_registrations_daily
public.admin_set_privacy_bypass      public.admin_storage_stats
public.admin_sweep_calls             public.get_data_sizes
public.get_table_sizes               public.fn_archive_deleted_user
public.fn_room_role                  public.dummy_uids
public.dummy_heartbeat               public.rls_auto_enable
public.scrub_reply_snapshot_private  public.scrub_reply_snapshot_room
public.profiles_ledger_signup        ...
```
> Catatan: `admin_*` **SUDAH** cek email admin di dalam body (terverifikasi),
> jadi belum tentu bocor — tapi `GRANT EXECUTE` ke anon tetap sebaiknya
> dicabut (defense-in-depth).

### Rekomendasi
`REVOKE EXECUTE ON FUNCTION ... FROM anon, authenticated;` untuk fungsi yang
**bukan** untuk klien, lalu `GRANT EXECUTE` hanya ke `service_role`/`postgres`.
Kerjakan berkelompok (mis. semua `admin_*`, `scrub_*`, `fn_*`) — uji tiap
kelompok bahwa app tetap jalan (RPC klien dipanggil via `authenticated`).

**HATI-HATI:** jangan revoke fungsi yang **memang** dipanggil klien anon
(`get_online_users`, `avatar_for`, `avatars_for`, `check_email_exists`,
`profile_public`, `list_gifts`, dll.) — cek FEATURE_MAP/test dulu.

---

## 3. `function_search_path_mutable` (28) — sedang

Fungsi tanpa `search_path` tetap → rentan **search_path hijacking** (penyerang
bikin objek bernama sama di schema lain). Fix: tambahkan di definisi fungsi:
```sql
alter function public.<fn>(args) set search_path = public, pg_temp;
-- atau di CREATE: ... language plpgsql security definer set search_path = 'public';
```
Fungsi terdampak: `admin_test, call_history_insert, check_email_exists,
check_private_chat_update, coin_ledger_no_mutate, comment_like_count_sync,
comment_share_count_sync, enforce_age_min, enforce_storage_photo,
follow_count_sync, get_data_sizes, get_last_messages, get_message_counts,
get_table_sizes, handle_new_private_message, increment_unread,
notify_call_ringing, post_comment_count_sync, post_like_count_sync,
room_online_counts, set_participant_registered, set_room_presence_from_profile,
set_sender_name_from_profile, streak_bonus_amount, subscriber_count_sync,
trg_coin_ledger_balance, week_label, week_start_utc`.

> Prioritas: fungsi `SECURITY DEFINER` dulu (yang `trigger`/`definer`).

---

## 4. `auth_allow_anonymous_sign_ins` (54) — BY-DESIGN (rendah)

RLS policy yang berlaku untuk role anon. **Ini memang desain app** (ChatYuk
anon-first — user bisa chat tanpa daftar). Kebocoran dicegah **di dalam policy
sendiri** (per-baris: `id = auth.uid()` dsb.), bukan dengan melarang anon.
Tidak perlu diubah; pastikan tiap policy tetap scoped ke `auth.uid()`.

---

## 5. `rls_enabled_no_policy` (16) — INFO (rendah)

Tabel RLS aktif TANPA policy = **deny-all** (aman; hanya service_role yang
tembus). Umumnya tabel internal:
`admin_stats_cache, ai_browse_cache, ai_chat_state, ai_chat_summary,
ai_daily_story, ai_internal_config, ai_memory, ai_provider_config,
ai_reply_claims, ai_reply_log, chat_ai_pause, debug_notify_log,
fcm_token_cache, outbox, story_mutes, user_location_history`.

Tidak perlu tindakan **kecuali** salah satu harus dibaca klien → beri policy
eksplisit. (Sudah benar kalau memang internal-only.)

---

## 6. `extension_in_public` (3) — SENGAJA TIDAK DIUBAH

`pg_net`, `cube`, `earthdistance` terpasang di schema `public`.

**Keputusan: JANGAN dipindah** (risiko > manfaat):
- **`cube` + `earthdistance`** dipakai fitur **"Orang Sekitar"**
  (`nearby_users`, `update_my_location`) — bergantung pada **tipe & operator**
  (`<@>`, `ll_to_earth`). Pindah schema = drop+create ulang → risiko kolom
  bertipe `cube`/`earth` & operator resolusi pecah. Manfaat hanya hilangkan
  1 lint WARN.
- **`pg_net`** dipakai 8 fungsi (`net.http_post` — trigger notif, ai_reply,
  fanout). Qualified (`net.`), tapi tetap: project ini menaruh `pg_net` di
  public secara default; drop+create berisiko memutus notifikasi.
- Kalau SUATU SAAT ingin dipindah: harus `CREATE EXTENSION ... SCHEMA extensions`
  + reindex + uji menyeluruh fitur lokasi & notifikasi. **Bukan pekerjaan cepat.**
  Tidak ada eksploit konkret dari extension di schema public (hanya best-practice).

---

## 7. `auth_leaked_password_protection` (1) — sedang

HIBP (HaveIBeenPwned) untuk cek password bocor **nonaktif**. Aktifkan di
Dashboard → Auth → Passwords → **Leaked password protection**. Di API:
(setting `password_hibp_enabled = true`).

---

## Urutan kerja yang disarankan

1. ✅ **profiles_public** — DONE (`20260928110000`).
2. ✅ **86 fungsi `SECURITY DEFINER` internal/trigger/admin** — REVOKE EXECUTE
   dari PUBLIC/anon/authenticated (`20260928120000`); 88 → 32 temuan anon.
3. ✅ **`function_search_path_mutable`** — SET search_path (`20260928130000`);
   28 → 0.
4. ✅ **`auth_leaked_password_protection`** — HIBP diaktifkan; 1 → 0.
5. ✅ **`authenticated_*` internal/legacy** — REVOKE 38 fungsi
   (`20260928140000`); 221 → 183. Sisa 183 = fungsi klien (harus `authenticated`).
6. **`extension_in_public`** — ⛔ SENGAJA DIBIARKAN (lihat §6; risiko fitur
   lokasi/notifikasi > manfaat).

> **Perhatian untuk ke depan:** `REVOKE EXECUTE ... FROM anon` SENDIRIAN tidak
> cukup — Postgres memberi EXECUTE ke `PUBLIC` secara default, dan anon
> mewarisinya. Selalu `REVOKE ... FROM PUBLIC, anon, authenticated` (lihat
> `20260928120000`). Pola ini terverifikasi: `has_function_privilege('anon',...)`
> baru `false` setelah revoke dari PUBLIC.

## Guardrail
- Setiap `REVOKE`/policy perlu penanda `-- SAFE:` (dicek `check_migrations.sh`).
- Setiap perubahan migrasi → catat di `docs/MIGRATION_LOG.md`.
- Uji: app tetap bisa chat/online/profil (RPC klien via `authenticated`).
- **JANGAN** revoke `EXECUTE` fungsi publik yang benar-benar dipanggil klien.
