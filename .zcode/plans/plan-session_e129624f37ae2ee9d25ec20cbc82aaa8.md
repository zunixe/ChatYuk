# Rencana: Tuntaskan sisa temuan audit ekosistem koin

## Ringkasan

Review ulang menemukan **masalah yang paling serius: dua perbaikan saya dari kemarin diam-diam dibatalkan** oleh migrasi `20261101190000_paid_only_economy.sql` — file yang **bukan saya buat**, sudah ter-stage di git, dan saya apply setelah migrasi saya sendiri. Karena nomornya lebih besar (190000 > 180000), definisi `request_withdraw`-nya yang menang, dan ia menyalin dari versi lama sehingga membuang perbaikan kuota dan pembulatan fee.

Saya verifikasi sendiri di file, bukan mengandalkan laporan agen:

- `20261101190000_paid_only_economy.sql:417` — `WHERE user_id = v_uid AND created_at >= current_date` **tanpa** `AND status <> 'rejected'`
- `:424` — `WHERE user_id = v_uid` **tanpa** filter status yang sama
- `:457` — `greatest((v_gross * v_fee_pct) / 100, v_fee_min)` — pembagian integer, memotong; client membulatkan

Satu klaim agen ternyata **salah** dan sudah saya cek: gate panggilan sebenarnya sudah memakai `_topupBalance + _earnedBalance` (`points_provider.dart:296`), bukan saldo total. Jadi itu bukan masalah.

---

## FASE 1 — Regresi: pulihkan perbaikan yang dibatalkan

### 1.1 Kuota withdraw tidak lagi dihabisi pengajuan ditolak
`request_withdraw` di `20261101190000:415-429` menghitung kuota harian dan cooldown dari **semua** baris, apa pun statusnya. Pengajuan yang ditolak admin tetap memakan kuota 3/hari dan cooldown 1 jam — persis bug yang saya perbaiki kemarin dan sekarang hidup kembali.

**Fix:** migrasi baru yang menambahkan `AND status <> 'rejected'` pada kedua query.

### 1.2 Fee preview selisih 1 Rp
Server memotong (`/ 100`), client membulatkan (`round()`). Dialog konfirmasi bisa menjanjikan Rp 1 lebih besar dari yang benar-benar diterima.

**Fix:** samakan ke pembulatan, konsisten dengan `WithdrawQuote.calc`.

### 1.3 Zona waktu kuota harian
Kuota memakai `current_date` (UTC) sementara perbaikan zona waktu kemarin hanya diterapkan pada `get_earnings_summary`. Dengan server UTC dan WIB sudah beda hari (terverifikasi: WIB `2026-11-02`, UTC `2026-11-01`), "hari" di sini bisa berbeda dari yang dirasakan user.

**Fix:** pakai `(now() AT TIME ZONE 'Asia/Jakarta')::date`.

---

## FASE 2 — Angka saldo & teks yang menyesatkan

### 2.1 Saldo "bisa ditarik" melebihinya
Terverifikasi: `get_earnings_summary.withdrawable` menjumlahkan **semua bucket** (`20261101180000:98-100`), sementara `request_withdraw` hanya menerima bucket `earned` (`20261101190000:400`). Layar Saldo memakai angka itu sebagai headline (`saldo_screen.dart:40` → `_headline`).

Hari ini angkanya kebetulan sama karena female tidak punya bonus (semua penulis bonus male-only), tapi female dengan koin bonus historis atau top-up di masa depan akan melihat angka yang tidak bisa ditarik.

**Fix:** `withdrawable` di `get_earnings_summary` diubah jadi hanya bucket `earned`, sama dengan `get_wallet.withdrawable` dan validasi server. Tambahkan field terpisah untuk total supaya UI tetap bisa menampilkan keduanya.

### 2.2 String "min. 1500" padahal server 2000
Dua tempat: `strings_points_mx.dart:366-367` (onboarding female) dan `:723` (`wdAmountHint`). User mengetik 1500–1999 akan kena `BELOW_MINIMUM`.

**Fix:** jadikan dinamis dari `config.minCoins` seperti perbaikan error mapping kemarin.

### 2.3 Janji palsu "Semua YukCoin kamu bisa ditarik"
`wdWithdrawableHint` (`:717-718`) — salah sejak koin bonus jadi tidak bisa dicairkan.

**Fix:** ubah jadi "Hanya YukCoin penghasilan yang bisa ditarik".

---

## FASE 3 — Test & CI

### 3.1 Test vacuous (lulus tapi tidak menguji apa pun)
`economy_bonus_saldo_test.sql:151` memanggil `request_withdraw(1500)` padahal minimum live 2000 → server balas `BELOW_MINIMUM` **sebelum** sampai ke logika kuota. Assertion `not in ('DAILY_LIMIT','TOO_SOON')` jadi lulus kosong. Ini menjelaskan kenapa regresi 1.1 tidak terdeteksi.

**Fix:** naikkan ke 2000 (atau baca `withdraw_min_coins`), lalu tambah assertion positif: setelah ada baris `rejected`, request 2000 harus **berhasil** (`ok: true`), bukan cuma "bukan DAILY_LIMIT".

