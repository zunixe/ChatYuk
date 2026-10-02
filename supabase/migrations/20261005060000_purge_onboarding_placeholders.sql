-- ============================================================
-- PEMBERSIH "PLACEHOLDER ONBOARDING": baris `profiles` yang dibuat trigger
-- `handle_new_user_profile` (nickname "AnonXXXXXXXX") untuk sesi anon yang
-- TIDAK PERNAH dilanjutkan user (belum isi nama, tidak pernah beraktivitas).
--
-- BEDA dari `purge_ghost_users`:
--   - `purge_ghost_users` → `auth.users` anon TANPA baris `profiles`.
--   - fungsi ini         → baris `profiles` placeholder yang PUNYA
--     `auth.users` (dibuat trigger) tapi tak pernah dipakai.
--
-- KRITERIA HAPUS (SEMUA wajib benar — fail-safe, "hanya hapus bila terbukti
-- tak terpakai"):
--   1. nickname cocok 'Anon' + hex (placeholder trigger), DAN
--   2. needs_onboarding = true (belum selesai onboarding), DAN
--   3. is_registered = false (BUKAN akun email nyata), DAN
--   4. BELUM PERNAH AKTIF: last_seen = created_at (tidak ada aktivitas
--      setelah trigger membuatnya — jejak presence/heartbeat tak pernah
--      update), DAN
--   5. tidak ada jejak berharga: tanpa device aktif, tanpa pesan pribadi,
--      tanpa chat, tanpa koin, tanpa poin, tanpa story/post, tanpa follow,
--      tanpa friend_request, DAN
--   6. cukup umur: created_at >= p_min_age_hours (default 24 jam; beri jeda
--      supaya sesi yang sedang berjalan tidak ikut terhapus), DAN
--   7. bukan dummy (dummy_accounts).
--
--   Kondisi (1),(2),(3) WAJIB: melindungi akun email nyata & user anon yang
--   masih berpeluang lanjut. Kondisi (4)+(5) memastikan benar-benar tak ada
--   aktivitas.
--
-- `p_dry_run = true` (default AMAN) mengembalikan daftar TANPA menghapus.
-- Wajib `false` eksplisit untuk benar-benar menghapus. Cron memanggil
-- `false` otomatis (lihat bawah).
--
-- Hapus memakai urutan aman: arsip → hapus FK anak → profiles → auth.users
-- (device & location SEBELUM profiles — FK NOT NULL 23503). Trigger
-- append-only coin_ledger dimatikan sementara (konsisten
-- `cleanup_stale_anonymous`).
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.purge_onboarding_placeholders(
  p_min_age_hours integer default 24,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_ids uuid[];
  v_count int := 0;
  v_uid uuid;
begin
  -- Kandidat: placeholder trigger yang benar-benar tak pernah dipakai.
  select coalesce(array_agg(p.id), '{}')
    into v_ids
    from public.profiles p
   where p.nickname ~ '^Anon[0-9A-F]+$'           -- (1) pola trigger
     and coalesce(p.needs_onboarding, false) = true  -- (2) belum onboarding
     and coalesce(p.is_registered, false) = false     -- (3) bukan akun email
     and p.last_seen = p.created_at                    -- (4) belum pernah aktif
     and p.created_at < now() - make_interval(hours => p_min_age_hours)  -- (6)
     and not exists (select 1 from public.dummy_accounts d where d.uid = p.id) -- (7)
     -- (5) tanpa jejak berharga apa pun:
     and not exists (select 1 from public.user_devices dv where dv.user_id = p.id)
     and not exists (select 1 from public.user_location_history l where l.user_id = p.id)
     and not exists (select 1 from public.private_messages m where m.sender_id = p.id)
     and not exists (select 1 from public.private_chats c where c.participants @> array[p.id]::uuid[])
     and not exists (select 1 from public.coin_ledger k where k.user_id = p.id)
     and not exists (select 1 from public.point_events e where e.user_id = p.id)
     and not exists (select 1 from public.stories s where s.author_id = p.id)
     and not exists (select 1 from public.posts po where po.author_id = p.id)
     and not exists (select 1 from public.follows f where f.follower_id = p.id or f.followee_id = p.id)
     and not exists (select 1 from public.friend_requests fr where fr.from_id = p.id or fr.to_id = p.id)
     and not exists (select 1 from public.user_photos ph where ph.user_id = p.id)
     and not exists (select 1 from public.blocks b where b.blocker_id = p.id or b.blocked_id = p.id)
     and not exists (select 1 from public.reports r where r.reporter_id = p.id or r.reported_id = p.id)
     and not exists (select 1 from public.contact_messages cm where cm.user_id = p.id);

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'count', coalesce(array_length(v_ids, 1), 0),
      'ids', to_jsonb(v_ids)
    );
  end if;

  -- Hapus satu per satu; satu kegagalan tidak menggagalkan sisanya.
  foreach v_uid in array v_ids loop
    begin
      perform public.fn_archive_deleted_user(v_uid, 'onboarding_placeholder');
      delete from public.room_presence where user_id = v_uid;
      delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
      delete from public.reports where reporter_id = v_uid or reported_id = v_uid;
      delete from public.user_photos where user_id = v_uid;
      delete from public.private_messages pm
        using public.private_chats pc
        where pm.chat_id = pc.chat_id and pc.participants @> array[v_uid]::uuid[];
      delete from public.private_chats pc where pc.participants @> array[v_uid]::uuid[];
      delete from public.private_messages where sender_id = v_uid;
      -- Device & location WAJIB dihapus SEBELUM profiles (FK SET NULL tapi
      -- kolom NOT NULL → 23503 bila profiles lebih dulu).
      delete from public.user_devices where user_id = v_uid;
      delete from public.user_location_history where user_id = v_uid;
      delete from public.contact_messages where user_id = v_uid;
      delete from public.profiles where id = v_uid;
      -- Ledger koin & point_events: trigger append-only menolak DELETE.
      alter table public.coin_ledger disable trigger coin_ledger_no_delete;
      delete from public.coin_ledger where user_id = v_uid;
      alter table public.coin_ledger enable trigger coin_ledger_no_delete;
      delete from public.point_events where user_id = v_uid;
      delete from auth.users where id = v_uid;
      v_count := v_count + 1;
    exception when others then
      -- Satu user gagal (mis. data aneh) tidak menggagalkan seluruh run.
      -- Pastikan trigger coin_ledger kembali ENABLE walau error di tengah.
      begin
        alter table public.coin_ledger enable trigger coin_ledger_no_delete;
      exception when others then null;
      end;
    end;
  end loop;

  return jsonb_build_object(
    'dry_run', false,
    'count', v_count,
    'candidates', coalesce(array_length(v_ids, 1), 0)
  );
end;
$fn$;

revoke execute on function public.purge_onboarding_placeholders(integer, boolean)
  from public, anon, authenticated;
grant execute on function public.purge_onboarding_placeholders(integer, boolean)
  to service_role;

-- Cron harian 05:20 — setelah purge_ghost_users (05:10) & cleanup (04:00).
select cron.schedule(
  'purge_onboarding_placeholders',
  '20 5 * * *',
  $$select public.purge_onboarding_placeholders(24, false)$$
);

-- Verifikasi setelah apply:
--   1) DRY RUN dulu (default true → tidak menghapus):
--      select public.purge_onboarding_placeholders(24);   -- count + ids
--   2) Cron terjadwal:
--      select jobid, schedule, command from cron.job
--       where command like '%purge_onboarding_placeholders%';
--   3) ACL: hanya service_role:
--      select has_function_privilege('authenticated',
--        'public.purge_onboarding_placeholders(integer,boolean)', 'EXECUTE'); -- false
