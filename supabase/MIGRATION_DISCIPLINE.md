# Disiplin Migration — ChatYuk

Aturan main database dev → prod. Tujuannya satu: **promosi ke production
harus mekanis, bukan proyek baru.**

## Aturan Wajib

1. **Semua perubahan schema = file migration baru** di `supabase/migrations/`
   dengan format `YYYYMMDDHHMMSS_deskripsi_singkat.sql`.
   - BOLEH: `supabase migration new tambah_kolom_x`
   - DILARANG: ubah schema via klik di Supabase Studio (local maupun hosted)
     tanpa menuliskannya jadi file migration.
2. **Satu migration = satu tujuan**, idempotent bila memungkinkan
   (`IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`).
3. **Data seed dev** (gift ngarang, user dummy) TIDAK BOLEH masuk folder
   `migrations/` — taruh di `supabase/seeds/dev/` dan jalankan manual.
   Hanya seed prod yang direview boleh jadi migration.
4. **Sebelum merge ke master**: `supabase db reset` harus hijau bersih
   (bukti tidak ada drift antara migration files dan hasil apply).
5. **Promosi ke prod** = `supabase db push` ke project prod setelah backup.
   Tidak pernah copy-paste SQL manual ke dashboard prod.

## Kenapa

File `fix_*.sql` / `schema*.sql` yang terpisah dari `migrations/` adalah pola
lama yang menyebabkan drift schema. Pola itu dilarang mulai sekarang —
semua perubahan tercatat, terurut, dan bisa di-replay kapan saja.

## Checklist Promosi Prod

- [ ] `supabase db reset` hijau di local
- [ ] Daftar migration baru sejak branch `develop` direview
- [ ] Backup project prod
- [ ] `supabase db push` ke prod
- [ ] Seed `gift_catalog` prod via migration yang direview
- [ ] Smoke test: login, buka live, kirim gift 1x
