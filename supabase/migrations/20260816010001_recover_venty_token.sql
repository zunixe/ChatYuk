-- ChatYuk: recovery token dummy Venty — refresh token hilang dari auth
-- (refresh_token_not_found saat becomeDummy). Akun auth.users + profile
-- masih utuh; cukup buat sesi + refresh token baru (pola recovery Maria/Sandra
-- di 20260815020004), lalu simpan ke dummy_accounts.
-- ============================================================

do $$
declare
  v_uid text := 'a2810e43-40af-48d4-87ff-d1dfd7d4611b';
  v_sid uuid;
  v_rt text;
begin
  -- Replay bersih: user Venty hanya ada di prod — skip jika tidak ada
  if not exists (select 1 from auth.users where id = v_uid::uuid) then
    return;
  end if;

  -- Buang sesi + refresh token basi milik Venty (force logout semua device)
  delete from auth.refresh_tokens where user_id = v_uid;
  delete from auth.sessions where user_id = v_uid::uuid;

  -- Sesi baru (100 tahun, ala recovery sebelumnya)
  insert into auth.sessions (id, user_id, created_at, updated_at, not_after, aal, refreshed_at)
  values (gen_random_uuid(), v_uid::uuid, now(), now(), now() + interval '100 years', 'aal1', now())
  returning id into v_sid;

  -- Refresh token baru (12 char base62, format GoTrue modern)
  insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, session_id)
  values ('00000000-0000-0000-0000-000000000000'::uuid,
    left(md5(random()::text || clock_timestamp()::text), 12), v_uid, false, now(), now(), v_sid)
  returning token into v_rt;

  -- Simpan ke dummy_accounts supaya becomeDummy bisa dipakai lagi
  update public.dummy_accounts set refresh_token = v_rt where uid = v_uid::uuid;
end;
$$;

-- Token di atas sempat dirotasi sekali saat verifikasi curl (single-use).
-- Simpan hasil rotasi terakhir supaya token di DB selalu yang aktif.
update public.dummy_accounts set refresh_token = 'ag4w7tgn5on2'
where uid = 'a2810e43-40af-48d4-87ff-d1dfd7d4611b';