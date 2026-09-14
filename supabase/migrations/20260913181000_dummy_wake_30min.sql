-- Bangunkan: default 10 → 30 menit (minta owner).
-- Lewat masa → kembali ikut jadwal/tidur otomatis (gate + tick baca
-- ai_wake_until; tak perlu cleanup khusus).
create or replace function public.admin_wake_dummy(
  p_uid uuid,
  p_minutes integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_until timestamptz;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  v_until := now() + make_interval(mins => least(greatest(coalesce(p_minutes, 30), 1), 120));
  update public.dummy_accounts
     set ai_wake_until = v_until
   where uid = p_uid;
  update public.profiles
     set status = 'online', last_seen = now()
   where id = p_uid and status <> 'invisible';
  return jsonb_build_object('uid', p_uid, 'wake_until', v_until);
end;
$fn$;
