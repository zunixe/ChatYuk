-- menyentuh: (tidak ada fungsi frozen)
-- Tahap 2 audit performa: friend_request_inbox/outbox tanpa limit →
-- halaman friend request bisa ratusan/ribuan. Tambah varian ber-paginasi
-- p_limit/p_offset; versi lama (tanpa argumen) TIDAK diubah agar kompatibel.
create or replace function public.friend_request_inbox_page(
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  res jsonb; me uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit,50), 200));
  v_offset int := greatest(0, coalesce(p_offset,0));
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.from_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.from_id
    where fr.to_id = me and fr.status = 'pending'
    order by fr.created_at desc
    limit v_limit offset v_offset
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.friend_request_inbox_page(int, int) from public, anon;
grant execute on function public.friend_request_inbox_page(int, int) to authenticated;

create or replace function public.friend_request_outbox_page(
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  res jsonb; me uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit,50), 200));
  v_offset int := greatest(0, coalesce(p_offset,0));
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.to_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.to_id
    where fr.from_id = me
    order by fr.created_at desc
    limit v_limit offset v_offset
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.friend_request_outbox_page(int, int) from public, anon;
grant execute on function public.friend_request_outbox_page(int, int) to authenticated;
