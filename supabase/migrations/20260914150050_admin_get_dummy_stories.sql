-- menyentuh: (tidak ada fungsi frozen)
-- Admin: list story harian satu dummy (untuk panel admin — ketahui mana
-- yang belum ke-generate). Mengembalikan tanggal N hari terakhir + status
-- terisi/kosong + ringkas isi story.
create or replace function public.admin_get_dummy_stories(
  p_uid text,
  p_days int default 14
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid;
  v_days int := greatest(1, least(coalesce(p_days, 14), 60));
  v_result jsonb;
  v_kind text;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;

  v_uid := p_uid::uuid;

  select coalesce(kind, 'regular') into v_kind
    from public.dummy_accounts where uid = v_uid;
  if v_kind is null then v_kind := 'regular'; end if;

  -- Bangun daftar hari (WIB) terakhir, LEFT JOIN story per hari.
  select coalesce(jsonb_agg(row_json order by d_date desc), '[]'::jsonb)
  into v_result
  from (
    select
      to_char(days.d_date, 'YYYY-MM-DD') as d_date,
      jsonb_build_object(
        'date', to_char(days.d_date, 'YYYY-MM-DD'),
        'has_story', (s.story is not null),
        'story', s.story,
        'created_at', s.created_at
      ) as row_json
    from (
      select ((now() + interval '7 hours')::date - (g.i || ' days')::interval)::date as d_date
      from generate_series(0, v_days - 1) as g(i)
    ) days
    left join public.ai_daily_story s
      on s.dummy_uid = v_uid
     and s.story_date = days.d_date
  ) x;

  return jsonb_build_object(
    'kind', v_kind,
    'story_expected', (v_kind = 'regular'),
    'days', v_result
  );
end;
$fn$;

revoke execute on function public.admin_get_dummy_stories(text, int) from public, anon;
grant execute on function public.admin_get_dummy_stories(text, int) to authenticated, service_role;
