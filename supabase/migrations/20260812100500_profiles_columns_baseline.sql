-- Kolom profiles yang dibuat manual di prod sebelum folder migrations ada.
-- Rekonstruksi dari pemakaian lib/ + migration hardening_rls (grant list).
-- Idempotent — aman dijalankan ulang.
alter table public.profiles add column if not exists avatar text not null default '';
alter table public.profiles add column if not exists login_at timestamptz;
alter table public.profiles add column if not exists last_seen timestamptz;
alter table public.profiles add column if not exists hashtags text not null default '';
alter table public.profiles add column if not exists points int not null default 0;
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists has_password boolean not null default false;
