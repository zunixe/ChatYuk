-- ADMIN: set / UNSET negara asal (`home_country`).
--
-- Keputusan produk (2026-10-27):
--   * Admin TIDAK butuh baris `country_moderators` — aksesnya sudah lintas
--     negara lewat `is_chatyuk_admin` (can_send_room_media, moderator_console,
--     admin_moderation_overview). Baris moderator untuk admin = redundan.
--   * `home_country = NULL` bagi admin berarti "semua negara".
--   * Unset HANYA mengosongkan `home_country`
--     (+ `home_country_changed_at`); baris `country_moderators` lain yang
--     mungkin ada TIDAK dicabut (keputusan 6a).
--   * RPC ini ADMIN-ONLY (bukan untuk moderator).
--
-- CATATAN KEAMANAN: `can_send_room_media` MELEWATI cek izin lintas negara
-- bila `home_country` kosong. Untuk admin itu tidak berdampak (admin sudah
-- bypass lebih awal), tetapi karena itu RPC ini WAJIB admin-only — user biasa
-- tidak boleh bisa mengosongkan `home_country`-nya sendiri.
--
-- SAFE: 1 fungsi RPC baru (admin-only) + penulisan 2 kolom pada baris milik
--       target. Tidak mengubah policy/RLS, tidak mengubah fungsi lain.
create or replace function public.admin_set_home_country(
  p_uid uuid,
  p_country text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_country text := nullif(btrim(coalesce(p_country, '')), '');
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_uid is null then
    raise exception 'uid_required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_uid) then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  -- Trigger `guard_home_country_trg` hanya mengizinkan perubahan bila
  -- penanda ini aktif (jalur RPC resmi / admin).
  perform set_config('chatyuk.home_country_ok', '1', true);

  update public.profiles
     set home_country = v_country,
         home_country_changed_at = case when v_country is null
                                        then null
                                        else now() end
   where id = p_uid;

  perform set_config('chatyuk.home_country_ok', '', true);

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', coalesce(v_country, ''), me, p_uid,
          case when v_country is null then 'revoke_permit' else 'grant_permit' end,
          case when v_country is null
               then 'admin_home_country_unset'
               else 'admin_home_country_set:' || v_country end);

  return jsonb_build_object(
    'ok', true,
    'uid', p_uid,
    'home_country', v_country
  );
end;
$function$;

revoke execute on function public.admin_set_home_country(uuid, text)
  from public, anon;
grant execute on function public.admin_set_home_country(uuid, text)
  to authenticated;
