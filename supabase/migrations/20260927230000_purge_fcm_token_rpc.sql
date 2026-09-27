-- ============================================================
-- RPC purge_fcm_token: bersihkan token FCM mati (permanen).
--
-- Latar: edge send-push mencoba membersihkan token basi via PostgREST
-- (`.from('profiles').update().eq('fcm_token', token)`) TAPI GAGAL —
-- PostgREST tidak bisa memfilter kolom `fcm_token` karena privilege SELECT
-- kolom itu di-revoke (privacy hardening) → update 0 baris (diam-diam).
-- Akibatnya token basi (NotRegistered / SenderIdMismatch) menumpuk.
--
-- RPC ini SECURITY DEFINER (bypass RLS & col-privilege) → bisa hapus token
-- dari profiles & user_devices dengan andal. Hanya service_role yang boleh.
-- ============================================================

create or replace function public.purge_fcm_token(p_token text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_token is null or p_token = '' then return; end if;
  update public.profiles set fcm_token = '' where fcm_token = p_token;
  delete from public.user_devices where fcm_token = p_token;
end;
$$;

revoke execute on function public.purge_fcm_token(text) from public, anon, authenticated; -- SAFE: hanya service_role (edge send-push) yang boleh bersihkan token FCM; tidak ada klien user yang memakai fungsi ini.
grant execute on function public.purge_fcm_token(text) to service_role; -- SAFE: grant rutin RPC internal (hardening standar); dipakai send-push untuk auto-clean token mati.

-- Verifikasi:
--   select proname from pg_proc where proname='purge_fcm_token';
