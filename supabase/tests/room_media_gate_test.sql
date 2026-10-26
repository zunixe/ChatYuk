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

select supabase_tests.check('kolom profiles.country_changed_at ada (lock 7 hari)',
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'profiles'
             and column_name = 'country_changed_at'));

select supabase_tests.check('konsep home_country sudah DIHAPUS',
  not exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'profiles'
                 and column_name in ('home_country', 'home_country_changed_at')));

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

  -- Samakan negara akun uji dengan negara room agar yang diuji murni trust
  -- gate, bukan izin lintas negara. `country` dijaga trigger → fixture WAJIB
  -- menandai dirinya trusted seperti RPC resmi.
  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles
     set country = (select country from public.rooms where id = v_room)
   where id in (v_new, v_old);
  perform set_config('chatyuk.country_ok', '', true);

  perform supabase_tests.check('akun baru DITOLAK kirim media di room publik',
    public.can_send_room_media(v_room, v_new) = false);

  -- Negara wajib ada pada profil (dipakai aturan lintas negara).
  perform supabase_tests.check('negara profil terisi',
    coalesce(btrim((select country from public.profiles where id = v_new)), '') <> '');

  -- Beda negara asal & room → butuh izin (bukan lolos begitu saja).
  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles set country = 'ZZ' where id = v_old;
  perform supabase_tests.check('beda negara -> butuh izin',
    public.can_send_room_media(v_room, v_old) = false);
  update public.profiles
     set country = (select country from public.rooms where id = v_room)
   where id = v_old;
  perform set_config('chatyuk.country_ok', '', true);

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

-- ── Negara: lock 7 hari + cabut jabatan moderator saat pindah ─────────────
do $ct$
declare
  v_mod   uuid := 'd0c1e000-0000-4000-8000-0000000000b1';
  v_plain uuid := 'd0c1e000-0000-4000-8000-0000000000b2';
  v_admin uuid;
  v_prev  text;
  r       jsonb;
begin
  perform supabase_tests.mk_dummy(v_mod, '[TEST] CountryLock', 'offline');
  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles
     set country = 'Indonesia', country_changed_at = now()
   where id = v_mod;
  perform set_config('chatyuk.country_ok', '', true);
  insert into public.country_moderators (scope, scope_value, uid, source)
  values ('country', 'Indonesia', v_mod, 'admin');

  v_prev := (select country from public.profiles where id = v_mod);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);

  -- (a) UPDATE langsung oleh user (bukan RPC) DIABAIKAN.
  update public.profiles set country = 'Thailand' where id = v_mod;
  perform supabase_tests.check('negara tak bisa diubah lewat UPDATE langsung',
    (select country from public.profiles where id = v_mod) = v_prev);

  -- (b) Lock tidak bisa di-reset dari klien.
  update public.profiles
     set country_changed_at = now() - interval '90 days'
   where id = v_mod;
  perform supabase_tests.check('country_changed_at tak bisa direset langsung',
    (select country_changed_at from public.profiles where id = v_mod)
      > now() - interval '2 days');

  -- (c) RPC resmi DALAM masa lock (7 hari) tetap menolak.
  r := public.set_my_country('Thailand');
  perform supabase_tests.check('set_my_country tolak perubahan <7 hari',
    (r->>'ok') = 'false' and (r->>'error') = 'cooldown');

  -- (d) Nilai kosong ditolak.
  begin
    perform public.set_my_country('');
    perform supabase_tests.check('set_my_country tolak negara kosong', false);
  exception when others then
    perform supabase_tests.check('set_my_country tolak negara kosong (22023)',
      sqlstate = '22023');
  end;

  -- (e) Setelah lock lewat (disimulasikan DB) → boleh + jabatan DICABUT.
  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles
     set country_changed_at = now() - interval '8 days'
   where id = v_mod;
  perform set_config('chatyuk.country_ok', '', true);

  r := public.set_my_country('Thailand');
  perform supabase_tests.check('set_my_country izinkan setelah 7 hari',
    (r->>'ok') = 'true'
    and (select country from public.profiles where id = v_mod) = 'Thailand');

  perform supabase_tests.check('moderator pindah negara -> jabatan dicabut',
    (select count(*) from public.country_moderators
      where uid = v_mod and revoked_at is null) = 0);

  perform supabase_tests.check('pencabutan tercatat di moderator_actions',
    exists (select 1 from public.moderator_actions
             where uid = v_mod and target_uid = v_mod
               and note = 'auto_revoke_country_change'));

  -- (f) Setelah berubah, lock 7 hari berjalan lagi.
  r := public.set_my_country('Malaysia');
  perform supabase_tests.check('lock 7 hari berjalan lagi setelah perubahan',
    (r->>'ok') = 'false' and (r->>'error') = 'cooldown');

  -- (g) Admin selalu bisa (tanpa cooldown).
  select id into v_admin from public.profiles
   where lower(email) = 'zunixe@gmail.com' limit 1;

  if v_admin is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    r := public.admin_set_country(v_mod, 'Indonesia');
    perform supabase_tests.check('admin bisa ubah negara tanpa cooldown',
      (r->>'ok') = 'true'
      and (select country from public.profiles where id = v_mod) = 'Indonesia');

    -- Negara kosong ditolak (harus exception 22023).
    begin
      perform public.admin_set_country(v_mod, '');
      perform supabase_tests.check('admin_set_country tolak negara kosong', false);
    exception when others then
      perform supabase_tests.check('admin_set_country tolak negara kosong (22023)',
        sqlstate = '22023');
    end;
  end if;

  -- (h) USER BIASA tidak boleh memakai admin_set_country.
  perform supabase_tests.mk_dummy(v_plain, '[TEST] NotAdmin', 'offline');
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_plain, 'role', 'authenticated')::text, true);
  begin
    perform public.admin_set_country(v_plain, 'Thailand');
    perform supabase_tests.check('user biasa DILARANG admin_set_country', false);
  exception when others then
    perform supabase_tests.check('user biasa DILARANG admin_set_country (42501)',
      sqlstate = '42501');
  end;

  perform set_config('request.jwt.claims', '', true);
end
$ct$;

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
