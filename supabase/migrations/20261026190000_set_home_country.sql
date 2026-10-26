-- NEGARA ASAL user (home_country) — boleh diubah manual, maks 1× / 30 hari.
--
-- `profiles.country` tetap dipakai fitur lokasi (nearby/IP) dan bisa berubah
-- otomatis; `home_country` HANYA berubah lewat RPC ini (anti-VPN/penyalahgunaan
-- izin lintas negara).
--
-- SAFE: fungsi baru; tidak mengubah policy/kolom lain.
create or replace function public.set_home_country(p_country text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me       uuid := auth.uid();
  v_cur    text;
  v_changed timestamptz;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(p_country, '') = '' then
    raise exception 'country_required' using errcode = '22023';
  end if;

  select home_country, home_country_changed_at
    into v_cur, v_changed
    from public.profiles where id = me;

  if v_cur is not null and v_cur = p_country then
    return jsonb_build_object('ok', true, 'unchanged', true);
  end if;

  -- Saat pertama kali diisi (NULL) → bebas; setelah itu maks 1× / 30 hari.
  if v_changed is not null and v_changed > now() - interval '30 days' then
    return jsonb_build_object(
      'ok', false,
      'error', 'cooldown',
      'next_change_at', (v_changed + interval '30 days')
    );
  end if;

  update public.profiles
     set home_country = p_country,
         home_country_changed_at = now()
   where id = me;

  return jsonb_build_object('ok', true, 'home_country', p_country);
end;
$function$;

revoke execute on function public.set_home_country(text) from public, anon;
grant execute on function public.set_home_country(text) to authenticated;
