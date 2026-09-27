-- ============================================================
-- Admin ringkasan: tampilkan user ter-exclude dgn badge (tidak disembunyikan)
--
-- menyentuh: admin_stats_detail
--
-- Kebijakan baru: user yang ter-exclude (device/uid, mis. device dipakai
-- akun asli seperti "SimpleMe") TETAP tampil di daftar ringkasan admin —
-- diberi flag 'excluded': true supaya UI bisa memberi badge. Sebelumnya
-- mereka DIBUANG total dari users_* sehingga user asli yang online tampak
-- "hilang" dari admin.
--
-- DUMMY tetap DIBUANG (akun fiktif — memang harus tersembunyi dari ringkasan).
--
-- Kartu angka (admin_stats_compute) TIDAK diubah — metrik besar tetap
-- menghitung tanpa excluded supaya tidak melonjak.
--
-- Dasar = definisi LIVE terbaru (pg_get_functiondef). Perubahan: keempat
-- query users_* buang `not (id = any(v_excl))`, tambah field 'excluded'.
-- ============================================================

create or replace function public.admin_stats_detail()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_dummy))), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last)
      from profiles where is_registered = true
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles where is_registered = false
        and not (id = any(v_dummy))), '[]'::jsonb),
    'rooms_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'room_id', t.room_id,
        'room_name', coalesce(r.name, t.room_id),
        'is_private', coalesce(r.is_private, false),
        'user_count', t.c
      ) order by t.c desc)
      from (select room_id, count(*) as c from room_presence group by room_id) t
      left join rooms r on r.id = t.room_id), '[]'::jsonb),
    'messages_today', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'sender_id', sender_id,
          'sender_name', sender_name,
          'sender_gender', sender_gender,
          'text', case when type = 'image' then '[foto]' else text end,
          'type', type,
          'created_at', created_at
        ) as x
        from private_messages
        where created_at >= current_date at time zone 'Asia/Jakarta'
        order by created_at desc
        limit 200
      ) sub), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

-- Verifikasi:
--   select jsonb_array_length((admin_stats_detail())->'users_all');  -- naik (excluded ikut)
--   select count(*) from jsonb_array_elements((admin_stats_detail())->'users_all') e
--     where (e->>'excluded')::bool;                                  -- > 0
