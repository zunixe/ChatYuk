-- ============================================================
-- ChatYuk: Admin — Monitor GRUP (private rooms user)
--
-- "Grup" di app = public.rooms dengan is_private = true (dibuat user,
-- bayar koin). Anggota = room_members. Chat = public.messages (room_id).
-- Room PUBLIC/global TIDAK masuk monitor ini (permintaan admin).
--
-- 4 RPC security-definer (gate email admin):
--   1. admin_list_private_rooms_page(p_limit,p_offset,p_search,p_country)
--   2. admin_room_members(p_room_id)
--   3. admin_room_messages_page(p_room_id,p_limit,p_offset)
--   4. admin_room_message_image(p_message_id)
--
-- Read-only (admin hanya melihat). password_hash TIDAK pernah di-select
-- (column-level grant sudah membuangnya); hanya has_password.
-- ============================================================

-- ── 1. Daftar grup privat (paging + search + filter negara) ──
create or replace function public.admin_list_private_rooms_page(
  p_limit int default 50,
  p_offset int default 0,
  p_search text default '',
  p_country text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
  q text := coalesce(trim(p_search),'');
  ctry text := coalesce(trim(p_country),'');
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (
      select count(*) from public.rooms r
      where r.is_private = true
        and (q = '' or r.name ilike '%'||q||'%' or r.owner_name ilike '%'||q||'%')
        and (ctry = '' or r.country = ctry)
    ),
    'items', coalesce(jsonb_agg(room_obj order by sort_at desc), '[]'::jsonb)
  )
  into result
  from (
    select
      jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'icon', r.icon,
        'owner_id', r.owner_id,
        'owner_name', r.owner_name,
        'country', r.country,
        'category', r.category,
        'has_password', r.has_password,
        'expires_at', r.expires_at,
        'created_at', r.created_at,
        'member_count', (select count(*) from public.room_members m where m.room_id = r.id),
        'message_count', (select count(*) from public.messages msg where msg.room_id = r.id),
        'last_message_at', (select max(msg.created_at) from public.messages msg where msg.room_id = r.id),
        'last_message', (
          select case
            when msg.is_deleted then coalesce(nullif(msg.text,''),'') -- tetap teks; UI tandai terhapus
            when msg.type = 'image' then '[Foto]'
            when msg.type = 'video' then '[Video]'
            when msg.type = 'voice' then '[Voice]'
            when msg.type in ('view_once','view_once_expired') then '[Sekali Lihat]'
            else coalesce(msg.text,'')
          end
          from public.messages msg
          where msg.room_id = r.id
          order by msg.created_at desc
          limit 1
        ),
        'last_message_sender', (
          select msg.sender_name
          from public.messages msg
          where msg.room_id = r.id
          order by msg.created_at desc
          limit 1
        )
      ) as room_obj,
      coalesce(
        (select max(msg.created_at) from public.messages msg where msg.room_id = r.id),
        r.created_at
      ) as sort_at
    from public.rooms r
    where r.is_private = true
      and (q = '' or r.name ilike '%'||q||'%' or r.owner_name ilike '%'||q||'%')
      and (ctry = '' or r.country = ctry)
    order by sort_at desc
    limit p_limit offset p_offset
  ) s;

  return coalesce(result, jsonb_build_object('total',0,'items','[]'::jsonb));
end;
$$;
revoke execute on function public.admin_list_private_rooms_page(int,int,text,text) from public, anon;
grant execute on function public.admin_list_private_rooms_page(int,int,text,text) to authenticated, service_role;

-- ── 2. Anggota satu grup ──
create or replace function public.admin_room_members(p_room_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'nickname', coalesce(p.nickname,'Anon'),
      'avatar', coalesce(p.avatar,''),
      'gender', coalesce(p.gender,'other'),
      'is_registered', coalesce(p.is_registered,false),
      'joined_at', m.joined_at,
      'is_owner', (m.user_id = r.owner_id)
    ) order by m.joined_at asc
  ), '[]'::jsonb)
  into result
  from public.room_members m
  left join public.profiles p on p.id = m.user_id
  left join public.rooms r on r.id = m.room_id
  where m.room_id = p_room_id;

  return result;
end;
$$;
revoke execute on function public.admin_room_members(text) from public, anon;
grant execute on function public.admin_room_members(text) to authenticated, service_role;

-- ── 3. Pesan satu grup (paging, terbaru dulu) ──
create or replace function public.admin_room_messages_page(
  p_room_id text,
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.messages where room_id = p_room_id),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'sender_id', m.sender_id,
        'sender_name', m.sender_name,
        'sender_gender', m.sender_gender,
        -- Foto biasa: image_data dikosongkan (load lazy via
        -- admin_room_message_image). View-once: tetap utuh (admin perlu lihat).
        'image_data', case
          when m.type in ('view_once','view_once_expired') then m.image_data
          else ''
        end,
        'image_path', coalesce(m.image_path,''),
        'voice_path', coalesce(m.voice_path,''),
        'text', m.text,
        'type', m.type,
        'duration_ms', m.duration_ms,
        'is_deleted', m.is_deleted,
        'edited', m.edited,
        'replied_to_id', m.replied_to_id,
        'replied_to_text', m.replied_to_text,
        'replied_to_sender_name', m.replied_to_sender_name,
        'created_at', m.created_at
      ) order by m.created_at desc
    ), '[]'::jsonb)
  )
  into result
  from (
    select * from public.messages
    where room_id = p_room_id
    order by created_at desc
    limit p_limit offset p_offset
  ) m;

  return coalesce(result, jsonb_build_object('total',0,'items','[]'::jsonb));
end;
$$;
revoke execute on function public.admin_room_messages_page(text,int,int) from public, anon;
grant execute on function public.admin_room_messages_page(text,int,int) to authenticated, service_role;

-- ── 4. Ambil image_data satu pesan (lazy-load foto grup) ──
create or replace function public.admin_room_message_image(p_message_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  result text;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select m.image_data into result
  from public.messages m
  where m.id = p_message_id;

  return coalesce(result,'');
end;
$$;
revoke execute on function public.admin_room_message_image(bigint) from public, anon;
grant execute on function public.admin_room_message_image(bigint) to authenticated, service_role;
