-- KUNCI KEAMANAN RPC UANG & METADATA (audit 2026-10-21, apply 2026-10-22)
--
-- Temuan (diverifikasi via Management API pada DB live):
--   * spend_yukcoin(p_user, ...)  SECURITY DEFINER, EXECUTE utk `authenticated`,
--     TANPA membandingkan p_user dgn auth.uid(). Klien memakainya untuk
--     view-once & foto HD berbayar → siapa pun berakun bisa memanggil RPC dgn
--     uid ORANG LAIN dan menguras saldo YukCoin korban (top-up Google Play =
--     nilai uang nyata).
--   * charge_metered(p_caller, ...) SECURITY DEFINER + `authenticated`, tanpa
--     cek auth.uid(). Satu-satunya pemanggil sah: call_billing_tick (sudah
--     mengisi p_caller := auth.uid()). Tanpa guard, user bisa mendebit user
--     lain langsung.
--   * list_my_groups(p_uid) / list_my_global_rooms(p_uid)  menerima uid
--     sembarang → membocorkan daftar grup/room privat user lain.
--
-- Perbaikan: guard auth.uid() pada 4 RPC (service_role dikecualikan karena
-- auth.uid() NULL di sana). REVOKE sengaja TIDAK dipakai untuk charge_metered:
-- `call_billing_tick` dipanggil dari sesi user saat call berjalan, revoke akan
-- mematikan penagihan call.
--
-- Body fungsi = SALINAN PERSIS definisi live (pg_get_functiondef) + blok guard
-- di awal body. Nama publik yang dipanggil klien tidak berubah; hanya
-- list_my_* dipecah jadi `<nama>_impl` (body asli) + wrapper ber-guard.
--
-- SAFE: hanya `create or replace` isi fungsi + membuat 2 fungsi `_impl`
--       (di-revoke dari semua role klien); tidak menyentuh RLS policy,
--       grant tabel, maupun tabel bersama.

