-- ChatYuk: recovery token dummy "haihai" — refresh token hilang dari
-- auth.refresh_tokens (rt_count=0) sehingga becomeDummy gagal
-- "refresh_token_not_found". Akun auth.users + profile masih utuh.
-- Buat sesi + refresh token baru, simpan ke dummy_accounts.
-- ============================================================

do $$
declare
  v_uid uuid := '0d6f0065-e6a0-48c3-8027-7e100eb83da3';
  v_sid uuid;
  v_rt text;
begin
  delete from auth.refresh_tokens where user_id = v_uid::text;
  delete from auth.sessions where user_id = v_uid;

  insert into auth.sessions (id, user_id, created_at, updated_at, not_after, aal, refreshed_at)
  values (gen_random_uuid(), v_uid, now(), now(), now() + interval '100 years', 'aal1', now())
  returning id into v_sid;

  insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, session_id)
  values ('00000000-0000-0000-0000-000000000000'::uuid,
    left(md5(random()::text || clock_timestamp()::text), 12), v_uid::text, false, now(), now(), v_sid)
  returning token into v_rt;

  update public.dummy_accounts set refresh_token = v_rt where uid = v_uid;
end;
$$;
