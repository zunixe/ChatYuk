# Insiden: hapus akun gagal 23502 untuk user ber-device (2026-09-23)

## Gejala
- Hapus akun (ketik HAPUS → tombol aktif → eksekusi) selalu gagal dengan
  snackbar `errDeleteAccount`, di Xiaomi maupun Huawei. Retry ("masih gagal").
- Akun tanpa device row (kasus uji awal) lolos — bug tak terdeteksi.

## Akar masalah (terbukti via reproduksi JWT anon asli)
`delete_my_account()` → `delete from public.profiles` memicu FK
`user_devices.user_id` / `user_location_history.user_id` yang aksinya
**SET NULL**, tetapi kedua kolom `user_id` itu **NOT NULL**:
```text
ERROR 23502: null value in column "user_id" of relation "user_devices"
CONTEXT: UPDATE user_devices SET user_id = NULL ... (FK SET NULL)
         saat `delete from public.profiles` — delete_my_account() line 57
```
Komentar lama ("hardware milik install, FK SET NULL") salah asumsi.
Praktis SEMUA user nyata punya device row → hapus akun rusak total.

## Perbaikan (server-side, tanpa ubah aplikasi)
- Migrasi `20260923130000_delete_account_devices_fix.sql`: hapus eksplisit
  `user_devices` + `user_location_history` milik user SEBELUM `delete profiles`.
  Selaras privasi (hapus akun = hapus jejak) + syarat hapus-akun Google Play.
  Hardware re-register via `syncToServer`; exclusion admin (berbasis
  install_id di tabel lain) tidak ikut terhapus.
- Grant tidak diubah. Bukan fungsi FROZEN.
- Terverifikasi live: anon + device + location + ledger → `{"ok": true}`,
  cleanup sisa 0.

## Pencegahan
- Dikunci: `supabase/tests/delete_account_test.sql` (4 assert: ada-nya hapus
  eksplisit, urutan SEBELUM profiles, komentar usang hilang).
- Pelajaran umum: **SET NULL hanya valid bila kolomnya nullable** — setiap
  FK `ON DELETE SET NULL` wajib dipasangkan dengan cek nullability kolom
  (lihat tabel verifikasi di bawah). Jangan percaya komentar lama.
- Saat debug "gagal hapus": reproduksi sebagai JWT user ASLI (atau
  akun test ber-data), bukan anon kosong — kasus kosong menutupi bug ini.

## Verifikasi SET NULL vs nullable (2026-09-23, kode mentah confdeltype)
| Tabel.kolom | Aksi FK | Nullable | Aman? |
|---|---|---|---|
| `user_devices.user_id` | SET NULL (110) | NO | ❌ → diperbaiki (hapus eksplisit) |
| `user_location_history.user_id` | SET NULL (110) | NO | ❌ → diperbaiki (hapus eksplisit) |
| `contact_messages.user_id` | SET NULL (110) | YES | ✅ aman |
| `profiles.referred_by` | SET NULL | YES | ✅ aman |
| ke `auth.users` | semua CASCADE kecuali `scim_users` (SET NULL, fitur tak dipakai) | — | ✅ aman |
