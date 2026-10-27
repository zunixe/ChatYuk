-- REALTIME AKTIVITAS MODERASI (lanjutan 20261027160000_moderator_slots_fcfs)
--
-- 1. Tambah 5 tabel moderasi ke publication `supabase_realtime` supaya
--    - kartu moderasi di Profil user update REALTIME (tampil/hilang) begitu
--      slot moderator berubah (lamaran ditetapkan / moderator resign /
--      dicabut admin), tanpa menunggu buka-tutup Profil;
--    - panel admin menerima aktivitas moderasi REALTIME (permohonan izin,
--      lamaran, laporan, tinjauan, perubahan moderator) — bukan polling
--      180s. Tabel `messages` sudah ada di publication (filter
--      `needs_review=eq.true` di sisi klien).
-- 2. `admin_moderation_activity()` ditambah hitungan + timestamp terakhir
--    LAMARAN MODERATOR pending (sebelumnya hanya permohonan izin media).
-- 3. Policy SELECT admin-only di `reports` supaya klien admin bisa
--    subscribe realtime; user biasa tetap TIDAK bisa membaca laporan
--    (RLS `reports_insert_own` tidak berubah).
--
-- menyentuh: admin_moderation_activity
--
-- SAFE: `create or replace` fungsi milik fitur moderasi + policy SELECT
-- BARU (admin-only, aditif) di tabel `reports` — tidak mengubah/menghapus
-- policy apa pun; fitur terdampak: laporan pesan (report_room_message —
-- tetap bisa INSERT; insert-own policy tetap berlaku).

-- ── 1. Publication realtime (idempoten) ───────────────────────────────────
do $pub$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'country_moderators'
  ) then
    alter publication supabase_realtime add table public.country_moderators; -- SAFE: menambah tabel ke publication realtime; tidak mengubah data/policy.
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'moderator_applications'
  ) then
    alter publication supabase_realtime add table public.moderator_applications; -- SAFE: idem.
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'moderator_actions'
  ) then
    alter publication supabase_realtime add table public.moderator_actions; -- SAFE: idem.
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'country_send_permits'
  ) then
    alter publication supabase_realtime add table public.country_send_permits; -- SAFE: idem.
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'reports'
  ) then
    alter publication supabase_realtime add table public.reports; -- SAFE: idem.
  end if;
end;
$pub$;

-- ── 2. Policy SELECT admin-only di reports (untuk realtime admin) ─────────
do $pol$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'reports'
       and policyname = 'reports_select_admin'
  ) then
    create policy reports_select_admin on public.reports -- SAFE: policy SELECT admin-only ADITIF (user biasa tetap tanpa SELECT; fitur laporan tetap INSERT via reports_insert_own). Terdampak: laporan pesan (report_room_message) & panel admin.
      for select to authenticated
      using (public.is_chatyuk_admin(auth.uid())); -- SAFE: policy SELECT admin-only ADITIF (user biasa tetap tanpa SELECT; fitur laporan tetap INSERT via reports_insert_own).
  end if;
end;
$pol$;

-- ── 3. admin_moderation_activity: + lamaran moderator pending ─────────────
create or replace function public.admin_moderation_activity()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'permits', (select count(*) from public.country_send_permits
                 where status = 'pending'),
    'permits_at', (select max(requested_at) from public.country_send_permits
                    where status = 'pending'),
    'applications', (select count(*) from public.moderator_applications
                      where status = 'pending'),
    'applications_at', (select max(requested_at)
                          from public.moderator_applications
                         where status = 'pending'),
    'reports', (select count(*) from public.reports
                 where status = 'open' and message_id is not null),
    'reports_at', (select max(created_at) from public.reports
                    where status = 'open' and message_id is not null),
    'reviews', (select count(*) from public.messages
                 where needs_review = true
                   and coalesce(is_deleted, false) = false),
    'reviews_at', (select max(created_at) from public.messages
                    where needs_review = true
                      and coalesce(is_deleted, false) = false),
    'mods_at', (select max(created_at) from public.moderator_actions
                 where action in ('grant_permit', 'revoke_permit')),
    'mods_last', (
      select jsonb_build_object(
               'country', ma.scope_value,
               'action', ma.action,
               'note', ma.note,
               'nickname', coalesce(tp.nickname, '?'),
               'created_at', ma.created_at)
        from public.moderator_actions ma
        left join public.profiles tp on tp.id = ma.target_uid
       where ma.action in ('grant_permit', 'revoke_permit')
       order by ma.created_at desc
       limit 1
    )
  );
end;
$function$;

revoke execute on function public.admin_moderation_activity() from public, anon;
grant execute on function public.admin_moderation_activity() to authenticated;
