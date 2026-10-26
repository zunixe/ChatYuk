-- MODERATOR BOLEH MENGANGKAT REKAN MODERATOR di NEGARANYA SENDIRI.
--
-- Permintaan user 2026-10-26: "kalau moderator pilih orangnya jadi moderator
-- gimana?" Sebelumnya hanya admin yang bisa mengangkat langsung; moderator
-- hanya bisa menyetujui LAMARAN. Sekarang moderator bisa memilih kandidat
-- dari kontributor negaranya.
--
-- Batasan pengaman:
--   * Hanya untuk negara tempat ia moderator (tidak bisa lintas negara).
--   * Kandidat = kontributor nyata (>=50 pesan di room publik negara itu).
--   * Tidak bisa mengangkat diri sendiri.
--   * Semua tindakan dicatat di `moderator_actions` (bisa dicabut admin).
--
-- SAFE: perluas constraint `source` (nilai baru 'moderator') + 2 fungsi RPC
--       baru. Tidak menyentuh policy/RLS/tabel lain.
alter table public.country_moderators
  drop constraint if exists country_moderators_source_check;
alter table public.country_moderators
  add constraint country_moderators_source_check
  check (source in ('admin', 'application', 'moderator'));

-- ── Kandidat moderator (kontributor negaranya) ─────────────────────────────
create or replace function public.moderator_candidates(p_country text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not (public.is_chatyuk_admin(me)
          or public.is_country_moderator(p_country, me)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'uid', t.uid, 'nickname', t.nickname, 'messages', t.n)
           order by t.n desc)
      from (
        select m.sender_id as uid,
               coalesce(max(pr.nickname), '?') as nickname,
               count(*) as n
          from public.messages m
          join public.rooms r on r.id = m.room_id
          left join public.profiles pr on pr.id = m.sender_id
         where r.is_private = false
           and r.country = p_country
           and m.sender_id <> me
           and not exists (
             select 1 from public.country_moderators cm
              where cm.uid = m.sender_id
                and cm.scope = 'country'
                and cm.scope_value = p_country
                and cm.revoked_at is null
           )
         group by m.sender_id
        having count(*) >= 50
         order by count(*) desc
         limit 30
      ) t
  ), '[]'::jsonb);
end;
$function$;

revoke execute on function public.moderator_candidates(text) from public, anon;
grant execute on function public.moderator_candidates(text) to authenticated;

-- ── Angkat / copot rekan moderator (dalam negaranya sendiri) ───────────────
create or replace function public.moderator_set_colleague(
  p_country text,
  p_uid     uuid,
  p_grant   boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me      uuid := auth.uid();
  v_admin boolean;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  v_admin := public.is_chatyuk_admin(me);
  if not (v_admin or public.is_country_moderator(p_country, me)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_uid = me then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;
  if coalesce(p_country, '') = '' then
    raise exception 'country_required' using errcode = '22023';
  end if;

  if p_grant then
    insert into public.country_moderators
      (scope, scope_value, uid, granted_by, source)
    values ('country', p_country, p_uid, me,
            case when v_admin then 'admin' else 'moderator' end)
    on conflict (scope, scope_value, uid) do update
      set revoked_at = null, granted_by = me, granted_at = now(),
          source = case when v_admin then 'admin' else 'moderator' end;
  else
    update public.country_moderators
       set revoked_at = now()
     where scope = 'country' and scope_value = p_country
       and uid = p_uid and revoked_at is null;
  end if;

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', p_country, me, p_uid,
          case when p_grant then 'grant_permit' else 'revoke_permit' end,
          case when p_grant then 'moderator_appointed' else 'moderator_revoked' end);

  return jsonb_build_object('ok', true, 'granted', p_grant);
end;
$function$;

revoke execute on function public.moderator_set_colleague(text, uuid, boolean) from public, anon;
grant execute on function public.moderator_set_colleague(text, uuid, boolean) to authenticated;
