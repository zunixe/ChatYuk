-- pgTAP: SLOT MODERATOR MAKS 2 PER NEGARA + SIAPA CEPAT DIA DAPAT + RESIGN
-- (keputusan produk 2026-10-27)
--
-- Mengunci aturan:
--   1. Lamaran memenuhi syarat saat slot terbuka → LANGSUNG jadi moderator
--      ("siapa cepat dia dapat"), bukan menunggu tinjauan.
--   2. Maks 2 moderator aktif per negara — lamaran/angkat rekan/admin ditolak
--      `slots_full` saat penuh.
--   3. `moderator_resign()` mencabut jabatan sendiri → slot terbuka lagi.
--   4. `my_moderation_state()` melaporkan `eligible` + `slot_open`.
--   5. `admin_moderation_activity()` RPC admin ringan tersedia.
--
-- Transaksional (BEGIN/ROLLBACK) — tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- ── Struktur ──────────────────────────────────────────────────────────────
select supabase_tests.check('fungsi slot/resign/aktivitas ada',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('active_moderator_count', 'moderator_resign',
                        'admin_moderation_activity')) = 3);

select supabase_tests.check('index parsial pendukung aktivitas ada',
  (select count(*) from pg_indexes
    where schemaname = 'public'
      and indexname in ('messages_needs_review_idx', 'reports_open_idx',
                        'moderator_actions_grant_idx')) = 3);

-- ── Perilaku slot ─────────────────────────────────────────────────────────
do $t$
declare
  v_a     uuid := 'd0c1e000-0000-4000-8000-0000000000c1';
  v_b     uuid := 'd0c1e000-0000-4000-8000-0000000000c2';
  v_c     uuid := 'd0c1e000-0000-4000-8000-0000000000c3';
  v_admin uuid;
  v_room  text;
  v_ctry  text;
  r       jsonb;
  i       int;
