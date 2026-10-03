-- ============================================================
-- list_room_members_v2: sertakan `gender` (untuk border avatar di sheet
-- anggota room/grup, selaras list Pengguna Online).
--
-- LATAR: sheet anggota room pakai CircleAvatar inisial polos — tak ada foto
--   maupun border gender. Client ingin avatar + border gender (male=biru,
--   female=pink) seperti daftar online. Butuh `gender` dari RPC ini.
--
-- PERUBAHAN: +field 'gender' = pr.gender. Sisa query PERSIS live.
--   Bukan FROZEN. Apply via Management API (1 statement create fn).
-- ============================================================

create or replace function public.list_room_members_v2(p_room_id text)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', m.user_id, 'nickname', coalesce(pr.nickname,'User'),
           'role', m.role, 'joined_at', m.joined_at,
           'broadcast_granted', m.broadcast_granted,
           'status', pr.status, 'last_seen', pr.last_seen,
           'gender', pr.gender
         ) ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
                    pr.nickname), '[]'::jsonb)
    FROM public.room_members m
    LEFT JOIN public.profiles pr ON pr.id = m.user_id
   WHERE m.room_id = p_room_id;
$function$;

-- Verifikasi setelah apply:
--   select public.list_room_members_v2('<room_id>')->0->>'gender';
