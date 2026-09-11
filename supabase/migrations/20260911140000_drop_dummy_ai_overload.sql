-- Hapus overload 3-param admin_set_dummy_ai (PostgREST 300 Multiple
-- Choices saat client kirim 3 named args → tombol Simpan sheet Mode AI
-- selalu gagal). Sisakan versi 4-param (p_schedule_auto opsional) —
-- perilaku 3 param pertama identik.
drop function if exists public.admin_set_dummy_ai(uuid, boolean, jsonb);
