-- ============================================================
-- admin_list_chats_page: sertakan participant_genders.
--
-- ALASAN: monitor chat admin ingin menampilkan avatar peserta ber-ring
--   warna gender (male/female) untuk user tanpa foto — konsisten dengan
--   daftar "Pengguna Online". Tanpa kolom ini, ring gender tak bisa
--   ditentukan di sisi klien.
--
-- Perubahan: tambah 'participant_genders', c.participant_genders pada
--   jsonb_build_object + kolom di subquery. Sisa logika TIDAK diubah.
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.admin_list_chats_page(p_limit integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  v_total bigint;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  -- Estimasi murah untuk total (cukup untuk badge + hasMore admin).
  select greatest(coalesce(reltuples, 0), 0)::bigint into v_total
    from pg_class
   where oid = 'public.private_chats'::regclass;

  select jsonb_build_object(
    'total', coalesce(v_total, 0),
    'admin_uids', coalesce((
      select jsonb_agg(id) from auth.users where email = 'zunixe@gmail.com'
    ), '[]'::jsonb),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'chat_id', c.chat_id,
        'participants', c.participants,
        'participant_names', c.participant_names,
        'participant_genders', c.participant_genders,
        'last_message', c.last_message,
        'last_message_at', c.effective_last,
        'message_count', c.msg_count
      ) order by c.effective_last desc nulls last
    ), '[]'::jsonb)
  ) into result
  from (
    select
      c.chat_id,
      c.participants,
      c.participant_names,
      c.participant_genders,
      c.last_message,
      c.last_message_at,
      coalesce(m.last_noncall, c.last_message_at) as effective_last,
      coalesce(m.msg_count, 0) as msg_count
    from public.private_chats c
    -- SATU agregasi untuk semua pesan (ganti 2× correlated per chat).
    left join (
      select
        m.chat_id as chat_id,
        count(*) as msg_count,
        max(m.created_at) filter (
          where coalesce(m.type, 'text') != 'call'
        ) as last_noncall
      from public.private_messages m
      group by m.chat_id
    ) m on m.chat_id = c.chat_id
    where c.last_message_at is not null
       or m.chat_id is not null
    order by effective_last desc nulls last
    limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) c;

  return result;
end;
$function$;

-- Verifikasi setelah apply:
--   select position('participant_genders' in
--     pg_get_functiondef('public.admin_list_chats_page(integer,integer)'::regprocedure)) > 0;
--     -- true
