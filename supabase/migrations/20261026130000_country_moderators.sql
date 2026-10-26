-- MODERATOR per NEGARA + negara asal user (stabil, bukan IP)
-- (permintaan user 2026-10-26)
--
-- LATAR:
--   * 363 room publik tersebar di 36 negara → moderator per NEGARA dulu;
--     skema disiapkan naik ke per-ROOM nanti lewat kolom `scope`.
--   * `profiles.country` saat ini DI-TIMPA OTOMATIS dari IP tiap login
--     (login_screen._recordIpToServer) → tidak bisa dipakai sebagai "negara
--     asal" karena VPN/bepergian akan mengubahnya. Ditambah `home_country`
--     yang hanya berubah bila USER sendiri mengubah (maks 1x / 30 hari).
--
-- WEWENANG MODERATOR (least privilege):
--   ✅ sembunyikan/buka pesan · tinjau antrean NSFW · lihat laporan negaranya ·
--      setujui/cabut izin kirim lintas negara · bypass trust gate negaranya
--   ❌ lihat data pribadi (email/IP/lokasi/poin) · blokir/suspend akun ·
--      hapus room · angkat moderator lain
--   Semua tindakan dicatat di `moderator_actions` untuk audit.
--
-- SAFE: semua ADITIF — kolom baru di profiles (nullable), 4 tabel baru,
--       fungsi baru. Tidak mengubah policy/RLS/tabel yang ada.
--       Fitur terdampak: moderasi room publik (baru); profil hanya dapat
--       kolom tambahan.

-- ── 1. Negara asal user (stabil) ───────────────────────────────────────────
alter table public.profiles
  add column if not exists home_country text,
  add column if not exists home_country_changed_at timestamptz;

-- Backfill sekali: pakai country saat ini (NULL bila kosong).
update public.profiles
   set home_country = country
 where home_country is null
   and coalesce(country, '') <> '';

-- ── 2. Moderator per negara ────────────────────────────────────────────────
-- `scope` disiapkan agar nanti bisa 'room' tanpa ubah skema.
create table if not exists public.country_moderators (
  id          bigserial primary key,
  scope       text not null default 'country'
              check (scope in ('country', 'room')),
  scope_value text not null,                 -- nama negara (atau room id)
  uid         uuid not null references auth.users(id) on delete cascade,
  granted_by  uuid,
  granted_at  timestamptz not null default now(),
  revoked_at  timestamptz,
  source      text not null default 'admin'
              check (source in ('admin', 'application')),
  unique (scope, scope_value, uid)
);

create index if not exists country_moderators_uid_idx
  on public.country_moderators (uid) where revoked_at is null;
create index if not exists country_moderators_scope_idx
  on public.country_moderators (scope, scope_value) where revoked_at is null;

-- ── 3. Lamaran moderator ───────────────────────────────────────────────────
create table if not exists public.moderator_applications (
  id           bigserial primary key,
  scope        text not null default 'country'
               check (scope in ('country', 'room')),
  scope_value  text not null,
  uid          uuid not null references auth.users(id) on delete cascade,
  reason       text not null default '',
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'rejected')),
  created_at   timestamptz not null default now(),
  decided_by   uuid,
  decided_at   timestamptz,
  decision_note text
);

-- Satu lamaran pending per (scope, scope_value, uid).
create unique index if not exists moderator_applications_pending_uniq
  on public.moderator_applications (scope, scope_value, uid)
  where status = 'pending';

-- ── 4. Audit tindakan moderator ────────────────────────────────────────────
create table if not exists public.moderator_actions (
  id          bigserial primary key,
  scope       text not null default 'country'
              check (scope in ('country', 'room')),
  scope_value text not null,
  uid         uuid not null references auth.users(id) on delete cascade,
  message_id  text,
  target_uid  uuid,
  action      text not null
              check (action in ('hide', 'unhide', 'approve_media',
                                'reject_media', 'grant_permit',
                                'revoke_permit', 'dismiss_report')),
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists moderator_actions_uid_idx
  on public.moderator_actions (uid, created_at desc);

-- ── 5. Predikat peran ──────────────────────────────────────────────────────
create or replace function public.is_country_moderator(
  p_country text,
  p_uid     uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(p_uid is not null and exists (
    select 1 from public.country_moderators cm
     where cm.uid = p_uid
       and cm.scope = 'country'
       and cm.scope_value = p_country
       and cm.revoked_at is null
  ), false);
$function$;

revoke execute on function public.is_country_moderator(text, uuid) from public, anon;
grant execute on function public.is_country_moderator(text, uuid) to authenticated, service_role;

-- ── 6. RLS tabel baru ──────────────────────────────────────────────────────
alter table public.country_moderators      enable row level security;
alter table public.moderator_applications  enable row level security;
alter table public.moderator_actions       enable row level security;

-- country_moderators: user boleh melihat datanya sendiri; admin melihat semua
-- (lewat is_chatyuk_admin). Penulisan HANYA lewat RPC security definer.
drop policy if exists country_moderators_select on public.country_moderators; -- SAFE: hanya policy baca tabel BARU; tidak menyentuh tabel/fitur lain.
-- SAFE: policy SELECT aditif — hanya baris milik sendiri ATAU admin; tidak
--       membuka data user lain ke publik.
create policy country_moderators_select on public.country_moderators -- SAFE: SELECT baris sendiri / admin pada tabel baru; fitur moderasi saja.
  for select to authenticated
  using (uid = auth.uid() or public.is_chatyuk_admin(auth.uid())); -- SAFE: baca sendiri/admin saja

-- moderator_applications: pelamar melihat lamarannya; admin/moderator negara
-- melihat lamaran di negaranya.
drop policy if exists moderator_applications_select on public.moderator_applications; -- SAFE: hanya policy baca tabel BARU.
-- SAFE: policy SELECT aditif — pelamar sendiri, admin, atau moderator negara
--       tsb (agar bisa meninjau). Tidak membuka data ke user lain.
create policy moderator_applications_select on public.moderator_applications -- SAFE: SELECT pelamar/admin/moderator negara pada tabel baru.
  for select to authenticated
  using (
    uid = auth.uid()
    or public.is_chatyuk_admin(auth.uid())
    or public.is_country_moderator(scope_value, auth.uid())
  ); -- SAFE: baca sendiri/admin/moderator negara

-- moderator_actions: moderator negara & admin bisa melihat audit negaranya.
drop policy if exists moderator_actions_select on public.moderator_actions; -- SAFE: hanya policy baca tabel BARU.
-- SAFE: policy SELECT aditif — audit hanya untuk admin & moderator negara ybs.
create policy moderator_actions_select on public.moderator_actions -- SAFE: SELECT audit oleh admin/moderator negara pada tabel baru.
  for select to authenticated
  using (
    public.is_chatyuk_admin(auth.uid())
    or public.is_country_moderator(scope_value, auth.uid())
  ); -- SAFE: baca audit oleh admin/moderator negara

grant select on public.country_moderators     to authenticated; -- SAFE: baca tabel baru; RLS membatasi ke baris sendiri/admin.
grant select on public.moderator_applications to authenticated; -- SAFE: baca tabel baru; RLS membatasi pelamar/admin/moderator.
grant select on public.moderator_actions      to authenticated; -- SAFE: baca audit tabel baru; RLS membatasi admin/moderator negara.
