-- ============================================
-- ChatYuk: DUMMY KIND (pisahkan expert vs biasa)
-- ============================================
-- menyentuh: admin_list_dummies
-- (fungsi FROZEN — perubahan hanya menambah kolom `kind` di hasil; cabang
--  lain dipertahankan dari snapshot terbaru. Lihat AGENTS.md § SQL.)
-- Latar:
--   Semua akun dummy (biasa + expert) selama ini nyampur di tabel
--   dummy_accounts tanpa penanda tipe eksplisit. "Expert" hanya
--   tersirat dari flag ai_always_reply + ai_persona, dan SET kasus
--   (20260913160000) mendeteksinya via lower(nickname) IN (...) —
--   rapuh: ganti nickname = expert hilang.
--
-- Solusi:
--   Kolom tunggal `kind` ('regular' | 'expert'). Satu sumber
--   kebenaran. Gak ada tabel/FK baru, RLS & RPC tak berubah bentuk.
--
-- Catatan:
--   ai_always_reply = perilaku balas (dipakai expert & CS).
--   kind            = tipe akun. Keduanya independen dan tetap ada.
-- ============================================

alter table public.dummy_accounts
  add column if not exists kind text not null default 'regular'
  check (kind in ('regular', 'expert'));

comment on column public.dummy_accounts.kind is
  'Tipe akun dummy: regular (biasa) | expert (persona teknis, selalu balas).';

-- Backfill: tandai expert dari set lama (idempoten — aman dijalankan ulang).
update public.dummy_accounts
   set kind = 'expert'
 where lower(nickname) in ('softwareexpert', 'hardwareexpert')
   and kind <> 'expert';

-- ── admin_list_dummies: sertakan `kind` ──
-- Ditulis ulang eksplisit (basis terbaru: 20260913190001_dummy_photos_toggle.sql
-- + tambah 'kind') agar tidak bergantung pada urutan OID / string-replace.
drop function if exists public.admin_list_dummies();
create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_rows jsonb[];
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'gender', p.gender,
    'age', p.age,
    'city', p.city,
    'country', p.country,
    'unread', coalesce((
      select sum(coalesce((c.unread_counts ->> d.uid::text)::int, 0))
      from public.private_chats c
      where d.uid = any (c.participants)
    ), 0),
    'kind', coalesce(d.kind, 'regular'),
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_guard_enabled', d.ai_guard_enabled,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true),
    'ai_always_online', coalesce(d.ai_always_online, false),
    'ai_no_rate_limit', coalesce(d.ai_no_rate_limit, false),
    'ai_max_replies', d.ai_max_replies,
    'ai_min_interval', d.ai_min_interval,
    'ai_always_reply', coalesce(d.ai_always_reply, false),
    'ai_wake_until', d.ai_wake_until,
    'ai_photos_enabled', coalesce(d.ai_photos_enabled, true)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$function$;

revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;
