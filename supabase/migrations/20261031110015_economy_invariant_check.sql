-- ============================================================
-- 20261031110015_economy_invariant_check.sql
-- Diagnostik read-only: audit konsistensi coin_ledger ↔ kolom cache
-- di profiles (points, bonus_balance, earned_balance).
--
-- Model data:
--   profiles.points        = sum(amount) semua bucket   (wallet_sync_points)
--   profiles.bonus_balance = sum(amount) bucket='bonus' (trigger incremental)
--   profiles.earned_balance= sum(amount) bucket='earned'(trigger incremental)
--   bucket topup tidak punya kolom cache — ikut di points total.
--
-- Akses: service_role saja (dipakai admin/CI via Management API).
-- Tidak grant ke anon/authenticated — fungsi ini membaca saldo SEMUA user.
-- ============================================================

create or replace function public.economy_invariant_check(p_limit int default 100)
returns table(check_name text, user_id uuid, expected bigint, actual bigint, detail text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_limit is null or p_limit < 1 then p_limit := 100; end if;

  -- 1) profiles.points ≠ sum(ledger) — cache total keliru
  return query
    with sums as (
      select l.user_id, sum(l.amount)::bigint as total
      from public.coin_ledger l group by l.user_id
    )
    select 'points_mismatch'::text, p.id, s.total, p.points::bigint,
           'profiles.points <> sum(coin_ledger.amount)'::text
    from public.profiles p join sums s on s.user_id = p.id
    where p.points <> s.total
    limit p_limit;

  -- 2) saldo hantu: tak ada baris ledger tapi kolom saldo non-nol
  return query
    select 'phantom_balance'::text, p.id, 0::bigint,
           (p.points + p.bonus_balance + p.earned_balance)::bigint,
           'no ledger rows but balance columns non-zero'::text
    from public.profiles p
    where (p.points <> 0 or p.bonus_balance <> 0 or p.earned_balance <> 0)
      and not exists (select 1 from public.coin_ledger l where l.user_id = p.id)
    limit p_limit;

  -- 3) bonus_balance ≠ sum(bucket='bonus')
  return query
    with sums as (
      select l.user_id, sum(l.amount)::bigint as b
      from public.coin_ledger l where l.bucket = 'bonus' group by l.user_id
    )
    select 'bonus_mismatch'::text, p.id, s.b, p.bonus_balance::bigint,
           'profiles.bonus_balance <> sum(bucket=bonus)'::text
    from public.profiles p join sums s on s.user_id = p.id
    where p.bonus_balance <> s.b
    limit p_limit;

  -- 4) earned_balance ≠ sum(bucket='earned')
  return query
    with sums as (
      select l.user_id, sum(l.amount)::bigint as e
      from public.coin_ledger l where l.bucket = 'earned' group by l.user_id
    )
    select 'earned_mismatch'::text, p.id, s.e, p.earned_balance::bigint,
           'profiles.earned_balance <> sum(bucket=earned)'::text
    from public.profiles p join sums s on s.user_id = p.id
    where p.earned_balance <> s.e
    limit p_limit;

  -- 5) bucket negatif — debit melebihi kredit di bucket tsb (mustahil bila
  --    spend helpers benar; tanda ada jalur tulis ledger yang salah).
  return query
    select 'negative_bucket'::text, l.user_id, 0::bigint, sum(l.amount)::bigint,
           ('bucket=' || l.bucket)::text
    from public.coin_ledger l
    group by l.user_id, l.bucket
    having sum(l.amount) < 0
    limit p_limit;

  -- 6) baris ledger untuk user tanpa profil (yatim — biasanya hanya
  --    mungkin lewat write manual; FK cascade seharusnya mencegah).
  return query
    select 'orphan_ledger'::text, l.user_id, 0::bigint, count(*)::bigint,
           'ledger rows without matching profile'::text
    from public.coin_ledger l
    where not exists (select 1 from public.profiles p where p.id = l.user_id)
    group by l.user_id
    limit p_limit;
end;
$$;

-- Akses dibatasi: diagnostic ini mengekspos saldo semua user.
revoke execute on function public.economy_invariant_check(int) from public, anon, authenticated;
grant execute on function public.economy_invariant_check(int) to service_role;

comment on function public.economy_invariant_check(int) is
  'Audit read-only ledger↔profile. check_name: points_mismatch | phantom_balance | bonus_mismatch | earned_mismatch | negative_bucket | orphan_ledger. 0 baris = sehat.';