begin
  perform supabase_tests.mk_dummy(v_a, '[TEST] SlotA', 'offline');
  perform supabase_tests.mk_dummy(v_b, '[TEST] SlotB', 'offline');
  perform supabase_tests.mk_dummy(v_c, '[TEST] SlotC', 'offline');

  select id into v_room from public.rooms where is_private = false limit 1;
  if v_room is null then
    perform supabase_tests.check('ada room publik uji', false);
    return;
  end if;
  select country into v_ctry from public.rooms where id = v_room;

  -- Syarat lamaran: umur akun >= 7 hari & >= 50 pesan publik di negaranya.
  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles
     set country = v_ctry, created_at = now() - interval '10 days'
   where id in (v_a, v_b, v_c);
  perform set_config('chatyuk.country_ok', '', true);

  for i in 1..50 loop
    insert into public.messages (room_id, sender_id, sender_name, sender_gender,
                                 text, type)
    values (v_room, v_a, '[TEST] SlotA', 'male', 'isi ' || i, 'text');
    insert into public.messages (room_id, sender_id, sender_name, sender_gender,
                                 text, type)
    values (v_room, v_b, '[TEST] SlotB', 'male', 'isi ' || i, 'text');
  end loop;

  -- (a) Slot 0 → lamaran pertama LANGSUNG ditetapkan.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  r := public.apply_country_moderator(v_ctry);
  perform supabase_tests.check('slot terbuka: lamaran langsung ditetapkan',
    (r->>'ok') = 'true' and (r->>'granted') = 'true');
  perform supabase_tests.check('A benar-benar moderator',
    public.is_country_moderator(v_ctry, v_a));

  -- (b) Slot 1 → lamaran kedua juga langsung (isi batas 2).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  r := public.apply_country_moderator(v_ctry);
  perform supabase_tests.check('slot kedua: langsung ditetapkan',
    (r->>'ok') = 'true' and (r->>'granted') = 'true');

  -- (c) Slot 2 → penuh; user memenuhi syarat pun ditolak slots_full.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  r := public.apply_country_moderator(v_ctry);
  perform supabase_tests.check('slot penuh: ditolak slots_full',
    (r->>'ok') = 'false' and (r->>'error') = 'slots_full');

  -- (d) my_moderation_state: C punya 0 pesan → eligible=false; slot penuh.
  r := public.my_moderation_state();
  perform supabase_tests.check('state C: eligible=false slot_open=false',
    (r->>'eligible') = 'false' and (r->>'slot_open') = 'false');

  -- (d2) B punya 50 pesan (sudah moderator) → eligible=true, slot penuh.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  r := public.my_moderation_state();
  perform supabase_tests.check('state B: eligible=true slot_open=false',
    (r->>'eligible') = 'true' and (r->>'slot_open') = 'false');

  -- (e) my_moderation_state: user baru (0 pesan) → eligible=false.
  r := (select jsonb_build_object('x', 1)); -- placeholder agar blok jelas
  perform supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000c4',
    '[TEST] SlotNew', 'offline');
  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles set country = v_ctry
   where id = 'd0c1e000-0000-4000-8000-0000000000c4';
  perform set_config('chatyuk.country_ok', '', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', 'd0c1e000-0000-4000-8000-0000000000c4',
      'role', 'authenticated')::text, true);
  r := public.my_moderation_state();
  perform supabase_tests.check('state user baru: eligible=false',
    (r->>'eligible') = 'false');

  -- (f) Resign → slot terbuka; pelamar berikutnya langsung dapat.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  r := public.moderator_resign();
  perform supabase_tests.check('resign B: was_moderator=true',
    (r->>'ok') = 'true' and (r->>'was_moderator') = 'true');
  perform supabase_tests.check('B tidak lagi moderator',
    not public.is_country_moderator(v_ctry, v_b));
  perform supabase_tests.check('resign tercatat di moderator_actions',
    exists (select 1 from public.moderator_actions
             where uid = v_b and note = 'moderator_resign'));

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  -- C belum punya 50 pesan → tetap ditolak, tapi ERRORNYA bukan slots_full.
  r := public.apply_country_moderator(v_ctry);
  perform supabase_tests.check('slot terbuka lagi: C kena syarat pesan',
    (r->>'error') = 'not_enough_messages');

  -- Beri C 50 pesan → sekarang dapat slot.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform set_config('chatyuk.country_ok', '1', true);
  for i in 1..50 loop
    insert into public.messages (room_id, sender_id, sender_name, sender_gender,
                                 text, type)
    values (v_room, v_c, '[TEST] SlotC', 'male', 'isi ' || i, 'text');
  end loop;
  perform set_config('chatyuk.country_ok', '', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  r := public.apply_country_moderator(v_ctry);
  perform supabase_tests.check('slot kosong: C langsung dapat',
    (r->>'ok') = 'true' and (r->>'granted') = 'true');

  -- (g) Angkat rekan saat penuh → slots_full.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  r := public.moderator_set_colleague(v_ctry, v_b, true);
  perform supabase_tests.check('angkat rekan saat penuh: slots_full',
    (r->>'ok') = 'false' and (r->>'error') = 'slots_full');

  -- (h) RPC aktivitas admin berbentuk objek dengan kunci dasar.
  --     (is_chatyuk_admin membaca auth.users asli — pakai id admin asli,
  --     read-only; kalau tidak ada, bagian ini dilewati.)
  v_admin := (select id from auth.users
               where lower(email) = 'zunixe@gmail.com' limit 1);
  if v_admin is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    r := public.admin_moderation_activity();
    perform supabase_tests.check('aktivitas moderasi: kunci lengkap',
      r ? 'permits' and r ? 'reports' and r ? 'reviews' and r ? 'mods_last');
  else
    perform supabase_tests.check('aktivitas moderasi (dilewati: admin asli tak ada)', true);
  end if;

  -- (i) Bukan admin → RPC aktivitas menolak.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    perform public.admin_moderation_activity();
    perform supabase_tests.check('aktivitas: bukan admin ditolak', false);
  exception when others then
    perform supabase_tests.check('aktivitas: bukan admin ditolak (42501)',
      sqlstate = '42501');
  end;
end;
$t$;

select supabase_tests.report() as result;
rollback;
