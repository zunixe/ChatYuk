-- Cek apakah email sudah terdaftar di Auth (tanpa expose data user lain).
-- Dipanggil dari app sebelum mengirim email reset password.
-- Security definer + revoke dari public agar hanya mengembalikan boolean,
-- bukan data auth.users.
create or replace function public.check_email_registered(p_email text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from auth.users where lower(email) = lower(p_email)
  );
$$;

revoke all on function public.check_email_registered(p_email text) from public;
grant execute on function public.check_email_registered(p_email text) to anon, authenticated;
