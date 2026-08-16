-- ============================================================
-- ChatYuk: admin_renew_dummy_token — regenerasi sesi dummy yang
-- token-nya basi/hilang (refresh_token_not_found). Dipakai sebagai
-- fallback di becomeDummy supaya "Chat Sebagai" SELALU berhasil
-- tanpa bergantung token lama di dummy_accounts.
-- Membuat session baru + refresh_token baru (100 th), simpan ke
-- dummy_accounts, return token.
-- ============================================================

create or replace function public.admin_renew_dummy_token(p_uid uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sid uuid;
  v_rt text;
  v_is_dummy boolean;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  -- Pastikan uid memang akun dummy.
  select exists (select 1 from public.dummy_accounts d where d.uid = p_uid)
  into v_is_dummy;
  if not v_is_dummy then
    raise exception 'not_a_dummy';
  end if;

  -- Buang sesi + refresh token basi milik dummy ini.
  delete from auth.refresh_tokens where user_id = p_uid::text;
  delete from auth.sessions where user_id = p_uid;

  insert into auth.sessions (id, user_id, created_at, updated_at, not_after, aal, refreshed_at)
  values (gen_random_uuid(), p_uid, now(), now(), now() + interval '100 years', 'aal1', now())
  returning id into v_sid;

  insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, session_id)
  values ('00000000-0000-0000-0000-000000000000'::uuid,
    left(md5(random()::text || clock_timestamp()::text), 12), p_uid::text, false, now(), now(), v_sid)
  returning token into v_rt;

  update public.dummy_accounts set refresh_token = v_rt where uid = p_uid;

  return v_rt;
end;
$$;

revoke execute on function public.admin_renew_dummy_token(uuid) from public, anon;
grant execute on function public.admin_renew_dummy_token(uuid) to authenticated, service_role;
