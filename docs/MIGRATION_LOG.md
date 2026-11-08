## 2026-11-11 — Room v2: sesi terjadwal + host (APPLIED 2026-11-11 via API)

### `20261111120000_room_sessions_v2.sql` (APPLIED 2026-11-11)
- **Tabel baru** `room_sessions` (jadwal sesi per room global + KPI
  `peak_viewers`/`gifts_total`) dan `room_session_reminders` (opt-in
  "Ingatkan"), plus `profiles.is_host` (admin-set, bukan role baru).
  RLS: SELECT publik untuk `room_sessions`, own-rows untuk reminders;
  semua write lewat RPC `security definer`. Grant hanya SELECT.
- **RPC baru**: `schedule_room_session` (admin; validasi host `is_host`,
  format, jam, overlap 1 sesi scheduled/live per room), `start_room_session`
  (host/admin; guard sesi live ganda; notif `social_push` ke reminders),
  `end_room_session` (live→ended, scheduled→cancelled),
  `next_room_sessions` (live/terdekat per room + host + reminded),
  `toggle_session_reminder`, `session_host_mute` (izin diperluas ke host
  sesi live), `room_session_tick` (peak dari `room_presence` TANPA
  `dummy_accounts`), `room_session_sweep` (auto-end > ends_at+2j, service
  role), `admin_set_host`, `admin_room_session_stats`.
- **`send_room_gift` diaktifkan lagi** (dimatikan 20261101100200) dengan
  ekonomi PAID-ONLY terkini (pola `send_gift`): advisory lock, kill-switch
  `points_enabled`, wajib `is_registered`, female diblok, rate limit
  `coin_tx_max_per_hour`, `yukcoin_spendable` + `ledger_spend_promo`
  (bonus hanya lewat promo plafon), penerima SELALU bucket `earned`.
  Cabang baru: room global + sesi live → penerima host sesi +
  `room_sessions.gifts_total += koin kotor`; tanpa sesi live → ditolak
  pesan friendly. Grant execute dikembalikan ke `authenticated`.
- pgTAP `supabase/tests/room_sessions_test.sql` 23/23 hijau (dummy-only,
  transaksional). `check_migrations.sh --all` bersih.
## 2026-11-10 (b) — Koin bonus untuk fee match (APPLIED 2026-11-04 via API)

### `20261110060000_admin_promo_budget.sql` (APPLIED 2026-11-05)
- `admin_update_point_settings` menerima `promo_budget_idr_monthly` (min 0);
  `admin_get_point_settings` + `promo_budget_left_idr`. Panel admin tab Poin:
  isian plafon + sisa bulan ini. Isi fungsi dari snapshot live (+1 baris).

### `20261110050000_promo_bonus_spend.sql` (APPLIED 2026-11-04)
Keputusan user: bonus male bisa untuk call/gift/kirim koin/langganan;
penghasilan female dari situ bisa ditarik (biaya promosi), plafon Rp300rb/bln.
- `ledger_spend_promo`: koin beli/earned dulu; sisa ditambal bonus ×
  `bonus_price_multiplier` (3). Biaya Rupiah dicatat `metadata.promo_idr`.
- `_promo_payer_ok`: male terdaftar, device bukan 'unknown', install_id tidak
  dipakai akun lain, plafon tersisa > 0.
- Plafon `app_settings.promo_budget_idr_monthly` (default 300000, bulan WIB) —
  dipakai bersama hadiah misi female earned (`_mission_payout_eligible` →
  `promo_budget` bila habis). Belum ada UI admin.
- Menyentuh: `send_gift`, `send_coins` (FROZEN), `subscribe_creator`,
  `_charge_metered_core`, `_call_bill_as`, `get_wallet` (+`promo_ok`,
  `bonus_multiplier`). Diff snapshot: hanya blok debit yang berubah.
- Test: `promo_bonus_spend_test.sql` 12/12 + 8 suite ekonomi hijau di live.

### `20261110040000_female_mission_withdrawable.sql` (APPLIED 2026-11-04)
- `claim_mission_reward`: hadiah misi FEMALE → `earned` (bisa ditarik, ikut
  masa tahan) bila `_mission_payout_eligible` lolos; selain itu tetap `bonus`
  + `reason` (`no_device`/`shared_device`/`shared_ip`). Male tetap bonus.
- Device: tabel baru `mission_payout_devices` — install_id dimiliki akun
  pertama yang menerima hadiah earned; akun lain di device itu → bonus.
- IP: `_request_ip()` membaca header request (cf-connecting-ip /
  x-forwarded-for) — IP dari HP (`user_devices.ip_address`) tidak valid
  (152 device, 1 IP). IP sama < 24 jam dgn akun lain → bonus.
- Ledger `metadata` mencatat `ip` & `reason`. Klien: snackbar sesuai bucket.
- Test: `female_mission_payout_test.sql` 9/9; ekonomi lain tetap hijau.
  Verifikasi REST: `_request_ip()` = IP publik pemanggil.

### `20261110030000_match_bonus_fee.sql`
Keputusan user: koin BONUS boleh membayar fee match; call gratis 30 detik;
lewat itu konek + menit wajib koin isi ulang (billing menjeda + top-up).
- `random_match_join`: precheck diri & kandidat = `yukcoin_total >= fee`
  (dulu `yukcoin_paid_total >= fee + konek` → akun bonus-only tak bisa match).
- Klien: kartu YukCoin profil & header menampilkan rincian Bonus / Isi ulang /
  Penghasilan + penjelasan (dulu hanya total → user mengira bonus bisa semua).
Test: `random_match_test` 0c disesuaikan (bonus-only boleh antre).

## 2026-11-10 — Review ulang ekonomi + level (APPLIED 2026-11-04 via API)

### `20261110000000_econ_lockdown_phase1.sql`
- `withdraw_accounts` & `subscriptions`: klien SELECT-only (revoke tulis +
  drop policy tulis). Dulu PATCH langsung melewati cooldown nomor DANA dan
  membuat langganan gratis.
- `guard_economy_columns` (+INSERT): `subscription_price` hanya via
  `set_subscription_price` (kini set `chatyuk.economy_ok`); `is_registered`
  hanya naik bila auth user terverifikasi (`profile_is_verified`); insert profil
  klien → saldo 0, `created_at` now, gender terkunci. Deteksi klien memakai GUC
  `role` (fungsi definer → `current_user` selalu owner).
- Nomor DANA unik antar akun (`DANA_IN_USE`); `request_withdraw` menahan
  (`shared_device` → UNDER_REVIEW) penghasilan dari akun yang berbagi device.
- `admin_withdraw_process`: approve ditolak bila ada `fraud_holds` terbuka;
  `reviewed_by = auth.uid()`.
- `subscribe_creator(…, p_expected_price)` → `PRICE_CHANGED`.
- `send_gift` (FROZEN): wallet lock. `user_fcm_tokens`: internal saja.

### `20261110010000_server_call_billing.sql`
- Isi `call_billing_tick` → `_call_bill_as(call, payer)`; tick = wrapper.
- `settle_call` menagih atas nama payer: trigger saat `ended_at` terisi +
  cron `call-billing-settle` tiap menit (call aktif). Saldo kurang > 4 menit →
  server mengakhiri call (`calls.billing_short_since`).

### `20261110020000_refund_chain_level_missions.sql`
- `reverse_play_topup`: tahan penerima berantai (kedalaman 3) + cabut level &
  hadiah level (`level_recompute_after_refund`).
- Level = koin `topup_orders` status paid (`level_paid_coins`) — tutup panen
  level via `refund_chat_point`.
- `refund_chat_point` maks 10/jam; `update_mission_progress` dari klien
  dibatasi waktu nyata (`user_missions.last_increment_at`).

Test: `econ_review_1110_test.sql` 14/14; `my_level_test` & `call_billing_toggle_test`
disesuaikan; smoke_anon_register OK; seluruh suite SQL lolos.
Edge function `play-topup-verify` v8 (tolak purchaseType test/promo kecuali secret `PLAY_ALLOW_TEST_PURCHASES=1`).

## 2026-11-09 (b) — Withdraw: masa tahan, refund Play, billing call

### `20261109020000_withdraw_hold_play_refund.sql` (APPLIED 2026-11-04 via API)
Keputusan user: reward misi → bonus; `send_coins` tetap earned + masa tahan;
masa tahan 7 hari.
- `app_settings.withdraw_hold_days` (7) & `withdraw_max_coins_per_day` (50.000).
- `earned_held(uid, days)`: kredit `earned` (kecuali `withdraw_refund`)
  dalam masa tahan → belum bisa ditarik.
- `request_withdraw` v3: `HELD_BALANCE` {available, held}, `DAILY_AMOUNT_LIMIT`
  {remaining}, `UNDER_REVIEW` (fraud_holds terbuka), KYC dicek SEBELUM nomor
  DANA disimpan (N8).
- `get_earnings_summary`: `withdrawable` setelah masa tahan + `held`,
  `hold_days`. `get_withdraw_config`: + `hold_days`, `max_coins_per_day`.
- `claim_mission_reward`: reward selalu `bonus`.
- Refund Play: `topup_orders.status` + 'refunded' (+`refunded_at`,
  `refund_shortfall`), tabel `fraud_holds`, `reverse_play_topup(token)`
  (tarik topup → earned sebatas saldo; tahan pembeli + semua `to_user`
  di platform_revenue sejak pembelian; idempoten), `admin_fraud_holds`,
  `admin_resolve_fraud_hold`. Cron `play-voided-sync` 02:40 → edge function.

### `20261109030000_billing_private_media_pricing.sql` (APPLIED 2026-11-04 via API)
- `call_billing_tick`: `FEATURE_DISABLED` hanya untuk call random (private
  call tak lagi gratis saat flag random_call mati); random ditagih hanya
  setelah `media_connected_at` (tanpa fallback `answered_at`).
- `metered_pricing_public` + `match_search_cost`, `match_connect_cost`,
  `match_free_seconds` (UI tak lagi hardcode).

Edge function (deploy `--use-api`): `play-topup-verify` v7 (tolak token
yang `obfuscatedExternalAccountId` ≠ sha256(uid)), `play-voided-sync` v1
(verify_jwt=false, x-app-secret). Klien mengirim `applicationUserName`.
Test: `withdraw_hold_refund_test.sql` 16/16; suite lama disesuaikan
(hold 0 di test non-hold, misi → bonus, random call distempel media);
seluruh suite SQL lolos.

## 2026-11-09 — Review ulang ekonomi + KYC profesional

### `20261109000000_econ_calls_guard_v2.sql` (APPLIED 2026-11-04 via API)
Menutup celah yang muncul dari Fase A (`20261106000000`):
1. **N1** `call_billing_tick`: `v_end := least(coalesce(ended_at, now()), now())`
   — dulu `ended_at` masa depan (bisa ditulis peserta) menagih semua menit
   sampai saldo payer habis.
2. **N2/N3** `calls_client_guard`: `created_at`, `caller_id`, `callee_id`,
   `call_type` dibekukan untuk klien; `answered_at`/`ended_at` hanya sekali &
   diisi jam SERVER (nilai jam HP diabaikan → tak lagi ditolak saat jam HP
   telat). Perubahan ilegal DINORMALKAN (bukan error) supaya retry
   `updateStatus` klien tetap aman.
3. **N4** revoke `economy_invariant_cron()` dari public/anon/authenticated.
4. **S4** `_spend_yukcoin_core`: `pg_advisory_xact_lock('wallet:'||uid)`
   (komentar Fase A bilang sudah, ternyata belum).
Test: `econ_lockdown_test.sql` 34/34 (A3b disesuaikan: backdate diabaikan;
+N1/N2/N4).

### `20261109010000_kyc_validation.sql` (APPLIED 2026-11-04 via API)
KYC divalidasi ulang di server (klien bisa dimodifikasi):
- hanya KTP; `kyc_nik_info(nik)` = struktur NIK (provinsi, kab/kec ≠ 00,
  tgl lahir +40 perempuan, urut ≠ 0000);
- `submit_kyc` v2 (+`p_checks jsonb`, signature lama DI-DROP): tgl lahir ==
  NIK, usia ≥ 17, maks 3/24 jam, **1 NIK = 1 akun** (unique index
  pending/approved), error berupa kode `KYC_*` (klien → string bilingual);
- kolom `checks` (OCR/liveness/kualitas dari klien) & `server_checks`;
- `admin_kyc_list` tanpa foto (+checks), foto via `admin_kyc_photos(id)`;
- `admin_kyc_review`: `FOR UPDATE` + wajib `pending` + alasan tolak wajib.
Test: `kyc_validation_test.sql` 21/21.

Catatan: `economy_bonus_saldo_test.sql` gagal 2 cek "kuota gratis female"
bila dijalankan 00:00–00:40 WIB (fixture `answered_at = now()-40m` jatuh ke
hari sebelumnya) — rapuh waktu, bukan regresi.

## 2026-11-02 — Audit lanjutan: pulihkan regresi + zona waktu (Fase 23)

**Temuan utama:** migrasi `20261101190000_paid_only_economy.sql` (yang
menutup jalur koin gratis → uang) menyalin `request_withdraw` dari salinan
LAMA sehingga diam-diam membuang dua perbaikan dari `20261101180000`.
Juga ditemukan bug zona waktu yang belum tertangani di tiga fungsi.

### `20261102220000_withdraw_quota_fee_timezone_restore.sql` (APPLIED)
1. **Kuota withdraw dipulihkan:** `AND status <> 'rejected'` dikembalikan
   pada query kuota harian DAN cooldown. Tanpa itu, pengajuan yang ditolak
   admin tetap memakan kuota 3/hari dan cooldown 1 jam.
2. **Fee rounding dipulihkan:** `round((v_gross * v_fee_pct) / 100.0)`
   (sebelumnya `greatest(... / 100, ...)` yang memotong) agar sama dengan
   preview client — dialog konfirmasi tidak lagi selisih 1 Rp.
3. **Zona waktu:** batas "hari" memakai awal hari Asia/Jakarta sebagai
   `timestamptz`.

### `20261102230000_economy_consistency_round2.sql` (APPLIED)
1. `get_earnings_summary.withdrawable` kini **hanya bucket `earned`** (sama
   dengan validasi `request_withdraw`); field baru `total_balance` untuk
   informasi. Sebelumnya menjumlah semua bucket → layar Saldo bisa
   melebihkan angka yang benar-benar bisa ditarik.
2. `get_user_missions` ditambah `SET search_path TO 'public'`.
3. `claim_mission_reward` menegakkan `missions.gender` di server (misi
   female-only sebelumnya bisa diklaim male lewat RPC langsung).
4. `streak_bonus_amount` dicabut dari `public, anon`.
5. `spend_yukcoin` dicabut dari `authenticated` (permukaan mati dengan
   semantik gift lama yang masih menerima bucket bonus).

### `20261102240000_call_free_limit_timezone.sql` (APPLIED)
1. **Bug zona waktu batas gratis female:** `answered_at >= current_date`
   memakai UTC. Server Supabase ber-zona UTC sementara user WIB → panggilan
   yang dijawab setelah tengah malam WIB tidak terhitung ke kuota hari itu.
2. **Bug perbandingan tipe:** membandingkan kolom `timestamptz` dengan
   `date` SALAH tafsir (date dibaca UTC midnight). Terbukti di test:
   panggilan 23:29 UTC (06:29 WIB hari berikutnya) terbaca 0 menit.
   Solusi: `(((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
   AT TIME ZONE 'Asia/Jakarta')`.
3. **Afford-check call memakai saldo PAID:** `yukcoin_total` →
   `yukcoin_paid_total`. Sebelumnya caller bonus-only lolos cek lalu
   `charge_metered` melempar exception di tengah tick.
4. Nama variabel disamakan dengan pola yang diuji `call_billing_toggle_test`
   (`points_on`).

### Perbaikan client
- Minimum withdraw 2000 (bukan 1500) di string; angka kini dari server.
- `wdWithdrawableHint` tidak lagi menjanjikan "semua koin bisa ditarik".
- Layar Saldo menampilkan `withdrawable` (earned) sebagai headline dan
  `total_balance` terpisah bila berbeda.
- 7 string paywall foto (mati) dihapus; editor admin `photo_upload_reward`
  dan `photo_unlock_owner_pct` dihapus.
- Header migrasi `20261101190000` yang salah tulis (copy-paste) diperbaiki.

### Test
- `economy_bonus_saldo_test.sql` diperkuat: kuota withdraw diuji dengan
  **3 baris `rejected`** (sebelumnya 1 baris — kuota 3, jadi lolos dua-dua
  dan assertion lulus kosong). Assertion diubah jadi positif
  (`ok = true`), bukan sekadar "bukan DAILY_LIMIT".
- **Verifikasi uji-regresi secara sad:** filter `status <> 'rejected'`
  sengaja dihapus → test GAGAL; dipulihkan → test lulus. Ini membuktikan
  test benar-benar menangkap regresi, bukan lolos kosong.
- Coverage baru: batas gratis female 30 menit (jalur `free_limit`), batas
  tepat minimum withdraw (min-1 vs min), misi female-only untuk male,
  `withdrawable` vs `total_balance`.
- Test basi untuk `unlock_photo` (fitur sudah dinonaktifkan) dihapus dari
  `economy_money_test.sql` dan `economy_matrix_test.sql`.

### Verifikasi (2026-11-02)
- `check_migrations.sh` → **OK bersih**
- `run_sql_tests.sh` → **51 file hijau** (termasuk
  `economy_bonus_saldo_test.sql` 24/24, `economy_paid_only_test.sql` 27/27)
- Migrasi & test baru sudah `git add` (ter-track, tidak di-commit)

## 2026-11-02 — Sisa celah audit: precheck client + 2 titik SQL laten

### `20261101210000_client_paid_precheck_hardening.sql` (APPLIED via Management API)
Review ulang audit peredaran koin (2026-11-02) menemukan:
- **RUSAK (efek 190000):** `ensureEnoughForCall` (`points_provider.dart`)
  cek saldo TOTAL (`_points`) — server kini minta paid → male bonus-only
  lolos dialog lalu call diputus. Fix client: cek `_topupBalance +
  _earnedBalance`; room create/extend cek per-bucket
  (`paidBalance >= paid || bonusBalance >= paid×mult`); subscribe
  precheck `paidBalance >= price`; headline Saldo pakai `withdrawable`
  (earned) bukan total; snackbar klaim misi male berlabel "koin bonus
  (tidak bisa dicairkan)" + komentar by-gender.
- **SQL laten 1:** `spend_yukcoin` masih di-grant `authenticated`
  (client tak pernah memanggil; pemanggil sah `random_match_join` via
  `_spend_yukcoin_core` definer) → REVOKE dari `authenticated`.
- **SQL laten 2:** `get_earnings_summary.v_withdrawable` = SUM semua
  bucket → filter bucket `earned` (bonus menggelembungkan "bisa ditarik").
  Badan lain sama dengan 20261101180000.
- **Test:** `economy_paid_only_test.sql` 27/27 (+2: grant spend_yukcoin,
  withdrawable earned-only); Dart `test/points_call_precheck_test.dart`
  4/4 (baru) + regresi di `points_provider_extra_test.dart` (bonus-only →
  dialog MUNCUL); `missions_screen_test.dart` tanggal hardcode
  '2026-11-01' → `_todayWib()` dinamis (bukan regresi — test basi saat
  tanggal berganti). Semua suite SQL hijau; `check_migrations.sh --all`
  OK; snapshot refresh (30 fungsi, 0 hilang); `flutter analyze` 0 error/
  0 warning.
- **Docs:** FEATURE_MAP (ringkasan paid-only + bucket misi + precheck
  client), ECONOMY_TEST_MATRIX A17 (kolom bucket).

## 2026-11-01 — Audit menyeluruh bonus, saldo & YukCoin (Fase 22)

**Temuan:** 5 bug yang merugikan user, ~15 hal menyesatkan/tidak konsisten,
dan sejumlah fitur mati. Semua sudah diverifikasi langsung di kode.

### `20261101170000_claim_mission_coins_from_balance.sql` (APPLIED)
**Bug:** misi bertarget koin (`nyonya_1000`) mustahil diklaim.
`get_user_missions` (160000) menghitung `is_completed` dari saldo ledger
tanpa menulis ke `user_missions`, tetapi `claim_mission_reward`
mensyaratkan baris `user_missions` -> selalu `MISSION_NOT_STARTED`.
Female dengan >= 1000 koin earned melihat tombol "Klaim +100" tetapi tidak
mendapat apa pun (UI juga gagal senyap).
-> Untuk misi `target_unit='coins'`, kelulusan dihitung dari saldo bucket
`earned` (rumus sama dengan `get_user_missions`); baris `user_missions`
dibuat bila belum ada. Klaim tetap atomik (`WHERE claimed = false`).

### `20261101180000_economy_consistency_fixes.sql` (APPLIED)
1. `get_earnings_summary`: `breakdown.match_call` & `message` di-hardcode 0
   padahal `private_call` sudah memasukkan `match_call_income` -> income
   match muncul di baris "Panggilan Privasi" dan baris "Panggilan Match"
   SELALU 0. Sekarang dipisahkan.
2. Zona waktu: `current_date`/`date_trunc('week')` memakai zona sesi DB
   (UTC) -> "Hari Ini" reset 07:00 WIB. Dipindah ke Asia/Jakarta.
3. `SET search_path` ditambahkan (fungsi SECURITY DEFINER tanpa itu).
4. `request_withdraw`: kuota harian & cooldown menghitung SEMUA baris apa
   pun statusnya -> pengajuan yang DITOLAK tetap memakan kuota 3/hari dan
   cooldown 1 jam. Status `rejected` sekarang dikecualikan.
5. Fee dibulatkan ke atas agar sama dengan preview client (dulu server
   memotong -> selisih 1 Rp di dialog konfirmasi).

### `20261101190000_paid_only_economy.sql` (APPLIED)
Menutup tiga jalur koin gratis -> uang: `charge_metered` dan
`request_withdraw` tidak lagi memakai bucket `bonus`; reward misi tidak
lagi jatuh ke `earned` untuk gender yang tidak berhak.

### `20261101200000_disable_photo_unlock.sql` (APPLIED)
Fitur "buka foto pakai koin" DINONAKTIFKAN (keputusan produk): tidak ada
UI yang memanggilnya, dan `user_info` justru membuang foto terkunci ->
`photo_income` tidak pernah bisa terjadi. EXECUTE dicabut dari
`authenticated`; tipe kolom `photo_unlock_once/perm` dinormalkan ke `int`
(baseline membuatnya boolean -> replay bersih bisa gagal).

### Perbaikan client (tanpa migrasi)
- **Female caller tidak bisa menelepon:** `ensureEnoughForCall` memblokir
  siapa pun dengan saldo < tarif per menit, padahal server memberi female
  30 menit gratis/hari dan menagih 0. Sekarang female lolos.
- **Withdraw menampilkan kode mentah:** UI memetakan `INSUFFICIENT_EARNED`
  (mati) padahal server mengembalikan `INSUFFICIENT_BALANCE`;
  `POINTS_DISABLED` juga tidak dipetakan. Keduanya diperbaiki, dan batas
  (min/harian/interval/umur) kini memakai angka dari server.
- **Admin withdraw sukses palsu:** respons RPC dibuang ->
  `{ok:false, error:'ALREADY_PROCESSED'}` dilaporkan sebagai berhasil.
  Sekarang respons dibaca dan jumlah refund ditampilkan saat reject.
- **Janji "+100 daftar email"** salah untuk female -> label dibuat netral.
- **Harga phantom:** "Beli slot foto - 60" padahal server menagih 0;
  getter `costUndoMessage/costEditMessage/costExtraPhotoSlot/
  costGhostModeDaily` dihapus.
- **Minimum withdraw 1500 -> 2000** di string & default config; rate 7
  yang di-hardcode diganti `config.rate`.
- **Match:** ditambahkan catatan tarif per menit setelah menit gratis.
- **Kirim koin > 1000** kini divalidasi client (dulu error mentah server).
- **Label riwayat** untuk `post_boost`, `level_reward`,
  `female_bonus_reset`.
- **Harga room** ditampilkan sebelum konfirmasi (buat & perpanjang).
- **Konsistensi saldo:** angka "bisa ditarik" selaras dengan validasi
  server; saldo & ringkasan penghasilan di-refresh setelah withdraw;
  layar Withdraw punya state error (dulu saldo 0 disamarkan sebagai
  "belum ada apa-apa").
- **Menu Undo** tidak lagi digate paywall (undo gratis).
- **Fitur mati dibuang:** `unlock_photo` (+ string paywall foto),
  `chatChargeYukcoin`/`spendYukcoin`, `gateFeature`, `editMessage` v2,
  `buyGhostMode`/`isGhostMode`, `myExtraPhotoSlots`, `getYukcoin`,
  `yukcoinV2For`, `claimReferralReward`, `rewardPhotoSlot`,
  `roomReadBonus`, `oneTimeBonus`, `registerBonus`, `listGifts`,
  `RoomGiftPanel`, `syncFromProfile`/`_trackNyonya`, dan string mati.
- **Panel admin:** kolom `photo_unlock_once/perm` dihapus (fitur mati).

### Verifikasi (2026-11-01)
- `check_migrations.sh` -> **OK bersih**
- `run_sql_tests.sh` -> **51 file hijau** (termasuk
  `economy_bonus_saldo_test.sql` baru, 14/14)
- `smoke_anon_register.sh` -> **OK bersih**
- `snapshot_functions.sh` -> 30 fungsi, 0 hilang, tanpa cabang kritis hilang
- `flutter analyze` -> 0 error / 0 warning; `flutter test` -> **2588 lulus**
- Test `daily_login_test` diperbaiki: "kemarin" kini memakai
  Asia/Jakarta (server ber-zona UTC, jadi `current_date - 1` bisa berbeda
  dari hari yang dihitung fungsi).

## 2026-11-01 — Audit peredaran koin + tutup 3 jalur koin gratis → uang

### `20261101190000_paid_only_economy.sql` (APPLIED via Management API)
- **Audit peredaran (live):** 521 user (474 male / 47 female).
  Peredaran **11.081 koin** = bonus 10.093 (91%) + earned 988 +
  topup 0. **0 top-up, 0 withdraw** — ekonomi masih pra-pendapatan
  (`play_topup` & `call_billing` flag belum published). Bonus pernah
  dikeluarkan: signup 11.250 · welcome_anon 100 · daily_login 75 ·
  migrate 58 · one_time 45 · new_chat 40. Female bonus sudah dinolkan
  (1.278 via `female_bonus_reset`). Bocor terwujud: 1 koin bonus bayar
  call_video (≈Rp 2). `economy_invariant_check` → 0 pelanggaran.
- **L1 (call):** `charge_metered` memakai `ledger_spend` (bonus DULU) →
  bonus male bayar menit call → 30% net jadi `earned` female →
  withdrawable Rp 7/koin. Fix: `ledger_spend_paid` + precheck
  `yukcoin_paid_total`; `call_billing_tick` afford-check pakai paid
  (bonus-only → `can_continue=false`, bukan exception).
- **L2 (withdraw):** `request_withdraw` cek saldo TOTAL + debit
  `ledger_spend` (bonus dulu). Fix: cek + debit HANYA bucket `earned`
  via helper baru `ledger_spend_earned` (advisory lock, service_role).
  Refund `admin_withdraw_process` sudah per-bucket → tak berubah.
- **L3 (misi):** `claim_mission_reward` selalu kredit `earned` untuk
  siapa pun (missions.gender='all' hampir semua) → male klaim misi
  harian 10–25 koin → kirim koin/gift ke female → withdraw. Fix:
  female → `earned`; selain female → `bonus` (non-withdrawable, tak
  bisa ditransfer/bayar fitur).
- **Helper baru:** `yukcoin_paid_total(uuid)` (cermin paidBalance
  client) + `ledger_spend_earned(uuid,text,int,text)`.
- **CATATAN URUTAN:** file ini HARUS setelah
  `20261101180000_economy_consistency_fixes.sql` — file itu me-replace
  `request_withdraw` dari salinan lama (masih `ledger_spend`) dan akan
  membuka kembali L2 kalau di-apply setelah file ini. (Timestamp 180000
  asli milik file ini dipindah ke 190000 karena bentrok dengan file
  consistency_fixes yang muncul saat sesi berjalan.)
- **Test:** suite baru `economy_paid_only_test.sql` 25/25 (charge
  paid/mixed/bonus-only, tick afford, withdraw earned-only/bonus-only/
  mixed, misi by-gender, anti-dobel). Perbaikan suite lama:
  `economy_money_test` & `economy_hardening_test` withdraw 1500→2000
  (ikut `withdraw_min_coins` live sejak 20261101160000 — test basi,
  bukan regresi). Semua suite SQL hijau; `check_migrations.sh --all`
  OK; snapshot refresh (30 fungsi, 0 hilang; diff hanya catch-up
  marker migrasi basi + tier bonus `send_gift` yang sudah dihapus
  20261031110005).

## 2026-11-02 — call_billing_tick: remaining konsisten + match tertagih 120 dtk

### `20261102120000_billing_remaining_consistency.sql` (APPLIED via Management API)

- **Masalah 1 (counter loncat 986↔1021):** `remaining` yang dikirim ke
  client memakai dua definisi — `yukcoin_paid_total` (topup+earned)
  pra-charge, `yukcoin_total` (semua bucket) pasca-charge & early-return.
  Client menaruhnya langsung ke saldo UI → poll profiles.points
  mengoreksi bolak-balik. **Fix:** `remaining` SELALU `yukcoin_total`;
  `v_paid` dipisah khusus afford-check (`charge_metered` menolak bonus).
- **Masalah 2 (match tidak tertagih):** migrasi 240000 (timezone)
  menulis `(elapsed_sec - 120)/60` → tagihan pertama baru di elapsed
  180 dtk ≈ 3 menit. Dikembalikan ke `elapsed_sec/60 - 1` → menit ke-1
  gratis, charge mulai **120 dtk** sesuai desain 110011/190000.
- **Catatan flag:** `call_billing` feature_flags `published:false` —
  per-menit billing OFF untuk user biasa; admin (`zunixe@gmail.com`)
  bypass via `feature_enabled_for` → tetap tertagih.

### `20261102123000_publish_call_billing.sql` (APPLIED via Management API)

- `feature_flags.call_billing` → `published:true` — billing per-menit
  berlaku untuk SEMUA user (keputusan produk).
- **Verifikasi:** `random_match_test.sql` 26/26 (+3 asersi: charge
  1 menit @130 dtk, remaining=total, tick ulang tidak dobel);
  call_billing_toggle 3/3, call_test 20/20, economy 27+28+14 hijau.

## 2026-11-03 — Ping match: jangan kembalikan call mati

### `20261103000000_random_match_ping_dead_call.sql` (APPLIED via Management API)

- **Gejala user:** "pas klik match pas mau ngebuka aga ngelag — layarnya
  jadi kaya double". Dua akar:
  1. `matched_call_id` menempel di `random_match_queue` sampai
     leave()/re-join; `random_match_ping` selalu menjawab 'matched'
     tanpa cek call masih hidup → client membuka `CallSession` untuk
     call yang SUDAH ended di atas sesi baru → media ganda (lag) +
     tampilan duplikat.
  2. `RandomMatchState.callId` tidak pernah dibersihkan di client →
     dedup `_openSession` bisa lolos untuk callId basi; `_openCallRoute`
     juga tidak cek `routeTracker` (ensureCallScreenRoute bisa push
     duluan saat resume/tap notif → layar ditumpuk).
- **Fix server:** ping memvalidasi `calls.status='answered'` +
  `coalesce(last_seen_at, answered_at, created_at)` segar <120 dtk
  (heartbeat client 25 dtk, zombie sweep admin 75 dtk → 120 aman).
  Call ended/zombie → `matched_call_id` & `matched_with` dibersihkan,
  jawab 'waiting' (user tetap antre → bisa ter-pair ulang).
- **Fix client:** `copyWith.clearCallId` (dipakai start/next/cancel/
  hangup/onRemoteEnded/_fail); `hangup`/`onRemoteEnded` ikut
  `unawaited(_svc.leave())`; dedup `_openSession` menolak 'matched' basi
  saat fase connecting/inCall dengan callId lain, dan promote→inCall
  bila `callProvider.activeSession.callId` sama; `_openCallRoute`
  mengecek `routeTracker.contains(kCallScreenRoute)`.
- **Verifikasi:** `random_match_test.sql` **30/30** (+5 asersi:
  ended→waiting + jejak dibersihkan, zombie heartbeat basi→waiting,
  hidup→matched + call_id benar); `check_migrations --all` OK bersih.

## 2026-11-01 — Progres nyonya = saldo earned net + min withdraw 2000

### `20261101160000_nyonya_progress_earned_balance.sql` (APPLIED via Management API)

- **Masalah:** `nyonya_1000` memakai `v_total` (SUM amount>0 SEMUA
  bucket = kumulatif seumur hidup) → female lama langsung
  `is_completed` → "Klaim +100" walau saldo withdrawable masih kecil.
- **Fix:** misi `target_unit='coins'` dihitung dari `v_earned_bal` =
  `SUM(amount) WHERE bucket='earned'` NET — rumus sama dengan
  `v_earned` di `request_withdraw` (koin yang benar-benar bisa
  ditarik). Belanja/withdraw menurunkan progres. `v_total` tetap
  untuk unlock misi harian @1200 dan output `total_coins`.
- **Setting:** `withdraw_min_coins` 1500 → **2000** (live via UPDATE
  di migrasi yang sama).
- **UI:** tombol withdraw di `saldo_screen` non-aktif saat
  `earned < minCoins` (`WithdrawState.canWithdraw`).
- **Verifikasi:** live ChatAja earned_net=0 → progress 0 + tak
  selesai (tampil "0/1000", bukan "Klaim +100"); pgTAP 19/19
  (+2 asersi: kredit bonus tak dihitung, pengeluaran earned
  menurunkan progres); widget test 22/22; gate migrasi OK;
  snapshot refresh (0 hilang).

## 2026-11-01 — Progres misi 'coins' dari ledger kumulatif (nyonya)

### `20261101150000_nyonya_coins_progress.sql` (APPLIED via Management API)

- **Masalah:** `nyonya_1000` ("kumpulkan 1000 koin") membaca
  `user_missions.progress` yang TIDAK ADA penulisnya → counter 0/1000
  selamanya walau user sudah mengumpulkan ribuan koin.
- **Fix:** misi `target_unit='coins'` di `get_user_missions` dihitung
  dari `v_total` = SUM(amount>0) coin_ledger (definisi sama dengan
  unlock misi harian @1200). Retroaktif — semua female langsung
  melihat progres benar; klaim tetap via `claim_mission_reward`.
- **UI:** female "Tugas Pemula" menampilkan dua counter rata kanan —
  chip koin `cur/1000` (berubah jadi tombol "Klaim +100" saat penuh)
  + "x/y selesai". Male tetap "x/y selesai".
- **Verifikasi:** pgTAP 17/17 (700→700/1000 belum selesai; 1100→cap
  1000 + selesai); live female kumulatif 3646 → 1000/1000 claimable;
  widget test 14/14; gate migrasi OK; snapshot refresh.


## 2026-11-01 — My Level (level kumulatif topup, male only)

### `20261101130000_my_level.sql` (APPLIED via Management API)

- **Fitur:** halaman "My Level" ala app referensi — level dari **kumulatif
  koin topup** (`coin_ledger` bucket `topup`, amount > 0), khusus MALE.
  Naik level → reward koin ke bucket `bonus` (non-withdrawable, server
  menolak bonus untuk gift → tidak bisa jadi jalur withdraw).
- **Skema:** tabel `level_config` (tangga Lv.0=0 … Lv.10=1.000.000 + reward
  0/50/100/150/200/300/400/500/750/1000/2000; admin ubah via SQL) dan
  `user_level_state` (penanda reward per level sudah dicetak; client hanya
  SELECT).
- **RPC baru (bukan FROZEN):** `get_my_level()` — hitung level + grant reward
  idempoten (`for update` + `reward_granted_level`; male-only + gate
  `points_enabled`), return `{level, cumulative, next_level, next_at,
  remaining, ladder[], just_rewarded[]}`; `get_user_level(p_user)` — badge
  level (female/dummy → 0). Tidak menyentuh `credit_play_topup`,
  `charge_metered`, `profile_public`.
- **Verifikasi:** `scripts/run_sql_tests.sh my_level_test.sql` → **18/18**
  (anon ditolak; kumulatif hanya topup positif; earned/bonus/spend tidak
  mengubah level; reward tidak dobel saat dipanggil ulang; kill-switch
  `points_enabled=false` menahan reward & melepasnya saat ON; reward tidak
  masuk withdrawable). `check_migrations.sh --all` OK bersih; snapshot
  functions di-refresh (0 fungsi hilang).

## 2026-11-01 — Audit & hardening ekosistem koin (Fase 21)

**Temuan audit:** 5 jalur pencetakan koin gratis + 1 bug withdraw yang
aktif merugikan user. Semua migrasi sebelumnya SUDAH ter-apply live, jadi
celah ini nyata (bukan draft). Diperbaiki lewat 5 migrasi.

### `20261101100000_withdraw_single_debit.sql` (APPLIED via Management API)

**Bug (uang nyata):** `20261031110016` membuat `request_withdraw` mendebit
koin saat pengajuan, tapi `admin_withdraw_process` (fungsi yang benar-benar
dipanggil app — `lib/screens/admin_withdraw_tab.dart`) MASIH mendebit lagi
saat approve dan sebelumnya memeriksa `v_total < coin_amount`. Karena saldo
sudah terpotong, cek itu hampir selalu gagal → `INSUFFICIENT_AT_APPROVE`,
DAN jalur tolak tidak me-refund apa pun → **koin user hilang permanen**.

1. **Satu titik debit:** tetap di `request_withdraw` (koin terkunci selama
   pending). `admin_withdraw_process` tidak lagi mendebit.
2. **Reject → refund penuh**, tepat sebesar baris ledger `withdraw` milik
   pengajuan itu (reverse per bucket, ledger tetap append-only).
3. **`FOR UPDATE` + `UPDATE ... WHERE status='pending'`** → approve ganda
   tidak mungkin.
4. **`pg_advisory_xact_lock('withdraw:'||uid)`** di `request_withdraw` →
   dua pengajuan paralel tidak over-debit.
5. **Test diperbaiki:** `economy_money_test.sql` dulu menguji
   `admin_withdrawal_review` (fungsi legacy yang sudah di-revoke) — kini
   menguji `admin_withdraw_process` (yang dipakai app).
6. **Verifikasi live:** request 2000→500 (debit −1500), approve → tetap
   500 + status `paid`; reject → kembali 2000 + status `rejected`.
   `economy_money_test` 32/32.

### `20261101100100_coin_mint_lockdown.sql` (APPLIED via Management API)

1. **`credit_welcome_bonus`** — `20261031110013` memberi `GRANT` ke
   `authenticated`, badan fungsi tidak pernah cek `auth.uid()`, dan batas
   per-IP dilewati bila `p_ip` NULL. Siapa pun bisa memanggil berulang
   dengan `install_id` acak → 100 koin gratis tiap panggilan.
   → kembali **`service_role` saja** (edge fn `welcome-bonus` memakai
   service_role, alur normal tidak berubah) + guard client hanya boleh
   mengkredit dirinya.
2. **`charge_metered`** — `p_recipient` input bebas client dan
   `ledger_spend` boleh memakai bucket `bonus` → male memindahkan koin
   gratis ke akun female miliknya sendiri sebagai `earned` (withdrawable).
   → **`service_role` saja** (pemanggil sah: `call_billing_tick`,
   `_spend_yukcoin_core` — keduanya SECURITY DEFINER) + validasi
   `p_recipient` harus callee dari call tersebut.
3. **Misi** — `update_mission_progress` menerima `p_increment` tanpa batas;
   `user_missions` punya policy `FOR ALL USING(user_id=auth.uid())` sehingga
   client menulis `is_completed=true` langsung. Reward masuk `earned`.
   → increment di-clamp 1..120, policy dipisah (SELECT saja untuk client),
     INSERT/UPDATE/DELETE dicabut, `claim_mission_reward` memakai
     `UPDATE ... WHERE claimed=false RETURNING` (anti claim ganda).

### `20261101100200_disable_room_gift.sql` (APPLIED via Management API)

**Gift hanya untuk chat 1:1** (penerimanya jelas). Di room/group penerima
ambigu → fitur kirim gift dinonaktifkan.

Alasan tambahan: `send_room_gift` tidak pernah diperbarui sejak 2026-09-08 —
masih menerima bucket `bonus`, tanpa cek registrasi, tanpa rate limit, qty
sampai 20. Karena withdraw menjumlah semua bucket, ini jalur pencucian
bonus → earned.

- Badan fungsi kini selalu raise; EXECUTE dicabut dari semua role.
- Client: wiring `onOpenGiftPanel` di room dihapus, `_openRoomGiftPanel`,
  `sendRoomGift` (provider + service) dihapus. **Pesan gift lama tetap
  dirender read-only**; group memang tidak pernah punya jalur gift.
- `schema_sync_test` tetap lulus (fungsi masih ada).

### `20261101100300_economy_integrity_hardening.sql` (APPLIED via Management API)

1. **`point_events`** — RLS memang sudah aktif (koreksi: klaim "RLS inert"
   di audit awal SALAH), TAPI grant default Supabase memberi
   INSERT/UPDATE/DELETE ke `anon`+`authenticated`, dan hanya ada policy
   SELECT → client bisa **memalsukan skor leaderboard mingguan** dan
   menghapus riwayat. → grant tulis + TRUNCATE dicabut.
2. **`profiles`** — policy `profiles_update_own` (20260829060000) terbuka
   untuk semua kolom; penjaga `points` lama sudah dihapus. Client bisa
   menulis `points`/`*_balance`/**`created_at`** (dipakai syarat umur akun
   72 jam withdraw). → trigger `guard_economy_columns` mengembalikan nilai
   lama untuk client; konteks internal (migrasi/job/service_role/test,
   `auth.uid()` null) tidak dibatasi.
3. **`ledger_spend`** — baca-lalu-tulis tanpa lock → dua debit paralel bisa
   sama-sama lolos cek saldo. → `pg_advisory_xact_lock('wallet:'||user)`.
4. **Realtime** — `profiles` & `app_settings` dikeluarkan dari publication
   (payload WAL membawa saldo/email/`fcm_token`/`app_shared_secret`;
   revoke per-kolom tidak melindungi WAL).
5. **`get_earnings_summary`** — tambah guard anti-IDOR (dulu bisa membaca
   penghasilan user lain). Kontrak JSON dipertahankan PERSIS.

### `20261101100400_unlock_photo_fix.sql` (APPLIED via Management API)

1. Overload `text` (20261031110005) membandingkan parameter `text` dengan
   kolom `user_photos.id` bertipe `uuid` → **error runtime 42883**. Kini di-cast
   eksplisit + validasi mode.
2. Wajib koin beli (topup+earned), idempoten via `photo_unlocks`, dan tidak
   bisa membuka foto sendiri.
3. Overload lama (`uuid`) yang MASIH menerima bucket `bonus` dicabut dari
   `authenticated` → hanya satu overload yang bisa dipanggil client.

### Verifikasi keseluruhan (2026-11-01)

- `check_migrations.sh` → **OK bersih**
- `run_sql_tests.sh` → **seluruh suite hijau** (economy_money 32/32,
  economy_matrix 33/33, economy_invariants 14/14, security_guards 10/10,
  schema_sync 63/63, dll)
- `smoke_anon_register.sh` → **OK bersih** (registrasi tidak rusak oleh
  guard kolom `profiles`)
- `snapshot_functions.sh` → 30 fungsi, 0 tidak ditemukan, tidak ada cabang
  kritis hilang
- `flutter analyze` → 0 error / 0 warning; `flutter test` → **2516 lulus**
- Uji role `authenticated` live: `credit_welcome_bonus`, `charge_metered`,
  `send_room_gift`, tulis `user_missions`, tulis `point_events` → **semua
  ditolak**; tulis `profiles.points` → diabaikan.

## 2026-10-31 — Audit exclusions + moderation fix (Fase 20)

### `20261031110018_economy_invariant_exclusions.sql` (APPLIED via Management API)

1. **`economy_audit_exclusions`** (tabel baru, RLS, service-role only) —
   daftar putih temuan checker yang sudah diverifikasi manual. Ledger
   TIDAK dihapus: immutable + audit trail uang harus bertahan setelah
   akun dihapus.
2. **Checker** kini melewati `(check_name, user_id)` yang tercatat —
   kontrak "0 baris = sehat" berlaku lagi; pelanggaran BARU tetap muncul.
3. **3 orphan dikenal dicatat:** `96c59b22…` (akun dihapus, +10 bonus),
   `a2810e43…` (dummy venty, +4 net), `a8389420…` (akun dihapus, +50
   signup) — semua bucket `bonus`, non-withdrawable.

### `20261031110017_moderation_activity_requested_at.sql` (APPLIED via Management API)

1. **Fix bug live:** `admin_moderation_activity` mereferensikan
   `moderator_applications.requested_at` — kolom nyata `created_at`
   (definisi tabel 20261026130000). Fungsi error sejak lahir; ditangkap
   `moderator_slots_test.sql`. `country_send_permits.requested_at` benar —
   dibiarkan.
2. **Verifikasi:** `moderator_slots_test.sql` 17/17.

## 2026-10-31 — Withdraw debit on request (Fase 19)

### `20261031110016_withdraw_debit_on_request.sql` (APPLIED via Management API)

1. **Lubang uang yang ditutup:** `request_withdraw` live sebelumnya membuat
   baris `withdrawal_requests` pending **tanpa mendebit ledger** — saldo
   user tetap utuh selama pending, dan `admin_withdrawal_review` menulis
   `withdraw_refund` saat reject (koin gratis) / membayar tanpa pernah
   memotong (uang keluar + koin tetap).
2. **Fix:** injeksi debit `withdraw` −N ke `coin_ledger` (bucket `earned`)
   saat request dibuat — atomik dalam transaksi yang sama. Reject →
   `withdraw_refund` +N mengembalikan debit itu (bukan koin baru).
3. **Verifikasi:** `economy_money_test.sql` § withdraw menguji debit saat
   request + refund saat reject (saldo akhir = awal); suite lulus 32/32.

## 2026-10-31 — Economy invariant checker (Fase 18)

### `20261031110015_economy_invariant_check.sql` (APPLIED via Management API)

1. **`economy_invariant_check(p_limit int default 100)`** — diagnostik
   read-only SECURITY DEFINER; mengembalikan baris pelanggaran invariant
   ledger↔profile (0 baris = sehat):
   - `points_mismatch` — `profiles.points` ≠ sum(`coin_ledger.amount`);
   - `phantom_balance` — kolom saldo non-nol tanpa baris ledger;
   - `bonus_mismatch` — `bonus_balance` ≠ sum(bucket='bonus');
   - `earned_mismatch` — `earned_balance` ≠ sum(bucket='earned');
   - `negative_bucket` — sum per (user,bucket) < 0 (jalur debit bocor);
   - `orphan_ledger` — baris ledger untuk user tanpa profil.
2. **Akses:** `REVOKE` dari public/anon/authenticated, `GRANT` ke
   `service_role` saja — fungsi mengekspos saldo semua user. Dipakai admin/
   CI via Management API + test `economy_invariants_test.sql`.
3. **Hasil live pertama:** 0 pelanggaran saldo/bucket — hanya 3
   `orphan_ledger` residu lama (baris ledger untuk uid tanpa row profiles;
   kemungkinan profil terhapus tanpa hapus auth.users — ledger immutable
   `coin_ledger_no_delete`, didokumentasikan bukan dihapus).

## 2026-10-31 — Charge-on-match (Fase 17)

Keluhan user: fee match 2 koin dipotong saat klik — kalau antrean tak
menemukan siapa pun, koin hangus sia-sia. Kini fee dipotong **tepat saat
pair terbentuk** di server.

### `20261031110014_match_charge_on_pair.sql` (APPLIED via Management API)

1. **`_spend_yukcoin_core`** (fungsi internal baru) — seluruh logika debit
   `spend_yukcoin` (flag free-pass, allowlist, female exempt, ledger,
   `yukcoin_consumptions`, `point_events`, `platform_revenue`) TANPA auth
   guard. Diperlukan karena `random_match_join` harus menagih **partner**
   male saat joiner-nya female — guard `p_user = auth.uid()` menolak itu.
   `REVOKE ... FROM public, anon, authenticated` — tak bisa dipanggil user.
2. **`spend_yukcoin`** — wrapper tipis: auth guard + delegasi ke core
   (perilaku dari luar identik).
3. **`random_match_join`** —
   - male dengan `yukcoin_total < fee` → `{"status":"no_funds"}` sebelum
     masuk antrean (tidak menunggu percuma);
   - kandidat partner male tak mampu bayar diskip lewat precheck saldo;
   - fee ditagih `_spend_yukcoin_core` TEPAT sebelum `calls`/queue/pairs
     dibuat — satu transaksi atomik (gagal pair → debit rollback);
   - race saldo (lulus precheck, gagal charge) → kandidat berikutnya;
   - kalau payer adalah joiner sendiri & gagal → baris antrean dihapus +
     `no_funds`;
   - `points_enabled=false` → free otomatis (core free-pass).
4. **Client** — `_chargeMatchFee`/`chargeMatchSearch` dihapus; `start()` &
   `next()` langsung join; status `no_funds` → `errorCode MATCH_NEED_COIN`
   (dialog top-up yang sudah ada).

### Test
- pgTAP `random_match_test.sql` 20/20: +assert male saldo 0 → `no_funds`
  tanpa baris antrean; debit `match_search −2` dari male saat matched;
  `platform_revenue` tercatat; female tidak didebit. Flag `random_call`
  dipaksa OFF di dalam transaksi §0 (prod sudah publish → test deterministik).
- E2E live (dummy saldo 0): `random_match_join` → `{"status":"no_funds"}`,
  0 baris antrean, 0 tulisan.
- `_spend_yukcoin_core` tidak bisa dieksekusi role `authenticated`.

## 2026-10-31 — Konsistensi points_enabled (Fase 16)

Kill-switch `points_enabled` kini seragam mengikuti 3 semantik yang sudah
settle: **free-pass** (aksi jalan tanpa tagih), **block** (transfer/nilai
ke user lain), **no-credit** (earn → no-op graceful).

### `20261031110013_points_enabled_consistency.sql` (APPLIED via Management API)

1. **`spend_yukcoin`** — sebelumnya TAK cek flag → fee `match_search` &
   spend `gift` tetap menagih saat poin OFF. Kini free-pass semua feature
   (`tier:'free', free:true` — pola `unlock_photo`/`deduct_chat_point`).
2. **`charge_metered`** — free-pass `charged:0` saat OFF (defense:
   `call_billing_tick` sudah cek, tapi fungsi bisa dipanggil langsung).
3. **`request_withdraw`** — `{ok:false, error:'POINTS_DISABLED'}` saat OFF
   (block — pola error yang sama dengan `FEMALE_ONLY`; client withdraw
   menampilkan error apa adanya).
4. **`claim_mission_reward`** — `{error:'POINTS_DISABLED'}` saat OFF
   (reward misi = kredit `earned` = ekonomi; `update_mission_progress`
   dibiarkan jalan — progress bukan ekonomi, user tak kehilangan progres).
5. **`credit_welcome_bonus`** — `{granted:false, reason:'points_disabled'}`
   saat OFF (graceful; edge fn welcome-bonus sudah menangani granted:false).

Tidak disentuh: fitur v2 gratis (`undo/edit/buy_*_v2` — kill-switch sendiri
`yukcoin_v2_enabled`), semua reads (`get_wallet`, `get_user_missions`, …),
fungsi admin, dan fungsi FROZEN (snapshot tidak perlu regen).

**Client:** nol ubahan — `chargeMatchSearch` sudah menerima `free:true`,
`claimReward` sudah baca `res['error']`, withdraw provider menampilkan
error string, edge fn welcome-bonus menangani `granted:false`.

**Verifikasi live:** `pg_get_functiondef` — 5 fungsi `reads_flag=true` +
guard baru ada. ⚠️ Flag tidak diuji flip di prod (OFF = semua fitur
berbayar gratis global); verifikasi matriks butuh window maintenance.

## 2026-10-31 — Audit poin: fix inkonsistensi (Fase 15)

### `20261031110012_points_fixes_audit.sql` (APPLIED via Management API)

1. **`charge_metered`** — harga/cut call kini baca KOLOM
   (`call_audio_cost_per_min`, `call_video_cost_per_min`, `call_cut_pct`)
   yang diedit admin; `metered_pricing` JSONB hanya fallback non-call.
   Fix split-brain: sebelumnya debit aktual pakai JSONB basi (seed 1 Okt).
2. **Sync `metered_pricing`** dari kolom sekarang (satu kali).
3. **Auth guard** `auth.uid()` di `update_mission_progress`,
   `claim_mission_reward`, `get_user_missions`, `check_user_total_coins`
   (sebelumnya siapa pun bisa tulis/baca misi uid lain).
4. **`admin_mass_bonus`** — skip female (`gender <> 'female'`): female
   tidak boleh punya bucket bonus.
5. **`get_earnings_summary`** — whitelist income diselaraskan:
   +`coin_received`, `subscribe_income`, `photo_income` (unlock_photo
   menulis `photo_income`, bukan `photo_unlock_income`).
6. **`spend_yukcoin`** — female gratis untuk `match_search` (parity
   client); fee match_search dicatat ke `platform_revenue` (hangus).
7. **`admin_update_point_settings`** — kembalikan `yukcoin_v2_enabled`
   (hilang di rewrite 110004 → toggle admin no-op) + tambah
   `coin_tx_max_per_hour` (dibaca send_coins/send_gift, sebelumnya tak
   bisa diubah).
8. **`check_user_total_coins` / `get_user_missions`** — "total koin" =
   kumulatif kredit seumur hidup (bukan saldo bersih) → unlock misi
   harian @1200 tidak turun saat user belanja.

### Flutter
- `call_session.dart` — tangkap `reason`+`free_limit_min` saat
  `can_continue=false`; getter `billingPauseReason`/`billingFreeLimitMin`.
- `call_no_coin_dialog.dart` — +`showCallFreeLimitDialog` (tanpa tombol
  top-up: female di batas gratis tak bisa melanjutkan dengan top-up).
- `call_screen.dart`/`random_call_screen.dart` — `reason='free_limit'`
  → dialog batas gratis; `insufficient` → dialog koin habis.
- `history_tile.dart` — label untuk call/gift/match/topup/mission/
  withdraw/photo/subscribe/welcome/refund (sebelumnya "Lainnya").
- `admin_panel_screen.dart` — hapus 4 field mati (cost_undo/edit/
  extra_slot/ghost yang tidak dihandle RPC) + field `coin_tx_max_per_hour`.
- `point_tab_cards.dart` — +flag `random_call` di kartu Publish.
- `chat_selection_mixin.dart` — undo/edit gratis: hapus dialog biaya +
  charge RPC; label menu tanpa harga.
- `profile_photos.dart` — dialog slot foto "gratis" (bukan harga 60).
- `private_chat_message.dart` — track `daily_receive_gift` dedup per
  message id (sebelumnya 1 RPC per render bubble).
- `points_provider.dart` — `deductBeforeSend`/`refundChatPoint` skip
  RPC untuk 'text' (gratis — hemat 1 RPC per pesan teks).

## 2026-10-31 — Match berbayar + lawan jenis otomatis (Fase 14)

Keputusan user: klik Match/Next = **−2 poin** (hangus), match **menit ke-1
gratis**, menit ke-2+ tarif video 20/menit, **female gratis**. Pilihan gender
dihapus — otomatis lawan jenis.

### `20261031110011_match_paid_opposite_gender.sql` (APPLIED)

1. **`spend_yukcoin`** — allowlist ditambah `match_search`
   (`gift`,`gift_sent`,`match_search`). Fitur lain tetap gratis.
2. **`random_match_join`** — `v_want` dipaksa lawan jenis:
   `male → female`, `female → male` (selain itu pakai argumen).
3. **`random_match_stats`** — `sample`, `v_online`, `v_waiting` difilter
   lawan jenis + field baru `opposite_gender`.
4. **`call_billing_tick`** — `kind='random'`:
   `billable_minutes = greatest(0, elapsed_sec/60 - 1)` → **0–119 s = 0 koin**;
   respons +`free_seconds_left`.

### Flutter
- `random_match_service.dart` — +`chargeMatchSearch()` (RPC `spend_yukcoin`
  fitur `match_search`, 2 poin).
- `random_match_provider.dart` — +`_chargeMatchFee()` (female gratis,
  guard try/catch agar test/klien belum siap tidak memblokir); dipanggil di
  `start()` & `next()`. `onRemoteEnded()` TIDAK dikenai biaya.
- `random_match_screen.dart` — `_GenderChips` + `_Chip` **dihapus**, diganti
  badge **"Kamu akan dipasangkan dengan Cowok/Cewek"**. Error
  `MATCH_NEED_COIN` → dialog "Koin tidak cukup" + tombol **Isi Koin**
  (`NavGate.topupSheet`).
- `lib/widgets/call_no_coin_dialog.dart` (BARU) — dialog "Koin habis" saat
  call berjalan: **Lanjutkan/Isi Koin** atau **Akhiri**.
- `call_session.dart` — +`awaitingContinue`, +`resumeBillingAfterTopup()`,
  +`endCallNoCoin()`. `_billingTick` saat `can_continue=false` **TIDAK lagi
  memutus panggilan** — dijeda + dialog.
- `call_screen.dart` & `random_call_screen.dart` — cek `awaitingContinue` tiap
  detik → tampilkan dialog.
- `strings_random_mx.dart` — +10 string ID/EN.

### Verifikasi
- `spend_yukcoin` memuat `match_search` ✅
- `random_match_join` memuat paksa lawan jenis ✅
- `random_match_stats` memuat `opposite_gender` ✅
- `call_billing_tick` memuat aturan "menit ke-1 GRATIS" untuk match ✅
- `check_migrations.sh --all` → OK bersih
- `flutter analyze` → 0 error/0 warning; `flutter test` → 2435 lolos
- APK profile terinstall di HP

## 2026-10-31 — Poin hanya untuk call/video/match/gift (Fase 13)

**Keputusan user:** poin HANYA berkurang untuk **call, video call, match
(video), dan gift**. Fitur lain gratis: filter gender, cari orang sekitar,
undo pesan, edit pesan, slot foto tambahan, mode hantu.

### `20261031110010_points_only_calls_gifts.sql` (APPLIED)

1. **`call_billing_tick`** — hapus cabang `if c.kind = 'random' then ...
   gratis`. Match sekarang **ditagih** dengan tarif `call_video`
   (20 koin/menit), split 70% platform / 30% callee seperti video call biasa.
   `unit_cost` juga memakai `call_video_cost_per_min` untuk match.

2. **`gate_feature`** — langsung `return { ok:true, charged:0, free:true }`.
   Fitur akses-harian (filter gender, nearby) tidak pernah memotong poin lagi.

3. **`spend_yukcoin`** — hanya `gift`/`gift_sent` yang didebit. Fitur lain
   (`extra_photo_slots`, `ghost_mode`, `undo_message`, `edit_message`) →
   `{ tier:'free', charged:0 }` tanpa menyentuh ledger.

### Flutter
- `lib/screens/point_history/widgets/yukcoin_how_to.dart` — daftar "Cara
  pakai" hanya Audio call, Video call (hapus filter gender, nearby, undo,
  edit, slot foto, ghost).
- `lib/screens/privacy_settings_screen.dart` — blok **mode hantu dihapus**
  (+ `_buyGhost`, variabel terkait, import points_provider).
- `lib/screens/profile/profile_ui2.dart` — tombol **"Beli slot foto"
  disembunyikan** (slot tambahan kini gratis).
- `lib/screens/profile/profile_ui.dart` — kartu YukCoin (kuning) tetap
  tampil untuk male walau `points_enabled=false` → jalur top-up tetap ada.
  Tombol **Top-up** (ikon keranjang) ditambahkan di kartu kuning.

### Catatan top-up
`AppFlavor.topupEnabled` = `true` HANYA untuk build `play` (kebijakan Google
Play: digital goods wajib Play Billing). Build `apkpure`/`admin` tidak
menampilkan transaksi — sheet menampilkan "Top-up segera hadir".

### Verifikasi live
- `gate_feature('gender_filter')` → `charged: 0, free: true` ✅
- `spend_yukcoin(...,'extra_photo_slots',60)` → `charged: 0, free: true` ✅
- `spend_yukcoin(...,'ghost_mode',50)` → gratis ✅
- `spend_yukcoin(...,'undo_message',10)` → gratis ✅
- `call_billing_tick` memuat tarif `call_video` untuk `kind='random'`;
  baris "Random video call: GRATIS" sudah **hilang** ✅
- `flutter analyze` → 0 error/0 warning; `flutter test` → 2435 lolos

## 2026-10-31 — Nolkan bonus koin female (Fase 12)

**Aturan final:** bonus pendaftaran (`signup` 50 koin) **hanya untuk MALE**.
Female tidak punya koin gratis — penghasilan murni dari aktivitas male
(`earned`).

### `20261031110008_zero_female_bonus.sql` (APPLIED)
- RPC `admin_zero_female_bonus(p_dry_run bool)` — idempoten, admin/service_role
  saja. Menghitung bonus per female, lalu menyisipkan entri **kompensasi
  negatif** (`type='female_bonus_reset'`) karena `coin_ledger` melarang
  DELETE/UPDATE (audit trail). Trigger `trg_coin_ledger_balance` otomatis
  menyesuaikan `profiles.bonus_balance` + `points`.
- Hanya bucket `bonus` disentuh; `earned` & `topup` TIDAK berubah.

### Hasil
| Item | Nilai |
|---|---|
| Female terdampak | **26** (dari 48) |
| Total bonus dinolkan | **1.285 koin** |
| Entri kompensasi | 26 |
| Female dengan bonus > 0 setelah | **0** |

Contoh — `ChatAja`: `bonus 0`, `earned 37`, `topup 21`, `points 58`
(sebelumnya `bonus 7`, `points 65`).

### Catatan rincian bonus female sebelum reset
`signup` 1.200 · `welcome_anon` 100 · `test_bonus` 100 · `mission_reward` 10 ·
`new_chat` 10 · `photo_upload` 10 · `one_time` 5 · `room_read` 4 ·
`spend_chat` −1 · `withdraw` −153.

### Guard yang sudah ada (mencegah terulang)
- `credit_welcome_bonus` → male only (`female_no_bonus`)
- `claim_mission_reward` → bucket `earned`
- `send_gift` & `unlock_photo` → tolak koin `bonus`

## 2026-10-31 — Fix gender lock tidak muncul di UI (Fase 11)

### `20261031110007_profile_public_gender_locked.sql` (APPLIED)
- RPC `profile_public` **tidak mengirim `gender_locked`** → `UserModel.genderLocked`
  selalu `false` → dropdown gender tetap editable walau server menolak.
  Ditambahkan `'gender_locked', coalesce(r.gender_locked, false)`.

### Flutter
- `lib/providers/riverpod/auth_provider.dart` — `applyProfileEvent`
  **tidak meneruskan `genderLocked`**: setiap event realtime (status/points)
  menimpa nilainya jadi default `false`. Ditambahkan `pick('genderLocked', ...)`
  (pola sama seperti `needsOnboarding`).

### Verifikasi di HP (Huawei 24129PN74G, wireless 46589)
- Sebelum: Edit Profil menampilkan **"Laki-laki"** (padahal DB `female`) dan
  dropdown **editable**.
- Sesudah: menampilkan **"Perempuan"** + teks **"Gender tidak dapat diubah"**,
  dropdown **read-only** (ikon gembok).
- Penyebab label salah: cache profil lokal (`profile:` di SQLite) menyimpan
  payload lama tanpa `gender_locked`; `pm clear` + install ulang menyelesaikan.
- `flutter analyze` → 0 error.

## 2026-10-31 — Lock gender permanen (Fase 10)

Keputusan user: gender dipilih SEKALI, **tidak bisa diubah** setelahnya.
Gender menentukan seluruh ekonomi (female: misi/penghasilan/withdraw; male:
bayar koin), jadi tanpa lock: male bisa topup → pindah female → withdraw →
platform rugi.

### `20261031110006_gender_lock.sql` (APPLIED)
- `profiles.gender_locked boolean NOT NULL DEFAULT false`.
- Trigger `trg_guard_gender_lock` + fungsi `guard_gender_lock()`:
  - gender tidak berubah → lolos, TAPI `gender_locked` dipulihkan dari nilai
    lama (client DILARANG membuka kunci sendiri lewat RLS terbuka);
  - admin (`is_chatyuk_admin`) → boleh koreksi + tetap terkunci;
  - `old.gender_locked` → gender **dikembalikan ke nilai lama** (revert senyap,
    update kolom lain pada baris sama tetap berhasil — pola `guard_country_lock`);
  - perubahan pertama → otomatis `gender_locked = true`.
- **Backfill retroaktif:** user dengan riwayat `coin_ledger` / `user_missions` /
  `withdrawal_requests` → dikunci. Hasil: **229 terkunci, 294 belum** dari 523.
- `REVOKE UPDATE (gender_locked) ... FROM authenticated, anon` (lapis kedua;
  `-- SAFE:` dengan daftar fitur terdampak).

### Flutter
- `lib/models/user_model.dart` — +`genderLocked` (baca `gender_locked`).
- `lib/services/auth_service_profile.dart` — `registerProfile()` kirim
  `gender_locked: true` (registrasi langsung kunci).
- `lib/widgets/gender_lock_dialog.dart` (BARU) — dialog konfirmasi
  "Pastikan Gender Sudah Benar" (tanpa penjelasan hak gender), dipakai bersama
  registrasi & edit profil.
- `lib/screens/entry_screen.dart` & `register_screen.dart` — konfirmasi gender
  SEBELUM submit registrasi.
- `lib/screens/profile/profile_photos.dart` — dropdown gender jadi **read-only**
  (ikon gembok + "Gender tidak dapat diubah") saat `genderLocked`; bila belum
  terkunci & gender diubah → dialog konfirmasi; snackbar khusus
  "Gender tersimpan dan tidak dapat diubah lagi".
- `lib/config/strings_points_mx.dart` — ±8 string ID/EN.

### Verifikasi live (simulasi JWT)
- User terkunci ubah gender → **tetap female** ✅
- User belum terkunci ubah gender → **berubah + gender_locked=true** ✅
- Client paksa `gender_locked=false` → **tetap true** ✅
- Update kolom lain (`about`) pada user terkunci → **berhasil**, lock tetap ✅
- `check_migrations.sh --all` → **OK bersih**
- `flutter analyze` → 0 error; `flutter test` → 2431 lolos

## 2026-10-31 — Female: SEMUA koin withdrawable + tutup bocor (Fase 9)

Keputusan user: "female koinnya harusnya semua bisa di withdrawal" — tidak ada
lagi bucket `bonus` yang menganggur untuk female.

### `20261031110005_female_withdraw_all.sql` (APPLIED)

**Tutup jalur bocor (WAJIB sebelum membuka withdraw-all):**

1. **`send_gift` (FROZEN, header `-- menyentuh:` ada)** — ditemukan **BUG BESAR**:
   tier `bonus` memberi penerima `bonus_price = n × mult` (= **3× nilai gift**)
   TANPA potongan platform. Koin gratis male jadi saldo female → kalau bisa
   ditarik = rugi **Rp 2.100 per gift 100 koin**.
   → Tier `bonus` **DIHAPUS**. Gift wajib pakai koin `topup`/`earned`
   (error `22023` kalau tidak cukup). Penerima SELALU bucket `earned` + cut 30%.

2. **`unlock_photo`** — tier `bonus` mengredit pemilik foto ke bucket `bonus`.
   → Tier `bonus` **DIHAPUS**. Unlock foto wajib koin beli; pemilik selalu
   bucket `earned`.

**Buka withdraw-all untuk female:**

3. **`request_withdraw`** — validasi terhadap **TOTAL saldo** (semua bucket),
   bukan hanya `earned`. Error `INSUFFICIENT_EARNED` → `INSUFFICIENT_BALANCE`.

4. **`admin_withdraw_process`** — debit **PROPORSIONAL** dari ketiga bucket
   (`bonus`, `topup`, `earned`) sesuai porsi saldo, dengan koreksi pembulatan
   agar tidak melebihi saldo bucket. Return rincian `debited`.

5. **`get_earnings_summary`** — `withdrawable` = **total saldo**.

**Flutter:**
- `saldo_screen.dart` — `_BalanceCard` headline = **total saldo**; chip
  "🔒 Tidak bisa ditarik" **dihapus**; teks hint jadi "Semua koin kamu bisa
  ditarik ke DANA".
- `strings_points_mx.dart` — hint diperbarui.

### Kenapa aman (platform tidak rugi)
Setelah tutup bocor, female HANYA menerima bucket `earned`, yang sumbernya:
- 30% call male (platform sudah ambil 70%)
- 70% gift male (platform sudah ambil 30%)
- 60% unlock foto male (platform sudah ambil 40%)
- reward misi (dibiayani cut platform)

Koin gratis (`bonus`) tidak lagi bisa masuk ke female → "semua withdrawable"
tidak menciptakan kebocoran baru.

### Verifikasi live (Management API, simulasi JWT)
- Saldo uji: bonus 160 + topup 500 + earned 905 = **1.565**
- `request_withdraw(1500)` → gross Rp 10.500, fee Rp 1.000, **net Rp 9.500** ✅
- `admin_withdraw_process(approve)` → `debited: {bonus 153, topup 479, earned 868}`
  (proporsional), saldo 1.565 → **65** ✅
- `send_gift` memuat guard `Gift membutuhkan koin beli/penghasilan` ✅
- Snapshot `functions.sql` di-regenerate (FROZEN `send_gift` & `deduct_chat_point`);
  `check_migrations.sh --all` → **OK bersih**
- `flutter analyze` → 0 error; `flutter test` → 2431 lolos
- Terverifikasi di HP: "Saldo Bisa Ditarik **65 🪙** — Semua koin kamu bisa
  ditarik ke DANA", tanpa chip terkunci

## 2026-10-31 — Auth listener + build & verifikasi device (Fase 7 sisa & 8)

### Fase 7 sisa — provider tidak lagi stale saat ganti user
- `missions_provider.dart`, `earnings_provider.dart`, `withdraw_provider.dart`:
  tambah listener `onAuthStateChange` (signedIn / signedOut / initialSession /
  tokenRefreshed) → `refresh()`. Dulu provider global menyimpan data user
  SEBELUMNYA setelah logout → login akun lain.
- Semua listener di-cancel di `ref.onDispose`.

### Fase 8 — verifikasi end-to-end di device (Huawei 24129PN74G)
APK profile `1.2.74` (177,6 MB) terinstall. Semua layar dibuka & diverifikasi:

| Layar | Hasil |
|---|---|
| Profil (ChatAja, female) | Card **Saldo** & **Misi** sejajar, rata, padding atas benar |
| Saldo | "Saldo Saya 65 🪙", **"Saldo Bisa Ditarik 5 🪙"** (= bucket `earned`), tombol Withdraw, rincian penghasilan (Tugas 15, Bonus 50), statistik aktivitas |
| Withdraw | Saldo withdrawable 5 🪙 ≈ Rp 35, kalkulator, form DANA, riwayat kosong |
| Misi | 12 misi utama dengan reward (`+10`, `+5`, dst) & progress `0/60`, `0/3`; **banner "Misi Harian Terkunci — 65 / 1200 koin"** + 6 misi harian tampil redup/terkunci |

### Status akhir
- `flutter analyze` → **0 error**
- `flutter test` → **2431 lolos, 0 gagal**
- 18/18 misi terhubung ke aksi app
- Withdraw: request → approve → debit `earned` (teruji, `bonus` tidak tersentuh)
- Ekonomi: chat teks gratis, call/gift/foto berbayar, female tanpa bonus koin,
  withdraw hanya dari `earned` @ Rp 7 (margin platform ~82%)

## 2026-10-31 — Wiring tracking misi 18/18 (Fase 6)

### Semua misi kini terhubung ke aksi app

| Misi | Lokasi tracking |
|---|---|
| `message_various_users`, `daily_message_users`, `reply_users` | `lib/mixins/chat_send_mixin.dart` |
| `upload_photos` | `lib/mixins/chat_photo_send_mixin.dart` (foto & video) |
| `private_calls`, `call_minutes`, `daily_private_call_duration` | `lib/screens/call_screen.dart` (`_tick`) |
| `match_calls`, `daily_match_calls` | `lib/providers/riverpod/random_match_provider.dart` |
| `create_posts`, `like_posts` | `lib/providers/riverpod/timeline_provider.dart` |
| `add_friends_in_call` | `lib/providers/riverpod/social_provider.dart` |
| `daily_receive_gift` | `lib/widgets/private_chat_message.dart` (hanya penerima) |
| `daily_online_minutes`, `daily_online_duration` | `lib/providers/riverpod/points_provider.dart` |
| `evening_online_call` (19-23), `night_owl_online_call` (01-05) | `lib/providers/riverpod/points_provider.dart` |
| `nyonya_1000` (total kumulatif) | `lib/providers/riverpod/points_provider.dart` |

### Perbaikan dari review (Fase 7)
- **Dobel hitung online DIPERBAIKI:** dulu tiap tick 30 detik mengirim menit
  KUMULATIF → progress bisa 3× lipat. Sekarang kirim hanya **delta**
  (`_missionOnlineMinutesSent`). Pola sama dipakai untuk menit panggilan
  (`_missionCallMinutesSent`) dan `nyonya_1000` (`_nyonyaLastSent`).
- **Dead code dihapus:** `lib/widgets/missions/missions_list.dart` (memicu gagal
  `strings_test`) & `findMission()`.
- **`PointsService` & `MissionProgressService` lazy client:** konstruksi tidak
  lagi menyentuh `Supabase.instance` → test tanpa inisialisasi Supabase lolos.
- **`trackMission`/`updateProgress` dibungkus guard:** tracking misi adalah efek
  samping NON-KRITIS — kalau Supabase belum siap, aksi utama (kirim pesan, like,
  follow, call) TIDAK ikut gagal.
- **Provider stale saat ganti user:** `missionsProvider`/`earningsProvider`/
  `withdrawProvider` memakai `NotifierProvider` biasa + refresh manual saat
  layar dibuka (`refresh()`), jadi data user baru dimuat ulang.

### Verifikasi
- `flutter analyze` → 0 error.
- `flutter test` → **2431 lolos, 0 gagal**.
- 18/18 misi terhubung (dicek otomatis terhadap daftar `missions` di DB).

## 2026-10-31 — Admin Panel Withdraw (Fase 5)

### `20261031110004_admin_point_settings_withdraw.sql` (APPLIED)
- **FIX BUG KRITIS pre-existing:** `admin_update_point_settings` merujuk 18 kolom
  yang SUDAH DIHAPUS dari `app_settings` (`bonus_registered`, `bonus_rated`,
  `bonus_shared`, `bonus_profile`, `bonus_first_photo`, `bonus_room_read`,
  `bonus_new_chat`, `bonus_invited`, `bonus_first_room`, `bonus_referral`,
  `bonus_online_5min/30min/60min/120min`, `room_reads_daily_limit`,
  `new_chats_daily_limit`, `share_click_reward`, `share_click_cap_daily`) →
  SETIAP pemanggilan gagal `42703`. **Akibatnya admin tidak bisa menyimpan
  pengaturan poin sama sekali.** Semua rujukan mati dibuang, kolom yang masih
  ada dipertahankan, dan ditambah:
  - `withdraw_rate_idr`, `withdraw_min_coins`, `withdraw_fee_pct`,
    `withdraw_fee_min_idr`, `withdraw_max_per_day`,
    `withdraw_min_interval_hours`, `withdraw_min_account_age_hours`
  - `female_free_call_min_per_day`
  - `gift_cut_pct` (sebelumnya tidak tersimpan lewat fungsi ini)

### Flutter (admin)
- `lib/screens/admin_withdraw_tab.dart` — tab **Withdraw** di admin panel:
  - **Kartu ringkasan "Perlu Dicairkan"** (gradient oranye): jumlah pengajuan
    menunggu, **total Rupiah yang harus ditransfer**, total koin, total fee.
    Ringkasan SELALU dihitung dari filter `pending` walau admin sedang melihat
    filter lain (paid/rejected/all).
  - Filter status: Menunggu / Dibayar / Ditolak / Semua.
  - Kartu per pengajuan: user + email, nominal (koin, nilai, fee, diterima),
    tujuan DANA + nama pemilik, tanggal, catatan admin.
  - Tombol **Setujui** (debit `earned` + status `paid`) / **Tolak** (status
    `rejected`), dengan dialog catatan opsional.
- `lib/screens/admin_panel_screen.dart` — `_AdminTab` +`withdraw` (setelah
  `point`), TabController 14 → 15, label & body via `switch` (satu sumber
  kebenaran). `_pointFields` +8 field withdraw & batas call gratis female.
- `lib/config/strings_admin.dart` — +±30 string ID/EN.
- `test/admin_panel_tab_order_test.dart` — urutan enum diupdate (+`withdraw`).

### Verifikasi
- `admin_update_point_settings` (simulasi JWT admin) → semua field withdraw
  tersimpan dengan benar; sebelumnya **gagal total** dengan `42703`.
- `flutter analyze` → 0 error; `flutter test` → 2431 lolos, 0 gagal.
- APK admin `1.2.74-admin` (113,5 MB) terinstall di HP.

## 2026-10-31 — Withdraw Flutter + Saldo/Misi (Fase 3 & 4)

### `20261031110003_withdraw_config.sql` (APPLIED)
- RPC `get_withdraw_config()` — rate, min koin, fee pct, fee min, limit/hari,
  interval, umur akun. Dipakai kalkulator preview di app.

### Flutter (baru)
- `lib/models/withdraw_request.dart` — `WithdrawRequest`, `WithdrawAccount`,
  `WithdrawStatus`, `WithdrawQuote` (kalkulator fee).
- `lib/providers/riverpod/withdraw_provider.dart` — `WithdrawState`,
  `WithdrawConfig`, `WithdrawNotifier` (load config + akun + riwayat, request,
  simpan akun). Provider TIDAK autoDispose → refresh manual saat buka layar.
- `lib/widgets/withdraw/dana_form.dart` — form nomor DANA + nama pemilik,
  validasi client `^(08|62)[0-9]{8,13}$`, normalisasi `62xx` → `0xx`.
- `lib/screens/withdraw_screen.dart` — kartu saldo withdrawable (gradient hijau
  saat cukup, abu saat belum), kalkulator real-time (gross/fee/net), form DANA,
  riwayat ber-status, dialog konfirmasi sebelum submit.
- `lib/screens/saldo_screen.dart` — +kartu **"Saldo Bisa Ditarik"** (`earned`)
  dengan tombol Withdraw → `WithdrawScreen`; fix `saldoMessageReply` &
  `saldoOnlineDuration` agar pakai sumber data benar.
- `lib/providers/riverpod/earnings_provider.dart` — +field `withdrawable`.
- `lib/providers/riverpod/missions_provider.dart` — klaim misi sukses →
  `ref.invalidate(earningsProvider)` (reward misi masuk bucket `earned`).

### Perbaikan dari review (Fase 7, sebagian)
- **Dead code dihapus:** `lib/widgets/missions/missions_list.dart` (tak dipakai,
  memicu gagal `strings_test` karena hardcode Indonesia) & `findMission()`.
- **`MissionProgressService` lazy client:** konstruksi tidak lagi menyentuh
  `Supabase.instance` → test tanpa inisialisasi Supabase lolos (8 test
  `chat_outbox_flow_test` sebelumnya gagal karena ini).

### Verifikasi
- `flutter analyze` → **0 error** (41 info/warning pre-existing).
- `flutter test` → **2431 lolos, 0 gagal**.

## 2026-10-31 — Withdraw ke DANA (Fase 2)

### `20261031110002_withdraw.sql` (APPLIED)
- `app_settings`: +`withdraw_fee_pct` (5), +`withdraw_fee_min_idr` (1000),
  `withdraw_min_coins` 1000 → **1500** (Rp 10.500, di atas biaya admin).
- `withdrawal_requests` (REUSE dari fitur finansial lama, kosong): +`gross_idr`,
  +`fee_idr`. Kolom yang dipakai: `coin_amount`, `rate`, `gross_idr`, `fee_idr`,
  `payout_idr` (net), `status` (pending/paid/rejected), `pay_method` ('ewallet'),
  `pay_account` (nomor DANA), `pay_holder` (nama).
- Tabel BARU `withdraw_accounts` — akun DANA tersimpan per user (RLS own-only).
- RPC: `save_withdraw_account`, `get_withdraw_account`, `request_withdraw`,
  `admin_withdraw_process`, `get_withdraw_history`, `admin_withdraw_list`.
- `get_earnings_summary`: +field `withdrawable` (saldo bucket `earned`).

### Aturan withdraw
- **Hanya FEMALE** (`FEMALE_ONLY`) — male tidak punya bucket `earned`.
- **Sumber HANYA bucket `earned`** — koin gratis (`bonus`) & topup tidak bisa
  ditarik. Ini kunci anti-rugi: platform sudah ambil cut (70% call / 30% gift /
  40% unlock foto) SEBELUM koin masuk `earned`.
- Minimum 1.500 koin · umur akun 72 jam · maks 3×/hari · interval 1 jam.
- Nomor DANA dinormalisasi (`62xx` → `0xx`, strip non-digit), validasi
  `^(08|62)[0-9]{8,13}$`.
- Fee: `max(gross × 5%, Rp 1.000)` → net = gross − fee.
- **Manual approve** oleh admin (`zunixe@gmail.com`); approve melakukan debit
  bucket `earned` (trigger `trg_coin_ledger_balance` urus saldo).

### Verifikasi live (Management API, simulasi JWT)
- `request_withdraw(2000)` → gross Rp 14.000, fee Rp 1.000, **net Rp 13.000**,
  nomor `0812-3456-7890` → `081234567890`, status `pending` ✅
- `admin_withdraw_process(approve)` → status `paid`; `earned_balance` 2000 → **0**,
  `bonus_balance` **tetap 50**, `points` 2050 → **50** (hanya earned didebit) ✅
- Guard: `INSUFFICIENT_EARNED`, `BELOW_MINIMUM` (min 1500), `NOT_ADMIN` (non-admin
  panggil `admin_withdraw_process`) ✅
- Ledger akhir konsisten: bonus +60, earned +5, points +65 (artefak test yang
  tidak bisa dihapus karena trigger `coin_ledger_no_delete`).

## 2026-10-31 — Ekonomi koin berbasis gender + misi female + withdraw (Fase 1)

Keputusan user: **male bayar, female gratis & penghasil**. Chat teks gratis untuk
semua gender; hanya foto (3) & view-once (5) yang berbayar. Female tidak pernah
mendapat koin gratis — penghasilannya murni dari aktivitas male (bucket `earned`).
Reward misi female masuk bucket `earned` (withdrawable).

### `20261031100001_gender_points_missions.sql` (APPLIED)
- Tabel `missions` (master, 18 misi) + `user_missions` (progress per user).
- RPC: `update_mission_progress`, `claim_mission_reward`, `get_user_missions`,
  `check_user_total_coins`.
- RLS: `missions` public-SELECT, `user_missions` own-only (keduanya tabel BARU).

### `20261031100002_mission_fixes.sql` (APPLIED)
- Fix `get_user_missions`: kolom `coin_ledger.kind` → `type`/`bucket` (skema asli).
- Fix `claim_mission_reward`: hapus UPDATE `profiles.points` manual (trigger
  `trg_coin_ledger_balance` sudah auto) → dulu DOBEL hitung.
- Fix `update_mission_progress`: UPSERT `INSERT ... ON CONFLICT` + unique index
  `COALESCE(period_date,'1970-01-01')` (dulu tidak pernah INSERT baris baru).

### `20261031100003_earnings_summary.sql` (APPLIED)
- RPC `get_earnings_summary(p_user_id)` — total/mingguan/harian + breakdown
  (gift, misi, bonus, lainnya) + statistik call (jumlah, durasi, rata-rata match,
  tingkat menjawab).

### `20261031110001_coin_economy_gender.sql` (APPLIED)
- `app_settings` +`female_free_call_min_per_day` (default 30).
- `deduct_chat_point` (**FROZEN**, header `-- menyentuh:` ada): chat TEKS → **0**
  (gratis). Foto 3 & view-once 5 tetap berbayar.
- `call_billing_tick`: caller **female → GRATIS** dengan batas menit/hari
  (dihitung server-side dari `calls`, anti-tamper). Lewat batas → `can_continue:false`,
  `reason:'free_limit'`.
- `charge_metered`: callee **male → income 0** (platform ambil 100%). Hanya
  female yang dikreditkan bucket `earned`.
- `credit_welcome_bonus`: **male only** — female dapat `granted:false`,
  `reason:'female_no_bonus'`.
- `claim_mission_reward`: reward misi → bucket **`earned`** (bukan `bonus`).

### Verifikasi live (Management API)
- `deduct_chat_point` memuat `else 0 end` ✅
- `credit_welcome_bonus` memuat `female_no_bonus` ✅
- `call_billing_tick` memuat `free_limit` ✅
- `charge_metered` memuat `v_recipient_gender` ✅
- Klaim misi `like_posts` (+5): `earned_balance` 0→5, `bonus_balance` tetap 50,
  `points` 50→55, ledger `bucket='earned'` ✅ (tidak dobel)
- Snapshot `functions.sql` di-regenerate — diff `deduct_chat_point` hanya
  +1 komentar & `else c_text` → `else 0` (0 cabang hilang).
- Versi `20261031100001`, `20261031100003`, `20261031110001` dicatat di
  `supabase_migrations.schema_migrations`.

## 2026-10-27 (lanjutan 4) — SATU negara, lock 7 hari, moderator dicabut saat pindah

Keputusan user: satu negara saja (ikut profil), tidak bisa diganti 7 hari,
**IP tidak menimpa negara**, moderator yang pindah negara **otomatis dicabut**,
popup persetujuan wajib, info lewat snackbar + catatan Profil.

### `20261027150000_single_country_lock.sql` (APPLIED)
- **Data diselamatkan:** `country = home_country` bila pilihan eksplisit user
  ada (contoh: `ChatAja` → Argentina).
- Kolom baru `profiles.country_changed_at`; diisi `now()` untuk user lama
  (masa lock mulai hari ini). User baru = `NULL` (boleh betulkan sekali).
- **Dihapus:** kolom `home_country`, `home_country_changed_at`; trigger
  `set_home_country_default_trg`, `guard_home_country_trg`; fungsi
  `set_home_country_default()`, `guard_home_country()`, `set_home_country()`,
  `admin_set_home_country()`.
- **Guard `guard_country_lock_trg`** — perubahan `country`/`country_changed_at`
  hanya lolos bila: flag `chatyuk.country_ok='1'` (RPC resmi) · admin ·
  `country_changed_at IS NULL` · atau sudah lewat **7 hari**. Selain itu nilai
  lama dipulihkan (tanpa error) sehingga update kolom lain tetap jalan.
- **`set_my_country(country)`** — satu-satunya jalur user: tolak kosong, tolak
  `<7 hari` (`cooldown` + `next_change_at`), set + `changed_at = now()`.
  **Auto-revoke:** baris `country_moderators` dengan negara berbeda dicabut
  (`revoked_at = now()`) dan dicatat di `moderator_actions`
  (`auto_revoke_country_change`). Respons menyertakan `revoked_moderator_for`.
- **`admin_set_country(uid, country)`** — admin-only, wajib terisi, tanpa
  cooldown, tercatat di `moderator_actions`.
- **6 fungsi pindah ke `country`:** `can_send_room_media`,
  `room_media_gate_state`, `request_country_permit`, `profile_public`,
  `admin_moderation_overview`, `admin_search_users`.
- `my_moderation_state` kini mengembalikan `revoked` (riwayat pencabutan
  otomatis) untuk catatan di Profil.

### Perbaikan klien
- `login_screen.dart`: **berhenti mengirim `country`/`city`** dari deteksi IP —
  negara tidak lagi bisa ditimpa VPN/roaming.
- `UserModel.homeCountry` dihapus.
- `lib/core/moderation_texts.dart`: `effectiveCountry`, `countryCooldownMessage`,
  `countryChangedMessage`, `countryChangeConfirmBody`, `moderationDate`.
- Profil: **popup persetujuan pindah negara** (menyebut jabatan yang akan
  DICABUT + lock 7 hari), snackbar hasil + tanggal bisa ubah lagi, dan
  **catatan riwayat pencabutan** jabatan moderator.
- Edit Profil (`profile_photos.dart`): negara **tidak** dikirim lewat
  `updateProfile`; memakai popup + `set_my_country` (field lain tetap tersimpan).
- Ajukan moderator saat negara kosong → "Atur negara dulu" (bukan hint media).
- String: hint lamaran **7 hari & 50 pesan** (dari 30/100), kandidat **≥20
  pesan**, konsep "semua negara"/unset dihapus.

### Test
- `test/moderation_texts_test.dart` — **22 unit test** (negara tunggal, lock
  7 hari, format tanggal, isi popup untuk moderator & non-moderator, pesan
  pencabutan).
- `room_media_gate_test` 24 → **29 assert**: lock <7 hari ditolak, UPDATE
  langsung ditahan, lock tak bisa direset, boleh setelah 7 hari, **jabatan
  moderator dicabut + tercatat**, lock berjalan lagi, admin tanpa cooldown,
  `admin_set_country` admin-only & tolak kosong, `set_my_country` tolak kosong.

### Risiko yang diakui
`can_send_room_media` kini memakai `country` yang **bisa** diubah user setiap
7 hari → izin lintas negara bisa berpindah setelah lock lewat. Ini konsekuensi
langsung dari keputusan "satu negara"; lock 7 hari menjaga agar tidak bisa
dipindah sesukanya.

## 2026-10-27 (lanjutan 3) — Admin: unset negara asal = akses semua negara

Keputusan user: (1) hilangkan redundansi dua negara, (2) tanpa baris
`country_moderators` untuk admin, (3) RPC admin-only, (4) tombol "Ajukan"
untuk admin diganti teks statis, (5) unset hanya mengosongkan `home_country`.

### `20261027140000_admin_home_country.sql` (APPLIED)
- RPC `admin_set_home_country(p_uid, p_country)` — **admin-only**
  (`forbidden` 42501 untuk selain admin):
  - `p_country` NULL/kosong → unset (`home_country` & `changed_at` = NULL)
  - `p_country` terisi → set + `changed_at = now()`
  - Menulis di bawah flag trusted `chatyuk.home_country_ok` agar
    `guard_home_country_trg` mengizinkan (termasuk transisi ke NULL)
  - Audit `moderator_actions` (`grant_permit` / `revoke_permit`)
- **Kenapa admin-only:** `can_send_room_media` MELEWATI cek izin lintas
  negara bila `home_country` kosong; untuk admin tak berdampak (bypass lebih
  awal), tapi user biasa tidak boleh bisa mengosongkannya sendiri.

### Data live
- Baris `country_moderators` milik `ChatYuk Admin` (Armenia, Indonesia)
  **dihapus** — admin tidak butuh baris moderator (aksesnya lintas negara
  lewat `is_chatyuk_admin`).
- `home_country` admin → **NULL** (semua negara).

### Perbaikan klien
- `lib/core/moderation_texts.dart` (baru, murni/testable):
  `moderationApplyMessage`, `effectiveHomeCountry`,
  `homeCountryCooldownMessage`.
- Profil: negara asal dibaca dari PROFIL tiap build (+ override sesi) —
  `??=` dihapus (akar "negara tidak tertulis").
- Admin: tile negara asal membuka sheet **Pilih negara / Kosongkan (semua
  negara)**; baris "Admin — akses semua negara" menggantikan tombol Ajukan;
  konsol bisa dibuka untuk negara mana pun (pilih negara dulu).
- User biasa: cooldown menyebut TANGGAL (`next_change_at`);
  `already_moderator` ≠ `already_pending` pada pesan lamaran.
- Konsol moderasi: selain moderator/admin → "Bukan moderator negara ini" +
  tombol kembali (bukan "terjadi kesalahan").

### Test
- `test/moderation_texts_test.dart` — **15 unit test** (urutan pesan lamaran,
  unset≠profil, format tanggal cooldown).
- `room_media_gate_test` 20 → **24 assert** (unset/set oleh admin, admin tanpa
  negara tetap lolos gate media, user biasa ditolak 42501).

## 2026-10-27 (lanjutan 2) — Admin tidak perlu "melamar" jadi moderator

Laporan user: "di chatyuk admin ajukan jadi moderator gagal".

**Akar masalah (bukan bug):** akun admin punya `home_country = Armenia`,
sementara pesan publiknya 29 di Indonesia + 1 Hong Kong, **0 di Armenia** →
`apply_country_moderator` benar menolak dengan `not_enough_messages`
(need 50, have 0). Untuk user biasa aturan ini memang disengaja, tetapi
ADMIN tidak seharusnya diminta melamar — wewenang angkat sudah dimilikinya.

### `20261027124000_admin_self_appoint_moderator.sql` (APPLIED)
- `apply_country_moderator`: bila pemanggil admin → **langsung diangkat**
  (insert `country_moderators` + audit `moderator_actions`), tanpa syarat
  umur/pesan. User biasa tetap kena syarat ≥7 hari & ≥50 pesan.
- Respons penolakan menyertakan angka: `need`, `have`, dan (untuk
  `account_too_new`) `have_days`.

### Data live
- Akun `ChatYuk Admin` diangkat moderator **Armenia** (negara asal) dan
  **Indonesia** (negara aktif) agar konsolnya bisa langsung dipakai.

## 2026-10-27 (lanjutan) — Negara asal tidak bisa diakali + konsol moderasi hidup

Laporan user: (1) "dimoderasi negara asal masih bisa dirubah walau belum 30
hari", (2) "ajukan jadi moderator gagal", (3) "buka konsol moderasi gagal",
(4) "di user ko ada moderasi juga?".

### `20261027110000_guard_home_country.sql` (APPLIED)
- **Celah:** policy `profiles_update_own` hanya `auth.uid() = id` — tanpa
  guard kolom. Klien bisa `update profiles set home_country='XX'` langsung,
  melewati cooldown 30 hari (dan izin lintas negara).
- Trigger `guard_home_country_trg` (BEFORE UPDATE OF home_country,
  home_country_changed_at): perubahan hanya diterima bila datang dari RPC
  `set_home_country` (menandai `chatyuk.home_country_ok`) atau admin;
  selain itu **nilai lama dipertahankan** (tanpa error, agar update kolom
  lain tetap jalan). `home_country_changed_at` ikut dikunci → cooldown tidak
  bisa di-reset.
- `profile_public` kini mengembalikan `home_country` +
  `home_country_changed_at` **hanya untuk profil DIRI SENDIRI** (dibutuhkan
  UI; sebelumnya tidak pernah dikirim sehingga `_homeCountry` selalu null).

### Perbaikan klien
- `UserModel.homeCountry` + dibaca dari `profile_public`.
- `_moderationSection` mengisi `_homeCountry` dari profil → "Ajukan jadi
  moderator" & "Buka konsol" tidak lagi mengirim string kosong (dulu SELALU
  gagal karena `country_required` / toast hint).
- Pesan gagal lamaran kini spesifik: `account_too_new` (butuh 7 hari) dan
  `not_enough_messages` (butuh 50 pesan, dengan jumlah milik user).
- "Buka konsol moderasi" **disembunyikan** untuk user non-moderator/non-admin
  (`myModerationState` + `isRealAdmin`), subtitle negara asal menampilkan
  nilai aktif.

### Test
- `room_media_gate_test` 15 → **20 assert**: home_country tak bisa diubah via
  UPDATE langsung, cooldown tak bisa direset, RPC menolak <30 hari.
- Verifikasi manual (ROLLBACK di live): rpc1 ok, rpc2 ditolak `cooldown`,
  update langsung diabaikan, reset cooldown diabaikan, `profile_public` self
  mengembalikan `home_country`.

## 2026-10-27 — Menutup celah moderasi (Fase A+B)

Temuan audit: fitur moderasi belum berjalan penuh. Lima migrasi + perbaikan
klien di bawah ini menutupnya.

### `20261027100000_home_country_default.sql` (APPLIED)
- **Celah fatal:** `home_country` hanya diisi backfill sekali. User yang
  mendaftar SETELAH itu punya `home_country = NULL`, dan
  `can_send_room_media` MELEWATI cek izin lintas negara bila nilainya kosong
  → user baru bisa kirim media di room publik NEGARA MANA PUN.
- Trigger `profiles BEFORE INSERT` mengisi `home_country = country`; ditambah
  backfill idempoten. `home_country` tetap stabil (hanya `set_home_country`,
  maks 1×/30 hari).

### `20261027101000_media_type_include_sticker_file.sql` (APPLIED)
- `is_room_media_type` kini mencakup `sticker` dan `file`. Sebelumnya stiker
  (GIF/WebP/MP4) dan dokumen bisa dikirim tanpa trust gate, tanpa rate limit,
  dan tanpa klasifikasi NSFW.

### `20261027102000_moderation_review_console.sql` (APPLIED)
- Kolom `messages.needs_review` + indeks parsial: verdict NSFW `review`
  (0,50–0,75) tidak lagi diabaikan.
- RPC `flag_media_review(message_id)` — pengirim menandai pesannya sendiri.
- `moderator_console` & `admin_moderation_overview` kini mengembalikan
  `reviews`, dan laporan membawa `type`, `image_path`, `text`, `hidden`
  (moderator bisa MELIHAT media yang dilaporkan).
- RPC `admin_search_users(query)` — admin bisa mengangkat moderator di luar
  daftar kandidat.

### `20261027103000_moderation_thresholds_autohide.sql` (APPLIED)
- Ambang diturunkan (keputusan user): lamaran moderator **≥7 hari & ≥50
  pesan** (dari 30 hari & 100), kandidat angkatan **≥20 pesan** (dari 50).
- **Auto-hide hanya `porn`/`violence`.** Spam/penipuan/lainnya tetap masuk
  antrean moderator tetapi TIDAK menyembunyikan pesan (mencegah penyalahgunaan
  tombol lapor).

### `20261027104000_moderator_resolve_review.sql` (APPLIED)
- RPC `moderator_resolve_review(message_id, hide)` — setujui (`hide=false`,
  bersihkan flag) atau sembunyikan (`hide=true`), tercatat di
  `moderator_actions` (`approve_media`/`hide`).

### Perbaikan klien
- `room_chat_core.dart`: `_refreshMediaGate()` + `_loadMyModerationState()`
  dipindah keluar dari `_initPrivate()` → kini berlaku untuk SEMUA room
  (dulu global room tidak ter-gate saat dibuka & ikon "Moderasi" tak muncul).
- `chat_sticker_send_mixin` / `chat_file_send_mixin`: stiker & file
  (mime `image/*`/`video/*`) melewati `contentSafetyAllowsMedia`.
- `chat_outbox_mixin`: media yang diantre offline juga diklasifikasi saat
  flush (dulu bypass).
- `moderation_screen`: 4 tab (**Tinjauan**, Laporan, Izin, Lamaran) +
  thumbnail media, "Tampilkan lagi", dan pencarian user khusus admin.
- `admin_moderation_tab`: seksi "Tinjauan" lintas negara.

## 2026-10-27 — Admin lihat lintas negara + moderator boleh angkat rekan

Dua pertanyaan user: (1) "kalau ada yang lintas negara admin taunya dimana?",
(2) "kalau moderator pilih orangnya jadi moderator gimana?".

### `20261026200000_admin_moderation_overview.sql` (APPLIED)
- RPC `admin_moderation_overview()` — **khusus admin**, mengembalikan SEMUA
  yang menunggu tinjauan lintas negara: `permits` (permohonan izin kirim media
  lintas negara), `applications` (lamaran moderator), `reports` (pesan
  terlapor), masing-masing membawa `country`.
- Klien: tab admin baru **"Moderasi"** (`lib/screens/admin_moderation_tab.dart`)
  → daftar gabungan per negara; tap → buka konsol moderasi negara itu.

### `20261026201000_moderator_colleagues.sql` (APPLIED)
- `country_moderators.source` kini menerima nilai `'moderator'` (angkatan oleh
  moderator, bukan hanya admin).
- RPC `moderator_candidates(country)` — daftar kontributor (≥50 pesan di room
  publik negara itu), urut kontribusi, tanpa moderator yang sudah ada.
- RPC `moderator_set_colleague(country, uid, grant)` — guard: admin ATAU
  moderator negara tsb; **tidak bisa lintas negara**, **tidak bisa diri
  sendiri**; tercatat di `moderator_actions`.
- Klien: tombol "Angkat moderator" (ikon orang+) di AppBar konsol moderasi →
  bottom sheet kandidat → angkat.

**Uji (ROLLBACK):** kandidat terdeteksi (55 pesan → 1 kandidat); angkat
berhasil (`is_country_moderator=true`); percobaan lintas negara **DITOLAK**.
pgTAP `room_media_gate_test` 15/15.

## 2026-10-26 (lanjutan) — Izin lintas negara, laporan ber-alasan, NSFW, konsol moderator

Semua **SUDAH APPLY** via Management API (versi tercatat di
`supabase_migrations.schema_migrations`).

### 1. `20261026160000_country_send_permits.sql`
- Tabel `country_send_permits(uid, country, status, ...)` — satu baris per
  (user, negara), status `pending/approved/rejected/revoked`.
- RPC `request_country_permit`, `decide_country_permit` (moderator negara /
  admin), `revoke_country_permit` (melanggar).
- `can_send_room_media` DIPERLUAS: `home_country` beda dengan negara room →
  wajib izin `approved` (selain trust gate).
- **Uji ROLLBACK:** room negara sendiri = true; negara lain tanpa izin =
  false; dengan izin = true.

### 2. `20261026161000_room_media_gate_state.sql`
- RPC `room_media_gate_state(room)` → `{allowed, reason, room_country,
  home_country, permit_status, min_days, min_msgs, have_msgs}`. Dipakai klien
  untuk menampilkan alasan + tombol "Ajukan izin".

### 3. `20261026170000_report_reason_codes_autohide.sql`
- `reports` + `message_id`, `room_id`, `reason_code`
  (`porn/violence/spam/scam/other`), `status`, `actioned_by/at`;
  unique parsial `(reporter_id, message_id)`.
- RPC `report_room_message` → **≥3 pelapor berbeda** menyembunyikan pesan
  otomatis (`is_deleted=true`) + `admin_alerts`; `resolve_message_reports`
  untuk menandai selesai/abaikan.
- **Uji ROLLBACK:** 3 pelapor → `auto_hidden=true`, pesan ter-hide.

### 4. `20261026180000_moderator_console_rpc.sql`
- `moderator_console(country)` → daftar lamaran, permohonan izin, laporan
  terbuka, moderator aktif (guard moderator negara/admin).
- `moderator_uids(uids)` → badge perisai publik (hanya uid+country).
- `my_moderation_state()` → negara yang saya moderasi + lamaran pending.

### 5. `20261026190000_set_home_country.sql`
- RPC `set_home_country` — boleh diubah manual, **maks 1× / 30 hari**
  (mencegah ganti negara untuk mengakali izin).

### Klien
- `ChatService`: `checkContentSafety`, `roomMediaGateState`,
  `requestCountryPermit`, `moderatorConsole`, `decideModeratorApplication`,
  `decideCountryPermit`, `moderatorHideMessage`, `resolveMessageReports`,
  `applyCountryModerator`, `moderatorUids`, `myModerationState`,
  `setHomeCountry`.
- `room_chat_media_gate.dart`: gate tombol media + dialog "Ajukan izin".
- `contentSafetyAllowsMedia` hook di jalur kirim foto/video (room publik saja).
- `moderation_screen.dart`: konsol 3 tab (Laporan / Izin / Lamaran).
- `ModeratorBadgeForUid` + `moderatorUidsProvider` (badge perisai di bubble).
- Profil → "Moderasi": pilih negara asal, ajukan moderator, buka konsol.
- Dialog lapor kini ber-alasan (`porn/violence/spam/scam/other`) dan mengirim
  `message_id` (auto-hide server).
- Edge Function `content-safety`: klasifikasi via provider vision aktif
  (`ai_provider_config`), ambang `nsfw_reject_threshold=0.75` /
  `nsfw_review_threshold=0.50`; gagal → fail-open + `admin_alerts`.
  Helper murni di `_shared/content_safety.ts` + test Deno 6/6.

**Verifikasi:** `flutter analyze` 0/0/0; `flutter test` 2372 lulus;
`run_sql_tests` semua lolos; `check_migrations --all` OK.

## 2026-10-26 — Moderasi media room publik: trust gate, rate limit, moderator negara (SUDAH APPLY)

**Latar (permintaan user):** di global room ada yang mengirim foto/video porn.
Sebelumnya SIAPA PUN yang terdaftar bisa kirim media di room publik — tanpa
gate umur akun, tanpa rate limit, tanpa verifikasi konten, tanpa moderator.

**Aturan yang diterapkan (keputusan produk):**
- Room **privat/grup**: TIDAK berubah (bebas).
- Room **publik**: kirim media (image/video/video_once) wajib (1) umur akun
  >= `media_trust_min_days` (default 3 hari) DAN (2) >= `media_trust_min_msgs`
  (default 20) pesan **di room publik**. Moderator negara/admin bypass.
- Rate limit media: `media_rate_per_min` (3) & `media_rate_per_hour` (20)
  per user per room.
- Hanya MEDIA yang dibatasi; teks/voice/lokasi tetap bebas.
- Akun tidak dihukum (hanya tombol media ditahan sampai syarat terpenuhi).

**Migrasi:**
1. `20261026130000_country_moderators.sql` — `profiles.home_country` (negara
   asal STABIL, tidak ditimpa IP) + backfill dari `country`; tabel
   `country_moderators` (kolom `scope` disiapkan untuk naik ke per-room),
   `moderator_applications`, `moderator_actions` (audit) + RLS 3 tabel baru.
2. `20261026130500_country_moderator_rpcs.sql` — RPC `apply_country_moderator`
   (syarat >=30 hari & >=100 pesan room publik negara itu),
   `decide_moderator_application`, `admin_set_country_moderator`,
   `moderator_hide_message` (hide/unhide; TIDAK ada aksi blokir akun).
3. `20261026140000_room_media_trust_gate.sql` — kolom `app_settings`
   (media_trust_min_days/min_msgs, media_rate_per_min/hour,
   nsfw_reject_threshold, nsfw_review_threshold), fungsi
   `is_room_media_type`, `can_send_room_media(room text, uid)`,
   `room_media_rate_ok(room text, uid)`, dan trigger
   `enforce_room_media_gate_trg` (BEFORE INSERT pada `messages`).

**Penting:** `rooms.id` & `messages.room_id` bertipe **TEXT**
(mis. `'Hong_Kong_general'`), bukan uuid — sempat salah tipe saat uji dan
sudah diperbaiki.

**Verifikasi (transaksi ROLLBACK di live):** akun baru → `can_send_room_media`
false; akun lama + 20 pesan → true; room privat → true; rate limit 3 media →
ditolak. Pasca-apply: `trigger_gate=1`, 5 fungsi, 3 tabel, kolom
`home_country` ada. pgTAP `room_media_gate_test.sql` 11/11.

**SAFE:** semua aditif (kolom baru, tabel baru, fungsi baru, 1 trigger baru).
Tidak mengubah policy/RLS/kolom yang sudah ada; room privat & private chat
tidak terpengaruh.

## 2026-10-24 — refund_chat_point: anti-replay + jendela + kill-switch (SUDAH APPLY)

**Review `docs/REVIEW_2026-10-24.md` SEC-02 (P0).** Dua rancangan sempat dibuat
terpisah untuk bug yang sama (`20261024100000` oleh sesi lain, `20261024140000`
yang sempat live) — DIGABUNG menjadi satu: `20261024160000_refund_chat_point_hardened.sql`
(APPLIED via Management API, versi tercatat).

Celah yang ditutup: `refund_chat_point` (20260819000000) me-refund baris
`spend_chat` TERAKHIR berulang tanpa penanda → via REST
`/rest/v1/rpc/refund_chat_point` saldo YukCoin bisa naik tanpa batas
(kerugian finansial; top-up Play Billing jadi tak bernilai).

Proteksi sekarang (keempatnya terverifikasi ada di `pg_get_functiondef` live):
1. `points_enabled` kill-switch — bila poin nonaktif tidak ada debit, refund
   tidak menulis apa pun (hanya `wallet_sync_points`).
2. Jendela 10 menit — hanya kegagalan kirim yang wajar.
3. `metadata.refund_of` = id baris spend; spend yang sudah direfund dilewati.
4. `pg_advisory_xact_lock(user)` + UNIQUE INDEX parsial
   `coin_ledger_refund_once(user_id, refund_of)` → anti-race panggilan paralel.

**Uji (transaksi ROLLBACK, live):** refund 1×/2×/3× → saldo tetap `33` dan
baris `refund_of` tetap `1`. Kill-switch: saat `points_enabled=false` →
0 baris `spend_refund` baru. Data historis: 0 baris `spend_refund` sebelum
migrasi (aman untuk unique index).

**SAFE:** hanya `create or replace` body fungsi (bukan FROZEN) + 1 index baru;
kontrak RPC & grant tidak berubah.

**Catatan test:** `supabase/tests/refund_chat_point_test.sql` kini menyalakan
`points_enabled` di dalam transaksi (di-rollback) — tanpa itu guard
kill-switch menahannya dan 6 assert gagal. `points_test.sql` +4 assert
(penanda refund_of, kill-switch, jendela, refund 3× → 1 baris).

## 2026-10-22 (lanjutan 2) — Status blokir dua arah untuk klien

**Masalah:** trigger `enforce_chat_block` sudah menolak INSERT dua arah, TAPI
klien tidak bisa tahu dirinya diblokir: RLS `blocks` hanya mengizinkan SELECT
baris milik sendiri (`auth.uid() = blocker_id`) — benar untuk privasi, tapi
akibatnya user mengetik → bubble tampil optimistis → INSERT ditolak
(`blocked`, P0001) → pesan hilang tanpa penjelasan. Klien juga hanya mengenali
`42501`/`policy`, jadi penolakan blokir tampil sebagai "gagal kirim" generik.

**Perbaikan:**
1. Migrasi `20261022150000_chat_block_state.sql` — RPC `chat_block_state(p_other)`
   mengembalikan `{i_blocked_other, other_blocked_me, can_send}` (boolean saja,
   TANPA identitas → privasi tetap: kita tahu "tidak bisa kirim", bukan "siapa
   memblokir"). `security definer` read-only; EXECUTE hanya authenticated.
2. Klien: `ChatService.getChatBlockState()` + `chatProvider.chatBlockState()`;
   `sendPreCheck()` sekarang memeriksa DUA arah → composer menolak kirim dengan
   pesan `msgBlockedByOther` sebelum bubble optimistis dibuat.
3. `OfflineOutbox.isBlockedError()` mengenali `blocked`/`42501`/
   `insufficient_privilege`/RLS → snack yang benar bila penolakan tetap terjadi.
4. pgTAP `security_guards_test.sql` +2 assert (total 10/10) dan unit test
   `isBlockedError` (2 kasus positif, 3 negatif).

**Verifikasi live (ROLLBACK):** pemblokir ditolak (`blocked`), yang diblokir
ditolak (`blocked`); `chat_block_state` dari sisi B →
`{can_send:false, i_blocked_other:false, other_blocked_me:true}`.

## 2026-10-22 (lanjutan) — Tabrakan timestamp diperbaiki + blokir chat ditegakkan

### Anomali yang ditemukan & ditutup
`20261022010000` dipakai **DUA** file sekaligus (`secure_money_rpcs` dan
`private_chats_update_check`). `supabase_migrations.schema_migrations` hanya
bisa menyimpan satu baris per `version` → salah satu migrasi berisiko terlewat
dan `scripts/check_migrations.sh` menolak seluruh repo.

**Bukti live sebelum perbaikan:** guard `spend_yukcoin` ADA; policy
`private_chats_update` TANPA `WITH CHECK`; fungsi/trigger `enforce_chat_block`
TIDAK ADA.

### Tindakan
1. **Rename** `20261022010000_private_chats_update_check.sql` →
   `20261022010100_private_chats_update_check.sql` (+ penanda `-- SAFE:` pada
   baris `drop policy` & `create policy`, wajib oleh gate [6]).
2. **Apply** `20261022010100` → `private_chats_update` kini punya
   `with check (auth.uid() = ANY (participants))`. **SAFE:** hanya mengetatkan,
   aturan sama dengan `USING`; pin/mute/hide/read-receipt tetap jalan.
3. **Apply** `20261022000000_chat_block_enforcement.sql` (fungsi
   `enforce_chat_block()` + trigger `enforce_chat_block_trg` BEFORE INSERT pada
   `private_messages`). Sebelumnya blokir HANYA dicek klien → klien lain /
   REST langsung tetap bisa mengirim ke orang yang memblokirnya.
4. **Hapus** `supabase/migrations/points_v1.sql` — duplikat persis:
   9/9 fungsinya dibuat ulang di migrasi ber-timestamp (2–30 file per fungsi),
   tabel `point_events` sudah ada di `20260814090000_points_v1_baseline.sql`
   dan ada di live. Nama tanpa prefix timestamp membuat file ini **tidak pernah**
   di-push tooling mana pun.
5. **pgTAP baru** `supabase/tests/security_guards_test.sql` (8 assert):
   guard `auth.uid()` pada 4 RPC, `*_impl` tidak bisa dieksekusi
   `authenticated`, `private_chats_update` punya `WITH CHECK`, trigger blokir
   terpasang. Terdaftar di `scripts/run_sql_tests.sh` → ikut CI.

### Verifikasi
- Uji trigger di transaksi ROLLBACK: pesan dari pasangan TERBLOKIR ditolak
  (`blk=1`), pesan pasangan normal lolos (`lolos=1`).
- Pasca-apply: `trigger_blokir=1`, `with_check=true`.
- Versi tercatat: `20261022000000`, `20261022010100`.
- `scripts/check_migrations.sh --all` → **OK bersih** (sebelumnya DITOLAK).
- `scripts/run_sql_tests.sh` → semua lolos (security_guards 8/8).

## 2026-10-22 — Tutup kebocoran `app_shared_secret` + rotasi (SUDAH APPLY)

- **Migrasi** `20261022120000_app_settings_hide_shared_secret.sql` — APPLIED via
  Dashboard SQL Editor (token Management API di `.env` kedaluwarsa); versi
  tercatat di `supabase_migrations.schema_migrations`.
- **Celah:** `20260922130000` meng-`grant select` level TABEL `app_settings` →
  `app_shared_secret` terbaca anon via REST publishable key (HTTP 200).
  Dengan secret itu: push ke token/topik mana pun, `ai-reply` atas nama dummy,
  `email-worker`, `migrate-photos`, `outbox-worker`, `sticker-gc`.
- **Fix:** revoke SELECT tabel + grant dinamis semua kolom KECUALI
  `app_shared_secret`. Kolom BARU di `app_settings` wajib grant kolom sendiri.
- **Verifikasi live:** `has_column_privilege` secret = false (anon+auth),
  `latest_version` = true; pgTAP `app_settings_secret_test.sql` 3/3; probe anon
  `select=app_shared_secret` & `select=*` → 401, `select=latest_version` → OK.
- **Rotasi `APP_SHARED_SECRET`:** nilai baru dibuat di DB (`gen_random_bytes`),
  diterapkan ke **3 tempat yang WAJIB sama**: Edge secret `APP_SHARED_SECRET`,
  `app_settings.app_shared_secret`, `ai_internal_config.callback_secret`
  (dipakai `ai_reply_post` → `ai-reply`). Cocok via SHA-256 digest Dashboard.
  Gangguan push/AI ±04:33–07:09 UTC (Edge secret terlambat diganti); 07:10
  `outbox-worker` 200 `sent:4` (antrean terkirim). Baris staging dihapus.
- **Catatan:** `email-worker` 500 `RESEND_API_KEY belum diset` sudah ada
  sebelumnya (tidak terkait).

## 2026-10-22 — Kunci keamanan RPC uang & metadata (SUDAH APPLY)

- **Migrasi** `20261022010000_secure_money_rpcs.sql` — APPLIED via Management
  API (versi tercatat di `supabase_migrations.schema_migrations`).
- **Celah yang ditutup (audit 2026-10-21, diverifikasi live):**
  1. `spend_yukcoin(p_user, ...)` SECURITY DEFINER + EXECUTE `authenticated`,
     **tanpa** cek `auth.uid()` → siapa pun berakun bisa memanggil RPC dengan
     uid ORANG LAIN dan menguras saldo YukCoin korban (client memakainya untuk
     view-once & foto HD berbayar; saldo berasal dari top-up Play Billing).
     **CRITICAL** — 277 baris `coin_ledger`, 232 profil bersaldo.
  2. `charge_metered(p_caller, ...)` sama (tanpa cek pemilik). Pemanggil sah
     satu-satunya `call_billing_tick`, yang sudah mengisi `p_caller := auth.uid()`.
  3. `list_my_groups(p_uid)` / `list_my_global_rooms(p_uid)` menerima uid
     sembarang → bocor daftar grup/room privat user lain (MEDIUM).
- **Perbaikan:** guard `auth.uid()` pada keempat RPC (`service_role` dikecualikan
  karena `auth.uid()` NULL di sana). **Revoke sengaja TIDAK dipakai** untuk
  `charge_metered`: `call_billing_tick` dipanggil dari sesi user saat call
  berjalan — revoke akan mematikan penagihan call (regresi finansial arah
  sebaliknya).
- **Body fungsi = salinan PERSIS `pg_get_functiondef` live** + blok guard di
  awal body (diverifikasi programatik: 4/4 identik). `list_my_*` dipecah jadi
  `*_impl` (body asli, EXECUTE dicabut dari anon/authenticated) + wrapper
  publik ber-guard — nama yang dipanggil klien tidak berubah.
- **Uji negatif dijalankan (transaksi rollback sebelum apply):**
  `spend_yukcoin(uid_lain)` → `42501 Forbidden`; `list_my_groups(uid_lain)` →
  `42501`; `list_my_global_rooms(uid_lain)` → `42501`;
  `charge_metered(uid_lain)` → `42501`. Pemakaian sah (uid sendiri) lolos.
- **Verifikasi pasca-apply:** `pg_get_functiondef` keempat RPC memuat
  `auth.uid()`; `*_impl` tanpa guard dan `EXECUTE=False` untuk anon &
  authenticated.
- **SAFE:** hanya `create or replace` isi fungsi + 2 fungsi `_impl` baru;
  RLS policy, grant tabel, dan tabel bersama tidak disentuh.

## 2026-10-21 — Guard MIME bucket `chat-photos` diselaraskan (SUDAH APPLY)

- **Migrasi** `20261021030000_align_chat_photos_guard_mime.sql` — APPLIED via
  Management API. **Akar masalah sebenarnya** dari penolakan upload
  stiker/dokumen: trigger lama `trg_chat_photos_guard` →
  `public.chat_photos_guard()` hanya mengizinkan jpeg/png/webp + audio
  terbatas dan melempar `check_violation` (23514). Jadi — terlepas dari
  `allowed_mime_types` bucket — `.tgs` (`application/gzip`), `.gif`, PDF/DOCX/
  XLSX/PPTX/ZIP/TXT, dan `video/webm` SELALU gagal. Bukti data:
  `storage.objects` bucket `chat-photos` folder `stickers` hanya berisi
  video/mp4 dan folder `chat` hanya video — tidak ada stiker gambar/`.tgs`
  maupun dokumen sama sekali.
- **Perbaikan:** guard kini membaca `storage.buckets.allowed_mime_types`
  (single source of truth), MIME kosong ditolak, batas ukuran video 50 MB /
  file lain 20 MB (≤ `file_size_limit`).
- **Verifikasi (curl ke Storage REST, tanpa sesi):** `application/gzip`,
  `image/gif`, `application/pdf`, `video/webm` → lolos guard (berhenti di RLS
  403 seperti seharusnya); `application/x-msdownload` → 415 dari allowlist.
- **SAFE:** hanya `create or replace` fungsi trigger bucket `chat-photos`;
  RLS policy, grant, dan tabel bersama tidak disentuh.

## 2026-10-21 — Batas bucket storage (MIME allowlist) (SUDAH APPLY)

- **Migrasi** `20261021010000_storage_bucket_limits.sql` — metadata bucket
  `chat-photos`: `file_size_limit` 50 MiB + `allowed_mime_types`.
  **SUDAH di-apply** via Management API (versi `20261021010000` tercatat).
  Live: `file_size_limit = 52428800`, `allowed_mime_types` 25 entri.
- **Wajib sebelum apply** (revisi reviewer 2026-10-21): allowlist WAJIB memuat
  `image/svg+xml`, `image/svg+xml-compressed`, `application/gzip` (stiker
  Telegram `.tgs` — klien mengirim content-type hasil tebakan ekstensi path,
  `.tgs` → `image/svg+xml`, BUKAN `application/octet-stream`) dan `audio/m4a`.
  Tanpa itu upload stiker/voice ditolak 400.
- **Klien ikut diperbaiki:** `StoragePhotoService.uploadSticker` kini kirim
  `contentType` eksplisit per ekstensi (`stickerMime`), `uploadStoryImage` /
  `uploadPostImage` kirim `_detectImageFormat().mime`, dan `uploadVoice`
  memakai `audio/mp4` (bukan `audio/m4a` yang tak terdaftar di daftar media
  type Supabase Storage).

## 2026-10-21 — DIBATALKAN: fix scrub_reply_snapshot_cast

- File `20261021020000_fix_scrub_reply_snapshot_cast.sql` **DIBATALKAN/
  dihapus** sebelum apply. Premisnya salah: ia mengubah
  `scrub_reply_snapshot_private` kembali ke `new.id` (bigint), padahal
  `private_messages.replied_to_id` bertipe **text** di live dan fungsi live
  SUDAH memakai `new.id::text` (perbaikan `20260923160000`). Bila di-apply →
  `operator does not exist: bigint = text` (42883) dan SEMUA soft-delete
  pesan gagal — persis insiden yang ingin dicegah.
- **Verifikasi live (Management API, 2026-10-21):**
  `messages.replied_to_id` = bigint, `private_messages.replied_to_id` = text;
  `scrub_reply_snapshot_private` = `pm.replied_to_id = new.id::text`,
  `scrub_reply_snapshot_room` = `m.replied_to_id = new.id`. Konsisten dengan
  pgTAP `supabase/tests/delete_message_test.sql`.
- **Catatan:** entri log `20260923160000` (DITERAPKAN & TERVERIFIKASI LIVE)
  tetap benar; klaim "kolom bigint" pada migrasi yang dibatalkan adalah salah.

## 2026-10-20 — Metadata kutipan balasan (replied_to_meta) (SUDAH APPLY via Management API)

- **Migrasi** `20261020120000_reply_meta.sql` — ADITIF: kolom
  `replied_to_meta jsonb` di `private_messages` DAN `messages` (`add column if
  not exists` — idempotent, baris lama NULL → kutipan jatuh ke mode teks).
  Menyimpan payload JSON ringkas kutipan (tipe/id/dimensi/path) untuk kutipan
  media (foto/video/lokasi/stiker) — thumbnail tetap dari cache lokal.
- **Insiden:** migrasi ini sempat BELUM di-apply padahal klien baru (pull
  2026-10-20) sudah SELECT kolomnya → `PostgrestException 42703 column
  private_messages.replied_to_meta does not exist` → SEMUA fetch pesan gagal
  (chat tampak kosong di build baru). Terdeteksi dari log HP (build profil).
- **Verifikasi:** kolom terlihat di `information_schema.columns` untuk kedua
  tabel; log HP setelah apply: fetch sukses `server=135ms n=100`; versi
  tercatat di `supabase_migrations.schema_migrations`.
- **Catatan:** tidak ada fungsi FROZEN yang disentuh; snapshot tidak berubah.

## 2026-10-18 — Label media last_message & notif private (SUDAH APPLY via Management API)

- **Migrasi** `20261018140000_last_message_media_labels.sql` (FROZEN:
  `handle_new_private_message`, `notify_private_message`; basis = versi live,
  diverifikasi identik snapshot). HANYA menambah cabang: last_message stiker
  `[Stiker]`, voice `[Pesan suara]`, video tanpa caption `[Video]`; body notif
  stiker `[Stiker]`, lokasi `[Lokasi]` (dulu JSON mentah).
- **Backfill** `20261018140100_backfill_last_message_media.sql`: 5 chat yang
  last_message-nya terlanjur kosong (3 voice, 2 stiker) diberi label; waktu/
  unread/urutan tidak disentuh.
- **Snapshot:** hanya 2 blok fungsi diperbarui manual dari `pg_get_functiondef`
  live — `snapshot_functions.sh` gagal mengambil 16/30 fungsi (rate limit
  keychain token) sehingga hasilnya TIDAK dipakai. Diff = tambahan saja.
- **Verifikasi:** pgTAP `last_message_media_labels_test.sql` 7/7 (sebelum apply
  gagal di label baru); `check_migrations.sh` OK.
- **Catatan:** stiker yang DIHAPUS sebagai pesan terakhir tetap membuat
  last_message kosong (perilaku alur hapus, di luar cakupan).

## 2026-10-18 — KIRIM KONTAK: private, grup & global room (SUDAH APPLY via Management API)

- **Migrasi** `20261018170000_contact_message.sql` — ADITIF: `'contact'` di
  `private_messages_type_check` **dan** `messages_type_check` (basis = daftar
  LIVE 15 tipe, jadi tipe lama utuh) + kolom `contact jsonb` di kedua tabel.
  Dua payload: `{"t":"user","u":uid}` (ChatYuk — **hanya id**, penerima
  resolve nama sendiri; privasi terjaga) dan
  `{"t":"phone","n":nama,"p":[nomor…]}` (buku kontak HP). `text` = '📇 <nama>'
  → notif/last_message lewat cabang teks (fungsi FROZEN tak disentuh).
- **Verifikasi:** pgTAP `contact_message_test.sql` 4/4 (private: payload user
  uid-saja & phone nama+2 nomor tersimpan, tipe tak dikenal ditolak; room:
  payload tersimpan). Versi tercatat di `supabase_migrations.schema_migrations`.
  Snapshot fungsi FROZEN tidak berubah (diff = baris Timestamp saja).
- **Klien:** model `ChatContact` + `MessageModel.contact` (ikut cache lokal →
  frame-1), `sendPrivateMessage/sendRoomMessage(contact:)`, pemilih 2 tab
  (**ChatYuk**: teman ∪ pernah chat; **Kontak HP**: `fast_contacts` +
  `READ_CONTACTS`), kartu `ContactBubble` (ChatYuk: Chat/Lihat profil; HP:
  Salin/WhatsApp/Telepon), chip panel lampiran **di samping Lokasi**.
- **Rilis:** `READ_CONTACTS` masuk AndroidManifest + plugin `fast_contacts`
  (butuh deklarasi izin Contacts di Play Console sebelum submit AAB).

## 2026-10-18 — HARDENING fungsi poll: cabut EXECUTE dari PUBLIC/anon (SUDAH APPLY via Management API)

- **Migrasi** `20261018160000_poll_fn_hardening.sql`. Temuan saat cek ulang
  fitur poll: `revoke execute ... from anon` (di 20261018130000 & 20261018150000)
  TIDAK menghapus grant implisit **PUBLIC** dari Postgres → verifikasi
  `has_function_privilege('anon', …)` = **true** untuk `get_poll_results`,
  `vote_poll`, `get_room_poll_results`, `vote_room_poll`, padahal RPC lain
  (`pin_private_chat`, `mark_chat_read`, `mute_room`) = false.
- **Fix:** `revoke execute ... from public, anon` + `grant execute ... to
  authenticated` untuk keempat fungsi.
- **Verifikasi:** anon=false, public=false, authenticated=true (keempat).
  pgTAP `chat_poll_test.sql` 9/9 & `room_poll_test.sql` 9/9 + seluruh SQL
  suite tetap lolos (jalur authenticated tak terpengaruh).

## 2026-10-18 — POLLING grup & global room (SUDAH APPLY via Management API)

- **Migrasi** `20261018150000_room_poll.sql` — paritas dengan poll private
  (`20261018130000_chat_poll.sql`). ADITIF: `messages_type_check` + `'poll'`
  (basis = constraint LIVE, jadi 14 tipe lama TIDAK hilang), kolom
  `messages.poll jsonb` (definisi poll ikut baris pesan → bubble lengkap dari
  cache lokal di frame pertama), tabel BARU `room_poll_votes` (RLS baca =
  aturan `messages_select`: room publik bebas, room privat hanya anggota,
  admin selalu; tulis HANYA via RPC), realtime publication, RPC
  `get_room_poll_results(bigint[])` + `vote_room_poll(bigint, int[])`.
- **Verifikasi:** pgTAP `room_poll_test.sql` 9/9 (vote, ganti pilihan,
  pilih-satu menolak >1 opsi, opsi di luar rentang ditolak, tarik suara,
  non-anggota room privat tak bisa vote/hasil, authenticated tak punya INSERT
  langsung). Versi tercatat di `supabase_migrations.schema_migrations`.
- **Snapshot:** `scripts/snapshot_functions.sh` → 30 fungsi FROZEN, diff hanya
  baris Timestamp (fungsi BARU bukan FROZEN → tidak masuk snapshot).
- **Klien:** `PollService.resultsRoom/voteRoom/subscribeRoom`,
  `PollController.room()` + `roomPollProvider` (controller TERPISAH dari poll
  private karena id pesan antar tabel bisa sama), `PollBubble(roomId:)`,
  bubble poll di `RoomMessageBubble`, tombol poll di composer grup/global room,
  `sendRoomMessage(poll:)`.

## 2026-10-18 — POLLING private chat (SUDAH APPLY via Management API)

- **Migrasi** `20261018130000_chat_poll.sql`: type `'poll'` di
  `private_messages_type_check`; kolom `private_messages.poll jsonb`; tabel
  `chat_poll_votes` (RLS select peserta; tulis hanya via RPC; realtime +
  replica identity full); RPC `get_poll_results(bigint[])` & `vote_poll(bigint,int[])`.
- Fungsi notif/last_message FROZEN tidak disentuh (`text`='📊 <tanya>').
- **Verifikasi:** pgTAP `chat_poll_test.sql` 9/9; `smoke_anon_register.sh` OK;
  `check_migrations.sh` OK. (`email_marketing_test.sql` gagal sejak lama —
  memanggil `supabase_tests.finish_tests()` yang tidak ada; tak terkait.)

## 2026-10-17 — Pesan tipe FILE/dokumen (SUDAH APPLY via Management API)

- **Migrasi** `20261017180000_file_message_type.sql`: tambah `'file'` ke
  `private_messages_type_check` & `messages_type_check` (aditif, basis =
  constraint live). Tanpa kolom baru: `text` = nama file, `image_path` =
  `chat/<chatId>/<stamp>_f.<ext>`, `duration_ms` = ukuran (byte).
- Fungsi notif/last_message (FROZEN) TIDAK disentuh — cabang `else new.text`
  sudah menampilkan nama file.
- **Verifikasi:** kedua constraint memuat `'file'`; versi tercatat di
  `supabase_migrations.schema_migrations`; `check_migrations.sh` OK.


## 2026-10-06 — call_billing_tick hormati master toggle koin (SUDAH APPLY via Management API)

- **Masalah:** banner `X coin/menit` + dialog "koin kurang" tetap muncul saat
  call walau admin mematikan master toggle koin (`points_enabled=false`).
  Client cuma cek flag publish `call_billing`, dan server `call_billing_tick`
  juga cuma cek flag publish → tick tetap memotong saldo diam-diam.
- **Client (5 file):** `ensureEnoughForCall` return true saat koin OFF;
  gate call jadi `pp.enabled && pp.callBillingPublished` + `setBillingPerMinute`
  0 saat OFF (`private_chat`, `user_info`, `call_history _redial` yang selama
  ini tanpa gate); banner `CallScreen` sembunyi saat `PointsProvider.enabled`
  false. Overlay video dalam chat & sisi penerima memang tak ada UI koin.
- **Migrasi** `20261006200000_call_billing_master_toggle.sql`: rewrite
  `call_billing_tick` (basis `20261005140000`) + guard `points_enabled` PALING
  ATAS → return gratis (`can_continue=true`, `per_minute=0`). Bukan FROZEN.
- **STATUS: SUDAH APPLY** via Management API. Verifikasi: `prosrc` memuat
  guard (pos 508); pgTAP `call_billing_toggle_test.sql` 3/3 + `call_test.sql`
  20/20 hijau. `check_migrations.sh` bersih untuk file ini (2 FAIL
  pre-existing `story_slides` tak terkait).

## 2026-10-06 — get_online_users: optimasi perf (SUDAH APPLY via Management API)

- **Minta user:** fix lag RPC `get_online_users` (~1.46s terukur di HP).
- **Akar:** RPC memanggil `public.privacy_can_view()` **4x PER USER**
  (photo/seen/presence/about) → limit 200 = 800 eksekusi fungsi multi-SELECT
  per request. Tiap call menyentuh app_settings/private_chats/room_members/
  profiles/profile_privacy_exclusions/_privacy_are_friends.
- **Migrasi** `20261006090000_get_online_users_perf.sql`: evaluasi privasi 4
  field **sekali per user** (CTE: candidates→chat_partners/room_mates/excl/
  friends→resolved→flags), TANPA 4x function call. Semantik SAMA dengan
  `privacy_can_view` versi 20261006030000 (presence/last_seen/profile_photo/
  about + bypass admin + mitra chat/room untuk foto). Signature tak berubah.
- **STATUS: SUDAH APPLY** (2026-10-06) via Management API
  `POST /v1/projects/{ref}/database/query`. Verifikasi: `pg_proc.prosrc`
  memuat CTE (bukan 4x privacy_can_view).
- **Hasil terukur (EXPLAIN ANALYZE server):** `get_online_users(null,200)`
  **12ms** (dulu ~1460ms → **~122x lebih cepat**). `count_room_presence_by_country`
  3.8ms, `cleanup_room_presence` 1.8ms. Compute tetap **Micro** (1GB, 2 core —
  cukup; server-side cepat, latensi 1.46s lama = network/HP, bukan DB).
- **Client (SUDAH, commit 2a3e578):** defer RPC berat saat buka layar
  (get_online_users 400ms, count_room_presence 600ms, cleanup_room_presence
  2s) → frame pertama bersih.

## 2026-10-05 — Preview kartu ikut teks hasil edit (private chat)

- **Migrasi** `20261006130000_private_last_message_on_edit.sql`: trigger
  baru `trg_private_msg_edit` sinkronkan `private_chats.last_message` saat
  teks pesan terakhir diedit. Applied via Management API + tercatat di
  `schema_migrations`. `check_migrations` OK.

## 2026-10-05 — Pesan room user terhapus tampil "Pesan dihapus"

- **Migrasi** `20261006120000_room_deleted_user_placeholder.sql`:
  `delete_my_account` soft-delete pesan room (`is_deleted=true`, bukan
  hard-delete); `purge_onboarding_placeholders` ikut soft-delete per-user;
  backfill 56 pesan yatim. Applied via Management API + tercatat di
  `schema_migrations`. Test pgTAP `delete_account_test.sql` 6/6.

## 2026-10-05 — Daftar user admin: flag Fake GPS vs GPS asli

- **Minta user:** di "Per User" admin, tahu MANA Fake GPS vs GPS asli;
  tanggal daftar per user (WIB) — yang terakhir sudah ada di sheet
  registrasi (`formatDateTimeWib` + relatif) & kartu Per User (`Terdaftar:`),
  jadi tidak diubah.
- **Migrasi** `20261006060000_admin_users_gps_flag.sql`:
  `admin_stats_users_page` (BUKAN frozen) kirim tambahan `lat_gps`,
  `lon_gps`, `gps_updated_at`, `location_mocked`, `location_mock_reason`.
  Body lain identik. Applied via Management API + tercatat di
  `schema_migrations`.
- **Client:** widget baru `GpsBadge` (Fake GPS merah + reason / GPS asli
  hijau / Hanya IP) di `DeviceCard` + kartu user tanpa device; merge
  `mergeUsersWithDevices` meneruskan field GPS; string bilingual di
  `strings_admin.dart`.
- **Test:** `gps_badge_test.dart` (4) + kasus merge GPS di
  `admin_grouping_test.dart`. `check_migrations` OK; boundary OK
  (pelanggaran hanya pre-existing).

## 2026-10-05 — Call 1:1/video: hardening RLS + gerbang billing lebih awal

- **Review subsistem call** (1:1 & video call). Temuan + fix server-side:
  - `20261005130000_calls_update_with_check.sql`: policy `calls_update` dulu
    tanpa `WITH CHECK` → peserta berpotensi meng-UPDATE kolom identitas
    (caller_id/callee_id). FIX: pisahkan `USING` (baris lama) dari
    `WITH CHECK` (baris baru tetap peserta, identitas tak berubah). Tidak
    mengubah izin update status/answered_at/ended_at/last_seen_at.
  - `20261005140000_call_billing_gate_first.sql`: `call_billing_tick` dulu
    membaca `app_settings` (unit_cost/cut_pct) SEBELUM gate
    `feature_enabled_for('call_billing')`. FIX: gate dipindah ke paling atas
    → jalur OFF nol query config. Kontrak return tidak berubah.
- **Client** (`lib/services/call_service.dart` + baru
  `lib/core/call/signal_route.dart`): awalnya ICE candidate dikirim EPHEMERAL
  via Realtime Broadcast. **DI-REVERT** (uji 2-device): candidate broadcast
  TIDAK sampai ke peer → ICE tunggu 15 dtk → call "menghubungkan lama". Kini
  SEMUA sinyal kembali lewat DB `call_signals` (postgres_changes) — jalur lama
  yang terbukti cepat. Kode broadcast dipertahankan (dorman) + didokumentasikan
  (`docs/PERFORMANCE.md §27c`).
- **Test:** `test/signal_route_test.dart` (routing tipe, envelope, dedup,
  defense broadcast ditolak saat ephemeral OFF). Regresi call lama OK.
- **Verifikasi device (2 HP):** panggil audio + video → connect cepat kembali
  (< 5 dtk) setelah revert.

## 2026-10-05 — Fake GPS lanjutan (shared/static/emulator) + badge sumber IP/GPS

- **Temuan (audit Kartika/live):** 77/348 user ber-GPS di 19 koordinat dipakai
  >1 orang. Cluster besar (-6.9097,107.5649)=35 akun & (37.4220,-122.0841)=10
  akun (default Android Emulator) — LOLOS deteksi lama.
- **Migrasi** `20261005040000_fake_gps_shared_coord.sql`: `update_my_location`
  +heuristik `static_coord`, `known_emulator`, `shared_coord` (khusus gps);
  + helper `admin_flag_shared_locations(p_min_users)`.
- **Backfill:** 44 user ter-flag `shared_coord` (mocked 2→46). Kartika (unik)
  aman.
- **A (penyebab "GPS beda"):** profil `lat_gps` = GPS asli, tapi baris history
  terbaru bisa `ip` (perkiraan kasar). UI admin kini **chip sumber GPS/IP** di
  riwayat lokasi + reason mock diperjelas → tidak lagi tertukar.
- **Verifikasi:** `check_migrations` OK; pgTAP schema_sync 58/58 (+3);
  `flutter analyze` 0/0 (kecuali 1 warning TikTok paralel).

## 2026-10-06 — Putus teman (unfollow) benar-benar memutus (fix stale)

- **Temuan:** 2 definisi teman — `_privacy_are_friends` (mutual follows;
  privasi/Top Aktif) vs `_are_friends` (friend_requests accepted; story).
  `unfollow_user` dulu hanya hapus `follows` → `_are_friends` tetap true →
  story mantan teman stale. (Top Aktif sudah benar.)
- **Fix** `20261006070000`: `unfollow_user` juga hapus `friend_requests`
  accepted/pending kedua arah → konsisten.
- **Verifikasi:** privacy_test 20/20 (+3: sebelum/sesudah unfollow).
- **Efek ke Top Aktif:** `friends`/`friends_except` otomatis berhenti lihat
  setelah unfollow (sudah benar, kini story ikut konsisten).

## 2026-10-06 — Privasi "Top Aktif" (leaderboard visibility)

- **Kolom** `profiles.leaderboard_visibility` (default everyone) + CHECK
  `profile_privacy_exclusions.field` +'leaderboard'.
- **RPC** `update_privacy_settings`(+p_leaderboard, drop overload 6-arg),
  `my_privacy_settings`, `privacy_can_view` (+mapping leaderboard),
  `replace_privacy_exclusions` (+leaderboard), `activity_leaderboard`
  (filter privacy_can_view(id,'leaderboard',viewer) di entries & me).
- **Admin:** `admin_stats_compute.privacy_users` +field leaderboard.
- **App:** PrivacySettings.leaderboard + service/provider + tile "Top Aktif"
  di layar Privasi (6 opsi sama) + strings bilingual.
- Verifikasi: privacy_only 22/22; semua SQL test lolos; analyze 0/0.

## 2026-10-05 — Tanggal register di list Perangkat + fix gate onboarding

- **Temuan (user Anon6A/Anon0DB):** trigger `handle_new_user_profile` membuat
  profil placeholder 'AnonXXXXXXXX' + `needs_onboarding=true` untuk SETIAP
  auth.users. Jika user register (email/OTP) lalu TUTUP app sebelum memilih
  nama, nickname placeholder TETAP. Gate lama hanya menahan ANON → 18 user
  registered masih ber-nickname 'AnonXXXX' (136 needs_onboarding).
- **Fix (app.dart):** gate menahan SEMUA user dgn `needs_onboarding=true`
  (kecuali dummy) → dipaksa ke EntryScreen pilih nama. +2 test gate.
- **Migrasi** `20261005090000_admin_stats_users_created_at.sql`:
  `admin_stats_users_page` +field `created_at` (tanggal register).
- **App:** `formatDateWib()` → kartu Perangkat/Per User tampil
  "Terdaftar: 30 Sep 2026" (WIB).
- **Bonus:** test `get_online_users about_visibility` dikendurkan ke
  `privacy_can_view` (impl live pakai `about_ok`, bukan `about_visibility`).
- Verifikasi: check_migrations OK; schema_sync 59/59; auth_gate 15/15.

## 2026-10-05 — Tanpa auto-anon + placeholder registered bukan "Anon"

- **Akar:** `AuthProvider._init` auto `signInAnonymously()` saat tanpa sesi →
  tiap buka app membuat user anon + profil 'AnonXXXX'. Trigger membuat
  placeholder 'AnonXXXX' untuk SEMUA (termasuk registered).
- **Fix app (auth_provider.dart):** `_init` TIDAK auto signInAnonymously →
  tanpa sesi langsung EntryScreen; user HANYA dibuat saat user menekan
  "Mulai" (registerProfile bikin anon + profil dgn nickname PILIHAN user).
- **Fix DB (20261005110000):** trigger `handle_new_user_profile` — registered
  (email) dapat 'Pengguna'+6hex (bukan 'AnonXXXX'); anon tetap 'Anon'+8hex.
- **20261005120000:** retensi arsip `deleted_users` >90 hari + cron 04:30
  (jobid 37) — arsip tidak tumbuh abadi lagi.
- **Verifikasi:** schema_sync 62/62; auth tests 15/15 + 41/41; trigger diuji
  live (registered→Pengguna, anon→Anon).

## 2026-10-05 — Cegah user stuck "AnonXXXXXXXX" (guard trigger + gate)

- **Trigger** `trg_enforce_onboarding_placeholder`: nickname placeholder
  `^Anon[0-9A-F]{8}$` WAJIB needs_onboarding=true (cegah recurrence).
  Dipaksa `true` walau ada jalur men-set false. Backfill diterapkan.
- **Gate** app.dart menahan SEMUA needs_onboarding (registered juga).
- Verifikasi: schema_sync 60/60.

## 2026-10-05 — Leaderboard "Top Aktif" (keaktifan: pesan + reaksi)

- **Migrasi** `20261005030000_activity_leaderboard.sql`:
  `activity_leaderboard(p_scope, p_limit, p_offset)` → jsonb
  `{scope, entries[], me}`. Skor = pesan private + pesan room + reaksi
  (`weekly`=7 hari, `alltime`=seumur hidup). Kecualikan dummy + excluded;
  hanya user nyata (registered atau status <> offline) — pola
  `points_leaderboard`. Entri + `msg_count` & `reaction_count`.
- **App:** `PointsService.activityLeaderboard` + passthrough provider;
  `ActivityLeaderboardScreen` (tab Mingguan/Sepanjang Masa, kartu rank +
  sub-label "N pesan · N reaksi", bar peringkat sendiri).
- **Ikon:** `Icons.emoji_events_rounded` di `leading` AppBar menu Online,
  tepat di samping ikon Search (`leadingWidth: 96`). Semua user boleh lihat.
- **Catatan:** `profiles.login_streak`/`last_login_date` TIDAK dipakai
  (cuma 3 baris — fitur daily-login mati). "Sering online" diproksikan via
  keaktifan chat (label "Top Aktif", bukan klaim presence).
- **Verifikasi:** `check_migrations` OK; pgTAP `schema_sync` 55/55;
  `points_service_io_test` +2 hijau; `flutter analyze` 0/0.

## 2026-10-05 — Laporan admin: nickname pelapor & terlapor + fix filter bulan

- **Migrasi** `20261005020000_admin_reported_users_nickname.sql`:
  `admin_stats_compute()` blok `reported_users` diperkaya → `reported_nickname`,
  `reported_registered`, `reporters` [{id, nickname}]. Admin kini tahu SIAPA
  yang dilaporkan (dulu cuma uid terpotong). Non-FROZEN, sisa fungsi persis
  live.
- **App:** `ReportedUsersCard` tampilkan nama terlapor + "Dilaporkan oleh: …"
  (pelapor ≠ terlapor jelas).
- **Fix filter bulan** (`registrationschart_card`): dropdown bulan 12 terakhir
  diurutkan eksplisit descending (terbaru di atas) via `_monthOptions()`.
- Verifikasi: `check_migrations` OK; analyze 0/0; admin tests hijau.

## 2026-10-05 — Insight registrasi CEO (panel admin Ringkasan)

**Alasan:** kartu "Registrasi Email" hanya menampilkan bar per-hari satu bulan.
Untuk keputusan CEO, dibutuhkan KPI + tren + konteks akuisisi.

- **Migrasi** `20261005010000_admin_registrations_insights.sql`:
  - `admin_registration_kpis()` → total terdaftar, total anon, konversi (%),
    baru bulan ini, baru bulan lalu, MoM %, baru hari ini, rata-rata/hari,
    hari terbaik (+jumlahnya), aktif hari ini. SEMUA mengecualikan dummy +
    excluded uid (user nyata; beda dari `admin_stats_compute`).
  - `admin_registrations_monthly(p_months)` → total per bulan (LEFT JOIN
    `generate_series` supaya bulan kosong tidak bolong) untuk tren 12 bulan.
- **App:** `AdminService.fetchRegistrationKpis/fetchRegistrationsMonthly`,
  `AdminProvider.fetchRegistrationInsights` (cache 1×), kartu
  `registrationschart_card.dart` dirombak: grid KPI (6 tile) + tren 12 bulan
  (CustomPaint, highlight bulan terakhir + delta chip vs bulan lalu) + bar
  harian (tandai hari terbaik) + tombol "Lihat daftar".
- **Konsistensi KPI:** dummies (12 akun) & excluded uid dibuang → angka CEO
  tidak menghitung akun dummy. MoM % hanya ditampilkan bila bulan lalu ≥ 10
  (hindari +22900% saat bulan lalu = 1).
- **Verifikasi:** `check_migrations` OK; pgTAP `schema_sync_test` 52/52;
  `admin_service_test` +2 test hijau; `flutter analyze` 0/0.

### Rename timestamp (AGENTS.md §2) — drift WIP

Dua migrasi untracked bentrok timestamp (checker menolak):
- `20261001000000_admin_chats_participant_genders.sql` → `20261001005000_...`
  (bentrok `coin_engine_config`).
- `20261001010000_admin_app_versions_sort_newest.sql` → `20261001015000_...`
  (bentrok `disable_free_points`).

## 2026-10-04 — Gate onboarding (`needs_onboarding`) + fix test tertinggal

**Alasan:** gate "wajib isi username" dulu (`nicknameSet` / migrasi
`20261002070000/080000`) di-**revert** di commit `5eb347e`. Pendekatan baru
memakai kolom **`needs_onboarding`** (dibuat trigger `handle_new_user_profile`).

- **Migrasi** `20261004060000_needs_onboarding_flag.sql` (kolom
  `needs_onboarding boolean not null default true`) + `20261004070000_reapply_trigger_with_onboarding.sql`.
- **App:** `UserModel.needsOnboarding` (fromMap/toMap/copyWith), gerbang root
  `app.dart`, `auth_provider.dart`, `auth_service_profile.dart`.
- **Fix:** `test/models_test.dart` masih menguji `nicknameSet` (API yang sudah
  di-revert) → **7 `flutter analyze` error**. Diganti 6 test `needsOnboarding`
  (key absen → false, true/false eksplisit, non-bool → false, toMap, copyWith).
  `flutter analyze` kembali 0 error/0 warning.

### Rename timestamp (AGENTS.md §2)

`20261001000000_admin_chats_participant_genders.sql` **bentrok** dengan
`20261001000000_coin_engine_config.sql` (dua file, prefix sama → apply tidak
deterministik, `check_migrations` menolak). Di-rename →
**`20261001005000_admin_chats_participant_genders.sql`** (slot bebas, urut
setelah coin_engine_config). Fungsi `admin_list_chats_page` sudah live di prod
(participant_genders terpasang).

## 2026-10-04 — Noise filter `ai_reply_log`

**Alasan (audit):** tabel `ai_reply_log` (retensi 7 hari) mentok ~11.4k baris /
~7 MB, padahal hanya ~39 baris `replied` per 7 hari. **84% isinya DUA decision
tak informatif:** `skipped:dummy_disabled` (5.401) + `skipped:ai_disabled`
(4.195) = "dummy penerima AI-off", yang sinyalnya sudah ada di
`dummy_accounts.ai_enabled`. Noise ini menenggelamkan kasus menarik.

- **Migrasi** `20261004080000_ai_reply_log_noise_filter.sql`:
  - `create or replace public.ai_log_reply(...)` (signature identik) + denylist:
    `if p_decision in ('skipped:dummy_disabled','skipped:ai_disabled') then return;`.
  - Semua call-site SQL (`ai_reply_enqueue`/`ai_reply_post` — FROZEN) ikut
    terfilter otomatis karena lewat helper pusat. **Fungsi FROZEN TIDAK
    disentuh** → tak butuh header `-- menyentuh:` / snapshot refresh.
  - Apply via Management API (3 statement: create fn, revoke, grant). SUDAH
    TERAPPLIED di `fohcucyyejdryryoxitm`.
- **Edge:** `supabase/functions/ai-reply/index.ts` — denylist setara di shadow
  `json()` (jalur insert `edge`). **Deploy v196 ACTIVE** via
  `supabase functions deploy ai-reply --use-api`.
- **Cleanup:** hapus 9.596 baris noise lama → 11.417 → 1.821 baris (84% turun);
  `VACUUM public.ai_reply_log` → dead tuples 0 (ruang dipakai-ulang insert
  berikutnya; file tetap ~7 MB, tidak akan tumbuh lagi).
- **Verifikasi live:** definisi `ai_log_reply` memuat filter; uji terarah —
  `skipped:dummy_disabled` & `skipped:ai_disabled` → **tidak** insert,
  `skipped:rate_max` → insert (baris uji dihapus); `check_migrations.sh --all`
  OK bersih; pgTAP `ai_test.sql` hijau.
- **Efek:** skema/retensi tak berubah — hanya penulis log. Cara debug
  "dummy diam" berpindah ke `dummy_accounts.ai_enabled` (lihat
  `docs/AI_DUMMY_DEBUG.md §7.0`).

## 2026-10-04 — Atribusi sumber user (tab admin baru)

**Tujuan:** admin tahu user datang dari kanal mana (Facebook/IG/Google/TikTok/
referral/organik).

- **Migrasi** `20261004000000_attribution.sql`:
  - Kolom `attribution_source`, `utm_source/medium/campaign/content`,
    `referrer_raw`, `attribution_at` di `public.user_devices` (+2 index).
  - `upsert_device` diperluas dgn 6 param attribution (DEFAULT '') — call-site
    lama (7/8 arg) tetap valid (overload PostgREST). **TULIS SEKALI**
    (`coalesce(existing, excluded)`) supaya resume tidak menimpa kanal asli.
  - RPC admin: `admin_attribution_summary(p_days)`,
    `admin_attribution_users_page(p_source,limit,offset)`.
- **App:** `lib/services/attribution_service.dart` (Play Install Referrer +
  Firebase Analytics), disuntik di `device_info_service.dart` (`upsert_device`)
  + bootstrap `main.dart`. UI: `admin_attribution_tab.dart` (tab ke-9).
- **Build fix:** `android/build.gradle.kts` menaikkan `compileSdk` plugin lama
  (mis. `android_play_install_referrer` = 33) ke 36 → build release tidak gagal
  karena `androidx.exifinterface` menuntut compileSdk ≥ 34.
- **Verifikasi:** migrasi diuji di Postgres 16 lokal (idempotent, write-once,
  RPC ok, backward-compat 7/8-arg ok); `test/attribution_test.dart` (14 test);
  build APK `apkpureProd` OK + gate anti-admin OK.

## 2026-10-03 — stuck_users: hanya user terdaftar

**Alasan:** di ekonomi YukCoin, saldo awal semua user = 0 (kecuali klaim
welcome bonus anon). Definisi lama `stuck_users` (points = 0 & aktif 7 hari)
jadi false-positive — hampir semua user baru anon terhitung "terjebak"
padahal normal. Ditambah `is_registered = true` → yang dihitung hanya user
yang SUDAH daftar email tapi saldo 0.

**Migrasi:** `20261003000300_stuck_users_registered.sql` (apply via Management
API, SUDAH TERAPPLIED): rewrite `admin_stats_compute` — SALINAN PERSIS body
live (dari `20260905100000_admin_stats_exclude_dummies.sql`), **hanya baris
`stuck_users`** diubah. ACL `service_role` dipertahankan. Cache stats di-reset.
- Bukan fungsi FROZEN (tak ada di frozen_functions.txt / snapshot).
- **Verifikasi live:** `has_new_def=true`, `has_old_def=false`; ACL
  `authenticated=false`, `service_role=true`.

**Kode klien:** `config/strings_admin.dart` (`adminStuckUsers` →
"user terdaftar saldo 0 (7 hari)").

## 2026-10-03 — Rapikan label & toast panel Poin (bilingual)

- **Danger Zone**: "Reset semua user ke 50 poin" → "Reset saldo semua user
  ke 50 YukCoin" (+judul/body). Mass bonus → "Bonus Massal YukCoin".
- **Hardcode toast → `s.`** (AGENTS.md): ForceLogoutCard
  (`adminForceLogoutDone`, reuse `errGeneric`), DangerZone (`adminResetDone`),
  MassBonusCard (`adminMassBonusDone`), FeaturePublishCard
  (`adminFeaturePublished`/`adminFeatureHidden`, `errGeneric`, judul/desc +
  4 label fitur `adminFlag*`).
- **Status YukCoin v2** ditampilkan di bawah toggle-nya (`adminYukcoinV2On/Off`)
  + `adminRealtimeDesc` diperjelas (points_enabled = saklar utama ekonomi).
- TANPA migrasi. `flutter analyze` 0 error/0 warning.

## 2026-10-03 — Admin Pengaturan Poin selaras sistem YukCoin

**Bug kritis diperbaiki:** `admin_update_point_settings` (versi 20261001020000)
masih menulis kolom `call_free_minutes_daily` yang DROPPED di
`20261003000000_coin_call_no_free.sql` → SETIAP Simpan Pengaturan Poin dari
panel admin GAGAL (SQLSTATE 42703). Migrasi `20261003000100` sudah membetulkan
`metered_pricing_public` tapi melewatkan RPC ini.

**Migrasi:** `20261003000200_admin_point_settings_yukcoin.sql` (apply via
Management API, SUDAH TERAPPLIED):
1. Rewrite `admin_update_point_settings`: buang `call_free_minutes_daily` +
   semua field faucet mati; TAMBAH welcome bonus (`welcome_anon_coins`,
   `welcome_register_coins`, `welcome_max_claims_per_ip_day`), YukCoin v2
   (`yukcoin_v2_enabled`, `cost_undo_message`, `cost_edit_message`,
   `cost_extra_photo_slot`, `cost_ghost_mode_daily`), `gift_cut_pct`.
2. Rewrite `points_quests`: tak baca lagi kolom faucet (daily/weekly/oneTime
   dikosongkan — layar misi sudah orphan & reward faucet no-op).
3. DROP 19 kolom faucet mati di `app_settings` (`bonus_registered/rated/shared/
   profile/first_photo/room_read/new_chat/invited/first_room/referral/
   online_5min/30min/60min/120min/first_friend`, `room_reads_daily_limit`,
   `new_chats_daily_limit`, `share_click_reward`, `share_click_cap_daily`).
   `bonus_price_multiplier` DIPERTAHANKAN (masih dipakai room_pricing,
   send_gift, unlock_photo).
- Bukan fungsi FROZEN. Snapshot FROZEN tidak berubah.
- **Verifikasi live:** 0 sisa kolom mati; `admin_update_point_settings` &
  `points_quests` tak menyebut kolom yang di-drop; 30 kolom yang ditulis RPC
  semua ada.

**Kode klien:** `lib/screens/admin_panel_screen.dart` (`_pointFields` dirapikan
per grup + toggle boolean `_pointFlags`), `admin_panel/widgets/point_tab_cards.dart`
(switch YukCoin v2 + label), `config/strings_admin.dart` (label YukCoin bilingual).
`flutter analyze` 0 error. Layar misi (`missions_screen.dart`) orphan — tak
tersentuh perilaku.

## 2026-10-03 — Coin untuk nelp (tanpa gratis) + welcome bonus bertahap + fix keamanan

**Keputusan produk:** nelp MURNI pakai coin (tanpa kuota gratis); tarif audio 6 /
video 20 coin per menit; welcome bonus bertahap — anon 100 coin (cukup video 5
menit) + register 100 coin (total 200, register langsung dapat full); anti-farming
sekali per device (`install_id`) + limit per IP/hari.

**Migrasi (apply via Management API, urut):**
1. `20261003000000_coin_call_no_free.sql`
   - DROP kolom kuota-gratis: `profiles.call_free_{audio,video}_seconds_today`,
     `call_free_date`, `app_settings.call_free_minutes_daily`; DROP fungsi
     `call_free_limit_sec()`.
   - Rewrite `call_billing_tick`: tanpa gratis, `billable_minutes = ceil(elapsed/60)`,
     idempoten (`yukcoin_consumptions`), afford-guard (saldo tak minus), return
     `per_minute`.
   - **FIX KEAMANAN**: `charge_metered` revoke dari `authenticated` → hanya
     `service_role` (sebelumnya user bisa mendebit coin user lain via param p_caller).
   - Tabel `bonus_claims` (`install_id, kind, user_id, ip`) + RPC
     `credit_welcome_bonus` (service_role, 3 lapis: install_id, IP/24jam, user).
   - Config: `welcome_anon_coins=100`, `welcome_register_coins=100`,
     `welcome_max_claims_per_ip_day=3`.
2. `20261003000100_fix_metered_pricing_public.sql` — `metered_pricing_public`
   error 42703 setelah kolom `call_free_minutes_daily` dihapus → dikembalikan
   tanpa kolom itu.

**Edge function (deploy --use-api):**
- `welcome-bonus` (verify_jwt=true) — tangkap IP server-side (x-forwarded-for),
  panggil `credit_welcome_bonus`.
- `play-topup-verify` (verify_jwt=true) — verifikasi purchase ke Google Play
  Developer API → `credit_play_topup`.

**Verifikasi live:** kolom `call_free_*` = 0 sisa; `metered_pricing_public()`
return audio 6/video 20; `charge_metered` ACL = {postgres, service_role};
`credit_welcome_bonus` ada; 2 edge function ACTIVE.

## 2026-09-30 — Notif "X online" → teman + follower + pernah chat

**Minta user:** saat A online, notifikasinya ke teman, follower, dan orang
yang pernah chat dengan dia (dulu HANYA yang pernah chat).
**Migrasi:** `20260930052500_online_notify_friends_followers.sql` — penerima
`notify_contact_online` = UNION(teman mutual | follower-ku | pernah 1:1
chat); chatId diisi bila ada chat (tap → chat), NULL bila tidak (klien:
tap → profil); skip blokir dua arah (selaras get_online_users; dulu tak
dicek); guard lain utuh (transisi →online; author dummy tak notify).
**Klien:** `_openFromData` — `online` tanpa chatId → `UserInfoScreen`
(sebelumnya jatuh ke chat kosong).
**Apply:** Management API + catat `schema_migrations`.
**Test:** pgTAP `online_notify_test.sql` 6/6 (teman/follower/chatter dapat +
chatId; stranger & diblokir tidak; idle→online notify lagi).

## 2026-10-02 — Deteksi Fake GPS (flag device + heuristik server), tandai saja

**Minta user:** di admin panel bisa tahu lokasi GPS asli atau palsu — flag
device + heuristik; badge/ikon di info lat-long & peta; riwayat perlu.
**Migrasi:** `20261002060000_fake_gps_detect.sql`:
- `profiles` + `location_mocked / location_mock_reason / location_accuracy_m
  / location_flagged_at`; `user_location_history` + `location_mocked /
  mock_reason / accuracy_m`.
- `update_my_location` 4-arg → 6-arg (`+p_mocked`, `+p_accuracy`); overload
  lama DI-DROP. Heuristik: `is_mocked` (device `Position.isMocked`) |
  `accuracy_zero` (akurasi ≤0) | `impossible_speed` (>250 m/s, **butuh jeda
  ≥10 dtk**) | `spoof_delta` (GPS↔IP >500 km). Hanya `p_source='gps'`.
- `admin_stats_detail` (FROZEN, `-- menyentuh:`) + `location_mocked` /
  `mock_reason` di 4 query users_*; `admin_user_detail` location_history +
  `mocked/reason/accuracy_m`.
**Klien:** `LocationService` baru tipe `DeviceFix` (lat/lon/mocked/accuracy)
→ `p_mocked`/`p_accuracy`; provider export `DeviceFix`; 3 call-site
(entry/register/location_picker) diadaptasi.
**Admin UI:** pin peta merah + ikon `gpp_bad` (prioritas), baris koordinat
"GPS (Fake)" + reason, legenda, `stat_detail_sheet`, riwayat di
`user_detail_sheet` (badge).
**Apply:** Management API + catat `schema_migrations`. Snapshot FROZEN
di-regenerate (diff = hanya 4 baris `admin_stats_detail`, 0 hapus).
**Test:** pgTAP `fake_gps_test.sql` 7/7.
**Batasan (SADAR):** `isMocked` bisa dilewati sebagian Fake GPS → indikator,
BUKAN bukti 100%; tidak untuk auto-ban. Ambang heuristik konstanta mudah ubah.

## 2026-09-30 — Fix chatId NULL di payload outbox "online" (temuan review)

**Bug:** penerima tanpa chat 1:1 dapat `chatId: null` → outbox-worker →
send-push `String(null)` = string `"null"` → cek `.isEmpty` klien gagal →
jatuh ke layar chat rusak, bukan profil.
**Migrasi:** `20260930053000_online_notify_chatid_fix.sql` — 1 baris:
`coalesce(contact_chat,'')` di `notify_contact_online`.
**Review lanjutan:** PostCard di layar detail tak refresh (like/komen/share/
follow/boost) karena hanya andalkan `updatePost` provider + rebuild parent —
tambah `_patchLocal` (patch map lokal + setState) di 5 situs; hapus post
dari detail kini pop via callback `onDeleted`.

## 2026-09-29 — Audit notif post timeline (3 kurang diperbaiki)

**Diminta user cek ulang.** Temuan & fix (`20260929220200_timeline_post_notify_audit.sql`):
1. `get_post` belum ada gate ANON_DISABLED (ada di `list_posts`) → anon bisa
   baca post public. Ditambah (bypass dummy & admin, cermin list_posts).
2. Post public dari author **dummy** akan blast semua user asli → cabang
   public→semua kini dilewati bila author dummy (follower/subscriber dummy
   tetap dapat seperti dulu).
3. Klien: tipe FCM `timeline` (topic) lolos dari toggle prefs Timeline →
   `shouldShowForFcmType` kini memetakan `timeline` → toggle `timeline`.
**Test:** pgTAP `timeline_post_notify_test.sql` 13/13 (+anon ditolak, +cek
definisi); prefs timeline on/off hijau.

## 2026-09-29 — Notif post timeline sesuai visibilitas + tap buka postingan

**Minta user:** post PUBLIC → notifikasi untuk SEMUA + tap masuk ke
postingannya; FOLLOWERS → follower saja; SUBSCRIBERS → subscriber saja.
**Temuan:** trigger `notify_post_followers` untuk public hanya ke follower
(+subscriber-non-follower); fanout topic `timeline-all` tembak SEMUA
visibilitas (bocor isi followers/subscribers-only; walau topic belum ada
subscriber); tap `timeline_post` hanya buka tab Timeline (bukan postnya).
**Migrasi:** `20260929213300_timeline_post_notify_all.sql` — cabang `public`
→ loop semua profil registered non-dummy non-exclude (kecuali author; skip
blokir); `notify_timeline_post_fanout` hanya bila `public`; RPC BARU
`get_post(p_id)` (bentuk = item `list_posts`, hormat visibilitas+blokir).
**Klien:** `PostDetailScreen` (pakai ulang `PostCard`); tap
`timeline_post`/`timeline` + `postId` → detail; tanpa postId → tab Timeline.
**Apply:** Management API + catat `schema_migrations`.
**Test:** pgTAP `timeline_post_notify_test.sql` 10/10; `timeline_service_test`
(+getPost) hijau; `post_detail_screen_test` hijau; `flutter analyze` 0/0.

## 2026-09-29 — Privacy picker: kandidat = semua yang pernah chat (registered + anon)

**Keluhan (user):** memilih "Hanya orang tertentu", nama "Kartika"
(registered, pernah 1:1 chat) tidak muncul saat dicari.
**Akar:** `privacy_excludable_users` @20260929130000 hanya menambah chatters
`is_registered = false` (anon) → user registered non-teman tak pernah jadi
kandidat.
**Migrasi:** `20260929140000_privacy_excludable_all_chatters.sql` — buang
syarat `is_registered = false`; kandidat kini = teman | follower-ku |
subscriber aktifku | **pernah 1:1 chat (registered maupun anon)** | sudah di
daftar saya. Limit 300→500.
**Apply:** Management API + catat `schema_migrations`. Verifikasi live: sebagai
`tisubasah` → `privacy_excludable_users()` memuat `Kartika` (is_friend=false).
**Test:** pgTAP `privacy_only_test.sql` 15/15 (+2 assert: chatter registered
muncul; isolated tak muncul).

## 2026-09-29 — Privasi "Hanya orang tertentu" (only) menggantikan circle + fix allowlist

**Keluhan (user):** di Pengaturan › Privasi, memilih opsi "Kenalan" tidak
bisa memilih siapa orangnya; harusnya ada pilihan orang tertentu saja.
**Akar (lebih besar):** `update_privacy_settings` di DB live MASIH 4 nilai
lama (`everyone/friends/except/nobody`) — jadi memilih `circle`,
`everyone_except`, maupun `friends_except` SELALU gagal
(`Invalid presence visibility`) dan tak tersimpan. Keputusan user: ganti
mode otomatis `circle` → `only` = daftar PUTIH yang dipilih manual.
**Migrasi:** `20260929130000_privacy_only_whitelist.sql` — constraint 6
nilai `..._except`, `only`, `nobody` (data `circle`→`only`); drop
`_privacy_is_circle` (tak ada pemakai lain); `privacy_can_view` cabang
`only` → `v_excluded` (whitelist, **menyentuh: privacy_can_view**);
`get_online_users` cermin `only` (join exclusion yang sama = daftar putih);
`update_privacy_settings` allowlist 6 nilai + guard `only` wajib 1+ orang;
`privacy_excludable_users` kandidat diperluas (teman|follower|sub-aktif|
anon-pernah-chat|sudah-di-daftar-`only`).
**Apply:** Management API + catat `schema_migrations`. Verifikasi live:
constraint_ok (`only`), helper circle=0, gate/online has `only`,
update allowlist has `only`, versi tercatat.
**Test:** pgTAP `privacy_only_test.sql` 13/13 (daftar putih lolos; teman
non-daftar DITOLAK; field tanpa daftar tak ada yang lolos; guard `only`
tanpa daftar ditolak; cermin online list). `privacy_test.sql` 6-opsi OK.
Widget `privacy_widget_test.dart` (picker daftar putih) + unit enum hijau.
**Rollback:** constraint `circle`, re-apply gate/online @20260929120000
(helper circle), re-apply `update_privacy_settings` @20260920130000.

## 2026-09-29 — Privasi mode "circle" (Kenalan), nilai visibility ke-6 — DIGANTIKAN

> DIGANTIKAN oleh `20260929130000_privacy_only_whitelist.sql` (di atas):
> mode `circle` otomatis → `only` daftar putih manual; helper
> `_privacy_is_circle` di-drop. Catatan di bawah untuk riwayat.

**Kebutuhan (user):** profil hanya tampil untuk orang tertentu — teman,
follower, subscriber, atau yang pernah chat (termasuk anon). Opsi lama
(teman = mutual saja; pernah-chat-non-teman = stranger) tidak cukup.
Keputusan: mode baru `circle` ( inbound saja: yang follow aku, subscriber
aktifku, teman, pernah 1:1 chat); TANPA `circle_except`; list tetap
tampil+sensor (tidak ada sembunyi-baris baru).
**Migrasi:** `20260929120000_privacy_circle_visibility.sql` — constraint
5→6 nilai; helper baru `_privacy_is_circle()` (follows-inbound | subscription
aktif | `private_chats.participants @>`; mutual tercakup inbound; grants
= pola RPC standar); cabang `circle` di `privacy_can_view`
(**menyentuh: privacy_can_view**, sumber @20260924230000, cabang lama
byte-identik); cermin `circle` di 4 flag + filter presence
`get_online_users` (sumber @20260926020000). Reader lain (presence_for,
avatar_for, nearby, story_tray/slides, profile_public) memanggil gate
langsung → tanpa ubah. `idx_private_chats_participants_gin` sudah ada.
Bukan fungsi FROZEN → snapshot tidak perlu.
**Apply:** Management API + catat `schema_migrations`. Verifikasi live:
constraint_ok, helper ada, gate_ok + mirror_ok via `pg_get_functiondef`.
**Test:** pgTAP `privacy_circle_test.sql` 17/17 (teman/follower/sub-aktif/
chat/anon-chat lolos; stranger/sub-kedaluwarsa/following-searah ditolak;
daftar-kecuali diabaikan; cabang friends utuh; cermin online list +
presence_for). Regresi: privacy 17/17, bypass 7/7, presence 9/9, story
20/20, contract 11/11, schema_sync 44/45 (1 gagal pre-existing nearby
share_location, tak terkait).
**Klien:** enum `circle` + sheet 5→6 opsi + string bilingual
(`privacyCircle`/`privacyCircleDesc`); test widget 14/14 hijau.
**Rollback:** kembalikan visibility pemakai circle → friends, constraint
5-nilai, re-apply gate @20260924230000 + get_online_users @20260926020000.
# MIGRATION_LOG â€” catatan perubahan versi & penerapan

## 2026-09-29 â€” Monitor chat realtime (policy SELECT admin)

**Keluhan (user):** pesan baru di monitor chat admin telat 5-10 detik.
**Akar:** policy SELECT `private_messages` live hanya untuk peserta chat â†’
Supabase Realtime (tunduk RLS) tidak mengirim event ke sesi admin â†’ layar
hanya mengandalkan poll 5 dtk. Tabel sudah di publication realtime.
**Migrasi:** `20260929010000_admin_monitor_realtime_select.sql` â€” policy BARU
`private_messages_admin_select` FOR SELECT USING (`is_admin_request()`);
read-only, hanya admin; user biasa tetap policy peserta; admin sudah baca
semua via RPC (`admin_get_chat_messages_page`) jadi tidak ada akses baru
secara substansi. Bukan fungsi FROZEN â†’ snapshot tidak perlu.
**Apply:** Management API + catat `schema_migrations`.
**Verifikasi live:** policy ada (`pg_policies`), USING = `is_admin_request()`;
`smoke_anon_register.sh` OK; pgTAP `contract` 11/11, `delete_message` 4/4,
`regression` 5/5 hijau. `schema_sync` 44/45 â€” 1 gagal
(`nearby_users() gate share_location`) tidak terkait perubahan ini
(pre-existing, jalur nearby).
**Klien:** tanpa perubahan â€” `_subscribeRealtime` sudah benar, event kini
mengalir; pesan baru tampil instan, poll 5 dtk tinggal fallback.

## 2026-09-26 â€” Video di private chat + video "sekali lihat"

**Kebutuhan (user):** "di private chat di bawah icon tambah, selain foto bisa
kirim video juga tapi dilimit videonya dan dicompress" + "video sama kaya foto
ada timernya cuman timernya untuk sekali lihat AJA (kalo sesuai panjang video
kan)". Keputusan: durasi maks 60 dtk, hasil kompres â‰¤8 MB, preview sebelum
kirim, private dulu (room menyusul).

**Migrasi (bukan FROZEN, kecuali notif):**
- `20260926120000_chat_photos_guard_video.sql` (sesi paralel) â€” guard storage
  izinkan video/mp4 â‰¤20 MB di bucket chat-photos.
- `20260926130000_private_chat_video_type.sql` â€” `private_messages.type` +
  `'video'`; `notify_private_message` body `[Video]` (**menyentuh:
  notify_private_message**).
- `20260926160000_video_once_type.sql` â€” + `video_once` & `video_once_expired`.
  (Timestamp awal `20260926140000` BENTROK dgn sesi paralel
  `messages_allow_location_type.sql` â†’ dinaikkan.)
- `20260926150000_notif_video_label.sql` â€” label `[Video]` untuk ketiga type
  video (**menyentuh: notify_private_message**). Snapshot di-refresh.

**Keputusan desain penting:** `duration_ms` untuk video = PANJANG VIDEO
(playback), BUKAN timer. Karena itu "sekali lihat" video ditandai lewat TYPE
(`video_once`) â€” menumpang duration_ms akan bertabrakan makna (foto memakai
duration_ms sebagai timer countdown).

**Klien:**
- `storage_photo_service.dart`: `chatVideoPath`/`uploadChatVideo`/
  `compressChatVideo` (480p)/`videoDurationMs`; **fix `isPath()`** menerima
  `.mp4`/`.mov` (tanpa ini path video dikira base64 â†’ bubble gagal).
- `chat_photo_send_mixin.dart`: `videoPickToPreview` (validasi durasi â†’
  kompres + progress â†’ poster â†’ preview) + `sendVideoFromPreview`/`_sendVideoLike`
  (optimistic + poin + upload + outbox `uploadKind: 'video'`).
- `chat_video_bubble.dart` (BARU): poster + play + durasi; `locked` untuk
  `video_once_expired`; `VideoPlayerScreen` publik (dipakai preview composer).
- `chat_composer_input.dart`: preview video (play + badge durasi + toggle
  "sekali lihat") + chip "Kirim Video".
- `chat_send_mixin.dart`: router video sebelum foto.
- Outbox flush: cabang `uploadKind == 'video'`.

**Bug yang ditemukan & diperbaiki saat smoke test HP:**
1. Tombol send tetap jadi tombol MIC saat hanya video pending (kondisi
   `hasText/hasPhoto` tak menghitung video) â†’ video tak pernah terkirim.
2. Preview video tak bisa diputar (tidak ada aksi tap) â†’ tombol play sekarang
   membuka `VideoPlayerScreen`.
3. `pendingVideoMs` di mixin berbentuk FIELD â†’ menutupi getter layar â†’ durasi
   selalu 0. Diganti `get` (analyzer menjaga: layar memakai `@override get`).

**Test:** `test/chat_video_bubble_test.dart` 11 assert (label durasi, batas
60 dtk/8 MB, deteksi path, regresi `isPath` video). `analyze` 0 error.


## 2026-09-26 â€” Voice stage global room (`20260926100000`)

- **Fitur:** max 6 mic nyala (audio-only), pendengar unlimited, mic default
  mati, admin/owner mute paksa, keluar room = turun stage otomatis.
- **Isi:** tabel `room_voice_signals` (+index, RLS global/member, realtime)
  + `room_voice_speakers` (+index, RLS select saja); RPC join (enforce max 6
  via heartbeat 45 dtk) / heartbeat / leave / mute (owner/app-admin +
  sinyal v_mute) / sweep; cron `sweep_room_voice` tiap menit.
- **Check:** `check_migrations.sh` OK bersih (policy baru pakai `-- SAFE:`).
- **Apply:** Management API + catat `schema_migrations`. Verifikasi: 2 tabel
  ada, 5 RPC ada, cron job 26 aktif.
- **Client:** `room_voice_service.dart` (mesh audio, pola broadcast) +
  `VoiceMicButton`/`VoiceStageStrip` + wiring `room_chat_screen.dart`
  (global room saja). Test `room_voice_session_test.dart` 3/3.

## 2026-09-26 â€” Admin scale Fase 2: N+1 â†’ agregasi + sheet paginasi

- **`20260926060000`**: `admin_list_dummies_page` â€” `unread` 50Ã— correlated
  â†’ 1Ã— GROUP BY + join (`ai_persona` tetap dikirim).
- **`20260926070000`**: `admin_list_chats_page` â€” total â†’ estimasi reltuples;
  count+max per chat â†’ 1Ã— agregasi (semantik urutan `call` dipertahankan).
- **`20260926080000`**: `admin_user_detail` â€” count via agregasi;
  `location_history` dibatasi 200; kunci JSON tidak berubah.
- **`20260926090000`**: `admin_stats_users_page` (BARU) â€” daftar user
  statistik ber-paginasi; `admin_stats_detail` (FROZEN) tidak disentuh.
  Client `stat_detail_sheet.dart` infinite scroll untuk 4 kunci user.
- Apply via Management API + catat `schema_migrations`; verifikasi definisi
  live per fungsi.

## 2026-09-26 â€” Fix paginasi admin_list_deleted (`20260926050000`)

**Bug:** `LIMIT/OFFSET` di subquery union tanpa `ORDER BY` dalam (urut baru
di agregat luar) â†’ halaman 2+ mengambil baris acak/duplikat saat data banyak.

**Fix:** `order by sort_at desc nulls last` di dalam subquery sebelum limit;
output halaman-1 identik. Dasar = definisi live 20260926000000
(device_count/location_count dipertahankan). Bukan fungsi frozen.
Apply via Management API + catat `schema_migrations`. Verifikasi live:
definisi memuat klausa fix; paginasi deterministik (page1=100, page2=5,
overlap=0, batas urutan benar); EXPLAIN = Index Only Scan via
`deleted_users_deleted_idx`.

## 2026-09-25 â€” Story admin ghost-mode (`20260926030000`)

**Kebutuhan (user):** "chatyuk admin jangan keliatan kalo liat story orang"
+ "hapus yang udah keliatan" â€” admin moderasi story harus invisible.

**Akar:** viewer memanggil `mark_story_seen_bulk` untuk semua user termasuk
admin â†’ baris `story_views(viewer_id=admin)` tercatat â†’ pemilik story melihat
nama admin di daftar penonton.

**Migrasi `20260926030000_story_admin_ghost.sql`** (bukan FROZEN):
- `mark_story_seen`: return ok tanpa insert bila `is_admin_request()` dan
  bukan author sendiri.
- `mark_story_seen_bulk`: WHERE + `(s.author_id = uid or not is_admin_request())`
  â†’ bulk admin hanya mencatat milik sendiri.
- `story_viewers`: filter `not exists (auth.users email=zunixe)` â†’ baris admin
  tidak pernah dikembalikan (walau lolos via client lama).
- CLEANUP: `delete from story_views using auth.users where email=zunixe`
  â†’ jejak yang sudah tercatat terhapus (live: 0 sisa).
- Client `story_viewer_screen.dart`: `_isAdminCached` (init) + skip `_markSeen`
  / buang antrean di `_flushSeen` bila admin lihat story orang â†’ 0 RPC.
- Test: `story_test.sql` +3 assert ghost (single/bulk/viewers).
- Apply via Management API + verified live (single/bulk/viewers true).
- Catatan: `check_migrations --all` masih FAIL timestamp duplikat lama
  `20260926020000` (online_list_about + story_mute) â€” pre-existing, bukan
  dari migrasi ini.

## 2026-09-25 â€” Tentang tampil di kartu Online (`20260926020000`)

**Kebutuhan (user):** isi Tentang tampil di bawah baris gender di halaman
Online. Kolom output baru `about` di `get_online_users` + `presence_for`
(fast-path presence), hormati `about_visibility` + exclusions (pola sama
dengan avatar/last_seen). Kosong/tidak diizinkan â†’ server kirim `''`,
kartu menyembunyikan barisnya. Klien: baris italic maxLines 2 di
`_UserCard`; `UserModel.fromMap`/`toMap` sudah membawa `about` (cache
disk ikut). Bukan FROZEN. Apply via Management API + verified live
(`about_ok`, privacy `about`). Test: `schema_sync_test.sql` +2 assert
(31/31), `online_visibility_test.dart` +3 (24/24).

## 2026-09-25 â€” Riwayat device + GPS tetap di tab Terhapus (`20260926000000`)

**Kebutuhan (user):** "info perangkatnya jangan dihapus di admin sama gpsnya"
+ "riwayat device dan riwayat gpsnya" â€” user yang sudah dihapus harus tetap
menampilkan info perangkat & riwayat GPS di admin panel tab Terhapus.

**Akar:** `delete_my_account` (20260923130000) & `admin_delete_anon_user`
(20260921230000) menghapus eksplisit `user_devices` + `user_location_history`
SEBELUM `delete profiles` (wajib, kalau tidak 23502 NOT NULL). Efek samping:
`admin_deleted_device_history(nickname)` (baca `nickname_snapshot` live) selalu
kosong untuk hapusan baru, dan GPS tak ada RPC-nya di tab Terhapus.

**Migrasi `20260926000000_deleted_device_gps_archive.sql`** (bukan FROZEN):
- `deleted_users` +2 kolom: `devices jsonb`, `locations jsonb` (default `'[]'`).
- `fn_archive_deleted_user` (dasar = live): snapshot â‰¤50 device + â‰¤100 lokasi
  terbaru SEBELUM baris live dihapus; insert mencakup kedua kolom.
- `admin_deleted_device_history`: utamakan snapshot arsip terbaru per nickname,
  fallback ke live yatim (arsip lama).
- BARU `admin_deleted_location_history(p_user_id)` â†’ snapshot GPS/IP arsip.
- `admin_list_deleted`: item arsip +`device_count`/`location_count`
  (pending tetap 0). Live tables tetap dibersihkan (deletion sukses, tab
  Perangkat tanpa orphan).
- Client: `AdminService.getDeletedLocationHistory` +
  `AdminProvider.getDeletedLocationHistory`; `AdminDeletedTab._showDetail`
  fetch device (by nick) + lokasi (by uid); `DeletedDetailSheet` section
  "Riwayat GPS" (hijau=gps, oranye=ip, â‰¤20 terbaru) + string bilingual
  `adminDeletedLocationHistory`/`adminDeletedNoLocation`.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” kolom `devices`/`locations` ada;
`admin_deleted_location_history` ada; `fn_archive` memuat `v_devices`/
`v_locations`; `admin_list_deleted` memuat counts. pgTAP baru
`supabase/tests/deleted_archive_test.sql` 8/8 hijau. `flutter test`
`test/admin_service_test.dart` 29/29 hijau (termasuk RPC lokasi baru).
Catatan: arsip LAMA (terhapus sebelum migrasi) tetap kosong â€” snapshot hanya
untuk hapusan setelah migrasi ini.

## 2026-09-25 â€” Email + sort register-terbaru di Reg ringkasan (`20260925061000`)

**Kebutuhan (user):** tab Reg ringkasan admin tampilkan email + sort
register paling baru di atas (bukan online).

**Migrasi `20260925061000_admin_stats_detail_reg_email.sql`** (menyentuh
FROZEN `admin_stats_detail`, header ada; dasar = snapshot live persis):
`'email', email` ke KEEMPAT list user + `users_registered`
`order by created_at desc nulls last` (list lain tetap `last_seen`).
UI `userRow` SUDAH membaca `u['email']` â€” tanpa ubah client.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” blok `users_registered`
live memuat email + sort created_at; snapshot diregenerate.

## 2026-09-25 â€” PEMISAH global vs grup + ikon upload (`20260925054000`)

**Kebutuhan (user, tegas):** room buatan explore = GLOBAL ROOM persis
seperti global lama (chat terbuka, tanpa anggota/password); grup (legacy
`'private'`) tampil di tab Grup saja. Kasus: 'Curhat Kehidupan' telanjur
masuk Grup. Ikon room bisa upload sendiri.

**Migrasi `20260925054000_room_global_split.sql`** (menyentuh FROZEN
`create_private_room`, header ada; dasar = live persis):
room kategori â†’ `is_private=false` (GLOBAL, kolom lain sama);
data fix `category <> 'private' AND is_private` â†’ global (1 room:
Curhat Kehidupan); `list_room_explore` + `AND is_private=false`
(grup tidak bocor ke Global Room); `storage_object_owner_ok` (BUKAN
frozen) + cabang `room-icons/<uid>/<file>` (ikon upload, fail-closed
tetap untuk prefix lain).

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” Curhat Kehidupan
`is_private=False`; explore Indonesia â†’ 11 room semua global;
snapshot diregenerate (diff = hanya tambahan split, tanpa cabang hilang).

## 2026-09-24 â€” Explore room + buat room gratis per kategori (`20260924221000`)

**Kebutuhan (user):** Global Room ala gambar â€” chip kategori (Rame/Game/Musik/
Curhat/...) + satu list gabungan global + grup (member â€¢ online, preview,
badge unread, waktu relatif, Live HANYA grup) + FAB Buat Room gratis.

**Migrasi `20260924221000_room_explore.sql`** (menyentuh FROZEN
`create_private_room`, header ada; dasar = snapshot live persis):
tambah `p_category` (allowlist 10 kategori + `'private'` legacy);
kategori ASLI = GRATIS (skip ledger), terbuka (`approval_required=false`,
`max_members=200`); legacy `'private'` tidak berubah (bayar + antre + 20).
Overload 4-arg lama di-DROP (cegah PostgREST 300, preseden 2026-09-11).
BARU: tabel `room_reads` (unread sync) + RLS own-row;
RPC `list_room_explore(p_country)` (member/online/pesan terakhir/is_live
grup-only/unread) + `mark_room_read(p_room_id)`.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” overload tinggal 1;
`list_room_explore('Indonesia')` â†’ 11 room; snapshot diregenerate
(diff = hanya tambahan kategori/gratis, tanpa cabang hilang).

## 2026-09-24 â€” Avatar gender di sheet Ringkasan (`20260924110000`)

**Kebutuhan (laporan user):** daftar user di sheet Ringkasan (Users, Active,
Msgs, Reg, Anon) disamakan Pengguna Online â€” foto + ketahuan laki/
perempuan. Data `gender` sudah ada, tapi `id` (untuk foto) hanya ada di
`users_all`, dan `messages_today` tanpa sender/gender.

**Migrasi `20260924110000_admin_stats_detail_gender_photo.sql`** (menyentuh
FROZEN `admin_stats_detail`, header ada; dasar = definisi live persis):
tambah `'id'` ke users_active/registered/anonymous +
`'sender_id'`/`'sender_gender'` ke messages_today. Murni aditif.

**Client (`admin_panel_screen`):** `userRow` + `msgRow` pakai avatar warna
gender (biru/pink ala Online) + ikon â™‚/â™€ di samping nama; foto via
`AdminAvatarCircle` yang sudah ada (lazy per viewport).

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” `pg_get_functiondef`
memuat `sender_gender` + `'id', id` Ã—4; snapshot diregenerate
(stamp baru, diff = hanya tambahan itu, tanpa cabang hilang).

## 2026-09-24 â€” Breakdown ukuran tabel di Ringkasan (`20260924100000`)

**Kebutuhan (laporan user):** angka "Database 71MB" di kartu Ringkasan tidak
bisa ditelusur â€” mau diklik lalu terlihat tabel/fungsi mana yang besar untuk
cek pertumbuhan.

**Migrasi `20260924100000_admin_table_sizes.sql`** (fungsi BARU, bukan
FROZEN): `admin_table_sizes(p_limit=30)` â€” guard admin sama seperti
`admin_storage_stats`, return `{db_bytes, tables: [{schema, table,
total_bytes, table_bytes, index_bytes, rows_est}]}`. Hanya baca katalog
(`pg_total_relation_size` + `reltuples` estimasi) â€” tanpa seq-scan.
Fungsi SQL sendiri tidak memakan ruang berarti; yang diukur = tabel (+index).

**Client:** `AdminService.getTableSizes` + `AdminProvider.fetchTableSizes`
(fresh tiap sheet dibuka) + sheet `tablesize_sheet.dart` dari baris Database
(chevron). String admin bilingual baru 6 biji.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPKAN & TERVERIFIKASI LIVE** â€” RPC balas
`db_bytes=74034323` (~71MB âœ… cocok dengan kartu). Top live:
`cron.job_run_details` 35MB (!), `ai_reply_log` ~4MB, `private_messages`
~2.6MB, `call_signals` ~2.2MB, `auth.refresh_tokens` ~1.8MB.

## 2026-09-23 â€” Delete private chat selalu gagal: fix cast trigger (`20260923160000`)

**Masalah (laporan user: gagal delete pesan):**
`deletePrivateMessage` â†’ `update is_deleted=true` selalu di-rollback oleh
trigger `scrub_reply_snapshot_private` yang membandingkan
`replied_to_id (text) = new.id (bigint)` tanpa cast â†’ Postgres error
"operator does not exist: text = bigint". Room aman
(`messages.replied_to_id` bigint). Backfill di migrasi asal sudah pakai
`::text`, hanya trigger yang kelewat.

**Migrasi `20260923160000_fix_private_delete_trigger.sql`** (fungsi non-FROZEN):
`where pm.replied_to_id = new.id::text`.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPKAN & TERVERIFIKASI LIVE** â€” `pg_get_functiondef`
mengandung `new.id::text`.

## 2026-09-23 â€” Hapus akun: fix 23502 user_devices/user_location_history (`20260923130000`)

**Masalah (laporan user: hapus akun anon "hdjdjfj" selalu gagal):**
`delete_my_account()` â†’ `delete from public.profiles` memicu FK
`user_devices.user_id` / `user_location_history.user_id` yang aksinya
SET NULL â€” tetapi kedua kolom `user_id` NOT NULL â†’ `23502 null value in
column "user_id"`. Komentar lama ("hardware milik install, FK SET NULL")
salah asumsi. Akun tanpa device row lolos, sehingga bug tak terdeteksi
(reproduksi awal dgn anon kosong: `{"ok": true}`).

**Migrasi `20260923130000_delete_account_devices_fix.sql`** (fungsi
non-FROZEN; definisi penuh disalin dari live + 2 baris hapus eksplisit
SEBELUM `delete from profiles`; grant tidak diubah):
- `delete from public.user_devices where user_id = v_uid;`
- `delete from public.user_location_history where user_id = v_uid;`

**Apply:** via Management API (bukan `db push`), versi `20260923130000`
dicatat di `schema_migrations`. **Status: DITERAPKAN & TERVERIFIKASI LIVE** â€”
anon + device + location + ledger â†’ `delete_my_account` = `{"ok": true}`,
sisa artefak test 0 (dibersihkan tuntas via pola replica-role).

**Test:** `supabase/tests/delete_account_test.sql` BARU (4 assert, hijau:
hapus eksplisit ada, urutan SEBELUM profiles, komentar usang hilang).
Tanpa rebuild aplikasi (fix server-side; app 1.2.49 sudah memanggil RPC ini).
Lihat `docs/INCIDENT_DELETE_ACCOUNT_23502.md`.

## 2026-09-23 â€” Penonton story: admin bebas + pariti mark_seen (`20260923120000`)

**Masalah (audit fungsi penonton story, versi live diverifikasi via Management
API):**
1. `story_viewers` HANYA mengizinkan author (`s.author_id = auth.uid()`),
   padahal UI (`story_viewer_screen.dart`) menampilkan tombol penonton untuk
   `_own || _isAdmin`. Admin membuka slide dummy â†’ RPC `raise 'Unauthorized'`
   â†’ klien dulu menelan error jadi `[]` â†’ admin melihat "Belum ada penonton"
   (salah, menyesatkan).
2. `mark_story_seen` (single) mendukung `'everyone'/'registered'/'friends'`
   TANPA `'followers'` dan TANPA cek blokir.
3. `mark_story_seen_bulk` mendukung `'everyone'/'followers'/'friends'`
   TANPA `'registered'`.
   Keduanya belum memanggil `privacy_can_view(author,'story')` yang sudah jadi
   sumber kebenaran di `story_slides` + `story_tray` â†’ penonton tidak tercatat
   untuk sebagian kombinasi visibility (daftar penonton kurang).

**Migrasi `20260923120000_story_viewers_admin_markseen_parity.sql`** (3 fungsi
non-FROZEN; signature TIDAK berubah, tanpa `DROP FUNCTION`):
- `story_viewers`: guard jadi author ATAU `public.is_admin_request()`
  (guard admin anti-rentan â€” cek email di DB, bukan hanya klaim JWT).
- `mark_story_seen` + `mark_story_seen_bulk`: daftar visibility DISAMAKAN ke
  `everyone`/`followers`/`friends`/`registered` + cek blokir dua arah +
  `privacy_can_view(author,'story')`.
- Fungsi FROZEN `story_slides` & `create_story` TIDAK disentuh.

**Klien:** `story_service.dart` `fetchViewers` sekarang `List<StoryViewer>?`
(`null` = gagal, `[]` = kosong) â€” dulu keduanya `[]` sehingga kegagalan
menyamar jadi "belum ada penonton"; `story_provider.dart` + `story_viewer_screen.dart`
menampilkan pesan gagal (`storyViewersLoadFail`) bila `null`.

**Apply:** via Management API (bukan `db push`), versi `20260923120000` di-apply
2026-09-23. **Status: DITERAPKAN & TERVERIFIKASI LIVE** â€”
`story_viewers` punya `is_admin_request`; `mark_story_seen` &
`mark_story_seen_bulk` memuat `followers` + `registered` + `privacy_can_view`.

**Test:** `supabase/tests/story_test.sql` BARU (17 assert, hijau);
`test/story_viewer_model_test.dart` BARU + grup `fetchViewers` di
`test/story_social_io_test.dart`. `flutter test` 1025 hijau, SQL tests 11 file hijau.

## 2026-09-22 â€” Privasi "Orang Sekitar": filter blokir + gate berbagi (`20260922140000`)

**Masalah (audit fitur Nearby):**
1. `nearby_users` **tanpa filter `blocks`** â†’ user yang saling memblokir tetap
   muncul di daftar Orang Sekitar (keberadaan + jarak bocor; chat-nya sendiri
   sudah ditolak server).
2. Gate "harus bagikan lokasi dulu" hanya di UI
   (`nearby_screen` `if (!_shareOn)`) â†’ panggilan RPC langsung tetap bisa
   melihat orang lain walau viewer `share_location=false` (bisa "mengintip").
3. `get_online_users` punya lubang blokir **sama** (daftar online tak memfilter
   `blocks`).

**Migrasi `20260922140000_nearby_privacy_blocks_share_gate.sql`** (menyentuh
FROZEN `nearby_users` + non-frozen `get_online_users`):
- `nearby_users`: gate simetris â€” bila `share_location=false` â†’ `raise exception
  'Share required'` (dicek sebelum cek `lat/lon`, sebelum `'No location'`);
  tambah filter blokir dua arah (`blocks`) idiom sama dengan `story_slides`.
- `get_online_users` (kedua overload plpgsql): tambah filter blokir dua arah.
  Tidak ada gate share di sini (online list bukan fitur lokasi).

**Klien:** `lib/config/strings.dart` + `nearbyNeedShareDesc` (bilingual);
`lib/screens/nearby_screen.dart` memetakan error `'share required'` â†’ empty
state "Butuh berbagi lokasi" (dibedakan dari `'no location'`).

**Apply:** via Management API (bukan `db push`), versi `20260922140000` dicatat
di `supabase_migrations.schema_migrations`. **Status: DITERAPKAN 2026-09-22** â€”
terverifikasi live: `nearby_users` punya `public.blocks` + `'Share required'`;
`get_online_users` punya `public.blocks`. Snapshot FROZEN di-regenerate
(`supabase/snapshots/functions.sql`, diff = hanya `nearby_users`). Test pgTAP
`schema_sync_test.sql` +4 assert (29/29 hijau).

## 2026-09-22 â€” Konfigurasi popup update aplikasi (`20260922120000`)

**Fitur:** klien menampilkan popup update saat masuk app bila ada versi baru.
Sumber kebijakan = `app_settings` (bukan hardcode), sehingga admin bisa
mengaktifkan/mengubah tanpa rilis ulang.

**Migrasi `20260922120000_app_update_config.sql`:** tambah 4 kolom ke
`public.app_settings` (idempotent, tanpa DROP/ALTER TYPE, tidak menyentuh
fungsi FROZEN):
- `update_enabled boolean not null default false` â€” saklar fitur (default OFF
  supaya aman dirilis sebelum admin mengisi).
- `latest_version text not null default ''` â€” versionName terbaru (`X.Y.Z`).
- `min_version text not null default ''` â€” batas bawah; versi lokal di bawah
  ini â†’ popup wajib (force).
- `update_notes text not null default ''` â€” catatan rilis (bilingual, teks
  bebas dari admin).

**Klien:** `lib/services/app_update_service.dart` (fetch policy + banding
semver + deteksi installer Play + Play Core flexible/immediate),
`lib/providers/update_provider.dart` (state + snooze 24 jam),
`lib/widgets/update_dialog.dart`. Non-Play (apkpure/admin) â†’ tombol membuka
listing Play di browser.

**Apply:** via Management API (bukan `db push`), lalu catat versi di
`supabase_migrations.schema_migrations`. **Status: DITERAPKAN 2026-09-22** â€”
4 kolom terverifikasi ada; versi `20260922120000` tercatat. Detail + rollback
di `supabase/migrations/APPLIED_VIA_API.md`.

## 2026-09-22 â€” Privacy hardening: tutup bypass REST (`20260922100000`, `20260922110000`)

**Masalah (audit privasi):** setting privasi berfungsi di jalur RPC, tapi bisa
**dilewati via REST langsung** karena RLS `profiles_select`/`user_photos_select`
= `USING(true)` dan kolom sensitif masih ter-grant SELECT ke `anon`+`authenticated`.

**Yang bocor (terverifikasi live):**
- `user_photos.photo` â†’ readable anon+authenticated â†’ **bypass paywall**
  `get_user_photos_access`/`unlock_photo` (foto terkunci bisa dibaca gratis).
- `profiles.status` + `last_seen` â†’ bypass `presence_visibility`/`last_seen_visibility`.
- `profiles.avatar` â†’ bypass `profile_photo_visibility`.
- `story_tray` tidak cek `privacy_can_view(author,'story')` â†’ story "nobody"
  tetap muncul (avatar + count slide) di tray.

**Sudah aman sebelumnya (tidak disentuh):** `lat/lon/lat_gps/lon_gps/lat_ip/
lon_ip/ip_address/email/fcm_token/about` â€” tidak ter-grant; `app_shared_secret`
tak ada SELECT grant.

**Migrasi 1 â€” `20260922100000_privacy_harden_columns.sql`:**
- RPC baru (security definer, grant `authenticated` saja): `presence_for(uuid[])`,
  `avatar_for(uuid)`, `avatars_for(uuid[])`, `my_photos()` â€” semua menerapkan
  `privacy_can_view` + blokir + invisible.
- `revoke select (status, last_seen, avatar, share_location) on profiles`
  â†’ baca via RPC di atas.
- `user_photos`: **revoke table-level SELECT** dulu (grant `arwdDxtm` menutupi
  revoke kolom!) lalu `grant select (id, user_id, photo_preview, created_at)`.
  Foto asli hanya lewat RPC ber-gating (`get_user_photos_access`/`my_photos`).

**Migrasi 2 â€” `20260922110000_story_tray_privacy.sql`:**
- `story_tray` tambah `privacy_can_view(author, 'story', auth.uid())` +
  mask avatar via `profile_photo_visibility`.

**Dampak klien (diubah di commit yang sama):** `chat_service_presence.dart`
(getUserStatus/getUserLastSeen/fast-path/fallback) & `avatar_service.dart`
(get/refresh/prefetch) â†’ RPC; `getPhotos(own)` â†’ `my_photos`, foto orang lain â†’
`get_user_photos_access`; `auth_service_auth.dart` buang kolom revoked dari
copy profil; `user_info_screen.dart` pakai `getPhotosWithAccess`.

**Apply:** Management API (bukan `db push` â€” hang di mesin ini), tercatat di
`APPLIED_VIA_API.md`. **Verifikasi live:** `has_column_privilege('authenticated',
'profiles','avatar','SELECT')=false`, `('anon','user_photos','photo','SELECT')=false`,
`photo_preview`=true; REST anon/authenticated â†’ 403 utk kolom revoked, 200 utk
kolom aman; RPC â†’ 200 (anon RPC â†’ 401); masking avatar terbukti
(`everyone`=path, `nobody`='').

## 2026-09-21 - Penanda "peserta sudah dihapus" (20260921230000)

**Masalah:** saat akun dihapus (self-delete / admin hapus anon / hapus dummy /
purge), baris private_chats ikut DIHAPUS. Lawan bicara hanya melihat chat itu
hilang mendadak tanpa penjelasan. Lebih buruk: bila pengirim masih menyimpan
last_read_at lawan di cache lokal, pesan barunya tetap tampak **centang-2**
padahal tidak ada perangkat lawan yang menerimanya (read-receipt hantu).

**Solusi:** baris chat DIPERTAHANKAN + kolom penanda
private_chats.deleted_participants uuid[]. ISI PESAN DIHAPUS (privasi: isi
percakapan tidak tinggal di server atas nama user yang sudah pergi; sesuai
keputusan pemilik produk). Klien menampilkan label "Akun dihapus", mengunci
kirim, mengabaikan centang-2, dan user boleh menghapus chat itu sendiri.

**Yang ditambahkan:**
- Kolom private_chats.deleted_participants uuid[] not null default '{}'.
- Helper terpusat mark_chats_user_deleted(p_uid uuid) - idempoten
  (array_agg(distinct ...)): hapus seluruh isi percakapan di chat yang
  melibatkan uid, lalu pasang penanda + kosongkan metadata preview.
  **message_count SENGAJA tidak dinolkan** - klien menyaring messageCount > 0;
  kalau dinolkan, baris justru terbuang dari daftar dan label tidak pernah
  muncul (membatalkan tujuan fitur).
- Fungsi yang diubah agar memakai helper: delete_my_account,
  admin_delete_anon_user, admin_delete_dummy, purge_inactive_accounts.

**Tidak diubah:** admin_delete_chat (tombol hapus chat di monitor admin) -
itu penghapusan chat eksplisit, bukan penghapusan akun.

- Apply: Management API (bukan db push - hang di mesin ini), tercatat di
  schema_migrations (20260921230000). Lihat APPLIED_VIA_API.md.
- Verifikasi live: deleted_participants ada (col_ok=1),
  mark_chats_user_deleted ada (fn_ok=1), dan keempat fungsi penghapus
  akun memanggil helper (pakai_helper=true).


## 2026-09-21 â€” Fix guard `friend_requests` (`20260921220000`)

**Bug (severity tinggi, ditemukan saat menulis `supabase/tests/privacy_test.sql`):**
`_social_registered_guard()` ditulis untuk tabel `follows`
(`new.follower_id`/`new.followee_id`), tetapi trigger
`social_guard_friend_requests` memasang fungsi yang sama di `friend_requests`
(kolomnya `from_id`/`to_id`). Akibatnya **setiap** `INSERT`/`UPDATE`
`friend_requests` gagal `42703 record "new" has no field "follower_id"`.

Dampak nyata:
- `send_friend_request()` & `respond_friend_request()` selalu gagal.
- `_are_friends()` selalu `false` â†’ visibility privacy `'friends'` mati.
- `privacy_friends()` selalu kosong â†’ picker "Teman kecuali" selalu empty.

**Fix:** guard membaca kolom sesuai `TG_TABLE_NAME` (`friend_requests` â†’
`from_id`/`to_id`; selain itu â†’ `follower_id`/`followee_id`). Logika guard
tidak berubah: tetap menolak akun `is_registered = false` (kecuali dummy).

- Apply: Management API (bukan `db push`), tercatat di `schema_migrations`
  (`20260921220000`). Lihat `supabase/migrations/APPLIED_VIA_API.md`.
- Verifikasi live: insert teman antar-registered â†’ sukses; antar-anon â†’
  `SOCIAL_REGISTERED_ONLY` (perilaku benar, bukan lagi 42703).
- Test: `supabase/tests/privacy_test.sql` (23 assert, termasuk seed
  `friend_requests` accepted) + tripwire di `regression_test.sql`.
- `bash scripts/check_migrations.sh --all` â†’ OK bersih.

## 2026-09-20 â€” Privacy: 5 opsi + "kecuali" teman/anon (`20260920130002`â€“`0004`)

Uji coba di HP menemukan 3 bug pada privasi:

1. **Daftar "kecuali" kosong walau punya teman.** Enforcement memakai
   `_are_friends` (friend_requests accepted) sementara aplikasi memakai
   mutual follow â†’ tidak sinkron. Ditambah `privacy_friends()` (`0002`),
   lalu disamakan ke mutual follow lewat `_privacy_are_friends()` (`0003`).
2. **Semantik "kecuali" salah.** Dulu `except` = "SEMUA orang kecuali
   daftar" sehingga non-teman ikut melihat. Dipisah tegas (`0004`):
   `everyone_except` (semua, kecuali daftar) vs `friends_except` (teman,
   kecuali daftar). Nilai lama `except` dimigrasi ke `friends_except`.
3. **Daftar kecuali hanya teman.** `privacy_excludable_users()` kini
   mengembalikan **teman + anon yang pernah chat** (badge "Anon"), dan
   kedua opsi "kecuali..." bisa memilih keduanya.

- `privacy_can_view()` diperluas jadi 5 cabang; `get_online_users()`
  memakai perhitungan set-based agar listing online tidak lambat.
- Hasil uji live: `privacy_friends()` = 1 (SimpleMe),
  `privacy_excludable_users()` = 37 kandidat.
- Test: `supabase/tests/privacy_test.sql` (17 assert) + 23 test Flutter
  (`test/privacy_*_test.dart`) lulus; `flutter analyze` 0 error.

## 2026-09-20 â€” Privacy fixes (`20260920130001`)

Hasil cek ulang menemukan 4 regresi yang lalu diperbaiki:

1. `nearby_users` memakai `order by 12` padahal hanya 11 kolom â†’ error saat
   dipanggil. Dikembalikan ke `order by 11 asc`.
2. `get_online_users` terlanjur mencabut akses `anon` (perilaku lama:
   `authenticated, anon`). Dipulihkan, dan filter privacy di-INLINE (bukan
   fungsi per baris) supaya listing online tidak melambat.
3. `profile_public` kehilangan `share_location` + `points` milik sendiri â€”
   berdampak ke toggle "bagikan lokasi" di Nearby dan fallback bonus login.
   Dikembalikan khusus untuk pemilik (`about` tetap kosong bagi non-pemilik).
4. `mark_chat_read` saat read-receipt OFF tidak menolkan `unread_counts`
   penerima â†’ badge tidak pernah hilang. Sekarang badge SELALU dinolkan;
   hanya `last_read_at` yang tidak ditulis sehingga centang biru tetap aman.

- Helper `privacy_can_view` dan seluruh RPC privacy tetap dipakai.
- Test: `schema_sync_test.sql` (26 assert) + `test/privacy_provider_test.dart`
  dan `test/privacy_settings_test.dart` lulus.
- `bash scripts/check_migrations.sh --all` â†’ OK bersih.

## 2026-09-20 â€” Privacy settings foundation (`20260920130000`)


- Menambahkan visibility privacy untuk presence, last seen, foto profil,
  about, story, dan read receipts.
- Menambahkan tabel pengecualian teman per pemilik dan field privacy.
- Menambahkan RPC `my_privacy_settings`, `update_privacy_settings`,
  `replace_privacy_exclusions`, dan helper `privacy_can_view`.
- UI `Profile > Pengaturan > Privasi` sudah tersedia dengan pilihan Semua
  orang, Teman, Teman kecuali, dan Tidak ada.
- Default semua visibility tetap `everyone`; read receipts tetap aktif.

## 2026-09-20 â€” Restore guard `ai_always_online` (`20260920120002`)

- **Masalah:** `ai_reply_enqueue` live sudah memiliki pengecualian
  `ai_always_online`, tetapi migration `20260915090000` yang terakhir
  mendefinisikannya di repo belum membawa cabang tersebut.
- **Perbaikan:** migration restore baru mengambil perilaku dari snapshot live,
  mempertahankan toggle AIâ†”AI, `ai_always_reply`, rate limit, logging, dan
  guard agar dummy `ai_always_online` tidak diturunkan ke `idle`.
- **Apply:** diterapkan via Supabase Management API dan versi
  `20260920120002` sudah dicatat di `schema_migrations`.
- **Verifikasi:** `scripts/snapshot_functions.sh` menyimpan 30 fungsi;
  `bash scripts/check_migrations.sh --all` menghasilkan `OK bersih`.

## 2026-09-20 â€” Story viewer inline reply, like, dan share (`20260920120001`)

- **UI:** story milik orang lain memakai kotak foto yang sama dengan composer;
  balasan awalnya berupa tombol di dalam foto, lalu membuka field yang bisa
  digeser bebas di dalam kotak foto. Saat mengetik, tombol send tampil bersama
  like dan share.
- **Like:** `story_likes` + RPC `toggle_story_like(uuid)` menyimpan toggle
  like per user/story. `story_slides()` mengembalikan `like_count` dan
  `liked`; `story_viewers()` mengembalikan penonton yang memberi like.
- **Share:** memakai share sheet HP melalui `share_plus`, tanpa data sensitif.
- **Server:** migrasi diterapkan via Supabase Management API dan versi
  `20260920120001` sudah dicatat di `schema_migrations`. Snapshot FROZEN
  `story_slides` diperbarui dari fungsi live.
- **Verifikasi:** `test/story_social_io_test.dart` dan
  `test/story_provider_test.dart` lulus.

## 2026-09-21 â€” Tab Terhapus: tampilkan anon pending + hapus anon (`20260921210000`)

**Kebutuhan:** di tab "Terhapus", tampilkan BERSAMAAN user terhapus (arsip)
dan user anon yang belum terhapus, dan admin bisa menghapus anon itu supaya
nickname-nya bebas dipakai.

**Sebelumnya:** `admin_list_deleted` hanya membaca `deleted_users` (arsip).
Menghapus anon hanya mungkin lewat `cleanup_stale_anonymous` (>7 hari) atau
`claim_nickname` â€” nickname tertahan sampai 7 hari.

**Perbaikan:**
- `admin_delete_anon_user(p_uid)` â€” hapus 1 user anon: arsip dulu
  (`fn_archive_deleted_user`, reason `admin_delete`), bersihkan
  room_presence/blocks/reports/user_photos/devices/location/contact + chat
  privat, lalu `profiles` & `auth.users`. Menolak REGISTERED & DUMMY
  (cek DUMMY lebih dulu karena dummy ber-`is_registered=true`).
  `coin_ledger` append-only â†’ trigger `coin_ledger_no_delete` dimatikan
  sementara (pola `admin_delete_dummy`).
- `admin_list_deleted(p_limit,p_offset,p_include_pending)` â€” tambah item
  `pending` (anon belum dihapus, `pending=true`, `deleted_at=null`),
  diurut `last_seen`. Signature 2-arg di-DROP.
- Client: service `deleteAnonUser` + `listDeleted(includePending)`,
  provider `deleteAnonUser` (refresh otomatis), UI filter
  Semua/Terhapus/Belum dihapus + badge oranye + tombol hapus di detail.

**Verifikasi live (rollback):** anon `caritemen` â†’ profil & auth terhapus,
arsip 1 baris; user terdaftar â†’ `REGISTERED`; dummy â†’ `DUMMY`.
List: 11 arsip + 84 anon pending = 95 total (sebelumnya 11).

## 2026-09-21 â€” Lokasi: GPS dipisah dari IP + history diperbaiki (`20260921200000`)

**Dua bug nyata (terukur di live DB):**
1. `user_location_history` **0 baris** padahal 66 user ber-`loc_source='gps'`.
   Sebab: migrasi `20260815150000` membuat OVERLOAD 4-arg `update_my_location`
   TANPA logika `insert ... history`; client memanggil yang 4-arg â†’ history
   tidak pernah tercatat.
2. **GPS tertimpa IP** â€” saat GPS gagal fix, fallback IP menulis ke
   `profiles.lat/lon` yang sama â†’ koordinat GPS terakhir hilang.

**Perbaikan:**
- Kolom terpisah `lat_gps/lon_gps/gps_updated_at` + `lat_ip/lon_ip/ip_updated_at`.
  IP **tidak menimpa** GPS; `lat/lon/loc_source` (dibaca peta admin &
  `nearby_users`) = GPS bila ada, else IP â†’ kontrak pembaca tidak berubah.
- Satu jalur RPC `update_my_location` (overload lama di-DROP) yang SELALU
  mencatat history untuk gps & ip.
- Backfill data lama ke kolom sesuai `loc_source`.
- `admin_location_sources()` untuk ringkasan GPS/IP/history.
- Client: pencatatan lokasi hanya saat **online** (`_isLocationEligible`) â€”
  idle/invisible/dummy/banned tidak menulis â†’ yang tersimpan adalah lokasi
  terakhir saat benar-benar aktif.

**Verifikasi live:** GPS (-6.2,106.8) lalu IP (-7.9999,110.9999) â†’
`lat/lon` tetap GPS, `lat_ip/lon_ip` terisi, history 2 baris (gps+ip).

`nearby_users` FROZEN â€” tidak disentuh.

## 2026-09-21 â€” `install_id` pindah ke MediaDrm (`20260921190000`)

**Alasan:** `install_id` lama (`android-<ANDROID_ID>`) berubah saat signing key
/ user profile berbeda â†’ device yang sama tampil sebagai device baru (device
ter-exclude "muncul lagi"). MediaDrm (Widevine) `deviceUniqueId` stabil per
perangkat FISIK: tahan reinstall, ganti keystore, Dual Apps/Second Space.

**Implementasi:**
- Kotlin `MainActivity.mediaDrmDeviceId()` â†’ method channel `deviceUniqueId`.
- Dart `ScreenSecureService.deviceUniqueId()`; `DeviceInfoService.installId()`
  â†’ `drm-<hex>`, fallback `android-<ANDROID_ID>` bila Widevine tak ada.
- `upsert_device` (9-arg) menerima `p_legacy_install_id`: memigrasi baris lama
  milik user yang sama **in-place** + membuang duplikat brand+model yang sama.
  Signature lama (7-arg & 8-arg) di-DROP dulu agar tidak jadi overload.

**Verifikasi live:** HP `24129PN74G` â†’ baris `drm-e21f475d9d83113fb46e08f3547b60c5`
(1.2.43-admin); baris `android-2f218335e9fd56d5` milik uid yang sama
**digantikan**, bukan bertambah (tidak ada duplikat).

## 2026-09-21 â€” INSIDEN: device ter-exclude "muncul lagi" (`20260921170000` + `20260921180000`)

**Gejala:** admin exclude 1 HP, tapi device yang sama **muncul lagi** di tab
Perangkat dengan install_id BERBEDA.

**Akar masalah:** `install_id` = `android-<ANDROID_ID>`, dan Android 8+
meng-scope `ANDROID_ID` ke **(device + user profile + app signing key)**.
Terbukti di DB: model `24129PN74G` punya DUA install_id â€”
`android-2f218335e9fd56d5` (1.2.16â†’1.2.43) dan `android-e29a2f7c3e9624c6`
(hanya 1.2.40). Jadi exclude berbasis device **rapuh**.

**Perbaikan dua arah:**
1. `20260921170000_admin_exclude_cascade_uids.sql`:
   - `admin_list_devices` kini memakai `admin_excluded_uids()` (device **dan**
     uid manual) â€” sebelumnya hanya `excluded_devices`.
   - RPC baru `admin_exclude_device_cascade(p_install_id)`: exclude device
     **sekali** menambahkan semua uid yang pernah login di device itu ke
     `excluded_uids` â†’ exclude tahan walau install_id berubah.
   - Backfill: uid dari device yang sudah ter-exclude dimasukkan (2 â†’ 17 uid).
2. `20260921180000_admin_unexclude_uid_sync.sql`:
   - `admin_set_excluded_devices` menyinkronkan `excluded_uids`: uid yang
     device-nya tidak lagi ter-exclude **dibuang**, tapi uid tanpa baris
     device (anon manual) **dipertahankan**.

**Verifikasi (live `fohcucyyejdryryoxitm`):** cascade 17â†’18 uid; un-exclude
18â†’17 uid + device kembali 3; `admin_list_devices` total 44 baris â†’ 29
(15 milik uid ter-exclude disembunyikan).

**Aturan:** `admin_stats_detail` FROZEN â€” tidak disentuh. Snapshot
`functions.sql` tidak memuat `admin_list_devices`, jadi tidak perlu update.

Setiap migrasi yang di-apply atau di-rename WAJIB dicatat di sini supaya AI/dev
berikutnya tahu. Format: tanggal | versi | aksi | catatan.

## 2026-09-21 â€” INSIDEN: `delete_my_account` gagal untuk user ber-koin (`20260921160000_delete_my_account_ledger_fix.sql`)

**Gejala:** user dengan riwayat koin menekan "Hapus Akun" â†’ error
`coin_ledger is append-only`. Terdampak **177 user** (semua yang punya ledger).
Melanggar syarat Google Play (akun harus bisa dihapus).

**Akar:** `20260911000000_delete_my_account.sql` memanggil
`delete from public.coin_ledger` tanpa menonaktifkan trigger append-only
`coin_ledger_no_delete`. Fungsi sah lain (`admin_delete_chat`, hapus dummy,
purge) memakai `set local session_replication_role = 'replica'` â€” pola TERLEWAT.

**Fix:** bungkus hapus ledger+dummy-poin dengan toggle `session_replication_role`
(replica â†’ origin), persis pola `20260815040000_admin_delete_chat_coinledger_fix.sql`.
Definisi diambil dari LIVE, hanya menambah blok itu.

Verifikasi: `delete_my_account` memuat `session_replication_role` (true);
simulasi hapus ledger user ber-koin â†’ sukses (sebelumnya DITOLAK); migrasi
tercatat di `schema_migrations`. `check_migrations --all` hanya FAIL
pre-existing `ai_reply_enqueue` â€” bukan dari migrasi ini.

## 2026-09-21 â€” INSIDEN: semua pendaftaran gagal (`42501 permission denied for table profiles`)

**Gejala:** login/register anon, Google, & email semuanya gagal; Auth sign-in
sendiri sukses (token terbit) tapi `registerProfile()` ditolak server.

**Akar:** `20260915120000_security_hardening.sql` mencabut SELECT level-tabel
`public.profiles` dan hanya memberi grant kolom publik â€” **tanpa**
`email, ip_address, fcm_token, lat, lon`. PostgREST `upsert`
(`ON CONFLICT DO UPDATE`) butuh SELECT pada KOLOM YANG DITULIS, sehingga upsert
yang menyertakan kolom sensitif â†’ `42501`. Ini pola regresi yang sama dengan
insiden `20260812200000` (direvert oleh `20260812230000`).

**Keputusan:** perbaiki di **KLIEN**, bukan melonggarkan grant (hardening tetap
utuh â€” kolom sensitif tidak bisa di-SELECT publik):
- `auth_service_profile.dart` `registerProfile()`: upsert **kolom publik saja**
  + `update()` terpisah untuk `fcm_token`/`email`/`ip_address` (UPDATE tidak
  butuh SELECT kolom tsb; RLS `profiles_update_own` tetap berlaku).
- `auth_service_auth.dart` `linkGoogleProfile()`: idem (upsert `old` publik,
  email via UPDATE terpisah).

**Tidak ada migrasi DB** (murni klien). Verifikasi HTTP live: anon + email
register â†’ upsert 201/200, update sensitif 204 (sebelumnya 403).

**Pelajaran:** setiap kali `grant select (kolom...)` dipersempit di `profiles`,
WAJIB cek jalur `upsert` klien â€” upsert butuh SELECT semua kolom yang ditulis.
Lihat `lib/services/auth_service_profile.dart` (komentar guard).

## 2026-09-21 â€” Fitur mention `@` (`20260921120000_mentions.sql`)

Apply via Management API + recorded. **Tidak menyentuh fungsi FROZEN**;
hanya menambah kolom dan satu fungsi/trigger baru.

| Objek | Isi |
|---|---|
| `messages.mentions` | `jsonb not null default '[]'` â€” `[{"uid","name"}]` per pesan room/grup |
| `private_messages.mentions` | idem untuk private 1:1 |
| `notify_mention_room()` + trigger `notify_mention_room_trg` | `AFTER INSERT ON messages` â€” push TERARAH hanya ke uid yang di-mention (kecuali sender), token dari `user_devices` â†’ fallback `profiles.fcm_token`, `type='mention'` + `toUid` |

`@all` di-ekspansi di KLIEN menjadi daftar uid eksplisit (hanya private
room/grup oleh owner/admin, cap 100 uid) â€” di global room `@all` dimatikan
total. Private 1:1 sudah punya `notify_private_message` per pesan, jadi
mention di sana hanya highlight (tanpa push tambahan).

Verifikasi: `information_schema.columns` punya `mentions` di kedua tabel;
`pg_trigger` punya `notify_mention_room_trg`; `schema_migrations` memuat
`20260921120000`. Edge `send-push` dideploy ulang (`--use-api`) dengan
`'mention'` ditambahkan ke `dataOnlyTypes`.
`check_migrations --all` FAIL pre-existing lapis 5 (`ai_reply_enqueue`/
`ai_always_online`) â€” bukan dari migrasi ini.

## 2026-09-19 â€” Retensi call otomatis: cron `chatyuk-call-sweep` (`20260919094500_call_sweep_cron.sql`)

Apply via Management API + recorded. **Tidak menyentuh fungsi FROZEN**
(`admin_sweep_calls` bukan anggota `scripts/frozen_functions.txt`) dan tidak
mengubah definisi fungsi/tabel/policy apa pun â€” hanya menjadwalkan.

| Objek | Isi |
|---|---|
| Cron `chatyuk-call-sweep` | `*/5 * * * *` â†’ `select public.admin_sweep_calls()` (idempotent: `unschedule` dulu bila ada) |

**Masalah:** `admin_sweep_calls()` sudah benar (akhiri `ringing` >90 dtk,
`answered` tanpa heartbeat >75 dtk, hapus `call_signals` call selesai >1 jam)
tetapi hanya terpanggil saat admin membuka panel (`admin_service.dart`). Untuk
user biasa: call zombie menggantung & `call_signals` menumpuk. Bukti DB saat
review: 436 baris `calls`, 81 baris `call_signals` tapi **2.160 kB**.

Verifikasi: `select jobname,schedule,active from cron.job where
jobname='chatyuk-call-sweep'` â†’ `*/5 * * * *`, `active=true`;
`schema_migrations` memuat `20260919094500`.
`check_migrations --all` FAIL pre-existing lapis 5 (`ai_reply_enqueue`/
`ai_always_online`) â€” bukan dari migrasi ini.

## 2026-09-19 â€” Dummy idle hilang di app: RPC `dummy_uids()` (`20260919082500_dummy_uids_rpc.sql`)

Apply via Management API + recorded. Tidak menyentuh fungsi FROZEN, tabel,
policy, atau grant yang ada (murni tambah 1 RPC + grant execute).

| Objek | Isi |
|---|---|
| `dummy_uids()` | `SETOF uuid`, `SECURITY DEFINER`, `STABLE` â€” daftar `uid` dummy_accounts; `GRANT EXECUTE` ke `authenticated, anon` |

**Masalah:** di app hanya Sarah (online) tampil, Dhanu (idle) hilang â€” padahal
di admin keduanya ada, dan Dhanu sempat muncul lalu hilang lagi (flapping).
Akar: `dummy_accounts` RLS admin-only (`dummy_admin_all`) â†’ select langsung
dari HP selalu 0 baris (RLS, bukan error) â†’ `_fetchDummyUids()` = set kosong
â†’ `filterRpcOnlineRows` menggugurkan Dhanu sebagai "idle zombie" (idle tanpa
socket hanya lolos via daftar dummy). Online lolos tanpa syarat â€” makanya
Sarah tidak pernah terpengaruh.

**Client:** `_fetchDummyUids()` (`chat_service.dart`) kini `_sb.rpc('dummy_uids')`
(PostgREST kembalikan array uuid â†’ `'$r'` per elemen). Bentuk respons beda
dari `.select()` (bukan Map) â€” jangan kembalikan ke `(r as Map)['uid']`.

**Test:** assert baru di `supabase/tests/contract_test.sql` (`dummy_uids() ada`).

Verifikasi: `select '44d9832a-...'::uuid in (select dummy_uids())` â†’ true;
`flutter analyze` 0 error/warning; `flutter test` 241/241 hijau.
`check_migrations --all` FAIL pre-existing lapis 5 `ai_reply_enqueue`/
`ai_always_online` (sudah gagal sebelum migrasi ini â€” bukan dari migrasi ini).

## 2026-09-18 â€” Optimasi performa story (`20260918120000_story_perf.sql`)

Apply via Management API + recorded. Tidak menyentuh fungsi FROZEN.
Snapshot diregenerasi (hanya berubah baris timestamp).

| Objek | Isi |
|---|---|
| `idx_story_views_story_viewer` | Index `(story_id, viewer_id)` â€” percepat cek "sudah dilihat?" per slide saat `story_views` membesar |
| `mark_story_seen_bulk(uuid[])` | RPC baru â€” tandai banyak slide dalam 1 round-trip; guard visibility/blocks sama seperti `mark_story_seen`; `on conflict do nothing` (idempoten) |

### âš ï¸ `story_tray` SENGAJA TIDAK diubah (rewrite JOIN = REGRESI)

Rencana awal: ubah subquery per-baris (N+1) di `story_tray` jadi
`LEFT JOIN profiles` + `DISTINCT ON` thumb terbaru. **Sudah diukur di DB
live dan hasilnya LEBIH LAMBAT** â€” jadi di-revert ke bentuk asli:

| Skenario | Subquery (asli) | JOIN (rewrite) |
|---|---|---|
| Data asli, 2 author | **0.082 ms** | 0.157 ms |
| Simulasi 300 author / 1200 slide | **29.5 ms** | 51.0 ms |

(per panggilan, rata-rata 100â€“300 iterasi)

Hasil kedua versi **identik** (diverifikasi: 2 author, 0 baris beda di kedua
arah) â€” jadi tidak ada alasan menanggung lambatnya. Planner PostgreSQL sudah
menangani subquery skalar ini dengan baik; JOIN + DISTINCT ON menambah
materialisasi yang tidak perlu.

**Jangan "optimalkan" `story_tray` lagi tanpa mengukur dulu.**

Verifikasi: index ada, RPC ada, `story_tray()` tetap 2 author.
`run_sql_tests.sh` semua lolos. `check_migrations --all` FAIL pre-existing
`ai_reply_enqueue`/`ai_always_online` (bukan dari migrasi ini).

## 2026-09-17 â€” Centang-2 di preview list Pesan (kolom `last_sender_id`)

Migrasi `20260917180000_last_sender_id.sql` SUDAH APPLY via Management API + recorded
di `schema_migrations`. Menyentuh FROZEN `handle_new_private_message` (header ada,
snapshot di-regenerate â€” diff hanya stamp + 1 baris `last_sender_id`, tanpa cabang hilang).

| Objek | Isi |
|---|---|
| `private_chats.last_sender_id` (uuid, nullable) | Pengirim pesan terakhir; diisi trigger tiap pesan baru; backfill 50/50 chat berisi (0 chat berisi tanpa sender) |
| Trigger `handle_new_private_message` | Tambah `last_sender_id = new.sender_id`; cabang preview image/view_once/coin/gift + unread + last_read dipertahankan |

UI: preview pesan terakhir di card list Pesan (`private_chats_screen.dart`) kini
diawali `âœ“âœ“` bila pesan terakhir dariku â€” biru (`primary`) kalau lawan sudah baca
(`lastMessageAt <= lastReadAt[lawan]`), abu kalau belum; tanpa centang bila dari lawan.
Model `PrivateChatInfo.lastSenderId` (fromMap/toMap/copyWith + `_rowToPrivateChat`).

Verifikasi: `flutter analyze` 2 file 0 error 0 warning (infos pre-existing);
`flutter test` 227/227 hijau; `run_sql_tests.sh notif_chat_test.sql` lolos (2 assert baru);
`check_migrations --all` FAIL pre-existing lapis 5 `ai_reply_enqueue`/`ai_always_online`
(sudah gagal di HEAD bersih sebelum migrasi ini â€” bukan dari migrasi ini).

## 2026-09-17 â€” Fitur: long-press ala WA (reaksi + bintang + teruskan) â€” private & room

Migrasi `20260917000000_message_reactions_stars.sql` SUDAH APPLY via Management API.
Tabel baru saja, tidak menyentuh fungsi FROZEN.

| Objek | Isi |
|---|---|
| `message_reactions` | Satu baris = satu user + satu emoji (`chat_type` private/room, `chat_id`, `message_id`, `user_id`, `emoji`, unique per kombinasi) |
| `starred_messages` | Bintang per-user (`user_id`, `chat_type`, `chat_id`, `message_id`, unique per user+pesan) |
| `private_messages.is_forwarded` / `messages.is_forwarded` | Flag label "Diteruskan" di bubble |

UI: tahan pesan â†’ header jadi toolbar (balas/bintang/hapus/teruskan/â€¢â€¢â€¢) + bar emoji
(ðŸ‘ â¤ï¸ ðŸ˜‚ ðŸ˜® ðŸ˜¢ ðŸ™ ðŸ˜ +) mengambang di atas bubble; tap = multi-seleksi.
Badge reaksi + ikon bintang + label Diteruskan tampil di bubble.
Forward: sheet pilih chat/room â†’ kirim ulang dengan `is_forwarded=true`.

| File | Perubahan |
|---|---|
| `lib/services/message_reaction_service.dart` | Baru: toggle/watch reaksi & bintang |
| `lib/widgets/message_reaction_bar.dart` | Baru: `ReactionBar`, `ReactionBadge`, sheet emoji tambahan |
| `lib/widgets/forward_picker_sheet.dart` | Baru: picker chat/room tujuan teruskan |
| `lib/models/message_model.dart` | Tambah `isForwarded` (fromMap/toMap/copyWith) |
| `lib/services/chat_service.dart` + `chat_stream_session.dart` + `providers/chat_provider.dart` | Select + insert `is_forwarded` |
| `lib/widgets/private_chat_message.dart` | `MessageBubble`: `selected`, `reactions`, `starred`, `onTapSelect`, label Teruskan, badge reaksi |
| `lib/screens/private_chat_screen.dart` + `room_chat_screen.dart` | Mode seleksi WA: AppBar toolbar, reaction overlay, aksi balas/bintang/salin/hapus/teruskan/edit, `PopScope` back = batal seleksi |
| `lib/config/strings.dart` | 11 getter bilingual baru (menuForward/menuStar/menuUnstar/menuCopy/msgMessageCopied/msgStarred/msgUnstarred/msgForwarded/forwardTitle/forwardSearchHint/msgForwardedLabel/msgReactionFailed) |
| `supabase/tests/schema_sync_test.sql` | 4 assert baru utk 2 tabel + 2 kolom |

Verifikasi: `flutter analyze` file terkait 0 error 0 warning (1 warning pre-existing di
`admin_chat_view_screen.dart:513` + FAIL pre-existing `check_migrations` lapis 5
`ai_reply_enqueue`/`ai_always_online` â€” bukan dari migrasi ini);
`flutter test` 216/216 hijau; tabel + kolom terverifikasi ada di DB live.

## 2026-09-16 â€” Fitur: swipe-to-reply (geser kanan = balas) â€” private & grup

Tanpa migrasi SQL. Murni Dart.

| File | Perubahan |
|---|---|
| `widgets/private_chat_message.dart` | Widget baru `SwipeToReply` (publik) + param opsional `MessageBubble.onSwipeReply` |
| `screens/private_chat_screen.dart` | `onSwipeReply` diisi untuk pesan LAWAN saja (`isMe \|\| isDeleted` â†’ null) |
| `screens/room_chat_screen.dart` | `SwipeToReply(enabled: m.senderId != auth.uid && !m.isDeleted)` membungkus `_MessageBubble` |

**Cara kerja:** `onHorizontalDragUpdate` menggeser bubble 0â€“72 px ke kanan; ikon
reply di kiri muncul & menguat; lepas â‰¥48 px â†’ masuk mode balas, <48 px â†’ balik.

**Jebakan yang sudah dihindari:**
- Pesan SENDIRI tidak di-swipe â€” swipe kanan dari tepi kiri = swipe-back sistem
  iOS, kalau aktif user tidak bisa keluar chat.
- Pakai `onHorizontalDrag*`, BUKAN `Dismissible` (Dismissible menggeser permanen
  & bentrok dengan long-press action bar).
- `SwipeToReply` wajib PUBLIK â€” sempat `_SwipeToReply` sehingga gagal dipakai
  dari `room_chat_screen.dart`.

Detail invariant: `docs/FEATURE_MAP.md` Â§3b.

## 2026-09-16 â€” Perf: buka private chat instan + centang-2 instan + typing ikut scroll

Tanpa migrasi SQL. Murni Dart â€” detail invariant di
`docs/FEATURE_MAP.md` Â§3a (baca dulu sebelum menyentuh file di bawah).

**Masalah (dilaporkan user):**
1. Buka private chat ada jeda (tidak seperti WhatsApp).
2. Centang-2 muncul belakangan â€” padahal kalau sudah pernah dibaca harusnya
   langsung centang-2.
3. Bubble typing tidak ikut scroll bersama pesan.

**Akar masalah & perbaikan:**

| File | Perubahan |
|---|---|
| `private_chats_screen.dart` | Transisi `PageRouteBuilder` 320 ms â†’ 150 ms (sempat 0 ms, dikembalikan karena terasa "patah"); tambah `_warmTopChats()` â€” 6 chat teratas di-prefetch ke memori saat list dimuat |
| `online_users_screen.dart`, `story_viewer_screen.dart` | Transisi ke `PrivateChatScreen` 320 ms â†’ 150 ms |
| `chat_stream_session.dart` | `controller.onListen` = **replay** `_current`. Broadcast tidak menyimpan emit terakhir; emit memori di `initState` hilang sebelum `StreamBuilder` subscribe |
| `private_chat_screen.dart` | `_primeReadFromCache()` baca 2 sumber memori (snapshot live `_privateChatsLast` + `peekRawList`), ambil terbaru â€” sebelumnya hanya `peekRawList` yang bisa basi |
| `private_chat_screen.dart` | `_otherLastRead` jadi **monoton maju** (di stream & kv): nilai null/lebih tua tidak boleh menurunkan centang-2 |
| `private_chat_screen.dart` | `isRead` pakai `!msg.timestamp.isAfter(...)` (`<=`) â€” sebelumnya `isBefore` ketat, pesan dengan timestamp sama tidak ikut centang-2 |
| `private_chat_screen.dart` | Subscription non-kritis (`_subscribeStatus`, `_subscribeTyping`, `_chatInfoSub`, profil lawan, `markAsRead`) ditunda ke post-frame |
| `private_chat_screen.dart` | Toast bonus: `Future.microtask` ke-dobel tiap `build()` â†’ dijaga `_bonusToastScheduled` (sekali per buka chat) |
| `private_chat_screen.dart` | Bubble typing dipindah dari luar `ListView` jadi **item list paling bawah** (`itemCount + 1`, index 0 saat `reverse: true`) supaya ikut scroll |

**Catatan build (bukan migrasi):** flavor admin yang benar = `adminProd`
(bukan `admin`), karena ada dimensi env dev/prod. RK:

```sh
flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
flutter build apk --release --flavor adminProd -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=build/app/symbols
```

## 2026-09-15 â€” Story harian: expert dikecualikan + panel admin

| Versi | Aksi |
|---|---|
| 20260914150050_admin_get_dummy_stories.sql | RPC baru `admin_get_dummy_stories(p_uid,p_days)` â€” list story harian satu dummy (14 hari) + status terisi/kosong (panel admin) |

**Catatan:** awalnya `...150000` lalu di-rename karena bentrok dengan
`20260914150000_storage_ownership.sql` (session paralel).

**Fix terkait (bukan migrasi):**
- `ai-daily-life`: story harian HANYA untuk dummy `kind='regular'` â€” expert
  (Admin Chatyuk/CS) tidak dibuatkan story.
- `config.toml`: `[functions.ai-daily-life] verify_jwt=false`.
- **INSIDEN**: env `APP_SHARED_SECRET` edge â‰  `app_settings.app_shared_secret`
  â†’ cron `chatyuk-ai-daily-life` gagal diam-diam (pg_net anggap HTTP 200 sukses
  walau body `{"error":"unauthorized"}`). Disamakan via
  `supabase secrets set APP_SHARED_SECRET=<nilai app_settings>`; invoke manual
  kini `ok:true`.

## 2026-09-14 â€” Security: fix Storage IDOR + limit upload server-side

**Masalah (review ulang):** policy bucket `chat-photos` hanya cek
`auth.role() = 'authenticated'` tanpa ownership/path check â†’ IDOR: user
authenticated mana pun bisa overwrite/delete file user lain (avatar, gallery,
voice, story, post).

| Versi | Aksi |
|---|---|
| 20260914150000_storage_ownership.sql | Helper `storage_object_owner_ok(name)` (owner-or-admin per path) + ganti 4 policy bucket `chat-photos` (insert/update/delete wajib owner) + trigger `trg_chat_photos_guard` (whitelist `content_type` + limit 8 MB) |

**Catatan:** path layout mengikuti `storage_photo_service.dart`:
`avatars/<uid>_<ts>.jpg`, `gallery|posts|story|timeline/<uid>/<file>`,
`chat|voice/<chatId>/<file>` (chat/voice divalidasi sebagai peserta `private_chats`).
Admin lewat `is_admin_request()`. Tidak menyentuh fungsi FROZEN.

## 2026-09-14 â€” Audit performa: paginasi & hilangkan fetch tanpa limit

**Masalah:** beberapa RPC/query memuat SELURUH tabel tanpa limit â†’ lag (polling
admin tiap 15â€“30 dtk menarik ribuan baris).

| Versi | Aksi |
|---|---|
| 20260914130050_admin_list_dummies_page.sql | RPC baru `admin_list_dummies_page(p_limit,p_offset)` â€” paging daftar dummy (versi lama `admin_list_dummies()` TIDAK diubah) |
| 20260914140000_friend_request_pagination.sql | RPC baru `friend_request_inbox_page/outbox_page(p_limit,p_offset)` (versi lama tidak diubah) |

**Catatan:** `20260914130050` awalnya ditulis `...130000` lalu di-rename karena
bentrok timestamp dengan `20260914130000_ai_provider_models.sql` (session paralel).

## 2026-09-14 â€” Audit drift kode â†” DB: pulihkan fitur & sinkron pencatatan

**Masalah ditemukan (audit):** 3 fitur rusak di produksi karena migrasi ada di
repo tapi tak ter-apply; 38 versi sudah ter-apply tapi tak tercatat di
`schema_migrations` (drift pencatatan).

**Aksi â€” apply migrasi yang selama ini tertunda:**

| Versi | Fitur dipulihkan |
|---|---|
| 20260909000000_mute_archive_chats.sql | Bisukan & Arsipkan chat (kolom `muted_by`/`archived_by` + RPC `mute_private_chat`/`archive_private_chat`) |
| 20260908000000_room_gift.sql | Kirim gift di room live (RPC `send_room_gift`) |
| 20260914110000_dummy_kind.sql | Filter Expert/Regular di admin (kolom `kind` + `admin_list_dummies`) |
| 20260914110001_dummy_kind_experts.sql | Koreksi set EXPERT (5 akun: Admin Chatyuk, Dr Nara, HardwareExpert, Kang Modal, SoftwareExpert) |
| 20260914110002_expert_flags.sql | Admin Chatyuk `ai_always_reply=true`; HardwareExpert `long_answers=true` |

**Aksi â€” sinkron pencatatan:** 38 versi yang objeknya sudah ada di DB (diverifikasi
via probe `pg_proc`/`information_schema.tables`) dicatat ke
`schema_migrations`. Total kini 246 versi file bertimestamp tercatat (sebelumnya
205). Tidak ada lagi versi file yang belum tercatat.

**Obsolete (JANGAN apply â€” sengaja dihapus):**
- `20260819150001_calls_notify_trigger.sql` + `20260823155000_notify_call_trigger.sql`
  â†’ membuat trigger `notify_call_trigger` yang **redundan** dengan
  `notify_call_ringing_trigger`; sudah dihapus di `20260827000000_notif_fix.sql`.
  Fungsi `notify_call` memang tidak ada di DB (by design).

**Selaraskan kode ke skema (bukan ubah DB):**
- `messages.inserted_at` tidak ada â†’ kode diselaraskan ke `created_at`
  (`room_chat_screen.dart`, `group_media_screen.dart`).
- `room_presence.country/city` tidak ada â†’ pembacaan dihapus di
  `chat_service.dart` (kosongkan, tanpa query kolom nir-skema).

## 2026-09-14 â€” Lapis 6: perbaikan 8 timestamp duplikat

**Masalah:** `supabase_migrations.schema_migrations.version` adalah PRIMARY KEY,
tapi ada 8 pasang file migrasi dengan prefix timestamp SAMA â†’ file kedua tidak
dijamin ter-apply (bergantung urutan filesystem). Ini bikin drift lokalâ†”remote.

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

## 2026-09-14 â€” Lapis 3: harness test SQL

| Versi | Aksi | Catatan |
|---|---|---|
| 20260914100000_sql_test_harness.sql | applied + recorded | schema `supabase_tests` + `check()`/`report()`/`mk_dummy()` |

## 2026-09-27 â€” Dimensi foto post (feed proporsional ala Threads)

| Versi | Aksi | Catatan |
|---|---|---|
| 20260927000000_posts_image_dims.sql | applied + recorded | `posts.image_w/image_h/image_dims` + `create_post(p_image_dims)` + FROZEN `list_posts` output `images/imageW/imageH/imageDims` (4 baris ditambah, 0 dihapus) |

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

## 2026-09-14 â€” INSIDEN: guard mendeteksi regresi live (ai_always_online)

**Kejadian:** saat menerapkan Lapis 6 (apply ulang file migrasi yang di-rename),
`20260913180001_dummy_wake.sql` ter-apply â€” fungsi `ai_presence_tick` versi itu
**tidak punya blok `if ai_always_online`**, sehingga cabang Admin Chatyuk 24/7
hilang di DB live (persis pola regresi lama). Restore-nya ada di
`20260914020000_admin_chatyuk_always_online_restore.sql` yang tidak ikut ter-apply
(urutan).

**Deteksi:** `scripts/run_sql_tests.sh` (test `presence_test.sql`) GAGAL dengan
"definisi memuat cabang ai_always_online" + "always_online â†’ online". Guard
bekerja seperti desain.

**Perbaikan:** apply ulang `20260914020000` â†’ `ai_always_online` kembali (pos=389).
Semua 35 assert hijau kembali.

**Pelajaran (WAJIB):** setelah apply ulang file lama, **re-apply migrasi
"restore/patch" yang lebih baru** untuk fungsi yang sama, ATAU gunakan
`create or replace` dari snapshot terbaru sebagai sumber. Inilah alasan
frozen-functions guard + snapshot ada.

## 2026-09-24 â€” 20260924230000_admin_privacy_bypass.sql (APPLY)

- **Fitur:** toggle Bypass Privasi (Admin > Global Setting). ON + viewer admin
  â†’ `privacy_can_view()` true semua field (foto/status/last_seen/about/story).
  User biasa tidak terdampak (server cek `auth.email()`).
- **Isi:** kolom `app_settings.privacy_bypass_enabled` (default false);
  rewrite `privacy_can_view` (BUKAN frozen â€” tanpa header/snapshot);
  RPC `admin_set_privacy_bypass(p_enabled)` (guard admin); baca via
  `admin_get_point_settings` (full row).
- **Apply:** Management API + catat `schema_migrations`. Verifikasi: kolom
  false, RPC ada, pgTAP `privacy_bypass_test.sql` 7/7.

## 2026-09-26 â€” 20260926010000_location_history_dedupe.sql (APPLY)

- **Temuan:** `user_location_history` penuh ratusan baris koordinat identik
  (tulis tiap 1-2 dtk saat idleâ†’online flap; mis. 1389 baris/7 hari, 18 titik
  beda). Pengambilan GPS-nya benar (titik berubah saat bergerak).
- **Isi:** `profiles` lat/lon tetap update tiap panggilan; baris history
  hanya bila bergerak >50m (`earth_distance`) ATAU titik terakhir >30 mnt.
  Definisi fungsi disalin persis dari live (overload 4-arg dipertahankan).
- **Apply:** Management API + catat `schema_migrations`. Verifikasi:
  def memuat earth_distance + p_ip; cek matematika 0m vs 1135m OK.

## 2026-09-26 â€” 20260926040000_story_mute.sql (APPLY)

- **Fitur:** mute story ala IG (tahan tile tray â†’ Benamkan). Tile jadi
  transparan + pindah paling belakang, tanpa ring; viewer paging melewati
  yang dibenamkan (kecuali tile-nya diketuk sengaja).
- **Isi:** tabel `story_mutes` (RLS deny, tulis via RPC); RPC
  `mute/unmute_story_author` (guard auth, tolak self); rewrite
  `story_tray()` (BUKAN frozen): flag `muted`, `has_unseen` mati bila mute,
  urutan muted terakhir.
- **Apply:** Management API + catat `schema_migrations` (rename 2x karena
  tabrakan timestamp sesi lain: 020000â†’030000â†’040000). Verifikasi: RPC ada,
  pgTAP `story_mute_test.sql` 4/4.

## 2026-09-26 â€” 20260926110000_story_video.sql (APPLY)

- **Fitur:** story VIDEO pendek (maks 15 dtk, polos). Rekam tahan-shutter
  dari kamera app, preview + publish, viewer play + auto-advance durasi.
- **Isi:** kolom stories.media_type/video_path/duration_ms + CHECK;
  rewrite FROZEN create_story (+3 param defaults, validasi path story/ +
  durasi 1-15000ms), story_slides + story_tray (+kolom video/has_video);
  DROP overload lama (hindari PostgREST 300). Policy Storage tak berubah
  (bucket+owner agnostik ekstensi). RLS 10/hari + purge tak berubah.
- **Apply:** Management API + snapshot regenerate (diff aditif) + catat
  schema_migrations. Verifikasi: 1 overload, kolom ada, guard OK,
  pgTAP story_video_test.sql 7/7.

## Catatan story video â€” tanpa migrasi tambahan (pakai 20260926110000)

- Kompres 720p hemat (Â±3 MB) + poster JPEG di `image_path` (kolom lama,
  tanpa kolom `poster_path` baru, tanpa rewrite FROZEN tambahan).
- Cap pasca-kompresi 15 MB (client). Timeout download video 15â†’30 dtk.

## 2026-09-26 â€” 20260926120000_chat_photos_guard_video.sql (APPLY)

- **Masalah:** publish story video SELALU gagal (`gagal membagikan story`).
  Poster JPEG terupload sukses, video ditolak trigger `chat_photos_guard`
  (`Tipe file tidak diizinkan: video/mp4`) â€” guard hanya whitelist gambar+audio.
- **Isi:** tambah tipe video (mp4/quicktime/3gpp/mkv) + batas video 20 MB
  (non-video tetap 8 MB). Fail-closed tipe lain. Server-only, tanpa ubah APK.
- **Apply:** Management API + catat schema_migrations. Verifikasi:
  `pg_get_functiondef` memuat `video/mp4` âœ….

## 2026-09-26 â€” 20260926140000_messages_allow_location_type.sql (APPLY)

- **Fitur:** kirim LOKASI (ala WhatsApp) di private chat & room â€” koordinat
  JSON di kolom `text` (`{"lat":..,"lng":..,"label":".."}`), `type='location'`.
- **Masalah:** `private_messages_type_check` & `messages_type_check` belum
  memuat `'location'` â†’ insert ditolak check constraint.
- **Isi:** tambah satu nilai `'location'` ke kedua constraint (nilai lama
  dipertahankan; idempotent drop+add).
- **Apply:** Management API. Verifikasi (live): kedua constraint kini memuat
  `'location'` âœ… (query `pg_constraint`).

## 2026-09-27 â€” 20260927090000_update_manual_push.sql (APPLY)

- **Fitur:** tombol "Kirim Popup Update" di admin panel â€” admin memicu popup
  update manual (mis. user menekan "Nanti"/snooze, atau catatan penting baru).
- **Isi:** `app_settings.update_push_at timestamptz` (stempel push terakhir)
  + RPC `admin_push_update()` (SECURITY DEFINER, guard `is_admin_request()`,
  set `update_push_at = now()`). Grants: authenticated + service_role.
- **Alur klien:** saat app DIBUKA, klien banding `update_push_at` server vs
  waktu push terakhir yang dilihat (prefs). Lebih baru â†’ tampilkan popup
  walau versi sudah di-snooze. Tidak perlu app dibuka saat push.
- **Apply:** Management API. Verifikasi (live): kolom `update_push_at`
  (timestamptz) + fungsi `admin_push_update` ada âœ….

## 2026-09-27 â€” 20260927100000_profile_birthdate_phone.sql (APPLY)

- **Fitur:** Pengaturan â€º Akun â€” simpan **tanggal lahir asli** (date picker) +
  **nomor HP**.
- **Isi:** `profiles.birth_date date` + `profiles.phone text` (nullable) +
  constraint kewarasan (birth_date 1900..hari ini; phone `^\+?[0-9]{6,20}$`).
- **Privasi:** TIDAK ditambahkan ke RPC publik mana pun â€” hanya pemilik baris
  yang membaca (RLS). Tidak bocor ke user lain.
- **Apply:** Management API. Verifikasi (live): kedua kolom ada âœ….

## 2026-09-27 â€” 20260927120000_index_dedup_and_fix.sql (APPLY)

- **Tujuan:** optimasi index (skala jutaan user) â€” tanpa menyentuh fungsi,
  grant, RLS, atau semantik query apa pun.
- **Dasar audit LIVE** (`pg_indexes`/`pg_index`/`pg_stat_user_indexes`,
  stats_reset 2026-07-24 â€” jadi `idx_scan=0` valid, bukan index baru):
  1. `private_chats`: `idx_private_chats_participants_gin` **DAN**
     `private_chats_participants_gin_idx` â†’ definisi **IDENTIK**
     (`USING gin (participants)`) = duplikat persis.
  2. `private_chats.idx_private_chats_last_message_at_desc` (btree) ADA di file
     `20260829020000_perf_indexes.sql` tetapi **TIDAK ADA di live** (drift),
     padahal `private_chats.idx_scan` = 1,7jt & urutan list chat pakai
     `last_message_at desc` â†’ index ini PERLU ditambahkan.
- **Isi:** (a) ADD `idx_private_chats_last_message_at_desc` (additive, idempotent);
  (b) DROP `private_chats_participants_gin_idx` (duplikat persis, penanda `-- SAFE:`).
- **SENGAJA TIDAK di-drop:** `idx_story_views_story_viewer` â€” kolomnya = pkey,
  TETAPI **dikunci** `supabase/tests/story_test.sql` ('index â€¦ ada') sebagai
  kontrak. Sempat di-drop; test FAIL (19/20) â†’ **di-recreate** & file migrasi
  dikoreksi agar tidak menghapus index itu. Pelajaran: test suite menangkap
  penghapusan yang terlihat "aman" â€” hormati kontrak test.
- **Apply:** Management API `POST /v1/projects/{ref}/database/query`. Versi
  dicatat di `supabase_migrations.schema_migrations` (20260927120000).
- **Verifikasi live:**
  - EXPLAIN list chat â†’ `Index Scan using idx_private_chats_last_message_at_desc` âœ…
  - EXPLAIN RLS chat â†’ `Bitmap Index Scan on idx_private_chats_participants_gin` âœ…
    (duplikat yang di-drop tidak dipakai planner)
  - EXPLAIN story_views â†’ `Index Only Scan using story_views_pkey` âœ…
  - Total index: 163 â†’ 163 (add 1, drop 1, story index di-recreate).
  - `bash scripts/run_sql_tests.sh` â†’ **19/19 file lolos** (schema_sync 31/31,
    story_test 20/20). `check_migrations.sh --all` â†’ OK bersih.
- **Rollback:** `drop index idx_private_chats_last_message_at_desc;` +
  `create index private_chats_participants_gin_idx on public.private_chats using gin (participants);`
- **Backup definisi index sebelum ubah:** `/tmp/chatyuk_idx_backup/indexes_before.json` (163 baris).

## 2026-09-27 â€” 20260927130000_drop_useless_brin_index.sql (APPLY)

- **Tujuan:** lanjutan dedup index. Hanya buang index yang TERBUKTI tidak berguna
  & tidak dikontrak test. Tidak menyentuh fungsi/grant/RLS.
- **Dasar audit LIVE** (`pg_index`/`pg_stat_user_indexes`, stats_reset 2026-07-24):
  - `idx_private_chats_last_message_at_brin` (BRIN) `idx_scan=0`.
  - Kolomnya sama dengan btree `idx_private_chats_last_message_at_desc` (baru
    ditambahkan di `20260927120000`).
  - BRIN berguna hanya bila data TERURUT FISIK; `last_message_at` terus di-update
    ke `now()` â†’ urutan acak â†’ BRIN praktis tak pernah menang (scan=0). Tidak
    dikunci `supabase/tests/*`, tidak disebut fungsi/RPC â†’ drop aman.
- **Isi:** DROP `idx_private_chats_last_message_at_brin` (penanda `-- SAFE:`).
- **SENGAJA TIDAK di-drop** (meski terlihat "terliput" â€” semua idx_scan > 0,
  jadi masih aktif dipakai planner): `user_devices_user_idx` (scan=30.602),
  `idx_coin_ledger_bucket` (scan=18.618), `idx_coin_ledger_user` (94).
  Juga tidak di-drop (scan=0 tapi dipakai fitur): `idx_private_chats_{pinned,
  muted,archived}_by`, `idx_rooms_muted_by`, `idx_posts_country_boost_created`,
  `idx_blocks_reverse`, `user_devices_fcm_idx`, `idx_*_need_migrate`,
  `coin_ledger_pkey` (PRIMARY KEY).
- **Apply:** Management API. Versi dicatat di `schema_migrations` (20260927130000).
- **Verifikasi live:**
  - `pg_indexes` â†’ hanya `idx_private_chats_last_message_at_desc` tersisa âœ…
  - EXPLAIN list chat â†’ `Index Scan using idx_private_chats_last_message_at_desc` âœ…
  - Total index: 163 â†’ 162.
  - `run_sql_tests.sh` â†’ **19/19 file lolos**. `check_migrations.sh --all` â†’ OK.
- **Rollback:** `create index if not exists idx_private_chats_last_message_at_brin
  on public.private_chats using brin (last_message_at);`

## 2026-09-27 â€” Outbox Fase A: edge function `outbox-worker` (ADDITIVE, bukan migrasi)

- **Latar:** 15 fungsi live masih pakai `net.http_post` SINKRON di trigger
  (transaksi INSERT pesan menunggu HTTP round-trip). Tabel `public.outbox`
  sudah ada sejak `20260901020000` tapi **mati** (tak ada worker/cron).
- **Fase A (dilakukan sekarang â€” nol risiko):** deploy edge function
  `outbox-worker` (self-contained, tanpa import `_shared` â€” deploy Management
  API single-file tak sertakan folder itu). Worker: ambil batch `outbox`
  (`sent_at is null`, order id), teruskan `type='push'` â†’ `send-push`
  (header `x-app-secret`), set `sent_at=now()`; gagal â†’ biarkan null (retry);
  baris >24 jam dibuang (anti-backlog). Guard: `x-app-secret` ATAU service_role.
- **TIDAK mengubah perilaku apa pun:** tidak ada trigger yang menulis ke outbox,
  jadi outbox tetap kosong â†’ worker no-op. **Belum ada cron** yang memanggilnya.
- **Deploy:** Management API `POST /v1/projects/{ref}/functions/deploy?slug=outbox-worker`
  â†’ **ACTIVE v1**.
- **Verifikasi live:**
  - invoke worker saat outbox kosong â†’ `{"ok":true,"processed":0}` âœ…
  - insert 1 baris uji (token invalid) â†’ `{"processed":1,"failed":1}`, `sent_at` tetap null âœ…
  - baris uji dibersihkan â†’ `outbox count = 0` âœ…
- **Sisa (Fase B/C â€” BELUM dikerjakan, butuh uji E2E notif):** cron pemanggil
  worker (*/1m) + pindahkan trigger `notify_*` dari `net.http_post` sinkron ke
  `insert into outbox`. Sentuh fungsi FROZEN â†’ butuh header `-- menyentuh:` +
  regen snapshot + uji E2E dummy.

## 2026-09-27 â€” Outbox Fase B: cron worker + notify_mention_room â†’ outbox (APPLY)

- **Tujuan:** mulai memindahkan trigger notifikasi dari `net.http_post` SINKRON
  ke `insert into outbox` (transaksi tulis pesan tidak lagi menunggu HTTP).
- **Migrasi 1 â€” `20260927150000_outbox_worker_cron.sql`:** cron
  `chatyuk-outbox-worker` `* * * * *` memanggil edge `outbox-worker` via
  `net.http_post` (x-app-secret). Saat outbox kosong â†’ no-op.
- **Migrasi 2 â€” `20260927140000_notify_mention_via_outbox.sql`:** ganti
  `perform net.http_post(...)` â†’ `insert into public.outbox (type, payload)`
  di `notify_mention_room` (BUKAN FROZEN). **Logika lain 100% identik** (guard
  mentions, sender_display/avatar, room_name, v_body, loop user_devices,
  fallback profiles.fcm_token) â€” hanya cara kirim yang berubah. Dasar = definisi
  LIVE terbaru (`pg_get_functiondef`).
- **Apply:** Management API (cron dulu, baru trigger). Versi dicatat:
  `20260927140000` + `20260927150000`.
- **Verifikasi live:**
  - cron run: `succeeded` (2Ã— dalam 2 menit) âœ…
  - fungsi: `uses_outbox=true, uses_http=false` âœ…
  - **Uji E2E (dummyâ†’dummy, semua [TEST]):** insert device dummy (token FCM
    PALSU) + insert pesan room `Iran_general` dgn mention ke dummy target â†’
    **outbox terisi 1 baris** (`data.type=mention`, title=General, token target) âœ…
    â†’ jalankan worker â†’ `{"processed":1,"failed":1}` (token palsu ditolak FCM,
    tepat; token nyata akan `sent`) âœ…
  - data uji dibersihkan tuntas: msgs=0, devices=0, outbox=0 âœ…
  - `run_sql_tests.sh` â†’ **19/19 lolos** (mention_test 6/6). `check_migrations` OK.
- **Rollback:** re-apply `notify_mention_room` dari definisi lama
  (`/tmp/notify_mention_room_BEFORE.sql` atau migrasi `20260921120000_mentions.sql`);
  `select cron.unschedule('chatyuk-outbox-worker');`
- **CATATAN PENTING:** mulai sekarang, notif mention BERGANTUNG pada cron +
  edge `outbox-worker` aktif. Bila worker mati, mention tidak terkirim (tapi
  pesan tetap tersimpan â€” bukan data loss, hanya notif). Trigger lain
  (`notify_private_message`, `call_push`, dll) MASIH pakai `net.http_post`
  sinkron (belum dipindah).

## 2026-09-27 â€” Outbox Fase C: notify_private_message â†’ outbox (APPLY)

- **menyentuh: notify_private_message** (FROZEN).
- **Tujuan:** pindahkan jalur notif pesan 1:1 (paling sering) dari
  `net.http_post` sinkron ke `insert into outbox`.
- **Migrasi `20260927160000_notify_private_via_outbox.sql`:** ganti **kedua**
  `perform net.http_post(...)` (cabang `type='call'`/missed_call + cabang pesan
  biasa) â†’ `insert into public.outbox (type, payload) values ('push', ...)`.
  Logika lain 100% IDENTIK (dedup call 30 dtk, resolusi receiver dari
  participants, guard receiver_token, sender_display/avatar, v_body preview
  tipe image/video/voice/coin/gift/teks-200). Dasar = definisi LIVE terbaru.
- **Snapshot:** `scripts/snapshot_functions.sh` dijalankan (30/30 fungsi).
  `git diff supabase/snapshots/functions.sql` = **hanya 2 blok http_post â†’
  outbox + stamp @20260927160000**, 0 baris logika hilang (direview). Guardrail
  `check_migrations.sh --all` â†’ OK bersih.
- **Apply:** Management API. Versi dicatat `schema_migrations` (20260927160000).
- **Verifikasi live:**
  - fungsi: `uses_outbox=true, uses_http=false` âœ…
  - **Uji E2E (dummyâ†’dummy, semua [TEST]):** buat chat [TEST] dummy + isi
    `profiles.fcm_token` target (token PALSU) + insert pesan 1:1 â†’
    **outbox terisi** (`data.type=message`, title sender, token target) âœ… â†’
    worker â†’ `{"processed":1,"failed":1}` (token palsu, tepat) âœ…
  - data uji dibersihkan tuntas (msgs/chats/devices/outbox=0,
    `profiles.fcm_token` dipulihkan ke '') âœ…
  - `run_sql_tests.sh` â†’ **19/19 lolos** (notif_chat 10/10, mention 6/6). âœ…
- **Rollback:** re-apply definisi lama dari `/tmp/notify_private_message_LIVE.sql`
  atau migrasi `20260926150000_notif_video_label.sql` + regen snapshot.
- **âš ï¸ TEMUAN PENTING (belum diubah, butuh keputusan):** `notify_private_message`
  membaca **`profiles.fcm_token`**, BUKAN `user_devices.fcm_token`. Padahal
  `20260827000000` sudah mengosongkan `profiles.fcm_token`. Akibatnya notif
  pesan 1:1 hanya terkirim bila `profiles.fcm_token` terisi (klien lama) â€”
  device klien baru (`user_devices`) tidak menerima. BUKAN regresi dari
  perubahan ini (perilaku lama sudah begitu), tapi titik lemah yang perlu
  dirapikan (arahkan ke `user_devices` + fallback profiles) â€” KANDIDAT LANJUTAN.
- **Fungsi live `net.http_post` sinkron: 14 â†’ 13.**

## 2026-09-27 â€” Outbox Fase D: fix token notif + pindah call ke outbox + test (APPLY)

Tiga langkah sekaligus (semua terverifikasi, data uji dibersihkan).

### D1 â€” helper `user_fcm_tokens` + notif baca `user_devices` (BUKAN profiles)
- **Masalah nyata:** beberapa trigger baca **`profiles.fcm_token`** SAJA
  (legacy, dikosongkan `20260827000000`) â†’ notif TIDAK sampai ke device klien
  baru (`user_devices`). Terbukti saat uji: panggilan masuk (`call_push` 6-arg)
  & chat 1:1 tidak menghasilkan push karena token profil kosong.
- **Migrasi `20260927170000_user_fcm_tokens_helper.sql`:** helper terpusat
  `user_fcm_tokens(uid)` â†’ token dari `user_devices` (aktif) + **fallback**
  `profiles.fcm_token` HANYA bila tak ada device bertoken (kompat klien lama).
  SECURITY DEFINER, read-only, additive.
- **Migrasi `20260927180000_notif_use_user_devices_tokens.sql`:** `call_push`
  (6-arg), `notify_contact_online`, `notify_broadcast_started` â†’ pakai helper.
- **Migrasi `20260927190000_notify_private_use_user_devices.sql`:**
  `notify_private_message` (FROZEN, menyentuh) â†’ token via helper + loop
  (semua device). Payload & logika lain 100% IDENTIK.

### D2 â€” `call_push` (2 overload) + `notify_call_ended` â†’ outbox
- **Migrasi `20260927200000_call_push_via_outbox.sql`** (keduanya FROZEN,
  `-- menyentuh:`). Ganti `net.http_post` â†’ `insert into outbox`. Logika &
  payload identik; `notify_call_ended` tetap set `notif_sent_at` (idempoten).

### D3 â€” test pgTAP (mengunci arsitektur)
- **`supabase/tests/outbox_notif_test.sql` (BARU, 16 assert):** tabel outbox,
  helper, cron `chatyuk-outbox-worker`, trigger notif memakai outbox & TIDAK
  http_post sinkron, token via `user_fcm_tokens`, konsistensi
  `posts.author_name == profiles.nickname`, index kunci skala.

### Verifikasi
- Snapshot `functions.sql` di-regen (30/30). Diff = hanya `net.http_post` â†’
  `insert into outbox` + sumber token; 0 cabang logika hilang (direview).
- Guardrail `check_migrations.sh --all` â†’ OK bersih.
- **Uji E2E (dummy, [TEST]):** `call_push` â†’ outbox `type=call` token device âœ…;
  `notify_private_message` â†’ outbox `type=message` âœ…; worker proses âœ…;
  data uji dibersihkan (devices/outbox=0) âœ….
- **SQL tests: 20/20 file lolos** (outbox_notif_test 16/16, call 18/18,
  notif_chat 10/10, schema_sync 31/31).
- **Fungsi live `net.http_post` sinkron: 13 â†’ 10** (mention, private_message,
  call_pushÃ—2, notify_call_ended sudah pindah).
- Versi tercatat: `20260927170000..20260927200000`.

### Sisa (belum dipindah ke outbox â€” masih `net.http_post` sinkron)
`send_reengage_notifications`, `social_push`, `ai_reply_post`, `ai_proactive_tick`,
`notify_online_fanout`, `notify_room_fanout`, `notify_timeline_*_fanout`,
`notify_contact_online`, `notify_broadcast_started` (Ã—2 = 10 fungsi).
Fanout topical & AI sudah punya pola async sendiri (pg_net non-blocking),
prioritas lebih rendah.

### Rollback
- D1/D2: re-apply definisi lama dari `20260926150000`/`20260913130001` +
  `/tmp/notify_private_message_LIVE.sql`, lalu regen snapshot.
- D1 helper: `drop function public.user_fcm_tokens(uuid);`

## 2026-09-27 â€” Outbox Fase E: contact_online & broadcast â†’ outbox (fanout DIREVERT)

- **Tujuan:** lanjut pindahkan sisa trigger `net.http_post` (+ dukungan
  endpoint majemuk di worker).
- **Migrasi `20260927210000_fanout_and_online_via_outbox.sql`:** pindah 6 fungsi
  ke outbox (4 fanout topical + `notify_contact_online` +
  `notify_broadcast_started`). Worker diperluas (**v2**) mendukung
  `payload.endpoint` = `send-push` (default, back-compat) / `fanout`.
- **Migrasi `20260927220000_revert_fanout_to_http.sql` (REVERT fanout):**
  ditemukan saat uji bahwa edge **`fanout`** mengautentikasi via **service_role
  JWT** (`isServiceRoleJwt`), sedangkan worker memakai `fetch` dgn
  `SUPABASE_SERVICE_ROLE_KEY` yang formatnya tidak dijamin JWT di runtime â†’
  workerâ†’fanout **gagal** (workerâ†’send-push OK karena `send-push` terima
  `x-app-secret`). Daripada mematikan fanout topical (notif online/room/
  timeline), 4 fanout **dikembalikan** ke `net.http_post` (perilaku asli).
  `notify_contact_online` + `notify_broadcast_started` **TETAP via outbox**
  (pakai send-push + x-app-secret, terbukti jalan).
- **Verifikasi:**
  - `notify_contact_online` â†’ outbox `type=online` (3 baris, 1 per kontak) âœ…
  - `notify_broadcast_started` â†’ outbox (send-push) âœ…
  - fanout topical â†’ `http_post` lagi (hp=true, ob=false) âœ…
  - snapshot regen (30/30) + `check_migrations` OK + **SQL tests 20/20 lolos**
  - outbox & data uji bersih (0) âœ…
- **Status akhir `net.http_post` sinkron: 15 â†’ 8** (7 pindah ke outbox:
  mention, private_message, call_pushÃ—2, call_ended, contact_online,
  broadcast_started).
- **SISA 4 fungsi `net.http_post` (SENGAJA tidak dipindah â€” bukan trigger,
  dipanggil cron/RPC, sudah punya pola async sendiri, prioritas rendah):**
  `ai_proactive_tick`, `ai_reply_post`, `send_reengage_notifications`,
  `social_push`, + 4 fanout topical (kembali sinkron karena keterbatasan auth
  edge `fanout`). Untuk memindah fanout ke outbox nanti: samakan auth
  `fanout` agar menerima `x-app-secret` (perlu deploy multi-file `_shared`).
- Versi tercatat: `20260927210000`, `20260927220000`.

## 2026-09-27 â€” Outbox Fase F: fix penumpukan token FCM basi (worker v3 + RPC)

- **Temuan saat verifikasi produksi:** outbox menumpuk ~97 baris (tidak
  terkirim). Setelah investigasi: baris berasal dari **`profiles.fcm_token`**
  yang **basi** (device lama / project Firebase lama `chatyuk-8470e`). FCM
  menolak `404 NotRegistered` / `403 SenderIdMismatch`. Worker lama menandai
  `failed` â†’ retry selamanya â†’ menumpuk.
- **Fix 1 â€” `outbox-worker` v3:** kegagalan **4xx = PERMANEN** â†’ tandai
  `sent_at` (dibuang), jangan retry; 5xx/timeout = transient â†’ retry. Terbukti
  outbox 96 â†’ 0 (30 drop di run pertama, sisanya menyusul; 2 nyata terkirim).
- **Fix 2 â€” `send-push` auto-clean diperluas:** selain `NotRegistered` (404),
  kini juga `SenderIdMismatch` (403) dibersihkan. **Ditemukan bug:** auto-clean
  lama pakai PostgREST `.from('profiles').update().eq('fcm_token', token)`
  â†’ **0 baris** (PostgREST tak bisa filter kolom `fcm_token` karena SELECT
  di-revoke). 
- **Fix 3 â€” RPC `purge_fcm_token(text)` (`20260927230000`, SECURITY DEFINER,
  service_role only):** hapus token dari `profiles` + `user_devices` dengan
  andal. `send-push` kini memanggil `admin.rpc('purge_fcm_token', ...)`.
  Terbukti: 199 â†’ 198 profil (token uji terhapus).
- **Efek:** token basi terbersihkan otomatis seiring waktu â†’ outbox tidak
  menumpuk. Bukan regresi (perilaku lama sama: kirim ke `profiles.fcm_token`
  basi; dulu gagal diam-diam via http_post, kini terlihat & self-healing).
- **Verifikasi:** outbox pending=0 (dikuras cron tiap menit), data uji bersih,
  **SQL tests 20/20 lolos**, `check_migrations` file sesi bersih.
- Versi/deploy: `send-push` v64, `outbox-worker` v3, migrasi `20260927230000`.
- **CATATAN:** ada file `supabase/migrations/20260928000000_unified_yukcoin.sql`
  (BUKAN dari sesi ini) yang membuat `check_migrations --all` DITOLAK (policy/
  grant tanpa `-- SAFE:`). Perlu diperbaiki oleh pembuatnya.

## 2026-09-27 â€” 20260928020000_purge_location_history_90d.sql (APPLY)

- **Tujuan:** retensi `user_location_history` (tabel tumbuh tiap update
  lokasi user). Di jutaan user, tanpa retensi tabel membengkak tanpa batas.
- **Isi:** fungsi `purge_location_history_90d()` (buang baris `created_at <
  now()-90d`, SECURITY DEFINER) + cron harian `purge-location-history-90d`
  (`10 4 * * *`). Data ini hanya dibaca fitur admin untuk riwayat JANGKA
  PENDEK â†’ 90 hari cukup.
- **Zero-impact:** semua baris saat ini < 30 hari â†’ purge = 0 (tabel tetap
  4687). Persiapan skala, bukan perubahan perilaku.
- **Apply:** Management API. Versi tercatat `20260928020000`.
- **Catatan timestamp:** awalnya `20260928010000` BENTROK dengan file lain
  (`20260928010000_align_profiles_points_default.sql`, BUKAN sesi ini) â†’
  di-rename ke `20260928020000` (guardrail timestamp unik). Versi
  `schema_migrations` sudah dikoreksi.
- **Verifikasi:** fungsi ada + cron active âœ…; `purge_location_history_90d()`
  â†’ 0; tabel tetap 4687; **SQL tests 20/20 lolos**.
- **Rollback:** `select cron.unschedule('purge-location-history-90d');
  drop function public.purge_location_history_90d();`

## 2026-09-27 â€” 20260927110000_view_once_video_expire_policy.sql (APPLY)

- **Masalah:** video "sekali lihat" (type='video_once') di private chat TIDAK
  terkunci di penerima â€” bisa diputar ulang selamanya (beda dari foto yang
  terkunci setelah ditonton). Penyebab: policy
  `private_messages_update_view_once` hanya mengizinkan `type =
  'view_once_expired'` (foto) â†’ update penerima ke `video_once_expired`
  DITOLAK RLS (0 baris). Room bahkan belum punya policy expire sama sekali.
- **Isi:** perluas WITH CHECK jadi `type in ('view_once_expired',
  'video_once_expired')` untuk `private_messages` & tambah policy setara
  untuk `messages` (room; global room = semua login, private room = member).
  Qual siapa-yang-boleh TIDAK diubah.
- **Apply:** Management API. Verifikasi (live): kedua policy memuat
  `video_once_expired` âœ….

## 2026-09-27 â€” 20260927120000_admin_chat_messages_media.sql (APPLY)

- **Fitur:** monitor admin bisa MELIHAT semua media di chat: foto biasa,
  video, dan view-once foto/video; call/video-call (teks) juga tampil.
- **Masalah:** `admin_get_chat_messages_page` lama hanya mengisi `image_data`
  untuk view_once; TIDAK mengirim `image_path` â†’ foto biasa & video kosong
  di monitor (FotoCache tak punya path).
- **Isi:** tambah key `image_path`, `is_deleted`, `edited`; `image_data`
  tetap utuh untuk view_once/video_once (+expired). Guard admin TIDAK berubah.
- **Apply:** Management API. Verifikasi (live): fungsi baru terpasang.

## 2026-09-27 â€” Admin lihat SEMUA user (excluded diberi badge) (APPLY)

- **Masalah (user):** "SimpleMe ga muncul di admin padahal online". Ternyata
  SimpleMe **ter-exclude** karena device `drm-10b31...` ada di
  `excluded_devices` (exclude berbasis perangkat menyeret semua akun yang
  login di device itu) + uid-nya juga di `excluded_uids` manual. BUKAN bug
  kode â€” tapi kebijakan menyembunyikan total bikin user asli "hilang".
- **Keputusan user:** admin harus bisa lihat SEMUA (excluded/enggak), cukup
  diberi badge `EXCLUDED`.
- **Migrasi:**
  - `20260928070000_admin_show_excluded_with_flag.sql` â€” `admin_stats_detail`
    (FROZEN, menyentuh): keempat `users_*` **tidak lagi membuang** excluded,
    tambah field `'excluded'`. DUMMY tetap dibuang.
  - `20260928080000_admin_users_page_show_excluded.sql` â€” `admin_stats_users_page`
    (dipakai sheet Users di ringkasan): sama â€” biarkan excluded, tambah flag.
- **SENGAJA TIDAK diubah** (jalur user nyata â€” exclude device = akun test/dev
  TIDAK boleh tampil ke user asli): `list_posts`, `nearby_users`,
  `create_private_room`, `_anon_write_ok`, `_social_registered_guard`,
  `admin_stats_compute` (kartu angka tetap seperti semula).
- **Client:** `usermap_card.dart` â€” buang filter `isHiddenUid` (peta tampil
  semua), tambah badge di detail. `stat_detail_sheet.dart` â€” badge EXCLUDED
  di baris user.
- **Verifikasi live:** `admin_stats_users_page('all',500,0)` mengembalikan
  SimpleMe/AntoSusanto/halo dengan `excluded=true`; snapshot regen (30/30);
  `check_migrations` file sesi bersih; test admin 96/96 lolos.
- **Catatan:** file `20260927120000_index_dedup_and_fix.sql` (sesi lebih awal)
  di-rename â†’ `20260927125000_index_dedup_and_fix.sql` karena bentrok timestamp
  dengan `20260927120000_admin_chat_messages_media.sql` (file paralel).

## 2026-09-28 ï¿½ 20260928110000_drop_profiles_public_view.sql (APPLY)

- **Sumber:** temuan Security Advisor Supabase ï¿½ *"View public.profiles_public
  is defined with the SECURITY DEFINER property"*.
- **Akar masalah:** view milik `postgres` (SECURITY DEFINER = hak OWNER,
  menembus RLS `profiles`), di-GRANT SELECT/INSERT/UPDATE/DELETE/TRUNCATE ke
  `anon` + `authenticated`. Siapa pun bisa `select * from profiles_public` ?
  bocor `avatar`/`last_seen`/`status` SEMUA user (membatalkan hardening yang
  mencabut SELECT profiles.avatar).
- **Isi:** `drop view if exists public.profiles_public;` ï¿½ view LEGACY, 0
  referensi di kode (lib/ & supabase/), 0 dependen (view/fungsi lain).
- **Verifikasi live:** `count(*) profiles_public = 0`; kolom sensitif `profiles`
  (`avatar/last_seen/fcm_token/status`) tetap TANPA SELECT untuk anon/auth
  (hardening utuh).
- **Rollback:** buat ulang dengan `with (security_invoker = true)` agar ikut
  RLS pemanggil (lihat header migrasi).
- **Catatan:** audit lengkap 467 temuan advisor ? `docs/SECURITY_AUDIT.md`
  (profiles_public selesai; berikutnya anon SECURITY DEFINER & search_path).

## 2026-09-28 ï¿½ Security hardening lanjutan (3 migrasi, APPLY)

Lanjutan audit advisor (467 ? 326 temuan). Semua **0 perubahan body** fungsi
(hanya REVOKE/ALTER SET), jadi fungsi FROZEN tidak tersentuh.

- **`20260928120000_revoke_anon_internal_functions.sql`** ï¿½ REVOKE EXECUTE
  56 fungsi internal/trigger/admin (notify_*, *_count_sync, sync_*, admin_*,
  dll.) dari **PUBLIC, anon, authenticated**. Temuan
  `anon_security_definer_function_executable` **88 ? 32**.
  - **Temuan kunci:** `revoke ... from anon` SENDIRIAN tidak cukup ï¿½ Postgres
    memberi EXECUTE ke `PUBLIC` default & anon mewarisinya. Wajib `from public`.
    Terverifikasi `has_function_privilege('anon',...)` baru false setelah ini.
  - Fungsi klien (get_online_users, avatar_for, deduct_chat_point, dst.) TIDAK
    di-revoke ï¿½ diverifikasi tak ada yang putus (`authenticated=true` tetap).
  - Helper lintas-fungsi/policy (is_admin_request, fn_room_role,
    _privacy_are_friends, storage_object_owner_ok, dst.) SENGAJA dibiarkan.
- **`20260928130000_set_function_search_path.sql`** ï¿½ ALTER FUNCTION SET
  `search_path = public, pg_temp` untuk 28 fungsi. Temuan
  `function_search_path_mutable` **28 ? 0**.
- **HIBP** (`password_hibp_enabled=true` via Auth config API) ï¿½
  `auth_leaked_password_protection` **1 ? 0**.
- Verifikasi: `flutter analyze`-0 (tak ada perubahan Dart); advisor re-scan;
  `has_function_privilege`/`proconfig` dicek langsung. Detail: `docs/SECURITY_AUDIT.md`.

## 2026-09-28 ï¿½ 20260928140000_revoke_authenticated_internal_legacy.sql (APPLY)

- **Tujuan:** lanjut audit advisor ï¿½ cabut EXECUTE 38 fungsi internal/legacy
  dari `authenticated` (+PUBLIC+anon). Temuan `authenticated_security_definer_
  function_executable` **221 ? 183**. Total advisor **326 ? 288**.
- **Isi:** REVOKE untuk `admin_*` legacy (register_dummy/renew_dummy_token/
  list_dummies/dummy_uids/ï¿½), `ai_*` tick/cleanup/claim, `ledger_*`,
  `call_push`, `friend_request_inbox/outbox`, `presence_idle_tick`,
  `room_voice_sweep`, `purge_inactive_accounts`, `send_reengage_notifications`,
  `social_push`, `yukcoin_total`, dll. + GRANT balik ke `service_role`.
- **Bukti aman:** semua pemanggil internal fungsi ini **SECURITY DEFINER**
  (diverifikasi: `ledger_spend_dual` ? boost_post/send_gift/unlock_photo/
  create_private_room/extend_private_room; `ledger_spend_paid` ? send_coins/
  subscribe_creator/ledger_spend_dual; `yukcoin_total` ? spend_yukcoin) ?
  definer jalan sebagai owner, rantai TIDAK putus.
- **Tidak direvoke:** 10 helper lintas-fungsi/policy (`is_admin_request`,
  `fn_room_role`, `_anon_*`, `_privacy_are_friends`, `storage_object_owner_ok`,
  `chat_photos_guard`, `user_fcm_tokens`, `privacy_can_view`, `privacy_friends`)
  & semua RPC klien (diverifikasi `has_function_privilege` tetap true).
- **`extension_in_public` SENGAJA DIBIARKAN** (cube/earthdistance ? fitur
  "Orang Sekitar"; pg_net ? notif; pindah schema = risiko tinggi, manfaat 1 lint).
  Alasan lengkap: `docs/SECURITY_AUDIT.md` ï¿½6.

## 2026-09-28 â€” 20260928150000_restore_admin_storage_stats_grant.sql (SUDAH APPLY)

- **Tujuan:** kembalikan EXECUTE `admin_storage_stats()` ke `authenticated`.
  Efek samping hardening `20260928120000` (cabut dari authenticated, sisa
  service_role) â†’ kartu "Penggunaan Data Supabase" di panel admin 403/loading
  terus (app admin login via JWT = role authenticated).
- **Isi:** 1 baris GRANT saja (body fungsi TIDAK disentuh â€” bukan FROZEN).
- **Bukti aman:** guard admin internal di body (`auth.email()='zunixe@gmail.com'`
  atau service_role, selain itu `raise 'Unauthorized'`); preseden
  `admin_table_sizes` memang di-grant ke authenticated.
- **Client:** `getStorageStats`/`getTableSizes`/`getCfUsage` kini timeout 30 dtk
  + kartu tampil error + tombol retry (tidak spinner selamanya).
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `auth_can_exec=true`, `anon_can_exec=false` (hardening tetap).

## 2026-09-28 â€” 20260928160000_admin_storage_stats_pro_quota.sql (SUDAH APPLY)

- **Tujuan:** kuota kartu admin ikut paket PRO (sebelumnya hardcode FREE tier
  â†’ progress bar penuh padahal pemakaian kecil). DB 512 MB â†’ 8 GB
  (8589934592), storage 1 GB â†’ 100 GB (107374182400) sesuai supabase.com/pricing.
- **Isi:** body disalin utuh dari 20260825170000 (tak ada migrasi lain yang
  menyentuh body); hanya 2 angka kuota + komentar yang berubah. Bukan FROZEN.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `qdb=8589934592`, `qstor=107374182400`.

## 2026-09-28 â€” 20260928170000_admin_storage_stats_bandwidth.sql (SUDAH APPLY)

- **Tujuan:** tampilkan batas bandwidth di kartu admin (Pro = 250 GB egress).
  Pemakaian live TIDAK diekspos API mana pun (hanya dashboard Supabase â†’
  Usage), jadi yang ditampilkan = kuota + hint.
- **Isi:** body disalin utuh dari 20260928160000; tambah 2 key output
  (`quota_bandwidth_bytes=268435456000`, `plan='pro'`). Bukan FROZEN.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `bw=268435456000`, `plan=pro`.
- **Client:** baris "Bandwidth (egress) â€” Kuota: 250 GB" + hint di kartu
  (string `adminStorageBandwidth`/`adminBandwidthHint`, bilingual).

## 2026-09-28 â€” 20260928180000_restore_admin_dummy_uids_policy_grant.sql (SUDAH APPLY) âš ï¸ INSIDEN

- **GEJALA (laporan user):** SEMUA panggilan (audio & video) gagal â€” pesan
  "Hanya akun terdaftar yang bisa melakukan panggilan" walau
  `app_settings.call_anon_enabled = true`. Timeline juga rusak. Error asli
  dari logcat: `PostgrestException ... permission denied for function
  admin_dummy_uids, code: 42501`.
- **AKAR:** hardening `20260928140000` mencabut EXECUTE `admin_dummy_uids()`
  dari `authenticated`. Tapi fungsi itu dipanggil **DI DALAM policy RLS**
  `calls.calls_insert` (with check) & `posts.posts_select` (qual) â€” dan policy
  RLS dievaluasi sebagai **role pemanggil**, bukan definer. Jadi setiap
  INSERT calls & SELECT posts oleh user login kena 42501 SEBELUM logika toggle
  anon tercapai. (Asumsi "hanya dipanggil trigger/cron/definer" salah untuk
  fungsi ini.)
- **Isi:** 1 baris `grant execute on function public.admin_dummy_uids() to
  authenticated;` (body TIDAK disentuh). `anon` tetap dicabut.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `auth_can=true, anon_can=false`; simulasi role
  `authenticated` â†’ `admin_dummy_uids()=14`, `select posts=19` (0 error 42501).
- **âš ï¸ PELAJARAN (untuk audit berikutnya):** fungsi yang dipanggil di
  `qual`/`with_check` policy, VIEW, atau kolom DEFAULT dijalankan sebagai
  caller â€” **TIDAK BOLEH** di-revoke dari role yang memakai policy itu, walau
  fungsinya SECURITY DEFINER. Sebelum REVOKE, scan dulu:
  `select policyname from pg_policies where (qual||with_check) ~ '<fn>';`
  Lihat `docs/SECURITY_AUDIT.md`.

## 2026-09-28 â€” 20260928190000_restore_calls_insert_anon_branch.sql (SUDAH APPLY) âš ï¸ INSIDEN KEDUA

- **GEJALA lanjutan:** setelah 20260928180000 (grant), panggilan MASIH gagal
  "Hanya akun terdaftar yang bisa melakukan panggilan" walau toggle anon ON.
- **AKAR:** policy live `calls_insert` ternyata versi LAMA 20260912000050
  (registered-only absolut, TANPA cabang `call_anon_enabled`), padahal
  `20260912090000_call_anon_toggle.sql` **tercatat applied** di
  `schema_migrations`. Pola "recorded but not actually applied / tertimpa"
  (lihat APPLIED_VIA_API.md). Jadi anon/dummy tetap ditolak RLS.
- **Isi:** re-apply definisi policy versi benar (identik 20260912090000,
  idempoten) â€” tambah cabang `call_anon_enabled` untuk anon & dummy.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `has_anon_branch=true`; simulasi INSERT `calls` sebagai
  role authenticated + uid anon (toggle ON) â†’ **berhasil** (return inserted id,
  tanpa 42501). Rollback â†’ data produksi tak tersentuh.
- **CATATAN:** dua insiden berurutan (grant + policy basi) sama-sama membuat
  SEMUA panggilan gagal. Sebelum menyalahkan client, SELALU tarik error asli
  (`debugPrint('[CALL-START] ...')` di logcat) + verifikasi `pg_policies` live,
  bukan hanya `schema_migrations`.

## 2026-09-28 â€” 20260928203000_admin_chat_org_sync.sql (SUDAH APPLY)

- **Masalah (laporan user):** kategori folder monitor chat (mis. "Huha") dibuat
  di HP Xiaomi tidak muncul di HP Redmi. Akar: `admin_chat_org.dart` menyimpan
  PIN + kategori HANYA di SharedPreferences lokal per HP (murni sisi klien).
- **Isi:** tabel `public.admin_chat_org` (1 baris global: `pinned_chat_ids`,
  `category_list`, `category_map` jsonb) â€” RLS enabled TANPA policy (deny
  semua), hanya service_role & RPC security-definer (guard email admin) yang
  akses. RPC `admin_get_chat_org()` + `admin_set_chat_org(text[], text[], jsonb)`.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** round-trip `admin_set_chat_org` â†’ `admin_get_chat_org`
  mengembalikan `category_list=['Huha']` + map yang benar.
- **Klien:** provider `orgGet`/`orgSet` bridge; load = lokal dulu (instan) lalu
  server (sumber kebenaran); setiap mutasi push ke server. **Seed upgrade:**
  server kosong + lokal ada â†’ dorong lokal ke atas (jangan hapus).
- **âš ï¸ Pelajaran:** fitur "alat kerja admin" yang dulu sengaja lokal (prefs)
  tetap berisiko saat admin pakai >1 HP. Bila ada keluhan "ada di HP A tidak di
  HP B", cek dulu apakah state-nya server atau lokal.

## 2026-09-28 â€” 20260928200000_stagger_cron_schedules.sql (SUDAH APPLY)

- **TUJUAN (stabilitas, bukan fitur):** cron per-menit kehabisan worker pg_cron
  di instance Micro â†’ banyak run gagal `job startup timeout`.
- **BUKTI (live, 24 jam):** `cron.job_run_details` â†’ 414/8956 run gagal (4.6%);
  menit kelipatan 5 pernah 11 job gagal serentak. `SHOW max_worker_processes`
  = 6 (dipakai autovacuum 3 + realtime 2 walsender + pg_net). Ada 5 job
  `* * * * *` TERPISAH + 4 job `*/5` yang menabrak di menit sama.
- **ISI:**
  1. Fungsi BARU `housekeeping_tick()` (wrapper; bukan FROZEN) yang memanggil
     berurutan `presence_idle_tick()`, `room_voice_sweep()`, + 2 DELETE
     cleanup room (sinyal/broadcaster basi). Tiap blok `exception when others`.
  2. Job BARU `chatyuk-housekeeping` (`* * * * *`) â†’ 1 worker, bukan 5.
  3. Lepas 4 job lama per-menit: `cleanup-room-signals`,
     `cleanup-stale-broadcasters`, `chatyuk-presence-idle`, `sweep_room_voice`.
  4. `chatyuk-outbox-worker` â†’ `*/2` (http_post bisa tahan lama; jangan ikut
     tiap menit).
  5. Job `*/5` disebar menitnya (`1-59/5`, `2-59/5`, `3-59/5`).
     `chatyuk-call-sweep` TIDAK diubah â€” dikunci `call_test.sql` (`*/5 * * * *`).
- **CATATAN pg_cron:** format 6-field (detik) TIDAK didukung di instance ini â€”
  job dengan jadwal `0 * * * * *` berhenti total (tidak jalan). Percobaan
  awal pakai detik sudah di-REVERT.
- **Verifikasi live:** maks 5 job/menit (dulu 10-11), **0 gagal** setelah
  perubahan; `housekeeping_tick()` â†’ `{voice_sweep:0, presence_idle:0}`;
  `room_signals`/`room_broadcasters` basi = 0.
- **Test:** `outbox_notif_test.sql` 16/16, `ai_test.sql` 16/16,
  `call_test.sql` 20/20 hijau.
- **Rollback:** `/tmp/chatyuk_cron_backup/jobs_before.json` (definisi awal);
  `cron.unschedule('chatyuk-housekeeping')` + `cron.schedule(...)` job lama.
- **Bukan** fungsi FROZEN â†’ snapshot tidak berubah (revert setelah regenerate
  karena drift `nearby_users` dari sesi lain bukan bagian perubahan ini).

## 2026-09-28 â€” 20260928210000_disable_ai_daily_life_cron.sql (SUDAH APPLY)

- **Tujuan:** hentikan cron `chatyuk-ai-daily-life` (jobid 15, `0 22 * * *`)
  karena belum dipakai â€” mengurangi beban/worker pg_cron.
- **Isi:** `cron.unschedule('chatyuk-ai-daily-life')` (hapus dari scheduler,
  bukan sekadar `active=false`).
- **Verifikasi live:** `count(*) from cron.job where jobname='chatyuk-ai-daily-life'`
  â†’ 0. Total job aktif 17 â†’ 16.
- **Tidak ada test** yang mengunci job ini; tidak menyentuh FROZEN/GRANT/RLS.
- **Aktifkan lagi:** jalankan ulang blok `cron.schedule('chatyuk-ai-daily-life',
  '0 22 * * *', ...)` dari `20260912010000_audit_cleanup_batch.sql`.

## 2026-09-28 â€” 20260928220000_restore_admin_rpcs_execute.sql (SUDAH APPLY) âš ï¸ INSIDEN KETIGA

- **GEJALA (log Postgres):** `42501 permission denied for function
  admin_sweep_calls` & `admin_registrations_daily` berulang. Chart registrasi
  admin + sweep zombie call rusak.
- **AKAR:** hardening `20260928120000` + `20260928140000` memakai daftar
  revoke yang terverifikasi "0 referensi di lib/ sebagai .rpc()" â€” tetapi
  deteksi berbasis grep itu **melewatkan RPC multi-baris** (mis.
  `await _rpc(\n 'admin_registrations_daily', ...)`). Akibatnya 6 fungsi
  admin yang MASIH dipanggil app admin ikut dicabut:
  `admin_sweep_calls`, `admin_registrations_daily`,
  `admin_contact_messages_page`, `admin_contact_set_read`,
  `admin_contact_delete`, `admin_set_privacy_bypass`.
- **KENAPA AMAN dikembalikan:** ke-6 fungsi punya guard internal
  `if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise`. EXECUTE
  bukan bypass â€” hanya pintu masuk ke guard. Preseden sah:
  `admin_storage_stats` memang authenticated=true + guard sama.
- **Isi:** 6 baris `grant execute ... to authenticated` (body tidak disentuh).
- **Apply:** Management API. Versi dicatat di `schema_migrations`.
- **Verifikasi live:** authoritative `has_function_privilege('authenticated',â€¦)`
  = true untuk ke-6 fungsi; `anon` = false. Simulasi
  `set local role authenticated` â†’ `admin_sweep_calls()` jalan (bukan 42501).
  Cron `chatyuk-call-sweep` kembali `succeeded 1 row`.
- **GUARD BARU:** 8 assert di `supabase/tests/schema_sync_test.sql`
  mengunci: authenticated boleh EXECUTE 7 fungsi admin tsb, anon DILARANG.
- **âš ï¸ PELAJARAN:** audit "0 referensi di lib/" WAJIB pakai parser/pola yang
  menangkap pemanggilan **multi-baris** â€” grep satu baris tidak cukup.
  Scan: `scripts/audit_revoked_rpcs.py` (lihat SECURITY_AUDIT.md).

## 2026-09-29 â€” 20260929000000_fix_cleanup_stale_anonymous.sql (SUDAH APPLY)

- **GEJALA:** log Postgres `P0001 coin_ledger is append-only` berulang +
  `23503` FK `user_devices`/`user_location_history`; **1.597 akun anon stale
  MENUMPUK** (cleanup tak pernah berhasil membersihkan).
- **REPRODUKSI (aman, rollback):**
  `begin; select public.cleanup_stale_anonymous(0); rollback;`
  â†’ `ERROR P0001 coin_ledger is append-only ... delete from auth.users`.
- **AKAR (3 defect di fungsi lama):**
  1. `delete from auth.users` cascade ke `coin_ledger` (FK ON DELETE CASCADE)
     tapi trigger append-only `coin_ledger_no_delete` menolak cascade â†’
     error. (`delete_my_account`/`admin_delete_anon_user` sudah benar.)
  2. `delete from public.profiles` dijalankan SEBELUM user_devices/
     user_location_history dihapus â†’ FK SET NULL vs kolom NOT NULL â†’ 23503.
  3. Loop TANPA `exception` per-user â†’ SATU user gagal membatalkan SELURUH
     cleanup â†’ akun stale menumpuk.
- **Isi:** redefine fungsi mengikuti pola `delete_my_account` yang terverifikasi
  (hapus device/location lebih dulu; hapus coin_ledger + point_events dengan
  trigger dimatikan; `exception when others` per user).
- **Verifikasi live (rollback):** `would_delete=1683`, TANPA error append-only.
- **GUARD BARU:** 2 assert `schema_sync_test.sql` (fungsi wajib menyebut
  disable trigger coin_ledger + hapus devices/location + `exception when others`).
- **âš ï¸ PELAJARAN:** setiap loop hapus-user WAJIB bungkus `exception` per user â€”
  satu baris bermasalah (mis. ledger) tidak boleh menggagalkan migrasi data
  massal, kalau tidak akun stale diam-diam menumpuk berbulan-bulan.

## 2026-09-29 â€” 20260929020000_reduce_presence_write_load.sql (SUDAH APPLY)

- **Konteks:** stall panel admin (57014/timeout). Akar UTAMA = compute **Nano**
  (RAM 0,5 GB, I/O 11 MB/s) â€” DIPERBAIKI dengan upgrade ke **Micro** (RAM 1 GB,
  I/O 87 MB/s, harga SAMA) via API `billing/addons`. Lihat PERFORMANCE.md Â§22.
- **Migrasi ini = perbaikan pendamping** (mengurangi volume tulis profiles):
  1. `notify_online_fanout` AFTER â†’ **BEFORE UPDATE**: set
     `new.last_online_notified_at` langsung, hapus `UPDATE profiles` NESTED
     (dulu 1 transisi status = 2Ã— tulis + 9 trigger profiles dipicu ulang).
  2. `notify_online_fanout` + `notify_contact_online` **skip akun dummy**
     (14 bot ikut fanout tiap `ai_presence_tick` tiap 5 menit â†’ http_post +
     outbox spam; 94 chat berisi dummy).
  3. `housekeeping_tick` pangkas `cron.job_run_details` > 7 hari.
- **Verifikasi live:** trigger `profiles_online_fanout_trigger` = BEFORE UPDATE
  (`tgtype` bit); uji transisi dummy online â†’ `net._http_response` TIDAK nambah
  (224 â†’ 224); `housekeeping_tick()` â†’ `cron_purged` kendali jalan.
- Bukan fungsi FROZEN. Snapshot FROZEN TIDAK berubah (revert diff `nearby_users`
  pre-existing dari sesi lain).


## 2026-09-29 — Panggilan Terbaru (fitur klien, TANPA migrasi)

- **Fitur:** menu ⋮ tab Pesan → halaman "Panggilan Terbaru" (riwayat call
  masuk/keluar ala WhatsApp). Tap baris → buka chat; ikon call → panggil ulang
  jenis terakhir (audio→fullscreen, video→mode chat).
- **Data:** tabel `public.calls` yang SUDAH ADA — RLS `calls_select`
  (`auth.uid() = caller_id OR callee_id`) otomatis membatasi ke user sendiri.
  Query client `.or(caller_id.eq.me,callee_id.eq.me)` → **tidak ada perubahan
  DB, tidak ada RPC baru, tidak ada grant/RLS yang disentuh.**
- **Kode:** `lib/services/call_service.dart` (`listMyRecentCalls`,
  `lookupNicknames`), `lib/providers/call_provider.dart` (passthrough),
  `lib/core/call/call_history_entry.dart` (murni), `lib/screens/call_history_screen.dart`,
  `lib/screens/chats_screen.dart` (item menu), `lib/config/strings.dart` (7 getter).
- **Verifikasi:** `flutter analyze` 0 error/0 warning; `test/call_history_test.dart`
  14/14 hijau; `check_screen_boundary.sh` — file baru 0 import services.

## 2026-10-01 — Setup Produk Google Play (in-app products) + secret edge function

- **Masalah:** Play Console blokir pembuatan produk: "Aplikasi belum memiliki
  produk sekali beli — harus menambahkan izin PENAGIHAN ke APK". APK rilis
  (1.2.61) di-upload sebelum `in_app_purchase` ditambahkan.
- **Fix:** bump 1.2.62+84 → build AAB `playProd` (izin `com.android.vending.BILLING`
  ikut dari plugin) → upload ke **internal testing** via Play Console. Blokir
  terbuka.
- **Produk dibuat via Google Play Developer API** (service account
  `chatyuk-play-upload@chatyuk-7c9e4`, sudah ada di `fastlane/google-play.json`,
  ter-gitignore):
  - Endpoint: `PATCH .../v3/applications/{pkg}/onetimeproducts/{id}?allowMissing=true&regionsVersion.version=2026/01&updateMask=listings,purchaseOptions`
    (catatan: path **huruf kecil** `onetimeproducts`; bahasa listing `id`).
  - Aktivasi: `POST .../oneTimeProducts/-/purchaseOptions:batchUpdateStates`
    (`activatePurchaseOptionRequest`, purchaseOptionId `buy`).
  - 5 produk ACTIVE: `chatyuk_coins_700`/1850/3900/8200/21500 =
    Rp 10.000/25.000/50.000/100.000/250.000 (sinkron `topup_packages`).
- **Secret edge function** (`play-topup-verify`): `GOOGLE_PLAY_SA_JSON`
  (isi `fastlane/google-play.json`), `ANDROID_PACKAGE_NAME=com.chatyuk.chatyuk`.
- **Verifikasi:** kelima produk `state=ACTIVE` + harga IDR sesuai.

## 20261017130000_posts_blurhash

- **Status:** TERAPPLIED via Management API — `20261017130000_posts_blurhash.sql`.
- **Kolom baru:** `posts.image_blurhashes jsonb not null default '[]'` (array hash
  sejajar `images[]`; post lama = `[]` → client fallback alas `#1E1E1E`).
- **Fungsi:**
  - `create_post(...)` → argumen baru `p_image_blurhashes` (overload 4-arg di-drop).
  - `list_posts(...)` (FROZEN) → output `imageBlurhashes` (satu field ditambah,
    cabang lain IDENTIK; header `-- menyentuh: list_posts`).
  - `get_post(...)` → output `imageBlurhashes` (dipakai layar detail).
- **Verifikasi:** kolom ada; `list_posts` mengandung `imageBlurhashes`;
  `create_post` 5-arg; snapshot `functions.sql` diupdate; `check_migrations --all` OK.
- **Klien:** composer menghitung BlurHash (`core/media/blurhash.dart`, 32px) saat
  upload; `PostCard`/`PostPhotoGrid` menampilkan `BlurHash` placeholder.

## 20261017140000_posts_blurhash_backfill

- **Status:** TERAPPLIED via Management API.
- **Isi:** backfill `posts.image_blurhashes` untuk **22 post lama** berfoto
  (sebelumnya `[]`). Hash dihitung dengan encoder aplikasi
  (`lib/core/media/blurhash.dart`, 32px, 4×3) dari file Storage
  (bucket `chat-photos` = public read).
- **Idempoten:** hanya baris dengan `image_blurhashes = '[]'`.
- **Verifikasi:** `select count(*) filter (where image_blurhashes <> '[]')`
  = **22** dari 22 post berfoto.

## 20261027160000_moderator_slots_fcfs

- **Status:** TERAPPLIED via Management API (2026-10-27) — di-apply 2x
  (revisi kecil menambah `action` pada `mods_last`, tetap idempoten).
- **Keputusan produk:** panel moderasi di Profil hanya muncul bagi yang
  memenuhi syarat & slot terbuka; **maks 2 moderator aktif per negara**,
  lamaran memenuhi syarat **langsung ditetapkan** (siapa cepat dia dapat);
  moderator bisa keluar sendiri; admin panel dapat notifikasi aktivitas
  moderasi (permohonan izin/laporan/tinjauan/perubahan moderator).
- **Isi:** `active_moderator_count()`, `moderator_resign()` (BARU),
  `admin_moderation_activity()` (BARU, ringan utk notif), replace
  `apply_country_moderator` (instant grant + advisory lock
  `modslot:<negara>` + tutup pending legacy saat granted),
  `moderator_set_colleague` / `decide_moderator_application` /
  `admin_set_country_moderator` (semua jalur grant hormati batas 2 slot),
  `my_moderation_state` (+`eligible`/`slot_open`/`slot_count`/`slot_max`),
  3 index parsial aditif (`messages_needs_review_idx`, `reports_open_idx`,
  `moderator_actions_grant_idx`).
- **Verifikasi:** pgTAP `moderator_slots_test.sql` 17/17; suite pgTAP penuh
  hijau; snapshot `supabase/snapshots/functions.sql` di-refresh (diff review:
  hanya penambahan cabang ghost-mode migrasi sebelumnya yang belum
  tersnapshot — tidak ada cabang hilang); tidak ada negara dengan >2
  moderator aktif di produksi. `is_chatyuk_admin` tidak disentuh.
- **Klien:** visibilitas kartu via `moderationCardVisible` (pure, tested),
  lamaran diawali dialog konfirmasi (instant grant), tile resign, angkat
  rekan di konsol memetakan `slots_full`; admin panel poll
  `admin_moderation_activity` tiap 180s (part `admin/admin_mod_notif.dart`,
  seen persist di SharedPreferences `admin_mod_seen_at`).

## 20261027162000_moderation_realtime

- **Status:** TERAPPLIED via Management API (2026-10-27), idempoten.
- **Isi:** (1) 5 tabel moderasi (`country_moderators`,
  `moderator_applications`, `moderator_actions`, `country_send_permits`,
  `reports`) ditambahkan ke publication `supabase_realtime` → kartu
  moderasi Profil user & notifikasi admin panel kini REALTIME (bukan
  menunggu buka-tutup Profil / poll 180s). (2)
  `admin_moderation_activity()` + hitungan & timestamp `applications`
  (lamaran moderator pending). (3) policy SELECT admin-only
  `reports_select_admin` (aditif; user biasa tetap tanpa SELECT).
- **Klien:** user — `ChatService.moderatorSlotChanges` (channel
  `mod-slot-watch`, tabel `country_moderators`) → reload state Profil
  debounce 400ms; admin — `startModerationRealtime` (channel
  `admin-mod-notif`, 4 tabel + `messages` filter `needs_review=true`) →
  bump → `checkModerationActivity` debounce 1200ms; poll 180s tetap jadi
  fallback.
- **Guard:** `scripts/check_migrations.sh` & `snapshot_functions.sh`
  diubah grep-nya jadi case-insensitive — migrasi UPPERCASE
  (`CREATE OR REPLACE`, gaya dump) sebelumnya lolos deteksi dan bikin
  lama (`20261009250000`) dianggap versi terakhir `nearby_users`.
  Header `-- menyentuh:` ditambahkan ke `20261027123000` + snapshot
  refresh (stempel `create_private_room` & `nearby_users` terkoreksi).

## 20261024100000_refund_chat_point_idempotent

- **Status:** TERAPPLIED via Management API (2026-10-24), versi tercatat di
  `supabase_migrations.schema_migrations`.
- **Masalah (REVIEW_2026-10-24 SEC-02):** `refund_chat_point` me-refund spend
  `spend_chat` terakhir tanpa penanda → bisa dipanggil berulang = koin tak
  terbatas. Saat apply: `points_enabled=false`, 17 baris `spend_chat` lama,
  **0 baris `spend_refund`** (belum pernah disalahgunakan).
- **Fix:** hanya spend ≤ 10 menit; `metadata.refund_of` = id spend asal; spend
  yang sudah di-refund dilewati; unique index parsial `coin_ledger_refund_once`
  (user_id, refund_of) + advisory lock per user. Kontrak RPC tetap.
- **Test:** `supabase/tests/refund_chat_point_test.sql` 7/7 (merah sebelum
  apply: refund ke-2/ke-3 menambah saldo); seluruh suite pgTAP 37 file hijau.

## 20261027130000_friend_equals_mutual_follow

- **Status:** TERAPPLIED via Management API (2026-10-27), versi tercatat di
  `supabase_migrations.schema_migrations`.
- **Masalah:** dua definisi teman — story (`_are_friends`) = `friend_requests`
  accepted, sisanya = saling follow. 23 pasangan accepted tanpa saling follow
  masih saling lihat story `friends`.
- **Fix:** `_are_friends` = saling follow; kolom aditif
  `friend_requests.auto_follow`; `send_friend_request` = ikuti + ajakan;
  `follow_user` follow balik → teman (+`friend` di respons, request pending →
  accepted); tolak/batal hanya menarik follow buatan request.
- **Verifikasi live:** 41 accepted → 18 tetap teman (saling follow), 23 basi
  tertutup. `friend_mutual_follow_test.sql` 12/12 (merah 8/12 sebelum apply);
  suite pgTAP penuh hijau.

## 20261030100000_random_video_match

- **Status:** TERAPPLIED via Management API (2026-10-30), versi tercatat di
  `supabase_migrations.schema_migrations`.
- **Fitur:** Random Video Call ("Match Nearby") — dua user yang sama-sama
  menekan Match dipasangkan server lalu langsung video call tanpa ringing.
- **Skema:** `calls.kind` ('direct'|'random', default 'direct'); tabel
  `random_match_queue` (RLS: baca baris sendiri, tulis via RPC) &
  `random_match_pairs` (anti pasangan berulang 10 menit); realtime queue.
- **RPC:** `random_match_join/ping/leave/stats`, `random_call_history`,
  `random_match_sweep` (cron tiap menit). Flag `feature_flags.random_call`
  (default unpublished → admin dulu).
- **Penjaga alur lain (body dari DB live):** `call_history_insert` dilewati
  untuk kind='random' (tidak menulis bubble "Call ended" ke chat orang asing);
  `call_billing_tick` gratis untuk random (keputusan produk: gratis dulu).
- **Verifikasi:** `supabase/tests/random_match_test.sql` 15/15 (merah sebelum
  apply pada 8 assert); suite pgTAP lain hijau kecuali
  `moderator_slots_test.sql` (gagal karena kolom `requested_at` belum ada —
  berasal dari commit fitur moderasi sesi lain, tidak terkait fitur ini).

## 2026-11-01 — random_match_matched_with_fix
- **File:** `20261101110000_random_match_matched_with_fix.sql` (apply via Management API).
- **Isi:** `random_match_join` — baris PARTNER di antrean di-set
  `matched_with = q.user_id` (uid-nya sendiri) → sisi menunggu membaca profil
  sendiri sebagai "partner" (nama di layar call match tampil nama sendiri di
  kedua HP; otherUid chat setelah call salah). Koreksi: baris partner kini
  `matched_with = me` (uid joiner). Baris joiner tak berubah.
- **Verifikasi:** `random_match_test.sql` 23/23 (4 asersi baru: matched_with
  kedua baris + ping sisi menunggu mengembalikan partner yang benar).

## 2026-11-01 — daily_login_streak_v2 (halaman Bonus male)
- **File:** `20261101120000_daily_login_streak_v2.sql` (apply via Management API).
- **Isi:** `daily_login_bonus` diaktifkan ulang (dulu stub no-op oleh
  20261001010000): MALE only, gate `points_enabled`, idempotent harian,
  kredit `ledger_credit` bucket `bonus` (non-withdrawable) — kolom
  `profiles.points` TIDAK disentuh. `streak_bonus_amount` dikembalikan ke
  tier 25/30/35/40/45/50/100 (dulu dinolkan). `get_user_missions` diperluas
  field `login_streak`/`last_login_date`/`gender` untuk grid sign-in.
- **Verifikasi live:** klaim admin (male) streak 1 → +25 bucket bonus,
  total 1000; re-claim hari sama → bonus 0 (idempotent). Snapshot 30 fungsi
  direfresh (menangkap versi live migrasi terdokumentasi sebelumnya),
  `check_migrations --all` OK bersih.

## 2026-11-01 — mission_gender_filter
- **File:** `20261101140000_mission_gender_filter.sql` (apply via Management API).
- **Isi:** kolom `missions.gender` ('all' default) — `nyonya_1000` →
  `female` + judul dirapikan 'Misi Nyonya' (suffix "0/1000" dobel dengan
  label progres UI dihapus). `get_user_missions` memfilter misi
  `gender='all'` atau cocok gender user (main & daily).
- **Verifikasi:** live — male admin → nyonya_1000 absen;
  `daily_login_test.sql` 15/15 (male tanpa nyonya, female dengan judul
  bersih); `check_migrations --all` OK bersih.

## 20261103100000_match_billing_male_payer
- **File:** `20261103100000_match_billing_male_payer.sql` (apply via Management API).
- **Isi:** billing Random Match hybrid — payer SELALU pihak male siapa pun
  caller signaling-nya (asimetri lama: caller = joiner kedua → female-caller
  membuat call gratis total & female income 0). Model: gratis 30 detik →
  biaya konek 10 sekali (feature `match_call`, split 70/30 → female +3) →
  `call_video` 20/menit (female +6). <30 dtk siapa pun tutup → male hanya
  rugi pair fee 2. Tick boleh dari kedua peserta (random) — billing
  diarahkan ke payer via `_charge_metered_core` baru (badan faithful
  charge_metered live: points_enabled, guard recipient random-aware,
  yukcoin_paid_total + ledger_spend_paid, income hanya female). Guard
  recipient diperluas: kind='random' → penerima wajib peserta call
  (female bisa caller); private tetap wajib callee. `charge_metered` →
  wrapper auth-guard + delegasi; postur grant live dipertahankan
  (dicabut dari authenticated, service_role saja).
  `metered_pricing += match_call {unit_cost:10, cut_pct:70}`.
- **Client:** `CallSession.billingPayer` (default isCaller) — provider
  random-match mengisi `gender=='male'` supaya tick jalan di device payer
  (UX top-up/pause yang benar); tick sekali di detik ~30 agar biaya konek
  ter-charge tepat waktu.
- **Verifikasi:** `match_billing_test.sql` baru 15/15 (grace, konek,
  idempotent, female-caller→male tetap tertagih, insufficient, non-
  participant); `economy_paid_only_test.sql` 27/27; `random_match_test.sql`
  30/30 (assert model lama di-update); `call_billing_toggle_test.sql` 3/3;
  snapshot_functions di-refresh; `check_migrations --all` OK bersih.

## 20261103130000_match_income_ledger_type
- **File:** `20261103130000_match_income_ledger_type.sql` (apply via Management API).
- **Isi:** income per-menit match ditulis `call_video_income` → rincian
  Saldo female salah masuk "Panggilan Privasi" (fee konek sudah benar
  `match_call_income`). `coin_ledger` append-only → fix 3 lapis:
  `_charge_metered_core` + param `p_ledger_type` (pricing tetap p_feature,
  tipe ledger/income/revenue ditulis p_ledger_type; versi 5-arg lama
  di-drop supaya tidak ada overload ambigu); `call_billing_tick` per-menit
  kind='random' → p_ledger_type='match_call'; `get_earnings_summary`
  bucket match_call via JOIN calls(kind='random') → income lama
  `call_video_income` dari call random ikut terhitung match tanpa update
  ledger. Spend male match juga tertulis `match_call`.
- **Client:** tile riwayat `match_call` (spend) → label "Panggilan Match";
  hint saldoWdLocked di bawah tombol withdraw.
- **Verifikasi:** live ChatAja breakdown match_call=12 private_call=0;
  `random_match_test.sql` 35/35 (+6: income type, spend type, earnings
  bucket, regresi baris lama via join); `match_billing_test.sql` 16/16;
  `economy_money_test.sql` 28/28 (claim caller dipulihkan di section 8);
  full suite SQL hijau; `check_migrations --all` OK bersih.

## 20261104000000_call_media_connected_at.sql
- Jangkar billing match ke media CONNECT (bukan pair): kolom
  `calls.media_connected_at`; `touch_call(p_call_id,p_connected)` — overload
  1-arg lama di-drop (default-arg supaya rpc lama tetap resolve, ACL sama);
  `call_billing_tick` elapsed = coalesce(media_connected_at, answered_at)
  untuk kind='random' (client lama → fallback answered_at, bukan regresi);
  `random_match_join` precheck male → `yukcoin_paid_total >= pair+konek`
  (12) supaya match tak dijamin mati di detik 30 untuk male bonus-only.
- Client: `_recordConnected` stamp sekali; `billingFreeGraceSec=30` ke sesi
  → countdown "Gratis Ns" di header random call; `trackMission(match_calls)`
  dipindah ke phase→inCall (gagal connect tak dihitung).
- Applied via Management API; snapshot functions_all di-refresh.

## 20261104010000_match_search_spend_topup.sql
- BUG produksi: `_spend_yukcoin_core` hanya debit earned+bonus — `topup`
  (koin beli uang asli) tidak dihitung → male topup-only tak pernah bisa
  bayar fee pair (joiner di-skip / no_funds). `match_search` kini debit
  bonus → topup → earned (fee ke platform, tanpa penerima → bonus aman);
  fitur 'gift'/'gift_sent' legacy tetap earned+bonus.
- Applied via Management API; economy_money_test §11 di-update ke urutan
  baru (28/28).

## Verifikasi gabungan 2026-11-04
- `random_match_test.sql` 38/38 (precheck paid, kandidat bonus-only diskip,
  funding test dipindah ke bucket topup); `match_billing_test.sql` 21/21
  (jangkar media: pair 45s+media 5s → gratis; media 40s → 30; fallback
  answered_at; touch_call stamp sekali earliest menang);
  `economy_money_test.sql` 28/28; `call_billing_toggle_test.sql` 3/3;
  full suite SQL hijau; `check_migrations --all` OK bersih.

## 20261105000000_callee_billing_info.sql
- `call_billing_tick`: callee kini boleh tick (private sebelumnya ditolak
  "Only caller can be billed"). Billing tetap diarahkan ke payer
  (idempotent — tick dua sisi tidak dobel), respons memuat `income_total`
  (sum ledger `%_income` milik pemanggil) untuk tampilan pendapatan live.
- FIX laten: `v_caller_gender` kini dari `c.caller_id` (bukan `me`) —
  callee-tick random dulu salah resolve payer, callee-tick private bisa
  kena cabang free-female. `v_free_used` dihitung untuk `c.caller_id`.
- Client: `_startBilling` tick juga untuk penerima; `billingIncome` getter;
  banner call = saldo (−N caller / +N penerima); match: (+N) untuk female.
- Stabilitas: `_reconnecting` flag — ICE blip mid-call TIDAK lagi menurunkan
  fase ke connecting (penyebab layar blank+"menghubungkan"); stream lokal
  dipertahankan saat rebuild all-candidates (kamera tak re-init → PiP tak
  blink); chip "Menyambungkan ulang" di UI.
- Applied via Management API; match_billing_test 26/26; full SQL hijau.

## 20261106000000_econ_leak_lockdown.sql
- Fase A review ekonomi (audit): tutup kebocoran uang server-side.
- A1 REVOKE: `_charge_metered_core(6-arg)` dari public/anon/authenticated —
  sebelumnya anon+auth bisa execute (drain koin user lain). `touch_call`
  dicabut dari anon; `yukcoin_paid_total` dicabut dari authenticated
  (klien tak pernah panggil langsung; SECURITY DEFINER internal tetap jalan).
- A2 `call_billing_tick`: `FOR UPDATE` row lock pada calls; guard call
  ended (`v_ended` dari ended_at/status terminal) — elapsed di-cap ke
  ended_at, tick pasca-ended → `can_continue=false, ended=true`, nol
  tagihan baru; recipient read-only (tak lagi memicu charge ke payer —
  income_total tetap dikembalikan untuk UI); `v_caller_gender` dari
  c.caller_id.
- A3 trigger `calls_client_guard_trg` (BEFORE INSERT/UPDATE, hanya saat
  current_user='authenticated'): insert klien dipaksa kind='direct' +
  status='ringing' + answered_at/media_connected_at NULL; update klien
  ditolak bila mengubah kind/answered_at/media_connected_at/caller/callee.
  Status/ended_at tetap boleh (alur answer/hangup normal). Definer RPC
  (current_user=postgres) tak kena.
- A4 idempotensi: unique index (user_id,feature,ref_id,minute) di
  yukcoin_consumptions; advisory lock per-user di ledger_spend_paid +
  _spend_yukcoin_core; trigger coin_ledger_nonneg_trg menolak debit yang
  menjadikan bucket negatif.
- A5: cron `economy-invariant-daily` (25 3 * * * → economy_invariant_cron);
  reversal admin_test_grant di akun male terdaftar (-580, sisa yang masih
  ada — ledger append-only, grant asli tidak dihapus).
- Test: `econ_lockdown_test.sql` 20/20; update match_billing (female tick
  read-only → male tick menagih), random_match (tick pasca-ended),
  points_test & economy_invariants (nonneg guard). Full suite SQL hijau;
  smoke_anon_register OK; snapshot diff = timestamp saja.

## 20261107000000_econ_antifraud_phaseb.sql + 20261107010000_dana_cooldown_save_account.sql
- Fase B (keputusan user): send_coins dipotong seperti gift, tanpa hold
  earned, KYC penuh + cooldown DANA + tx_id.
- app_settings baru: `coin_send_cut_pct` (30), `withdraw_require_kyc`
  (true), `withdraw_dana_change_cooldown_hours` (168).
- send_coins (FROZEN, body dari live): penerima terima NET ke `earned`
  (gross−cut), cut → platform_revenue `coin_send_cut`; respons tambah
  `sent/received/cut_pct`. snapshot send_coins di-refresh.
- request_withdraw: gate KYC (`kyc_requests.approved` → KYC_REQUIRED)
  dipasang SETELAH validasi murah; cooldown ganti nomor DANA →
  DANA_CHANGE_COOLDOWN + `cooldown_until`; `updated_at` withdraw_accounts
  hanya maju saat nomor berubah. Cooldown juga di save_withdraw_account
  (migrasi 010000 — sebelumnya bypass lewat layar ubah akun).
- admin_withdraw_process: signature baru (…, p_tx_id) — approve WAJIB
  tx_id (TX_ID_REQUIRED) dan kolom tx_id terisi; reject tetap tanpa tx_id.
  Admin tab: field "ID Transaksi" di dialog approve.
- get_withdraw_config: + require_kyc, dana_change_cooldown_hours,
  coin_send_cut_pct; klien: WithdrawConfig + error KYC/DANA cooldown
  bilingual (withdraw_screen).
- Test: `econ_antifraud_test.sql` 19/19; update economy_money (net 14+cut6,
  KYC seed), hardening/paid_only/bonus_saldo (KYC seed); full suite hijau.

## Fase C — perbaikan klien (tanpa migrasi; dart saja)
- `call_session.dart`: `_awaitingContinue` HANYA untuk payer (recipient
  read-only → tak pernah lihat dialog Isi YukCoin); `income_total` tak
  di-reset ke +0 saat pause (field absen di respons pause); auto-hangup
  60 dtk saat jeda koin (`_pauseTimer` → `endCallNoCoin`); error tick
  terekam di `billingTickError` → banner koin berubah oranye + ikon seru.
- `nav_gate.dart`/`topup_sheet.dart`: `topupSheet` kini `Future<void>` —
  dialog koin-habis MENUNGGU sheet topup tertutup sebelum resume billing
  (`call_no_coin_dialog.dart` await → `resumeBillingAfterTopup`).
- `call_screen.dart`/`random_call_screen.dart`: `_checkNoCoin` guard
  `session.isBillingPayer` (defense di sisi UI).
- `random_match_provider.dart`: `_joinAgain` gagal → `_fail` (dulu error
  ditelan → state nyangkut 'searching').
- `gifts.dart`: `kMatchFreeMinutes=1` DIHAPUS → `kMatchFreeSeconds=30` +
  `kMatchConnectFeeCoins=10` (selaras billing hibrida server).
  `yukcoinMatchPerMinNote(perMin, freeSec, connectFee)`.
- `earnings_provider.dart`/`withdraw_provider.dart`: reset state saat
  signedOut + uid null (data user lama tak bocor ke akun berikutnya).
- `withdraw_provider.dart`: fallback `minCoins` 2000→1500 (selaras server).
- `profile_ui2.dart`/`profile_ui.dart`/`profile_screen.dart`: estimasi
  fiat earned (`showFiatEst`) hanya untuk female (earned male selalu 0).
- String hardcode dibersihkan: 'Coba lagi'→s.btnRetry (withdraw_screen),
  'Nanti'→s.btnLater (baru), 'Tutup'→s.btnClose (points_provider).
- flutter analyze 0; flutter test 2594/2594; boundary OK.

## 20261108000000_kyc_grant_authenticated.sql (APPLIED)
- Fungsi KYC dibuat tanpa grant — ACL live hanya postgres+service_role →
  klien mendapat `permission denied for function` saat membuka layar KYC.
- GRANT execute ke `authenticated`: `submit_kyc`, `get_my_kyc`,
  `admin_kyc_list`, `admin_kyc_review` (admin_* tetap guard
  `auth.email()='zunixe@gmail.com'` di dalam body — non-admin tetap
  Unauthorized). `anon` tetap tanpa akses.
- Assert baru di `econ_lockdown_test.sql` (25/25): 4 fungsi executable
  authenticated, submit_kyc tidak executable anon.
- Verifikasi live `has_function_privilege` = true×4 / anon false.
