-- Lapis 3: invariant poin/ekonomi (idempotensi klaim, kolom ledger).
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('one_time_bonus() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='one_time_bonus'));
select supabase_tests.check('send_coins() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='send_coins'));
select supabase_tests.check('send_gift() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='send_gift'));
select supabase_tests.check('room_read_bonus() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='room_read_bonus'));
select supabase_tests.check('points_leaderboard() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='points_leaderboard'));

-- Kolom saldo & ledger.
select supabase_tests.check('profiles.points ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles' and column_name='points'));

-- one_time_bonus idempoten: action_key unik di ledger.
select supabase_tests.check('tabel coin_ledger ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='coin_ledger'));

-- ── FROZEN: ekonomi chat/room (potong poin — salah = koin hilang/berlebih) ──
select supabase_tests.check('deduct_chat_point() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='deduct_chat_point'));
select supabase_tests.check('daily_login_bonus() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='daily_login_bonus'));
select supabase_tests.check('claim_weekly_quest() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='claim_weekly_quest'));
select supabase_tests.check('kolom profiles.bonus/earned_balance ada (cache wallet)',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='bonus_balance')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='earned_balance'));

-- ── SEC-02 (review 2026-10-24): refund_chat_point TIDAK boleh bisa replay ──
-- Dulu: tiap panggilan me-refund baris spend TERAKHIR lagi -> koin tak terbatas.
select supabase_tests.check('refund_chat_point menyimpan penanda refund_of',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'refund_chat_point'
      and pg_get_functiondef(p.oid) like '%refund_of%'
  ));

select supabase_tests.check('refund_chat_point menjaga kill-switch points_enabled',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'refund_chat_point'
      and pg_get_functiondef(p.oid) like '%points_enabled%'
  ));

select supabase_tests.check('refund_chat_point membatasi jendela refund',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'refund_chat_point'
      and pg_get_functiondef(p.oid) like '%10 minutes%'
  ));

-- Perilaku: refund 2x hanya menambah SATU baris spend_refund.
do $t$
declare
  v_uid uuid := gen_random_uuid();
  v_before int;
  v_after int;
begin
  -- Hanya jalankan bila poin aktif (kalau tidak, guard kill-switch menahan).
  if coalesce((select points_enabled from public.app_settings where id='global'), false) is not true then
    perform supabase_tests.check('refund ganda (dilewati: points_enabled=false)', true);
    return;
  end if;
  insert into auth.users(id, email, encrypted_password, email_confirmed_at)
    values (v_uid, 'pgtap_refund_' || v_uid || '@example.com', 'x', now())
    on conflict do nothing;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
    values (v_uid, 'earned', 'spend_chat', -5, 'text', '{}'::jsonb);
  perform public.refund_chat_point('text');
  perform public.refund_chat_point('text');
  perform public.refund_chat_point('text');
  select count(*) into v_after from public.coin_ledger
   where user_id = v_uid and type = 'spend_refund';
  perform supabase_tests.check('refund 3x -> hanya 1 baris spend_refund', v_after = 1);
end
$t$;

select supabase_tests.report() as result;
rollback;
