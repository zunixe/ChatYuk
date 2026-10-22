-- Tutup kebocoran `app_settings.app_shared_secret` ke anon/authenticated.
--
-- Riwayat: 20260915120000 me-revoke SELECT level tabel lalu grant kolom aman.
-- 20260922130000 kembali `grant select on public.app_settings` (level TABEL)
-- untuk memperbaiki popup update (kolom latest_version/min_version belum
-- masuk daftar grant kolom) → secret ikut terbaca lewat REST publishable key
-- (terverifikasi 2026-10-22: anon `select=app_shared_secret` → HTTP 200).
--
-- Fix: revoke level tabel, lalu grant SELECT ke SEMUA kolom KECUALI daftar
-- rahasia. Dinamis supaya kolom yang dibaca klien (latest_version dsb.) tidak
-- ketinggalan seperti insiden 2026-09-22.
-- PENTING: kolom BARU di app_settings setelah migrasi ini TIDAK otomatis
-- terbaca klien — tambahkan `grant select (<kolom>) ... to anon, authenticated`
-- di migrasinya. Guard: supabase/tests/app_settings_secret_test.sql.
--
-- Klien & edge function selalu select kolom eksplisit (tanpa `*`), dan
-- trigger/cron membaca secret sebagai pemilik/SECURITY DEFINER → tidak terdampak.

revoke select on table public.app_settings from anon, authenticated; -- SAFE: tabel app_settings (bukan tabel bersama); klien+edge select kolom eksplisit; terdampak: popup update, setting global, poin, presence AI — semua kolom non-rahasia di-grant ulang di bawah

do $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into v_cols
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'app_settings'
    and column_name not in ('app_shared_secret');
  execute format(
    'grant select (%s) on public.app_settings to anon, authenticated', v_cols); -- SAFE: grant kolom non-rahasia app_settings; terdampak: popup update, setting global, poin, presence AI
end $$;
