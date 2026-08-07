-- Hapus akun anonymous yang sudah tidak aktif (stale) agar
-- username/nickname mereka bebas dipakai lagi dan tidak
-- muncul sebagai "online" ghost di daftar pengguna.
-- Panggil dari app saat start (fire-and-forget).

create or replace function public.cleanup_stale_anonymous(min_age_days int default 7)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted int := 0;
  r record;
begin
  -- Akun anonymous (tanpa email) yang last_seen lebih lama dari threshold.
  -- Anonymous tidak bisa login ulang → aman dihapus.
  for r in
    select u.id
    from auth.users u
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.profiles p
        where p.id = u.id
          and p.last_seen > now() - make_interval(days => min_age_days)
      )
  loop
    -- Hapus data yang melibatkan user ini
    delete from public.room_presence where user_id = r.id;
    delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
    delete from public.reports where reporter_id = r.id or reported_id = r.id;
    delete from public.user_photos where user_id = r.id;

    -- Private chats yang hanya melibatkan user ini (2 pihak, keduanya stale)
    delete from public.private_messages pm
    using public.private_chats pc
    where pm.chat_id = pc.chat_id
      and pc.participants @> array[r.id]::uuid[];

    delete from public.private_chats pc
    where pc.participants @> array[r.id]::uuid[];

    -- Private messages yang dikirim user (chat mungkin sudah dihapus di atas)
    delete from public.private_messages where sender_id = r.id;

    delete from public.profiles where id = r.id;
    delete from auth.users where id = r.id;
    deleted := deleted + 1;
  end loop;
  return deleted;
end;
$$;

revoke execute on function public.cleanup_stale_anonymous(int) from public, anon;
grant execute on function public.cleanup_stale_anonymous(int) to authenticated, service_role;