### 3.2 Test untuk perilaku yang tidak ada tesnya
- Batas gratis female 30 menit/hari: saat `free_used >= 30` → `can_continue: false, reason: 'free_limit'` (sekarang hanya jalur di-bawah-limit yang diuji).
- Kuota withdraw: `DAILY_LIMIT`, `TOO_SOON`, `ACCOUNT_TOO_NEW`, dan batas tepat 1999 vs 2000.
- `admin_mass_bonus`: guard email admin, skip female, hanya registered.
- `send_coins`: batas 5..1000 → `Invalid amount`.
- Welcome bonus: batas IP/hari dan `already_claimed`.

### 3.3 Test basi untuk fitur yang sudah dihapus
`economy_money_test.sql` dan `economy_matrix_test.sql` masih menguji `unlock_photo` yang sudah dicabut grant-nya. Ini menyesatkan developer berikutnya.

**Fix:** hapus bagian tersebut.

### 3.4 File baru belum masuk git
Tiga dari empat migrasi baru plus `economy_bonus_saldo_test.sql` masih untracked, sehingga CI menjalankan repo yang berbeda dari yang di-apply ke DB. `run_sql_tests.sh` glob dari disk jadi test-nya jalan lokal, tapi `check_migrations.sh` di CI tidak melihat migrasinya.

**Fix:** `git add` migrasi + test baru (tidak commit — itu keputusan Anda).

---

## FASE 4 — Lubang kecil yang tersisa

- **`get_user_missions` tanpa `SET search_path`** (`20261101160000:19-23`) — sisa dari item 5.1 yang belum tuntas.
- **`claim_mission_reward` tidak cek gender misi** — `nyonya_1000` difilter female hanya di UI (`get_user_missions`), tapi RPC-nya tidak. Male dengan earned ≥ 1000 bisa klaim lewat RPC langsung. Dampak kecil (reward masuk `bonus`, tidak bisa dicairkan), tapi tidak konsisten.
- **`streak_bonus_amount` tanpa REVOKE** — anon bisa memanggil dan membaca tier bonus.
- **`spend_yukcoin` masih ter-grant** dengan semantik gift lama yang menerima `bonus` — tidak ada pemanggil client, permukaan mati.
- **Editor admin mati**: `photo_upload_reward` dan `photo_unlock_owner_pct` masih bisa diedit padahal hanya melayani fitur yang sudah dimatikan.
- **String foto mati**: 7 string paywall foto (`:193-206`) tanpa pemakai.
- **Header migrasi salah tulis**: `20261101190000_paid_only_economy.sql:2` menyebut nama file migrasi lain (copy-paste).
- **Komentar basi**: `missions_provider.dart:218` masih bilang reward misi masuk `earned`, padahal sejak 190000 non-female dapat `bonus`.

---

## FASE 5 — Dokumentasi

`docs/FEATURE_MAP.md` §5 masih menyebut hal yang sudah tidak benar:
- `gate_feature()` dan `gender_filter_paid`/`nearby_paid` masih didaftar sebagai fitur berbayar (keduanya sudah mati/dihapus wiring-nya)
- Tidak menyebut: buka foto dihapus, female gratis 30 menit/hari, minimum withdraw 2000, aturan misi nyonya, ekonomi paid-only
- `:346` masih menunjuk `lib/providers/points_provider.dart` yang sudah dipindah
- `:486` masih bilau `call_billing_tick` mengembalikan 0 untuk `kind='random'` — sekarang hanya 120 detik pertama gratis

`docs/MIGRATION_LOG.md` dan `APPLIED_VIA_API.md` juga masih mengklaim perbaikan kuota-rejected sudah berhasil, yang sekarang terbukti tidak.

**Fix:** perbarui ketiga dokumen agar sesuai keadaan live.

---

## FASE 6 — Verifikasi

1. Test pgTAP baru + perbaikan test basi → `run_sql_tests.sh` semua hijau
2. **Uji regresi secara sad**: setelah migrasi Fase 1, sabotage-test (balikkan filter `rejected`) untuk memastikan test benar-benar gagal — pola yang saya pakai kemarin untuk `daily_login_test`
3. `check_migrations.sh --all` → OK bersih
4. Apply lewat Management API, catat di `APPLIED_VIA_API.md` + `MIGRATION_LOG.md`
5. `snapshot_functions.sh` + review diff
6. `smoke_anon_register.sh`, `flutter analyze` (0/0), `flutter test`
7. `economy_invariant_check` → 0 pelanggaran
8. Build APK rilis + admin, push ke HP yang bisa dihubungi (Redmi Note 9 Pro kemarin tidak respons — akan saya coba ulang)

## Catatan penting

**Pelajaran dari regresi ini:** masalahnya bukan migrasi 190000 itu buruk — isinya benar dan menutup lubang uang yang nyata. Masalahnya ia menyalin `request_withdraw` dari versi lama tanpa menyadari ada perbaikan di atasnya. Untuk mencegah terulang, saya akan tambahkan komentar peringatan urutan di migrasi baru, dan test 3.1 sengaja dibuat agar gagal kalau filter itu hilang lagi.

## Risiko

- **2.1** mengubah angka yang dilihat user di layar Saldo. Untuk female yang hanya punya `earned` (kondisi normal sekarang) angkanya tidak berubah.
- **1.1** mengubah aturan produk: pengajuan ditolak tidak lagi menghabiskan kuota. Kalau Anda justru ingin itu tetap dihitung sebagai anti-spam, beri tahu saya.
- Saya **tidak akan commit** apa pun ke git — hanya `git add` agar CI melihat file baru. Keputusan commit tetap di Anda.