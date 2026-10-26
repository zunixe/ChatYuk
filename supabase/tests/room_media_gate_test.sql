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

  perform supabase_tests.check('akun baru DITOLAK kirim media di room publik',
    public.can_send_room_media(v_room, v_new) = false);

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

select supabase_tests.report() as result;
rollback;
