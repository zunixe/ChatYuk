# DATABASE — entitas, migrasi & kontrak ChatYuk

> Kerangka awal (2026-10-10, dari audit read-only). Kronologi apply di
> `MIGRATION_LOG.md`; disiplin di `supabase/MIGRATION_DISCIPLINE.md`; kebenaran
> fungsi di `supabase/snapshots/functions.sql`. Jangan duplikasi ketiganya.

## Skala (terverifikasi)

- 454 file `supabase/migrations/*.sql` (`20260812*` → `20261009*`) + 1 legacy
  `points_v1.sql`.
- 30 fungsi FROZEN (`scripts/frozen_functions.txt`), snapshot 1742 baris
  (`supabase/snapshots/functions.sql`).
- 24 Edge Functions (`supabase/functions/*/index.ts`), 29 test pgTAP
  (`supabase/tests/*.sql`).
- Semua RPC client lewat `measuredRpc` (`lib/core/perf/rpc_probe.dart`, 79 titik).

## Disiplin migrasi (ringkas — detail di MIGRATION_DISCIPLINE)

1. Timestamp UNIK `YYYYMMDDHHMMSS_nama.sql` (0 duplikat; guard `[1]`).
2. Sentuh fungsi FROZEN → header `-- menyentuh: <fn>` (44 file; guard `[3]`) +
   regenerate snapshot + review diff cabang.
3. `DROP TABLE/COLUMN`, `ALTER COLUMN TYPE` → `-- SAFE:` sebaris (guard `[2]`).
4. `GRANT/REVOKE`/policy RLS tabel bersama
   (`profiles`, `user_photos`, `private_chats`, `private_messages`, `messages`)
   → `-- SAFE:` + daftar fitur terdampak (guard `[6]`; insiden anon 2026-09-22) +
   `scripts/smoke_anon_register.sh` + pgTAP terkait + update `FEATURE_MAP.md`.
5. Apply di Mac HANYA via Management API (`APPLIED_VIA_API.md`); `db push` HANG.
6. Catat di `MIGRATION_LOG.md`; tambah/aktifkan test pgTAP bila ubah perilaku.

## Tabel & kolom kritis lintas-fitur (TODO lengkapi)

| Tabel/kolom | Dipakai oleh | Catatan |
|---|---|---|
| `dummy_accounts.ai_always_online`, `ai_no_sleep`, `ai_wake_until`, `ai_offline_until` | presence, notif, chat, admin, poin | Pernah hilang 2x saat replace (`ai_presence_tick`); guard cabang kritis `[5]` |
| `profiles.status`, `avatar`, `last_seen` | registrasi, presence, profil | SELECT di-revoke 2026-09-22 → baca via RPC `presence_for`/`avatar_for`/`get_online_users`; tulis split INSERT+PATCH |
| `app_settings.ai_global_enabled`, `latest_version`, `min_version` | presence, update-check | `latest_version` hanya sinkron SETELAH rilis Play live |
| `ai_internal_config.callback_secret` | AI, admin | — |
| `private_chats.unread_counts`, `last_read_at` | chat, badge | Read-receipt monoton maju (client `read_receipt.dart`) |
| `room_reads`, `outbox`, `coin_ledger`, `bonus_claims` | room, notif, poin | TODO: petakan kontrak per RPC |

## RPC utama per domain (pointer — detail di FEATURE_MAP)

- Presence: `ai_presence_tick`, `get_online_users`, `presence_stale_offline`,
  `housekeeping_tick`, `presence_for`.
- Chat/room: `create/join/extend_private_room`, `handle_new_private_message`,
  `mark_chat_read`, `mark_room_read`, `room_voice_*`.
- Notif: `notify_private_message`, `notify_call_ended`, `call_push` → outbox →
  cron `chatyuk-outbox-worker */1m` → `send-push` → FCM.
- Poin: `send_coins/gift`, `one_time_bonus`, `daily_login_bonus`,
  `room_read_bonus`, `new_chat_bonus`, `claim_weekly_quest`, `points_leaderboard`,
  `credit_welcome_bonus/play_topup` (idempoten via `bonus_claims`/`purchase_token`).
- Admin: `admin_list_dummies`, `admin_stats_detail`, `admin_set_dummy_ai`, ...
  (guard email `zunixe@gmail.com`).
- Feed/sosial: `list_posts`, `create_story`, `story_slides/tray/viewers`,
  `follow_count_sync`, `nearby_users`, `profile_public`, `activity_leaderboard`.

## Gap: idempotency message creation → lihat ADR-0001.
