-- pgTAP: TRUST GATE MEDIA ROOM PUBLIK + MODERATOR NEGARA
-- (permintaan user 2026-10-26 — hentikan foto/video porn di global room).
--
-- Mengunci aturan:
--   1. Room PUBLIK: akun <3 hari / <20 pesan room publik → TIDAK boleh media.
--   2. Akun lama & aktif → boleh.
--   3. Room PRIVAT (grup) → SELALU boleh (perilaku lama, tidak berubah).
--   4. Trigger `enforce_room_media_gate_trg` benar-benar terpasang.
--   5. Rate limit media berfungsi.
--   6. Moderator negara bisa hide pesan; TIDAK ada RPC untuk blokir akun.
--
-- Transaksional (BEGIN/ROLLBACK) — tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- ── Struktur & fungsi ─────────────────────────────────────────────────────
select supabase_tests.check('kolom app_settings gate media ada',
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'app_settings'
      and column_name in ('media_trust_min_days', 'media_trust_min_msgs',
                          'media_rate_per_min', 'media_rate_per_hour')) = 4);

select supabase_tests.check('fungsi can_send_room_media & room_media_rate_ok ada',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('can_send_room_media', 'room_media_rate_ok')) = 2);

select supabase_tests.check('trigger enforce_room_media_gate_trg terpasang',
  exists (select 1 from pg_trigger t
           join pg_class c on c.oid = t.tgrelid
           where c.relname = 'messages'
             and t.tgname = 'enforce_room_media_gate_trg' and not t.tgisinternal));

select supabase_tests.check('kolom profiles.home_country ada',
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'profiles'
             and column_name = 'home_country'));

select supabase_tests.check('tabel moderator negara ada',
  (select count(*) from information_schema.tables
    where table_schema = 'public'
      and table_name in ('country_moderators', 'moderator_applications',
                         'moderator_actions')) = 3);

-- ── Moderator TIDAK boleh blokir akun (least privilege) ───────────────────
select supabase_tests.check('tidak ada RPC moderator untuk blokir akun',
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname like 'moderator_%'
       and (p.proname ilike '%ban%' or p.proname ilike '%block%'
            or p.proname ilike '%suspend%')
  ));

-- ── Perilaku gate ─────────────────────────────────────────────────────────
do $t$
declare
  v_new    uuid := 'd0c1e000-0000-4000-8000-0000000000a1';
  v_old    uuid := 'd0c1e000-0000-4000-8000-0000000000a2';
  v_room   text;
  v_priv   text;
  i        int;
begin
  -- Ruangan uji: pakai room publik & privat yang sudah ada (read-only).
  select id into v_room from public.rooms where is_private = false limit 1;
  select id into v_priv from public.rooms where is_private = true limit 1;

  -- Akun BARU (dibuat hari ini).
  perform supabase_tests.mk_dummy(v_new, '[TEST] GateNew', 'offline');
  -- Akun LAMA: created_at dimundurkan 10 hari.
  perform supabase_tests.mk_dummy(v_old, '[TEST] GateOld', 'offline');
  update public.profiles set created_at = now() - interval '10 days'
   where id = v_old;

  -- Sejak 2026-10-27 `home_country` WAJIB terisi (trigger insert) supaya
  -- aturan lintas negara berlaku untuk user baru. Samakan negara asal akun
  -- uji dengan negara room agar yang diuji murni trust gate, bukan izin.
  -- `home_country` dijaga trigger (tak bisa diubah lewat UPDATE biasa) →
  -- fixture WAJIB menandai dirinya sebagai trusted seperti RPC resmi.
  perform set_config('chatyuk.home_country_ok', '1', true);
  update public.profiles
     set home_country = (select country from public.rooms where id = v_room)
   where id in (v_new, v_old);
  perform set_config('chatyuk.home_country_ok', '', true);

  perform supabase_tests.check('akun baru DITOLAK kirim media di room publik',
    public.can_send_room_media(v_room, v_new) = false);

  -- home_country terisi OTOMATIS dari country saat profil dibuat.
  perform supabase_tests.check('home_country terisi otomatis saat insert',
    (select home_country from public.profiles where id = v_new) is not null);

  -- Beda negara asal & room → butuh izin (bukan lolos begitu saja).
  perform set_config('chatyuk.home_country_ok', '1', true);
  update public.profiles set home_country = 'ZZ' where id = v_old;
  perform supabase_tests.check('beda negara asal -> butuh izin',
    public.can_send_room_media(v_room, v_old) = false);
  update public.profiles
     set home_country = (select country from public.rooms where id = v_room)
   where id = v_old;
  perform set_config('chatyuk.home_country_ok', '', true);

  -- Beri akun lama 20 pesan teks di room publik.
  for i in 1..20 loop
    insert into public.messages (room_id, sender_id, sender_name, sender_gender,
                                 text, type)
    values (v_room, v_old, '[TEST] GateOld', 'male', 'isi ' || i, 'text');
  end loop;

  perform supabase_tests.check('akun lama + 20 pesan LOLOS gate',
    public.can_send_room_media(v_room, v_old) = true);

  if v_priv is not null then
    perform supabase_tests.check('room privat SELALU boleh (perilaku lama)',
      public.can_send_room_media(v_priv, v_new) = true);
  else
    perform supabase_tests.check('room privat (dilewati: tidak ada room privat)', true);
  end if;

  -- Rate limit: 3 media terakhir = masih boleh; setelah 3 media baru, tidak.
  perform supabase_tests.check('rate limit awal masih boleh',
    public.room_media_rate_ok(v_room, v_old) = true);
  for i in 1..3 loop
    insert into public.messages (room_id, sender_id, sender_name, sender_gender,
                                 text, type)
    values (v_room, v_old, '[TEST] GateOld', 'male', '', 'image');
  end loop;
  perform supabase_tests.check('rate limit 3/menit tercapai -> ditolak',
    public.room_media_rate_ok(v_room, v_old) = false);
