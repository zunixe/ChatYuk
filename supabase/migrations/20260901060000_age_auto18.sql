-- Jika age = 0, ubah jadi 18 otomatis (minimal 18 tahun)
create or replace function public.enforce_age_min()
returns trigger language plpgsql as $$
begin
  if NEW.age = 0 or NEW.age is null then
    NEW.age := 18;
  end if;
  return NEW;
end; $$;
drop trigger if exists enforce_age_min_trg on public.profiles;
create trigger enforce_age_min_trg before insert or update on public.profiles for each row execute function public.enforce_age_min();
update public.profiles set age = 18 where age = 0;
