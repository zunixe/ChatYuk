-- ============================================================
-- Popup update MANUAL: admin bisa memicu popup di app user kapan saja.
--
-- LATAR: popup update selama ini hanya otomatis (klien membandingkan
-- versionName lokal vs app_settings.latest_version saat masuk app). Admin
-- butuh tombol "kirim popup" untuk memaksa popup muncul SEKARANG (mis. user
-- sudah menekan "Nanti"/snooze, atau admin menambah catatan penting).
--
-- PERUBAHAN:
--   1) app_settings += update_push_at timestamptz — stempel waktu push
--      manual terakhir. Klien menyimpan waktu push terakhir yang dilihat
--      (prefs) dan menampilkan popup bila update_push_at lebih baru.
--   2) RPC admin_push_update() — set update_push_at = now(). SECURITY
--      DEFINER + guard is admin (pola sama dgn RPC admin lain).
--
-- Idempotent (add column if not exists, create or replace). Tidak menyentuh
-- fungsi FROZEN. CARA APPLY: Management API (db push HANG di Mac ini).
-- ============================================================

alter table public.app_settings
  add column if not exists update_push_at timestamptz;

create or replace function public.admin_push_update()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- Guard admin: is_admin_request() = pengecekan seragam seluruh RPC admin.
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  update public.app_settings
     set update_push_at = now(),
         updated_at = now()
   where id = 'global';
  return jsonb_build_object('ok', true, 'pushed_at', now());
end;
$fn$;

revoke execute on function public.admin_push_update() from public, anon;
grant execute on function public.admin_push_update() to authenticated, service_role;