-- ── 1. spend_yukcoin ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.spend_yukcoin(p_user uuid, p_feature text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e int; b int; need int; take int; tier text;
begin
  -- GUARD KEAMANAN (2026-10-22): user hanya boleh mendebit saldo SENDIRI.
  -- service_role (auth.uid() null) tetap bebas untuk job server.
  if auth.uid() is not null and p_user is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh mendebit saldo user lain'
      using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = p_user;

  if (e + b) < p_amount then
    raise exception 'YukCoin tidak cukup';
  end if;

  need := p_amount;

  -- earned dulu
  take := least(e, need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (p_user, 'earned', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
    need := need - take;
  end if;

  -- sisanya dari bonus
  if need > 0 then
    take := least(b, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
  end if;

  tier := case when e >= p_amount then 'earned' else 'mixed' end;

  -- Log pemakaian + event analytics.
  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (p_user, p_feature, p_amount, p_ref, coalesce(p_meta, '{}'::jsonb));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, p_feature, -p_amount,
            jsonb_build_object('feature', p_feature, 'ref', p_ref, 'tier', tier));

  return jsonb_build_object(
    'tier', tier,
    'remaining', public.yukcoin_total(p_user)
  );
end; $function$;


-- ── 2. charge_metered ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.charge_metered(p_caller uuid, p_feature text, p_ref text, p_units integer DEFAULT 1, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cfg jsonb; unit_cost int; cut_pct int;
  total int; cut int; net int; remaining int; balance int;
begin
  -- GUARD KEAMANAN (2026-10-22): user hanya boleh menagih DIRINYA sendiri.
  -- call_billing_tick sudah mengisi p_caller := auth.uid() → tetap jalan.
  if auth.uid() is not null and p_caller is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh menagih user lain'
      using errcode = '42501';
  end if;
  if p_caller is null then raise exception 'Not authenticated'; end if;
  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  select metered_pricing -> p_feature into cfg
    from app_settings where id = 'global';
  if cfg is null then
    raise exception 'Unknown metered feature: %', p_feature;
  end if;
  unit_cost := coalesce((cfg->>'unit_cost')::int, 0);
  cut_pct   := coalesce((cfg->>'cut_pct')::int, 0);

  total := unit_cost * p_units;
  if total <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  balance := public.yukcoin_total(p_caller);
  if balance < total then
    raise exception 'YukCoin tidak cukup';
  end if;

  -- Potong dari saldo penelepon (semua bucket boleh dipakai — ekosistem
  -- coin tertutup: coin dari topup & dari income call sama-sama bisa dipakai).
  remaining := public.ledger_spend(p_caller, p_feature, total, p_ref);

  -- Split ke penerima (mis. pemilik call). Platform ambil cut_pct.
  cut := (total * cut_pct) / 100;
  net := total - cut;
  if p_recipient is not null and p_recipient <> p_caller and net > 0 then
    perform public.ledger_credit(p_recipient, 'earned', p_feature || '_income',
      net, p_ref, jsonb_build_object('from', p_caller, 'feature', p_feature,
      'gross', total, 'cut', cut));
    insert into public.point_events (user_id, event, amount, metadata)
      values (p_recipient, p_feature || '_income', net,
              jsonb_build_object('from', p_caller, 'ref', p_ref));
  end if;

  -- Catat revenue platform (cut).
  if cut > 0 then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (p_feature, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, p_feature, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $function$;


-- ── 3a. body asli dipindah ke `_impl` (didefinisikan DULU agar
--         wrapper plpgsql bisa memvalidasi pemanggilannya).
CREATE OR REPLACE FUNCTION public.list_my_groups_impl(p_uid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
  from (
    select r.*,
           lm.sender_name as last_sender_name,
           lm.text        as last_text,
           lm.type        as last_type,
           lm.created_at  as last_at,
           (select count(*)::int
              from public.messages mm
             where mm.room_id = r.id
               and coalesce(mm.is_deleted, false) = false
               and mm.created_at > coalesce(
                 (select rr.last_read_at from public.room_reads rr
                   where rr.room_id = r.id and rr.user_id = p_uid),
                 to_timestamp(0))) as unread
      from public.rooms r
      left join lateral (
        select m.sender_name, m.text, m.type, m.created_at
          from public.messages m
         where m.room_id = r.id
           and coalesce(m.is_deleted, false) = false
         order by m.created_at desc
         limit 1
      ) lm on true
     where r.is_private = true
       and exists (
         select 1 from public.room_members mb
          where mb.room_id = r.id and mb.user_id = p_uid
       )
  ) t;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_global_rooms_impl(p_uid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.last_at desc nulls last), '[]'::jsonb)
  from (
    select r.id, r.name, r.description, r.icon, r.country, r.category,
           r.is_private, r.owner_id, r.owner_name, r.has_password,
           r.expires_at, r.created_at,
           lm.sender_name as last_sender_name,
           lm.text        as last_text,
           lm.type        as last_type,
           lm.created_at  as last_at,
           (select count(*)::int
              from public.messages mm
             where mm.room_id = r.id
               and coalesce(mm.is_deleted, false) = false
               and mm.created_at > coalesce(
                 (select rr.last_read_at from public.room_reads rr
                   where rr.room_id = r.id and rr.user_id = p_uid),
                 to_timestamp(0))) as unread
      from public.rooms r
      join public.room_reads rd
        on rd.room_id = r.id and rd.user_id = p_uid
      left join lateral (
        select m.sender_name, m.text, m.type, m.created_at
          from public.messages m
         where m.room_id = r.id
           and coalesce(m.is_deleted, false) = false
         order by m.created_at desc
         limit 1
      ) lm on true
     where r.is_private = false
       and (r.expires_at is null or r.expires_at > now())
  ) t;
$function$;


-- ── 3b. wrapper publik ber-guard ─────────────────────────────────
-- ── 3. list_my_* : pindah body asli ke `_impl`, publik memakai wrapper ──
create or replace function public.list_my_groups(p_uid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is not null and p_uid is distinct from auth.uid() then
    raise exception 'Forbidden: hanya boleh melihat grup sendiri'
      using errcode = '42501';
  end if;
  return public.list_my_groups_impl(p_uid);
end;
$function$;

create or replace function public.list_my_global_rooms(p_uid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is not null and p_uid is distinct from auth.uid() then
    raise exception 'Forbidden: hanya boleh melihat room sendiri'
      using errcode = '42501';
  end if;
  return public.list_my_global_rooms_impl(p_uid);
end;
$function$;

-- `_impl` internal: hanya service_role. Wrapper publik di atas satu-satunya
-- jalur untuk klien (dan sudah ber-guard auth.uid()).
revoke execute on function public.list_my_groups_impl(uuid) from public;
revoke execute on function public.list_my_groups_impl(uuid) from anon;
revoke execute on function public.list_my_groups_impl(uuid) from authenticated;
revoke execute on function public.list_my_global_rooms_impl(uuid) from public;
-- SAFE: cabut execute `_impl` dari anon (hardening) — klien memakai wrapper
--       public.list_my_global_rooms yang tetap di-grant; fitur terdampak:
--       daftar room global (tidak ada, karena tetap lewat wrapper).
revoke execute on function public.list_my_global_rooms_impl(uuid) from anon;
revoke execute on function public.list_my_global_rooms_impl(uuid) from authenticated;
grant execute on function public.list_my_groups_impl(uuid) to service_role;
grant execute on function public.list_my_global_rooms_impl(uuid) to service_role;
