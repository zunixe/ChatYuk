-- ============================================================
-- Fix: fn_archive_deleted_user() gagal (23502) saat user tidak
-- punya baris profil.
--
-- Gejala (log device): `cleanupStaleAnonymous error: null value in
-- column "is_registered" of relation "deleted_users" violates
-- not-null constraint`. Terjadi untuk akun anon yang sudah dihapus
-- (auth.users ada, profiles tidak) — SELECT ... INTO tidak menemukan
-- baris sehingga v_reg tetap NULL, lalu INSERT melanggar NOT NULL
-- (kolom punya default 'false' tapi NULL eksplisit menang).
--
-- Tidak menyentuh fungsi FROZEN (fn_archive_deleted_user bukan anggota
-- scripts/frozen_functions.txt). Definisi diambil PERSIS dari live
-- (pg_get_functiondef) + hanya menambah coalesce pada nilai skalar.
-- ============================================================

create or replace function public.fn_archive_deleted_user(
  p_uid uuid,
  p_reason text,
  p_claimed_by uuid default null,
  p_claimed_nick text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_nick text; v_email text; v_reg boolean; v_ip text;
  v_brand text; v_model text; v_last timestamptz; v_created timestamptz;
begin
  select nickname, email, coalesce(is_registered,false), ip_address,
         last_seen, created_at
    into v_nick, v_email, v_reg, v_ip, v_last, v_created
    from profiles where id = p_uid;

  -- Snapshot device terakhir milik user (sebelum user_devices di-SET NULL).
  select brand, model into v_brand, v_model
    from user_devices
   where user_id = p_uid
   order by last_seen_at desc nulls last
   limit 1;

  insert into public.deleted_users
    (user_id, nickname, email, is_registered, brand, model, ip_address,
     last_seen_at, created_at, deleted_at, reason, claimed_by, claimed_nick)
  values
    (p_uid, coalesce(v_nick,''), v_email, coalesce(v_reg,false),
     coalesce(v_brand,''), coalesce(v_model,''), coalesce(v_ip,''),
     v_last, v_created, now(), p_reason, p_claimed_by, p_claimed_nick)
  on conflict (user_id) do nothing;
end;
$fn$;
