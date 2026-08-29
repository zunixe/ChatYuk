-- Cron: hapus akun tidak aktif 90 hari (anon & registered yang sudah tidak login)
-- Dipanggil harian jam 03:30 via pg_cron; idempotent.

create or replace function public.purge_inactive_accounts()
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  cutoff timestamptz := now() - interval '90 days';
  deleted int := 0;
  r record;
begin
  -- Hanya akun yang last_seen < cutoff dan bukan admin
  -- Admin (service_role) tidak dihapus walau lama tidak login
  for r in
    select id from public.profiles
    where last_seen < cutoff
      and last_seen is not null
      and id not in (select id from public.profiles where is_registered = true and points > 10000) -- jangan hapus admin/high points sembarangan
  loop
    -- Arsip dulu jika ada fungsi archive (opsional)
    begin
      perform public.archive_deleted_user(r.id);
    exception when others then null;
    end;
    -- Hapus relasi sosial
    delete from public.follows where follower_id = r.id or followee_id = r.id;
    delete from public.friend_requests where from_id = r.id or to_id = r.id;
    delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
    delete from public.subscriptions where subscriber_id = r.id or creator_id = r.id;
    -- Hapus private chats yang melibatkan user ini jika sudah tidak ada aktivitas
    delete from public.private_chats where r.id = any(participants);
    -- Hapus pesan room & private (opsional, bisa diarsip)
    delete from public.room_messages where sender_id = r.id;
    delete from public.private_messages where sender_id = r.id;
    -- Hapus presence
    delete from public.room_presence where user_id = r.id;
    -- Akhir: hapus profil
    delete from public.profiles where id = r.id;
    deleted := deleted + 1;
    -- Batasi 100 per run biar tidak lock lama
    exit when deleted >= 100;
  end loop;
  return jsonb_build_object('deleted', deleted, 'cutoff', cutoff);
end; $$;

revoke execute on function public.purge_inactive_accounts() from public, anon;
grant execute on function public.purge_inactive_accounts() to authenticated, service_role;

-- Jadwal harian 03:30
select cron.schedule('purge_inactive_90d', '30 3 * * *', $$select public.purge_inactive_accounts();$$);
