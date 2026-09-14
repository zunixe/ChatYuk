# MIGRATION_LOG — catatan perubahan versi & penerapan

Setiap migrasi yang di-apply atau di-rename WAJIB dicatat di sini supaya AI/dev
berikutnya tahu. Format: tanggal | versi | aksi | catatan.

## 2026-09-14 — Lapis 6: perbaikan 8 timestamp duplikat

**Masalah:** `supabase_migrations.schema_migrations.version` adalah PRIMARY KEY,
tapi ada 8 pasang file migrasi dengan prefix timestamp SAMA → file kedua tidak
dijamin ter-apply (bergantung urutan filesystem). Ini bikin drift lokal↔remote.

**Aksi:** file KEDUA tiap pasangan di-rename ke `versi+1 detik`, di-apply ulang
(semua idempotent: `create or replace` / `... if (not) exists`), lalu versi baru
dicatat di `schema_migrations`. Verifikasi dampak: tidak ada (idempotent).

| Versi lama (file ke-2) | Versi baru | Status |
|---|---|---|
| 20260911140000_drop_dummy_ai_overload.sql | 20260911140001 | applied + recorded |
| 20260911150000_ai_chat_state_consent.sql | 20260911150001 | applied + recorded |
| 20260912000000_call_push_guard.sql | 20260912000050 | applied + recorded |
| 20260912010000_chat_update_trigger_admin_bypass.sql | 20260912010001 | applied + recorded |
| 20260912090000_dummy_ai_model_param.sql | 20260912090001 | applied + recorded |
| 20260913180000_dummy_wake.sql | 20260913180001 | applied + recorded |
| 20260913190000_dummy_photos_toggle.sql | 20260913190001 | applied + recorded |
| 20260914060000_presence_idle_tick.sql | 20260914060001 | applied + recorded |

## 2026-09-14 — Lapis 3: harness test SQL

| Versi | Aksi | Catatan |
|---|---|---|
| 20260914100000_sql_test_harness.sql | applied + recorded | schema `supabase_tests` + `check()`/`report()`/`mk_dummy()` |

Cara jalankan test: `scripts/run_sql_tests.sh` (via Management API, transaksional).

## Cara mencatat migrasi baru (WAJIB)

Setelah apply via Management API (`APPLIED_VIA_API.md`):

```bash
TOK=$(cat /tmp/sbtoken); REF=fohcucyyejdryryoxitm
curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  --data '{"query":"insert into supabase_migrations.schema_migrations (version) values ('\''<VERSI>'\'') on conflict do nothing;"}'
```

Lalu tambahkan baris ke tabel di atas.

## 2026-09-14 — INSIDEN: guard mendeteksi regresi live (ai_always_online)

**Kejadian:** saat menerapkan Lapis 6 (apply ulang file migrasi yang di-rename),
`20260913180001_dummy_wake.sql` ter-apply — fungsi `ai_presence_tick` versi itu
**tidak punya blok `if ai_always_online`**, sehingga cabang Admin Chatyuk 24/7
hilang di DB live (persis pola regresi lama). Restore-nya ada di
`20260914020000_admin_chatyuk_always_online_restore.sql` yang tidak ikut ter-apply
(urutan).

**Deteksi:** `scripts/run_sql_tests.sh` (test `presence_test.sql`) GAGAL dengan
"definisi memuat cabang ai_always_online" + "always_online → online". Guard
bekerja seperti desain.

**Perbaikan:** apply ulang `20260914020000` → `ai_always_online` kembali (pos=389).
Semua 35 assert hijau kembali.

**Pelajaran (WAJIB):** setelah apply ulang file lama, **re-apply migrasi
"restore/patch" yang lebih baru** untuk fungsi yang sama, ATAU gunakan
`create or replace` dari snapshot terbaru sebagai sumber. Inilah alasan
frozen-functions guard + snapshot ada.
