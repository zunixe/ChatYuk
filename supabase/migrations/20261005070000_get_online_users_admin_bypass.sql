-- ============================================================
-- Fix: get_online_users tidak menghormati admin privacy bypass.
--
-- GEJALA: di menu "Pengguna Online", admin TIDAK bisa melihat foto user
-- yang menyetel profil privat (mis. Tya) — padahal di private chat &
-- monitor chat admin, foto tsb TERLIHAT (lewat avatar_for).
--
-- AKAR MASALAH: get_online_users (versi 20260926020000_online_list_about)
-- menulis ulang logika privasi SECARA INLINE (photo_ok/seen_ok/presence_ok/
-- about_ok) dan TIDAK memanggil public.privacy_can_view(). Akibatnya flag
-- global `privacy_bypass_enabled` + email admin (yang ditangani DI DALAM
-- privacy_can_view, lihat 20260924230000_admin_privacy_bypass.sql) diabaikan
-- total. Semua RPC lain (avatar_for, presence_for, nearby_users) sudah pakai
-- privacy_can_view → konsisten & bypass jalan. Hanya get_online_users yang
-- menyimpang.
--
-- FIX: ganti semua *_ok inline → public.privacy_can_view(p.id, <field>, v_me)
-- supaya logika privasi + bypass admin SATU sumber kebenaran.
-- Filter presence di WHERE juga pakai privacy_can_view (konsisten dengan
-- output status, agar user yang presence-nya privat tidak bocor ke list,
-- dan admin tetap melihat semua).
--
-- Grants dipertahankan (authenticated + anon + service_role) — signature
-- TIDAK berubah (p_country text, p_limit int).
-- Bukan fungsi FROZEN.
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

create or replace function public.get_online_users(
  p_country text DEFAULT NULL::text,
  p_limit integer DEFAULT 100
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  rows jsonb;
  v_me uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
begin
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'nickname', s.nickname, 'gender', s.gender, 'age', s.age,
    'country', s.country, 'city', s.city,
    'status', case when s.presence_ok then s.status else 'offline' end,
    'avatar', case when s.photo_ok then s.avatar else '' end,
    'is_registered', s.is_registered,
    'last_seen', case when s.seen_ok then s.last_seen else null end,
    'about', case when s.about_ok then s.about else '' end
  ) order by s.last_seen desc), '[]'::jsonb) into rows
  from (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen, p.about,
      public.privacy_can_view(p.id, 'profile_photo', v_me) as photo_ok,
      public.privacy_can_view(p.id, 'last_seen',     v_me) as seen_ok,
      public.privacy_can_view(p.id, 'presence',      v_me) as presence_ok,
      public.privacy_can_view(p.id, 'about',         v_me) as about_ok
    from public.profiles p
    where p.id <> v_me
      and p.status in ('online', 'idle')
      and p.last_seen >= now() - interval '30 minutes'
      and (p_country is null or p.country = p_country)
      -- Filter presence lewat privacy_can_view → konsisten dengan output
      -- 'status' di atas & menghormati bypass admin.
      and public.privacy_can_view(p.id, 'presence', v_me)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_me)
      )
    order by p.last_seen desc
    limit p_limit
  ) s;

  return rows;
end;
$fn$;

revoke execute on function public.get_online_users(text, int) from public, anon;
grant execute on function public.get_online_users(text, int) to anon, authenticated, service_role;
