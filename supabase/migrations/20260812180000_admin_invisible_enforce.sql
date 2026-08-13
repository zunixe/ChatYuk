-- ============================================================
-- ChatYuk: Enforcement Invisible Admin di server (trigger)
-- Selama invisible_enabled=true, status admin dipaksa jadi
-- 'invisible' apapun yang ditulis client (heartbeat, lifecycle,
-- multi-device, race startup). Toggle OFF → online normal.
-- ============================================================

alter table public.app_settings
  add column if not exists invisible_admin_uid text;

create or replace function public.enforce_invisible()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from app_settings s
    where s.id = 'global'
      and s.invisible_enabled = true
      and s.invisible_admin_uid = new.id::text
  ) then
    new.status := 'invisible';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_invisible on public.profiles;
create trigger trg_enforce_invisible
  before insert or update on public.profiles
  for each row execute function public.enforce_invisible();
