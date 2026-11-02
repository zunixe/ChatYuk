-- Orphan ledger yang DIKETAHUI (residu akun terhapus) dibedakan dari
-- pelanggaran BARU: daftar putih di economy_audit_exclusions membuat
-- checker kembali "0 baris = sehat" tanpa menghapus ledger immutable.
-- Ledger TIDAK dihapus — audit trail uang harus bertahan setelah akun hilang.

create table if not exists public.economy_audit_exclusions (
  check_name text not null,
  user_id    uuid not null,
  note       text not null default '',
  created_at timestamptz not null default now(),
  primary key (check_name, user_id)
);
alter table public.economy_audit_exclusions enable row level security;
revoke all on public.economy_audit_exclusions from anon, authenticated; -- SAFE: tabel audit internal baru — tak ada konsumen client; hanya service_role/CI membaca via fungsi SECURITY DEFINER.

-- 3 orphan diketahui (audit 2026-10-31): profil terhapus, auth.users masih
-- ada, semua bucket 'bonus' non-withdrawable, nominal kecil.
insert into public.economy_audit_exclusions (check_name, user_id, note) values
  ('orphan_ledger', '96c59b22-c168-4180-b6e8-b09408b525d8',
   'akun dihapus; bonus daily_login +10 (2026-08-16)'),
  ('orphan_ledger', 'a2810e43-40af-48d4-87ff-d1dfd7d4611b',
   'akun dummy venty@dummy.chatyuk.local; bonus new_chat/spend net +4 (2026-08-15)'),
  ('orphan_ledger', 'a8389420-7b56-4d37-bfa5-26e53fe0c597',
   'akun dihapus; bonus signup +50 (2026-09-19)')
on conflict do nothing;

-- Recreate checker (body live 110015) + filter eksklusi di setiap cabang.
create or replace function public.economy_invariant_check(p_limit integer default 100)
 returns table(check_name text, user_id uuid, expected bigint, actual bigint, detail text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
      and not exists (select 1 from public.economy_audit_exclusions e
                       where e.check_name = 'points_mismatch' and e.user_id = p.id)
    limit p_limit;

  -- 2) saldo hantu: tak ada baris ledger tapi kolom saldo non-nol
  return query
    select 'phantom_balance'::text, p.id, 0::bigint,
           (p.points + p.bonus_balance + p.earned_balance)::bigint,
           'no ledger rows but balance columns non-zero'::text
    from public.profiles p
    where (p.points <> 0 or p.bonus_balance <> 0 or p.earned_balance <> 0)
      and not exists (select 1 from public.coin_ledger l where l.user_id = p.id)
      and not exists (select 1 from public.economy_audit_exclusions e
                       where e.check_name = 'phantom_balance' and e.user_id = p.id)
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
      and not exists (select 1 from public.economy_audit_exclusions e
                       where e.check_name = 'bonus_mismatch' and e.user_id = p.id)
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
      and not exists (select 1 from public.economy_audit_exclusions e
                       where e.check_name = 'earned_mismatch' and e.user_id = p.id)
    limit p_limit;

  -- 5) bucket negatif — debit melebihi kredit di bucket tsb
  return query
    select 'negative_bucket'::text, l.user_id, 0::bigint, sum(l.amount)::bigint,
           ('bucket=' || l.bucket)::text
    from public.coin_ledger l
    where not exists (select 1 from public.economy_audit_exclusions e
                       where e.check_name = 'negative_bucket' and e.user_id = l.user_id)
    group by l.user_id, l.bucket
    having sum(l.amount) < 0
    limit p_limit;

  -- 6) baris ledger untuk user tanpa profil — residu akun terhapus yang
  --    SUDAH dicatat dikecualikan; laporan baru tetap muncul.
  return query
    select 'orphan_ledger'::text, l.user_id, 0::bigint, count(*)::bigint,
           'ledger rows without matching profile'::text
    from public.coin_ledger l
    where not exists (select 1 from public.profiles p where p.id = l.user_id)
      and not exists (select 1 from public.economy_audit_exclusions e
                       where e.check_name = 'orphan_ledger' and e.user_id = l.user_id)
    group by l.user_id
    limit p_limit;
end;
$function$;

comment on function public.economy_invariant_check(int) is
  'Audit read-only ledger↔profile. check_name: points_mismatch | phantom_balance | bonus_mismatch | earned_mismatch | negative_bucket | orphan_ledger. 0 baris = sehat (entri economy_audit_exclusions dilewati).';
comment on table public.economy_audit_exclusions is
  'Daftar putih temuan invariant yang sudah diverifikasi manual — checker melewati (check_name,user_id) yang tercatat. Ledger tidak dihapus.';