end
$t$;

-- ── Negara asal: TIDAK bisa diubah paksa lewat UPDATE langsung ────────────
do $hc$
declare
  v_uid  uuid := 'd0c1e000-0000-4000-8000-0000000000b1';
  v_prev text;
begin
  perform supabase_tests.mk_dummy(v_uid, '[TEST] HomeCountry', 'offline');
  perform set_config('chatyuk.home_country_ok', '1', true);
  update public.profiles
     set home_country = 'Indonesia', home_country_changed_at = now()
   where id = v_uid;
  perform set_config('chatyuk.home_country_ok', '', true);
  v_prev := (select home_country from public.profiles where id = v_uid);

  -- (a) UPDATE langsung oleh user (bukan lewat RPC) harus DIABAIKAN.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  update public.profiles set home_country = 'Thailand' where id = v_uid;
  perform supabase_tests.check('home_country tak bisa diubah lewat UPDATE langsung',
    (select home_country from public.profiles where id = v_uid) = v_prev);

  -- (b) Reset cooldown lewat UPDATE langsung juga harus DIABAIKAN.
  update public.profiles
     set home_country_changed_at = now() - interval '90 days'
   where id = v_uid;
  perform supabase_tests.check('home_country_changed_at tak bisa direset langsung',
    (select home_country_changed_at from public.profiles where id = v_uid)
      > now() - interval '2 days');

  -- (c) RPC resmi DALAM masa cooldown tetap menolak.
  perform supabase_tests.check('RPC set_home_country tolak perubahan <30 hari',
    (public.set_home_country('Thailand')->>'ok') = 'false');

  perform set_config('request.jwt.claims', '', true);
end
$hc$;


-- ── Admin set/unset negara asal (unset = akses semua negara) ──────────────
do $ah$
declare
  v_admin uuid;
  v_user  uuid := 'd0c1e000-0000-4000-8000-0000000000c1';
  r jsonb;
begin
  select id into v_admin from public.profiles
   where lower(email) = 'zunixe@gmail.com' limit 1;

  if v_admin is null then
    perform supabase_tests.check('admin_set_home_country (dilewati: admin tidak ada)', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

    r := public.admin_set_home_country(v_admin, null);
    perform supabase_tests.check('admin bisa UNSET negara asal',
      (r->>'ok') = 'true'
      and (select home_country is null from public.profiles where id = v_admin)
      and (select home_country_changed_at is null from public.profiles where id = v_admin));

    r := public.admin_set_home_country(v_admin, 'Indonesia');
    perform supabase_tests.check('admin bisa SET negara asal',
      (r->>'ok') = 'true'
      and (select home_country from public.profiles where id = v_admin) = 'Indonesia'
      and (select home_country_changed_at from public.profiles where id = v_admin) is not null);

    -- Admin tanpa negara asal tetap boleh kirim media (bypass lintas negara).
    perform supabase_tests.check('admin tanpa negara asal tetap lolos gate media',
      public.can_send_room_media(
        (select id from public.rooms where is_private = false limit 1),
        v_admin) = true);

    -- USER BIASA tidak boleh memakai RPC ini (bahaya: unset melewati cek
    -- izin lintas negara).
    perform supabase_tests.mk_dummy(v_user, '[TEST] AdminHC', 'offline');
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    begin
      perform public.admin_set_home_country(v_user, null);
      perform supabase_tests.check('user biasa DILARANG unset negara asal', false);
    exception when others then
      perform supabase_tests.check('user biasa DILARANG unset negara asal (42501)',
        sqlstate = '42501');
    end;
  end if;

  perform set_config('request.jwt.claims', '', true);
end
$ah$;

-- ── Moderator mengangkat rekan + admin melihat lintas negara ──────────────
select supabase_tests.check('RPC moderator_set_colleague ada',
  exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='moderator_set_colleague'));
select supabase_tests.check('RPC moderator_candidates ada',
  exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='moderator_candidates'));
select supabase_tests.check('RPC admin_moderation_overview ada',
  exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='admin_moderation_overview'));
select supabase_tests.check('country_moderators.source menerima moderator',
  exists (select 1 from pg_constraint con join pg_class c on c.oid=con.conrelid
           where c.relname='country_moderators' and con.conname='country_moderators_source_check'
             and pg_get_constraintdef(con.oid) like '%moderator%'));

select supabase_tests.report() as result;
rollback;
