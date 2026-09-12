-- HOLD sesi dummy: saat admin "masuk dummy", AI milik dummy itu DIVAKUM
-- (tidak pernah membalas otomatis — manusia yang memegang akunnya).
-- Kembali ke admin → hold lepas → AI lanjut normal.
alter table public.dummy_accounts
  add column if not exists ai_hold_active boolean not null default false;

create or replace function public.set_dummy_hold(p_uid uuid, p_held boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  update public.dummy_accounts set ai_hold_active = p_held where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.set_dummy_hold(uuid, boolean) from public, anon;
grant execute on function public.set_dummy_hold(uuid, boolean) to authenticated, service_role;
