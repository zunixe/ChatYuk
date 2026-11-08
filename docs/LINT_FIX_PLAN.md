# Rencana Perbaikan Supabase Advisors (Lint Schema)

> Sumber: audit Advisors di replica 43 (2026-11-07). Schema replica = mirror
> 100% hosted → warning di production identik. Semua perbaikan di bawah adalah
> MIGRASI PRODUCTION — ikuti checklist AGENTS.md (timestamp unik, penanda
> `-- SAFE:`, snapshot fungsi frozen, smoke_anon_register, pgTAP).
>
> Catatan replikasi: **DDL tidak ikut logical replication** — migrasi di hosted
> TIDAK otomatis sampai ke replica. Setelah migrasi prod, replica harus
> di-apply manual atau re-restore, dan `schema-check.sh` akan menandai drift.

## Skala realita dulu

DB production-scale saat ini kecil (tabel terbesar 7MB, total ~46MB). Semua
temuan di bawah = **asuransi murah untuk pertumbuhan 100x**, bukan kebakaran
yang harus dipadamkan hari ini. Urutan prioritas = dampak per baris data ÷
risiko perubahan.

## P1 — Initplan policy — ✅ SELESAI (2026-11-07, production + replica)

Policy UPDATE yang memanggil `auth.uid()` langsung dievaluasi **per baris**
(initplan per-row) — di tabel panas (messages, private_messages, calls,
profiles) ini yang paling terasa saat tabel besar.

| Tabel | Policy |
|---|---|
| calls | calls_update |
| private_chats | private_chats_update |
| messages | messages_update_own, messages_update_view_once |
| private_messages | private_messages_update, private_messages_update_view_once |
| profile_privacy_exclusions | profile_privacy_exclusions_own |
| profiles | profiles_update_own |
| room_reads | room_reads_own |
| starred_messages | starred_messages_owner |
| user_devices | user_devices_own |

Fix mekanis (aman, tanpa perubahan semantik):

```sql
-- SAFE: perf initplan auth.uid() → (select auth.uid()), semantik tak berubah.
-- Fitur terdampak: chat, call, profil, device (lihat docs/FEATURE_MAP.md).
ALTER POLICY private_messages_update ON public.private_messages
  TO authenticated
  USING (sender_id = (select auth.uid()));
```

SELESAI: 6 fungsi project di-pin `search_path = ''` (170000/173000 untuk
policy, 180000 untuk fungsi) — terapplied ke production hosted dan replica 43.
Sisa temuan = fungsi bawaan extension — accepted.

## P2 — search_path fix — ✅ SELESAI (2026-11-07, production + replica)

Dari 59 temuan, ~49 adalah fungsi bawaan extension (`cube_*`, `earth_*`,
`pg_stat_statements*` — biarkan, bawaan contrib). Yang perlu di-fix fungsi
project:

`_email_is_admin`, `calls_client_guard`, `check_user_total_coins`,
`clamp_last_seen`, `is_room_media_type`, `outbox_mark_local`,
`streak_bonus_amount`, + sisanya dari daftar lint (filter non-extension).

```sql
-- menyentuh: <nama_fn>   (WAJIB bila fungsi ada di scripts/frozen_functions.txt)
ALTER FUNCTION public.clamp_last_seen() SET search_path = '';
```

Aturan AGENTS.md: cek `scripts/frozen_functions.txt` dulu. **Hasil cek
2026-11-07: tidak ada satu pun dari fungsi-fungsi di atas yang frozen** —
jadi bisa langsung `ALTER FUNCTION ... SET search_path = ''` tanpa protokol
frozen. Tetap jalankan `scripts/check_migrations.sh --all` setelahnya.

## P3 — Index FK — ✅ SELESAI (2026-11-07, production + replica)

Semua tabel masih kecil, tapi FK tanpa index di tabel yang **terus bertambah**
akan jadi full-scan saat join/cascade delete. Prioritaskan yang di tabel
pertumbuhan pesan/komentar/ledger:

- `post_comments.author_id`, `post_comments.parent_id`
- `chat_poll_votes.user_id`, `room_poll_votes.user_id`
- `bonus_claims.user_id`, `contact_messages.user_id`
- `random_match_queue.matched_with`, `random_match_queue.matched_call_id`
- `topup_orders.package_id`, `withdrawal_requests.reviewed_by`,
  `kyc_requests.reviewed_by`, `room_join_requests.user_id`

```sql
-- SAFE: index FK post_comments(author_id) — join profil di feed komentar.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_comments_author
  ON public.post_comments (author_id);
```

SELESAI: 25 FK (audit akurat, bukan 85) di-index CONCURRENTLY di production
dan replica; sisa FK tanpa index = 0. Versi tercatat 20261107183000.

## P4 — Hapus index nganggur (pilih yang terbesar saja)

80 index nganggur, totalnya kecil (terbesar 360KB). Jangan hapus semua —
index yang baru dibuat/dipakai musiman bisa false-positive. Kandidat aman:
yang `idx_scan = 0` SEKALIGUS ukurannya > 100KB dan bukan unique. Verifikasi
dulu di production (statistik replica ≠ production traffic):

```sql
-- SAFE: index tak pernah dipakai (idx_scan=0), ukuran X, bukan unique.
DROP INDEX CONCURRENTLY IF EXISTS public.<nama_index>;
```

## Tidak perlu tindakan (accepted)

- **26 tabel RLS-on tanpa policy** — tabel internal (outbox, ai_internal_config,
  email_*, fraud_holds, ai_reply_*, dll) diakses via SECURITY DEFINER/service
  role. Memang tidak boleh punya policy client.
- **Fungsi extension (cube/earth/pg_stat_statements)** — bawaan contrib,
  warning bawaan, hosted juga menampilkannya.

## Urutan eksekusi yang disarankan

1. P1 (11 policy) — satu migrasi, dampak terbesar, risiko nol.
2. P2 (search_path) — satu migrasi, cek frozen list dulu.
3. P3 (index FK) — per index `CONCURRENTLY`, mulai dari post_comments.
4. P4 (drop index) — paling akhir, setelah statistik production cukup tua.

Setiap langkah: `bash scripts/check_migrations.sh --all` → hijau, catat di
`docs/MIGRATION_LOG.md`, update `docs/FEATURE_MAP.md` bila tabel lintas-fitur
tersentuh.
