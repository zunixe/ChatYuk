-- Admin (zunixe@gmail.com): jumlah registrasi email per hari di bulan tertentu.
-- Dipakai bar chart "Ringkasan" (admin panel) — filter bulan dari sisi client.
create or replace function public.admin_registrations_daily(p_year int, p_month int)
returns table (day int, count bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'forbidden';
  end if;
  return query
    -- Sumber kebenaran tunggal: profiles.is_registered (sama dengan card
    -- Registered Users di Ringkasan). auth.users tidak dipakai karena
    -- akun dummy punya email palsu (explorer@example.com, *.chatyuk.test).
    select extract(day from p.created_at)::int as d,
           count(*)::bigint as c
      from profiles p
     where p.is_registered = true
       and extract(year from p.created_at) = p_year
       and extract(month from p.created_at) = p_month
     group by 1
     order by 1;
end;
$$;

revoke all on function public.admin_registrations_daily(int, int) from public;
grant execute on function public.admin_registrations_daily(int, int) to authenticated;
