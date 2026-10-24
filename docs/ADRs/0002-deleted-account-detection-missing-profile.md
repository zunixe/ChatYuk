# ADR-0002: Deteksi "Akun dihapus" berbasis missing profile — risiko salah label

- Status: **Diterima (catat risiko)** — 2026-10-22
- Konteks: fitur "Akun dihapus" menandai bubble/room/chat list dengan label
  redup + snack bila profil lawan bicara tidak ditemukan.

## Keputusan

Deteksi memakai **kehadiran baris** di `public.profiles`:
`missingProfileUids(uids)` = uid yang TIDAK ada hasil SELECT-nya dianggap
"akun dihapus" (`lib/services/chat_service_private.dart:165-176`).

## Mengapa aman SAAT INI (diverifikasi live 2026-10-22)

- Policy `profiles_select` = `using (true)` — semua profil terbaca oleh
  `authenticated`; TIDAK ada mekanisme menyembunyikan profil
  (tidak ada kolom `invisible`/`hidden`/`deleted` di `profiles`;
  527 baris, 0 berstatus `deleted`).
- Hapus akun = **hard DELETE** baris profile (migrasi
  `20260923130000_delete_account_devices_fix.sql` — hapus device + location
  SEBELUM profile; lihat `docs/INCIDENT_DELETE_ACCOUNT_23502.md`).
- Query gagal (offline/error) mengembalikan **null** — pemanggil WAJIB tidak
  menganggap semua terhapus (kontrak di doc-comment).

## Risiko bila konteks berubah

1. **Soft-delete profil** (mis. `deleted_at` di-set, baris dipertahankan untuk
   kepatuhan): klien akan salah label "Akun dihapus" padahal baris masih ada —
   atau sebaliknya bila baris difilter policy, pesan lama tampil normal.
2. **Policy SELECT dipersempit** (mis. hanya user aktif terbaca, pola
   hardening `presence`): semua uid non-aktif terlihat "hilang" → salah label
   massal.
3. **Mode ghost/invisible profile** baru: profil ada tapi tak terbaca klien →
   salah label "dihapus".

## Kontrak pemakaian (WAJIB bagi kode baru)

- Selalu lewat `DeletedUserBuilder` (cek ter-batch, rebuild ter-target).
- JANGAN menandai "dihapus" dari kegagalan jaringan — hanya dari hasil query
  yang sukses (`missingProfileUids` sudah menangani ini lewat kontrak null).
- Bila salah satu risiko di atas terjadi, ganti deteksi ke kolom eksplisit
  (mis. `profiles.deleted_at`) dan lakukan migrasi — JANGAN menaikkan heuristik.

## Konsekuensi

- Tidak ada perubahan skema. Deteksi tetap "keberadaan baris" sampai ada
  kebutuhan nyata (soft-delete / ghost mode) — saat itu buat migrasi kolom
  `deleted_at` + ubah `missingProfileUids` sekali di satu tempat.
