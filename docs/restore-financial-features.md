# Restore Fitur Finansial (Top-Up, KYC, Withdraw)

> **Dokumen ini adalah panduan untuk mengembalikan fitur finansial** yang telah
> dihapus dari `main` (Agustus 2026) agar aplikasi Play-safe. Seluruh kode
> lama tersimpan permanen di git tag `archive/financial-features`.

## Latar Belakang

Fitur finansial dihapus total karena:
- Google Play **tidak mengizinkan** cash-out virtual currency ke uang riil
  untuk app berisi digital goods (Financial Services policy + butuh izin
  money transfer BI di Indonesia).
- Top-up via iPaymu/Midtrans melanggar Payments policy (wajib Google Play
  Billing untuk digital goods).
- Menyembunyikan fitur finansial di flavor Play berisiko dikategorikan
  **deceptive behavior** oleh Google Play.

Setelah penghapusan, aplikasi (kedua flavor) menjadi app chat murni dengan
koin sebagai **digital goods** (bonus → fitur premium, tanpa uang masuk/keluar).

---

## Arsip Kode (Tidak Pernah Hilang)

```
git tag    archive/financial-features   # titik sebelum penghapusan
git branch archive/financial-legacy     # cadangan branch (safety net)
```

Keduanya dibuat di commit `450e3fc` (versi 1.2.5+19).

---

## Cara Restore

### 1. Restore Kode Aplikasi

**A. 9 file yang dihapus total** — restore utuh (aman, tidak bentrok):

```bash
git checkout archive/financial-features -- \
  lib/screens/top_up_screen.dart \
  lib/screens/kyc_screen.dart \
  lib/screens/withdraw_screen.dart \
  lib/screens/withdrawal_history_screen.dart \
  lib/screens/admin_kyc_screen.dart \
  lib/screens/admin_withdrawal_screen.dart \
  lib/screens/admin_revenue_screen.dart \
  lib/services/topup_service.dart \
  lib/services/kyc_service.dart
```

**B. 6 file yang diedit** — restore **selektif** (jangan restore utuh agar
tidak menimpa perubahan bugfix baru di `main`):

| File | Yang harus dikembalikan |
|---|---|
| `lib/config/app_flavor.dart` | getter `topupEnabled`, `showCashOut`, `topupProvider` (lihat blok di bawah) |
| `lib/providers/points_provider.dart` | `_topupBalance`, getter `topupBalance`, `withdrawableBalance`; `paidBalance = _topupBalance + _earnedBalance`; baris `_topupBalance = w['topup']` di `refreshWallet` |
| `lib/services/points_service.dart` | metode `withdrawalSummary`, `requestWithdrawal`, `myWithdrawals`, `adminWithdrawals`, `adminRevenueOverview`, `adminWithdrawalReview` |
| `lib/screens/profile_screen.dart` | import 4 screen finansial; menu `TopUpScreen`/`KycScreen`/`WithdrawScreen` di `_ActionGrid`; rincian bucket (kelas `_BucketRow`) |
| `lib/screens/admin_panel_screen.dart` | import 3 screen; kartu `_revenue`, `_kycReview`, `_withdrawReview` + pemanggilannya |
| `lib/config/strings.dart` | semua getter KYC/Withdraw/Revenue/TopUp (lihat daftar di bawah) |

Cara membandingkan & menyalin selektif:

```bash
# Lihat daftar metode/ getter yang dihapus
git diff archive/financial-features -- lib/services/points_service.dart

# Ambil isi versi lama untuk disalin balik manual
git show archive/financial-features:lib/services/points_service.dart
```

Contoh blok `app_flavor.dart` yang dikembalikan:

```dart
static bool get showCashOut => !isPlay;
static bool get topupEnabled => !isPlay;
static String get topupProvider => isPlay ? 'play_billing' : 'ipaymu';
```

### 2. Restore Server (Supabase)

Tabel **tidak pernah di-drop** — data topup_orders / kyc_requests /
withdrawal_requests tetap ada. Cukup re-enable fungsi + edge functions.

**A. Edge functions** (folder `supabase/functions/` tetap di repo):

```bash
supabase functions deploy ipaymu-create ipaymu-callback ipaymu-return topup-create topup-webhook
```

**B. RPC finansial** — jalankan migrasi SQL berikut (urutan kronologis,
`create or replace` = idempotent, aman dijalankan ulang):

| File migrasi | Isi finansial |
|---|---|
| `supabase/migrations/20260814240000_topup_midtrans_phase2.sql` | Tabel `topup_packages`, `topup_orders`; RPC `list_topup_packages`, `create_topup_order`, `credit_topup_order`, `get_my_topup_orders` |
| `supabase/migrations/20260814250000_gift_platform_cut_phase3.sql` | RPC `admin_gift_revenue` |
| `supabase/migrations/20260814260000_kyc_phase4.sql` | Tabel `kyc_requests`; RPC `submit_kyc`, `get_my_kyc`, `admin_kyc_list`, `admin_kyc_review` |
| `supabase/migrations/20260814270000_withdrawal_phase5.sql` | Tabel `withdrawal_requests`; RPC `request_withdrawal`, `get_my_withdrawals`, `admin_withdrawal_list`, `admin_withdrawal_review`, `withdrawal_summary` |
| `supabase/migrations/20260814280000_antifraud_phase6.sql` | Versi lanjutan `request_withdrawal` (anti-fraud) |
| `supabase/migrations/20260815000000_admin_revenue_phase7.sql` | RPC `admin_revenue_overview` |
| `supabase/migrations/20260815120000_photo_paywall_point_settings.sql` | RPC `ledger_spend_topup` |

