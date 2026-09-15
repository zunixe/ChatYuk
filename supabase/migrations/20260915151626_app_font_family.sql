-- app_font_family: font global aplikasi, dipilih admin dari panel
-- (Global Setting). Berlaku untuk SEMUA tipografi lewat AppFonts/AppText.
-- Key 'default' = perilaku lama (judul/CTA Poppins, body Roboto);
-- key lain (mis. 'inter') = semua teks pakai font itu.
-- Idempotent. Realtime: app_settings sudah di publication supabase_realtime.
alter table public.app_settings
  add column if not exists app_font_family text not null default 'default';
