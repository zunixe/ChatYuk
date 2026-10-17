-- Notifikasi room/grup untuk tab Chat: unread + cuplikan pesan terakhir.
--
-- Kenapa perlu: `list_my_groups` lama TIDAK mengembalikan `unread` maupun
-- `last_*` — jadi layar tidak bisa membedakan grup yang ada pesan baru.
-- `list_room_explore` sudah menghitung unread vs `room_reads` (terbukti
-- benar); pola yang SAMA dipakai di sini supaya konsisten.
--
-- 1) list_my_groups  → + unread + last_sender_name/last_text/last_type/last_at
-- 2) list_my_global_rooms (BARU) → room NON-private yang pernah dibuka user
--    (punya baris room_reads) beserta unread + cuplikan. Room global yang
--    belum pernah dibuka BUKAN notifikasi (masuk kategori "room baru"),
--    jadi sengaja tidak ikut.
--
-- ADITIF: hanya menambah kolom pada RPC yang sudah ada; pemanggil lama
-- (Grup, Group Info) tetap jalan karena membaca field yang sama.

-- ── 1) Grup milikku (+ unread & cuplikan pesan terakhir) ──
create or replace function public.list_my_groups(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
  from (
    select r.*,
           lm.sender_name as last_sender_name,
           lm.text        as last_text,
           lm.type        as last_type,
           lm.created_at  as last_at,
           (select count(*)::int
              from public.messages mm
             where mm.room_id = r.id
               and coalesce(mm.is_deleted, false) = false
               and mm.created_at > coalesce(
                 (select rr.last_read_at from public.room_reads rr
                   where rr.room_id = r.id and rr.user_id = p_uid),
                 to_timestamp(0))) as unread
      from public.rooms r
      left join lateral (
        select m.sender_name, m.text, m.type, m.created_at
          from public.messages m
         where m.room_id = r.id
           and coalesce(m.is_deleted, false) = false
         order by m.created_at desc
         limit 1
      ) lm on true
     where r.is_private = true
       and exists (
         select 1 from public.room_members mb
          where mb.room_id = r.id and mb.user_id = p_uid
       )
  ) t;
$fn$;

revoke execute on function public.list_my_groups(uuid) from public, anon;
grant execute on function public.list_my_groups(uuid) to authenticated;

-- ── 2) Global room yang pernah dibuka user (+ unread & cuplikan) ──
create or replace function public.list_my_global_rooms(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.last_at desc nulls last), '[]'::jsonb)
  from (
    select r.id, r.name, r.description, r.icon, r.country, r.category,
           r.is_private, r.owner_id, r.owner_name, r.has_password,
           r.expires_at, r.created_at,
           lm.sender_name as last_sender_name,
           lm.text        as last_text,
           lm.type        as last_type,
           lm.created_at  as last_at,
           (select count(*)::int
              from public.messages mm
             where mm.room_id = r.id
               and coalesce(mm.is_deleted, false) = false
               and mm.created_at > coalesce(
                 (select rr.last_read_at from public.room_reads rr
                   where rr.room_id = r.id and rr.user_id = p_uid),
                 to_timestamp(0))) as unread
      from public.rooms r
      join public.room_reads rd
        on rd.room_id = r.id and rd.user_id = p_uid
      left join lateral (
        select m.sender_name, m.text, m.type, m.created_at
          from public.messages m
         where m.room_id = r.id
           and coalesce(m.is_deleted, false) = false
         order by m.created_at desc
         limit 1
      ) lm on true
     where r.is_private = false
       and (r.expires_at is null or r.expires_at > now())
  ) t;
$fn$;

revoke execute on function public.list_my_global_rooms(uuid) from public, anon;
grant execute on function public.list_my_global_rooms(uuid) to authenticated;