Jalankan via SQL Editor di dashboard Supabase (project yang sama — karena
sekarang satu project untuk kedua store).

> Catatan: `get_wallet` dan bucket ledger (`wallet_ledger_phase1`) **tetap
> aktif** — itu bukan finansial, dipakai untuk logika gift & fitur premium.

### 3. Verifikasi Restore

```bash
flutter analyze                                # 0 error, 0 warning
flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
# Audit APK: string finansial HARUS MUNCUL kembali (berlawanan dengan proses hapus)
```

---

## Daftar Getter Strings yang Dihapus

Berikut getter yang harus dikembalikan ke `lib/config/strings.dart` bila
restore (nilai asli ambil dari `git show archive/financial-features:lib/config/strings.dart`):

- **KYC**: `kycTitle`, `kycFullName`, `kycIdType`, `kycIdTypeKtp`,
  `kycIdTypePassport`, `kycIdNumber`, `kycBirthDate`, `kycOptional`,
  `kycAgeMin`, `kycIdPhoto`, `kycSelfie`, `kycHint`, `kycSubmit`,
  `kycSubmitted`, `kycAlreadySubmitted`, `kycSubmitFailed`, `kycErrName`,
  `kycErrIdNumber`, `kycErrPhotos`, `kycStatusNone`, `kycStatusPending`,
  `kycStatusApproved`, `kycStatusRejected`, `menuKyc`, `kycRejectTitle`,
  `kycRejectReason`, `kycApprovedToast`, `kycRejectedToast`, `kycNoRequests`,
  `btnApprove`, `btnReject`, `btnRefresh`
- **Admin KYC**: `adminKycTitle`, `adminKycDesc`
- **Withdraw**: `withdrawTitle`, `withdrawBalance`, `withdrawRate`,
  `withdrawOnlyEarned`, `withdrawAmount`, `withdrawMethod`,
  `withdrawMethodQris`, `withdrawMethodBank`, `withdrawMethodEwallet`,
  `withdrawQrisId`, `withdrawAccountNo`, `withdrawHolder`, `withdrawSubmit`,
  `withdrawPreview`, `withdrawPreviewHint`, `withdrawBelowMin`,
  `withdrawInsufficient`, `withdrawInvalidPayout`, `withdrawConfirmTitle`,
  `withdrawConfirmBody`, `withdrawRequested`, `withdrawKycRequired`,
  `withdrawFailed`, `withdrawHistory`, `withdrawNoHistory`,
  `withdrawStatusPending`, `withdrawStatusPaid`, `withdrawStatusRejected`,
  `withdrawTxId`, `withdrawNote`
- **Admin Withdraw**: `adminWithdrawTitle`, `adminWithdrawDesc`, `withdrawPay`,
  `withdrawPayTxId`, `withdrawPayConfirm`, `withdrawPaidToast`,
  `withdrawRejectedToast`, `withdrawRejectTitle`, `withdrawNoRequests`
- **Revenue**: `adminRevenueTitle`, `adminRevenueDesc`, `adminRevenueGift`,
  `adminRevenueCutTotal`, `adminRevenueCutToday`, `adminRevenueGross`,
  `adminRevenueGiftCount`, `adminRevenueTopGifts`, `adminRevenueWithdraw`,
  `adminRevenuePending`, `adminRevenuePaid`, `adminRevenueRejected`,
  `adminRevenueSettings`, `adminRevenueCutPct`, `adminRevenueRate`,
  `adminRevenueNoData`
- **TopUp**: `topupTitle`, `topupPickPackage`, `topupBuy`, `topupInfo`,
  `topupWaitingTitle`, `topupWaitingBody`, `topupCheckStatus`, `topupSuccess`,
  `topupStillPending`, `topupFailed`
- **Wallet**: `walletWithdrawable`, `walletBonusHint`, `walletTopupHint`,
  `walletEarnedHint`

---

## PENTING — Sebelum Restore untuk Google Play

1. **JANGAN aktifkan di Play tanpa Google Play Billing** — iPaymu/Midtrans
   adalah provider terlarang untuk digital goods di Play (Payments policy).
2. **Cash-out (withdraw) tidak akan pernah kompatibel dengan Play** untuk app
   berisi digital goods. Kalau mau monetisasi di Play: integrasi **Google Play
   Billing** (Billing Library v8+) adalah kode baru, bukan dari tag ini.
3. Setelah restore, lakukan audit APK (string finansial muncul) + isi ulang
   **Financial features declaration** di Play Console.
