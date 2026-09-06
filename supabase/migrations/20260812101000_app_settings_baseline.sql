-- app_settings: tabel setting global app (dipakai admin provider).
-- Di prod dibuat via dashboard/API sebelum folder migrations ada.
-- Rekonstruksi dari pemakaian di lib/ (admin_provider, points_provider,
-- auth_provider). Idempotent.
create table if not exists public.app_settings (
  id text primary key default 'global',
  excluded_devices jsonb not null default '[]'::jsonb,
  screenshot_enabled boolean not null default true,
  call_all_enabled boolean not null default true,
  invisible_enabled boolean not null default false,
  invisible_admin_uid text not null default '',
  reengage_enabled boolean not null default true,
  require_registration boolean not null default false,
  watermark_enabled boolean not null default true,
  photo_unlock_once boolean not null default false,
  photo_unlock_perm boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (id) values ('global') on conflict (id) do nothing;

alter table public.app_settings enable row level security;

-- RLS: select semua user ter-autentikasi, tulis hanya service_role/admin.
-- (App membaca lewat anon key; update hanya dari panel admin yang
-- memakai service role / edge function.)
drop policy if exists "app_settings_select_all" on public.app_settings;
create policy "app_settings_select_all" on public.app_settings
  for select using (true);

do $$
begin
  alter publication supabase_realtime add table public.app_settings;
exception
  when duplicate_object then null;
end $$;
