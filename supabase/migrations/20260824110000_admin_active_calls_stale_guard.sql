create or replace function public.admin_active_calls()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case
    when coalesce(auth.jwt() ->> 'email', '') <> 'zunixe@gmail.com'
      then '[]'::jsonb
    else coalesce((
      select jsonb_agg(t order by t.created_at desc)
      from (
        select
          c.id::text as id,
          case when c.caller_id::text < c.callee_id::text
            then c.caller_id::text || '_' || c.callee_id::text
            else c.callee_id::text || '_' || c.caller_id::text
          end as chat_id,
          c.caller_id::text as caller_id,
          c.callee_id::text as callee_id,
          coalesce(pc.nickname, 'Unknown') as caller_name,
          coalesce(pd.nickname, 'Unknown') as callee_name,
          c.call_type,
          case when (c.status = 'ringing' and c.created_at <= now() - interval '60 seconds')
            then 'missed' else c.status end as status,
          c.created_at,
          c.answered_at
        from public.calls c
        left join public.profiles pc on pc.id = c.caller_id
        left join public.profiles pd on pd.id = c.callee_id
        where (c.status = 'answered' and c.ended_at is null
               and c.answered_at > now() - interval '120 seconds')
           or (c.status = 'ringing' and c.created_at > now() - interval '60 seconds')
      ) t
    ), '[]'::jsonb)
  end;
$fn$;
