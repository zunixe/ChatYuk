-- Realtime DELETE stories antar-device: tanpa REPLICA IDENTITY FULL, old
-- record event DELETE hanya berisi PK (id) sehingga policy stories_select
-- (butuh author_id/visibility) gagal dievaluasi → Supabase TIDAK mengirim
-- event DELETE ke device lain. Akibat: story yang sudah dihapus/admin-hapus
-- tetap tampil di HP lain sampai refresh manual. FULL mengirim semua kolom
-- lama sehingga policy lolos dan event DELETE sampai ke semua viewer.
alter table public.stories replica identity full;
