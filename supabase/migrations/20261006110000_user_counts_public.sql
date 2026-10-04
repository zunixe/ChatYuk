-- ============================================================
-- ChatYuk — RPC publik: user_counts() → { registered, anon }
--
-- Dipakai header menu "Pengguna Online" untuk menampilkan TOTAL user
-- (registered + anon) di samping jumlah online. Angka AGREGAT saja (tanpa
-- PII) → aman untuk semua user authenticated (bukan admin-only seperti
-- admin_stats yang juga membuka detail & di-cache 5 menit).
--
-- Aturan hitung = SAMA dengan admin_stats_compute agar konsisten:
--   registered = is_registered=true, exclude excluded-uids & dummy
--   anon       = is_registered=false, exclude excluded/dummy & placeholder
--                (needs_onboarding=false)
-- ============================================================
create or replace function public.user_counts()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare
  v_excl uuid[];
  v_dummy uuid[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  return jsonb_build_object(
    'registered', (select count(*) from public.profiles
      where is_registered = true
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'anon', (select count(*) from public.profiles
      where is_registered = false
        and not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false)
  );
end;
$fn$;

revoke execute on function public.user_counts() from public, anon; -- SAFE: agregat user count, butuh login (tanpa PII)
grant execute on function public.user_counts() to authenticated; -- SAFE: RPC baca agregat untuk header menu Online
