# Insiden: "Masuk Anon" gagal di semua HP (2026-09-22)

## Gejala
- Klik **"Mulai Chat Sekarang"** (anon) gagal di Xiaomi DAN Huawei → snackbar
  error generik, user tidak masuk-masuk.
- Google Sign-In juga gagal di Huawei (masalah TERPISAH — Huawei tanpa GMS,
  memang tidak bisa; di luar cakupan insiden ini).

## Fakta yang menyesatkan
- `auth.users` TERISI user anon baru → `signInAnonymously()` **berhasil**.
- `profiles` KOSONG untuk user-user itu → yang gagal = pembuatan profil.

## Akar masalah (terbukti via reproduksi REST sebagai anon asli)
`registerProfile()` memakai:
```dart
_sb.from('profiles').upsert({...}, onConflict: 'id')   // merge-duplicates
```
PostgREST `ON CONFLICT DO UPDATE` butuh grant **SELECT di semua kolom yang
ditulis**. Hardening privasi (`security_hardening` + susulannya) mencabut
SELECT untuk `status`, `avatar`, `last_seen` — kolom yang WAJIB ditulis saat
registrasi. Hasil:
```json
{"code":"42501","message":"permission denied for table profiles",
 "hint":"GRANT SELECT ON public.profiles TO authenticated;"}
```
Retry di provider (`signOut` + anon baru + ulangi) gagal dengan cara yang
sama → user stuck. Berlaku untuk SEMUA pendaftaran baru (anon/Google/email),
bukan cuma anon.

## Perbaikan (tanpa menyentuh hardening privasi!)
`lib/services/auth_service_profile.dart` — pola split-write:
1. `upsert(row, onConflict: 'id', ignoreDuplicates: true)` → INSERT ...
   `ON CONFLICT DO NOTHING` — **tidak butuh SELECT**, cukup INSERT + RLS.
2. `update(row-tanpa-id).eq('id', uid)` → untuk baris yang sudah ada —
   cukup UPDATE + RLS own.

Terverifikasi langsung ke DB live sebagai anon:
- `merge-duplicates` → 42501 (pola lama, gagal) ✅ terbukti rusak
- `ignore-duplicates` → 201 (fresh + re-register, idempoten) ✅
- `PATCH update` → 204 ✅

JANGAN perbaiki dengan `GRANT SELECT` ke `status`/`avatar`/`last_seen` —
itu membuka kembali bacaan langsung yang ditutup hardening privasi
(`profiles_select` adalah `USING (true)` = publik!).

## Pencegahan (cek SEBELUM rilis bila menyentuh auth/profiles/grant)
- [ ] Setiap kolom BARU yang ditulis saat registrasi → pastikan ada di kontrak
      test `test/regression/r_auth_sensitive_cols_test.dart`.
- [ ] Setiap migrasi yang `REVOKE ... SELECT` di `profiles` → jalankan
      reproduksi anon (signup + upsert + update via REST anon key) dan
      pastikan 201/204, bukan 42501.
- [ ] Jangan pernah pakai `upsert()` merge-duplicates di tabel yang kolomnya
      di-revoke SELECT-nya. Pola aman: `ignoreDuplicates: true` + `PATCH`.
- [ ] Test regression di atas MENGUNCI kontrak ini — bila diubah, test merah.

## Data test insiden ini (sudah dibersihkan tuntas)
- 3 akun anon (`09a5768d…`, `f1330d53…`, `b622a5ed…`) + 1 profil
  (`TestFix456`) + ledger-nya → **dihapus semua** (ledger via pola
  `session_replication_role='replica'` seperti `delete_my_account`).
- Verifikasi akhir: `users=0, profiles=0`, role kembali `origin`.
