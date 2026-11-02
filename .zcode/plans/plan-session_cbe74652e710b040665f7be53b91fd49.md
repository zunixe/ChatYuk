# Rencana: Perbaikan sisa celah audit ekonomi koin (temuan review 2026-11-02)

## Konteks
Migrasi `20261101190000_paid_only_economy.sql` (sudah applied) menutup L1/L2/L3 di SERVER. Review ulang menemukan 4 ketidaksesuaian CLIENT (satu di antaranya bug nyata dari migrasi itu), 2 titik SQL laten, dan docs basi. Semua perbaikan kecil dan terarah.

## Fase 1 — Dart: samakan precheck client dengan aturan server (5 file)

1. `lib/providers/riverpod/points_provider.dart:292` — `if (_points >= need)` → `if (_topupBalance + _earnedBalance >= need)` (atau `state.paidBalance`). Fix bug call: male bonus-only akan dapat dialog top-up yang benar, bukan call diputus di tengah. Kena 3 pemanggil: `private_chat_chat2.dart:403`, `user_info_actions.dart:25`, `call_history_screen.dart:167`.
2. `lib/screens/group_screen.dart:89-90` + `lib/screens/group/group_widgets.dart:221-222` — precheck room create/extend: `points.paidBalance >= paid || points.bonusBalance >= paid * points.bonusMultiplier` (mengikuti `ledger_spend_dual`: tier paid dulu, fallback bonus × multiplier).
3. `lib/screens/saldo_screen.dart:169` — headline `_BalanceCard` pakai `withdrawable` (sudu di-fetch dari server, `earnings_provider.dart:85`) bukan `balance` total; perbaiki komentar basi baris 166-168.
4. `lib/screens/user_info/user_info_init.dart` (sebelum dialog konfirmasi ~baris 366) — tambah precheck `points.paidBalance >= price`; kalau kurang, dialog top-up (pola sama seperti gift).
5. Komentar basi: `missions_provider.dart:218` dan `missions_screen.dart:93` — perbaiki agar mencerminkan aturan bucket by-gender (female→earned, male→bonus). Snackbar klaim misi: pertimbangkan label bucket agar male tidak salah kira saldo bisa dipakai.

Verifikasi: `flutter analyze` (0 error baru; 2 error pre-existing di `points_service_io_test.dart`/`points_provider_test.dart` tetap dilaporkan apa adanya) + `flutter test -j 2` (baseline: 2582 lolos, 1 gagal pre-existing compile). Tambah 1 test Dart: `ensureEnoughForCall` dengan saldo bonus-only → false (dialog muncul), saldo paid cukup → true.

## Fase 2 — SQL: tutup 2 titik laten (1 migrasi baru)

File: `supabase/migrations/20261101200000_...` — cek dulu timestamp bentrok (`ls` terakhir: 20261101200000_disable_photo_unlock.sql sudah ada → naikkan, mis. 20261101210000).

1. `spend_yukcoin` — REVOKE EXECUTE dari `authenticated` (client tidak pernah memanggilnya; pemanggil sah hanya `random_match_join` via `_spend_yukcoin_core` sebagai definer). Allowlist `'gift'` di core dibiarkan (dead path, tanpa penerima — bukan bocor uang) ATAU dirapikan sekalian + sesuaikan `economy_money_test` §11 kalau memakai feature `'gift'` (cek saat implementasi; test berjalan sebagai superuser jadi REVOKE tidak memblokirnya).
2. `get_earnings_summary` — `v_withdrawable` dari SUM semua bucket → SUM bucket `earned` saja. Ambil versi TERBARU dari `20261101180000_economy_consistency_fixes.sql` (sesi paralel baru merombak) — jangan dari migrasi lama. Kalau sesi paralel masih aktif di file ini, koordinasi dulu (catat di MIGRATION_LOG).
3. Test: tambah asersi di `economy_paid_only_test.sql` — (a) `spend_yukcoin` dengan feature `'gift'` dari client `authenticated` → ditolak grant; (b) `get_earnings_summary` withdrawable tidak menghitung bonus.
4. Verifikasi wajib: `bash scripts/check_migrations.sh --all` → apply via Management API → `bash scripts/run_sql_tests.sh` (semua hijau) → `scripts/snapshot_functions.sh` + review diff → catat di `docs/MIGRATION_LOG.md`.

## Fase 3 — Docs

1. `docs/FEATURE_MAP.md` — tambah aturan: klaim misi female→`earned` / male→`bonus`; ringkasan "semua jalur income wajib koin beli" (call, gift, foto*, subscribe, kirim koin) + withdraw earned-only. *unlock foto sudah dimatikan total (migrasi 20261101200000) — baris model "unlock foto" di laporan kemarin jadi moot.
2. `docs/ECONOMY_TEST_MATRIX.md` A17 — tambah kolom bucket untuk klaim misi.
3. `docs/MIGRATION_LOG.md` — entri migrasi baru + koreksi entri 190000 (sebut konsekuensi client: saldo total vs paid).

## Risiko / catatan
- Perubahan Dart menyentuh 5 file UI/provider — semua kecil (ganti ekspresi saldo + 1 dialog precheck). Tidak ada perubahan skema/UI besar.
- `get_earnings_summary` adalah fungsi yang baru dirombak sesi paralel; kalau bentrok, tunda Fase 2 item 2 dan laporkan.
- Tidak ada build APK dalam scope ini (perubahan Dart/UI — build menyusul kalau diminta).