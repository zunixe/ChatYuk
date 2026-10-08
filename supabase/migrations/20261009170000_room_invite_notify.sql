-- ============================================================
-- ChatYuk: NOTIFIKASI saat diundang ke grup.
--
-- Kasus: owner/admin memanggil invite_to_room(room_id, uid) → user langsung
-- jadi member TANPA aksi apa pun dari user tsb → ia tak tahu kalau diundang
-- (grup muncul di "Grup saya" tanpa pemberitahuan).
--
-- Fix: kirim push terarah ke uid yang diundang dari DALAM invite_to_room
-- (titik spesifik "owner mengundang"), bukan trigger generik pada
-- room_members — agar tidak salah-notif join-sendiri/approve.
--
-- Body: "<pengundang> mengundangmu ke grup <nama grup>". Data push:
-- type=room_invite, roomId, otherUid (pengundang) — klien bisa buka grup.
--
-- Pola net.http_post + x-app-secret sama seperti notify_mention_room.
-- Fungsi ini SEBELUMNYA milik migrasi 20260905200000 (group_invite_promote);
-- di-replace di sini dengan penambahan notif. Logika inti TIDAK diubah.
-- ============================================================

create or replace function public.invite_to_room(
  p_room_id text,
  p_uid uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  my_role text;
  r record;
  member_count int;
  inviter_name text;
  room_name text;
  v_title text;
  v_body text;
  was_member boolean;
  rec record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_uid is null or p_uid = me then raise exception 'Invalid target'; end if;

  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if not r.is_private then raise exception 'Bukan grup private'; end if;
  if r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;

  my_role := public.fn_room_role(me, p_room_id);
  if my_role not in ('owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  if not exists (select 1 from public.profiles where id = p_uid) then
    raise exception 'User not found';
  end if;

  select count(*) into member_count
    from public.room_members where room_id = p_room_id;
  if member_count >= coalesce(r.max_members, 20)
     and not exists (
       select 1 from public.room_members
       where room_id = p_room_id and user_id = p_uid
     ) then
    raise exception 'Room full';
  end if;

  -- Sudah member sebelumnya? (agar tidak kirim notif dobel saat re-invite).
  was_member := exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_uid
  );

  insert into public.room_members (room_id, user_id, role)
  values (p_room_id, p_uid, 'member')
  on conflict (room_id, user_id) do nothing;

  -- Bersihkan status kicked lama (re-invite = pintu dibuka lagi).
  delete from public.room_join_requests
   where room_id = p_room_id and user_id = p_uid;

  -- ── Push notifikasi ke yang diundang (hanya bila BARU jadi member). ──
  if not was_member then
    begin
      select coalesce(nullif(nickname,''), 'Seseorang') into inviter_name
        from public.profiles where id = me;
      inviter_name := coalesce(inviter_name, 'Seseorang');
      room_name := coalesce(nullif(r.name,''), 'Grup');
      v_title := room_name;
      v_body := inviter_name || ' mengundangmu ke grup ' || room_name;

      -- Utamakan user_devices aktif (multi-device); fallback profiles.fcm_token.
      for rec in
        select d.fcm_token as token
          from public.user_devices d
         where d.user_id = p_uid
           and d.is_active = true
           and coalesce(d.fcm_token,'') <> ''
      loop
        begin
          perform net.http_post(
            url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'x-app-secret', (select app_shared_secret from app_settings where id = 'global')
            ),
            body := jsonb_build_object(
              'token', rec.token,
              'title', v_title,
              'body', v_body,
              'data', jsonb_build_object(
                'type', 'room_invite',
                'toUid', p_uid,
                'roomId', p_room_id,
                'roomName', room_name,
                'otherUid', me,
                'otherName', inviter_name,
                'message', v_body
              )
            )
          );
        exception when others then null;
        end;
      end loop;

      -- Fallback klien lama (tanpa baris user_devices).
      if not exists (
        select 1 from public.user_devices d
         where d.user_id = p_uid and d.is_active = true
           and coalesce(d.fcm_token,'') <> ''
      ) then
        for rec in
          select p.fcm_token as token
            from public.profiles p
           where p.id = p_uid and coalesce(p.fcm_token,'') <> ''
        loop
          begin
            perform net.http_post(
              url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
              headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-app-secret', (select app_shared_secret from app_settings where id = 'global')
              ),
              body := jsonb_build_object(
                'token', rec.token,
                'title', v_title,
                'body', v_body,
                'data', jsonb_build_object(
                  'type', 'room_invite',
                  'toUid', p_uid,
                  'roomId', p_room_id,
                  'roomName', room_name,
                  'otherUid', me,
                  'otherName', inviter_name,
                  'message', v_body
                )
              )
            );
          exception when others then null;
          end;
        end loop;
      end if;
    exception when others then null;
    end;
  end if;

  return jsonb_build_object('ok', true);
end;
$fn$;

revoke execute on function public.invite_to_room(text, uuid) from public, anon;
grant execute on function public.invite_to_room(text, uuid) to authenticated;
